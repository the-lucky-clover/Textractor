#!/usr/bin/env bash
# Compatibility entry point. Default is archive only; --action upload is explicit.
set -euo pipefail
TEXTRACTOR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec bash "${TEXTRACTOR_ROOT}/scripts/archive_appstore.sh" "$@"
