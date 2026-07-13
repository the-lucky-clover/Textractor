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

# Copy menu-bar template images into Contents/Resources/MenuBar (used by
# StatusBarController to render the system status-bar icon).
if [[ -d "Sources/Textractor/Resources/MenuBar" ]]; then
  mkdir -p "${APP_DIR}/Contents/Resources/MenuBar"
  cp -R "Sources/Textractor/Resources/MenuBar/" "${APP_DIR}/Contents/Resources/MenuBar/"
fi

# Copy the menubar popover banner image into Contents/Resources.
if [[ -f "Sources/Textractor/Resources/textractor-type.png" ]]; then
  cp "Sources/Textractor/Resources/textractor-type.png" "${APP_DIR}/Contents/Resources/textractor-type.png"
fi

# Copy the launch splash image into Contents/Resources.
if [[ -f "Sources/Textractor/Resources/textractor-splash.png" ]]; then
  cp "Sources/Textractor/Resources/textractor-splash.png" "${APP_DIR}/Contents/Resources/textractor-splash.png"
fi

# Ad-hoc sign the bundle so Gatekeeper lets the user open it via right-click → Open
if command -v codesign >/dev/null 2>&1; then
  echo "▸ Ad-hoc code-signing…"
  codesign --force --deep --sign - "$APP_DIR" 2>/dev/null \
    || codesign --force --sign - "$APP_DIR" 2>/dev/null \
    || echo "  (codesign unavailable; skipping)"
fi

# Install the finished bundle into /Applications so it's available system-wide.
# Writing there usually requires admin rights, so try a plain copy first and
# fall back to `sudo` (which will prompt for your password). Either way the
# build itself is already done, so a failed install never aborts the script.
install_to_applications() {
  local dest="/Applications/${APP_NAME}.app"
  rm -rf "$dest" 2>/dev/null || sudo rm -rf "$dest" 2>/dev/null || true
  if cp -R "$APP_DIR" "$dest" 2>/dev/null; then
    echo "▸ Installed to /Applications/${APP_NAME}.app"
  elif sudo cp -R "$APP_DIR" "$dest"; then
    echo "▸ Installed to /Applications/${APP_NAME}.app (via sudo)"
  else
    echo "  (Skipped /Applications install — copy ${APP_DIR} there manually if you want.)"
  fi
}
install_to_applications

echo ""
echo "✓ Built ${APP_DIR}"
echo ""
echo "Run it with:"
echo "  open '/Applications/${APP_NAME}.app'"
echo "  # or: open '${ROOT}/${APP_DIR}'"
echo ""
echo "Or install with:"
echo "  ./install.sh"
