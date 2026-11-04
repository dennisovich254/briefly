#!/usr/bin/env bash
# Canary for JD-011 (JI-005): the desktop build installs its system packages itself with sudo, and
# when it cannot, it ends in a Python traceback that does not name the packages.
# Simulates a machine without the WebKitGTK development packages: a pkg-config that finds nothing
# is first on PATH, in a fresh `jac create --kind desktop` project. Takes a few minutes.
# Exit 0 = the finding still holds; exit 1 = the build no longer reaches for sudo (or now names the
# packages): re-check JD-011; exit 2 = the setup failed.
set -uo pipefail
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/fakebin"
printf '#!/bin/sh\nexit 1\n' > "$work/fakebin/pkg-config"
chmod +x "$work/fakebin/pkg-config"
cd "$work" && jac create d --kind desktop >/dev/null 2>&1 && cd d || { echo "jac create failed"; exit 2; }
echo "jac $(jac --version | awk '{print $2}')"
PATH="$work/fakebin:$PATH" jac build > "$work/build.log" 2>&1 < /dev/null
rc=$?
grep -E "administrator|sudo|Error" "$work/build.log" | head -4
if (( rc != 0 )) && grep -q "sudo" "$work/build.log" && grep -q "^Traceback" "$work/build.log" \
        && ! grep -q "libwebkit2gtk-4.1-dev" "$work/build.log"; then
    echo "REPRODUCES: the build reached for sudo and ended in a traceback without the package names"
    exit 0
fi
echo "changed: build exit $rc; see the output above"
exit 1
