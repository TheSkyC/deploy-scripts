#!/bin/bash
set -euo pipefail
umask 077

# frp (https://github.com/fatedier/frp) ships a tarball containing frps,
# frpc, and example configs; the shared binary-app library (lib/binary_app.sh)
# provides the lifecycle and this file configures it for the frps server.
# frps listens on a raw TCP proxy port, so the health probe checks the systemd
# unit instead of an HTTP endpoint.
# See PLAN.md section 2 for the verified release asset mapping.

DOMAIN="${DOMAIN:-}"
PORT="${PORT:-7000}"
INSTALL_DIR="${INSTALL_DIR:-/opt/frps}"
DATA_DIR="${DATA_DIR:-/var/lib/frps}"
LOG_DIR="${LOG_DIR:-/var/log/frps}"
SERVICE_NAME="${SERVICE_NAME:-frps}"
SERVICE_USER="${SERVICE_USER:-frps}"
GITHUB_REPO="${GITHUB_REPO:-fatedier/frp}"
BACKUP_DIR="${BACKUP_DIR:-/opt/frps-backups}"
BACKUP_KEEP_DAYS="${BACKUP_KEEP_DAYS:-30}"
BA_BIN_NAME="frps"
BA_ARCHIVE_TYPE="tar.gz"
BA_USE_ENV_FILE=0
BA_FIREWALL=1
BA_SERVICE_DESCRIPTION="frp server (frps)"
BA_SERVICE_ARGS="-c /etc/frps/frps.toml"
CONFIG_KEYS=(
  DOMAIN PORT INSTALL_DIR DATA_DIR LOG_DIR SERVICE_NAME SERVICE_USER
  GITHUB_REPO BACKUP_DIR BACKUP_KEEP_DAYS INSTALLED_VERSION
)

# Upstream embeds the version without the leading v in the asset name.
ba_asset_name() {
  local version="$1"
  printf 'frp_%s_linux_%s.tar.gz\n' "${version#v}" "$BA_ARCH"
}

# Write the managed frps server configuration under /etc/frps.  The auth token
# is generated on first install and preserved on any reinstall.
ba_write_config() {
  local config_dir="/etc/frps"
  local config_file="${config_dir}/frps.toml"
  local token="" line=""
  if [[ -f "$config_file" ]]; then
    line="$(grep -E '^auth\.token' "$config_file" 2>/dev/null | head -1 || true)"
    if [[ -n "$line" ]]; then
      token="${line#*\"}"
      token="${token%\"*}"
    fi
  fi
  if [[ -z "$token" ]]; then
    token="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 32 || true)"
    [[ -n "$token" ]] || token="frps-$(date +%s)-$(tr -dc '0-9' </dev/urandom | head -c 8)"
  fi
  if ! atomic_write_file "$config_file" 600 root:root <<EOF
bindAddr = "0.0.0.0"
bindPort = ${PORT}
auth.token = "${token}"
EOF
  then
    error "$(t app.frps.error.config_write "$config_file")"
  fi
  success "$(t app.frps.success.config_written "$config_file")"
}

# Remove the managed server configuration during uninstall.
ba_uninstall_extra() {
  local config_dir="/etc/frps"
  local config_file="${config_dir}/frps.toml"
  ba_remove_file_or_error "$config_file" "FRPS_CONFIG_FILE"
  if [[ -d "$config_dir" ]] && [[ -z "$(ls -A "$config_dir" 2>/dev/null)" ]]; then
    if ! safe_rm_dir "$config_dir" "FRPS_CONFIG_DIR"; then
      warn "$(t app.frps.warn.config_dir_remove "$config_dir")"
    fi
  fi
  success "$(t app.frps.success.removed_config)"
}

# frps has no HTTP endpoint; check the systemd unit state instead.
bapp_health_probe() {
  if systemctl is-active --quiet "$SERVICE_NAME"; then
    success "$(t binary_app.success.started "$SERVICE_NAME")"
    return 0
  fi
  warn "$(t binary_app.warn.health "inactive")"
  warn "$(t binary_app.warn.debug_command "$SERVICE_NAME")"
  return 1
}

ba_summary_extra() {
  echo -e "  ${BOLD}$(t app.frps.hint.token "/etc/frps/frps.toml")${NC}"
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
