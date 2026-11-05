#!/usr/bin/env bash
# Smoke-test a built lean artifact: run it from an empty directory, then check the page,
# /healthz and the app_info endpoint. Used by CI after `jac build lean`.
#   scripts/smoke_lean.sh [path/to/briefly.jab]   (default: dist/briefly.jab)
set -uo pipefail
jab="$(realpath "${1:-dist/briefly.jab}")"
base="http://localhost:8000"
work="$(mktemp -d)"
server=""
cleanup() {
    [[ -n "$server" ]] && kill "$server" 2>/dev/null && wait "$server" 2>/dev/null
    rm -rf "$work"
}
trap cleanup EXIT

[[ -f "$jab" ]] || { echo "smoke: no artifact at $jab" >&2; exit 1; }
cp "$jab" "$work/"
(cd "$work" && exec jac run "$(basename "$jab")") > "$work/server.log" 2>&1 &
server=$!

for _ in $(seq 1 90); do
    curl -fs "$base/healthz" >/dev/null 2>&1 && break
    kill -0 "$server" 2>/dev/null || { echo "smoke: server exited" >&2; tail -20 "$work/server.log" >&2; exit 1; }
    sleep 2
done

failures=0
check() {  # check <description> <command...>
    local desc="$1"
    shift
    if "$@" >/dev/null 2>&1; then echo "  ok    $desc"; else echo "  FAIL  $desc"; failures=$((failures + 1)); fi
}
check "/healthz is ok"            bash -c "curl -fs '$base/healthz' | grep -q '\"ok\"'"
check "the page has the title"    bash -c "curl -fs '$base/' | grep -q '<title>Briefly</title>'"
check "listens on loopback only"   bash -c "ss -Hltn 'sport = :8000' | awk '{print \$4}' | grep -q . && ! ss -Hltn 'sport = :8000' | awk '{print \$4}' | grep -v '^127\\.0\\.0\\.1:'"
check "app_info answers Briefly"  bash -c "curl -fs -X POST -H 'Content-Type: application/json' -d '{}' '$base/function/app_info' | grep -q '\"name\": \"Briefly\"'"

if (( failures > 0 )); then tail -20 "$work/server.log" >&2; exit 1; fi
echo "Lean artifact smoke test passed."
