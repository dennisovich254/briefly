#!/usr/bin/env bash
# Type-check the project: fail on any error, and on more warnings than the committed baseline
# (.jac-warnings-baseline), which may only go down.
#   scripts/check_warnings.sh            check against the baseline
#   scripts/check_warnings.sh --update   write the current count as the new baseline
#   WARNING_BASELINE=N ...               override the baseline (used by scripts/hooks_selftest.sh)
# Two runs: a bare `jac check` checks each app as a whole program, but skips every file no app
# imports, such as tests/ and scripts/ (JD-005); so every tracked .jac file is also checked by name.
# The count is the sum of both runs' warnings.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
BASELINE_FILE=.jac-warnings-baseline

mapfile -d '' files < <(git ls-files -z '*.jac')
apps_out="$(jac check 2>&1)"
apps_rc=$?
files_out="$(jac check "${files[@]}" 2>&1)"
files_rc=$?
out="$apps_out"$'\n'"$files_out"
count="$(grep -cE '^⚠' <<<"$out" || true)"

if (( apps_rc != 0 || files_rc != 0 )); then
    grep -E -A3 '^✖' <<<"$out" | head -40
    echo "jac check: errors found (see above)." >&2
    exit 1
fi

if [[ "${1:-}" == "--update" ]]; then
    echo "$count" > "$BASELINE_FILE"
    echo "Baseline set to $count warning(s)."
    exit 0
fi

baseline="${WARNING_BASELINE:-$(tr -d '[:space:]' < "$BASELINE_FILE" 2>/dev/null)}"
baseline="${baseline:-0}"
if (( count > baseline )); then
    echo "jac check: $count warnings, baseline is $baseline. New warnings were introduced:" >&2
    grep -E -A1 '^⚠' <<<"$out" >&2
    exit 1
elif (( count < baseline )); then
    echo "jac check: $count warnings (baseline $baseline). Lock it in: scripts/check_warnings.sh --update"
else
    echo "jac check: 0 errors, $count warnings (= baseline)."
fi
