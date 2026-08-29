#!/usr/bin/env bash
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
BA_FIREWALL=0
BA_BIND_ADDR="127.0.0.1"
BA_SERVICE_DESCRIPTION="Alist file listing service"
BA_SERVICE_ARGS="server --data ${DATA_DIR}"
BA_HEALTH_URL="http://127.0.0.1:${PORT}/"
BA_HEALTH_CODES="^(200|301|302)$"
CONFIG_KEYS=(
  DOMAIN PORT INSTALL_DIR DATA_DIR LOG_DIR SERVICE_NAME SERVICE_USER
  GITHUB_REPO BACKUP_DIR BACKUP_KEEP_DAYS BA_BIND_ADDR BA_VERSION INSTALLED_VERSION
)

# Alist stores its own configuration and database under DATA_DIR on first
# start, so no managed config file is written by the deployment script.

ba_asset_name() {
  local version="$1"
  printf 'alist-linux-%s.tar.gz\n' "$BA_ARCH"
}

# Pin the HTTP listen address before the first start. Alist generates
# data/config.json on first run with scheme.address=0.0.0.0 by default; write
# a minimal config first so the service binds to BA_BIND_ADDR from the start.
# If an existing config.json already has a scheme block, preserve everything
# and only rewrite scheme.address (via a small awk in-place rewrite).
ba_pre_start() {
  local config_file="${DATA_DIR}/config.json"
  if [[ ! -f "$config_file" ]]; then
    if ! mkdir -p "$DATA_DIR"; then
      error "$(t app.alist.error.config_dir "$DATA_DIR")"
    fi
    if ! atomic_write_file "$config_file" 600 "root:${SERVICE_USER}" <<EOF
{
  "force": false,
  "site_url": "",
  "scheme": {
    "address": "${BA_BIND_ADDR}",
    "http_port": ${PORT},
    "https_port": -1,
    "force_https": false,
    "cert_file": "",
    "key_file": "",
    "unix_file": "",
    "unix_file_perm": ""
  }
}
EOF
    then
      error "$(t app.alist.error.config_write "$config_file")"
    fi
    success "$(t app.alist.success.config_written "$config_file")"
  elif ! grep -q "\"address\"" "$config_file"; then
    # Existing config without a scheme block: append one before the closing
    # brace so the listener stays pinned to BA_BIND_ADDR.
    local tmp
    if ! tmp=$(mktemp "${config_file}.XXXXXX"); then
      error "$(t app.alist.error.config_write "$config_file")"
    fi
    if ! awk -v addr="${BA_BIND_ADDR}" -v port="${PORT}" '
        { print }
        /^[[:space:]]*}[[:space:]]*$/ && !done {
          print "  ,\"scheme\": {"
          print "    \"address\": \"" addr "\","
          print "    \"http_port\": " port ","
          print "    \"https_port\": -1,"
          print "    \"force_https\": false,"
          print "    \"cert_file\": \"\","
          print "    \"key_file\": \"\","
          print "    \"unix_file\": \"\","
          print "    \"unix_file_perm\": \"\""
          print "  }"
          done = 1
        }
      ' "$config_file" > "$tmp"; then
      rm -f "$tmp"
      error "$(t app.alist.error.config_write "$config_file")"
    fi
    if ! chown "root:${SERVICE_USER}" "$tmp" 2>/dev/null \
        || ! chmod 600 "$tmp" \
        || ! mv -f "$tmp" "$config_file"; then
      rm -f "$tmp"
      error "$(t app.alist.error.config_write "$config_file")"
    fi
    success "$(t app.alist.success.config_written "$config_file")"
  else
    # Existing scheme block: rewrite only the address field.
    local tmp2
    if ! tmp2=$(mktemp "${config_file}.XXXXXX"); then
      error "$(t app.alist.error.config_write "$config_file")"
    fi
    if ! awk -v addr="${BA_BIND_ADDR}" '
        /"address"[[:space:]]*:/ { sub(/"address"[[:space:]]*:[[:space:]]*"[^"]*"/, "\"address\": \"" addr "\""); }
        { print }
      ' "$config_file" > "$tmp2"; then
      rm -f "$tmp2"
      error "$(t app.alist.error.config_write "$config_file")"
    fi
    if ! chown "root:${SERVICE_USER}" "$tmp2" 2>/dev/null \
        || ! chmod 600 "$tmp2" \
        || ! mv -f "$tmp2" "$config_file"; then
      rm -f "$tmp2"
      error "$(t app.alist.error.config_write "$config_file")"
    fi
    success "$(t app.alist.success.config_written "$config_file")"
  fi
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
