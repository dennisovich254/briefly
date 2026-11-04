#!/usr/bin/env bash
# Lint .jac files and fail on any finding.
#   scripts/jac_lint.sh [files...]   (no arguments: every tracked .jac file)
# `jac check --lint` prints violations, reports "0 errors found" and exits 0, and
# `jac precommit --verify` ignores violations it cannot auto-fix (JD-006, JI-010), so this script
# fails itself when a finding (⚠) or error (✖) is printed. With no paths, `jac check --lint` lints
# 0 files (JD-007), so the tracked files are always passed explicitly.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

files=("$@")
if (( ${#files[@]} == 0 )); then
    mapfile -d '' files < <(git ls-files -z '*.jac')
fi
(( ${#files[@]} )) || { echo "jac lint: no .jac files"; exit 0; }

out="$(jac check --lint "${files[@]}" 2>&1)"
rc=$?
printf '%s\n' "$out"
if (( rc != 0 )) || grep -qE '^(⚠|✖)' <<<"$out"; then
    echo "jac lint: violations found (fix them, or try: jac check --lint --fix <file>)" >&2
    exit 1
fi
