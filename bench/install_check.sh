#!/usr/bin/env bash
# Clean-install check for the desktop artifact (plan 1.3, FR-16, §16.3).
#   install_check.sh install <artifact.tar.gz>   in a fresh ubuntu container, as root: adds only what
#                                                the artifact needs to run, then checks it as a user
#   install_check.sh offline                     in the same container saved as an image and started
#                                                with --network none: checks it again, offline
#   install_check.sh local <artifact.tar.gz>     on a development machine: no packages, no user, a
#                                                throwaway HOME (so real app data is untouched)
# Each launch runs the app under Xvfb and waits for the page's own call to record_open, which proves
# the page loaded and its code reached the embedded server; app_opens then has to have grown by one,
# which proves the graph persisted across the restart. Every step is printed; the first failing step
# ends the run with exit 1. A report (packages, privileges, sizes, times) goes to $REPORT.
set -uo pipefail
mode="${1:-}"
artifact="${2:-}"
APP_USER="briefly"
APP_DIR="/opt/briefly"
REPORT="${REPORT:-/tmp/install-report.md}"
started=$SECONDS

step() { printf '\n== %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; printf '\n**Failed:** %s\n' "$*" >> "$REPORT"; exit 1; }
note() { printf '%s\n' "$*" | tee -a "$REPORT"; }

# Run a command as the app user (or as ourselves in local mode), with the app's environment.
as_user() {
    if [[ "$mode" == local ]]; then
        env HOME="$APP_HOME" XDG_DATA_HOME="$APP_HOME/.local/share" "$@"
    else
        runuser -u "$APP_USER" -- env HOME="$APP_HOME" "$@"
    fi
}

# Unresolved shared libraries of the files the app runs (`core`: the host, libwebview.so and
# PostgreSQL's programs and libraries) or of the optional PostgreSQL modules it bundles (`optional`:
# procedural languages, foreign-data wrappers, ecpg), which the app never loads.
missing_libs() {
    local files
    if [[ "$1" == core ]]; then
        files="$(find "$APP_DIR" -maxdepth 1 -type f; find "$APP_DIR/pgdist/bin" -type f; find "$APP_DIR/pgdist/lib" -maxdepth 1 -type f ! -name 'libecpg*')"
    else
        files="$(find "$APP_DIR/pgdist/lib/postgresql" -type f; find "$APP_DIR/pgdist/lib" -maxdepth 1 -type f -name 'libecpg*')"
    fi
    for f in $files; do
        file -b "$f" 2>/dev/null | grep -q ELF && ldd "$f" 2>/dev/null
    done | grep 'not found' | awk '{print $1}' | sort -u
}

# Launch the app under Xvfb, wait for the page's record_open, read app_opens, then stop the app
# with SIGTERM and stop its PostgreSQL (what a logout or reboot leaves; JD-020). Prints the count.
launch_once() {
    local label="$1" log="$WORK/app-$1.log" url="" count=""
    : > "$log"
    as_user xvfb-run -a -s "-screen 0 1280x800x24" "$APP_DIR/briefly-launch.sh" >"$log" 2>&1 &
    local runner=$!
    for _ in $(seq 1 120); do
        url="$(grep -oE 'JAC_DESKTOP_SERVING http://127\.0\.0\.1:[0-9]+/' "$log" | head -1 | cut -d' ' -f2)"
        [[ -n "$url" ]] && grep -q '"POST /function/record_open' "$log" && break
        kill -0 "$runner" 2>/dev/null || break
        sleep 1
    done
    if [[ -z "$url" ]] || ! grep -q '"POST /function/record_open' "$log"; then
        tail -30 "$log" >&2
        fail "$label: the page never called record_open (see the app log above)"
    fi
    count="$(curl -fs -X POST -H 'Content-Type: application/json' -d '{}' "${url}function/app_opens" \
        | grep -oE '"count": *[0-9]+' | grep -oE '[0-9]+$')"
    [[ -n "$count" ]] || fail "$label: app_opens did not answer at $url"
    local host
    host="$(pgrep -f "^\./briefly$|$APP_DIR/briefly$" | head -1)"
    [[ -n "$host" ]] && kill -TERM "$host" 2>/dev/null
    for _ in $(seq 1 30); do kill -0 "$runner" 2>/dev/null || break; sleep 1; done
    kill "$runner" 2>/dev/null
    local cluster
    cluster="$(find "$APP_HOME/.local/share" -maxdepth 3 -type d -path '*/pg/main' 2>/dev/null | head -1)"
    [[ -n "$cluster" ]] && as_user "$APP_DIR/pgdist/bin/pg_ctl" stop -D "$cluster" -m fast >/dev/null 2>&1
    echo "$count"
}

check_launches() {  # check_launches <first label> <second label>: two launches, the count grows by one
    local first second
    step "launch: $1"
    first="$(launch_once "$1" | tail -1)" || exit 1
    note "- $1: the page loaded and called record_open; app_opens = $first"
    step "launch: $2 (after a restart)"
    second="$(launch_once "$2" | tail -1)" || exit 1
    note "- $2: app_opens = $second"
    (( second == first + 1 )) || fail "the graph did not persist across a restart: app_opens went $first -> $second"
    note "- the graph persisted across the restart ($first -> $second)"
}

case "$mode" in
    install)
        [[ $EUID -eq 0 ]] || fail "install mode runs as root in a fresh container"
        WORK="$(mktemp -d)"
        APP_HOME="/home/$APP_USER"
        printf '# Clean install of the Briefly desktop artifact\n\n' > "$REPORT"
        step "system"
        . /etc/os-release
        note "- system: $PRETTY_NAME, $(uname -m), $(dpkg-query -f '.' -W | wc -c) packages installed"
        step "artifact"
        [[ -n "$artifact" && -f "$artifact" ]] || fail "no artifact at '${artifact}'"
        note "- artifact: $(du -h "$artifact" | cut -f1) compressed"
        step "harness packages (not counted against the app: xvfb for a display, curl, procps and file to probe)"
        export DEBIAN_FRONTEND=noninteractive
        apt-get update -qq >/dev/null || fail "apt-get update"
        apt-get install -y -qq --no-install-recommends xvfb xauth curl procps file ca-certificates >/dev/null \
            || fail "installing the harness packages"
        dpkg-query -f '${Package}\n' -W | sort > "$WORK/before.txt"
        step "user (PostgreSQL refuses to run as root, and a desktop user is not root)"
        useradd -m -s /bin/bash "$APP_USER" || fail "useradd"
        step "unpack"
        mkdir -p "$APP_DIR" && tar -xzf "$artifact" -C "$APP_DIR" || fail "unpacking the artifact"
        chown -R "$APP_USER:$APP_USER" "$APP_DIR"
        note "- installed size: $(du -sh "$APP_DIR" | cut -f1) in $APP_DIR"
        step "shared libraries the artifact needs that this system lacks"
        missing="$(missing_libs core)"
        if [[ -n "$missing" ]]; then
            note "- missing before any install: $(echo $missing | tr '\n' ' ')"
        else
            note "- missing before any install: none found by ldd"
        fi
        step "runtime packages: the WebKitGTK runtime (the package the build's development packages correspond to)"
        apt-get install -y -qq --no-install-recommends libwebkit2gtk-4.1-0 >/dev/null || fail "installing libwebkit2gtk-4.1-0"
        dpkg-query -f '${Package}\n' -W | sort > "$WORK/after.txt"
        added="$(comm -13 "$WORK/before.txt" "$WORK/after.txt" | wc -l)"
        note "- runtime packages added: libwebkit2gtk-4.1-0 and $((added - 1)) dependencies (root needed once, for apt-get)"
        still="$(missing_libs core)"
        [[ -z "$still" ]] || fail "shared libraries still missing after installing the runtime: $(echo $still)"
        note "- every shared library of the host, libwebview.so and PostgreSQL's programs resolves"
        optional="$(missing_libs optional)"
        [[ -z "$optional" ]] || note "- optional PostgreSQL modules bundled in pgdist/lib (procedural languages, foreign-data wrappers, ecpg) link libraries that are absent: $(echo $optional | tr '\n' ' '); the app does not load them"
        check_launches "first launch" "second launch"
        ;;
    offline)
        [[ $EUID -eq 0 ]] || fail "offline mode runs as root in the saved container"
        WORK="$(mktemp -d)"
        APP_HOME="/home/$APP_USER"
        step "network"
        if curl -fs --max-time 5 https://archive.ubuntu.com/ >/dev/null 2>&1; then
            fail "the network is reachable; start this phase with --network none"
        fi
        note "- offline: no route to the internet"
        check_launches "offline launch" "offline launch after a restart"
        ;;
    local)
        WORK="$(mktemp -d)"
        trap 'rm -rf "$WORK"' EXIT
        APP_HOME="$WORK/home"
        APP_DIR="$WORK/app"
        mkdir -p "$APP_HOME" "$APP_DIR"
        printf '# Local install check\n\n' > "$REPORT"
        [[ -n "$artifact" && -f "$artifact" ]] || fail "no artifact at '${artifact}'"
        command -v xvfb-run >/dev/null || fail "xvfb-run is not installed"
        tar -xzf "$artifact" -C "$APP_DIR" || fail "unpacking the artifact"
        note "- installed size: $(du -sh "$APP_DIR" | cut -f1)"
        check_launches "first launch" "second launch"
        ;;
    *)
        echo "usage: $0 install <artifact.tar.gz> | offline | local <artifact.tar.gz>" >&2
        exit 2
        ;;
esac
note "- total time: $((SECONDS - started)) s"
echo
echo "Install check passed."
