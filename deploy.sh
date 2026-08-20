#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1 && resolved_script_path="$(readlink -f -- "$SCRIPT_PATH" 2>/dev/null)" && [[ -n "$resolved_script_path" ]]; then
  SCRIPT_PATH="$resolved_script_path"
fi
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
exec bash "${SCRIPT_DIR}/bin/deploy.sh" "$@"
