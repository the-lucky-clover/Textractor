#!/usr/bin/env bash
# Textractor – automatic Mac App Store upload
# Usage: ./deploy_appstore.sh [--debug|--skip-upload|--skip-notarize]
#
# Prerequisites:
# 1. Apple Developer Program membership ($99/year)
# 2. Mac App Store distribution certificate in keychain
# 3. App Store Connect API key (Issuer ID, Key ID, .p8 file) or App-specific password
# 4. App record created in App Store Connect with matching Bundle ID

set -euo pipefail

APP_NAME="Textractor"
BUILD_DIR="dist/${APP_NAME}.app"
ZIP_PATH="dist/${APP_NAME}.zip"
ENTITLEMENTS="Sources/Textractor/Resources/Textractor.release.entitlements"

# ---- Config -------------------------------------------------------------------
# Set these as environment variables or in ~/.netrc for API key auth
# export ASC_API_ISSUER_ID="your-issuer-id"
# export ASC_API_KEY_ID="your-key-id"
# export ASC_API_KEY_PATH="path/to/AuthKey_XXXXXXXXXX.p8"
# OR for password auth:
# export ASC_APP_PASSWORD="@keychain:AC_PASSWORD"  # stored in keychain

# ---- 1. Pick signing identity -------------------------------------------------
IDENTITY=$(security find-identity -v -p codesigning \
  | grep -E '3rd Party Mac Developer Application' \
  | head -1 | sed -E 's/.*"([^"]+)".*/\1/')

if [[ -z "$IDENTITY" ]]; then
  echo "⚠️  No '3rd Party Mac Developer Application' cert found."
  echo "    Mac App Store submission REQUIRES this certificate."
  echo "    Get it from: https://developer.apple.com/account/resources/certificates/list"
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
echo "🔏  Codesigning with hardened runtime + App Sandbox…"
codesign --force --deep --timestamp --options runtime \
  --entitlements "$ENTITLEMENTS" \
  --sign "$IDENTITY" \
  "$BUILD_DIR"

# Verify signature
echo "🔍  Verifying signature…"
codesign --verify --deep --strict --verbose=2 "$BUILD_DIR"
spctl --assess --type execute --verbose "$BUILD_DIR"

# ---- 4. Create upload zip -----------------------------------------------------
echo "📦  Creating upload zip…"
ditto -c -k --keepParent "$BUILD_DIR" "$ZIP_PATH"

# ---- 5. Notarization (required for Mac App Store) ------------------------------
if [[ ! "${1:-}" == "--skip-notarize" && ! "${2:-}" == "--skip-notarize" ]]; then
  echo "📝  Submitting for notarization…"
  
  if [[ -n "${ASC_API_ISSUER_ID:-}" && -n "${ASC_API_KEY_ID:-}" && -n "${ASC_API_KEY_PATH:-}" ]]; then
    # API Key authentication (recommended)
    xcrun notarytool submit "$ZIP_PATH" \
      --issuer "$ASC_API_ISSUER_ID" \
      --key-id "$ASC_API_KEY_ID" \
      --key "$ASC_API_KEY_PATH" \
      --wait \
      --output-format json
  elif [[ -n "${ASC_APP_PASSWORD:-}" ]]; then
    # App-specific password authentication (legacy)
    xcrun notarytool submit "$ZIP_PATH" \
      --apple-id "$(whoami)@icloud.com" \  # Set your Apple ID
      --password "$ASC_APP_PASSWORD" \
      --team-id "$(security find-identity -v -p codesigning | grep '3rd Party Mac Developer' | head -1 | sed -E 's/.*\(([^)]+)\).*/\1/')" \
      --wait \
      --output-format json
  else
    echo "⚠️  Notarization skipped - set ASC_API_ISSUER_ID/ASC_API_KEY_ID/ASC_API_KEY_PATH"
    echo "   or ASC_APP_PASSWORD in environment"
  fi
  
  # Staple the notarization ticket
  echo "📎  Stapling notarization ticket…"
  xcrun stapler staple "$BUILD_DIR"
  xcrun stapler validate "$BUILD_DIR"
fi

# ---- 6. Upload to App Store Connect -------------------------------------------
if [[ ! "${1:-}" == "--skip-upload" && ! "${2:-}" == "--skip-upload" ]]; then
  echo "🚀  Uploading to App Store Connect via Transporter (xcrun altool is deprecated)…"
  
  if [[ -n "${ASC_API_ISSUER_ID:-}" && -n "${ASC_API_KEY_ID:-}" && -n "${ASC_API_KEY_PATH:-}" ]]; then
    xcrun transporter upload \
      --issuer "$ASC_API_ISSUER_ID" \
      --key-id "$ASC_API_KEY_ID" \
      --key "$ASC_API_KEY_PATH" \
      --file "$ZIP_PATH" \
      --output-format json
  else
    echo "⚠️  Upload skipped - set ASC_API_ISSUER_ID/ASC_API_KEY_ID/ASC_API_KEY_PATH"
    echo "   Or upload manually via Transporter.app"
  fi
fi

echo ""
echo "🎉  Done! Signed & notarized app at: $BUILD_DIR"
echo "   Test locally with: open \"$BUILD_DIR\""
echo ""
echo "Next steps for App Store submission:"
echo "  1. Create app record in App Store Connect (if not done)"
echo "  2. Fill in metadata: screenshots, description, keywords, privacy policy URL"
echo "  3. Set pricing/availability"
echo "  4. Submit for review"
echo ""
echo "Privacy Policy URL for App Store Connect:"
echo "  https://github.com/the-lucky-clover/Textractor/blob/main/PRIVACY_POLICY.md"