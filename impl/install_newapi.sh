#!/bin/bash
set -euo pipefail
umask 077
DOMAIN="api.tarxf.com"
PORT=8080
INSTALL_DIR="/opt/new-api"
DATA_DIR="/opt/new-api/data"
LOG_DIR="/opt/new-api/logs"
SERVICE_NAME="new-api"
SERVICE_USER="newapi"
GITHUB_REPO="QuantumNous/new-api"
BACKUP_DIR="/opt/new-api-backups"
BACKUP_KEEP_DAYS=30
BIN_PATH="${INSTALL_DIR}/new-api"
LOG_FILE="${LOG_DIR}/new-api.log"
CONF_FILE="/etc/new-api-deploy.conf"
CONFIG_KEYS=(
  DOMAIN PORT INSTALL_DIR DATA_DIR LOG_DIR SERVICE_NAME SERVICE_USER
  GITHUB_REPO BACKUP_DIR BACKUP_KEEP_DAYS INSTALLED_VERSION
)
preflight_check() {
  [[ $EUID -ne 0 ]] && error "$(t error.root_required "$0" "${1:-}")"
  command -v apt-get &>/dev/null \
    || error "$(t app.newapi.error.apt_only)"
  ARCH=$(uname -m)
  case $ARCH in
    x86_64)  BIN_ARCH="amd64" ;;
    aarch64) BIN_ARCH="arm64" ;;
    *) error "$(t app.newapi.error.arch "$ARCH")" ;;
  esac
}
LOCK_FILE="/var/lock/new-api-deploy.lock"
check_connectivity() {
  check_connectivity_urls \
    "https://api.github.com" \
    "https://github.com" \
    "https://objects.githubusercontent.com" && return 0
  error "$(t app.newapi.error.github_unreachable)"
}
save_config() {
  write_config_file "$CONF_FILE" "${CONFIG_KEYS[@]}"
  success "$(t config.saved "$CONF_FILE")"
}
load_config() {
  [[ -f "$CONF_FILE" ]] || return 0
  load_config_file "$CONF_FILE" "${CONFIG_KEYS[@]}" || return 0
  BIN_PATH="${INSTALL_DIR}/new-api"
  LOG_FILE="${LOG_DIR}/new-api.log"
  success "$(t config.loaded "$CONF_FILE")"
}
get_latest_release() {
  local json tag
  json=$(curl -fsSL --max-time 15 \
    "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" 2>/dev/null) \
    || { warn "$(t app.newapi.warn.github_api)"; echo ""; return; }
  if echo "test" | grep -qP 'test' 2>/dev/null; then
    tag=$(echo "$json" | grep -oP '"tag_name"\s*:\s*"\K[^"]+' 2>/dev/null | head -1 || true)
  fi
  if [[ -z "${tag:-}" ]]; then
    tag=$(echo "$json" | grep '"tag_name"' | head -1 \
      | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' 2>/dev/null || true)
  fi
  if [[ "${tag:-}" =~ ^v?[0-9] ]]; then
    echo "$tag"
  else
    echo ""
  fi
}
get_download_url() {
  local version="$1"
  if [[ "${BIN_ARCH}" == "amd64" ]]; then
    echo "https://github.com/${GITHUB_REPO}/releases/download/${version}/new-api-${version}"
  else
    echo "https://github.com/${GITHUB_REPO}/releases/download/${version}/new-api-arm64-${version}"
  fi
}
verify_binary() {
  local bin="$1"
  [[ -s "$bin" ]] || error "$(t app.newapi.error.binary_empty)"
  local size
  size=$(wc -c < "$bin")
  [[ $size -lt 1048576 ]] \
    && error "$(t app.newapi.error.binary_too_small "$size")"
  local magic
  magic=$(dd if="$bin" bs=1 count=4 2>/dev/null | od -An -tx1 | tr -d ' \n' 2>/dev/null || true)
  if [[ "$magic" != "7f454c46" ]]; then
    error "$(t app.newapi.error.binary_not_elf "${magic:-read failed}")"
  fi
  local size_mb=$(( size / 1024 / 1024 ))
  success "$(t app.newapi.success.binary_verified "$size_mb")"
}
_health_check() {
  local elapsed=0
  local HTTP_CODE
  until HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}" --max-time 5 \
      "http://127.0.0.1:${PORT}/" 2>/dev/null || echo "000") \
      && [[ "$HTTP_CODE" =~ ^(200|301|302)$ ]]; do
    sleep 1
    elapsed=$(( elapsed + 1 ))
    [[ $elapsed -ge 15 ]] && break
  done
  if [[ "$HTTP_CODE" =~ ^(200|301|302)$ ]]; then
    success "$(t app.newapi.success.http_health "$HTTP_CODE")"
  else
    warn "$(t app.newapi.warn.http_health "$HTTP_CODE")"
    warn "$(t app.newapi.warn.debug_command "$SERVICE_NAME")"
  fi
}
_write_systemd_unit() {
  local session_secret="$1"
  cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
[Unit]
Description=New API - LLM API Aggregation Gateway
Documentation=https://github.com/${GITHUB_REPO}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_USER}
WorkingDirectory=${DATA_DIR}

ExecStart=${BIN_PATH} \\
    --port ${PORT} \\
    --log-dir ${LOG_DIR}

# Restart automatically, with burst limits to avoid a crash loop.
Restart=always
RestartSec=5
StartLimitInterval=60
StartLimitBurst=5

# Environment variables.
Environment="PORT=${PORT}"
Environment="SESSION_SECRET=${session_secret}"
Environment="TZ=Asia/Shanghai"
Environment="SQLITE_BUSY_TIMEOUT=3000"
# Prefer Go DNS resolution to reduce SSE timeout stalls.
Environment="GODEBUG=netdns=go"

# File descriptor and process limits for API gateway workloads.
LimitNOFILE=65536
LimitNPROC=512

# Security hardening.
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
# Keep the filesystem read-only except for data and log directories.
ReadWritePaths=${DATA_DIR} ${LOG_DIR}

# Send logs to systemd journal; inspect with journalctl -u ${SERVICE_NAME}.
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}

[Install]
WantedBy=multi-user.target
EOF
}
_configure_firewall() {
  local FW_DONE=false
  if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw allow "${PORT}/tcp" comment "New API" > /dev/null
    success "$(t app.newapi.success.ufw_port "$PORT")"
    FW_DONE=true
  fi
  if ! $FW_DONE && command -v iptables &>/dev/null; then
    if ! iptables -C INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null; then
      iptables -A INPUT -p tcp --dport "$PORT" -j ACCEPT
    fi
    if command -v netfilter-persistent &>/dev/null; then
      netfilter-persistent save 2>/dev/null \
        && success "$(t app.newapi.success.iptables_saved)" || true
    elif command -v iptables-save &>/dev/null; then
      mkdir -p /etc/iptables
      iptables-save > /etc/iptables/rules.v4 2>/dev/null \
        && info "$(t app.newapi.info.iptables_rules_written)" \
        || warn "$(t app.newapi.warn.iptables_write_failed)"
    else
      warn "$(t app.newapi.warn.iptables_not_persisted)"
    fi
    success "$(t app.newapi.success.iptables_port "$PORT")"
    FW_DONE=true
  fi
  $FW_DONE || warn "$(t app.newapi.warn.no_firewall "$PORT")"
}
_write_logrotate() {
  cat > /etc/logrotate.d/new-api << LOGR
${LOG_DIR}/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    # copytruncate avoids requiring SIGHUP support from the service.
    # A tiny number of log lines can be lost during rotation.
    copytruncate
}
LOGR
  success "$(t app.newapi.success.logrotate)"
}
_write_backup_script() {
  mkdir -p "$BACKUP_DIR"
  local msg_start msg_data_missing msg_wal_ok msg_wal_warn msg_integrity_warn msg_backup_ok msg_tar_failed msg_removed_old msg_done
  msg_start="$(t app.newapi.backup.log.start)"
  msg_data_missing="$(t app.newapi.backup.log.data_missing '%s')"
  msg_wal_ok="$(t app.newapi.backup.log.wal_ok)"
  msg_wal_warn="$(t app.newapi.backup.log.wal_warn)"
  msg_integrity_warn="$(t app.newapi.backup.log.integrity_warn '%s')"
  msg_backup_ok="$(t app.newapi.backup.log.ok '%s' '%s')"
  msg_tar_failed="$(t app.newapi.backup.log.tar_failed)"
  msg_removed_old="$(t app.newapi.backup.log.removed_old '%s' '%s')"
  msg_done="$(t app.newapi.backup.log.done)"
  cat > /usr/local/bin/new-api-backup << BKSH_HEADER
#!/bin/bash
# Auto-generated New API backup script. Do not edit this file manually.
# Regenerate it with: sudo bash install_newapi.sh install
set -euo pipefail
umask 077

BACKUP_DIR="${BACKUP_DIR}"
DATA_DIR="${DATA_DIR}"
SERVICE_NAME="${SERVICE_NAME}"
KEEP_DAYS="${BACKUP_KEEP_DAYS}"
MSG_START="${msg_start}"
MSG_DATA_MISSING="${msg_data_missing}"
MSG_WAL_OK="${msg_wal_ok}"
MSG_WAL_WARN="${msg_wal_warn}"
MSG_INTEGRITY_WARN="${msg_integrity_warn}"
MSG_BACKUP_OK="${msg_backup_ok}"
MSG_TAR_FAILED="${msg_tar_failed}"
MSG_REMOVED_OLD="${msg_removed_old}"
MSG_DONE="${msg_done}"
BKSH_HEADER
  cat >> /usr/local/bin/new-api-backup << 'BKSH_BODY'

LOG="${BACKUP_DIR}/backup.log"
TS=$(date +%Y%m%d_%H%M%S)
ARCHIVE="${BACKUP_DIR}/new-api_${TS}.tar.gz"
ARCHIVE_TMP="${ARCHIVE}.tmp"

_log() { echo "$(date '+%F %T')  $*" >> "$LOG"; }
_log "── ${MSG_START} ────────────────────────────────────"

# Refuse to create an empty backup when the data directory is missing.
if [[ ! -d "${DATA_DIR}" ]]; then
  _log "$(printf "$MSG_DATA_MISSING" "$DATA_DIR")"
  exit 1
fi

mkdir -p "${BACKUP_DIR}"

# Flush SQLite WAL data and run an integrity check before archiving.
DB_FILE="${DATA_DIR}/one-api.db"
if command -v sqlite3 &>/dev/null && [[ -f "${DB_FILE}" ]]; then
  if sqlite3 "${DB_FILE}" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null; then
    _log "$MSG_WAL_OK"
  else
    _log "$MSG_WAL_WARN"
  fi
  IC=$(sqlite3 "${DB_FILE}" "PRAGMA integrity_check;" 2>/dev/null || echo "error")
  if [[ "$IC" != "ok" ]]; then
    _log "$(printf "$MSG_INTEGRITY_WARN" "$IC")"
  fi
fi

# Write to a temporary archive first, then move it into place atomically.
if tar -czf "${ARCHIVE_TMP}" \
    --exclude="*.log" --exclude="*.log.*" \
    -C "$(dirname "${DATA_DIR}")" "$(basename "${DATA_DIR}")" 2>&1 | \
    while IFS= read -r line; do _log "[TAR] ${line}"; done; then
  if mv "${ARCHIVE_TMP}" "${ARCHIVE}"; then
    SIZE=$(du -sh "${ARCHIVE}" 2>/dev/null | awk '{print $1}')
    _log "$(printf "$MSG_BACKUP_OK" "$ARCHIVE" "$SIZE")"
  else
    rm -f "${ARCHIVE_TMP}"
    _log "$MSG_TAR_FAILED"
    exit 1
  fi
else
  rm -f "${ARCHIVE_TMP}"
  _log "$MSG_TAR_FAILED"
  exit 1
fi

# Remove backups older than the configured retention window.
if [[ "${KEEP_DAYS}" -gt 0 ]]; then
  REMOVED=0
  while IFS= read -r f; do
    rm -f "$f" && REMOVED=$(( REMOVED + 1 )) || true
  done < <(find "${BACKUP_DIR}" -maxdepth 1 -name "new-api_*.tar.gz" -mtime "+${KEEP_DAYS}" 2>/dev/null)
  [[ $REMOVED -gt 0 ]] && _log "$(printf "$MSG_REMOVED_OLD" "$REMOVED" "$KEEP_DAYS")"
fi

_log "── ${MSG_DONE} ────────────────────────────────────"
BKSH_BODY
  chmod 750 /usr/local/bin/new-api-backup
  success "$(t app.newapi.success.backup_script)"
}
_backup_silent() {
  local label="${1:-manual}"
  if [[ ! -d "$DATA_DIR" ]]; then
    warn "$(t app.newapi.warn.silent_data_missing "$DATA_DIR")"
    return 1
  fi
  mkdir -p "$BACKUP_DIR"
  local archive="${BACKUP_DIR}/new-api_${label}_$(date +%Y%m%d_%H%M%S).tar.gz"
  local archive_tmp="${archive}.tmp"
  local DB_FILE="${DATA_DIR}/one-api.db"
  if command -v sqlite3 &>/dev/null && [[ -f "$DB_FILE" ]]; then
    sqlite3 "$DB_FILE" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    local _ic
    _ic=$(sqlite3 "$DB_FILE" "PRAGMA integrity_check;" 2>/dev/null || echo "error")
    [[ "$_ic" != "ok" ]] && warn "$(t app.newapi.warn.sqlite_integrity "$_ic")"
  fi
  if tar -czf "$archive_tmp" \
      --exclude="*.log" --exclude="*.log.*" \
      -C "$(dirname "$DATA_DIR")" "$(basename "$DATA_DIR")" 2>&1 >&2; then
    if mv "$archive_tmp" "$archive"; then
      local sz; sz=$(du -sh "$archive" 2>/dev/null | awk '{print $1}')
      success "$(t app.newapi.success.silent_backup "$archive" "$sz")"
    else
      rm -f "$archive_tmp"
      warn "$(t app.newapi.warn.silent_backup_failed)"
      return 1
    fi
  else
    rm -f "$archive_tmp"
    warn "$(t app.newapi.warn.silent_backup_failed)"
    return 1
  fi
}
_print_install_summary() {
  local version="$1"
  local INTERNAL_IP
  INTERNAL_IP=$(hostname -I | awk '{print $1}')
  echo ""
  echo -e "${BOLD}${GREEN}"
  echo "  ╔══════════════════════════════════════════════════════╗"
  echo "  ║           $(t app.newapi.summary.title)                     ║"
  echo "  ╠══════════════════════════════════════════════════════╣"
  echo -e "  ║  $(t app.newapi.summary.public)  ${CYAN}https://${DOMAIN}${GREEN}"
  echo -e "  ║  $(t app.newapi.summary.internal)  ${CYAN}http://${INTERNAL_IP}:${PORT}${GREEN}"
  echo "  ╠══════════════════════════════════════════════════════╣"
  echo -e "  ║  $(t app.newapi.summary.default_user)  ${YELLOW}root${GREEN}"
  echo -e "  ║  $(t app.newapi.summary.default_password)  ${YELLOW}123456${GREEN}  <- $(t app.newapi.summary.change_password)"
  echo "  ╠══════════════════════════════════════════════════════╣"
  echo -e "  ║  $(t app.newapi.summary.api_url)  ${CYAN}https://${DOMAIN}/v1${GREEN}"
  echo -e "  ║  $(t app.newapi.summary.version)  ${YELLOW}${version}${GREEN}"
  echo "  ╠══════════════════════════════════════════════════════╣"
  echo -e "  ║  $(t app.newapi.summary.data_dir)  ${YELLOW}${DATA_DIR}${GREEN}"
  echo -e "  ║  $(t app.newapi.summary.log_dir)  ${YELLOW}${LOG_DIR}${GREEN}"
  echo -e "  ║  $(t app.newapi.summary.backup_dir)  ${YELLOW}${BACKUP_DIR}${GREEN}"
  echo "  ╚══════════════════════════════════════════════════════╝"
  echo -e "${NC}"
  echo -e "  ${BOLD}$(t app.newapi.summary.management)${NC}"
  echo -e "    ${CYAN}bash $0 status${NC}      - $(t app.newapi.summary.status_cmd)"
  echo -e "    ${CYAN}bash $0 update${NC}      - $(t app.newapi.summary.update_cmd)"
  echo -e "    ${CYAN}bash $0 backup${NC}      - $(t app.newapi.summary.backup_cmd)"
  echo -e "    ${CYAN}bash $0 uninstall${NC}   - $(t app.newapi.summary.uninstall_cmd)"
  echo ""
  echo -e "  ${BOLD}$(t app.newapi.summary.systemd)${NC}"
  echo -e "    ${CYAN}systemctl status ${SERVICE_NAME}${NC}     $(t app.newapi.summary.show_status)"
  echo -e "    ${CYAN}journalctl -u ${SERVICE_NAME} -f${NC}     $(t app.newapi.summary.live_logs)"
  echo -e "    ${CYAN}systemctl restart ${SERVICE_NAME}${NC}    $(t app.newapi.summary.restart)"
  echo ""
  echo -e "  ${YELLOW}${BOLD}$(t app.newapi.summary.cf_ssl)${NC}"
  echo -e "  ${YELLOW}${BOLD}$(t app.newapi.summary.cf_sse)${NC}"
  echo ""
}
do_install() {
  show_banner
  preflight_check "install"
  acquire_lock
  step "$(t app.newapi.step.latest)"
  check_connectivity
  info "$(t app.newapi.info.query_latest)"
  local LATEST
  LATEST=$(get_latest_release)
  [[ -z "$LATEST" ]] && error "$(t app.newapi.error.version_failed)"
  success "$(t app.newapi.success.latest "${BOLD}${LATEST}${NC}")"
  local DOWNLOAD_URL
  DOWNLOAD_URL=$(get_download_url "$LATEST")
  step "$(t app.newapi.step.deps)"
  apt-get update -qq
  apt-get install -y -qq curl ca-certificates sqlite3
  success "$(t app.newapi.success.deps)"
  step "$(t app.newapi.step.user_dirs)"
  if ! id "$SERVICE_USER" &>/dev/null; then
    useradd -r -s /usr/sbin/nologin -d "$INSTALL_DIR" "$SERVICE_USER"
    success "$(t app.newapi.success.user_created "$SERVICE_USER")"
  else
    info "$(t app.newapi.info.user_exists "$SERVICE_USER")"
  fi
  mkdir -p "$INSTALL_DIR" "$DATA_DIR" "$LOG_DIR" "$BACKUP_DIR"
  chown -R "${SERVICE_USER}:${SERVICE_USER}" "$INSTALL_DIR" "$LOG_DIR" "$BACKUP_DIR"
  success "$(t app.newapi.success.dirs "$INSTALL_DIR" "$DATA_DIR" "$LOG_DIR")"
  step "$(t app.newapi.step.download "$BIN_ARCH")"
  info "$(t app.newapi.info.download_url "$DOWNLOAD_URL")"
  local TMP_BIN
  TMP_BIN=$(mktemp "${INSTALL_DIR}/new-api.tmp.XXXXXX")
  if ! curl -fL --progress-bar -o "$TMP_BIN" "$DOWNLOAD_URL"; then
    rm -f "$TMP_BIN"
    error "$(t app.newapi.error.download "$GITHUB_REPO")"
  fi
  verify_binary "$TMP_BIN"
  if [[ -f "$BIN_PATH" ]]; then
    local OLD_TS; OLD_TS=$(date +%Y%m%d_%H%M%S)
    mv "$BIN_PATH" "${INSTALL_DIR}/new-api.bak.${OLD_TS}"
    warn "$(t app.newapi.warn.old_binary_backup "new-api.bak.${OLD_TS}")"
  fi
  mv "$TMP_BIN" "$BIN_PATH"
  chmod +x "$BIN_PATH"
  chown -R "${SERVICE_USER}:${SERVICE_USER}" "$INSTALL_DIR"
  success "$(t app.newapi.success.binary_installed "$BIN_PATH")"
  step "$(t app.newapi.step.secret)"
  local SESSION_SECRET
  SESSION_SECRET=$(tr -dc 'A-Za-z0-9!@#$%^&*' </dev/urandom 2>/dev/null | head -c 40; true)
  success "$(t app.newapi.success.secret)"
  step "$(t app.newapi.step.systemd)"
  _write_systemd_unit "$SESSION_SECRET"
  success "$(t app.newapi.success.systemd "$SERVICE_NAME")"
  step "$(t app.newapi.step.firewall)"
  _configure_firewall
  step "$(t app.newapi.step.logrotate)"
  _write_logrotate
  step "$(t app.newapi.step.cron)"
  _write_backup_script
  echo "30 3 * * * root /bin/bash /usr/local/bin/new-api-backup" \
    > /etc/cron.d/new-api-backup
  chmod 644 /etc/cron.d/new-api-backup
  success "$(t app.newapi.success.cron "$BACKUP_KEEP_DAYS")"
  step "$(t app.newapi.step.start)"
  if ss -ltn 2>/dev/null | grep -qE ":${PORT}[[:space:]]"; then
    local _port_owner
    _port_owner=$(ss -ltnp 2>/dev/null | grep ":${PORT}" | awk '{print $NF}' | head -1 || t app.newapi.status.unknown_process)
    warn "$(t app.newapi.warn.port_used "$PORT" "$_port_owner")"
    warn "$(t app.newapi.warn.port_release)"
  fi
  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME" --quiet
  systemctl restart "$SERVICE_NAME"
  if wait_for_service "$SERVICE_NAME" 20; then
    success "$(t app.newapi.success.service_started)"
    systemctl status "$SERVICE_NAME" --no-pager -l | head -12 | sed 's/^/  /' >&2
  else
    warn "$(t app.newapi.warn.start_rollback)"
    systemctl stop    "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    systemctl daemon-reload 2>/dev/null || true
    rm -f "$BIN_PATH"
    error "$(t app.newapi.error.install_start_failed "$SERVICE_NAME")"
  fi
  step "$(t app.newapi.step.health)"
  INSTALLED_VERSION="$LATEST"
  save_config
  _health_check
  _print_install_summary "$LATEST"
}
do_update() {
  show_banner
  preflight_check "update"
  load_config
  acquire_lock
  [[ ! -x "$BIN_PATH" ]] \
    && error "$(t app.newapi.error.not_installed "$BIN_PATH")"
  step "$(t app.newapi.step.check_update)"
  check_connectivity
  info "$(t app.newapi.info.query_latest)"
  local LATEST
  LATEST=$(get_latest_release)
  [[ -z "$LATEST" ]] && error "$(t app.newapi.error.latest_failed)"
  local CURRENT="${INSTALLED_VERSION:-unknown}"
  info "$(t app.newapi.info.current "${YELLOW}${CURRENT}${NC}")"
  info "$(t app.newapi.info.github_latest "${YELLOW}${LATEST}${NC}")"
  if [[ "$CURRENT" == "$LATEST" ]]; then
    success "$(t app.newapi.success.already_latest "$LATEST")"
    exit 0
  fi
  local _pre_svc_state
  _pre_svc_state=$(systemctl is-active "$SERVICE_NAME" 2>/dev/null || echo "inactive")
  if [[ "$_pre_svc_state" == "failed" ]]; then
    warn "$(t app.newapi.warn.pre_failed_state)"
    warn "$(t app.newapi.warn.pre_failed_debug "$SERVICE_NAME")"
  fi
  step "$(t app.newapi.step.pre_backup)"
  _backup_silent "pre-update" || warn "$(t app.newapi.warn.pre_backup_failed)"
  step "$(t app.newapi.step.download_update "$CURRENT" "$LATEST")"
  local DOWNLOAD_URL
  DOWNLOAD_URL=$(get_download_url "$LATEST")
  info "$(t app.newapi.info.download_url "$DOWNLOAD_URL")"
  local TMP_BIN
  TMP_BIN=$(mktemp "${INSTALL_DIR}/new-api.tmp.XXXXXX")
  if ! curl -fL --progress-bar -o "$TMP_BIN" "$DOWNLOAD_URL"; then
    rm -f "$TMP_BIN"
    error "$(t app.newapi.error.update_download)"
  fi
  verify_binary "$TMP_BIN"
  step "$(t app.newapi.step.replace_restart)"
  local BAK_TS; BAK_TS=$(date +%Y%m%d_%H%M%S)
  local BAK_PATH="${INSTALL_DIR}/new-api.bak.${BAK_TS}"
  cp "$BIN_PATH" "$BAK_PATH"
  info "$(t app.newapi.info.old_binary "$BAK_PATH")"
  info "$(t app.newapi.info.stop_service)"
  systemctl stop "$SERVICE_NAME" 2>/dev/null || true
  mv "$TMP_BIN" "$BIN_PATH"
  chmod +x "$BIN_PATH"
  chown "${SERVICE_USER}:${SERVICE_USER}" "$BIN_PATH"
  systemctl daemon-reload
  systemctl start "$SERVICE_NAME"
  if wait_for_service "$SERVICE_NAME" 20; then
    success "$(t app.newapi.success.updated_started)"
    INSTALLED_VERSION="$LATEST"
    save_config
    local -a _old_baks
    mapfile -t _old_baks < <(
      find "$INSTALL_DIR" -maxdepth 1 -name "new-api.bak.*" -type f \
        -printf '%T@ %p\n' 2>/dev/null | sort -rn | awk 'NR>3{print $2}'
    )
    if [[ ${#_old_baks[@]} -gt 0 ]]; then
      rm -f "${_old_baks[@]}"
      info "$(t app.newapi.info.cleaned_old "${#_old_baks[@]}")"
    fi
    _health_check
    echo ""
    echo -e "  ${BOLD}${GREEN}$(t app.newapi.success.update_done "${YELLOW}${CURRENT}${GREEN}" "${YELLOW}${LATEST}${NC}")${NC}"
    echo ""
  else
    warn "$(t app.newapi.warn.update_start_failed "$LATEST" "$CURRENT")"
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    mv "$BAK_PATH" "$BIN_PATH"
    chmod +x "$BIN_PATH"
    chown "${SERVICE_USER}:${SERVICE_USER}" "$BIN_PATH"
    systemctl start "$SERVICE_NAME" 2>/dev/null || true
    if wait_for_service "$SERVICE_NAME" 15; then
      success "$(t app.newapi.success.rollback "$CURRENT")"
    else
      warn "$(t app.newapi.warn.rollback_start_failed "$SERVICE_NAME")"
    fi
    error "$(t app.newapi.error.update_failed "$CURRENT" "$SERVICE_NAME" "$BAK_PATH")"
  fi
}
do_backup() {
  show_banner
  preflight_check "backup"
  load_config
  acquire_lock
  [[ ! -d "$DATA_DIR" ]] \
    && error "$(t app.newapi.error.data_missing_install "$DATA_DIR")"
  step "$(t app.newapi.step.manual_backup)"
  mkdir -p "$BACKUP_DIR"
  local DB_FILE="${DATA_DIR}/one-api.db"
  if command -v sqlite3 &>/dev/null && [[ -f "$DB_FILE" ]]; then
    sqlite3 "$DB_FILE" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null \
      && success "$(t app.newapi.success.wal)" \
      || warn "$(t app.newapi.warn.wal)"
    local _ic
    _ic=$(sqlite3 "$DB_FILE" "PRAGMA integrity_check;" 2>/dev/null || echo "error")
    if [[ "$_ic" == "ok" ]]; then
      success "$(t app.newapi.success.sqlite_integrity)"
    else
      warn "$(t app.newapi.warn.sqlite_integrity_failed "$_ic")"
    fi
  fi
  local TS; TS=$(date +%Y%m%d_%H%M%S)
  local ARCHIVE="${BACKUP_DIR}/new-api_${TS}.tar.gz"
  local ARCHIVE_TMP="${ARCHIVE}.tmp"
  info "$(t app.newapi.info.backing_up "$DATA_DIR" "$ARCHIVE")"
  if tar -czf "$ARCHIVE_TMP" \
      --exclude="*.log" --exclude="*.log.*" \
      -C "$(dirname "$DATA_DIR")" "$(basename "$DATA_DIR")" 2>&1; then
    if mv "$ARCHIVE_TMP" "$ARCHIVE"; then
      local SZ; SZ=$(du -sh "$ARCHIVE" 2>/dev/null | awk '{print $1}')
      success "$(t app.newapi.success.backup_done "$ARCHIVE" "$SZ")"
    else
      rm -f "$ARCHIVE_TMP"
      error "$(t app.newapi.error.backup_failed "$BACKUP_DIR")"
    fi
  else
    rm -f "$ARCHIVE_TMP"
    error "$(t app.newapi.error.backup_failed "$BACKUP_DIR")"
  fi
  local _cleaned=0
  while IFS= read -r f; do
    rm -f "$f" && _cleaned=$(( _cleaned + 1 )) || true
  done < <(find "$BACKUP_DIR" -maxdepth 1 -name "new-api_*.tar.gz" \
           -mtime "+${BACKUP_KEEP_DAYS}" 2>/dev/null)
  [[ $_cleaned -gt 0 ]] && info "$(t app.newapi.info.cleaned_backups "$_cleaned" "$BACKUP_KEEP_DAYS")"
  echo ""
  info "$(t app.newapi.info.backup_list "$BACKUP_DIR")"
  local -a _bak_list
  mapfile -t _bak_list < <(
    find "$BACKUP_DIR" -maxdepth 1 -name "new-api_*.tar.gz" \
      -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -10 | awk '{print $2}'
  )
  if [[ ${#_bak_list[@]} -gt 0 ]]; then
    local _sz
    for _f in "${_bak_list[@]}"; do
      _sz=$(du -sh "$_f" 2>/dev/null | cut -f1 || echo "?")
      printf '  %-55s  %s\n' "$(basename "$_f")" "$_sz" >&2
    done
    local _total
    _total=$(find "$BACKUP_DIR" -maxdepth 1 -name "new-api_*.tar.gz" 2>/dev/null | wc -l)
    info "$(t app.newapi.info.backup_total "$_total")"
  else
    warn "$(t app.newapi.warn.no_backups)"
  fi
  echo ""
  release_lock
}
do_status() {
  show_banner
  preflight_check "status"
  load_config
  [[ $EUID -ne 0 ]] && warn "$(t app.newapi.warn.non_root_status "$0")"
  step "$(t app.newapi.step.status)"
  echo -e "\n${BOLD}[$(t app.newapi.status.systemd)]${NC}"
  systemctl is-active --quiet "$SERVICE_NAME" \
    && echo -e "  ${GREEN}[✓]${NC} ${SERVICE_NAME} $(t app.newapi.status.running)" \
    || echo -e "  ${RED}[✗]${NC} ${SERVICE_NAME} $(t app.newapi.status.not_running)"
  systemctl status "$SERVICE_NAME" --no-pager -l 2>/dev/null \
    | tail -n +3 | head -10 | sed 's/^/  /' || true
  echo -e "\n${BOLD}[$(t app.newapi.status.version_info)]${NC}"
  if [[ -x "$BIN_PATH" ]]; then
    echo -e "  $(t app.newapi.status.recorded_version):  ${YELLOW}${INSTALLED_VERSION:-$(t app.newapi.status.unknown)}${NC}"
    echo -e "  $(t app.newapi.status.binary_path): ${BIN_PATH}"
    echo -e "  $(t app.newapi.status.binary_time): $(stat -c '%y' "$BIN_PATH" 2>/dev/null | cut -d'.' -f1 || t app.newapi.status.unknown)"
    echo -e "  $(t app.newapi.status.binary_size): $(du -sh "$BIN_PATH" 2>/dev/null | cut -f1 || t app.newapi.status.unknown)"
  else
    echo -e "  ${RED}[✗]${NC} $(t app.newapi.status.binary_missing "$BIN_PATH")"
  fi
  echo -e "\n${BOLD}[$(t app.newapi.status.resources)]${NC}"
  local pid
  pid=$(systemctl show "$SERVICE_NAME" --property=MainPID --value 2>/dev/null || echo "0")
  if [[ "$pid" -gt 0 ]] 2>/dev/null; then
    local mem cpu
    mem=$(ps -p "$pid" -o rss= 2>/dev/null | awk '{printf "%.1f MB", $1/1024}' || echo "N/A")
    cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null | tr -d ' ' || echo "N/A")
    echo -e "  $(t app.newapi.status.pid):  ${pid}"
    echo -e "  $(t app.newapi.status.memory):  ${mem}"
    echo -e "  $(t app.newapi.status.cpu):  ${cpu}%"
    echo -e "  $(t app.newapi.status.start_time):  $(ps -p "$pid" -o lstart= 2>/dev/null | tr -s ' ' || echo 'N/A')"
  else
    echo -e "  ${YELLOW}[!]${NC} $(t app.newapi.status.no_process)"
  fi
  echo -e "\n${BOLD}[$(t app.newapi.status.directories)]${NC}"
  if [[ -d "$DATA_DIR" ]]; then
    local data_size; data_size=$(du -sh "$DATA_DIR" 2>/dev/null | awk '{print $1}')
    echo -e "  $(t app.newapi.status.data_dir):  ${DATA_DIR} (${data_size})"
    if [[ -f "${DATA_DIR}/one-api.db" ]]; then
      local db_size; db_size=$(du -sh "${DATA_DIR}/one-api.db" 2>/dev/null | awk '{print $1}')
      echo -e "  $(t app.newapi.status.database):    one-api.db (${db_size})"
    fi
  else
    echo -e "  ${RED}[✗]${NC} $(t app.newapi.status.data_missing "$DATA_DIR")"
  fi
  echo -e "  $(t app.newapi.status.log_dir):  ${LOG_DIR}"
  echo -e "\n${BOLD}[$(t app.newapi.status.backup_info)]${NC}"
  if [[ -d "$BACKUP_DIR" ]]; then
    local bak_count bak_total_size
    bak_count=$(find "$BACKUP_DIR" -maxdepth 1 -name "new-api_*.tar.gz" 2>/dev/null | wc -l)
    bak_total_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | awk '{print $1}')
    echo -e "  $(t app.newapi.status.backup_dir):  ${BACKUP_DIR} (${bak_total_size}, $(t app.newapi.status.backup_count "$bak_count"))"
    local _cnt=0
    while IFS= read -r f; do
      local _sz; _sz=$(du -sh "$f" 2>/dev/null | cut -f1 || echo "?")
      echo -e "  $((_cnt+1)). $(basename "$f") (${_sz})"
      _cnt=$(( _cnt + 1 ))
    done < <(find "$BACKUP_DIR" -maxdepth 1 -name "new-api_*.tar.gz" \
             -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -3 | awk '{print $2}')
    [[ $_cnt -eq 0 ]] && echo -e "  ${YELLOW}[!]${NC} $(t app.newapi.warn.no_backups)"
  else
    echo -e "  ${YELLOW}[!]${NC} $(t app.newapi.status.backup_missing "$BACKUP_DIR")"
  fi
  echo -e "\n${BOLD}[$(t app.newapi.status.disk)]${NC}"
  local disk_fmt
  disk_fmt="$(t app.newapi.status.disk_usage)"
  df -h "$INSTALL_DIR" 2>/dev/null \
    | awk -v fmt="$disk_fmt" 'NR==2{printf "  " fmt "\n", $6,$3,$2,$5}' || true
  echo -e "\n${BOLD}[$(t app.newapi.status.health "$PORT")]${NC}"
  local HTTP_CODE
  HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}" --max-time 5 \
    "http://127.0.0.1:${PORT}/" 2>/dev/null || echo "000")
  if [[ "$HTTP_CODE" =~ ^(200|301|302)$ ]]; then
    echo -e "  ${GREEN}[✓]${NC} $(t app.newapi.status.local_ok "$HTTP_CODE")"
  else
    echo -e "  ${YELLOW}[!]${NC} $(t app.newapi.status.local_warn "$HTTP_CODE")"
  fi
  echo -e "\n${BOLD}[$(t app.newapi.status.firewall "$PORT")]${NC}"
  if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
    local ufw_rule
    ufw_rule=$(ufw status 2>/dev/null | grep "${PORT}" || true)
    if [[ -n "$ufw_rule" ]]; then
      echo -e "  ${GREEN}[✓]${NC} $(t app.newapi.status.ufw_allowed "$PORT")"
      echo "$ufw_rule" | sed 's/^/  /'
    else
      echo -e "  ${YELLOW}[!]${NC} $(t app.newapi.status.ufw_missing "$PORT")"
    fi
  elif command -v iptables &>/dev/null; then
    if iptables -C INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null; then
      echo -e "  ${GREEN}[✓]${NC} $(t app.newapi.status.iptables_allowed "$PORT")"
    else
      echo -e "  ${YELLOW}[!]${NC} $(t app.newapi.status.iptables_missing "$PORT")"
    fi
  else
    echo -e "  ${YELLOW}[!]${NC} $(t app.newapi.status.no_firewall)"
  fi
  echo ""
}
do_uninstall() {
  show_banner
  preflight_check "uninstall"
  load_config
  acquire_lock
  [[ -z "${INSTALL_DIR:-}" ]] && error "$(t app.newapi.error.install_dir_empty "$CONF_FILE")"
  [[ -z "${DATA_DIR:-}"    ]] && error "$(t app.newapi.error.data_dir_empty)"
  [[ -z "${BACKUP_DIR:-}"  ]] && error "$(t app.newapi.error.backup_dir_empty)"
  [[ "${INSTALL_DIR}" == "/" ]] && error "$(t app.newapi.error.install_dir_root)"
  [[ "${DATA_DIR}"    == "/" ]] && error "$(t app.newapi.error.data_dir_root)"
  [[ "${BACKUP_DIR}"  == "/" ]] && error "$(t app.newapi.error.backup_dir_root)"
  step "$(t app.newapi.step.uninstall)"
  echo -e "${RED}${BOLD}"
  echo "  $(t app.newapi.uninstall.removes)"
  echo "     - $(t app.newapi.uninstall.binary "$INSTALL_DIR")"
  echo "     - $(t app.newapi.uninstall.systemd "$SERVICE_NAME")"
  echo "     - $(t app.newapi.uninstall.logrotate)"
  echo "     - $(t app.newapi.uninstall.cron)"
  echo "     - $(t app.newapi.uninstall.backup_script)"
  echo "     - $(t app.newapi.uninstall.deploy_config "$CONF_FILE")"
  echo ""
  echo "  $(t app.newapi.uninstall.keep_data "$DATA_DIR")"
  echo "  $(t app.newapi.uninstall.keep_backup "$BACKUP_DIR")"
  echo -e "${NC}"
  prompt "$(t app.newapi.prompt.continue)"
  local _c; read -r _c
  [[ "$_c" != "YES" ]] && { info "$(t app.newapi.info.cancelled)"; exit 0; }
  prompt "$(t app.newapi.prompt.delete_data "$DATA_DIR")"
  local _del_data; read -r _del_data
  local DELETE_DATA=false
  [[ "${_del_data,,}" == "y" ]] && DELETE_DATA=true
  prompt "$(t app.newapi.prompt.delete_backup "$BACKUP_DIR")"
  local _del_bak; read -r _del_bak
  local DELETE_BACKUP=false
  [[ "${_del_bak,,}" == "y" ]] && DELETE_BACKUP=true
  info "$(t app.newapi.info.stop_disable "$SERVICE_NAME")"
  systemctl stop    "$SERVICE_NAME" 2>/dev/null || true
  systemctl disable "$SERVICE_NAME" 2>/dev/null || true
  rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
  systemctl daemon-reload
  success "$(t app.newapi.success.removed_systemd)"
  rm -f "$BIN_PATH"
  find "$INSTALL_DIR" -maxdepth 1 -name "new-api.bak.*" -type f -delete 2>/dev/null || true
  find "$INSTALL_DIR" -maxdepth 1 -name "new-api.tmp.*" -type f -delete 2>/dev/null || true
  success "$(t app.newapi.success.removed_binary)"
  rm -f /etc/cron.d/new-api-backup \
        /usr/local/bin/new-api-backup \
        /etc/logrotate.d/new-api
  success "$(t app.newapi.success.removed_scheduled)"
  rm -f "$CONF_FILE"
  success "$(t app.newapi.success.removed_config)"
  if [[ -n "${LOG_DIR:-}" && "$LOG_DIR" != "." && "$LOG_DIR" != "/" && -d "$LOG_DIR" ]]; then
    safe_rm_dir "$LOG_DIR" "LOG_DIR"
    success "$(t app.newapi.success.deleted_log "$LOG_DIR")"
  else
    warn "$(t app.newapi.warn.log_path "${LOG_DIR:-unset}")"
  fi
  if $DELETE_DATA; then
    safe_rm_dir "$DATA_DIR" "DATA_DIR"
    success "$(t app.newapi.success.deleted_data "$DATA_DIR")"
    if [[ -d "$INSTALL_DIR" ]] && [[ -z "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]]; then
      safe_rm_dir "$INSTALL_DIR" "INSTALL_DIR"
      success "$(t app.newapi.success.cleaned_install "$INSTALL_DIR")"
    fi
  else
    info "$(t app.newapi.info.kept_data "$DATA_DIR")"
  fi
  if $DELETE_BACKUP; then
    safe_rm_dir "$BACKUP_DIR" "BACKUP_DIR"
    success "$(t app.newapi.success.deleted_backup "$BACKUP_DIR")"
  else
    info "$(t app.newapi.info.kept_backup "$BACKUP_DIR")"
  fi
  if $DELETE_DATA && id "$SERVICE_USER" &>/dev/null; then
    userdel "$SERVICE_USER" 2>/dev/null \
      && success "$(t app.newapi.success.deleted_user "$SERVICE_USER")" \
      || warn "$(t app.newapi.warn.delete_user "$SERVICE_USER")"
  fi
  echo ""
  echo -e "${BOLD}${GREEN}  $(t app.newapi.success.uninstalled)${NC}"
  if ! $DELETE_DATA; then
    echo -e "  ${YELLOW}[hint]${NC} $(t app.newapi.hint.data_kept "$DATA_DIR")"
    echo -e "  ${YELLOW}[hint]${NC} $(t app.newapi.hint.remove_data "$DATA_DIR")"
  fi
  if ! $DELETE_BACKUP; then
    echo -e "  ${YELLOW}[hint]${NC} $(t app.newapi.hint.backup_kept "$BACKUP_DIR")"
  fi
  echo ""
}
