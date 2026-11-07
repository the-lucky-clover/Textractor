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
if [[ "$CONFIG" == "release" && -f "Sources/Textractor/Resources/Textractor.release.entitlements" ]]; then
  cp "Sources/Textractor/Resources/Textractor.release.entitlements" "${APP_DIR}/Contents/Textractor.entitlements"
elif [[ -f "Sources/Textractor/Resources/Textractor.entitlements" ]]; then
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

# Copy .png images into Contents/Resources.
for img in textractor-type.png textractor-splash.png textractor-navbar-final.png textractor-beaker.png; do
  if [[ -f "Sources/Textractor/Resources/${img}" ]]; then
    cp "Sources/Textractor/Resources/${img}" "${APP_DIR}/Contents/Resources/${img}"
  fi
done

# Copy .lproj localization directories into Contents/Resources.
if [[ -d "Sources/Textractor/Resources" ]]; then
  for lproj in "Sources/Textractor/Resources/"*.lproj; do
    [[ -d "$lproj" ]] || continue
    mkdir -p "${APP_DIR}/Contents/Resources/$(basename "$lproj")"
    cp -R "${lproj}/" "${APP_DIR}/Contents/Resources/$(basename "$lproj")/"
  done
fi

# Include SPM resources; Bundle.module resolves this bundle beside the executable.
for bundle in "${BIN_PATH}/"*.bundle; do
  [[ -d "$bundle" ]] || continue
  cp -R "$bundle" "${APP_DIR}/Contents/Resources/"
done

if command -v codesign >/dev/null 2>&1; then
  codesign --force --deep --sign - "$APP_DIR"
  codesign --verify --deep --strict "$APP_DIR"
fi

# Build never installs or deletes an installed app. Installation is explicit.
echo "Built ${APP_DIR} (development signature; not notarized)."
echo "Run: open '${ROOT}/${APP_DIR}'"
echo "Install separately: ./install.sh"
