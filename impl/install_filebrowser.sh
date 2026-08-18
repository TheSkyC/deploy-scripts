#!/bin/bash
set -euo pipefail
umask 077

# Filebrowser (https://github.com/filebrowser/filebrowser) ships a tarball
# with a binary named filebrowser and serves a configurable root directory.
# The shared binary-app library (lib/binary_app.sh) provides the lifecycle;
# this file configures it and adds Filebrowser-specific hooks.
# See PLAN.md section 2 for the verified release asset mapping.

DOMAIN="${DOMAIN:-}"
PORT="${PORT:-8081}"
INSTALL_DIR="${INSTALL_DIR:-/opt/filebrowser}"
DATA_DIR="${DATA_DIR:-/var/lib/filebrowser}"
LOG_DIR="${LOG_DIR:-/var/log/filebrowser}"
SERVICE_NAME="${SERVICE_NAME:-filebrowser}"
SERVICE_USER="${SERVICE_USER:-filebrowser}"
GITHUB_REPO="${GITHUB_REPO:-filebrowser/filebrowser}"
BACKUP_DIR="${BACKUP_DIR:-/opt/filebrowser-backups}"
BACKUP_KEEP_DAYS="${BACKUP_KEEP_DAYS:-30}"
FB_ROOT="${FB_ROOT:-/srv/filebrowser}"
BA_BIN_NAME="filebrowser"
BA_ARCHIVE_TYPE="tar.gz"
BA_USE_ENV_FILE=0
BA_FIREWALL=1
BA_SERVICE_DESCRIPTION="Filebrowser web file manager"
BA_SERVICE_ARGS="-d ${DATA_DIR}/filebrowser.db -r ${FB_ROOT} -a 0.0.0.0 -p ${PORT}"
BA_READWRITE_PATHS="${FB_ROOT}"
BA_HEALTH_URL="http://127.0.0.1:${PORT}/"
BA_HEALTH_CODES="^(200|301|302)$"
CONFIG_KEYS=(
  DOMAIN PORT INSTALL_DIR DATA_DIR LOG_DIR SERVICE_NAME SERVICE_USER
  GITHUB_REPO BACKUP_DIR BACKUP_KEEP_DAYS FB_ROOT INSTALLED_VERSION
)

ba_asset_name() {
  local version="$1"
  printf 'linux-%s-filebrowser.tar.gz\n' "$BA_ARCH"
}

# The served root is a configurable path that must exist and be writable by
# the service user before the process starts.
ba_validate_extra() {
  require_safe_path "FB_ROOT" "$FB_ROOT"
}

ba_pre_start() {
  if ! mkdir -p "$FB_ROOT"; then
    error "$(t app.filebrowser.error.root_prepare "$FB_ROOT")"
  fi
  if ! chown "${SERVICE_USER}:${SERVICE_USER}" "$FB_ROOT"; then
    error "$(t app.filebrowser.error.root_prepare "$FB_ROOT")"
  fi
  success "$(t app.filebrowser.success.root_prepared "$FB_ROOT")"
}

ba_summary_extra() {
  echo -e "  ${BOLD}$(t app.filebrowser.hint.default)${NC}"
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

do_status() {
  bapp_status
}

do_uninstall() {
  acquire_lock
  bapp_uninstall
}

binary_app_bootstrap
