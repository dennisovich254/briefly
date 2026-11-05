#!/usr/bin/env bash
# Canary for JD-038: `jac run lean` (dev mode for a web app) starts Vite on every interface, and
# Vite proxies the whole API, so the app is on the network whatever `[serve] host` says; the
# documented `--host 127.0.0.1` does not reach Vite either. Starts `jac run lean --host 127.0.0.1`
# and lists the Vite listener. Makes no Claude call.
# Exit 0 = the finding still holds (Vite on every interface); exit 1 = Vite keeps to loopback:
# re-check JD-038; exit 2 = the setup failed.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v ss >/dev/null || { echo "ss is not installed"; exit 2; }
log="$(mktemp)"
cd "$root" || exit 2
setsid jac run lean --host 127.0.0.1 >"$log" 2>&1 &
group=$!
cleanup() { kill -- "-$group" 2>/dev/null; sleep 2; rm -f "$log"; }
trap cleanup EXIT
web=""
for _ in $(seq 1 90); do
    web="$(grep -oE 'Local: +http://localhost:[0-9]+' "$log" | head -1 | grep -oE '[0-9]+$')"
    [[ -n "$web" ]] && break
    sleep 1
done
[[ -n "$web" ]] || { echo "the dev server did not start"; tail -5 "$log"; exit 2; }
listeners="$(ss -Hltn "sport = :$web" | awk '{print $4}' | tr '\n' ' ')"
echo "jac $(jac --version | awk '{print $2}'): Vite on port $web listening on: $listeners"
if grep -qE '(^| )(\*|0\.0\.0\.0|\[::\]):' <<<" $listeners"; then
    echo "REPRODUCES: with --host 127.0.0.1 the dev server still listens on every interface"
    exit 0
fi
echo "changed: the dev server keeps to loopback"
exit 1
