# JD-014: WebSockets can answer the sender or broadcast to everyone, but cannot send to a chosen connection

- **Version:** jaclang 0.39.0, Ubuntu 26.04, x86-64, both profiles
- **Found:** 2026-11-04, phase 1 / 1.1 S0 (re-test of JI-054)
- **Category / severity:** Missing capability / Minor
- **Capability:** Real-time delivery (host events, WebSockets, streams)
- **Status:** reported (https://github.com/jaseci-labs/jac/issues/10319, by AfriCinemas)
- **Related:** JI-054 (AfriCinemas), still holding on 0.39.0; upstream #10319 (open)
- **Cost:** 0.25 h (re-test); workaround to be chosen in S4 (1.4) or the live-answer work (phase 4)
- **Canary:** none (a feature request: upstream #10319 tracks it; re-check at each upgrade)

## Behaviour

`@restspec(protocol=APIProtocol.WEBSOCKET)` on an `async walker` serves `ws://host/ws/<name>`. A message from a client runs the walker, and its `report`s go back to that client; `broadcast=True` sends each response to every client connected to the endpoint. There is still no third way: sending, on the server's own initiative, to one chosen connection, user or group. The runtime's `WebSocketConnectionManager` has a `send_to(ctx: ConnectionContext, message)`, but it is the fan-out step `broadcast_target` uses internally; application code has no way to look up another user's connection context.

## Expected

A documented way to push to one user's or one device's connections, as Django Channels groups or Socket.IO rooms do. The `jac-sv-deploy` guide documents only sender replies and `broadcast=True`.

## Repro

No code repro: the guide (`jac guide jac-sv-deploy`), the 0.39.0 release notes and the runtime's `jaclang/scale/websocket/` were checked for a targeted API; none exists. Upstream #10319 is open.

## Analysis

For Briefly this matters less than for AfriCinemas: the phone companion is a single paired device per session (architecture §5.6), so one endpoint per session with `broadcast=True` might reach exactly that phone. Whether that holds (endpoints per session, authentication of the socket, what else can connect) is for the real-time spike to decide. Severity Minor for this app; it would be Major for a multi-user one.

## Workaround

Not chosen yet. Candidates: a per-session endpoint with `broadcast=True` and pairing-token authentication; Server-Sent Events from a per-session stream endpoint; polling.

## Canary

None: a missing capability tracked by upstream #10319. Re-checked by hand at each upgrade (§21.5).

## Upstream issue draft

Already reported by AfriCinemas as #10319. No new draft; add Briefly's single-device case as a comment if the owner wants.
