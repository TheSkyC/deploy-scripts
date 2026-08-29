#!/usr/bin/env bash
set -euo pipefail
umask 077

# Beszel (https://github.com/henrygd/beszel) ships a tarball containing the
# hub binary. The shared binary-app library (lib/binary_app.sh) provides the
# lifecycle; this file configures it and adds Beszel-specific hooks.
# See PLAN.md section 2 for the verified release asset mapping.

DOMAIN="${DOMAIN:-}"
PORT="${PORT:-8090}"
INSTALL_DIR="${INSTALL_DIR:-/opt/beszel}"
DATA_DIR="${DATA_DIR:-/var/lib/beszel}"
LOG_DIR="${LOG_DIR:-/var/log/beszel}"
SERVICE_NAME="${SERVICE_NAME:-beszel}"
SERVICE_USER="${SERVICE_USER:-beszel}"
GITHUB_REPO="${GITHUB_REPO:-henrygd/beszel}"
BACKUP_DIR="${BACKUP_DIR:-/opt/beszel-backups}"
BACKUP_KEEP_DAYS="${BACKUP_KEEP_DAYS:-30}"
BA_BIN_NAME="beszel"
BA_ARCHIVE_TYPE="tar.gz"
BA_USE_ENV_FILE=1
BA_FIREWALL=0
BA_BIND_ADDR="${BA_BIND_ADDR:-127.0.0.1}"
BA_SERVICE_DESCRIPTION="Beszel monitoring hub"
BA_SERVICE_ARGS="serve --http ${BA_BIND_ADDR}:${PORT} --dir ${DATA_DIR}"
BA_HEALTH_URL="http://127.0.0.1:${PORT}/api/health"
BA_HEALTH_CODES="^200$"
CONFIG_KEYS=(
  DOMAIN PORT INSTALL_DIR DATA_DIR LOG_DIR SERVICE_NAME SERVICE_USER
  GITHUB_REPO BACKUP_DIR BACKUP_KEEP_DAYS BA_BIND_ADDR BA_VERSION BA_ENABLE_HTTPS CERTBOT_EMAIL INSTALLED_VERSION
)

# Beszel release assets use the architecture name without the v-prefixed tag.
ba_asset_name() {
  printf 'beszel_linux_%s.tar.gz\n' "$BA_ARCH"
}

# Set the public application URL when a domain is supplied. The URL is also
# used by Beszel to generate links and is kept root-readable only.
ba_write_config() {
  local env_file="/etc/${SERVICE_NAME}.env"
  local app_url="http://127.0.0.1:${PORT}"
  if [[ -n "$DOMAIN" ]]; then
    app_url="http://${DOMAIN}:${PORT}"
  fi
  if ! atomic_write_file "$env_file" 600 root:root <<EOF
APP_URL=${app_url}
EOF
  then
    error "$(t app.beszel.error.env_write "$env_file")"
  fi
  success "$(t app.beszel.success.env_written "$env_file")"
}

ba_summary_extra() {
  local app_url="http://127.0.0.1:${PORT}"
  if [[ -n "$DOMAIN" ]]; then
    app_url="http://${DOMAIN}:${PORT}"
  fi
  echo -e "  ${BOLD}$(t app.beszel.hint.open_ui "$app_url")${NC}"
}

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
