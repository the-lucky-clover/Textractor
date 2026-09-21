#!/usr/bin/env bash
# Textractor Screenshot Automation - Swift-based (more reliable)
# Uses the app's own UI testing target to drive screenshots
#
# Usage:
#   ./scripts/capture_screenshots_swift.sh          # Capture all
#   ./scripts/capture_screenshots_swift.sh --list   # List scenes

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${ROOT_DIR}/dist/screenshots"
DERIVED_DATA="${ROOT_DIR}/build/Screenshots"

mkdir -p "$OUTPUT_DIR"

# Scene definitions matching the Swift test cases
SCENES=(
  "testCaptureOverlay"
  "testWindowCapture"
  "testHistoryGrid"
  "testSourceCodeMode"
  "testTranslationSettings"
  "testToastActions"
  "testPIIRedaction"
)

SCENE_NAMES=(
  "01-capture-overlay"
  "02-window-capture"
  "03-history-grid"
  "04-source-code-mode"
  "05-translation-settings"
  "06-toast-actions"
  "07-pii-redaction"
)

capture_with_xcodebuild() {
  local test_name="$1"
  local output_name="$2"
  
  echo "📸 Running UI test: $test_name"
  
  # Build and run the specific UI test
  xcodebuild test \
    -scheme Textractor \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    -only-testing:TextractorUITests/ScreenshotTests/"$test_name" \
    2>&1 | tail -20
  
  # The test should save screenshot to OUTPUT_DIR
  local screenshot_path="${DERIVED_DATA}/Attachments/${output_name}.png"
  if [[ -f "$screenshot_path" ]]; then
    cp "$screenshot_path" "$OUTPUT_DIR/${output_name}.png"
    echo "✅ Saved: $OUTPUT_DIR/${output_name}.png"
  else
    echo "⚠️  Screenshot not found at expected path"
    # Try to find it
    find "$DERIVED_DATA" -name "*.png" -newer "$DERIVED_DATA" 2>/dev/null | head -5
  fi
}

capture_all() {
  echo "🎬 Starting Swift-based screenshot capture..."
  echo "   Output: $OUTPUT_DIR"
  echo ""
  
  for i in "${!SCENES[@]}"; do
    capture_with_xcodebuild "${SCENES[$i]}" "${SCENE_NAMES[$i]}"
    echo ""
  done
  
  echo "🎉 Done! Screenshots in: $OUTPUT_DIR"
  ls -la "$OUTPUT_DIR"/*.png 2>/dev/null
}

# Main
if [[ "${1:-}" == "--list" ]]; then
  echo "Available test scenes:"
  for i in "${!SCENES[@]}"; do
    echo "  ${SCENES[$i]} -> ${SCENE_NAMES[$i]}.png"
  done
  exit 0
fi

capture_all