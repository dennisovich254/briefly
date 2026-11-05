# JD-027: A served Jac app uses about 13 MB (15 %) more idle memory on 0.39.1 than on 0.39.0

- **Version:** jaclang 0.39.1 against 0.39.0, Ubuntu 26.04, x86-64, Celeron N4020 with 3.3 GiB; both profiles
- **Found:** 2026-11-05, the `chore/jac-0.39.1` upgrade sub-phase
- **Category / severity:** Performance/resource / Minor
- **Capability:** Upgrades
- **Status:** open
- **Related:** JD-024 (the desktop budget miss this widens); upstream #10494 ("JacPython is the only Python: drop stock CPython"), the largest runtime change in 0.39.1 and the likely cause, not confirmed; upstream searched 2026-11-05: no matching issue
- **Cost:** 1 h; workaround: none (pin 0.39.0, which the owner decided against)
- **Canary:** none (a measurement: `bench/mem.jac` on each release, and `~/jac-repros/JD-027/measure.sh` comparing two compilers)

## Behaviour

Jac's own `jac create web --kind web-app` scaffold, built with each compiler and served with one worker (`JAC_SERVE_WORKERS=1`), idle for 30 s after one request, measured twice per version:

| Compiler | PSS | USS | RSS |
|---|---|---|---|
| 0.39.0 | 90.0 MB | 89.9 MB | 92.8 MB |
| 0.39.1 | 103.5 MB | 103.4 MB | 106.1 MB |

The two runs per version agree to 0.1 MB. The same shows in Briefly (`bench/mem.jac`, five runs each): the lean server 84.3 → 94.5 MB PSS; the desktop 335.0 → 353.2 MB PSS (host 123 → 135 MB, WebKit 110 → 114 MB, PostgreSQL 102 → 104.5 MB; USS 227 → 237 MB). The desktop artifact grew from 180 to 189 MB compressed and from 260 to 270 MB installed.

## Expected

A patch release keeps memory steady, or its notes say why it grew. The GitHub release for 0.39.1 has no notes beyond the install command.

## Repro

`~/jac-repros/JD-027/`: `measure.sh <jac binary> <label>` builds `web/` (the scaffold), serves the `.jab`, waits 30 s and sums PSS, USS and RSS of the server's processes. Run it with the 0.39.0 and 0.39.1 binaries.

## Analysis

The growth is private memory of the server process itself, so it is the runtime, not shared libraries. 0.39.1's largest runtime change is #10494, which makes JacPython the only Python (stock CPython dropped); that is the likely cause, but the commit range also has native-compilation and prepare changes. For Briefly the cost is real but small: the desktop's idle miss widens from 35 to 53 MB over the 300 MB budget, and the lean estimate with PostgreSQL rises from 178 to about 190 MB against 200 MB.

## Workaround

None. Staying on 0.39.0 would avoid it; the owner chose to take 0.39.1.

## Canary

None: `bench/mem.jac` measures every release, and the release reports compare the numbers.

## Upstream issue draft

(For the owner to review before posting.)

> **0.39.1: a served app's idle memory grew about 13 MB (15 %) over 0.39.0**
>
> Linux x86-64. The `jac create web --kind web-app` scaffold, `jac build`, then `JAC_SERVE_WORKERS=1 jac run web.jab`, idle 30 s after one request: 0.39.0 is 90.0 MB PSS / 89.9 MB USS, 0.39.1 is 103.5 MB / 103.4 MB (stable to 0.1 MB across runs). The growth is private memory of the server process. #10494 (JacPython as the only Python) looks like the likely source. On a 4 GB laptop this matters for desktop apps; could the release notes say what to expect, or is the growth avoidable?
