#!/usr/bin/env bash
# Self-test for scripts/check_governance.sh (plan 0.7). Copies the governance files into a
# throwaway repository, checks that the checker accepts them, then breaks one rule at a time and
# checks that the checker rejects each. Exits non-zero on any miss.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# The throwaway repository must not inherit GIT_DIR and friends from a calling hook.
# shellcheck disable=SC2046
unset $(git rev-parse --local-env-vars)
WORK="$(mktemp -d -t briefly-governance-XXXXXX)"
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

[[ -x "$ROOT/scripts/check_governance.sh" ]] || { echo "  MISS  scripts/check_governance.sh not found"; exit 1; }

# A fresh copy of the tracked files for each case, so one break never leaks into the next.
fresh() {
    local repo="$WORK/repo-$RANDOM"
    mkdir -p "$repo"
    git -C "$ROOT" ls-files -z | (cd "$ROOT" && xargs -0 cp --parents -t "$repo")
    git -C "$repo" init -q
    echo "$repo"
}
check() { "$1/scripts/check_governance.sh"; }

repo="$(fresh)"
expect pass "accepts the real governance files"                    check "$repo"

repo="$(fresh)"; rm "$repo/SECURITY.md"
expect fail "rejects a missing SECURITY.md"                        check "$repo"

repo="$(fresh)"; : > "$repo/.github/CODEOWNERS"
expect fail "rejects an empty CODEOWNERS"                          check "$repo"

repo="$(fresh)"; sed -i '/pre-commit install/d' "$repo/CONTRIBUTING.md"
expect fail "rejects a CONTRIBUTING.md without the hook setup"     check "$repo"

repo="$(fresh)"; printf 'BRIEFLY_CLOCK_CONTROL=1\n' >> "$repo/.env.example"
expect fail "rejects a value in .env.example"                      check "$repo"

repo="$(fresh)"
printf 'import os;\n\ndef flag -> str {\n    return os.environ.get("BRIEFLY_UNDOCUMENTED", "");\n}\n' > "$repo/core/probe.jac"
expect fail "rejects a BRIEFLY_ variable missing from .env.example" check "$repo"

repo="$(fresh)"
printf 'import os;\n\ndef key -> str {\n    return os.getenv("SOME_SERVICE_KEY") or "";\n}\n' > "$repo/core/probe.jac"
expect fail "rejects a getenv() variable missing from .env.example" check "$repo"

repo="$(fresh)"; printf 'LOCAL_ONLY_SETTING=x\n' > "$repo/.env"
expect fail "rejects a .env name missing from .env.example"        check "$repo"

repo="$(fresh)"; sed -i '/^bench\/private\/$/d' "$repo/.gitignore"
expect fail "rejects bench/private/ not being git-ignored"         check "$repo"

repo="$(fresh)"; sed -i '/^\.env$/d' "$repo/.gitignore"
expect fail "rejects .env not being git-ignored"                   check "$repo"

repo="$(fresh)"; sed -i 's/package-ecosystem: github-actions/package-ecosystem: npm/' "$repo/.github/dependabot.yml"
expect fail "rejects a dependabot.yml that does not watch Actions" check "$repo"

echo
if (( failures > 0 )); then echo "$failures governance self-test(s) failed."; exit 1; fi
echo "All governance self-tests passed."
