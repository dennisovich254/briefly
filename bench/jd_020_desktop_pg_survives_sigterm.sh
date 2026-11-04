#!/usr/bin/env bash
# Canary for JD-020: the desktop app's own PostgreSQL stops when its window is closed, but keeps
# running after the app gets SIGTERM (what logout or shutdown sends).
# Needs a desktop session and the built artifact (`jac build desktop`). Stops the cluster afterwards.
# Exit 0 = the finding still holds; exit 1 = PostgreSQL stopped after SIGTERM too: re-check JD-020;
# exit 2 = the setup failed.
set -uo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
app_dir="$root/.jac/client/desktop/desktop"
data="$HOME/.local/share/io.github.dennisovich254.briefly.lean"
pg_ctl="$app_dir/pgdist/bin/pg_ctl"
[[ -x "$app_dir/briefly-launch.sh" ]] || { echo "no desktop artifact: run jac build desktop"; exit 2; }
cluster_pid() { pgrep -f "[p]gdist/bin/postgres -D $data" | head -1; }
[[ -z "$(cluster_pid)" ]] || "$pg_ctl" stop -D "$data/pg/main" -m fast >/dev/null 2>&1

(cd "$app_dir" && exec setsid ./briefly-launch.sh >/dev/null 2>&1 < /dev/null) &
for _ in $(seq 1 90); do [[ -n "$(cluster_pid)" ]] && pgrep -f "[W]ebKitWebProcess" >/dev/null && break; sleep 1; done
host="$(pgrep -xf './briefly' | head -1)"
pg="$(cluster_pid)"
[[ -n "$host" && -n "$pg" ]] || { echo "the app did not start"; exit 2; }
echo "jac $(jac --version | awk '{print $2}'): host $host, its PostgreSQL $pg"
kill -TERM "$host"
for _ in $(seq 1 30); do kill -0 "$host" 2>/dev/null || break; sleep 1; done
sleep 20
if kill -0 "$pg" 2>/dev/null; then
    echo "REPRODUCES: PostgreSQL $pg still running 20 s after the host exited on SIGTERM"
    "$pg_ctl" stop -D "$data/pg/main" -m fast >/dev/null 2>&1
    exit 0
fi
echo "changed: PostgreSQL stopped after SIGTERM"
exit 1
