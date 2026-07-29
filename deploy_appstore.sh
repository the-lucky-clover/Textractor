#!/usr/bin/env bash
# Textractor – automatic Mac App Store upload
# Usage: ./deploy_appstore.sh [--debug|--skip-upload]

set -euo pipefail

APP_NAME="Textractor"
BUILD_DIR="dist/${APP_NAME}.app"
ZIP_PATH="dist/${APP_NAME}.zip"
ENTITLEMENTS="Sources/Textractor/Resources/Textractor.release.entitlements"

# ---- 1. Pick signing identity -------------------------------------------------
IDENTITY=$(security find-identity -v -p codesigning \
  | grep -E '3rd Party Mac Developer Application|Developer ID Application' \
  | head -1 | sed -E 's/.*"([^"]+)".*/\1/')

if [[ -z "$IDENTITY" ]]; then
  echo "⚠️  No Mac App Store / Developer ID cert found."
  echo "    Falling back to any available identity (will NOT be accepted by App Store)."
  IDENTITY=$(security find-identity -v -p codesigning | head -1 | sed -E 's/.*"([^"]+)".*/\1/')
fi

if [[ -z "$IDENTITY" ]]; then
  echo "❌ No code-signing identity in keychain – aborting."
  exit 1
fi
echo "✅ Using identity: $IDENTITY"

# ---- 2. Build -----------------------------------------------------------------
CONFIG="release"
if [[ "${1:-}" == "--debug" ]]; then
  CONFIG="debug"
fi
echo "🏗  Building ($CONFIG)…"
./build.sh --"$CONFIG"

# ---- 3. Hardened-runtime codesign --------------------------------------------
echo "🔏  Codesigning with hardened runtime…"
codesign --force --deep --timestamp --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --sign "$IDENTITY" \
  "$BUILD_DIR"

# ---- 4. Create upload zip -----------------------------------------------------
echo "📦  Creating upload zip…"
ditto -c -k --keepParent "$BUILD_DIR" "$ZIP_PATH"

# ---- 5. Upload with altool ----------------------------------------------------
if [[ "${1:-}" == "--skip-upload" || "${2:-}" == "--skip-upload" ]]; then
  echo "⏭️  Skipping upload (as requested)."
else
  echo "🚀  Uploading to App Store Connect…"
  # altool reads ~/.netrc automatically for api.appstoreconnect.apple.com
  xcrun altool --upload-app \
    --type macos \
    --file "$ZIP_PATH" \
    --output-format xml \
    --output /tmp/altool-output.xml

  REQUEST_UUID=$(xmllint --xpath "//uploadResult/status/@requestUUID" /tmp/altool-output.xml 2>/dev/null | sed -E 's/.*requestUUID="([^"]+)".*/\1/')
  if [[ -n "$REQUEST_UUID" ]]; then
    echo "✅ Upload accepted! Request UUID: $REQUEST_UUID"
    echo "   Monitor at: https://appstoreconnect.apple.com/expectations/1/$REQUEST_UUID"
  else
    echo "❌ Upload failed – check /tmp/altool-output.xml"
    exit 1
  fi
fi

echo "🎉  Done! Signed app at: $BUILD_DIR"
echo "   Test locally with: open $BUILD_DIR"