# JD-020: The desktop app's own PostgreSQL stops on a window close, but keeps running after SIGTERM

- **Version:** jaclang 0.39.0, Ubuntu 26.04 (GNOME, Wayland with XWayland), x86-64, desktop profile
- **Found:** 2026-11-04, phase 1 / 1.2 S1b (first seen in 0.3)
- **Category / severity:** Defect / Minor
- **Capability:** Native desktop host and window SDK
- **Status:** open
- **Related:** upstream searched 2026-11-04: no matching issue
- **Cost:** 0.5 h; workaround: none in the app (a cluster left behind is reused by the next launch)
- **Canary:** bench/jd_020_desktop_pg_survives_sigterm.sh

## Behaviour

A desktop build runs its own PostgreSQL cluster under the app's data directory (`~/.local/share/<identifier>/pg/main`, 11 processes, about 102 MB PSS at idle). The cluster is started detached from the host process.

- **Window closed** (a normal close request through the window manager): the host exits and the cluster stops 1.6–6.5 s after the request, in all 22 runs of `bench/mem.jac`.
- **Host sent SIGTERM**, which is what logout, shutdown or `kill` send: the host exits in 0.3 s, its WebKit processes go with it, but the cluster keeps running. It was still running minutes later, until it was stopped by hand with `pg_ctl`.

A crash presumably leaves it behind the same way.

## Expected

The 0.39.0 release notes: desktop apps "run a per-app cluster under the app's own per-user data directory … the cluster stops when the app exits." Exiting on SIGTERM is an exit.

## Repro

`bench/jd_020_desktop_pg_survives_sigterm.sh` launches the built Briefly artifact, sends the host SIGTERM, and checks the cluster 20 s later.

## Analysis

The stop is tied to the window's close path rather than to the process exiting. Ubuntu ends a session by sending SIGTERM, so after every logout or shutdown that happens while the app is open, about 100 MB stays resident until the next launch reuses the cluster or the machine restarts. On a 4 GB laptop that matters.

## Workaround

None in Briefly yet. A later launch finds the running cluster and reuses it; `pg_ctl stop -D <data dir>/pg/main -m fast` stops it by hand.

## Canary

`bench/jd_020_desktop_pg_survives_sigterm.sh`: exit 0 while the cluster survives SIGTERM. The opposite case is covered by `bench/mem.jac`, which closes the window normally and records the cluster stopping each time.

## Upstream issue draft

(For the owner to review before posting.)

> **Desktop app's per-app Postgres keeps running after the app exits on SIGTERM**
>
> jac 0.39.0, Ubuntu 26.04. A `kind = "desktop"` build with the embedded store: closing the window stops the app's cluster within a few seconds, but sending the host process SIGTERM (as logout or shutdown do) exits the host and leaves the cluster running (11 processes, about 100 MB). The release notes say "the cluster stops when the app exits". Suggest stopping the cluster from the host's exit path (SIGTERM/SIGINT handlers and `atexit`), or having the cluster exit when its parent goes away.
