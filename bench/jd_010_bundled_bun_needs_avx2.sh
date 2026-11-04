#!/usr/bin/env bash
# Canary for JD-010 (JI-002): the bun bundled in the Jac runtime needs AVX2 and has no fallback.
# Runs the runtime's original bundled bun: the one scripts/swap_bundled_bun.sh keeps as
# bun.avx2-original, or the bundled bun itself if it was never swapped.
# Exit 0 = the finding still holds (SIGILL on this CPU); exit 1 = the bundled bun runs here: re-check
# JD-010, mark it fixed, and with JD-001 plan removal of scripts/swap_bundled_bun.sh;
# exit 2 = not testable on this machine (the CPU has AVX2).
set -uo pipefail
if grep -qw avx2 /proc/cpuinfo; then
    echo "NOT TESTABLE: this CPU has AVX2"
    exit 2
fi
probe="$(mktemp -d)"; trap 'rm -rf "$probe"' EXIT
printf 'import jaclang;\nwith entry { print(jaclang.__file__); }\n' > "$probe/where.jac"
init_py="$(cd "$probe" && jac run where.jac 2>/dev/null | grep -E '/jaclang/__init__\.py$' | tail -1)"
[[ -n "$init_py" ]] || { echo "could not locate the active Jac runtime"; exit 2; }
dir="$(dirname "$init_py")/client/_bun"
bun="$dir/bun.avx2-original"
[[ -x "$bun" ]] || bun="$dir/bun"
[[ -x "$bun" ]] || { echo "no bundled bun under $dir"; exit 2; }
echo "jac $(jac --version | awk '{print $2}'), bundled bun $(tr -d '\n' < "$dir/bun.artifact.json" 2>/dev/null)"
echo "CPU: $(grep -m1 'model name' /proc/cpuinfo | cut -d: -f2- | sed 's/^ //')"
"$bun" --version >/dev/null 2>&1
rc=$?
if (( rc == 132 )); then
    echo "REPRODUCES: $bun exits 132 (SIGILL)"
    exit 0
fi
echo "bundled bun exited $rc: it runs on this CPU"
exit 1
