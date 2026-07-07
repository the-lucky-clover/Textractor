#!/usr/bin/env bash
# Textractor build script — produces a standalone macOS .app bundle.
# Usage:  ./build.sh            (release build)
#         ./build.sh --debug    (debug build)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

CONFIG="release"
if [[ "${1:-}" == "--debug" ]]; then
  CONFIG="debug"
fi

echo "▸ Building Textractor (${CONFIG})…"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"
APP_NAME="Textractor"
APP_DIR="dist/${APP_NAME}.app"

rm -rf "$APP_DIR"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

# Copy the executable
cp "${BIN_PATH}/${APP_NAME}" "${APP_DIR}/Contents/MacOS/${APP_NAME}"

# Copy Info.plist from a path SPM won't try to bundle as a resource.
if [[ -f "Sources/Textractor/Info.plist" ]]; then
  cp "Sources/Textractor/Info.plist" "${APP_DIR}/Contents/Info.plist"
else
  echo "✗ Info.plist not found at Sources/Textractor/Info.plist"
  exit 1
fi

# Copy entitlements next to the binary so codesign picks them up if available.
if [[ -f "Sources/Textractor/Resources/Textractor.entitlements" ]]; then
  cp "Sources/Textractor/Resources/Textractor.entitlements" "${APP_DIR}/Contents/"
fi

# Copy the app icon (.icns) into Contents/Resources.
if [[ -f "Sources/Textractor/Resources/textractor.icns" ]]; then
  cp "Sources/Textractor/Resources/textractor.icns" "${APP_DIR}/Contents/Resources/"
fi

# Touch the bundle so Finder/Launch Services pick it up
touch "$APP_DIR"

# Ad-hoc sign the bundle so Gatekeeper lets the user open it via right-click → Open
if command -v codesign >/dev/null 2>&1; then
  echo "▸ Ad-hoc code-signing…"
  codesign --force --deep --sign - "$APP_DIR" 2>/dev/null \
    || codesign --force --sign - "$APP_DIR" 2>/dev/null \
    || echo "  (codesign unavailable; skipping)"
fi

echo ""
echo "✓ Built ${APP_DIR}"
echo ""
echo "Run it with:"
echo "  open '${ROOT}/${APP_DIR}'"
echo ""
echo "Or install with:"
echo "  ./install.sh"
