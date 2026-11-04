# JD-005: In a project with an entry point, `jac check` with no paths skips every file no app imports

- **Version:** jaclang 0.39.0, Ubuntu 26.04, x86-64, both profiles
- **Found:** 2026-11-04, phase 0 / 0.5 pre-commit hooks
- **Category / severity:** Defect / Minor
- **Capability:** Tooling (`jac check`, `jac fmt`, `jac browse`, editor support)
- **Status:** open
- **Related:** none (upstream searched 2026-11-04: no matching issue)
- **Cost:** 0.5 h; workaround: `scripts/check_warnings.sh` also checks every tracked `.jac` file by name (2 lines)
- **Canary:** tests/canaries/jd_005_check_skips_unreached_files.jac

## Behaviour

In a workspace (`[apps.<name>]`), or a plain project that sets `entry-point`, `jac check` with no paths checks only the modules reachable from the entries. A file nothing imports, such as anything in `tests/` or `scripts/`, or a stray file at the project root, is not checked at all: a type error in it passes with exit 0, and the file is not named in the output. `jac check .` does the same. Naming the file or its directory (`jac check tests/`) reports the error.

In Briefly, `jac check` checked 2 of 17 files (`main.jac` and `hosts/desktop/main.jac`, plus what they import). The test suites, canaries, fixtures and `scripts/check_findings.jac` were never type-checked by it.

## Expected

`jac check --help`: "`jac check` — Check every app of the workspace as a whole program, **then the files no app reaches**". The CLI guide's example (`jac guide reference/cli --section jac-check`) says the same: "Check the whole workspace: one program per app, **then the orphan sweep**". The guide's own paragraph on the workspace gate contradicts both: "Unreachable source is checked by naming it explicitly." Either the orphan sweep is missing, or the help and example are wrong. A user who reads the help gets a silent gap.

## Repro

`~/jac-repros/JD-005/workspace/`:

```toml
# jac.toml
[project]
name = "repro"
version = "0.1.0"

[apps.web]
kind = "web-app"
entry-point = "main"
```

```jac
# main.jac
with entry {
    print("hi");
}
```

```jac
# tests/broken.jac
def broken -> int {
    return "not an int";
}
```

`jac check` and `jac check .` print `1 passed`, exit 0. `jac check tests/broken.jac` reports `E1002`, exit 1. `~/jac-repros/JD-005/plain/` shows a plain project without `entry-point` checks every file with `jac check .`, but not with a bare `jac check`.

## Analysis

The bare command is the one a pre-commit hook or CI job would naturally run, and the help promises it covers everything. Tests and tooling scripts are where unreached files collect, so the gap is invisible until a type error reaches run time.

## Workaround

`scripts/check_warnings.sh` (the pre-push ratchet, and the CI `quality` job from 0.6) runs both a bare `jac check` (each app as a whole program) and `jac check <every tracked .jac file>`. `scripts/hooks_selftest.sh` checks that a type error and a warning in an unreached file both fail it.

## Canary

`tests/canaries/jd_005_check_skips_unreached_files.jac`: the repro above with Jac's bare `jac check`; asserts exit 0 with `broken.jac` absent from the output. Mutation-checked: naming the file fails the canary, reporting exit 1 and the `E1002` error.

## Upstream issue draft

(For the owner to review before posting.)

> **`jac check` with no paths skips files no app imports, though `--help` promises an orphan sweep**
>
> jac 0.39.0. In a workspace with `[apps.web] entry-point = "main"`, a file `tests/broken.jac` containing `def broken -> int { return "not an int"; }` is not checked by `jac check` or `jac check .` (exit 0, file not mentioned); `jac check tests/broken.jac` reports E1002. `jac check --help` says the bare command checks "every app of the workspace as a whole program, then the files no app reaches", and the CLI reference example says "then the orphan sweep", but the reference's workspace-gate paragraph says "Unreachable source is checked by naming it explicitly". Expected: the orphan sweep runs, or the help and example stop promising it.
