#!/usr/bin/env bash
# Textractor Screenshot Automation
# Captures App Store screenshots (1280x800) in all required scenes
#
# Usage:
#   ./scripts/capture_screenshots.sh              # Capture all
#   ./scripts/capture_screenshots.sh --scene 1    # Capture specific scene
#   ./scripts/capture_screenshots.sh --list       # List available scenes
#
# Requirements:
#   - App installed at /Applications/Textractor.app
#   - Screen Recording permission granted
#   - Accessibility permission granted (for UI scripting)
#   - macOS 14+

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
OUTPUT_DIR="${ROOT_DIR}/dist/screenshots"
APP_PATH="/Applications/Textractor.app"
BUNDLE_ID="com.textractor.app"

# App Store screenshot dimensions
WIDTH=1280
HEIGHT=800

mkdir -p "$OUTPUT_DIR"

# Scene definitions: each scene is an AppleScript that sets up the UI
# Returns the window bounds for capture
declare -A SCENES=(
  [1]="capture_overlay"
  [2]="window_capture"
  [3]="history_grid"
  [4]="source_code_mode"
  [5]="translation_settings"
  [6]="toast_actions"
  [7]="pii_redaction"
)

declare -A SCENE_SCRIPTS=(
  [capture_overlay]='
tell application "Textractor"
  activate
  delay 1
  -- Trigger region capture via hotkey (⌘⇧2)
  tell application "System Events"
    key code 19 using {command down, shift down} -- ⌘⇧2
  end tell
  delay 1.5
  -- Position overlay to show interesting content
  tell application "System Events" to tell process "Textractor"
    set frontmost to true
    -- The overlay covers full screen, capture a portion showing the grid
  end tell
end tell
'

  [window_capture]='
tell application "Textractor"
  activate
  delay 1
  tell application "System Events"
    key code 19 using {command down, shift down} -- ⌘⇧2
  end tell
  delay 0.5
  -- Press SPACE to switch to window mode
  tell application "System Events" to key code 49 -- SPACE
  delay 1
  -- Click on a window (we'll use Finder as target)
  tell application "Finder" to activate
  delay 0.5
  tell application "System Events" to tell process "Textractor"
    click at {600, 400}
  end tell
end tell
'

  [history_grid]='
tell application "Textractor"
  activate
  delay 1
  -- Open history window (⌘H or menu)
  tell application "System Events"
    key code 4 using {command down} -- ⌘H
  end tell
  delay 1.5
  -- Resize window for screenshot
  tell application "System Events" to tell process "Textractor"
    set frontmost to true
    tell window 1
      set size to {1280, 800}
      set position to {100, 100}
    end tell
  end tell
end tell
'

  [source_code_mode]='
tell application "Textractor"
  activate
  delay 1
  -- Open settings
  tell application "System Events"
    key code 1 using {command down, shift down} -- ⌘⇧S (or your settings shortcut)
  end tell
  delay 1
  tell application "System Events" to tell process "Textractor"
    set frontmost to true
    -- Navigate to Formatting section, enable Source Code Mode
    -- This would need UI element targeting
  end tell
end tell
'

  [translation_settings]='
tell application "Textractor"
  activate
  delay 1
  tell application "System Events"
    key code 1 using {command down, shift down} -- Settings
  end tell
  delay 1
  tell application "System Events" to tell process "Textractor"
    set frontmost to true
    -- Navigate to Translation section
  end tell
end tell
'

  [toast_actions]='
tell application "Textractor"
  activate
  delay 1
  -- Trigger a capture to show toast
  tell application "System Events"
    key code 19 using {command down, shift down}
  end tell
  delay 2
  -- Toast appears at top-right, capture it
end tell
'

  [pii_redaction]='
tell application "Textractor"
  activate
  delay 1
  tell application "System Events"
    key code 1 using {command down, shift down} -- Settings
  end tell
  delay 1
  tell application "System Events" to tell process "Textractor"
    set frontmost to true
    -- Navigate to Privacy section, enable PII Redaction
  end tell
end tell
'
)

# List scenes
list_scenes() {
  echo "Available scenes:"
  for i in "${!SCENES[@]}"; do
    echo "  $i) ${SCENES[$i]}"
  done
}

# Capture a single scene using screencapture
capture_scene() {
  local scene_name="$1"
  local output_file="$OUTPUT_DIR/${scene_name}.png"
  
  echo "📸 Capturing: $scene_name"
  
  # Run the AppleScript to set up the scene
  osascript -e "${SCENE_SCRIPTS[$scene_name]}" 2>/dev/null || true
  
  # Give UI time to settle
  sleep 1
  
  # Capture specific window or region
  # For App Store, we need clean 1280x800 captures
  screencapture -R"100,100,$WIDTH,$HEIGHT" "$output_file" 2>/dev/null
  
  if [[ -f "$output_file" ]]; then
    echo "✅ Saved: $output_file"
    # Verify dimensions
    local dims=$(sips -g pixelWidth -g pixelHeight "$output_file" 2>/dev/null | awk '/pixelWidth|pixelHeight/ {print $2}' | paste -sd 'x' -)
    echo "   Dimensions: $dims"
  else
    echo "❌ Failed to capture $scene_name"
  fi
}

# Capture all scenes
capture_all() {
  echo "🎬 Starting screenshot capture for all scenes..."
  echo "   Output: $OUTPUT_DIR"
  echo "   Target: ${WIDTH}x${HEIGHT}"
  echo ""
  
  # Ensure app is running
  if ! pgrep -x "Textractor" >/dev/null; then
    echo "🚀 Launching Textractor..."
    open "$APP_PATH"
    sleep 3
  fi
  
  for i in "${!SCENES[@]}"; do
    capture_scene "${SCENES[$i]}"
    echo ""
  done
  
  echo "🎉 Done! Screenshots in: $OUTPUT_DIR"
  ls -la "$OUTPUT_DIR"/*.png 2>/dev/null || echo "No screenshots captured"
}

# Main
SCENE_NUM=""
while [[ $# -gt 0 ]]; do
  case $1 in
    --scene)
      SCENE_NUM="$2"
      shift 2
      ;;
    --list)
      list_scenes
      exit 0
      ;;
    --help|-h)
      echo "Usage: $0 [--scene N] [--list]"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

if [[ -n "$SCENE_NUM" ]]; then
  if [[ -z "${SCENES[$SCENE_NUM]:-}" ]]; then
    echo "❌ Invalid scene number: $SCENE_NUM"
    list_scenes
    exit 1
  fi
  capture_scene "${SCENES[$SCENE_NUM]}"
else
  capture_all
fi