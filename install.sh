#!/usr/bin/env bash
# Explicitly install the local development bundle. App Store distribution uses Xcode.
set -euo pipefail
TEXTRACTOR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${TEXTRACTOR_ROOT}/dist/Textractor Pro.app"
DEST="/Applications/Textractor Pro.app"
REPLACE=false
case "${1:-}" in
  "") ;;
  --replace) REPLACE=true ;;
  *) echo "Usage: $0 [--replace]" >&2; exit 2 ;;
esac
[[ $# -le 1 ]] || { echo "Unexpected extra arguments" >&2; exit 2; }
[[ -d "$SRC" ]] || { echo "Build first: bash '${TEXTRACTOR_ROOT}/build.sh'" >&2; exit 1; }
if [[ -e "$DEST" && "$REPLACE" != true ]]; then
  echo "An installation already exists at $DEST. Quit it, then use --replace to replace it." >&2
  exit 1
fi
codesign --verify --deep --strict "$SRC"
STAGE="$(mktemp -d /Applications/.textractor-install.XXXXXX)"
restore_on_error() {
  result=$?
  if [[ $result -ne 0 && -d "$STAGE/previous.app" && ! -e "$DEST" ]]; then
    mv "$STAGE/previous.app" "$DEST"
  fi
  rm -rf "$STAGE"
  exit "$result"
}
trap restore_on_error EXIT
ditto "$SRC" "$STAGE/Textractor Pro.app"
codesign --verify --deep --strict "$STAGE/Textractor Pro.app"
if [[ -e "$DEST" ]]; then mv "$DEST" "$STAGE/previous.app"; fi
mv "$STAGE/Textractor Pro.app" "$DEST"
/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister -f "$DEST" || true
printf 'Installed development bundle: %s\n' "$DEST"
printf '%s\n' 'Screen capture needs Screen Recording permission in System Settings.'
