#!/usr/bin/env bash
# Capture actual Textractor Pro development UI via the existing XCTest suite.
# These attachments are QA evidence, not approved App Store screenshots.
set -euo pipefail
TEXTRACTOR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$TEXTRACTOR_ROOT"
SCENES=(
  testUSEnglishPersistsAfterRelaunch
  testTourSkipAndReplay
  testCameraCancellationReturnsToSettings
  testCaptureOverlayActivatesAndEscapeReturnsToSettings
)
TEST_SELECTION=TextractorUITests/SettingsPlaytests
case "${1:-}" in
  --list)
    printf '%s\n' "${SCENES[@]}"
    exit 0
    ;;
  --test)
    [[ $# -eq 2 ]] || { echo "Usage: $0 [--list|--test TEST_NAME]" >&2; exit 2; }
    valid=false
    for name in "${SCENES[@]}"; do
      if [[ "$name" == "$2" ]]; then valid=true; fi
    done
    [[ "$valid" == true ]] || { echo "Unknown test; use --list." >&2; exit 2; }
    TEST_SELECTION="${TEST_SELECTION}/$2"
    ;;
  "") ;;
  --help|-h)
    echo "Usage: $0 [--list|--test TEST_NAME]"
    exit 0
    ;;
  *) echo "Usage: $0 [--list|--test TEST_NAME]" >&2; exit 2 ;;
esac
for tool in xcodegen xcodebuild xcrun python3; do
  command -v "$tool" >/dev/null || { echo "Required tool is missing: $tool" >&2; exit 1; }
done
mkdir -p dist/screenshots
RUN_DIR="$(mktemp -d "${TEXTRACTOR_ROOT}/dist/screenshots/run.XXXXXX")"
RESULT="${RUN_DIR}/playtests.xcresult"
xcodegen generate --spec "${TEXTRACTOR_ROOT}/project.yml"
set +e
xcodebuild test \
  -project "${TEXTRACTOR_ROOT}/Textractor.xcodeproj" \
  -scheme Textractor -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "${RUN_DIR}/DerivedData" -resultBundlePath "$RESULT" \
  "-only-testing:${TEST_SELECTION}" CODE_SIGNING_ALLOWED=NO 2>&1 | tee "${RUN_DIR}/tests.log"
TEST_STATUS=${PIPESTATUS[0]}
set -e
if [[ -d "$RESULT" ]]; then
  xcrun xcresulttool export attachments --path "$RESULT" --output-path "${RUN_DIR}/attachments"
else
  echo "Xcode produced no result bundle; inspect ${RUN_DIR}/tests.log" >&2
  exit 1
fi
cat > "${RUN_DIR}/README.txt" <<'NOTE'
Textractor Pro development UI attachments

Images here were exported from the XCTest result bundle for this run. The tests
exercise the Debug UI, not a distribution-signed sandboxed app. Test failures
remain in tests.log and the result bundle. Inspect each image before use.
These are not automatically approved or resized App Store screenshots; final
listing screenshots must show the shipping build and complete review separately.
NOTE
python3 - "${RUN_DIR}/attachments" <<'CHECK'
from pathlib import Path
import sys
images = list(Path(sys.argv[1]).rglob('*.png'))
if not images:
    raise SystemExit('No PNG attachments were exported; inspect the Xcode result bundle.')
print(f'Exported {len(images)} actual UI-test PNG attachments to {sys.argv[1]}')
CHECK
exit "$TEST_STATUS"
