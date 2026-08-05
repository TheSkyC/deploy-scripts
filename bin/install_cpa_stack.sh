#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT_DIR="$(cd -- "${SCRIPT_DIR}/.." && pwd)"

source "${DEPLOY_ROOT_DIR}/lib/core.sh"
source "${DEPLOY_ROOT_DIR}/apps/cpa_stack.sh"

main "$@"
