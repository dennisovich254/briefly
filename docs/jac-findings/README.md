# Jac findings

Briefly's second purpose is a reproducible evaluation of how well Jac builds a real desktop app (architecture §21). This folder is where that evaluation is recorded:

| File | What it holds |
|---|---|
| `README.md` | This index: every finding, by severity, with its status |
| `TEMPLATE.md` | The entry template (architecture §21.4) |
| `capability-matrix.md` | A verdict per Jac capability per compiler release (architecture §21.3) |
| `JD-NNN-<slug>.md` | One file per finding |
| `reports/` | Baseline, phase and release reports (architecture §21.7) |

`jac run scripts/check_findings.jac` checks this folder: every entry has its fields, a valid category, severity and status, a capability that is a matrix row, and (while open or reported) a canary file or a stated reason why it has none; every entry is in this index and every index link exists; every matrix verdict is from the list.

## Rules

- **Entry criteria (§21.4).** A finding is logged only when it reproduces on a clean, minimal project on the pinned compiler, is not this project's own mistake, and is a Jac shortcoming. A surprising but intentional language rule is a documentation gap, not a defect.
- **Repros live outside this repository**, in `~/jac-repros/JD-NNN/`. The entry holds the inline commands and minimal files needed to recreate them.
- **IDs** are `JD-NNN`, separate from AfriCinemas' `JI-NNN` series. When a finding shares a root cause with a JI entry, it links to it instead of repeating it.
- **Canaries (§21.5).** Each open, testable finding has a test in `tests/canaries/jd_NNN_*.jac` that asserts the *current* behaviour, so it fails when Jac changes. Findings that cannot be unit-tested name a `bench/` script, or `none (<reason>)`.
- **Upstream reporting.** Search upstream first, draft the issue in the entry, and post only after the owner has reviewed it. Record the link in **Status** and **Related**.

## Index

Sorted by severity (Blocker, Major, Minor, Cosmetic), then by ID.

| ID | Behaviour | Category | Severity | Status | Workaround |
|---|---|---|---|---|---|
| [JD-001](JD-001-jac-bun-is-ignored.md) | `jac install` ignores `JAC_BUN` and always runs the bundled bun (fatal on CPUs without AVX2) | Defect | Major | open | `scripts/swap_bundled_bun.sh` |
| [JD-004](JD-004-native-module-crashes-on-optional-datetime.md) | A module Jac compiles native by default crashes (`jac run`) or returns wrong values (`jac test`) on a `datetime \| None` glob plus `timedelta` | Defect | Major | open | `[placement] default = "server"` |
| [JD-002](JD-002-test-client-nested-entry.md) | `JacTestClient` cannot serve an entry that is not at the project root | Defect | Minor | open | lean entry at the root `main.jac` |
| [JD-003](JD-003-desktop-identifier-gets-another-apps-name.md) | In a workspace, the desktop build appends another app's name to `[desktop] identifier` (and so to its data directory) | Defect | Minor | open | none needed |
| [JD-005](JD-005-check-skips-unreached-files.md) | `jac check` with no paths skips every file no app imports, though `--help` promises an orphan sweep | Defect | Minor | open | `scripts/check_warnings.sh` also checks every tracked file by name |
| [JD-006](JD-006-lint-violations-exit-zero.md) | No Jac command fails on a lint violation it cannot auto-fix (`jac check --lint` exits 0: JI-010; `jac precommit --verify` too) | Defect | Minor | open | `scripts/jac_lint.sh` |
| [JD-007](JD-007-lint-without-paths-lints-nothing.md) | `jac check --lint` with no paths lints 0 files and reports success | Developer-experience friction | Minor | open | `scripts/jac_lint.sh` passes the files |
| [JD-008](JD-008-precommit-install-replaces-framework-hooks.md) | `jac precommit --install` replaces pre-commit framework hooks, which the guide calls a migration | Documentation gap or error | Minor | open | run `jac precommit --verify` from `.pre-commit-config.yaml` |
| [JD-009](JD-009-lint-report-omits-combine-rules.md) | `jac check --lint` never reports `combine-glob`/`combine-has`, which `--fix` applies; the merge moves a trailing comment | Defect | Minor | open | none needed (`jac precommit --verify` enforces them) |
