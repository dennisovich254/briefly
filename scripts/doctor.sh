#!/usr/bin/env bash
# Toolchain doctor for Briefly.
# Verifies every tool the dev workflow depends on. Exits non-zero if any check fails.
# Later sub-phases add their tools here (hooks in 0.5, actionlint in 0.6).
# Usage: scripts/doctor.sh          (NO_COLOR=1 for plain output)
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then GREEN=$'\e[32m'; RED=$'\e[31m'; DIM=$'\e[2m'; RESET=$'\e[0m'; else GREEN=""; RED=""; DIM=""; RESET=""; fi
failures=0

pass() { printf '%s  PASS%s  %s\n' "$GREEN" "$RESET" "$1"; }
fail() { printf '%s  FAIL%s  %s\n' "$RED" "$RESET" "$1"; [[ -n "${2:-}" ]] && printf '        %sfix: %s%s\n' "$DIM" "$2" "$RESET"; failures=$((failures + 1)); }

# 1. Jac installed at the pinned version (.jac-version is the single source of truth)
pinned="$(tr -d '[:space:]' < .jac-version 2>/dev/null)"
if [[ -z "$pinned" ]]; then
    fail "pinned Jac version in .jac-version" "create .jac-version containing e.g. 0.39.0"
elif ! command -v jac >/dev/null 2>&1; then
    fail "jac on PATH" "scripts/install_jac.sh"
else
    # A fresh binary's first run prints extraction lines first; take only the "jac X.Y.Z" line.
    actual="$(jac --version 2>/dev/null | grep -E '^jac [0-9]' | awk '{print $2}' | head -1)"
    if [[ "$actual" == "$pinned" ]]; then pass "jac $actual (pinned $pinned)"
    else fail "jac version $actual != pinned $pinned" "scripts/install_jac.sh, or bump .jac-version in a PR"; fi
fi

# 2. The bun that Jac uses for client builds runs on this CPU.
#    Jac's bundled bun needs AVX2 (JI-002), and Jac ignores JAC_BUN (JD-001), so the bun that
#    matters is the one inside the active runtime: <runtime>/site/jaclang/client/_bun/bun.
bun_bin=""
if command -v jac >/dev/null 2>&1; then
    probe_dir="$(mktemp -d)"
    printf 'import jaclang;\nwith entry { print(jaclang.__file__); }\n' > "$probe_dir/where.jac"
    init_py="$(cd "$probe_dir" && jac run where.jac 2>/dev/null | grep -E '/jaclang/__init__\.py$' | tail -1)"
    rm -rf "$probe_dir"
    [[ -n "$init_py" ]] && bun_bin="$(dirname "$init_py")/client/_bun/bun"
fi
if [[ -z "$bun_bin" || ! -e "$bun_bin" ]]; then
    fail "no bundled bun found in the active Jac runtime" "check that 'jac run' works, then rerun the doctor"
elif bun_ver="$("$bun_bin" --version 2>/dev/null)"; then
    pass "bun $bun_ver runs (bundled in the active Jac runtime)"
else
    fail "Jac's bundled bun does not run on this CPU (no AVX2: JI-002)" "scripts/swap_bundled_bun.sh   (JAC_BUN is ignored: JD-001)"
fi

# 3. Python 3.10+ (pre-commit hooks)
if python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 10) else 1)' 2>/dev/null; then
    pass "python3 $(python3 -c 'import platform; print(platform.python_version())')"
else
    fail "python3 >= 3.10" "install Python 3.10 or newer"
fi

# 4. Git identity and remote
name="$(git config user.name 2>/dev/null)"; email="$(git config user.email 2>/dev/null)"
if [[ -n "$name" && -n "$email" ]]; then pass "git identity: $name <$email>"
else fail "git user.name / user.email not set" "git config --global user.name 'Your Name' && git config --global user.email you@example.com"; fi

if git remote get-url origin >/dev/null 2>&1; then pass "git remote origin: $(git remote get-url origin)"
else fail "git remote 'origin' missing" "git remote add origin https://github.com/<owner>/briefly.git"; fi

# 5. Secrets file is never committable
if [[ ! -e .env ]] || git check-ignore -q .env; then pass ".env is git-ignored"
else fail ".env exists but is NOT git-ignored" "add .env to .gitignore"; fi

# 6. pre-commit, its hooks, and the binaries they run
if command -v pre-commit >/dev/null 2>&1; then pass "pre-commit $(pre-commit --version | awk '{print $2}')"
else fail "pre-commit not installed" "uv tool install pre-commit   (uv: github.com/astral-sh/uv/releases)"; fi

if [[ -f .git/hooks/pre-commit && -f .git/hooks/commit-msg && -f .git/hooks/pre-push ]]; then pass "Git hooks installed"
else fail "Git hooks not installed" "pre-commit install"; fi

if command -v gitleaks >/dev/null 2>&1; then pass "gitleaks $(gitleaks version 2>/dev/null)"
else fail "gitleaks not installed" "scripts/install_gitleaks.sh"; fi

if command -v actionlint >/dev/null 2>&1; then pass "actionlint $(actionlint -version 2>/dev/null | head -1)"
else fail "actionlint not installed" "scripts/install_actionlint.sh"; fi

# 7. GitHub CLI, authenticated (needed for PRs and pushing)
if ! command -v gh >/dev/null 2>&1; then
    fail "gh (GitHub CLI) not installed" "download gh_<ver>_linux_amd64.tar.gz from github.com/cli/cli/releases, verify its checksum, copy bin/gh to ~/.local/bin"
elif gh auth status >/dev/null 2>&1; then
    pass "gh $(gh --version | head -1 | awk '{print $3}') authenticated"
else
    fail "gh installed but not authenticated" "gh auth login && gh auth setup-git"
fi

echo
if (( failures > 0 )); then
    printf '%s%d check(s) failed.%s\n' "$RED" "$failures" "$RESET"
    exit 1
fi
printf '%sAll checks passed.%s\n' "$GREEN" "$RESET"
