#!/usr/bin/env bash
# Archive by default. Export and upload each require an explicit --action.
set -euo pipefail
TEXTRACTOR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 "${TEXTRACTOR_ROOT}/scripts/appstore_release.py" "$@"
