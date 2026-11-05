# ADR 0003: The phone link pairs one device through a session-scoped LAN gate, over HTTPS by default

- **Status:** Proposed (accepted when the owner merges the 1.5 pull request)
- **Date:** 2026-11-05
- **Decides:** architecture §18 A03 (the phone companion as the default private display) and the §5.6 transport rule
- **Evidence:** spike S7, plan 1.5: `tests/phone/link_tests.jac`, `bench/phone_link.jac` on the owner's phone, JD-035 to JD-038

## Context

§5.6 asks for four things: a LAN listener that exists only while a session is active, pairing by QR code with a short-lived one-time code, exactly one paired device per session, and plain HTTP only on the phone's hotspot or a network marked private, HTTPS otherwise. S7 was to find out whether a self-signed certificate is practical on the owner's phone.

What Jac offers and lacks:

| Need | Jac | Result |
|---|---|---|
| Codes and device tokens | the app-token store (`token_create`, `consume`, `peek`, `revoke`) | works: hashed at rest, server-side expiry, single-winner redeem, revocation by session |
| Refusals with real statuses | `respond(status=…)` | works (401, 403, 409) |
| A LAN listener for the session only | none: a served app binds one address at start, the desktop host only loopback (JD-035); dev mode is on every interface regardless (JD-038) | Briefly's own gate |
| HTTPS for the phone only | `[serve.tls]` applies to the whole server, the desktop window included | the gate terminates TLS |

On the owner's phone (Samsung A57, Chrome, home Wi-Fi): the page paired over both plain HTTP and HTTPS, the laptop's messages streamed to it, a second tab with the same link was refused, and ending the session showed "Disconnected" on the phone. Chrome kept the screen on over HTTPS but not over HTTP (browsers give the wake lock only to secure pages). The owner saw no certificate warning over HTTPS, which Chrome normally shows for a self-signed certificate; that is unexplained. The hotspot case was not tested.

Two defects in Briefly surfaced on the phone and were fixed: the lean server listened on `0.0.0.0` (now `127.0.0.1`), and with several workers the phone's requests reached workers that had never seen its session (now one worker). Both are checked by `scripts/smoke_lean.sh`.

## Decision

1. **The phone comes in through a gate** (`core/phone/gate.jac`), opened on the LAN address when a session starts and closed when it ends. It forwards only `GET /phone`, the page's bundle and `phone_pair` / `phone_feed`, and answers 404 to everything else, Jac's own `/docs`, `/graph`, `/admin` and registration included. The switch `BRIEFLY_PHONE_LISTENER=jac` keeps the Jac way re-testable (JD-035).
2. **Pairing** (`core/phone/link.jac`): the laptop's QR code carries the LAN URL with a one-time code after `#` (never sent to a server), valid 120 s. Redeeming it revokes every other code and yields one device token, held only in the page's memory. A second device needs a new code from the laptop, which revokes the first.
3. **HTTPS is the default** (A03: practical), with a per-install self-signed certificate whose SHA-256 fingerprint the laptop shows. It worked on the owner's phone, and only HTTPS keeps the phone's screen on during a meeting. Plain HTTP stays available for the phone's hotspot or a network the user marks private, as §5.6 allows.
4. **The lean server runs one worker**, because the phone session and the open answer streams live in process memory.
5. **The phone link needs the built app or the desktop app**, never `jac run lean` (JD-038).

## Consequences

- The laptop UI's session start and the phone's answer view (one answer at a time, Prepared/Draft/final labels) are built in phase 4 on these endpoints. `phone_push` is the spike's stand-in for real answers.
- The hotspot case and the missing certificate warning are re-checked when the phone view is built in phase 4. If the warning turns out to be awkward, the rule falls back to hotspot or private network only.
- The certificate is made with the `openssl` command, which a clean Ubuntu install may lack. The packaging work (phase 8) either declares it or generates the certificate in-process.
- Every served function's arguments are required until JD-036 is fixed upstream (#10602). A guard test enforces it.
