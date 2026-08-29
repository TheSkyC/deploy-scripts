#!/usr/bin/env bash
set -euo pipefail
umask 077

# ntfy (https://github.com/binwiederhier/ntfy) ships a tarball with a single
# binary named ntfy_<version>_linux_<arch>.tar.gz (version without the
# leading v).  The shared binary-app library (lib/binary_app.sh) provides the
# lifecycle; this file only configures it and adds ntfy-specific hooks.
# See PLAN.md section 2 for the verified release asset mapping.

DOMAIN="${DOMAIN:-}"
PORT="${PORT:-2586}"
INSTALL_DIR="${INSTALL_DIR:-/opt/ntfy}"
DATA_DIR="${DATA_DIR:-/var/lib/ntfy}"
LOG_DIR="${LOG_DIR:-/var/log/ntfy}"
SERVICE_NAME="${SERVICE_NAME:-ntfy}"
SERVICE_USER="${SERVICE_USER:-ntfy}"
GITHUB_REPO="${GITHUB_REPO:-binwiederhier/ntfy}"
BACKUP_DIR="${BACKUP_DIR:-/opt/ntfy-backups}"
BACKUP_KEEP_DAYS="${BACKUP_KEEP_DAYS:-30}"
BA_BIN_NAME="ntfy"
BA_ARCHIVE_TYPE="tar.gz"
BA_USE_ENV_FILE=0
BA_FIREWALL=0
BA_BIND_ADDR="${BA_BIND_ADDR:-127.0.0.1}"
BA_SERVICE_DESCRIPTION="ntfy push notification server"
BA_SERVICE_ARGS="serve /etc/ntfy/server.yml"
BA_HEALTH_URL="http://127.0.0.1:${PORT}/"
BA_HEALTH_CODES="^(200|301|302)$"
CONFIG_KEYS=(
  DOMAIN PORT INSTALL_DIR DATA_DIR LOG_DIR SERVICE_NAME SERVICE_USER
  GITHUB_REPO BACKUP_DIR BACKUP_KEEP_DAYS BA_BIND_ADDR BA_VERSION INSTALLED_VERSION
)

# Release asset names embed the version without the leading v.
ba_asset_name() {
  local version="$1"
  printf 'ntfy_%s_linux_%s.tar.gz\n' "${version#v}" "$BA_ARCH"
}

# Write the managed ntfy server configuration under /etc/ntfy.
ba_write_config() {
  local config_dir="/etc/ntfy"
  local config_file="${config_dir}/server.yml"
  if ! atomic_write_file "$config_file" 644 root:root <<EOF
# Managed by the ntfy deploy script.
listen-http: ${BA_BIND_ADDR}:${PORT}
cache-file: ${DATA_DIR}/cache.db
attachment-cache-dir: ${DATA_DIR}/attachments
EOF
  then
    error "$(t app.ntfy.error.config_write "$config_file")"
  fi
  success "$(t app.ntfy.success.config_written "$config_file")"
}

# Remove the managed server configuration during uninstall.
ba_uninstall_extra() {
  local config_dir="/etc/ntfy"
  local config_file="${config_dir}/server.yml"
  ba_remove_file_or_error "$config_file" "NTFY_CONFIG_FILE"
  if [[ -d "$config_dir" ]] && [[ -z "$(ls -A "$config_dir" 2>/dev/null)" ]]; then
    if ! safe_rm_dir "$config_dir" "NTFY_CONFIG_DIR"; then
      warn "$(t app.ntfy.warn.config_dir_remove "$config_dir")"
    fi
  fi
  success "$(t app.ntfy.success.removed_config)"
}

# Show a quick publish hint after install.
ba_summary_extra() {
  echo -e "  ${BOLD}$(t app.ntfy.hint.publish "$PORT")${NC}"
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
