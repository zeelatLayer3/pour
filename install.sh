#!/bin/bash
# Installs the latest Pour release into Applications and opens it.
# Files fetched with curl aren't quarantined, so Gatekeeper doesn't block the unnotarized build.
set -euo pipefail

REPO="zeelatLayer3/pour"
URL="https://github.com/$REPO/releases/latest/download/Pour.zip"

if [[ "$(uname)" != "Darwin" ]]; then
  echo "Pour is a macOS app." >&2
  exit 1
fi

major=$(sw_vers -productVersion | cut -d. -f1)
if (( major < 14 )); then
  echo "Pour needs macOS 14 Sonoma or later. This Mac has $(sw_vers -productVersion)." >&2
  exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

echo "Downloading Pour..."
curl -fsSL "$URL" -o "$tmp/Pour.zip"
ditto -x -k "$tmp/Pour.zip" "$tmp"

dest="/Applications"
if [[ ! -w "$dest" ]]; then
  dest="$HOME/Applications"
  mkdir -p "$dest"
fi

pkill -x Pour 2>/dev/null || true
rm -rf "$dest/Pour.app"
ditto "$tmp/Pour.app" "$dest/Pour.app"
xattr -dr com.apple.quarantine "$dest/Pour.app" 2>/dev/null || true

open "$dest/Pour.app"
echo "Pour is installed in $dest. Look for the cup near the clock in your menu bar."
