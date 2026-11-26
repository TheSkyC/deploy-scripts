#!/usr/bin/env bash
set -euo pipefail
umask 077

RUSTDESK_INSTALL_DIR="${RUSTDESK_INSTALL_DIR:-/opt/rustdesk-server}"
RUSTDESK_DATA_DIR="${RUSTDESK_DATA_DIR:-/var/lib/rustdesk-server}"
RUSTDESK_SERVICE_NAME="${RUSTDESK_SERVICE_NAME:-rustdesk-server}"
RUSTDESK_IMAGE="${RUSTDESK_IMAGE:-rustdesk/rustdesk-server:1.1.14}"
RUSTDESK_RELAY_HOST="${RUSTDESK_RELAY_HOST:-}"
RUSTDESK_BIND_ADDR="${RUSTDESK_BIND_ADDR:-0.0.0.0}"
RUSTDESK_COMPOSE_FILE="${RUSTDESK_COMPOSE_FILE:-${RUSTDESK_INSTALL_DIR}/compose.yaml}"
RUSTDESK_BACKUP_DIR="${RUSTDESK_BACKUP_DIR:-/opt/rustdesk-server-backups}"
CONFIG_KEYS=(RUSTDESK_INSTALL_DIR RUSTDESK_DATA_DIR RUSTDESK_SERVICE_NAME RUSTDESK_IMAGE RUSTDESK_RELAY_HOST RUSTDESK_BIND_ADDR RUSTDESK_COMPOSE_FILE RUSTDESK_BACKUP_DIR)
app_conf_register_legacy "/etc/rustdesk-server-deploy.conf"
CONF_FILE="$(app_conf_file)"
LOCK_FILE="$(app_lock_file)"

preflight_check() {
  [[ "${1:-}" == status || $EUID -eq 0 ]] || error "$(t error.root_required "$0" "${1:-}")"
  command -v systemctl >/dev/null 2>&1 || error "systemd is required"
  require_safe_path RUSTDESK_INSTALL_DIR "$RUSTDESK_INSTALL_DIR"
  require_safe_path RUSTDESK_DATA_DIR "$RUSTDESK_DATA_DIR"
  require_safe_path RUSTDESK_COMPOSE_FILE "$RUSTDESK_COMPOSE_FILE"
  require_safe_path RUSTDESK_BACKUP_DIR "$RUSTDESK_BACKUP_DIR"
  require_path_without_whitespace RUSTDESK_INSTALL_DIR "$RUSTDESK_INSTALL_DIR"
  require_path_without_whitespace RUSTDESK_DATA_DIR "$RUSTDESK_DATA_DIR"
  require_path_without_whitespace RUSTDESK_COMPOSE_FILE "$RUSTDESK_COMPOSE_FILE"
  [[ "$RUSTDESK_SERVICE_NAME" =~ ^[A-Za-z0-9_.@-]+$ ]] || error "Invalid RUSTDESK_SERVICE_NAME"
  [[ "$RUSTDESK_IMAGE" =~ ^[A-Za-z0-9._/-]+:[A-Za-z0-9._-]+$ ]] || error "Invalid RUSTDESK_IMAGE: $RUSTDESK_IMAGE"
  [[ "$RUSTDESK_RELAY_HOST" =~ ^[A-Za-z0-9.-]+$ ]] || error "Set RUSTDESK_RELAY_HOST to the public DNS name or IP clients use to reach this server"
  [[ "$RUSTDESK_BIND_ADDR" == 0.0.0.0 || "$RUSTDESK_BIND_ADDR" == 127.0.0.1 ]] || error "RUSTDESK_BIND_ADDR must be 0.0.0.0 or 127.0.0.1"
}

_rustdesk_write_compose() {
  local bind="$RUSTDESK_BIND_ADDR"
  atomic_write_file "$RUSTDESK_COMPOSE_FILE" 600 <<EOF
services:
  hbbr:
    image: ${RUSTDESK_IMAGE}
    command: hbbr
    restart: unless-stopped
    volumes:
      - ${RUSTDESK_DATA_DIR}:/root
    ports:
      - "${bind}:21117:21117/tcp"
  hbbs:
    image: ${RUSTDESK_IMAGE}
    command: hbbs -r ${RUSTDESK_RELAY_HOST}:21117
    restart: unless-stopped
    depends_on:
      - hbbr
    volumes:
      - ${RUSTDESK_DATA_DIR}:/root
    ports:
      - "${bind}:21115:21115/tcp"
      - "${bind}:21116:21116/tcp"
      - "${bind}:21116:21116/udp"
EOF
}

_rustdesk_compose() { compose_run "$RUSTDESK_INSTALL_DIR" "$RUSTDESK_COMPOSE_FILE" "$@"; }
_rustdesk_write_unit() {
  local unit="/etc/systemd/system/${RUSTDESK_SERVICE_NAME}.service" dir_q file_q cmd
  cmd="$(compose_command)"; [[ -n "$cmd" ]] || error "Docker Compose is required"
  printf -v dir_q '%q' "$RUSTDESK_INSTALL_DIR"
  printf -v file_q '%q' "$RUSTDESK_COMPOSE_FILE"
  atomic_write_file "$unit" 644 <<EOF
[Unit]
Description=RustDesk Server OSS
After=docker.service network-online.target
Wants=docker.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/bash -lc 'cd ${dir_q} && ${cmd} -f ${file_q} up -d'
ExecStop=/bin/bash -lc 'cd ${dir_q} && ${cmd} -f ${file_q} down'
TimeoutStartSec=300
TimeoutStopSec=120

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload || error "systemd daemon-reload failed"
}

do_install() {
  preflight_check install; acquire_lock
  if ! command -v docker >/dev/null 2>&1 || ! compose_command | grep -q .; then
    apt-get update -qq || warn "apt-get update failed; attempting dependency installation"
    apt-get install -y --no-install-recommends docker.io docker-compose-plugin \
      || apt-get install -y --no-install-recommends docker.io docker-compose \
      || error "Could not install Docker Compose dependencies"
  fi
  systemctl enable --now docker || error "Could not start Docker"
  mkdir -p "$RUSTDESK_INSTALL_DIR" "$RUSTDESK_DATA_DIR"
  _rustdesk_write_compose
  compose_require_runtime
  _rustdesk_write_unit
  app_save_config
  systemctl enable --now "$RUSTDESK_SERVICE_NAME"
  _rustdesk_show_key
}
do_update() {
  acquire_lock; app_load_config; preflight_check update
  _rustdesk_write_compose
  compose_run "$RUSTDESK_INSTALL_DIR" "$RUSTDESK_COMPOSE_FILE" pull
  compose_run "$RUSTDESK_INSTALL_DIR" "$RUSTDESK_COMPOSE_FILE" up -d
}
_rustdesk_show_key() {
  local key="${RUSTDESK_DATA_DIR}/id_ed25519.pub"
  if [[ -r "$key" ]]; then
    info "$(t app.rustdesk.info.public_key)"; printf '  %s\n' "$(<"$key")"
  else warn "$(t app.rustdesk.warn.no_key)"; fi
}
do_status() {
  app_load_config; preflight_check status
  systemctl status "$RUSTDESK_SERVICE_NAME" --no-pager -l 2>/dev/null || true
  _rustdesk_show_key
}
do_backup() {
  acquire_lock; app_load_config; preflight_check backup
  local archive stamp
  mkdir -p "$RUSTDESK_BACKUP_DIR"
  stamp="$(date -u +%Y%m%d%H%M%S)"
  archive="${RUSTDESK_BACKUP_DIR}/rustdesk_${stamp}.tar.gz"
  backup_create_tar_archive "$archive" -C "$(dirname "$RUSTDESK_DATA_DIR")" "$(basename "$RUSTDESK_DATA_DIR")" \
    || error "Failed to archive RustDesk identity and data"
  backup_finalize_archive "$archive" rustdesk "${RUSTDESK_IMAGE##*:}" 1 \
    || error "Failed to write RustDesk backup integrity metadata"
  success "RustDesk backup created: $archive"
}
do_verify() {
  app_load_config; preflight_check verify
  app_verify_latest_backup "$RUSTDESK_BACKUP_DIR" 'rustdesk_*.tar.gz'
}
do_restore() {
  acquire_lock; app_load_config; preflight_check restore
  local archive="${RUSTDESK_RESTORE_ARCHIVE:-}"
  if [[ -n "$archive" ]]; then
    [[ "$archive" == "$RUSTDESK_BACKUP_DIR"/rustdesk_*.tar.gz && -f "$archive" ]] \
      || error "Invalid RustDesk restore archive: $archive"
  else
    archive="$(backup_latest_archive "$RUSTDESK_BACKUP_DIR" 'rustdesk_*.tar.gz' || true)"
    [[ -n "$archive" ]] || error "No RustDesk backups found in $RUSTDESK_BACKUP_DIR"
  fi
  backup_restore_data_dir "$RUSTDESK_DATA_DIR" "$RUSTDESK_SERVICE_NAME" "$archive"
}
do_uninstall() {
  acquire_lock; app_load_config; preflight_check uninstall
  systemctl disable --now "$RUSTDESK_SERVICE_NAME" || error "Failed to stop/disable RustDesk service"
  rm -f "/etc/systemd/system/${RUSTDESK_SERVICE_NAME}.service"
  systemctl daemon-reload || error "systemd daemon-reload failed"
  info "Server stopped. Persistent identity retained at ${RUSTDESK_DATA_DIR}."
}
