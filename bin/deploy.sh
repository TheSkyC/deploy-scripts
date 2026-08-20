#!/usr/bin/env bash
set -euo pipefail

SCRIPT_PATH="${BASH_SOURCE[0]}"
if command -v readlink >/dev/null 2>&1 && resolved_script_path="$(readlink -f -- "$SCRIPT_PATH" 2>/dev/null)" && [[ -n "$resolved_script_path" ]]; then
  SCRIPT_PATH="$resolved_script_path"
fi
SCRIPT_DIR="$(cd -- "$(dirname -- "$SCRIPT_PATH")" && pwd)"
DEPLOY_ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

source "${DEPLOY_ROOT_DIR}/lib/core.sh"

manager_main "$@"
