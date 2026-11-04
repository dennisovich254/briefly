#!/usr/bin/env bash
# Governance check (plan 0.7): the repository files exist and say what they must, .env.example
# documents every environment variable the app reads with names only, and secrets stay out of git.
# Reads .env for variable NAMES only and never prints a value. Runs in the CI `quality` job;
# self-tested by scripts/governance_selftest.sh.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
failures=0
ok()   { printf '  ok    %s\n' "$1"; }
miss() { printf '  MISS  %s\n' "$1"; failures=$((failures + 1)); }
has()  { if [[ -s "$1" ]]; then ok "$1 exists"; else miss "$1 missing or empty"; fi; }
contains() { if grep -qF -- "$2" "$1" 2>/dev/null; then ok "$1 mentions: $2"; else miss "$1 should mention: $2"; fi; }

for f in CONTRIBUTING.md SECURITY.md .github/PULL_REQUEST_TEMPLATE.md .github/CODEOWNERS \
         .github/dependabot.yml .editorconfig .env.example; do
    has "$f"
done

for item in "scripts/install_jac.sh" "scripts/doctor.sh" "jac install" "pre-commit install" \
            "RED" "GREEN" "Jac-first" "Conventional Commits" "squash"; do
    contains CONTRIBUTING.md "$item"
done
for item in "## Summary" "## Jac findings" "## Screenshots"; do
    contains .github/PULL_REQUEST_TEMPLATE.md "$item"
done
contains SECURITY.md "security/advisories/new"
contains .github/dependabot.yml "package-ecosystem: github-actions"

# Every variable the app reads is documented in .env.example: BRIEFLY_* names in product code,
# names passed to os.getenv / os.environ in product code, names set in .env, and ${NAME} in
# jac.toml. Jac's own (JAC_*) and the test runner's variables are not the app's.
names() {  # NAME= assignments in a dotenv file
    grep -E '^\s*(export\s+)?[A-Za-z_][A-Za-z0-9_]*\s*=' "$1" 2>/dev/null \
        | sed -E 's/^\s*(export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=.*/\2/' | sort -u
}
mapfile -t product < <(git ls-files --cached --others --exclude-standard 'core/*.jac' 'ui/*.jac' 'hosts/*.jac' 'main.jac')
used="$(
    {
        (( ${#product[@]} )) && grep -ohE '"BRIEFLY_[A-Z0-9_]+"' "${product[@]}" | tr -d '"'
        (( ${#product[@]} )) && grep -ohE '(getenv|environ\.get|environ)\(?\[?\s*"[A-Za-z_][A-Za-z0-9_]*"' "${product[@]}" \
            | grep -oE '"[A-Za-z_][A-Za-z0-9_]*"' | tr -d '"'
        [[ -f .env ]] && names .env
        grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*' jac.toml 2>/dev/null | tr -d '${'
    } | sort -u
)"
documented="$(names .env.example)"
for v in $used; do
    if grep -qx "$v" <<<"$documented"; then ok ".env.example documents $v"; else miss ".env.example is missing $v"; fi
done
if grep -qE '^\s*(export\s+)?[A-Za-z_][A-Za-z0-9_]*\s*=\s*[^[:space:]#]' .env.example 2>/dev/null; then
    miss ".env.example must have names only (found a value)"
else
    ok ".env.example has names only, no values"
fi

# Secrets and local-only files stay out of git.
for f in .env .mcp.json .claude/x bench/private/x; do
    if git check-ignore -q --no-index "$f"; then ok "$f is git-ignored"; else miss "$f is NOT git-ignored"; fi
done

echo
if (( failures > 0 )); then echo "$failures governance check(s) failed."; exit 1; fi
echo "All governance checks passed."
