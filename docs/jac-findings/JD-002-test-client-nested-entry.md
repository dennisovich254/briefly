# JD-002: `JacTestClient` cannot serve an entry that is not at the project root

- **Version:** jaclang 0.39.0, Ubuntu 26.04, both profiles
- **Found:** 2026-11-03, phase 0 / 0.3 scaffold
- **Category / severity:** Defect / Minor
- **Capability:** Test runner (`jac test`)
- **Status:** open
- **Related:** none
- **Cost:** 1 h; the lean entry moved from `hosts/lean/main.jac` to the root `main.jac` (no extra code)
- **Canary:** tests/canaries/jd_002_test_client_nested_entry.jac

## Behaviour

`JacTestClient.from_file("hosts/web/main.jac", ...)` builds the app with `hosts/web/` as the program root. A project-root import in that entry (`import from core.ping { ping }`) then resolves relative to the entry file, and calling the endpoint returns **500**:

```text
{"code": "TARGET_UNAVAILABLE", "message": "Function 'ping' could not be loaded; see the server log"}
... Could not load function ping from ../../core/ping.jac
ModuleNotFoundError: No module named '_jac_app_<hash>.......core'
```

The same entry at the project root (`main.jac`) returns 200. A real server is not affected: `jac run <app>` with `entry-point = "hosts.web.main"` serves the endpoint correctly.

## Expected

The core cheatsheet says no-dot imports "resolve against the **project root** (the nearest `jac.toml` dir) from *anywhere* in the project", and the apps guide allows any project-relative dotted `entry-point`. `jac guide jac-testing` presents `JacTestClient.from_file` as the way to test served endpoints and does not say the entry must be at the root.

## Repro

`~/jac-repros/JD-002/proj/` (the canary builds the same project in a temp directory):

```text
jac.toml            [project] name = "repro"
core/ping.jac       def:pub ping -> str { return "pong"; }
main.jac            import from core.ping { ping }   with entry { _ = ping; }
hosts/web/main.jac  (same as main.jac)
check.jac           JacTestClient.from_file(<entry>, base_path=<temp dir>).post("/function/ping")
```

`jac run check.jac` prints `root=200` and `nested=500`.

## Analysis

`JacTestClient._ensure_initialized` (`jaclang/testing/impl/testing.impl.jac`) passes `base = os.path.dirname(self._jac_file)` to `prepare_application` as the program root, instead of the project root. It also discovers configuration from `base_path` (the test's data directory) when no `config` is given, so the project's `jac.toml` is not found either.

## Workaround

The lean profile's entry lives at the project root (`main.jac`, `entry-point = "main"` in `jac.toml`), so endpoint tests serve it with `JacTestClient`. The desktop entry stays in `hosts/desktop/`; both apps compile the same `core/` endpoints, so the lean entry covers them. No switch: this is a file location, noted in `main.jac` and `jac.toml`.

## Canary

`tests/canaries/jd_002_test_client_nested_entry.jac` runs the repro in a throwaway project (as a `jac run` subprocess, because a test client in the test process can only serve the project under test) and asserts `root=200`, `nested=500`.

## Upstream issue draft

(For the owner to review before posting; search for an existing issue first.)

> **`JacTestClient.from_file` roots the program at the entry file's directory, so nested entries cannot import project-root modules**
>
> jac 0.39.0. In a project with `core/ping.jac` (`def:pub ping`) and an entry at `hosts/web/main.jac` that does `import from core.ping { ping }`, `JacTestClient.from_file("hosts/web/main.jac").post("/function/ping")` returns 500 (`ModuleNotFoundError: No module named '_jac_app_<hash>.......core'`), while the same entry at the root returns 200 and `jac run` serves the nested entry fine. `_ensure_initialized` uses `os.path.dirname(jac_file)` as the program root; using the project root (nearest `jac.toml`) would match `jac run`. Configuration is also discovered from `base_path` rather than the project.
