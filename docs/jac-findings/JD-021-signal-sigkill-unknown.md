# JD-021: The type checker treats `signal.SIGKILL` as Unknown, so `jac check` and `jac run` refuse valid code

- **Version:** jaclang 0.39.0, Ubuntu 26.04, x86-64, both profiles
- **Found:** 2026-11-04, phase 1 / 1.2 S1b (writing `bench/mem.jac`)
- **Category / severity:** Defect / Minor
- **Capability:** Python interoperability
- **Status:** open
- **Related:** upstream searched 2026-11-04: no matching issue
- **Cost:** 0.5 h (first misread as an `except`-block problem); workaround `signal.Signals.SIGKILL` (1 line)
- **Canary:** tests/canaries/jd_021_signal_sigkill_unknown.jac

## Behaviour

```jac
import os;
import signal;

def stop(pid: int) {
    os.kill(pid, signal.SIGKILL);
}
```

`jac check` reports `error[E1053]: Cannot assign <Unknown> to parameter 'signal' of type int`, and `jac run` refuses to run the file. `signal.SIGSTOP` and `signal.SIGHUP` fail the same way. `signal.SIGTERM`, `signal.SIGINT` and `signal.Signals.SIGKILL` are accepted, and at run time all of them are ordinary `Signals` members.

## Expected

The checker knows every POSIX signal constant on Linux, or an unresolved constant is at most a warning. A type error that blocks running correct standard-library code is worse than no check.

## Repro

`~/jac-repros/JD-021/`: `v.jac` calls `os.kill` with six constants; `jac check v.jac` reports E1053 for SIGKILL, SIGSTOP and SIGHUP only.

## Analysis

The checker's view of the `signal` module seems to be missing the constants that only exist on POSIX platforms (SIGKILL, SIGSTOP and SIGHUP have no Windows equivalent; SIGTERM and SIGINT do), perhaps a platform branch of the stub resolved for the wrong platform. Because an Unknown argument is an error, not a warning, the whole file is refused.

## Workaround

`signal.Signals.SIGKILL` (`bench/mem.jac`, `KILL`, citing JD-021).

## Canary

`tests/canaries/jd_021_signal_sigkill_unknown.jac`: checks a two-function file; asserts E1053 on the SIGKILL line and nothing on the SIGTERM line. Mutation-checked: with SIGTERM on both lines the canary fails.

## Upstream issue draft

(For the owner to review before posting.)

> **`signal.SIGKILL` (also SIGSTOP, SIGHUP) is `<Unknown>` to the checker; `os.kill(pid, signal.SIGKILL)` is an E1053 error and `jac run` refuses the file**
>
> jac 0.39.0, Linux. `os.kill(pid, signal.SIGKILL)` gives `error[E1053]: Cannot assign <Unknown> to parameter 'signal' of type int`; `signal.SIGTERM`, `signal.SIGINT` and `signal.Signals.SIGKILL` are fine. Looks like the POSIX-only constants are missing from the checker's `signal` stub on Linux.
