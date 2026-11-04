# JD-007: `jac check --lint` with no paths lints 0 files and reports success

- **Version:** jaclang 0.39.0, Ubuntu 26.04, x86-64, both profiles
- **Found:** 2026-11-04, phase 0 / 0.5 pre-commit hooks (first seen in 0.3)
- **Category / severity:** Developer-experience friction / Minor
- **Capability:** Tooling (`jac check`, `jac fmt`, `jac browse`, editor support)
- **Status:** open
- **Related:** JD-005, JD-006; upstream searched 2026-11-04: no matching issue
- **Cost:** 0.25 h; workaround: `scripts/jac_lint.sh` passes the tracked files explicitly (1 line)
- **Canary:** tests/canaries/jd_007_lint_without_paths_lints_nothing.jac

## Behaviour

Inside a project, `jac check --lint` with no paths prints `✔ Linted 0 '.jac' files: 0 errors found.` and exits 0, whatever the project contains. It happens in a plain project and in a workspace. `jac check --lint .` lints every file.

## Expected

The CLI reference says, for `paths`: "Omit inside a project to check the whole workspace". A bare `jac check` does check the apps (JD-005 covers what it skips), so a bare `jac check --lint` should lint at least the same files. Linting nothing should at least not be reported with a success mark.

## Repro

`~/jac-repros/JD-007/`: a `jac.toml` with only `[project]`, and

```jac
# main.jac
def g() -> int {
    return 1;
}

with entry {
    print(g());
}
```

`jac check --lint`: `Linted 0 '.jac' files`, exit 0. `jac check --lint .`: reports `remove-empty-parens` on `main.jac`.

## Analysis

The bare form is the natural thing to put in a hook. Combined with JD-006 (violations never change the exit code), the visible signal is a green check mark. The only clue is the "0 files" count.

## Workaround

`scripts/jac_lint.sh` lints every tracked `.jac` file by name when it is given no arguments. `scripts/hooks_selftest.sh` checks that, with no arguments, it fails on a tracked file with a violation.

## Canary

`tests/canaries/jd_007_lint_without_paths_lints_nothing.jac`: the repro above; asserts exit 0 and `Linted 0 '.jac' files`. Mutation-checked: with `.` as the path, the canary fails and shows the reported violation.

## Upstream issue draft

(For the owner to review before posting.)

> **`jac check --lint` with no paths lints 0 files and prints a success mark**
>
> jac 0.39.0. In a project whose `main.jac` has `def g() -> int`, `jac check --lint` prints "✔ Linted 0 '.jac' files: 0 errors found." and exits 0; `jac check --lint .` reports `remove-empty-parens`. The CLI reference says omitting `paths` inside a project checks the whole workspace, and bare `jac check` does check the apps. Expected: lint the same files, or fail with a message when there is nothing to lint.
