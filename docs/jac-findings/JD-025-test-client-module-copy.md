# JD-025: JacTestClient serves the app from its own copy of every module, so module state set by a test never reaches it

- **Version:** jaclang 0.39.0, Ubuntu 26.04, x86-64, both profiles
- **Found:** 2026-11-04, phase 1 / 1.3 (a frozen clock did not reach an endpoint under test)
- **Category / severity:** Documentation gap or error / Minor
- **Capability:** Test runner (`jac test`)
- **Status:** open
- **Related:** the 0.39.x release note "`JacTestClient` serves the same module a real server does"; JD-002; upstream searched 2026-11-04: no matching issue
- **Cost:** 0.5 h; workaround: `core/clock.jac` keeps its frozen time in the environment (`BRIEFLY_CLOCK_FROZEN_AT`), which every module copy shares
- **Canary:** tests/canaries/jd_025_test_client_module_copy.jac

## Behaviour

A test imports `core.flag`, sets a module variable through it, and calls an endpoint of the same module through `JacTestClient.from_file("main.jac")`. The endpoint returns the variable's initial value. `sys.modules` shows two copies of the module: `core.flag` (the test's import) and `_jac_app_4e43437c6227abf6.core.flag` (the app the client serves). So any module-level state a test sets, such as a frozen clock, a fake, or a feature switch, is invisible to the served endpoints, while a direct call of the same function in the test sees it.

## Expected

The `jac-testing` guide's JacTestClient section to say that the client loads the app as a separate copy of its modules, and how a test should influence the served app's state (environment variables, an endpoint, or access to the served copy). The release note that `JacTestClient` "serves the module the application initialized" reads as a fix for double loading, not as a warning that the test's own imports are a different copy.

## Repro

`~/jac-repros/JD-025/`: `core/flag.jac` (a module variable, a setter and a `def:pub read_value`), `main.jac` importing it, and `tests/flag_tests.jac` that sets the value and reads it through the client: the client returns `unset`.

## Analysis

Serving the app's own copy is what a real server does, so the behaviour is defensible; what is missing is the documentation, and a supported way to share test setup with the served app. A test author's natural move (patching a module the endpoint uses) silently does nothing.

## Workaround

`core/clock.jac`'s `freeze`, `advance` and `reset` keep the frozen time in `BRIEFLY_CLOCK_FROZEN_AT`; `now()` reads it only while `BRIEFLY_CLOCK_CONTROL=1`. The environment is process-wide, so every module copy sees the same clock. `tests/app_opens_tests.jac` checks a frozen time reaching an endpoint.

## Canary

`tests/canaries/jd_025_test_client_module_copy.jac`: builds the repro and asserts the served app still sees the initial value. Mutation-checked: inverting the expectation makes it fail.

## Upstream issue draft

(For the owner to review before posting.)

> **jac-testing: document that JacTestClient serves its own copy of the app's modules (test-side module state doesn't reach endpoints)**
>
> jac 0.39.0. A test that sets a module variable through `import from core.flag { set_value }` and then calls `def:pub read_value` (same module) through `JacTestClient.from_file("main.jac")` gets the variable's initial value; `sys.modules` has both `core.flag` and `_jac_app_<hash>.core.flag`. Suggest documenting this in the JacTestClient section, with the supported way to share setup (for example environment variables, or a handle to the served module).
