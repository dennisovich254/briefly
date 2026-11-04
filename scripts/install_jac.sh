#!/usr/bin/env bash
# Install the Jac version pinned in .jac-version from the official jaseci-labs/jac release,
# REQUIRING a matching SHA-256 (the upstream install.sh only warns if the checksum is missing).
# `jac update --self` does not work for this kind of install, so this is the way to upgrade too.
# Used by CI and by new contributors.
#   scripts/install_jac.sh                      install to ~/.local/bin
#   JAC_INSTALL_DIR=/some/dir scripts/install_jac.sh
#   JAC_RELEASE_BASE_URL=file:///dir ...        serve releases from elsewhere (used by the self-test)
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

version="$(tr -d '[:space:]' < .jac-version)"
dest="${JAC_INSTALL_DIR:-$HOME/.local/bin}"
base="${JAC_RELEASE_BASE_URL:-https://github.com/jaseci-labs/jac/releases/download}"
case "$(uname -s)-$(uname -m)" in
    Linux-x86_64)  platform="linux-x86_64" ;;
    Linux-aarch64) platform="linux-aarch64" ;;
    *) echo "unsupported platform: $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac

asset="jac-${version}-${platform}"
url="${base}/v${version}/${asset}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

echo "Downloading ${asset}..."
curl -fsSL --retry 3 -o "$tmp/$asset" "$url"
if ! curl -fsSL --retry 3 -o "$tmp/$asset.sha256" "$url.sha256"; then
    echo "no checksum file published for $asset; refusing to install" >&2
    exit 1
fi
expected="$(awk '{print $1}' "$tmp/$asset.sha256")"
actual="$(sha256sum "$tmp/$asset" | awk '{print $1}')"
if [[ -z "$expected" || "$expected" != "$actual" ]]; then
    echo "checksum mismatch for $asset: expected '$expected', got '$actual'" >&2
    exit 1
fi
echo "Checksum verified ($actual)."

# Check the version before replacing anything, so a wrong binary never overwrites a working one.
chmod 755 "$tmp/$asset"
# A fresh binary's first run prints one-time runtime-extraction lines before the version,
# so take only the "jac X.Y.Z" line.
reported="$("$tmp/$asset" --version 2>/dev/null | grep -E '^jac [0-9]' | awk '{print $2}' | head -1)"
if [[ "$reported" != "$version" ]]; then
    echo "downloaded binary reports jac '$reported', expected $version" >&2
    exit 1
fi

mkdir -p "$dest"
install -m 755 "$tmp/$asset" "$dest/jac"
echo "Installed jac $reported to $dest/jac"
