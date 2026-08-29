#!/usr/bin/env bash
set -euo pipefail
umask 077

# Meilisearch (https://github.com/meilisearch/meilisearch) ships a bare,
# non-versioned binary named meilisearch-linux-<arch>.  The shared binary-app
# library (lib/binary_app.sh) provides the lifecycle; this file only configures
# it and adds Meilisearch-specific hooks.  Architecture maps to aarch64 for
# ARM64 because upstream uses aarch64 in the asset name.
# See PLAN.md section 2 for the verified release asset mapping.

DOMAIN="${DOMAIN:-}"
PORT="${PORT:-7700}"
INSTALL_DIR="${INSTALL_DIR:-/opt/meilisearch}"
DATA_DIR="${DATA_DIR:-/var/lib/meilisearch}"
LOG_DIR="${LOG_DIR:-/var/log/meilisearch}"
SERVICE_NAME="${SERVICE_NAME:-meilisearch}"
SERVICE_USER="${SERVICE_USER:-meilisearch}"
GITHUB_REPO="${GITHUB_REPO:-meilisearch/meilisearch}"
BACKUP_DIR="${BACKUP_DIR:-/opt/meilisearch-backups}"
BACKUP_KEEP_DAYS="${BACKUP_KEEP_DAYS:-30}"
BA_BIN_NAME="meilisearch"
BA_ARCHIVE_TYPE="none"
BA_USE_ENV_FILE=1
BA_FIREWALL=0
BA_BIND_ADDR="${BA_BIND_ADDR:-127.0.0.1}"
BA_SERVICE_DESCRIPTION="Meilisearch search engine"
BA_HEALTH_URL="http://127.0.0.1:${PORT}/health"
BA_HEALTH_CODES="^200$"
CONFIG_KEYS=(
  DOMAIN PORT INSTALL_DIR DATA_DIR LOG_DIR SERVICE_NAME SERVICE_USER
  GITHUB_REPO BACKUP_DIR BACKUP_KEEP_DAYS BA_BIND_ADDR INSTALLED_VERSION
)

# Upstream names the ARM64 asset aarch64 (the library BA_ARCH value is arm64).
ba_asset_name() {
  local version="$1" arch="$BA_ARCH"
  [[ "$arch" == "arm64" ]] && arch="aarch64"
  printf 'meilisearch-linux-%s\n' "$arch"
}

# Write the managed environment file.  The master key is generated on first
# install and preserved on any reinstall so existing data stays accessible.
ba_write_config() {
  local env_file="/etc/${SERVICE_NAME}.env" key=""
  if [[ -f "$env_file" ]]; then
    key="$(grep -E '^MEILI_MASTER_KEY=' "$env_file" 2>/dev/null | head -1 | cut -d= -f2- || true)"
  fi
  if [[ -z "$key" ]]; then
    key="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 40 || true)"
    [[ -n "$key" ]] || key="meilisearch-$(date +%s)-$(tr -dc '0-9' </dev/urandom | head -c 8)"
  fi
  if ! atomic_write_file "$env_file" 600 root:root <<EOF
MEILI_ENV=production
MEILI_MASTER_KEY=${key}
MEILI_DB_PATH=${DATA_DIR}/meili_data
MEILI_HTTP_ADDR=${BA_BIND_ADDR}:${PORT}
EOF
  then
    error "$(t app.meilisearch.error.env_write "$env_file")"
  fi
  success "$(t app.meilisearch.success.env_written "$env_file")"
}

# Point users at the admin key location after install.
ba_summary_extra() {
  echo -e "  ${BOLD}$(t app.meilisearch.hint.master_key "/etc/${SERVICE_NAME}.env")${NC}"
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
