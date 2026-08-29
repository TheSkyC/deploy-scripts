#!/bin/bash
set -euo pipefail
umask 077
DOMAIN="${DOMAIN:-api.example.com}"
PORT="${PORT:-8080}"
INSTALL_DIR="${INSTALL_DIR:-/opt/new-api}"
DATA_DIR="${DATA_DIR:-/opt/new-api/data}"
LOG_DIR="${LOG_DIR:-/opt/new-api/logs}"
SERVICE_NAME="${SERVICE_NAME:-new-api}"
SERVICE_USER="${SERVICE_USER:-newapi}"
GITHUB_REPO="${GITHUB_REPO:-QuantumNous/new-api}"
BACKUP_DIR="${BACKUP_DIR:-/opt/new-api-backups}"
BACKUP_KEEP_DAYS="${BACKUP_KEEP_DAYS:-30}"
BACKUP_CRON="${BACKUP_CRON:-30 3 * * *}"
TZ="${TZ:-Asia/Shanghai}"
BIN_PATH="${INSTALL_DIR}/new-api"
LOG_FILE="${LOG_DIR}/new-api.log"
ENV_FILE="/etc/${SERVICE_NAME}.env"
CONFIG_KEYS=(
  DOMAIN PORT INSTALL_DIR DATA_DIR LOG_DIR SERVICE_NAME SERVICE_USER
  GITHUB_REPO BACKUP_DIR BACKUP_KEEP_DAYS BACKUP_CRON TZ INSTALLED_VERSION
)
_NEWAPI_DERIVE_PATHS() {
  BIN_PATH="${INSTALL_DIR}/new-api"
  LOG_FILE="${LOG_DIR}/new-api.log"
  ENV_FILE="/etc/${SERVICE_NAME}.env"
}
APP_CONFIG_DERIVE_HOOK=_NEWAPI_DERIVE_PATHS
# Central check-update adapter: New API is a GitHub-release binary whose
# recorded version lives in INSTALLED_VERSION, so the shared release checker
# applies with the configured repository. Saved configuration is reloaded so
# custom install repositories are honored without running an app action.
_newapi_check_update_json() {
  app_check_update_json "newapi" "$1" "${2:-0}" "${3:-0}"
}
APP_CHECK_UPDATE_FN=_newapi_check_update_json
_newapi_status_version_json() {
  version_check_cached_binary_release_json "newapi" "${INSTALLED_VERSION:-}"
}
APP_STATUS_VERSION_FN=_newapi_status_version_json
_newapi_status_backup() {
  app_status_backup_json "BACKUP_DIR" "${BACKUP_DIR:-}" \
    "backup directory is unsafe or missing" 'new-api_*.tar.gz'
}

APP_STATUS_BACKUP_FN=_newapi_status_backup
_newapi_remove_dir_or_error() {
  app_remove_dir_or_error "$1" "$2" "$3" "app.newapi.error.remove_dir"
}
_newapi_remove_file_or_error() {
  app_remove_file_or_error "$1" "$2" "app.newapi.error.remove_file"
}
_newapi_require_safe_bin_path() {
  require_safe_path "BIN_PATH" "$BIN_PATH"
}
app_conf_register_legacy "/etc/new-api-deploy.conf"
CONF_FILE="$(app_conf_file)"
LOCK_FILE="$(app_lock_file)"
preflight_check() {
  [[ "${1:-}" != "status" && $EUID -ne 0 ]] && error "$(t error.root_required "$0" "${1:-}")"
  command -v apt-get &>/dev/null \
    || error "$(t app.newapi.error.apt_only)"
  ARCH=$(uname -m)
  case $ARCH in
    x86_64)  BIN_ARCH="amd64" ;;
    aarch64) BIN_ARCH="arm64" ;;
    *) error "$(t app.newapi.error.arch "$ARCH")" ;;
  esac
  _validate_config_values
}
_validate_config_values() {
  app_validate_port "$PORT" "PORT"
  app_validate_domain "DOMAIN" "$DOMAIN"
  app_validate_systemd_name "SERVICE_NAME" "$SERVICE_NAME"
  app_validate_system_name "SERVICE_USER" "$SERVICE_USER"
  app_validate_github_repo "GITHUB_REPO" "$GITHUB_REPO"
  require_safe_path "INSTALL_DIR" "$INSTALL_DIR"
  _newapi_require_safe_bin_path
  require_safe_path "DATA_DIR" "$DATA_DIR"
  require_safe_path "LOG_DIR" "$LOG_DIR"
  require_safe_path "LOG_FILE" "$LOG_FILE"
  require_safe_path "ENV_FILE" "$ENV_FILE"
  require_safe_path "BACKUP_DIR" "$BACKUP_DIR"
  # BACKUP_CRON is a crontab(5) schedule; reject newlines, quotes, or shell
  # metacharacters so the generated /etc/cron.d line stays well-formed.
  if [[ -z "$BACKUP_CRON" || "$BACKUP_CRON" == *$'\n'* || "$BACKUP_CRON" == *$'\r'* ]] \
      || [[ "$BACKUP_CRON" == *'&'* || "$BACKUP_CRON" == *'|'* || "$BACKUP_CRON" == *';'* \
      || "$BACKUP_CRON" == *'$'* || "$BACKUP_CRON" == *'`'* || "$BACKUP_CRON" == *'"'* \
      || "$BACKUP_CRON" == *"'"* ]]; then
    error "$(t app.newapi.error.cron_invalid "$BACKUP_CRON")"
  fi
  # TZ must be a bare IANA timezone name like Asia/Shanghai or UTC; reject
  # spaces, newlines, or shell metacharacters.
  if [[ -z "$TZ" || "$TZ" == *[[:space:]]* || "$TZ" == *$'\n'* || "$TZ" == *$'\r'* ]] \
      || [[ "$TZ" == *'&'* || "$TZ" == *'|'* || "$TZ" == *';'* || "$TZ" == *'$'* \
      || "$TZ" == *'`'* || "$TZ" == *'"'* || "$TZ" == *"'"* || "$TZ" == *'..'* \
      || "$TZ" == /* ]]; then
    error "$(t app.newapi.error.tz_invalid "$TZ")"
  fi
}
check_connectivity() {
  app_check_connectivity app.newapi.error.github_unreachable \
    "https://api.github.com" \
    "https://github.com" \
    "https://objects.githubusercontent.com"
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
  if [[ ! -s "$bin" ]]; then
    rm -f "$bin"
    error "$(t app.newapi.error.binary_empty)"
  fi
  local size
  size=$(wc -c < "$bin")
  if [[ $size -lt 1048576 ]]; then
    rm -f "$bin"
    error "$(t app.newapi.error.binary_too_small "$size")"
  fi
  local magic
  magic=$(dd if="$bin" bs=1 count=4 2>/dev/null | od -An -tx1 | tr -d ' \n' 2>/dev/null || true)
  if [[ "$magic" != "7f454c46" ]]; then
    rm -f "$bin"
    error "$(t app.newapi.error.binary_not_elf "${magic:-read failed}")"
  fi
  local size_mb=$(( size / 1024 / 1024 ))
  success "$(t app.newapi.success.binary_verified "$size_mb")"
}
_restore_moved_binary_backup() {
  app_binary_restore_moved_backup "$1"
}
_install_binary_candidate() {
  app_binary_install_candidate "$@"
}
_restore_binary_backup() {
  app_binary_restore_backup "$1"
}
_backup_current_binary() {
  local backup_path="$1"
  if ! app_binary_backup_current "$backup_path"; then
    error "$(t app.newapi.error.binary_install "$BIN_PATH")"
  fi
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
    return 0
  else
    warn "$(t app.newapi.warn.http_health "$HTTP_CODE")"
    warn "$(t app.newapi.warn.debug_command "$SERVICE_NAME")"
    return 1
  fi
}
_write_env_file() {
  local session_secret="$1"
  if ! atomic_write_file "$ENV_FILE" 600 root:root << EOF
# Managed by deploy-scripts.
PORT=${PORT}
SESSION_SECRET=${session_secret}
TZ=${TZ}
SQLITE_BUSY_TIMEOUT=3000
GODEBUG=netdns=go
EOF
  then
    error "$(t app.newapi.error.env_file "$ENV_FILE")"
  fi
  success "$(t app.newapi.success.env_file "$ENV_FILE")"
}
_write_systemd_unit() {
  local unit_path="/etc/systemd/system/${SERVICE_NAME}.service"
  if ! systemd_write_unit "$unit_path" << EOF
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

# Runtime environment.
EnvironmentFile=${ENV_FILE}

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
  then
    error "$(t app.newapi.error.systemd_unit "$SERVICE_NAME")"
  fi
}
_write_backup_script() {
  if ! mkdir -p "$BACKUP_DIR"; then
    error "$(t app.newapi.error.backup_dir_create "$BACKUP_DIR")"
  fi
  local backup_dir_literal data_dir_literal service_name_literal keep_days_literal
  printf -v backup_dir_literal '%q' "$BACKUP_DIR"
  printf -v data_dir_literal '%q' "$DATA_DIR"
  printf -v service_name_literal '%q' "$SERVICE_NAME"
  printf -v keep_days_literal '%q' "$BACKUP_KEEP_DAYS"
  local msg_start msg_backup_dir_failed msg_data_missing msg_wal_ok msg_wal_warn msg_integrity_warn msg_backup_ok msg_tar_failed msg_removed_old msg_remove_failed msg_done
  msg_start="$(t app.newapi.backup.log.start)"
  msg_backup_dir_failed="$(t app.newapi.backup.log.dir_failed '%s')"
  msg_data_missing="$(t app.newapi.backup.log.data_missing '%s')"
  msg_wal_ok="$(t app.newapi.backup.log.wal_ok)"
  msg_wal_warn="$(t app.newapi.backup.log.wal_warn)"
  msg_integrity_warn="$(t app.newapi.backup.log.integrity_warn '%s')"
  msg_backup_ok="$(t app.newapi.backup.log.ok '%s' '%s')"
  msg_tar_failed="$(t app.newapi.backup.log.tar_failed)"
  msg_removed_old="$(t app.newapi.backup.log.removed_old '%s' '%s')"
  msg_remove_failed="$(t app.newapi.backup.log.remove_failed '%s')"
  msg_done="$(t app.newapi.backup.log.done)"
  local backup_script="/usr/local/bin/new-api-backup"
  local backup_tmp
  if ! backup_tmp=$(mktemp "${backup_script}.XXXXXX"); then
    error "$(t app.newapi.error.backup_script)"
  fi
  if ! cat > "$backup_tmp" << BKSH_HEADER
#!/bin/bash
# Auto-generated New API backup script. Do not edit this file manually.
# Regenerate it with: sudo bash install_newapi.sh install
set -euo pipefail
umask 077

BACKUP_DIR=${backup_dir_literal}
DATA_DIR=${data_dir_literal}
SERVICE_NAME=${service_name_literal}
KEEP_DAYS=${keep_days_literal}
[[ "\$KEEP_DAYS" =~ ^[0-9]+$ ]] || KEEP_DAYS=0
MSG_START="${msg_start}"
MSG_BACKUP_DIR_FAILED="${msg_backup_dir_failed}"
MSG_DATA_MISSING="${msg_data_missing}"
MSG_WAL_OK="${msg_wal_ok}"
MSG_WAL_WARN="${msg_wal_warn}"
MSG_INTEGRITY_WARN="${msg_integrity_warn}"
MSG_BACKUP_OK="${msg_backup_ok}"
MSG_TAR_FAILED="${msg_tar_failed}"
MSG_REMOVED_OLD="${msg_removed_old}"
MSG_REMOVE_FAILED="${msg_remove_failed}"
MSG_DONE="${msg_done}"
BKSH_HEADER
  then
    rm -f "$backup_tmp"
    error "$(t app.newapi.error.backup_script)"
  fi
  if ! cat >> "$backup_tmp" << 'BKSH_BODY'

LOG="${BACKUP_DIR}/backup.log"
TS=$(date +%Y%m%d_%H%M%S)
ARCHIVE="${BACKUP_DIR}/new-api_${TS}.tar.gz"
ARCHIVE_TMP="${ARCHIVE}.tmp"

_log() { echo "$(date '+%F %T')  $*" >> "$LOG"; }
if ! mkdir -p "${BACKUP_DIR}"; then
  printf '%s  %s\n' "$(date '+%F %T')" "$(printf "$MSG_BACKUP_DIR_FAILED" "$BACKUP_DIR")" >&2
  exit 1
fi
_log "── ${MSG_START} ────────────────────────────────────"

# Refuse to create an empty backup when the data directory is missing.
if [[ ! -d "${DATA_DIR}" ]]; then
  _log "$(printf "$MSG_DATA_MISSING" "$DATA_DIR")"
  exit 1
fi

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
    # Integrity sidecar: bare digest is enough here; verify accepts it.
    if command -v sha256sum >/dev/null 2>&1; then
      sha256sum "${ARCHIVE}" | awk '{print $1"  "$(NF)}' > "${ARCHIVE}.sha256" || true
      chmod 600 "${ARCHIVE}.sha256" 2>/dev/null || true
    elif command -v shasum >/dev/null 2>&1; then
      shasum -a 256 "${ARCHIVE}" | awk '{print $1"  "$(NF)}' > "${ARCHIVE}.sha256" || true
      chmod 600 "${ARCHIVE}.sha256" 2>/dev/null || true
    fi
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
    if rm -f "$f"; then
      REMOVED=$(( REMOVED + 1 ))
    else
      _log "$(printf "$MSG_REMOVE_FAILED" "$f")"
    fi
  done < <(find "${BACKUP_DIR}" -maxdepth 1 -name "new-api_*.tar.gz" -mtime "+${KEEP_DAYS}" 2>/dev/null)
  if [[ $REMOVED -gt 0 ]]; then
    _log "$(printf "$MSG_REMOVED_OLD" "$REMOVED" "$KEEP_DAYS")"
  fi
fi

_log "── ${MSG_DONE} ────────────────────────────────────"
BKSH_BODY
  then
    rm -f "$backup_tmp"
    error "$(t app.newapi.error.backup_script)"
  fi
  if ! chmod 750 "$backup_tmp" \
      || ! chown root:root "$backup_tmp" \
      || ! mv "$backup_tmp" "$backup_script"; then
    rm -f "$backup_tmp"
    error "$(t app.newapi.error.backup_script)"
  fi
  success "$(t app.newapi.success.backup_script)"
}
_backup_silent() {
  local label="${1:-manual}"
  local backup_log="${BACKUP_DIR}/backup.log"
  _log_backup_helper() {
    [[ -d "$BACKUP_DIR" ]] || return 1
    printf '%s  %s\n' "$(date '+%F %T')" "$1" >> "$backup_log"
  }
  if ! mkdir -p "$BACKUP_DIR"; then
    warn "$(t app.newapi.warn.silent_backup_dir_failed "$BACKUP_DIR")"
    return 1
  fi
  if [[ ! -d "$DATA_DIR" ]]; then
    _log_backup_helper "$(t app.newapi.backup.log.data_missing "$DATA_DIR")"
    warn "$(t app.newapi.warn.silent_data_missing "$DATA_DIR")"
    return 1
  fi
  local archive
  archive="${BACKUP_DIR}/new-api_${label}_$(date +%Y%m%d_%H%M%S).tar.gz"
  local archive_tmp="${archive}.tmp"
  local DB_FILE="${DATA_DIR}/one-api.db"
  if command -v sqlite3 &>/dev/null && [[ -f "$DB_FILE" ]]; then
    sqlite3 "$DB_FILE" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    local _ic
    _ic=$(sqlite3 "$DB_FILE" "PRAGMA integrity_check;" 2>/dev/null || echo "error")
    if [[ "$_ic" != "ok" ]]; then
      _log_backup_helper "$(t app.newapi.backup.log.integrity_warn "$_ic")"
      warn "$(t app.newapi.warn.sqlite_integrity "$_ic")"
    fi
  fi
  if tar -czf "$archive_tmp" \
      --exclude="*.log" --exclude="*.log.*" \
      -C "$(dirname "$DATA_DIR")" "$(basename "$DATA_DIR")" >&2; then
    if mv "$archive_tmp" "$archive"; then
      local sz; sz=$(du -sh "$archive" 2>/dev/null | awk '{print $1}')
      success "$(t app.newapi.success.silent_backup "$archive" "$sz")"
    else
      rm -f "$archive_tmp"
      _log_backup_helper "$(t app.newapi.backup.log.tar_failed)"
      warn "$(t app.newapi.warn.silent_backup_failed)"
      return 1
    fi
  else
    rm -f "$archive_tmp"
    _log_backup_helper "$(t app.newapi.backup.log.tar_failed)"
    warn "$(t app.newapi.warn.silent_backup_failed)"
    return 1
  fi
}
_print_install_summary() {
  local version="$1"
  local summary_state="${2:-ready}"
  local INTERNAL_IP
  local summary_title
  INTERNAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
  INTERNAL_IP="${INTERNAL_IP:-YOUR_SERVER_IP}"
  if [[ "$summary_state" == "pending" ]]; then
    summary_title="$(t app.newapi.summary.title_pending)"
  else
    summary_title="$(t app.newapi.summary.title_ready)"
  fi
  echo ""
  echo -e "${BOLD}${GREEN}"
  echo "  ╔══════════════════════════════════════════════════════╗"
  echo "  ║           ${summary_title}                     ║"
  echo "  ╠══════════════════════════════════════════════════════╣"
  echo -e "  ║  $(t app.newapi.summary.public)  ${CYAN}https://${DOMAIN}${GREEN}"
  echo -e "  ║  $(t app.newapi.summary.internal)  ${CYAN}http://${INTERNAL_IP}:${PORT}${GREEN}"
  echo "  ╠══════════════════════════════════════════════════════╣"
  echo -e "  ║  ${RED}${BOLD}$(t app.newapi.summary.credential_warning)${GREEN}"
  echo -e "  ║  $(t app.newapi.summary.credential_hint)"
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
  LATEST=$(github_latest_release_tag "$GITHUB_REPO" "app.newapi.warn.github_api")
  [[ -z "$LATEST" ]] && error "$(t app.newapi.error.version_failed)"
  success "$(t app.newapi.success.latest "${BOLD}${LATEST}${NC}")"
  local DOWNLOAD_URL
  DOWNLOAD_URL=$(get_download_url "$LATEST")
  step "$(t app.newapi.step.deps)"
  if ! apt-get update -qq; then
    error "$(t app.newapi.error.apt_update)"
  fi
  if ! apt-get install -y -qq curl ca-certificates sqlite3; then
    error "$(t app.newapi.error.deps_install)"
  fi
  success "$(t app.newapi.success.deps)"
  step "$(t app.newapi.step.user_dirs)"
  if ! id "$SERVICE_USER" &>/dev/null; then
    if ! useradd -r -s /usr/sbin/nologin -d "$INSTALL_DIR" "$SERVICE_USER"; then
      error "$(t app.newapi.error.user_create "$SERVICE_USER")"
    fi
    success "$(t app.newapi.success.user_created "$SERVICE_USER")"
  else
    info "$(t app.newapi.info.user_exists "$SERVICE_USER")"
  fi
  require_safe_path "INSTALL_DIR" "$INSTALL_DIR"
  require_safe_path "DATA_DIR" "$DATA_DIR"
  require_safe_path "LOG_DIR" "$LOG_DIR"
  require_safe_path "BACKUP_DIR" "$BACKUP_DIR"
  if ! mkdir -p "$INSTALL_DIR" "$DATA_DIR" "$LOG_DIR" "$BACKUP_DIR"; then
    error "$(t app.newapi.error.dir_create "$INSTALL_DIR" "$BACKUP_DIR")"
  fi
  if ! chown -R "${SERVICE_USER}:${SERVICE_USER}" "$INSTALL_DIR" "$LOG_DIR" "$BACKUP_DIR"; then
    error "$(t app.newapi.error.dir_owner "${SERVICE_USER}:${SERVICE_USER}" "$INSTALL_DIR")"
  fi
  success "$(t app.newapi.success.dirs "$INSTALL_DIR" "$DATA_DIR" "$LOG_DIR")"
  step "$(t app.newapi.step.download "$BIN_ARCH")"
  info "$(t app.newapi.info.download_url "$DOWNLOAD_URL")"
  local TMP_BIN
  if ! TMP_BIN=$(mktemp "${INSTALL_DIR}/new-api.tmp.XXXXXX"); then
    error "$(t app.newapi.error.download "$GITHUB_REPO")"
  fi
  if ! curl -fL --progress-bar -o "$TMP_BIN" "$DOWNLOAD_URL"; then
    if ! rm -f "$TMP_BIN"; then
      warn "$(t app.newapi.warn.tmp_binary_cleanup_failed "$TMP_BIN")"
    fi
    error "$(t app.newapi.error.download "$GITHUB_REPO")"
  fi
  verify_binary "$TMP_BIN"
  local OLD_BIN_BAK=""
  if [[ -f "$BIN_PATH" ]]; then
    local OLD_TS; OLD_TS=$(date +%Y%m%d_%H%M%S)
    OLD_BIN_BAK="${INSTALL_DIR}/new-api.bak.${OLD_TS}"
  fi
  if ! _install_binary_candidate "$TMP_BIN" "$OLD_BIN_BAK"; then
    error "$(t app.newapi.error.binary_install "$BIN_PATH")"
  fi
  if [[ -n "$OLD_BIN_BAK" ]]; then
    warn "$(t app.newapi.warn.old_binary_backup "$(basename "$OLD_BIN_BAK")")"
  fi
  if ! chown -R "${SERVICE_USER}:${SERVICE_USER}" "$INSTALL_DIR"; then
    error "$(t app.newapi.error.dir_owner "${SERVICE_USER}:${SERVICE_USER}" "$INSTALL_DIR")"
  fi
  success "$(t app.newapi.success.binary_installed "$BIN_PATH")"
  step "$(t app.newapi.step.secret)"
  local SESSION_SECRET
  SESSION_SECRET=$(tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 48; true)
  [[ -n "$SESSION_SECRET" ]] || error "$(t app.newapi.error.secret)"
  success "$(t app.newapi.success.secret)"
  _write_env_file "$SESSION_SECRET"
  step "$(t app.newapi.step.systemd)"
  _write_systemd_unit
  success "$(t app.newapi.success.systemd "$SERVICE_NAME")"
  step "$(t app.newapi.step.firewall)"
  app_configure_firewall "$PORT" "app.newapi" "New API"
  step "$(t app.newapi.step.logrotate)"
  app_write_logrotate "/etc/logrotate.d/new-api" "$LOG_DIR" "app.newapi.error.logrotate" "app.newapi.success.logrotate"
  step "$(t app.newapi.step.cron)"
  _write_backup_script
  local cron_file="/etc/cron.d/new-api-backup"
  local cron_tmp
  if ! cron_tmp=$(mktemp "${cron_file}.XXXXXX"); then
    error "$(t app.newapi.error.cron)"
  fi
  if ! printf '%s\n' "${BACKUP_CRON} root /bin/bash /usr/local/bin/new-api-backup" > "$cron_tmp" \
      || ! chmod 644 "$cron_tmp" \
      || ! chown root:root "$cron_tmp" \
      || ! mv "$cron_tmp" "$cron_file"; then
    rm -f "$cron_tmp"
    error "$(t app.newapi.error.cron)"
  fi
  success "$(t app.newapi.success.cron "$BACKUP_KEEP_DAYS")"
  step "$(t app.newapi.step.start)"
  local _install_summary_state="ready"
  app_check_port_conflict "$PORT"
  if ! systemctl daemon-reload; then
    error "$(t app.newapi.error.systemd_reload "$SERVICE_NAME")"
  fi
  if ! systemctl enable "$SERVICE_NAME" --quiet; then
    warn "$(t app.newapi.warn.service_enable_failed "$SERVICE_NAME" "$SERVICE_NAME")"
  fi
  if systemctl restart "$SERVICE_NAME" && wait_for_service "$SERVICE_NAME" 20; then
    success "$(t app.newapi.success.service_started)"
    systemctl status "$SERVICE_NAME" --no-pager -l 2>/dev/null | head -12 | sed 's/^/  /' >&2 || true
  else
    warn "$(t app.newapi.warn.start_rollback)"
    if ! systemctl stop "$SERVICE_NAME" 2>/dev/null; then
      warn "$(t app.newapi.warn.cleanup_stop_failed "$SERVICE_NAME" "$SERVICE_NAME")"
    fi
    if ! systemctl disable "$SERVICE_NAME" 2>/dev/null; then
      warn "$(t app.newapi.warn.cleanup_disable_failed "$SERVICE_NAME" "$SERVICE_NAME")"
    fi
    _newapi_remove_file_or_error "/etc/systemd/system/${SERVICE_NAME}.service" "NEWAPI_SERVICE_FILE"
    if ! systemctl daemon-reload 2>/dev/null; then
      warn "$(t app.newapi.warn.cleanup_reload_failed)"
    fi
    if [[ -n "${OLD_BIN_BAK:-}" && -f "$OLD_BIN_BAK" ]]; then
      _restore_binary_backup "$OLD_BIN_BAK" \
        || error "$(t app.newapi.error.install_start_failed "$SERVICE_NAME")"
    else
      _newapi_require_safe_bin_path
      _newapi_remove_file_or_error "$BIN_PATH" "BIN_PATH"
    fi
    error "$(t app.newapi.error.install_start_failed "$SERVICE_NAME")"
  fi
  step "$(t app.newapi.step.health)"
  INSTALLED_VERSION="$LATEST"
  app_save_config
  if ! _health_check; then
    _install_summary_state="pending"
  fi
  _print_install_summary "$LATEST" "$_install_summary_state"
}
do_update() {
  show_banner
  preflight_check "update"
  app_load_config _NEWAPI_DERIVE_PATHS
  acquire_lock
  [[ ! -x "$BIN_PATH" ]] \
    && error "$(t app.newapi.error.not_installed "$BIN_PATH")"
  step "$(t app.newapi.step.check_update)"
  check_connectivity
  info "$(t app.newapi.info.query_latest)"
  local LATEST
  LATEST=$(github_latest_release_tag "$GITHUB_REPO" "app.newapi.warn.github_api")
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
  if ! _backup_silent "pre-update"; then
    warn "$(t app.newapi.warn.pre_backup_failed)"
  fi
  step "$(t app.newapi.step.download_update "$CURRENT" "$LATEST")"
  local DOWNLOAD_URL
  DOWNLOAD_URL=$(get_download_url "$LATEST")
  info "$(t app.newapi.info.download_url "$DOWNLOAD_URL")"
  local TMP_BIN
  if ! TMP_BIN=$(mktemp "${INSTALL_DIR}/new-api.tmp.XXXXXX"); then
    error "$(t app.newapi.error.update_download)"
  fi
  if ! curl -fL --progress-bar -o "$TMP_BIN" "$DOWNLOAD_URL"; then
    if ! rm -f "$TMP_BIN"; then
      warn "$(t app.newapi.warn.tmp_binary_cleanup_failed "$TMP_BIN")"
    fi
    error "$(t app.newapi.error.update_download)"
  fi
  verify_binary "$TMP_BIN"
  step "$(t app.newapi.step.replace_restart)"
  local BAK_TS; BAK_TS=$(date +%Y%m%d_%H%M%S)
  local BAK_PATH="${INSTALL_DIR}/new-api.bak.${BAK_TS}"
  _backup_current_binary "$BAK_PATH" \
    || error "$(t app.newapi.error.binary_install "$BIN_PATH")"
  info "$(t app.newapi.info.old_binary "$BAK_PATH")"
  info "$(t app.newapi.info.stop_service)"
  if ! systemctl stop "$SERVICE_NAME" 2>/dev/null; then
    if ! rm -f "$TMP_BIN"; then
      warn "$(t app.newapi.warn.tmp_binary_cleanup_failed "$TMP_BIN")"
    fi
    error "$(t app.newapi.error.stop_service_failed "$SERVICE_NAME" "$SERVICE_NAME")"
  fi
  if ! _install_binary_candidate "$TMP_BIN"; then
    if _restore_binary_backup "$BAK_PATH"; then
      if ! systemctl start "$SERVICE_NAME"; then
        warn "$(t app.newapi.warn.rollback_start_failed "$SERVICE_NAME")"
      fi
    fi
    error "$(t app.newapi.error.binary_install "$BIN_PATH")"
  fi
  if ! systemctl daemon-reload; then
    error "$(t app.newapi.error.systemd_reload "$SERVICE_NAME")"
  fi
  if systemctl start "$SERVICE_NAME" && wait_for_service "$SERVICE_NAME" 20; then
    success "$(t app.newapi.success.updated_started)"
    INSTALLED_VERSION="$LATEST"
    app_save_config
    local -a _old_baks
    local _old_bak_entry
    while IFS= read -r -d '' _old_bak_entry; do
      _old_baks+=("${_old_bak_entry#* }")
    done < <(
      find "$INSTALL_DIR" -maxdepth 1 -name "new-api.bak.*" -type f \
        -printf '%T@ %p\0' 2>/dev/null | sort -z -rn | tail -z -n +4
    )
    if [[ ${#_old_baks[@]} -gt 0 ]]; then
      local _cleaned_old=0
      local _old_bak
      for _old_bak in "${_old_baks[@]}"; do
        if rm -f "$_old_bak"; then
          _cleaned_old=$(( _cleaned_old + 1 ))
        else
          warn "$(t app.newapi.warn.cleanup_old_failed "$_old_bak")"
        fi
      done
      if [[ $_cleaned_old -gt 0 ]]; then
        info "$(t app.newapi.info.cleaned_old "$_cleaned_old")"
      fi
    fi
    if ! _health_check; then
      :
    fi
    echo ""
    echo -e "  ${BOLD}${GREEN}$(t app.newapi.success.update_done "${YELLOW}${CURRENT}${GREEN}" "${YELLOW}${LATEST}${NC}")${NC}"
    echo ""
  else
    warn "$(t app.newapi.warn.update_start_failed "$LATEST" "$CURRENT")"
    if ! systemctl stop "$SERVICE_NAME" 2>/dev/null; then
      error "$(t app.newapi.error.rollback_stop_failed "$SERVICE_NAME" "$BAK_PATH" "$SERVICE_NAME")"
    fi
    if ! _restore_binary_backup "$BAK_PATH"; then
      warn "$(t app.newapi.warn.rollback_start_failed "$SERVICE_NAME")"
      error "$(t app.newapi.error.update_failed "$CURRENT" "$SERVICE_NAME" "$BAK_PATH")"
    fi
    if systemctl start "$SERVICE_NAME"; then
      if wait_for_service "$SERVICE_NAME" 15; then
        success "$(t app.newapi.success.rollback "$CURRENT")"
      else
        warn "$(t app.newapi.warn.rollback_start_failed "$SERVICE_NAME")"
      fi
    else
      warn "$(t app.newapi.warn.rollback_start_failed "$SERVICE_NAME")"
    fi
    error "$(t app.newapi.error.update_failed "$CURRENT" "$SERVICE_NAME" "$BAK_PATH")"
  fi
}
do_backup() {
  show_banner
  preflight_check "backup"
  app_load_config _NEWAPI_DERIVE_PATHS
  acquire_lock
  [[ ! -d "$DATA_DIR" ]] \
    && error "$(t app.newapi.error.data_missing_install "$DATA_DIR")"
  step "$(t app.newapi.step.manual_backup)"
  if ! mkdir -p "$BACKUP_DIR"; then
    error "$(t app.newapi.error.backup_dir_create "$BACKUP_DIR")"
  fi
  local DB_FILE="${DATA_DIR}/one-api.db"
  if command -v sqlite3 &>/dev/null && [[ -f "$DB_FILE" ]]; then
    if sqlite3 "$DB_FILE" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null; then
      success "$(t app.newapi.success.wal)"
    else
      warn "$(t app.newapi.warn.wal)"
    fi
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
      -C "$(dirname "$DATA_DIR")" "$(basename "$DATA_DIR")" >&2; then
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
  local _keep_days="${BACKUP_KEEP_DAYS}"
  [[ "$_keep_days" =~ ^[0-9]+$ ]] || _keep_days=0
  if [[ "$_keep_days" -gt 0 ]]; then
    local _cleaned=0
    while IFS= read -r -d '' f; do
      if rm -f "$f"; then
        _cleaned=$(( _cleaned + 1 ))
      else
        warn "$(t app.newapi.warn.backup_cleanup_failed "$f")"
      fi
    done < <(find "$BACKUP_DIR" -maxdepth 1 -name "new-api_*.tar.gz" \
             -mtime "+${_keep_days}" -type f -print0 2>/dev/null)
    if [[ $_cleaned -gt 0 ]]; then
      info "$(t app.newapi.info.cleaned_backups "$_cleaned" "$_keep_days")"
    fi
  fi
  echo ""
  info "$(t app.newapi.info.backup_list "$BACKUP_DIR")"
  local -a _bak_list
  local _bak_entry
  while IFS= read -r -d '' _bak_entry; do
    _bak_list+=("${_bak_entry#* }")
  done < <(
    find "$BACKUP_DIR" -maxdepth 1 -name "new-api_*.tar.gz" \
      -printf '%T@ %p\0' 2>/dev/null | sort -z -rn | head -z -n 10
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
}
do_status() {
  show_banner
  preflight_check "status"
  app_load_config _NEWAPI_DERIVE_PATHS
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
    local data_size; data_size=$(du -sh "$DATA_DIR" 2>/dev/null | awk '{print $1}' || t app.newapi.status.unknown)
    echo -e "  $(t app.newapi.status.data_dir):  ${DATA_DIR} (${data_size})"
    if [[ -f "${DATA_DIR}/one-api.db" ]]; then
      local db_size; db_size=$(du -sh "${DATA_DIR}/one-api.db" 2>/dev/null | awk '{print $1}' || t app.newapi.status.unknown)
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
    bak_total_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | awk '{print $1}' || t app.newapi.status.unknown)
    echo -e "  $(t app.newapi.status.backup_dir):  ${BACKUP_DIR} (${bak_total_size}, $(t app.newapi.status.backup_count "$bak_count"))"
    local _cnt=0
    local _bak_entry
    while IFS= read -r -d '' _bak_entry; do
      f="${_bak_entry#* }"
      local _sz; _sz=$(du -sh "$f" 2>/dev/null | cut -f1 || echo "?")
      echo -e "  $((_cnt+1)). $(basename "$f") (${_sz})"
      _cnt=$(( _cnt + 1 ))
    done < <(find "$BACKUP_DIR" -maxdepth 1 -name "new-api_*.tar.gz" \
             -printf '%T@ %p\0' 2>/dev/null | sort -z -rn | head -z -n 3)
    if [[ $_cnt -eq 0 ]]; then
      echo -e "  ${YELLOW}[!]${NC} $(t app.newapi.warn.no_backups)"
    fi
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
    ufw_rule=$(ufw status 2>/dev/null | grep -E "(^|[[:space:]])${PORT}/tcp([[:space:]]|$)" || true)
    if [[ -n "$ufw_rule" ]]; then
      echo -e "  ${GREEN}[✓]${NC} $(t app.newapi.status.ufw_allowed "$PORT")"
      ufw_rule="${ufw_rule//$'\n'/$'\n'  }"
      printf '  %s\n' "$ufw_rule"
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
  app_load_config _NEWAPI_DERIVE_PATHS
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
  echo "     - $(t app.newapi.uninstall.env_file "$ENV_FILE")"
  echo "     - $(t app.newapi.uninstall.deploy_config "$CONF_FILE")"
  echo ""
  echo "  $(t app.newapi.uninstall.keep_data "$DATA_DIR")"
  echo "  $(t app.newapi.uninstall.keep_backup "$BACKUP_DIR")"
  echo -e "${NC}"
  local _c
  if deploy_assume_yes; then
    _c="YES"
  else
    prompt "$(t app.newapi.prompt.continue)"
    read -r _c
  fi
  [[ "$_c" != "YES" ]] && { info "$(t app.newapi.info.cancelled)"; exit 0; }
  local DELETE_DATA=false
  if deploy_assume_yes; then
    deploy_env_truthy DEPLOY_DELETE_DATA && DELETE_DATA=true
  else
    prompt "$(t app.newapi.prompt.delete_data "$DATA_DIR")"
    local _del_data; read -r _del_data
    [[ "${_del_data,,}" == "y" ]] && DELETE_DATA=true
  fi
  local DELETE_BACKUP=false
  if deploy_assume_yes; then
    deploy_env_truthy DEPLOY_DELETE_BACKUP && DELETE_BACKUP=true
  else
    prompt "$(t app.newapi.prompt.delete_backup "$BACKUP_DIR")"
    local _del_bak; read -r _del_bak
    [[ "${_del_bak,,}" == "y" ]] && DELETE_BACKUP=true
  fi
  info "$(t app.newapi.info.stop_disable "$SERVICE_NAME")"
  if ! systemctl stop "$SERVICE_NAME" 2>/dev/null; then
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
      error "$(t app.newapi.error.uninstall_stop_failed "$SERVICE_NAME" "$SERVICE_NAME")"
    fi
    warn "$(t app.newapi.warn.uninstall_stop_failed "$SERVICE_NAME" "$SERVICE_NAME")"
  fi
  if ! systemctl disable "$SERVICE_NAME" 2>/dev/null; then
    warn "$(t app.newapi.warn.uninstall_disable_failed "$SERVICE_NAME" "$SERVICE_NAME")"
  fi
  _newapi_remove_file_or_error "/etc/systemd/system/${SERVICE_NAME}.service" "NEWAPI_SERVICE_FILE"
  if ! systemctl daemon-reload; then
    error "$(t app.newapi.error.systemd_reload "$SERVICE_NAME")"
  fi
  success "$(t app.newapi.success.removed_systemd)"
  _newapi_require_safe_bin_path
  _newapi_remove_file_or_error "$BIN_PATH" "BIN_PATH"
  require_safe_path "INSTALL_DIR" "$INSTALL_DIR"
  local _cleanup_path
  while IFS= read -r -d '' _cleanup_path; do
    if ! rm -f "$_cleanup_path"; then
      warn "$(t app.newapi.warn.cleanup_old_failed "$_cleanup_path")"
    fi
  done < <(find "$INSTALL_DIR" -maxdepth 1 \( -name "new-api.bak.*" -o -name "new-api.tmp.*" \) -type f -print0 2>/dev/null)
  success "$(t app.newapi.success.removed_binary)"
  _newapi_remove_file_or_error "/etc/cron.d/new-api-backup" "NEWAPI_CRON_FILE"
  _newapi_remove_file_or_error "/usr/local/bin/new-api-backup" "NEWAPI_BACKUP_SCRIPT"
  _newapi_remove_file_or_error "/etc/logrotate.d/new-api" "NEWAPI_LOGROTATE_FILE"
  success "$(t app.newapi.success.removed_scheduled)"
  _newapi_remove_file_or_error "$ENV_FILE" "ENV_FILE"
  success "$(t app.newapi.success.removed_env_file)"
  _newapi_remove_file_or_error "$CONF_FILE" "CONF_FILE"
  success "$(t app.newapi.success.removed_config)"
  if [[ -n "${LOG_DIR:-}" && "$LOG_DIR" != "." && "$LOG_DIR" != "/" && -d "$LOG_DIR" ]]; then
    _newapi_remove_dir_or_error "$LOG_DIR" "LOG_DIR" "$(t app.newapi.success.deleted_log "$LOG_DIR")"
  else
    warn "$(t app.newapi.warn.log_path "${LOG_DIR:-unset}")"
  fi
  if $DELETE_DATA; then
    _newapi_remove_dir_or_error "$DATA_DIR" "DATA_DIR" "$(t app.newapi.success.deleted_data "$DATA_DIR")"
    if [[ -d "$INSTALL_DIR" ]] && [[ -z "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]]; then
      if ! safe_rm_dir "$INSTALL_DIR" "INSTALL_DIR"; then
        warn "$(t app.newapi.warn.cleanup_install_failed "$INSTALL_DIR")"
      else
        success "$(t app.newapi.success.cleaned_install "$INSTALL_DIR")"
      fi
    fi
  else
    info "$(t app.newapi.info.kept_data "$DATA_DIR")"
  fi
  if $DELETE_BACKUP; then
    _newapi_remove_dir_or_error "$BACKUP_DIR" "BACKUP_DIR" "$(t app.newapi.success.deleted_backup "$BACKUP_DIR")"
  else
    info "$(t app.newapi.info.kept_backup "$BACKUP_DIR")"
  fi
  if $DELETE_DATA && id "$SERVICE_USER" &>/dev/null; then
    if userdel "$SERVICE_USER" 2>/dev/null; then
      success "$(t app.newapi.success.deleted_user "$SERVICE_USER")"
    else
      warn "$(t app.newapi.warn.delete_user "$SERVICE_USER")"
    fi
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

do_verify() {
  show_banner
  require_root "verify"
  app_load_config _NEWAPI_DERIVE_PATHS
  step "$(t backup.verify.step)"
  require_safe_path "BACKUP_DIR" "$BACKUP_DIR"
  app_verify_latest_backup "$BACKUP_DIR" 'new-api_*.tar.gz'
}

do_restore() {
  show_banner
  require_root "restore"
  app_load_config _NEWAPI_DERIVE_PATHS
  acquire_lock
  step "$(t backup.restore.step)"
  require_safe_path "BACKUP_DIR" "$BACKUP_DIR"
  require_safe_path "DATA_DIR" "$DATA_DIR"
  [[ -d "$BACKUP_DIR" ]] || error "$(t backup.restore.no_backups "$BACKUP_DIR")"
  local archive
  archive="${NEWAPI_RESTORE_ARCHIVE:-}"
  if [[ -n "$archive" ]]; then
    [[ "$archive" == "$BACKUP_DIR"/new-api_*.tar.gz && -f "$archive" ]] \
      || error "$(t backup.restore.invalid_archive "$archive")"
  else
    archive="$(backup_latest_archive "$BACKUP_DIR" 'new-api_*.tar.gz' || true)"
    [[ -n "$archive" ]] || error "$(t backup.restore.no_backups "$BACKUP_DIR")"
  fi
  backup_restore_data_dir "$DATA_DIR" "$SERVICE_NAME" "$archive"
}
