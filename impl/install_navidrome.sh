#!/bin/bash
set -euo pipefail
umask 077

# Navidrome (https://github.com/navidrome/navidrome) ships a tarball with a
# binary named navidrome and configures itself through ND_* environment vars.
# The shared binary-app library (lib/binary_app.sh) provides the lifecycle;
# this file configures it and adds Navidrome-specific hooks.
# See PLAN.md section 2 for the verified release asset mapping.

DOMAIN="${DOMAIN:-}"
PORT="${PORT:-4533}"
INSTALL_DIR="${INSTALL_DIR:-/opt/navidrome}"
DATA_DIR="${DATA_DIR:-/var/lib/navidrome}"
LOG_DIR="${LOG_DIR:-/var/log/navidrome}"
SERVICE_NAME="${SERVICE_NAME:-navidrome}"
SERVICE_USER="${SERVICE_USER:-navidrome}"
GITHUB_REPO="${GITHUB_REPO:-navidrome/navidrome}"
BACKUP_DIR="${BACKUP_DIR:-/opt/navidrome-backups}"
BACKUP_KEEP_DAYS="${BACKUP_KEEP_DAYS:-30}"
MUSIC_DIR="${MUSIC_DIR:-/srv/music}"
BA_BIN_NAME="navidrome"
BA_ARCHIVE_TYPE="tar.gz"
BA_USE_ENV_FILE=1
BA_FIREWALL=0
BA_BIND_ADDR="${BA_BIND_ADDR:-127.0.0.1}"
BA_SERVICE_DESCRIPTION="Navidrome music server"
BA_READWRITE_PATHS="${MUSIC_DIR}"
BA_HEALTH_URL="http://127.0.0.1:${PORT}/ping"
BA_HEALTH_CODES="^200$"
CONFIG_KEYS=(
  DOMAIN PORT INSTALL_DIR DATA_DIR LOG_DIR SERVICE_NAME SERVICE_USER
  GITHUB_REPO BACKUP_DIR BACKUP_KEEP_DAYS MUSIC_DIR BA_BIND_ADDR INSTALLED_VERSION
)

# Upstream embeds the version without the leading v in the asset name.
ba_asset_name() {
  local version="$1"
  printf 'navidrome_%s_linux_%s.tar.gz\n' "${version#v}" "$BA_ARCH"
}

# Write the managed ND_* environment file read by the systemd unit.
ba_write_config() {
  local env_file="/etc/${SERVICE_NAME}.env"
  if ! atomic_write_file "$env_file" 600 root:root <<EOF
ND_ADDRESS=${BA_BIND_ADDR}
ND_PORT=${PORT}
ND_DATAFOLDER=${DATA_DIR}
ND_MUSICFOLDER=${MUSIC_DIR}
EOF
  then
    error "$(t app.navidrome.error.env_write "$env_file")"
  fi
  success "$(t app.navidrome.success.env_written "$env_file")"
}

# The music folder must exist and be writable by the service user.
ba_validate_extra() {
  require_safe_path "MUSIC_DIR" "$MUSIC_DIR"
}

ba_pre_start() {
  if ! mkdir -p "$MUSIC_DIR"; then
    error "$(t app.navidrome.error.music_prepare "$MUSIC_DIR")"
  fi
  if ! chown "${SERVICE_USER}:${SERVICE_USER}" "$MUSIC_DIR"; then
    error "$(t app.navidrome.error.music_prepare "$MUSIC_DIR")"
  fi
  success "$(t app.navidrome.success.music_prepared "$MUSIC_DIR")"
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
