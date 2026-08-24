#!/bin/bash
set -euo pipefail
umask 077

# Alist (https://github.com/AlistGo/alist) ships a single tarball with a
# binary named alist and keeps its configuration/data under a --data directory.
# The shared binary-app library (lib/binary_app.sh) provides the lifecycle;
# this file configures it and adds Alist-specific hooks.
# See PLAN.md section 2 for the verified release asset mapping.

DOMAIN="${DOMAIN:-}"
PORT="${PORT:-5244}"
INSTALL_DIR="${INSTALL_DIR:-/opt/alist}"
DATA_DIR="${DATA_DIR:-/var/lib/alist}"
LOG_DIR="${LOG_DIR:-/var/log/alist}"
SERVICE_NAME="${SERVICE_NAME:-alist}"
SERVICE_USER="${SERVICE_USER:-alist}"
GITHUB_REPO="${GITHUB_REPO:-AlistGo/alist}"
BACKUP_DIR="${BACKUP_DIR:-/opt/alist-backups}"
BACKUP_KEEP_DAYS="${BACKUP_KEEP_DAYS:-30}"
BA_BIN_NAME="alist"
BA_ARCHIVE_TYPE="tar.gz"
BA_USE_ENV_FILE=0
BA_FIREWALL=1
BA_SERVICE_DESCRIPTION="Alist file listing service"
BA_SERVICE_ARGS="server --data ${DATA_DIR}"
BA_HEALTH_URL="http://127.0.0.1:${PORT}/"
BA_HEALTH_CODES="^(200|301|302)$"
CONFIG_KEYS=(
  DOMAIN PORT INSTALL_DIR DATA_DIR LOG_DIR SERVICE_NAME SERVICE_USER
  GITHUB_REPO BACKUP_DIR BACKUP_KEEP_DAYS INSTALLED_VERSION
)

# Alist stores its own configuration and database under DATA_DIR on first
# start, so no managed config file is written by the deployment script.

ba_asset_name() {
  local version="$1"
  printf 'alist-linux-%s.tar.gz\n' "$BA_ARCH"
}

# Remind users how to seed/rotate the administrator password after install.
ba_summary_extra() {
  echo -e "  ${BOLD}$(t app.alist.hint.admin "$DATA_DIR")${NC}"
}

# Thin lifecycle delegates over the shared binary-app library.
preflight_check() {
  bapp_preflight "$@"
}

_validate_config_values() {
  bapp_validate_cfg
}

do_install() {
  acquire_lock
  bapp_install
}

do_update() {
  acquire_lock
  bapp_update
}

do_backup() {
  acquire_lock
  bapp_backup
}

do_verify() {
  bapp_verify
}

do_restore() {
  bapp_restore
}

do_status() {
  bapp_status
}

do_uninstall() {
  acquire_lock
  bapp_uninstall
}

binary_app_bootstrap
