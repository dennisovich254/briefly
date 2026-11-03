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

No findings yet.
