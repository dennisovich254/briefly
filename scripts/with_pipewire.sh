#!/usr/bin/env bash
# Run a command inside a private PipeWire session: its own runtime directory, PipeWire and
# WirePlumber, so the audio capture tests (tests/audio/) run where no desktop session exists (CI)
# and never touch the user's own audio. Fails if PipeWire does not come up, so those tests cannot
# silently skip. Call it under a private D-Bus session:
#   dbus-run-session -- scripts/with_pipewire.sh scripts/test.sh
set -uo pipefail
for tool in pipewire wireplumber pw-cli; do
    command -v "$tool" >/dev/null || { echo "with_pipewire: $tool is not installed"; exit 2; }
done
runtime="$(mktemp -d -t briefly-pw-XXXXXX)"
chmod 700 "$runtime"
export XDG_RUNTIME_DIR="$runtime"
unset PIPEWIRE_REMOTE PULSE_SERVER
# No hardware: the private session must not open the machine's sound card or Bluetooth (CI has
# none, and locally they belong to the user's own session). WirePlumber 0.5 reads the .conf,
# 0.4 (Ubuntu 24.04, CI) the Lua file; each ignores the other.
export XDG_CONFIG_HOME="$runtime/config"
mkdir -p "$XDG_CONFIG_HOME/wireplumber/wireplumber.conf.d" "$XDG_CONFIG_HOME/wireplumber/main.lua.d" \
    "$XDG_CONFIG_HOME/wireplumber/bluetooth.lua.d"
cat >"$XDG_CONFIG_HOME/wireplumber/wireplumber.conf.d/90-no-hardware.conf" <<'CONF'
wireplumber.profiles = {
  main = {
    monitor.alsa = disabled
    monitor.alsa-midi = disabled
    monitor.bluez = disabled
    monitor.v4l2 = disabled
    monitor.libcamera = disabled
  }
}
CONF
printf 'alsa_monitor.enabled = false\nv4l2_monitor.enabled = false\nlibcamera_monitor.enabled = false\n' \
    >"$XDG_CONFIG_HOME/wireplumber/main.lua.d/90-no-hardware.lua"
printf 'bluez_monitor.enabled = false\n' >"$XDG_CONFIG_HOME/wireplumber/bluetooth.lua.d/90-no-hardware.lua"
pipewire >"$runtime/pipewire.log" 2>&1 &
pw=$!
wireplumber >"$runtime/wireplumber.log" 2>&1 &
wp=$!
cleanup() { kill "$wp" "$pw" 2>/dev/null; wait "$wp" "$pw" 2>/dev/null; rm -rf "$runtime"; }
trap cleanup EXIT
for _ in $(seq 1 50); do
    pw-cli info 0 >/dev/null 2>&1 && break
    sleep 0.2
done
if ! pw-cli info 0 >/dev/null 2>&1; then
    echo "with_pipewire: PipeWire did not start"
    tail -5 "$runtime/pipewire.log" "$runtime/wireplumber.log"
    exit 2
fi
echo "with_pipewire: PipeWire $(pipewire --version | grep -oE 'libpipewire [0-9.]+' | head -1 | cut -d' ' -f2) running in $runtime"
"$@"
