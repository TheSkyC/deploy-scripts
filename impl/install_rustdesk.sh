#!/usr/bin/env bash
# shellcheck disable=SC2034
set -euo pipefail
umask 077

RUSTDESK_INSTANCE_SUFFIX="${APP_INSTANCE:+-${APP_INSTANCE}}"
RUSTDESK_INSTALL_DIR="${RUSTDESK_INSTALL_DIR:-/opt/rustdesk-server${RUSTDESK_INSTANCE_SUFFIX}}"
RUSTDESK_DATA_DIR="${RUSTDESK_DATA_DIR:-/var/lib/rustdesk-server${RUSTDESK_INSTANCE_SUFFIX}}"
RUSTDESK_SERVICE_NAME="${RUSTDESK_SERVICE_NAME:-rustdesk-server${RUSTDESK_INSTANCE_SUFFIX}}"
RUSTDESK_IMAGE="${RUSTDESK_IMAGE:-rustdesk/rustdesk-server:1.1.16}"
RUSTDESK_RELAY_HOST="${RUSTDESK_RELAY_HOST:-}"
RUSTDESK_BIND_ADDR="${RUSTDESK_BIND_ADDR:-0.0.0.0}"
RUSTDESK_DEFAULT_NETWORK_MODE=host
[[ -z "${APP_INSTANCE:-}" ]] || RUSTDESK_DEFAULT_NETWORK_MODE=bridge
RUSTDESK_NETWORK_MODE="${RUSTDESK_NETWORK_MODE:-$RUSTDESK_DEFAULT_NETWORK_MODE}"
RUSTDESK_NAT_PORT="${RUSTDESK_NAT_PORT:-21115}"
RUSTDESK_ID_PORT="${RUSTDESK_ID_PORT:-21116}"
RUSTDESK_RELAY_PORT="${RUSTDESK_RELAY_PORT:-21117}"
RUSTDESK_COMPOSE_FILE="${RUSTDESK_COMPOSE_FILE:-${RUSTDESK_INSTALL_DIR}/compose.yaml}"
RUSTDESK_BACKUP_DIR="${RUSTDESK_BACKUP_DIR:-/opt/rustdesk-server-backups${RUSTDESK_INSTANCE_SUFFIX}}"
CONFIG_KEYS=(RUSTDESK_INSTALL_DIR RUSTDESK_DATA_DIR RUSTDESK_SERVICE_NAME RUSTDESK_IMAGE RUSTDESK_RELAY_HOST RUSTDESK_BIND_ADDR RUSTDESK_NETWORK_MODE RUSTDESK_NAT_PORT RUSTDESK_ID_PORT RUSTDESK_RELAY_PORT RUSTDESK_COMPOSE_FILE RUSTDESK_BACKUP_DIR)
app_conf_register_legacy "/etc/rustdesk-server-deploy.conf"
CONF_FILE="$(app_conf_file)"
LOCK_FILE="$(app_lock_file)"

_rustdesk_doctor_service_name() { printf '%s\n' "$RUSTDESK_SERVICE_NAME"; }
APP_DOCTOR_SERVICE_FN=_rustdesk_doctor_service_name

_rustdesk_status_backup() {
  app_backup_latest_archive_json "$RUSTDESK_BACKUP_DIR" 'rustdesk_*.tar.gz'
}
APP_STATUS_BACKUP_FN=_rustdesk_status_backup

preflight_check() {
  [[ "${1:-}" == status || $EUID -eq 0 ]] || error "$(t error.root_required "$0" "${1:-}")"
  command -v systemctl >/dev/null 2>&1 || error "$(t app.rustdesk.error.systemd)"
  require_safe_path RUSTDESK_INSTALL_DIR "$RUSTDESK_INSTALL_DIR"
  require_safe_path RUSTDESK_DATA_DIR "$RUSTDESK_DATA_DIR"
  require_safe_path RUSTDESK_COMPOSE_FILE "$RUSTDESK_COMPOSE_FILE"
  require_safe_path RUSTDESK_BACKUP_DIR "$RUSTDESK_BACKUP_DIR"
  require_path_without_whitespace RUSTDESK_INSTALL_DIR "$RUSTDESK_INSTALL_DIR"
  require_path_without_whitespace RUSTDESK_DATA_DIR "$RUSTDESK_DATA_DIR"
  require_path_without_whitespace RUSTDESK_COMPOSE_FILE "$RUSTDESK_COMPOSE_FILE"
  [[ "$RUSTDESK_SERVICE_NAME" =~ ^[A-Za-z0-9_.@-]+$ ]] || error "$(t app.rustdesk.error.service_name "$RUSTDESK_SERVICE_NAME")"
  [[ "$RUSTDESK_IMAGE" =~ ^[A-Za-z0-9._/-]+:[A-Za-z0-9._-]+$ ]] || error "$(t app.rustdesk.error.image "$RUSTDESK_IMAGE")"
  [[ "$RUSTDESK_RELAY_HOST" =~ ^[A-Za-z0-9.-]+$ ]] || error "$(t app.rustdesk.error.relay_host)"
  [[ "$RUSTDESK_NETWORK_MODE" == host || "$RUSTDESK_NETWORK_MODE" == bridge ]] || error "$(t app.rustdesk.error.network_mode)"
  local port
  for port in "$RUSTDESK_NAT_PORT" "$RUSTDESK_ID_PORT" "$RUSTDESK_RELAY_PORT"; do
    if ! [[ "$port" =~ ^[0-9]+$ ]] || ! ((port > 0 && port < 65536)); then
      error "$(t app.rustdesk.error.port)"
    fi
  done
  [[ "$RUSTDESK_NAT_PORT" != "$RUSTDESK_ID_PORT" && "$RUSTDESK_NAT_PORT" != "$RUSTDESK_RELAY_PORT" \
      && "$RUSTDESK_ID_PORT" != "$RUSTDESK_RELAY_PORT" ]] || error "$(t app.rustdesk.error.port)"
  if [[ "$RUSTDESK_NETWORK_MODE" == host && ( "$RUSTDESK_NAT_PORT" != 21115 \
      || "$RUSTDESK_ID_PORT" != 21116 || "$RUSTDESK_RELAY_PORT" != 21117 ) ]]; then
    error "$(t app.rustdesk.error.host_ports)"
  fi
  [[ "$RUSTDESK_BIND_ADDR" == 0.0.0.0 || "$RUSTDESK_BIND_ADDR" == 127.0.0.1 ]] || error "$(t app.rustdesk.error.bind_addr)"
}

_rustdesk_write_compose() {
  local network_line ports_hbbs="" ports_hbbr=""
  if [[ "$RUSTDESK_NETWORK_MODE" == host ]]; then
    network_line="network_mode: host"
  else
    network_line=""
    ports_hbbs="ports:\n      - \"${RUSTDESK_BIND_ADDR}:${RUSTDESK_NAT_PORT}:21115/tcp\"\n      - \"${RUSTDESK_BIND_ADDR}:${RUSTDESK_ID_PORT}:21116/tcp\"\n      - \"${RUSTDESK_BIND_ADDR}:${RUSTDESK_ID_PORT}:21116/udp\""
    ports_hbbr="ports:\n      - \"${RUSTDESK_BIND_ADDR}:${RUSTDESK_RELAY_PORT}:21117/tcp\""
  fi
  atomic_write_file "$RUSTDESK_COMPOSE_FILE" 600 <<EOF
services:
  hbbr:
    image: ${RUSTDESK_IMAGE}
    command: hbbr
    restart: unless-stopped
    ${network_line}
    volumes:
      - ${RUSTDESK_DATA_DIR}:/root
    $(printf '%b' "$ports_hbbr")
  hbbs:
    image: ${RUSTDESK_IMAGE}
    command: hbbs -r ${RUSTDESK_RELAY_HOST}:${RUSTDESK_RELAY_PORT}
    restart: unless-stopped
    ${network_line}
    depends_on:
      - hbbr
    volumes:
      - ${RUSTDESK_DATA_DIR}:/root
    $(printf '%b' "$ports_hbbs")
EOF
}

_rustdesk_compose() { compose_run "$RUSTDESK_INSTALL_DIR" "$RUSTDESK_COMPOSE_FILE" "$@"; }

_rustdesk_compose_capture() {
  local compose_cmd="$1"
  shift
  local -a base_args
  mapfile -t base_args < <(compose_base_args "$RUSTDESK_INSTALL_DIR" "$RUSTDESK_COMPOSE_FILE")
  # shellcheck disable=SC2086
  $compose_cmd "${base_args[@]}" "$@"
}

_rustdesk_stack_healthy() {
  local compose_cmd output
  compose_cmd="$(compose_command)"
  [[ -n "$compose_cmd" ]] || return 1
  output="$(_rustdesk_compose_capture "$compose_cmd" ps --services --filter status=running 2>/dev/null)" || return 1
  [[ "$(printf '%s\n' "$output" | LC_ALL=C sort)" == $'hbbr\nhbbs' ]]
}

_rustdesk_wait_healthy() {
  local attempt
  for ((attempt = 0; attempt < 30; attempt++)); do
    _rustdesk_stack_healthy && return 0
    sleep 1
  done
  return 1
}
_rustdesk_write_unit() {
  local unit="/etc/systemd/system/${RUSTDESK_SERVICE_NAME}.service" dir_q file_q cmd
  cmd="$(compose_command)"; [[ -n "$cmd" ]] || error "$(t app.rustdesk.error.compose)"
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
  systemctl daemon-reload || error "$(t app.rustdesk.error.reload)"
}

do_install() {
  preflight_check install; acquire_lock
  if ! command -v docker >/dev/null 2>&1 || ! compose_command | grep -q .; then
    apt-get update -qq || warn "apt-get update failed; attempting dependency installation"
    apt-get install -y --no-install-recommends docker.io docker-compose-plugin \
      || apt-get install -y --no-install-recommends docker.io docker-compose \
      || error "$(t app.rustdesk.error.dependencies)"
  fi
  systemctl enable --now docker || error "$(t app.rustdesk.error.docker_start)"
  mkdir -p "$RUSTDESK_INSTALL_DIR" "$RUSTDESK_DATA_DIR"
  _rustdesk_write_compose
  compose_require_runtime
  _rustdesk_write_unit
  app_save_config
  systemctl enable "$RUSTDESK_SERVICE_NAME" || error "$(t app.rustdesk.error.start "$RUSTDESK_SERVICE_NAME")"
  systemctl restart "$RUSTDESK_SERVICE_NAME" || error "$(t app.rustdesk.error.start "$RUSTDESK_SERVICE_NAME")"
  if ! _rustdesk_wait_healthy; then
    systemctl stop "$RUSTDESK_SERVICE_NAME" >/dev/null 2>&1 || true
    error "$(t app.rustdesk.error.health)"
  fi
  _rustdesk_show_key
}

_rustdesk_create_backup() {
  local archive="" stamp status=0 restart_failed=false was_active=false
  if systemctl is-active --quiet "$RUSTDESK_SERVICE_NAME"; then
    was_active=true
    systemctl stop "$RUSTDESK_SERVICE_NAME" || return 1
  fi
  mkdir -p "$RUSTDESK_BACKUP_DIR" || status=1
  stamp="$(date -u +%Y%m%d%H%M%S)-$$"
  if ((status == 0)); then
    archive="$(mktemp "${RUSTDESK_BACKUP_DIR}/rustdesk_${stamp}-XXXXXX.tar.gz")" || status=1
  fi
  if ((status == 0)); then
    backup_create_tar_archive "$archive" -C "$(dirname "$RUSTDESK_DATA_DIR")" "$(basename "$RUSTDESK_DATA_DIR")" \
      || status=1
  fi
  if ((status == 0)); then
    backup_finalize_archive "$archive" rustdesk "${RUSTDESK_IMAGE##*:}" 1 \
      || status=1
  fi
  if [[ "$was_active" == true ]] && ! systemctl start "$RUSTDESK_SERVICE_NAME"; then
    restart_failed=true
  fi
  if ((status != 0)); then
    if [[ -n "$archive" ]]; then
      rm -f -- "$archive" "${archive}.sha256" "${archive}.manifest.json"
    fi
    return 1
  fi
  if [[ "$restart_failed" == true ]]; then
    warn "$(t app.rustdesk.error.backup_restart "$archive" "$RUSTDESK_SERVICE_NAME")"
    return 1
  fi
  printf '%s\n' "$archive"
}

_rustdesk_restore_previous_image() {
  local previous_image="$1" target_image="$2"
  docker image tag "$previous_image" "$target_image" || return 1
  RUSTDESK_IMAGE="$target_image"
  _rustdesk_write_compose || return 1
  compose_run "$RUSTDESK_INSTALL_DIR" "$RUSTDESK_COMPOSE_FILE" up -d
}

do_update() {
  acquire_lock; app_load_config; preflight_check update
  _rustdesk_stack_healthy || error "$(t app.rustdesk.error.update_prerequisite)"
  local container_id previous_image previous_hbbr_image rollback_image target_image snapshot
  container_id="$(_rustdesk_compose_capture "$(compose_command)" ps -q hbbs 2>/dev/null | head -1)"
  [[ -n "$container_id" ]] || error "$(t app.rustdesk.error.rollback_info)"
  previous_image="$(docker inspect --format '{{.Image}}' "$container_id" 2>/dev/null)" \
    || error "$(t app.rustdesk.error.rollback_info)"
  container_id="$(_rustdesk_compose_capture "$(compose_command)" ps -q hbbr 2>/dev/null | head -1)"
  [[ -n "$container_id" ]] || error "$(t app.rustdesk.error.rollback_info)"
  previous_hbbr_image="$(docker inspect --format '{{.Image}}' "$container_id" 2>/dev/null)" \
    || error "$(t app.rustdesk.error.rollback_info)"
  [[ "$previous_hbbr_image" == "$previous_image" ]] || error "$(t app.rustdesk.error.mixed_images)"
  target_image="$RUSTDESK_IMAGE"
  snapshot="$(_rustdesk_create_backup)" || error "$(t app.rustdesk.error.backup)"
  rollback_image="rustdesk/rollback:$(date -u +%Y%m%d%H%M%S)-$$"
  docker image tag "$previous_image" "$rollback_image" \
    || error "$(t app.rustdesk.error.image_retain)"
  _rustdesk_write_compose
  if compose_run "$RUSTDESK_INSTALL_DIR" "$RUSTDESK_COMPOSE_FILE" pull \
      && compose_run "$RUSTDESK_INSTALL_DIR" "$RUSTDESK_COMPOSE_FILE" up -d \
      && _rustdesk_wait_healthy; then
    app_save_config
    success "$(t app.rustdesk.success.updated "$target_image" "$snapshot")"
    return 0
  fi

  warn "$(t app.rustdesk.warn.update_rollback)"
  if ! _rustdesk_restore_previous_image "$previous_image" "$target_image"; then
    RUSTDESK_IMAGE="$target_image"
    _rustdesk_write_compose
    error "$(t app.rustdesk.error.image_rollback "$rollback_image" "$snapshot")"
  fi
  if ! backup_restore_data_dir "$RUSTDESK_DATA_DIR" "$RUSTDESK_SERVICE_NAME" "$snapshot" \
      || ! _rustdesk_wait_healthy; then
    RUSTDESK_IMAGE="$target_image"
    _rustdesk_write_compose
    app_save_config
    error "$(t app.rustdesk.error.data_rollback "$target_image" "$snapshot")"
  fi
  RUSTDESK_IMAGE="$target_image"
  _rustdesk_write_compose
  app_save_config
  error "$(t app.rustdesk.error.update_rolled_back "$target_image" "$snapshot")"
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
  if _rustdesk_stack_healthy; then
    success "$(t app.rustdesk.success.running)"
  else
    warn "$(t app.rustdesk.warn.services)"
  fi
  _rustdesk_show_key
}
do_backup() {
  acquire_lock; app_load_config; preflight_check backup
  local archive
  archive="$(_rustdesk_create_backup)" || error "Failed to create verified RustDesk backup"
  success "$(t app.rustdesk.success.backup "$archive")"
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
      || error "$(t app.rustdesk.error.restore_archive "$archive")"
  else
    archive="$(backup_latest_archive "$RUSTDESK_BACKUP_DIR" 'rustdesk_*.tar.gz' || true)"
    [[ -n "$archive" ]] || error "$(t app.rustdesk.error.no_backups "$RUSTDESK_BACKUP_DIR")"
  fi
  local rollback_snapshot
  rollback_snapshot="$(_rustdesk_create_backup)" || error "$(t app.rustdesk.error.backup)"
  backup_restore_data_dir "$RUSTDESK_DATA_DIR" "$RUSTDESK_SERVICE_NAME" "$archive"
  if _rustdesk_wait_healthy; then
    return 0
  fi
  warn "$(t app.rustdesk.warn.update_rollback)"
  if backup_restore_data_dir "$RUSTDESK_DATA_DIR" "$RUSTDESK_SERVICE_NAME" "$rollback_snapshot" \
      && _rustdesk_wait_healthy; then
    error "$(t app.rustdesk.error.restore_health_rollback "$rollback_snapshot")"
  fi
  error "$(t app.rustdesk.error.data_rollback "$RUSTDESK_IMAGE" "$rollback_snapshot")"
}
do_uninstall() {
  acquire_lock; app_load_config; preflight_check uninstall
  systemctl disable --now "$RUSTDESK_SERVICE_NAME" || error "$(t app.rustdesk.error.stop "$RUSTDESK_SERVICE_NAME")"
  rm -f "/etc/systemd/system/${RUSTDESK_SERVICE_NAME}.service"
  systemctl daemon-reload || error "$(t app.rustdesk.error.reload)"
  info "$(t app.rustdesk.info.uninstalled "$RUSTDESK_DATA_DIR")"
}
