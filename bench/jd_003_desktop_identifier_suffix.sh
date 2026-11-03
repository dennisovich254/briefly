#!/usr/bin/env bash
# Canary for JD-003: in a workspace, the desktop build appends ANOTHER app's name to
# [desktop] identifier, so the app's data directory is named after that app.
# Builds a throwaway workspace (a desktop app plus a web app named "zzz") and reads the identifier
# the generated desktop host boots with. Needs the desktop build packages (pkg-config, libgtk-3-dev,
# libwebkit2gtk-4.1-dev) and about a minute.
# Exit 0 = the finding still holds (identifier ends in ".zzz"); exit 1 = it changed: re-check JD-003.
set -uo pipefail
work="$(mktemp -d)"; trap 'rm -rf "$work"' EXIT
mkdir -p "$work/hosts/desktop" && cd "$work" || exit 2
version="$(jac --version | grep -E '^jac [0-9]' | awk '{print $2}')"
cat > jac.toml <<EOF
[project]
name = "repro"
version = "0.1.0"
jac-version = "==$version"
default-app = "desktop"

[apps.desktop]
kind = "desktop"
entry-point = "hosts.desktop.main"

[apps.zzz]
kind = "web-app"
entry-point = "main"

[dependencies.npm]
react = "^19.2.0"
react-dom = "^19.2.0"

[dependencies.npm.dev]
vite = "^6.4.1"
"@vitejs/plugin-react" = "^4.7.0"

[desktop]
name = "repro"
identifier = "org.example.repro"
EOF
printf 'def:pub app -> JsxElement {\n    <p>web</p>\n}\n' > main.jac
printf 'def:pub app -> JsxElement {\n    <p>desktop</p>\n}\n' > hosts/desktop/main.jac
jac install >/dev/null 2>&1 && jac build desktop >/dev/null 2>&1 || { echo "build failed"; exit 2; }
identifier="$(grep -o 'identifier[^,]*' .jac/client/desktop/desktop/host.jac | head -1 | sed 's/.*: *\\*"\([^\\"]*\)\\*".*/\1/')"
echo "jac $version: desktop host identifier = $identifier"
if [[ "$identifier" == "org.example.repro.zzz" ]]; then echo "HOLDS: the web app's name was appended"; exit 0; fi
echo "CHANGED: re-check JD-003"; exit 1
