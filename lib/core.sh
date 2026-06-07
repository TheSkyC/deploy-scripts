#!/usr/bin/env bash

DEPLOY_FRAMEWORK_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT_DIR="${DEPLOY_ROOT_DIR:-$(cd -- "${DEPLOY_FRAMEWORK_DIR}/.." && pwd)}"

source "${DEPLOY_FRAMEWORK_DIR}/i18n.sh"
source "${DEPLOY_FRAMEWORK_DIR}/logging.sh"
source "${DEPLOY_FRAMEWORK_DIR}/fs.sh"
source "${DEPLOY_FRAMEWORK_DIR}/lock.sh"
source "${DEPLOY_FRAMEWORK_DIR}/config.sh"
source "${DEPLOY_FRAMEWORK_DIR}/service.sh"
source "${DEPLOY_FRAMEWORK_DIR}/network.sh"
source "${DEPLOY_FRAMEWORK_DIR}/legacy.sh"
source "${DEPLOY_FRAMEWORK_DIR}/cli.sh"

main() {
  dispatch_action "${1:-menu}"
}
