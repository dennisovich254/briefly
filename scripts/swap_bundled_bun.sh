#!/usr/bin/env bash
# Workaround for JD-001 (Jac ignores JAC_BUN) on CPUs without AVX2 (JI-002):
# replace the bun bundled in the active Jac runtime with bun's "baseline" build of the same version.
# The original is kept beside it as bun.avx2-original. Run again after every Jac upgrade (a new
# runtime is extracted per release). Remove this script once the JD-001 canary shows the fix.
#   scripts/swap_bundled_bun.sh [path to baseline bun]     (default: $JAC_BUN, then ~/.local/opt/bun-baseline/bun)
# The baseline build is bun-linux-x64-baseline.zip from github.com/oven-sh/bun/releases (verify its checksum).
set -euo pipefail

baseline="${1:-${JAC_BUN:-$HOME/.local/opt/bun-baseline/bun}}"

# The active runtime is wherever this jac's own jaclang package lives.
probe_dir="$(mktemp -d)"; trap 'rm -rf "$probe_dir"' EXIT
printf 'import jaclang;\nwith entry { print(jaclang.__file__); }\n' > "$probe_dir/where.jac"
init_py="$(cd "$probe_dir" && jac run where.jac 2>/dev/null | grep -E '/jaclang/__init__\.py$' | tail -1)"
if [[ -z "$init_py" ]]; then
    echo "could not locate the active Jac runtime (is jac on PATH?)" >&2
    exit 1
fi
bun_dir="$(dirname "$init_py")/client/_bun"
bundled="$bun_dir/bun"

if ( "$bundled" --version ) >/dev/null 2>&1; then
    echo "The bundled bun runs on this CPU ($("$bundled" --version)); nothing to do."
    exit 0
fi

pinned="$(sed -n 's/.*"version": *"\([^"]*\)".*/\1/p' "$bun_dir/bun.artifact.json")"
if [[ ! -x "$baseline" ]]; then
    echo "baseline bun not found at $baseline" >&2
    exit 1
fi
offered="$("$baseline" --version 2>/dev/null || true)"
if [[ -z "$pinned" || "$offered" != "$pinned" ]]; then
    echo "baseline bun reports '$offered', but this Jac runtime pins bun '$pinned'" >&2
    exit 1
fi

[[ -e "$bun_dir/bun.avx2-original" ]] || cp -p "$bundled" "$bun_dir/bun.avx2-original"
install -m 755 "$baseline" "$bundled"
if ! "$bundled" --version >/dev/null 2>&1; then
    echo "the swapped bun at $bundled still does not run" >&2
    exit 1
fi
echo "Swapped the bundled bun $pinned for the baseline build at $bundled (original kept as bun.avx2-original)."
