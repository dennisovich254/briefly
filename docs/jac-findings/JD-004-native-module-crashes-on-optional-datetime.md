# JD-004: A module Jac compiles native by default crashes or returns wrong values on `datetime | None` plus `timedelta`

- **Version:** jaclang 0.39.0, Ubuntu 26.04, x86-64, both profiles
- **Found:** 2026-11-03, phase 0 / 0.4 test harness
- **Category / severity:** Defect / Major
- **Capability:** Codespace placement (server, client, native inference)
- **Status:** open
- **Related:** none
- **Cost:** 2 h; workaround `[placement] default = "server"` in `jac.toml` (1 setting)
- **Canary:** tests/canaries/jd_004_native_optional_datetime_add.jac

## Behaviour

`core/clock.jac` is ordinary server code: it imports `os` and `datetime` and keeps a module variable `glob _frozen: datetime | None`. Jac decides to compile the whole module **native** (`jac explain placement core/clock.jac`: `[decided native]`, with `os` and `datetime` mapped to Jac's native stdlib). Natively:

- under `jac run`, a script that freezes and then advances the clock **segfaults** (exit 139) before printing anything;
- under `jac test`, `advance` silently gives a **wrong time**, so the clock test fails with only `assertion failed`.

Reduced to the minimum (each part alone works natively: an `int` glob updated in a function, a `datetime | None` glob set and read with a fallback, a non-optional `datetime` glob plus a `timedelta`):

```jac
import from datetime { datetime, timedelta, timezone }

glob _t: datetime | None = None;

def setv(at: datetime) { _t = at; }
def advance(delta: timedelta) { _t = _t + delta; }   # a None guard before this does not help
def value -> datetime | None { return _t; }
```

`setv(...)`, `advance(timedelta(hours=25))`, `print(value())` from another module: segfault. With the module placed on the server, it prints `2026-03-03 10:30:00+00:00` as expected. Compiling the native module also takes about 55 s on the owner's laptop, against about 6 s for the same run on the server.

## Expected

Correct results, or the module staying on the server. `jac guide jac-codespaces` says a whole module goes native only "when its import closure has no native blockers (Python imports, ...)", and its own example marks `import from datetime { datetime }` as a "python import -> server anchor". In 0.39.0, `datetime` and `os` are not anchors: they are mapped to the native stdlib.

## Repro

`~/jac-repros/JD-004/` (`clock.jac` + `main.jac`) and the variants in `~/jac-repros/JD-004/variants/`. The canary builds the reduced module above in a temp project and runs `jac run main.jac`.

## Analysis

Two problems meet: placement silently moves code that the guide says should stay on the server into the native backend, and the native backend miscompiles a `datetime | None` global updated with a `timedelta` (a crash under `jac run`, a wrong value under the test runner's interop path). Any anchor-free module in `core/` could hit the same class of defect without warning.

## Workaround

`[placement] default = "server"` in `jac.toml`: anchor-free modules stay on the server unless a module is pinned native on purpose. `jac explain placement core/clock.jac` then shows `server`, and the clock tests pass. This setting is the switch; the canary keeps testing Jac's default.

## Canary

`tests/canaries/jd_004_native_optional_datetime_add.jac`: runs the reduced module with Jac's default placement and asserts a segfault (exit 139 / -11). Mutation-checked: with `[placement] default = "server"` in the canary's project it fails, reporting exit 0 and the correct time.

## Upstream issue draft

(For the owner to review before posting; search for an existing issue first.)

> **Native placement: module with `glob t: datetime | None` and `t = t + delta` segfaults; `datetime` import does not anchor server as documented**
>
> jac 0.39.0, Linux x86-64. A module importing `datetime` with `glob _t: datetime | None = None;`, `def setv(at: datetime) { _t = at; }`, `def advance(delta: timedelta) { _t = _t + delta; }` is placed whole-module native by default. Calling `setv`, then `advance(timedelta(hours=25))` from another module segfaults under `jac run` (exit 139); under `jac test` the value is silently wrong. Each part alone works. With `[placement] default = "server"` it is correct. Also, `jac-codespaces` says Python imports block native placement and shows `import from datetime` as a server anchor, but `datetime` and `os` are mapped to the native stdlib and do not anchor.
