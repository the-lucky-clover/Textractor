#!/usr/bin/env bash
# Textractor Pro development build — produces an ad-hoc standalone macOS bundle.
# App Store archives use scripts/archive_appstore.sh instead.
# Usage:  ./build.sh            (release build)
#         ./build.sh --debug    (debug build)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

[[ "$(uname -s)" == "Darwin" ]] || { echo "Textractor Pro builds require macOS and Xcode command-line tools." >&2; exit 1; }

CONFIG="release"
case "${1:-}" in
  ""|--release) ;;
  --debug) CONFIG="debug" ;;
  *) echo "Usage: $0 [--debug|--release]" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { echo "Unexpected extra arguments" >&2; exit 2; }

echo "▸ Building Textractor Pro (${CONFIG}, development bundle)…"
swift build -c "$CONFIG"

BIN_PATH="$(swift build -c "$CONFIG" --show-bin-path)"
APP_NAME="Textractor Pro"
EXECUTABLE_NAME="Textractor"
APP_DIR="dist/${APP_NAME}.app"

rm -rf "$APP_DIR"
mkdir -p "${APP_DIR}/Contents/MacOS"
mkdir -p "${APP_DIR}/Contents/Resources"

# Copy the executable
cp "${BIN_PATH}/${EXECUTABLE_NAME}" "${APP_DIR}/Contents/MacOS/${EXECUTABLE_NAME}"

# Copy Info.plist from a path SPM won't try to bundle as a resource.
if [[ -f "Sources/Textractor/Info.plist" ]]; then
  cp "Sources/Textractor/Info.plist" "${APP_DIR}/Contents/Info.plist"
else
  echo "✗ Info.plist not found at Sources/Textractor/Info.plist"
  exit 1
fi

# Xcode expands these settings for archives. SPM does not process Info.plist.
python3 - "${APP_DIR}/Contents/Info.plist" <<'PY'
import os, plistlib, re, sys
path = sys.argv[1]
with open(path, 'rb') as stream:
    info = plistlib.load(stream)
for key, variable, fallback in (
    ('CFBundleShortVersionString', 'MARKETING_VERSION', '2.0.0'),
    ('CFBundleVersion', 'CURRENT_PROJECT_VERSION', '2000'),
):
    value = os.environ.get(variable, fallback)
    if not re.fullmatch(r'[0-9]+(?:\.[0-9]+){0,2}', value):
        raise SystemExit(f'Invalid {variable}: use one to three numeric components')
    info[key] = value
with open(path, 'wb') as stream:
    plistlib.dump(info, stream)
PY

# Privacy manifests must also be at the app resource root, not just an SPM bundle.
cp "Sources/Textractor/Resources/PrivacyInfo.xcprivacy" "${APP_DIR}/Contents/Resources/PrivacyInfo.xcprivacy"

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

# Retain the SPM resource bundle for explicit bundle lookup. App UI assets and
# localizations are also copied above for Bundle.main lookup after installation.
for bundle in "${BIN_PATH}/"*.bundle; do
  [[ -d "$bundle" ]] || continue
  cp -R "$bundle" "${APP_DIR}/Contents/Resources/"
done

python3 scripts/verify_macos_bundle.py "$APP_DIR"
codesign --force --deep --sign - "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

# Build never installs or deletes an installed app. Installation is explicit.
echo "Built ${APP_DIR} (development signature; not notarized)."
echo "Run: open '${ROOT}/${APP_DIR}'"
echo "Install separately: ./install.sh"
