# JD-018: `atexit` handlers registered by test modules never run in parallel `jac test` workers

- **Version:** jaclang 0.39.0, Ubuntu 26.04, x86-64, both profiles
- **Found:** 2026-11-04, phase 1 / 1.1 S0 (first hit in 0.4: `scripts/check_findings.test.jac` left temporary directories behind)
- **Category / severity:** Developer-experience friction / Minor
- **Capability:** Test runner (`jac test`)
- **Status:** open
- **Related:** the 0.39.0 release note "JacPython ports `atexit`"; upstream searched 2026-11-04: no matching issue
- **Cost:** 0.5 h; workaround: clean up inside each test with `tempfile.TemporaryDirectory()` (done in 0.4)
- **Canary:** tests/canaries/jd_018_atexit_skipped_in_test_workers.jac

## Behaviour

Five test files, each registering an `atexit` handler that writes a marker file:

| Run | Handlers that ran |
|---|---|
| `jac test`, default (parallel workers) | 0 of 5 |
| `JAC_TEST_JOBS=4 jac test` | 0 of 5 |
| `JAC_TEST_JOBS=0 jac test` (serial) | 5 of 5 |
| one file only, default | 1 of 1 |

Whether cleanup runs therefore depends on how many test files the project has and how much memory the machine has (the default worker count is memory-budgeted). `jac run` runs `atexit` handlers normally.

## Expected

Handlers registered by a test module run when the worker that loaded it exits, as they do serially; or the testing guide says they don't and offers a per-module teardown. `jac guide jac-testing` describes the parallel workers but says nothing about `atexit` or teardown.

## Repro

`~/jac-repros/JD-018/`: `tests/atexit_tests.jac` and four copies (`atexit2_tests.jac` … `atexit5_tests.jac`), each writing its own marker from an `atexit` handler.

## Analysis

The workers most likely leave with `os._exit` after reporting, which skips `atexit`. A test suite that cleans up this way leaks files only in parallel runs, which is the default, and only once it has enough files to get more than one worker.

## Workaround

Never rely on `atexit` in tests: each test creates and removes its own data in a `with tempfile.TemporaryDirectory()` block (plan §2.3 rules).

## Canary

`tests/canaries/jd_018_atexit_skipped_in_test_workers.jac`: the five-file project with `JAC_TEST_JOBS=4` and `0`; asserts 0 and 5 handlers ran. Mutation-checked: serial in both runs fails the canary.

## Upstream issue draft

(For the owner to review before posting.)

> **`atexit` handlers registered by test modules don't run in parallel `jac test` workers**
>
> jac 0.39.0. With five test files each doing `atexit.register(mark)` (writing a marker file), `jac test` with parallel workers (default, or `JAC_TEST_JOBS=4`) runs none of the handlers; `JAC_TEST_JOBS=0` runs all five, and a single file runs its one. So cleanup depends on file count and the machine's memory budget. Expected: handlers run when a worker exits, or `jac-testing` documents this and offers a module-level teardown.
