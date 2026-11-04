# JD-017: The embedded Postgres socket lives under the caller's TMPDIR, so a different or long TMPDIR stalls 60 s and fails

- **Version:** jaclang 0.39.0, Ubuntu 26.04, x86-64, both profiles
- **Found:** 2026-11-04, phase 1 / 1.1 S0 (first hit in 0.4, where it made test runs take 228 s and fail)
- **Category / severity:** Defect / Minor
- **Capability:** Graph persistence and walkers
- **Status:** open
- **Related:** upstream #8540 (the same root cause on 0.36.1; closed as not planned 2026-09-04)
- **Cost:** about 1 h in 0.4 (slow, failing test runs first misread as worker contention); workaround: never point `TMPDIR` at a long path (0 lines)
- **Canary:** tests/canaries/jd_017_pg_socket_follows_tmpdir.jac

## Behaviour

The machine-wide embedded Postgres (`~/.cache/jac/pg/main`) listens on a Unix socket under `$TMPDIR/jacpg-<hash>/`, with `$TMPDIR` taken from the *calling* process. A process with a different `TMPDIR` looks for the socket in another place, finds a live pidfile but no socket, and logs:

```
INFO - embedded postgres unreachable despite a live pidfile (mid-shutdown?); taking the locked start path
```

If its `TMPDIR` is long enough that the socket path exceeds the 108-byte `AF_UNIX` limit (here a 116-character `TMPDIR`), it then waits a full minute and fails:

```
✖ Error: postgres not ready after 60.0s: AF_UNIX path too long
```

The first graph access of a plain script took 108 s to fail. Under `jac test`, every `JacTestClient` test stalls the same way.

## Expected

The socket path does not depend on each caller's `TMPDIR` (for example, it lives under the cluster's own directory, or is recorded in the pidfile), and a path that can never work fails at once with the cause. Upstream #8540 proposed both on 0.36.1. 0.39.0 does now name the cause, but only after the 60-second wait.

## Repro

`~/jac-repros/JD-017/`: `main.jac` creates a node under `root`. `jac run main.jac` prints `items: 1`. With `TMPDIR` set to a 116-character directory: 108 s, then the error above.

## Analysis

Easy to hit: tools and sandboxes set `TMPDIR` to per-session directories with long names (the 0.4 runs used one), and a stall looks like slowness or contention rather than a configuration problem. CI uses the default `TMPDIR` and is not affected.

## Workaround

Never set `TMPDIR` to a long path when running Jac. Recorded in this entry and in the plan's 0.4 notes.

## Canary

`tests/canaries/jd_017_pg_socket_follows_tmpdir.jac`: runs the repro with a 120-character `TMPDIR` and asserts a failure naming `AF_UNIX path too long` (about two minutes). Mutation-checked: with `TMPDIR=/tmp` the run succeeds and the canary fails.

## Upstream issue draft

(For the owner to review before posting.)

> **Embedded PG socket still derived from the caller's TMPDIR (#8540): a long TMPDIR stalls 60 s, then `AF_UNIX path too long`**
>
> jac 0.39.0. #8540 (closed as not planned) still reproduces. With a 116-character `TMPDIR`, `jac run` of a script that writes under `root` logs "embedded postgres unreachable despite a live pidfile (mid-shutdown?)", waits 60 s, and fails with `postgres not ready after 60.0s: AF_UNIX path too long` (108 s in all). A different but short `TMPDIR` orphans the running cluster the same way. Suggest a socket directory that does not depend on the caller's `TMPDIR` (under the cluster's data directory, or recorded in the pidfile), and failing at once when the path exceeds the `AF_UNIX` limit.
