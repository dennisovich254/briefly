#!/usr/bin/env bash
# Window SDK check (plan 1.2): what `app_window` from @jac/desktop really does in a desktop build.
# Builds a throwaway desktop app whose page calls set_title, set_size, fullscreen and terminate in
# turn, logging each step through a server function, and checks the real X11 window with xwininfo
# after each step. Needs a desktop session. Prints one line per check and exits 1 if any failed.
# Always-on-top, a second window and minimise/restore are not checked: app_window has no such calls.
#   WINDOW_PLUGIN=explicit bench/window_sdk.sh   also sets `[desktop.plugins] window = true`
set -uo pipefail
work="$(mktemp -d -t briefly-window-XXXXXX)"
trap 'rm -rf "$work"' EXIT
log="$work/steps.log"
: > "$log"

cd "$work" && jac create spike --kind desktop >/dev/null 2>&1 && cd spike || { echo "jac create failed"; exit 2; }
printf '\n[placement]\ndefault = "server"\n\n[desktop.window]\ntitle = "Window spike"\nwidth = 900\nheight = 640\n' >> jac.toml
[[ "${WINDOW_PLUGIN:-}" == explicit ]] && printf '\n[desktop.plugins]\nwindow = true\n' >> jac.toml
cat > main.jac <<'JAC'
"""Calls each app_window method in turn and logs the steps (bench/window_sdk.sh)."""
import os;
import time;
import from "@jac/desktop" { app_window }

def:pub mark(step: str) -> str {
    with open(os.environ["SPIKE_LOG"], "a") as fh {
        fh.write(step + "\n");
    }
    return step;
}

def:pub pause(seconds: float) -> float {
    time.sleep(seconds);
    return seconds;
}

def:pub app -> JsxElement {
    has status: str = "starting";

    async can with entry {
        await mark("loaded");
        await pause(3.0);
        for (name, call) in [
            ("set_title", lambda -> any { return app_window.set_title("Spike titled"); }),
            ("set_size", lambda -> any { return app_window.set_size(700, 500, 0); }),
            ("fullscreen", lambda -> any { return app_window.fullscreen(); })
        ] {
            try {
                await call();
                await mark(name + " ok");
            } except Exception as e {
                await mark(name + " error " + str(e));
            }
            status = name;
            await pause(3.0);
        }
        await mark("terminate");
        await app_window.terminate();
    }

    <p>{status}</p>
}
JAC
jac build >/dev/null 2>&1 || { echo "jac build failed"; exit 2; }
app_dir="$(find .jac/client -maxdepth 3 -name 'spike-launch.sh' -printf '%h\n' | head -1)"
[[ -n "$app_dir" ]] || { echo "no launcher found"; exit 2; }
echo "jac $(jac --version | awk '{print $2}'), [desktop.plugins] window: ${WINDOW_PLUGIN:-default}"

(cd "$app_dir" && SPIKE_LOG="$log" exec setsid ./spike-launch.sh >"$work/app.log" 2>&1 < /dev/null) &
failures=0
check() {  # check <description> <command...>
    local desc="$1"
    shift
    if "$@"; then echo "  ok    $desc"; else echo "  FAIL  $desc"; failures=$((failures + 1)); fi
}
wait_step() {  # wait_step <prefix>: wait up to 90 s for a log line starting with it
    for _ in $(seq 1 90); do grep -q "^$1" "$log" && return 0; sleep 1; done
    return 1
}
window_line() { xwininfo -root -tree | grep -E '"(Window spike|Spike titled)": \("spike"' | head -1; }
size_of() { window_line | grep -oE '[0-9]+x[0-9]+' | head -1; }

wait_step loaded || { echo "the page never loaded"; cat "$work/app.log" | tail -5; exit 2; }
echo "  window before: $(size_of) \"$(window_line | grep -oE '"[^"]*"' | head -1 | tr -d '"')\""
wait_step "set_title" && sleep 1
echo "  set_title: $(grep '^set_title' "$log")"
check "set_title changes the window title" bash -c "xwininfo -root -tree | grep -q '\"Spike titled\": (\"spike\"'"
wait_step "set_size" && sleep 1
echo "  set_size: $(grep '^set_size' "$log"), window now $(size_of)"
check "set_size(700, 500) resizes the window" test "$(size_of)" = "700x500"
wait_step "fullscreen" && sleep 2
screen="$(xwininfo -root | awk '/Width:/ {w=$2} /Height:/ {h=$2} END {print w "x" h}')"
echo "  fullscreen: $(grep '^fullscreen' "$log"), window now $(size_of), screen $screen"
check "fullscreen() makes the window fill the screen" test "$(size_of)" = "$screen"
wait_step terminate || true
host_gone=1
for _ in $(seq 1 30); do pgrep -f "[s]pike-launch.sh|\./spike$" >/dev/null || { host_gone=0; break; }; sleep 1; done
check "terminate() closes the app" test "$host_gone" -eq 0
pkill -f "[.]/spike$" 2>/dev/null
sleep 10
pg_leader="$(pgrep -f "[p]gdist/bin/postgres -D .*spike" | head -1)"
if [[ -n "$pg_leader" ]]; then
    echo "  note: the app's PostgreSQL was still running 10 s after terminate(); stopping it"
    data_dir="$(tr '\0' ' ' < "/proc/$pg_leader/cmdline" | sed -E 's/.* -D ([^ ]+).*/\1/')"
    "$app_dir/pgdist/bin/pg_ctl" stop -D "$data_dir" -m fast >/dev/null 2>&1
else
    echo "  note: the app's PostgreSQL stopped with it"
fi
echo
if (( failures > 0 )); then echo "$failures window check(s) failed."; exit 1; fi
echo "All window checks passed."
