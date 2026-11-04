#!/usr/bin/env bash
# The one way to run Briefly's tests: locally, in the pre-push hook and in CI.
#   scripts/test.sh            everything: jac tests (canaries included), the toolchain and governance self-tests
#   scripts/test.sh --quick    skips the canaries (tests named jd_*, which build throwaway projects)
#   scripts/test.sh [--quick] -- <extra jac test arguments>
# Strict: a test file whose import fails is a failure, not a silent skip (JI-001: without strict
# mode, `jac test` reports it as skipped and exits 0). Workers: Jac's default, which is budgeted by
# available memory (4 workers and about 330 MB in all on the owner's 4 GB laptop, 16 s for the quick
# suite; one worker took 228 s). JAC_TEST_JOBS overrides it.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

quick=0
extra=()
while (( $# )); do
    case "$1" in
        --quick) quick=1 ;;
        --) shift; extra=("$@"); break ;;
        *) echo "unknown option: $1 (see the header of $0)" >&2; exit 2 ;;
    esac
    shift
done

# Run as a Git hook, Git exports GIT_DIR and friends; tests that build throwaway repositories must
# not inherit them (from a linked worktree, `git init` would reinitialise this repository).
# shellcheck disable=SC2046
unset $(git rev-parse --local-env-vars)

export JAC_TEST_STRICT=1
export BRIEFLY_CLOCK_CONTROL=1

filter=()
(( quick )) && filter=(-f "not jd")

status=0
echo "== jac test (jobs: ${JAC_TEST_JOBS:-default}$( (( quick )) && echo ", quick"))"
jac test "${filter[@]}" "${extra[@]}" || status=1
echo "== toolchain self-test"
scripts/toolchain_selftest.sh || status=1
echo "== governance self-test"
scripts/governance_selftest.sh || status=1

(( status == 0 )) && echo "All tests passed." || echo "Some tests failed." >&2
exit $status
