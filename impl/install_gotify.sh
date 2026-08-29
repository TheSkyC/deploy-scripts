#!/usr/bin/env bash
set -euo pipefail
umask 077

# Gotify (https://github.com/gotify/server) ships a zip containing a single
# gotify binary and reads GOTIFY_* environment variables for configuration.
# The shared binary-app library (lib/binary_app.sh) provides the lifecycle;
# this file configures it and adds Gotify-specific hooks.
# See PLAN.md section 2 for the verified release asset mapping.

# Default port 8085: 8080 is taken by newapi, and 8081-8084 by
# vaultwarden/filebrowser/sub2api/cyberstrikeai. Override with PORT=... if
# you deploy on a host where these do not collide.
DOMAIN="${DOMAIN:-}"
PORT="${PORT:-8085}"
INSTALL_DIR="${INSTALL_DIR:-/opt/gotify}"
DATA_DIR="${DATA_DIR:-/var/lib/gotify}"
LOG_DIR="${LOG_DIR:-/var/log/gotify}"
SERVICE_NAME="${SERVICE_NAME:-gotify}"
SERVICE_USER="${SERVICE_USER:-gotify}"
GITHUB_REPO="${GITHUB_REPO:-gotify/server}"
BACKUP_DIR="${BACKUP_DIR:-/opt/gotify-backups}"
BACKUP_KEEP_DAYS="${BACKUP_KEEP_DAYS:-30}"
BA_BIN_NAME="gotify"
BA_ARCHIVE_TYPE="zip"
BA_APT_PACKAGES="unzip"
BA_USE_ENV_FILE=1
BA_FIREWALL=0
BA_BIND_ADDR="${BA_BIND_ADDR:-127.0.0.1}"
BA_SERVICE_DESCRIPTION="Gotify push notification server"
BA_HEALTH_URL="http://127.0.0.1:${PORT}/"
BA_HEALTH_CODES="^(200|301|302)$"
CONFIG_KEYS=(
  DOMAIN PORT INSTALL_DIR DATA_DIR LOG_DIR SERVICE_NAME SERVICE_USER
  GITHUB_REPO BACKUP_DIR BACKUP_KEEP_DAYS BA_BIND_ADDR BA_VERSION BA_ENABLE_HTTPS CERTBOT_EMAIL INSTALLED_VERSION
)

ba_asset_name() {
  local version="$1"
  printf 'gotify-linux-%s.zip\n' "$BA_ARCH"
}

# Write the managed GOTIFY_* environment file read by the systemd unit.
# Preserve the initial admin password on reinstall so existing credentials keep
# working; generate a random value instead of allowing Gotify's default.
ba_write_config() {
  local env_file="/etc/${SERVICE_NAME}.env" admin_password=""
  if [[ -f "$env_file" ]]; then
    admin_password="$(grep -E '^GOTIFY_DEFAULTUSER_PASS=' "$env_file" 2>/dev/null | head -1 | cut -d= -f2- || true)"
  fi
  if [[ -z "$admin_password" ]]; then
    admin_password="$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 40 || true)"
    [[ -n "$admin_password" ]] || error "$(t app.gotify.error.env_write "$env_file")"
  fi
  if ! atomic_write_file "$env_file" 600 root:root <<EOF
GOTIFY_SERVER_LISTENADDR=${BA_BIND_ADDR}
GOTIFY_SERVER_PORT=${PORT}
GOTIFY_DEFAULTUSER_NAME=admin
GOTIFY_DEFAULTUSER_PASS=${admin_password}
EOF
  then
    error "$(t app.gotify.error.env_write "$env_file")"
  fi
  success "$(t app.gotify.success.env_written "$env_file")"
}

# The generated password is stored in the root-only environment file.
ba_summary_extra() {
  echo -e "  ${BOLD}$(t app.gotify.hint.admin_password "/etc/${SERVICE_NAME}.env")${NC}"
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
