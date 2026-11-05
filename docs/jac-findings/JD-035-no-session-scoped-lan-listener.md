# JD-035: A Jac app cannot listen on the LAN only while a session is active; the desktop host serves on loopback only

- **Version:** jaclang 0.39.1, Ubuntu 26.04, x86-64, desktop and lean profiles
- **Found:** 2026-11-05, phase 1 / 1.5 S7 (the phone link)
- **Category / severity:** Missing capability / Major
- **Capability:** Several clients of one app
- **Status:** open
- **Related:** architecture §5.6 (the LAN listener exists only during a session); JD-038 (dev mode is on every interface regardless); upstream searched 2026-11-05: no matching issue
- **Cost:** 3 h; workaround: `core/phone/gate.jac` (about 250 lines), switch `BRIEFLY_PHONE_LISTENER`
- **Canary:** bench/jd_035_desktop_serves_loopback_only.sh

## Behaviour

Briefly's phone companion (§5.6) needs the app reachable from the LAN for the length of a meeting and from loopback only otherwise. Jac offers one address per server, chosen at start:

- **A served app** (`jac run --serve`, the lean profile) binds `[serve] host` / `JAC_SERVE_HOST` once, for the server's whole life. Nothing in the serve configuration or the guides opens, moves or closes a listener while the app runs. Its default is `0.0.0.0`, which put Briefly's whole server (`/docs`, `/graph`, `/admin`, registration) on every network the laptop joined until 1.5 set `127.0.0.1`.
- **The desktop host** always serves on `127.0.0.1` (`host_boot.impl.jac` passes `"host": "127.0.0.1"`), and ignores `[serve] host` and `JAC_SERVE_HOST=0.0.0.0`: the desktop profile cannot serve a phone at all.

So neither profile can follow the §5.6 rule through Jac; the lean one could only be on the LAN permanently, with every Jac surface exposed.

## Expected

The desktop guide calls the desktop target "a full-stack Jac app", and its config reference documents `host` as the "Interface to bind". A local-first app with a companion device needs either a configurable desktop host address or, better, a documented way for app code to open and close an extra listener (with its own TLS settings) on the running app, as the server's own `ServingServer.serve_background` does internally for tests.

## Repro

`bench/jd_035_desktop_serves_loopback_only.sh`: starts the built desktop artifact under Xvfb with `JAC_SERVE_HOST=0.0.0.0` and lists its listeners with `ss`: `127.0.0.1:<port>` only. For the served app: `JAC_SERVE_WORKERS=1 jac run --serve --port 8765 main.jac` in any project without `[serve] host` listens on `0.0.0.0:8765` and answers `/docs` 200, `/graph` 200, `/admin` 302 from the network.

## Analysis

The internals have what is needed (`ServingServer(app=…, host=…, settings=…)` with per-listener TLS, and `serve_background()` returning a stop function), but app code cannot reach the running `ServingApp`, and none of it is documented. A session-scoped listener is a common need for a desktop app with a phone or tablet companion, a local pairing flow, or a LAN share.

## Workaround

`core/phone/gate.jac`: for the session only, Briefly opens its own listener on the LAN address (optionally HTTPS with a per-install self-signed certificate) and forwards to the loopback server, one request per upstream connection. It lets through only `GET /phone`, the page's bundle and the two phone endpoints, and answers 404 to everything else (Jac's own surfaces included). Stopping it closes the listener and cuts open streams. Switch `BRIEFLY_PHONE_LISTENER=jac` drops the gate and points the phone at the Jac server's own port, to re-test the Jac way (lean only, with `JAC_SERVE_HOST=0.0.0.0`). `jac.toml` sets `[serve] host = "127.0.0.1"`, checked by `scripts/smoke_lean.sh`.

## Canary

`bench/jd_035_desktop_serves_loopback_only.sh`: exit 0 while the desktop host listens on loopback only despite `JAC_SERVE_HOST=0.0.0.0`.

## Upstream issue draft

(For the owner to review before posting.)

> **Desktop/served apps: no way to open a LAN listener for part of the app's life (and the desktop host ignores `[serve] host`)**
>
> jac 0.39.1. A desktop app with a phone companion needs to be reachable on the LAN only while the user has it on, and on loopback otherwise. The desktop host hard-codes `127.0.0.1` (`host_boot.impl.jac`, ignoring `[serve] host` and `JAC_SERVE_HOST`), and a served app binds one address at start. Internally `ServingServer(app=…, host=…, settings=…).serve_background()` already gives a second listener with its own TLS and a stop function; exposing that (for example `open_listener(host, port, tls=…) -> stop`) on the running app would cover it. Today the only way is an app-written forwarder.
