#!/usr/bin/env bash
# Install the gitleaks version the pre-commit hook uses (keep in sync with the gitleaks `rev` in
# .pre-commit-config.yaml), requiring a matching SHA-256. Used by CI.
#   scripts/install_gitleaks.sh                        install to ~/.local/bin
#   GITLEAKS_INSTALL_DIR=/some/dir scripts/install_gitleaks.sh
set -euo pipefail
version="8.30.1"
dest="${GITLEAKS_INSTALL_DIR:-$HOME/.local/bin}"
asset="gitleaks_${version}_linux_x64.tar.gz"
base="https://github.com/gitleaks/gitleaks/releases/download/v${version}"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

curl -fsSL --retry 3 -o "$tmp/$asset" "$base/$asset"
curl -fsSL --retry 3 -o "$tmp/checksums.txt" "$base/gitleaks_${version}_checksums.txt"
(cd "$tmp" && grep " ${asset}\$" checksums.txt | sha256sum -c -)
tar -xzf "$tmp/$asset" -C "$tmp" gitleaks
mkdir -p "$dest" && install -m 755 "$tmp/gitleaks" "$dest/gitleaks"
echo "Installed gitleaks $("$dest/gitleaks" version) to $dest/gitleaks"
