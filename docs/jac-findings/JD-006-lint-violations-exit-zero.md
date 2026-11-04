# JD-006: No Jac command fails on a lint violation it cannot auto-fix

- **Version:** jaclang 0.39.0, Ubuntu 26.04, x86-64, both profiles
- **Found:** 2026-11-04, phase 0 / 0.5 pre-commit hooks (re-test of JI-010)
- **Category / severity:** Defect / Minor
- **Capability:** Tooling (`jac check`, `jac fmt`, `jac browse`, editor support)
- **Status:** open
- **Related:** JI-010 (AfriCinemas: `jac check --lint` exits 0 when it reports violations), still holding on 0.39.0; upstream searched 2026-11-04: no matching issue
- **Cost:** 1 h, including the lint violations it hid in 0.3 and 0.4; workaround `scripts/jac_lint.sh` (about 20 lines)
- **Canary:** tests/canaries/jd_006_lint_violations_exit_zero.jac

## Behaviour

`jac check --lint <file>` prints each violation (`⚠ file, line 1, col 7: Mutable default argument 'list' … [mutable-default]`), then `✔ Linted 1 '.jac' files: 0 errors found.`, and exits 0. Jac's own commit gate, `jac precommit --verify`, also exits 0: it fails only when `jac fmt --lintfix` would change the file or `jac check` reports an error, so it catches violations Jac can auto-fix (`remove-empty-parens`) but not report-only ones (`mutable-default`, `repeated-condition`, `too-many-params`).

So Jac has no command that gates on lint. In Briefly this hid 10 violations committed in 0.3 and 0.4 (`unnecessary-none-return` ×8, `mutable-default` ×2): each lint run said "0 errors found" and exited 0, and the 0.4 record called lint clean.

## Expected

A gate that fails when a violation is reported, at least as an option (`--strict`, or a non-zero exit when any `⚠` is printed). The CLI reference describes `jac check --lint` as reporting violations, and `jac precommit` as able to "gate a commit". Neither says that reported violations do not affect the exit code. The summary line "0 errors found" directly under a printed violation is misleading.

## Repro

`~/jac-repros/JD-006/`:

```jac
# mutable.jac
def m(items: list[int] = []) -> int {
    return len(items);
}
```

`jac check --lint mutable.jac`: the violation is printed, exit 0. `jac precommit --verify mutable.jac`: exit 0. The same for `repeated.jac` (an `elif` repeating its `if` condition). `emptyparens.jac` (`def g() -> int`) is caught by `jac precommit --verify` (exit 1) because `--lintfix` rewrites it.

## Analysis

JI-010 holds unchanged on 0.39.0, and `jac precommit`, which looks like the answer, only covers the auto-fixable subset. Any project that wires either command into a hook or CI gets a lint gate that never fails on the rules that need a human.

## Workaround

`scripts/jac_lint.sh` runs `jac check --lint` on the given files (every tracked `.jac` file by default, because of JD-007) and fails when any `⚠` or `✖` line is printed. It is the `jac-lint` pre-commit hook, next to `jac precommit --verify` for the rest. `scripts/hooks_selftest.sh` checks that it rejects a report-only violation.

## Canary

`tests/canaries/jd_006_lint_violations_exit_zero.jac`: on the repro above, asserts that `jac check --lint` reports `mutable-default` and exits 0, and that `jac precommit --verify` exits 0. Mutation-checked: with an auto-fixable violation instead, `jac precommit --verify` exits 1 and the canary fails.

## Upstream issue draft

(For the owner to review before posting.)

> **No Jac command exits non-zero on a reported lint violation; `jac precommit --verify` misses rules without an auto-fix**
>
> jac 0.39.0. For `def m(items: list[int] = []) -> int { return len(items); }`, `jac check --lint file.jac` prints the `mutable-default` violation, then "✔ Linted 1 '.jac' files: 0 errors found.", and exits 0. `jac precommit --verify file.jac` also exits 0, since it fails only when `--lintfix` changes a file or `jac check` errors; report-only rules (`mutable-default`, `repeated-condition`, `too-many-params`) never fail it. A hook or CI gate built on either command never blocks lint violations. Suggest a non-zero exit when violations are reported (or a `--strict` flag), and have `jac precommit` use it.
