#!/usr/bin/env bash
# Canary for JD-001: `jac install` ignores JAC_BUN (and a bun on PATH) and always runs the bundled bun.
# Works on any CPU: JAC_BUN points at a wrapper that logs each call and then runs the real bun.
# Exit 0 = the finding still holds (wrapper never called); exit 1 = JAC_BUN is honoured: re-check
# JD-001, mark it fixed, and plan removal of scripts/swap_bundled_bun.sh.
set -uo pipefail
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
real_bun="${REAL_BUN:-$(command -v bun || echo "$HOME/.local/opt/bun-baseline/bun")}"
mkdir -p "$work/wrap"
cat > "$work/wrap/bun" <<WRAP
#!/usr/bin/env bash
echo "called: \$*" >> "$work/calls.log"
exec "$real_bun" "\$@"
WRAP
chmod +x "$work/wrap/bun"
cd "$work" && jac create app --kind web-app --skip >/dev/null 2>&1 && cd app || { echo "jac create failed"; exit 2; }
echo "jac $(jac --version | grep -E '^jac [0-9]' | awk '{print $2}')"
JAC_BUN="$work/wrap/bun" jac install 2>&1 | tail -2
if [[ -s "$work/calls.log" ]]; then echo "JAC_BUN honoured:"; cat "$work/calls.log"; exit 1; fi
echo "REPRODUCES: JAC_BUN wrapper was never called"
