# JD-009: `jac check --lint` never reports `combine-glob` or `combine-has`, which `--fix` applies; the merge moves a comment

- **Version:** jaclang 0.39.0, Ubuntu 26.04, x86-64, both profiles
- **Found:** 2026-11-04, phase 0 / 0.5 pre-commit hooks
- **Category / severity:** Defect / Minor
- **Capability:** Tooling (`jac check`, `jac fmt`, `jac browse`, editor support)
- **Status:** open
- **Related:** JD-006; upstream #8769 (another `--lintfix` rewrite that changes meaning); upstream searched 2026-11-04: no matching issue
- **Cost:** 0.5 h; workaround: none needed beyond the `jac-precommit` hook, which applies Jac's check; one comment moved back by hand
- **Canary:** tests/canaries/jd_009_lint_report_omits_combine_rules.jac

## Behaviour

Two consecutive `glob` (or `has`) declarations:

- `jac check --lint` reports nothing, even with `[check.lint] select = ["combine-glob", "combine-has"]` or `select = ["all"]`;
- `jac check --lint --fix`, `jac fmt --lintfix` and `jac precommit` merge them into one statement, and `jac precommit --verify` fails until they are merged, printing `⚠ … Consecutive 'glob' declarations can be combined [combine-glob]`.

So the report-only command, the one that tells you what to fix, is the only one that does not show these two rules. In Briefly, `jac check --lint` passed 17 files while `jac precommit --verify` failed 8 of them.

The merge also moves a trailing comment: `glob A: int = 1;  # about A` followed by `glob B: int = 2;` becomes

```jac
glob A: int = 1,
     B: int = 2;  # about A
```

so the comment describes the wrong value. In Briefly it moved `# 2026-01-05T09:00:00Z` from `START_EPOCH` to `PAIR` in `tests/support/git_fixtures.jac`. Once placed back by hand, `jac fmt` and `--lintfix` leave it there.

## Expected

The `[check.lint]` reference (`jac guide reference/config --section checklint`) lists both rules in the `default` group and says the configuration selects "which auto-lint rules are active during `jac check --lint` and `jac check --lint --fix`": the same rules in both modes. A comment stays with the declaration it was written on.

## Repro

`~/jac-repros/JD-009/`: `globs.jac` (`glob A: int = 1;` `glob B: int = 2;` and an `obj` with two `has` lines), `comment.jac` (the comment case), and `sel/` with the explicit `select` configurations.

## Analysis

Fix mode and report mode disagree on which rules are active, so a developer who lints first and commits second is surprised by the commit gate. The comment move is the second `--lintfix` rewrite found to change what code says (after upstream #8769); here only a comment, but it supports reviewing every `--lintfix` diff (AGENTS.md).

## Workaround

None needed in code: the `jac-precommit` hook (`jac precommit --verify`) enforces the rules, and `jac precommit <files>` applies them. Review the diff for moved comments.

## Canary

`tests/canaries/jd_009_lint_report_omits_combine_rules.jac`: asserts that `jac check --lint` does not report `combine-glob`, that `jac precommit --verify` exits 1, and that `--lintfix` writes the comment-moved text above. Mutation-checked: with the declarations already merged, `jac precommit --verify` exits 0 and the canary fails.

## Upstream issue draft

(For the owner to review before posting.)

> **`combine-glob` / `combine-has` are applied by `--fix` but never reported by `jac check --lint`; the merge moves a trailing comment**
>
> jac 0.39.0. For `glob A: int = 1;  # about A` followed by `glob B: int = 2;`, `jac check --lint` reports nothing (also with `[check.lint] select = ["all"]` or `["combine-glob"]`), while `jac check --lint --fix`, `jac fmt --lintfix` and `jac precommit --verify` apply or require `glob A: int = 1, B: int = 2;`. The same holds for `has`. The rewrite also moves `# about A` to the end of the combined statement, after `B`. Expected: report mode lists the same rules fix mode applies, and comments stay with their declaration.
