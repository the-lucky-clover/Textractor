#!/usr/bin/env bash
# Compatibility entry point for Textractor Pro's actual UI-test attachments.
set -euo pipefail
TEXTRACTOR_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${TEXTRACTOR_SCRIPT_DIR}/capture_screenshots_swift.sh" "$@"
