# JD-012: Without strict mode, `jac test` skips a test file whose in-project import is missing, and exits 0

- **Version:** jaclang 0.39.0, Ubuntu 26.04, x86-64, both profiles
- **Found:** 2026-11-04, phase 1 / 1.1 S0 (re-test of JI-001; also seen in 0.4)
- **Category / severity:** Developer-experience friction / Minor
- **Capability:** Test runner (`jac test`)
- **Status:** open
- **Related:** JI-001 (AfriCinemas), still holding on 0.39.0; upstream searched 2026-11-04: no matching issue
- **Cost:** 0.25 h; workaround: `scripts/test.sh` exports `JAC_TEST_STRICT=1` (1 line)
- **Canary:** tests/canaries/jd_012_test_runner_skips_missing_local_module.jac

## Behaviour

A test file that imports a module missing from the project itself (`import from mylib.missing { one }`, where `mylib/` exists) is reported as `1 skipped`, and `jac test` exits 0. With `JAC_TEST_STRICT=1` the same run fails (exit 1). The switch is an environment variable only: no CLI flag and no `jac.toml` key.

## Expected

A missing module inside the project is a broken test, not an optional dependency. The release notes document the skip for missing *optional third-party* dependencies and recommend `JAC_TEST_STRICT=1` for CI; nothing says an in-project package is treated the same way.

## Repro

`~/jac-repros/JD-012/`, AfriCinemas' JI-001 recipe: `mylib/real.jac`, and `checks/broken_tests.jac` importing `mylib.missing`. `jac test -d checks`: `1 skipped`, exit 0. `JAC_TEST_STRICT=1 jac test -d checks`: exit 1.

## Analysis

A typo in an import, or a renamed module, makes a whole test file vanish while CI stays green. Unchanged since 0.37.18.

## Workaround

`scripts/test.sh` sets `JAC_TEST_STRICT=1`, and `tests/harness_tests.jac` checks both that the suite runs strict and that strict mode fails such a file.

## Canary

`tests/canaries/jd_012_test_runner_skips_missing_local_module.jac`: the repro without `JAC_TEST_STRICT`; asserts exit 0 and `1 skipped`. Mutation-checked: with `JAC_TEST_STRICT=1` the canary fails.

## Upstream issue draft

(For the owner to review before posting.)

> **`jac test` skips (exit 0) a test file whose import of an in-project module fails**
>
> jac 0.39.0. With `mylib/real.jac` present and `checks/broken_tests.jac` doing `import from mylib.missing { one }`, `jac test -d checks` reports `1 skipped` and exits 0; `JAC_TEST_STRICT=1` makes it an error. The release notes describe the skip for missing optional third-party dependencies. Suggest treating an unresolved module under the project root as an error by default, and adding a `--strict` flag or `[test] strict` key alongside the environment variable.
