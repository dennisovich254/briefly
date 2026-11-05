#!/usr/bin/env bash
# Self-test for the Git hooks (plan 0.5). Builds a throwaway repository carrying this project's
# hook config, scripts and findings log, and asserts that each gate rejects bad input and accepts
# clean input. The throwaway project is a workspace with one app, so the gates are tested on files
# no app imports (JD-005). Needs the pre-commit hook repositories (fetched once into
# ~/.cache/pre-commit). Exits non-zero on any miss.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The throwaway repository must not inherit GIT_DIR and friends from a calling hook.
# shellcheck disable=SC2046
unset $(git rev-parse --local-env-vars)
WORK="$(mktemp -d -t briefly-hooks-XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

failures=0
expect() {  # expect <pass|fail> <description> <command...>
    local want="$1" desc="$2" got
    shift 2
    if "$@" >"$WORK/.last.log" 2>&1; then got=pass; else got=fail; fi
    if [[ "$got" == "$want" ]]; then
        printf '  ok    %-62s (%s)\n' "$desc" "$got"
    else
        printf '  MISS  %-62s (wanted %s, got %s)\n' "$desc" "$want" "$got"
        sed 's/^/        /' "$WORK/.last.log" | tail -8
        failures=$((failures + 1))
    fi
}

[[ -f "$ROOT/.pre-commit-config.yaml" ]] || { echo "  MISS  .pre-commit-config.yaml not found"; exit 1; }

REPO="$WORK/repo"
mkdir -p "$REPO/docs" "$REPO/tests"
cd "$REPO"
git init -q -b main
git config user.email selftest@example.invalid
git config user.name selftest
git config commit.gpgsign false
cp "$ROOT/.pre-commit-config.yaml" "$ROOT/.jac-warnings-baseline" .
cp -r "$ROOT/scripts" .
# Only the bench scripts: the findings log names bench canaries, and the .jac benches import core/.
mkdir -p bench && cp "$ROOT"/bench/*.sh bench/
cp -r "$ROOT/docs/jac-findings" docs/
cp -r "$ROOT/tests/canaries" tests/
printf '[project]\nname = "hooks-selftest"\nversion = "0.1.0"\n\n[apps.web]\nkind = "web-app"\nentry-point = "main"\n' > jac.toml
printf 'with entry {\n    print("hi");\n}\n' > main.jac
printf 'def f -> int {\n    return 1;\n}\n' > clean.jac
git add -A
git -c core.hooksPath=/dev/null commit -q -m "chore: seed"
git switch -q -c feat/selftest

run_hook() { pre-commit run "$1" --files "${@:2}"; }
# Track a file for one check and drop it again, so later checks see a clean tree.
track() { git add "$@"; }
untrack() { git rm -q -f --cached "$@" && rm -f "$@"; }

echo "== jac precommit --verify (format, fixable lint, type errors)"
printf 'def   f->int{return 1;}\n' > badfmt.jac
printf 'def g() -> int {\n    return 1;\n}\n' > emptyparens.jac
printf 'def k -> int {\n    return "not an int";\n}\n' > typeerr.jac
track badfmt.jac emptyparens.jac typeerr.jac
expect fail "rejects an unformatted file"                       run_hook jac-precommit badfmt.jac
expect fail "rejects a lint violation jac can fix"              run_hook jac-precommit emptyparens.jac
expect fail "rejects a type error"                              run_hook jac-precommit typeerr.jac
expect pass "accepts a clean file"                              run_hook jac-precommit clean.jac
untrack badfmt.jac emptyparens.jac typeerr.jac

echo "== jac lint (fails on any finding: JD-006)"
printf 'def m(items: list[int] = []) -> int {\n    return len(items);\n}\n' > mutable.jac
track mutable.jac
expect fail "rejects a report-only lint violation"              run_hook jac-lint mutable.jac
expect fail "with no arguments, lints every tracked file (JD-007)" scripts/jac_lint.sh
expect pass "accepts a clean file"                              run_hook jac-lint clean.jac
untrack mutable.jac
expect pass "with no arguments, passes a clean tree"            scripts/jac_lint.sh

echo "== secrets (built at runtime so this file never contains one)"
pk_header="-----BEGIN RSA ""PRIVATE KEY-----"
printf '%s\nMIIEpAIBAAKCAQEAselftestselftest\n' "$pk_header" > id_fake
token_prefix="gh""p_"
printf 'GITHUB_TOKEN = "%s%s"\n' "$token_prefix" "A1b2C3d4E5f6G7h8I9j0K1l2M3n4O5p6Q7r8" > leaked.py
track id_fake leaked.py
expect fail "detect-private-key rejects a private key"          run_hook detect-private-key id_fake
expect fail "gitleaks rejects a staged GitHub token"            run_hook gitleaks-system leaked.py
untrack id_fake leaked.py
expect pass "gitleaks accepts a tree without secrets"           run_hook gitleaks-system clean.jac

echo "== file hygiene"
printf 'trailing space \n' > spaces.txt
printf '[project\n' > broken.toml
track spaces.txt broken.toml
expect fail "trailing-whitespace rejects trailing spaces"       run_hook trailing-whitespace spaces.txt
expect fail "check-toml rejects invalid TOML"                   run_hook check-toml broken.toml
untrack spaces.txt broken.toml

echo "== commit messages (Conventional Commits)"
printf 'update stuff\n' > msg_plain
printf 'feature(p0.5): add hooks\n' > msg_unknown_type
printf 'feat(p0.5): add hooks\n\nBody.\n\nCo-Authored-By: Someone <someone@example.invalid>\n' > msg_feat
printf 'bench(1.3): measure idle memory\n' > msg_bench
cm() { pre-commit run conventional-pre-commit --hook-stage commit-msg --commit-msg-filename "$1"; }
expect fail "rejects 'update stuff'"                            cm msg_plain
expect fail "rejects an unknown type ('feature')"               cm msg_unknown_type
expect pass "accepts 'feat(p0.5): ...' with a body and trailer" cm msg_feat
expect pass "accepts the project's 'bench' type"                cm msg_bench
rm -f msg_plain msg_unknown_type msg_feat msg_bench

echo "== branch"
git switch -q main
expect fail "no-commit-to-branch blocks commits on main"        run_hook no-commit-to-branch clean.jac
git switch -q feat/selftest
expect pass "no-commit-to-branch allows feature branches"       run_hook no-commit-to-branch clean.jac

echo "== findings log"
expect pass "check-findings accepts the real log"               pre-commit run check-findings --all-files
first="$(ls docs/jac-findings/JD-*.md | head -1)"
cp "$first" "$WORK/finding.bak"
sed -i '/^- \*\*Cost:\*\*/d' "$first"
expect fail "check-findings rejects an entry missing a field"   pre-commit run check-findings --all-files
cp "$WORK/finding.bak" "$first"

echo "== jac check ratchet (pre-push: 0 errors, warnings <= baseline)"
expect pass "passes at the committed baseline"                  scripts/check_warnings.sh
printf 'def m(items: list[int] = []) -> int {\n    return len(items);\n}\n' > tests/warn.jac
track tests/warn.jac
expect fail "fails when a file no app imports adds a warning (JD-005)" env WARNING_BASELINE=0 scripts/check_warnings.sh
expect pass "passes when the baseline allows that warning"      env WARNING_BASELINE=1 scripts/check_warnings.sh
untrack tests/warn.jac
printf 'def k -> int {\n    return "not an int";\n}\n' > tests/orphan.jac
track tests/orphan.jac
expect fail "fails on a type error in a file no app imports (JD-005)" scripts/check_warnings.sh
untrack tests/orphan.jac
expect pass "runs as the pre-push hook"                         pre-commit run jac-check-ratchet --hook-stage pre-push --all-files

echo
if (( failures > 0 )); then echo "$failures hook self-test(s) failed."; exit 1; fi
echo "All hook self-tests passed."
