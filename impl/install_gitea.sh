#!/usr/bin/env bash
set -euo pipefail
umask 077

# Gitea (https://github.com/go-gitea/gitea) ships a bare, versioned binary
# named gitea-<version>-linux-<arch> and needs the system git binary for repo
# operations.  The shared binary-app library (lib/binary_app.sh) provides the
# lifecycle; this file configures it and adds Gitea-specific hooks.
# See PLAN.md section 2 for the verified release asset mapping.

DOMAIN="${DOMAIN:-}"
PORT="${PORT:-3000}"
INSTALL_DIR="${INSTALL_DIR:-/opt/gitea}"
DATA_DIR="${DATA_DIR:-/var/lib/gitea}"
LOG_DIR="${LOG_DIR:-/var/log/gitea}"
SERVICE_NAME="${SERVICE_NAME:-gitea}"
SERVICE_USER="${SERVICE_USER:-gitea}"
GITHUB_REPO="${GITHUB_REPO:-go-gitea/gitea}"
BACKUP_DIR="${BACKUP_DIR:-/opt/gitea-backups}"
BACKUP_KEEP_DAYS="${BACKUP_KEEP_DAYS:-30}"
BA_BIN_NAME="gitea"
BA_ARCHIVE_TYPE="none"
BA_APT_PACKAGES="git"
BA_USE_ENV_FILE=0
BA_FIREWALL=0
BA_BIND_ADDR="${BA_BIND_ADDR:-127.0.0.1}"
BA_SERVICE_DESCRIPTION="Gitea git server"
BA_SERVICE_ARGS="web --config /etc/gitea/app.ini --work-path ${DATA_DIR}"
BA_HEALTH_URL="http://127.0.0.1:${PORT}/"
BA_HEALTH_CODES="^(200|301|302|403)$"
CONFIG_KEYS=(
  DOMAIN PORT INSTALL_DIR DATA_DIR LOG_DIR SERVICE_NAME SERVICE_USER
  GITHUB_REPO BACKUP_DIR BACKUP_KEEP_DAYS BA_BIND_ADDR INSTALLED_VERSION
)

# Upstream embeds the version without the leading v in the binary name.
ba_asset_name() {
  local version="$1"
  printf 'gitea-%s-linux-%s\n' "${version#v}" "$BA_ARCH"
}

# Write the managed Gitea configuration under /etc/gitea.
ba_write_config() {
  local config_dir="/etc/gitea"
  local config_file="${config_dir}/app.ini"
  local server_name="${DOMAIN:-localhost}"
  if ! atomic_write_file "$config_file" 0660 "root:${SERVICE_USER}" <<EOF
RUN_USER = ${SERVICE_USER}
RUN_MODE = prod

[server]
APP_DATA_PATH = ${DATA_DIR}
PROTOCOL = http
HTTP_ADDR = ${BA_BIND_ADDR}
HTTP_PORT = ${PORT}
DOMAIN = ${server_name}
ROOT_URL = http://${server_name}:${PORT}/
DISABLE_SSH = true
LFS_START_SERVER = false

[database]
DB_TYPE = sqlite
PATH = ${DATA_DIR}/gitea.db

[service]
DISABLE_REGISTRATION = false

[log]
MODE = console
LEVEL = Info
EOF
  then
    error "$(t app.gitea.error.config_write "$config_file")"
  fi
  success "$(t app.gitea.success.config_written "$config_file")"
}

# Remove the managed server configuration during uninstall.
ba_uninstall_extra() {
  local config_dir="/etc/gitea"
  local config_file="${config_dir}/app.ini"
  ba_remove_file_or_error "$config_file" "GITEA_CONFIG_FILE"
  if [[ -d "$config_dir" ]] && [[ -z "$(ls -A "$config_dir" 2>/dev/null)" ]]; then
    if ! safe_rm_dir "$config_dir" "GITEA_CONFIG_DIR"; then
      warn "$(t app.gitea.warn.config_dir_remove "$config_dir")"
    fi
  fi
  success "$(t app.gitea.success.removed_config)"
}

# Remind users to create the first admin account after install.
ba_summary_extra() {
  echo -e "  ${BOLD}$(t app.gitea.hint.admin_create)${NC}"
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
