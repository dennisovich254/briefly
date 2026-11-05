#!/usr/bin/env bash
# Canary for JD-022: in a desktop app with no [desktop.plugins] table, every app_window call fails
# with "Plugin 'jac.window' is not registered", although the desktop guide says `window` is enabled
# by default. Runs bench/window_sdk.sh in its default configuration (a few minutes; needs a desktop
# session). Exit 0 = the finding still holds; exit 1 = the default now works: re-check JD-022 and
# consider dropping `window = true` from Briefly's [desktop.plugins]; exit 2 = the run failed.
set -uo pipefail
out="$("$(dirname "${BASH_SOURCE[0]}")/window_sdk.sh" 2>&1)"
rc=$?
printf '%s\n' "$out" | grep -E "jac |ok |FAIL|error" | head -8
if grep -q "Plugin 'jac.window' is not registered" <<<"$out"; then
    echo "REPRODUCES: app_window calls fail without [desktop.plugins] window = true"
    exit 0
fi
if (( rc == 0 )); then
    echo "changed: app_window works with the default configuration"
    exit 1
fi
echo "the window check failed for another reason"
exit 2
