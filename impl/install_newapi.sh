#!/usr/bin/env bash
set -euo pipefail
umask 077

# New API (https://github.com/QuantumNous/new-api) ships a bare, versioned
# GitHub-release binary (new-api-<version> on amd64, new-api-arm64-<version>
# on arm64) and configures itself through an env file. The shared binary-app
# library (lib/binary_app.sh) provides the lifecycle; this file configures it
# and adds New API-specific hooks: the env file with the generated
# SESSION_SECRET, the SQLite WAL checkpoint backup hook, the cron-driven
# backup script, and the credential warning in the install summary.
# See PLAN.md section 2 for the verified release asset mapping.

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
BA_BIN_NAME="new-api"
BA_ARCHIVE_TYPE="none"
BA_APT_PACKAGES="sqlite3"
BA_FIREWALL=0
BA_BIND_ADDR="${BA_BIND_ADDR:-127.0.0.1}"
BA_SERVICE_DESCRIPTION="New API - LLM API Aggregation Gateway"
# Keep the historical backup archive prefix so pre-migration archives remain
# discoverable by verify/restore/status.
BA_ARCHIVE_PREFIX="${BA_ARCHIVE_PREFIX:-new-api}"
BA_USE_ENV_FILE=1
BA_SERVICE_ARGS="--port ${PORT} --log-dir ${LOG_DIR}"
BA_HEALTH_URL="http://127.0.0.1:${PORT}/"
BA_HEALTH_CODES="^(200|301|302)$"
CONFIG_KEYS=(
  DOMAIN PORT INSTALL_DIR DATA_DIR LOG_DIR SERVICE_NAME SERVICE_USER
  GITHUB_REPO BACKUP_DIR BACKUP_KEEP_DAYS BACKUP_CRON TZ
  BA_BIND_ADDR BA_VERSION BA_ENABLE_HTTPS CERTBOT_EMAIL INSTALLED_VERSION
)

# The binary asset name embeds the version (without a leading v) and the
# architecture (arm64 asset uses the "arm64" suffix).
ba_asset_name() {
  local version="$1"
  if [[ "$BA_ARCH" == "amd64" ]]; then
    printf 'new-api-%s\n' "${version#v}"
  else
    printf 'new-api-arm64-%s\n' "${version#v}"
  fi
}

# Extra systemd directives for the API-gateway workload.
ba_systemd_extra() {
  printf 'LimitNOFILE=65536\nLimitNPROC=512\n'
}

# Write the managed env file (root-only) with a generated SESSION_SECRET, and
# the cron-driven backup script that the framework lifecycle cannot generate
# on its own.
ba_write_config() {
  local env_file="/etc/${SERVICE_NAME}.env"
  local session_secret=""
  if [[ -f "$env_file" ]]; then
    session_secret="$(grep -E '^SESSION_SECRET=' "$env_file" 2>/dev/null | head -1 | cut -d= -f2- || true)"
  fi
  if [[ -z "$session_secret" ]]; then
    session_secret="$(tr -dc 'A-Za-z0-9' </dev/urandom 2>/dev/null | head -c 48 || true)"
    [[ -n "$session_secret" ]] || error "$(t app.newapi.error.secret)"
  fi
  if ! atomic_write_file "$env_file" 600 root:root <<EOF
# Managed by deploy-scripts.
PORT=${PORT}
SESSION_SECRET=${session_secret}
TZ=${TZ}
SQLITE_BUSY_TIMEOUT=3000
GODEBUG=netdns=go
EOF
  then
    error "$(t app.newapi.error.env_file "$env_file")"
  fi
  success "$(t app.newapi.success.env_file "$env_file")"
  _write_backup_script
}

# Flush the SQLite WAL before the framework archives DATA_DIR.
ba_backup_hook() {
  local db_file="${DATA_DIR}/one-api.db"
  if command -v sqlite3 >/dev/null 2>&1 && [[ -f "$db_file" ]]; then
    sqlite3 "$db_file" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null || true
    local ic
    ic="$(sqlite3 "$db_file" "PRAGMA integrity_check;" 2>/dev/null || echo "error")"
    if [[ "$ic" != "ok" ]]; then
      warn "$(t app.newapi.backup.log.integrity_warn "$ic")"
    fi
  fi
  return 0
}

# Remove the cron entry and backup script during uninstall (the logrotate
# policy is removed by the shared lifecycle).
ba_uninstall_extra() {
  ba_remove_file_or_error "/etc/cron.d/new-api-backup" "NEWAPI_CRON_FILE"
  ba_remove_file_or_error "/usr/local/bin/new-api-backup" "NEWAPI_BACKUP_SCRIPT"
}

# The install summary needs the public/internal URLs and the credential
# warning (New API ships with a publicly known default admin account).
ba_summary_extra() {
  local internal_ip
  internal_ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  internal_ip="${internal_ip:-YOUR_SERVER_IP}"
  echo -e "  $(t app.newapi.summary.public)  ${CYAN}https://${DOMAIN}${GREEN}"
  echo -e "  $(t app.newapi.summary.internal)  ${CYAN}http://${internal_ip}:${PORT}${GREEN}"
  echo -e "  ${RED}${BOLD}$(t app.newapi.summary.credential_warning)${GREEN}"
  echo -e "  $(t app.newapi.summary.credential_hint)"
}

# Write the standalone cron backup script. The framework's manual backup path
# covers on-demand backups; the cron script gives unattended nightly backups
# with the same SQLite WAL quiescing and retention rules.
_write_backup_script() {
  if ! mkdir -p "$BACKUP_DIR"; then
    error "$(t app.newapi.error.backup_dir_create "$BACKUP_DIR")"
  fi
  local backup_dir_literal data_dir_literal keep_days_literal
  printf -v backup_dir_literal '%q' "$BACKUP_DIR"
  printf -v data_dir_literal '%q' "$DATA_DIR"
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
  if ! {
    cat << BKSH_HEADER
#!/bin/bash
# Auto-generated New API backup script. Do not edit this file manually.
# Regenerate it with: sudo bash install_newapi.sh install
set -euo pipefail
umask 077

BACKUP_DIR=${backup_dir_literal}
DATA_DIR=${data_dir_literal}
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
    cat <<'BKSH_BODY'

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
  } | atomic_write_file "$backup_script" 700 root:root; then
    error "$(t app.newapi.error.backup_script)"
  fi
  local cron_file="/etc/cron.d/new-api-backup"
  if ! atomic_write_file "$cron_file" 644 root:root <<CRON
${BACKUP_CRON} root /bin/bash ${backup_script}
CRON
  then
    error "$(t app.newapi.error.cron)"
  fi
  success "$(t app.newapi.success.cron "$BACKUP_KEEP_DAYS")"
}

# Thin lifecycle delegates over the shared binary-app library.
preflight_check() {
  bapp_preflight "$@"
}

_validate_config_values() {
  bapp_validate_cfg
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
