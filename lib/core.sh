#!/usr/bin/env bash

DEPLOY_FRAMEWORK_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_ROOT_DIR="${DEPLOY_ROOT_DIR:-$(cd -- "${DEPLOY_FRAMEWORK_DIR}/.." && pwd)}"

source "${DEPLOY_FRAMEWORK_DIR}/i18n.sh"
source "${DEPLOY_FRAMEWORK_DIR}/logging.sh"
source "${DEPLOY_FRAMEWORK_DIR}/fs.sh"
source "${DEPLOY_FRAMEWORK_DIR}/atomic.sh"
source "${DEPLOY_FRAMEWORK_DIR}/binary.sh"
source "${DEPLOY_FRAMEWORK_DIR}/lock.sh"
source "${DEPLOY_FRAMEWORK_DIR}/config.sh"
source "${DEPLOY_FRAMEWORK_DIR}/service.sh"
source "${DEPLOY_FRAMEWORK_DIR}/network.sh"
source "${DEPLOY_FRAMEWORK_DIR}/version.sh"
source "${DEPLOY_FRAMEWORK_DIR}/operation.sh"
source "${DEPLOY_FRAMEWORK_DIR}/state.sh"
source "${DEPLOY_FRAMEWORK_DIR}/manager_status.sh"
source "${DEPLOY_FRAMEWORK_DIR}/manager_history.sh"
source "${DEPLOY_FRAMEWORK_DIR}/manager_doctor.sh"
source "${DEPLOY_FRAMEWORK_DIR}/app.sh"
source "${DEPLOY_FRAMEWORK_DIR}/binary_app.sh"
source "${DEPLOY_FRAMEWORK_DIR}/app_registry.sh"
source "${DEPLOY_FRAMEWORK_DIR}/app_loader.sh"
source "${DEPLOY_FRAMEWORK_DIR}/cli.sh"
source "${DEPLOY_FRAMEWORK_DIR}/manager_cli.sh"

main() {
  dispatch_action "${1:-menu}"
}
