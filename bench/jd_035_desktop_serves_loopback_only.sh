#!/usr/bin/env bash
# Canary for JD-035: the desktop host serves on 127.0.0.1 only, whatever the app asks for, and Jac
# has no way to open a listener on the LAN while the app runs. Starts the built artifact under Xvfb
# with JAC_SERVE_HOST=0.0.0.0 (the documented way to widen a served app's address) and lists the
# host's TCP listeners. Builds nothing: uses the artifact from `jac build desktop` in place, with a
# throwaway HOME so the owner's data is untouched. Makes no Claude call.
# Exit 0 = the finding still holds (loopback only); exit 1 = the host now listens beyond loopback:
# re-check JD-035; exit 2 = the setup failed.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app="$root/.jac/client/desktop/desktop"
[[ -x "$app/briefly-launch.sh" ]] || { echo "no desktop artifact: run jac build desktop"; exit 2; }
command -v xvfb-run >/dev/null || { echo "xvfb-run is not installed"; exit 2; }
command -v ss >/dev/null || { echo "ss is not installed"; exit 2; }
work="$HOME/jac-repros/JD-035-run"
rm -rf "$work" && mkdir -p "$work/home"
cleanup() {
    local host cluster
    host="$(pgrep -f '^\./briefly$' | head -1)"
    [[ -n "$host" ]] && kill "$host" 2>/dev/null && sleep 5
    cluster="$(find "$work/home" -type d -path '*/pg/main' 2>/dev/null | head -1)"
    [[ -n "$cluster" ]] && "$app/pgdist/bin/pg_ctl" stop -D "$cluster" -m fast >/dev/null 2>&1
    rm -rf "$work"
}
trap cleanup EXIT
(cd "$app" && HOME="$work/home" XDG_DATA_HOME="$work/home/.local/share" JAC_SERVE_HOST=0.0.0.0 \
    env -u ANTHROPIC_API_KEY xvfb-run -a ./briefly-launch.sh >"$work/app.log" 2>&1 &)
url=""
for _ in $(seq 1 90); do
    url="$(grep -oE 'JAC_DESKTOP_SERVING http://[^/]+/' "$work/app.log" | head -1 | cut -d' ' -f2)"
    [[ -n "$url" ]] && break
    sleep 1
done
[[ -n "$url" ]] || { echo "the app did not start"; tail -5 "$work/app.log"; exit 2; }
port="$(grep -oE ':[0-9]+/$' <<<"$url" | tr -d ':/')"
listeners="$(ss -Hltn "sport = :$port" | awk '{print $4}')"
echo "jac $(jac --version | awk '{print $2}'): serving $url, listening on: $(tr '\n' ' ' <<<"$listeners")"
[[ -n "$listeners" ]] || { echo "nothing listens on port $port"; exit 2; }
if ! grep -qv '^127\.0\.0\.1:' <<<"$listeners"; then
    echo "REPRODUCES: JAC_SERVE_HOST=0.0.0.0 is ignored; the desktop host listens on loopback only"
    exit 0
fi
echo "changed: the desktop host listens beyond loopback"
exit 1
