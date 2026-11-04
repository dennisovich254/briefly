#!/usr/bin/env bash
# Install the actionlint version the pre-commit hook uses (keep in sync with the rhysd/actionlint
# `rev` in .pre-commit-config.yaml), requiring a matching SHA-256. Used by CI.
#   scripts/install_actionlint.sh                          install to ~/.local/bin
#   ACTIONLINT_INSTALL_DIR=/some/dir scripts/install_actionlint.sh
set -euo pipefail
version="1.7.12"
dest="${ACTIONLINT_INSTALL_DIR:-$HOME/.local/bin}"
asset="actionlint_${version}_linux_amd64.tar.gz"
base="https://github.com/rhysd/actionlint/releases/download/v${version}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

curl -fsSL --retry 3 -o "$tmp/$asset" "$base/$asset"
curl -fsSL --retry 3 -o "$tmp/checksums.txt" "$base/actionlint_${version}_checksums.txt"
(cd "$tmp" && grep " ${asset}\$" checksums.txt | sha256sum -c -)
tar -xzf "$tmp/$asset" -C "$tmp" actionlint
mkdir -p "$dest" && install -m 755 "$tmp/actionlint" "$dest/actionlint"
echo "Installed actionlint $("$dest/actionlint" -version | head -1) to $dest/actionlint"
