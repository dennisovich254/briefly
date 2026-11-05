#!/usr/bin/env bash
# Canary for JD-032: the desktop artifact does not carry the project's Python dependencies (byLLM's
# litellm and the rest); its launcher reaches into the project's .jac/venv instead. Run from a copy
# outside the project, as an installed app is, a byLLM call fails with ModuleNotFoundError.
# Builds nothing: uses the artifact from `jac build desktop`, under Xvfb, with no API key, so the
# call never reaches a provider and costs nothing. Copies the artifact into ~/jac-repros (270 MB).
# Exit 0 = the finding still holds; exit 1 = the installed copy now reaches the provider: re-check
# JD-032; exit 2 = the setup failed.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
src="$root/.jac/client/desktop/desktop"
[[ -x "$src/briefly-launch.sh" ]] || { echo "no desktop artifact: run jac build desktop"; exit 2; }
command -v xvfb-run >/dev/null || { echo "xvfb-run is not installed"; exit 2; }
work="$HOME/jac-repros/JD-032-run"
rm -rf "$work" && mkdir -p "$work/app" "$work/home"
cleanup() {
    local host cluster
    host="$(pgrep -f '^\./briefly$' | head -1)"
    [[ -n "$host" ]] && kill "$host" 2>/dev/null && sleep 5
    cluster="$(find "$work/home" -type d -path '*/pg/main' 2>/dev/null | head -1)"
    [[ -n "$cluster" ]] && "$work/app/pgdist/bin/pg_ctl" stop -D "$cluster" -m fast >/dev/null 2>&1
    rm -rf "$work"
}
trap cleanup EXIT
cp -a "$src/." "$work/app/"
(cd "$work/app" && HOME="$work/home" XDG_DATA_HOME="$work/home/.local/share" \
    env -u ANTHROPIC_API_KEY -u JAC_DESKTOP_DEPS xvfb-run -a ./briefly-launch.sh >"$work/app.log" 2>&1 &)
url=""
for _ in $(seq 1 90); do
    url="$(grep -oE 'JAC_DESKTOP_SERVING http://127\.0\.0\.1:[0-9]+/' "$work/app.log" | head -1 | cut -d' ' -f2)"
    [[ -n "$url" ]] && break
    sleep 1
done
[[ -n "$url" ]] || { echo "the app did not start"; tail -5 "$work/app.log"; exit 2; }
# A synthetic fixture password for a throwaway local account, not a secret.
account='{"identities":[{"type":"username","value":"canary"}],"credential":{"type":"password","password":"Fixture-Pass-7319-xq"}}'  # gitleaks:allow
token="$(curl -s -X POST -H 'Content-Type: application/json' -d "$account" \
    "${url}user/register" | grep -oE '"token": *"[^"]+"' | cut -d'"' -f4)"
[[ -n "$token" ]] || { echo "could not register"; exit 2; }
frame="$(curl -sN --max-time 60 -X POST -H 'Content-Type: application/json' -H "Authorization: Bearer $token" \
    -d '{"question":"q","request_id":"canary"}' "${url}function/answer_stream" | grep -m1 '^data')"
echo "jac $(jac --version | awk '{print $2}'): $frame"
if grep -q 'ModuleNotFoundError' <<<"$frame"; then
    echo "REPRODUCES: the installed copy cannot import byLLM's provider packages"
    exit 0
fi
echo "changed: the installed copy no longer fails on a missing module"
exit 1
