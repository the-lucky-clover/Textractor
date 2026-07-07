#!/usr/bin/env bash
# Installs Textractor.app to /Applications, handling Tauri's macOS bundle quirks.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
SRC="${ROOT}/dist/Textractor.app"
DEST="/Applications/Textractor.app"

if [[ ! -d "$SRC" ]]; then
  echo "✗ Build first: ./build.sh"
  exit 1
fi

echo "▸ Removing previous installation (if any)…"
rm -rf "$DEST"

echo "▸ Copying to /Applications…"
cp -R "$SRC" "$DEST"

echo "▸ Registering with Launch Services…"
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$DEST" || true

echo "▸ Clearing quarantine attribute (ad-hoc signed dev build)…"
xattr -cr "$DEST" || true

echo ""
echo "✓ Installed at ${DEST}"
echo "  Launch from Spotlight or:"
echo "  open '${DEST}'"
echo ""
echo "Required permission (one-time):"
echo "  System Settings → Privacy & Security → Screen Recording → enable Textractor"
echo "  (Cmd-Shift-2 then drag a region or press SPACE then click for window capture)"
