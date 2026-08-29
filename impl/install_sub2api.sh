#!/bin/bash
set -euo pipefail
umask 077
PORT="${PORT:-8082}"
INSTALL_DIR="${INSTALL_DIR:-/opt/sub2api}"
DATA_DIR="${DATA_DIR:-/opt/sub2api/data}"
LOG_DIR="${LOG_DIR:-/opt/sub2api/logs}"
CONFIG_DIR="${CONFIG_DIR:-/etc/sub2api}"
SERVICE_NAME="${SERVICE_NAME:-sub2api}"
SERVICE_USER="${SERVICE_USER:-sub2api}"
GITHUB_REPO="${GITHUB_REPO:-Wei-Shaw/sub2api}"
BACKUP_DIR="${BACKUP_DIR:-/opt/sub2api-backups}"
BACKUP_KEEP_DAYS="${BACKUP_KEEP_DAYS:-30}"
SUB2API_DOMAIN="${SUB2API_DOMAIN:-}"
# Bind the backend to loopback by default: the nginx reverse proxy on
# 80/443 is the public entry point. Set SUB2API_BIND_ADDR=0.0.0.0 only when
# you know you need direct backend access.
SUB2API_BIND_ADDR="${SUB2API_BIND_ADDR:-127.0.0.1}"
# Timezone for the service process; defaults to the server local time.
SUB2API_TZ="${SUB2API_TZ:-}"
PG_USER="${PG_USER:-sub2api}"
PG_PASS="${PG_PASS:-}"
PG_DB="${PG_DB:-sub2api}"
PG_DSN="${PG_DSN:-}"
BIN_PATH="${INSTALL_DIR}/sub2api"
CONFIG_KEYS=(
  PORT INSTALL_DIR DATA_DIR LOG_DIR CONFIG_DIR SERVICE_NAME SERVICE_USER
  GITHUB_REPO BACKUP_DIR BACKUP_KEEP_DAYS PG_USER PG_PASS PG_DB PG_DSN
  SUB2API_DOMAIN SUB2API_BIND_ADDR SUB2API_TZ INSTALLED_VERSION
)
_SUB2API_DERIVE_PATHS() {
  BIN_PATH="${INSTALL_DIR}/sub2api"
}
APP_CONFIG_DERIVE_HOOK=_SUB2API_DERIVE_PATHS
# Central check-update adapter: Sub2API is a GitHub-release binary whose
# recorded version lives in INSTALLED_VERSION, so the shared release checker
# applies with the configured repository. Saved configuration is reloaded so
# custom install repositories are honored without running an app action.
_sub2api_check_update_json() {
  app_check_update_json "sub2api" "$1" "${2:-0}" "${3:-0}"
}
APP_CHECK_UPDATE_FN=_sub2api_check_update_json
_sub2api_status_version_json() {
  version_check_cached_binary_release_json "sub2api" "${INSTALLED_VERSION:-}"
}
APP_STATUS_VERSION_FN=_sub2api_status_version_json
_sub2api_status_backup() {
  app_status_backup_json "BACKUP_DIR" "${BACKUP_DIR:-}" \
    "backup directory is unsafe or missing" 'sub2api_*.tar.gz' 'sub2api_*.sql.gz'
}
APP_STATUS_BACKUP_FN=_sub2api_status_backup
_sub2api_require_safe_bin_path() {
  require_safe_path "BIN_PATH" "$BIN_PATH"
}
_sub2api_remove_dir_or_error() {
  app_remove_dir_or_error "$1" "$2" "$3" "app.sub2api.error.remove_dir"
}
_sub2api_remove_file_or_error() {
  app_remove_file_or_error "$1" "$2" "app.sub2api.error.remove_file"
}
app_conf_register_legacy "/etc/sub2api-deploy.conf"
CONF_FILE="$(app_conf_file)"
LOCK_FILE="$(app_lock_file)"
preflight_check() {
  [[ "${1:-}" != "status" && $EUID -ne 0 ]] && error "$(t error.root_required "$0" "${1:-}")"
  if command -v apt-get &>/dev/null; then
    PKG_MANAGER="apt"
  elif command -v dnf &>/dev/null; then
    PKG_MANAGER="dnf"
  elif command -v yum &>/dev/null; then
    PKG_MANAGER="yum"
  else
    error "$(t app.sub2api.error.package_manager)"
  fi
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)  BIN_ARCH="amd64" ; ELF_MACHINE="3e" ;;
    aarch64) BIN_ARCH="arm64" ; ELF_MACHINE="b7" ;;
    *) error "$(t app.sub2api.error.arch "$ARCH")" ;;
  esac
  _validate_config_values
}

check_connectivity() {
  app_check_connectivity app.sub2api.error.github_unreachable \
    "https://api.github.com" \
    "https://github.com" \
    "https://objects.githubusercontent.com"
}
_APT_CODENAME_OK=false
_apt_codename() {
  local codename=""
  if command -v lsb_release &>/dev/null; then
    codename="$(lsb_release -cs 2>/dev/null || true)"
  fi
  if [[ -z "$codename" && -r /etc/os-release ]]; then
    local VERSION_CODENAME="" UBUNTU_CODENAME=""
    . /etc/os-release
    codename="${VERSION_CODENAME:-${UBUNTU_CODENAME:-}}"
  fi
  [[ -n "$codename" ]] || error "$(t app.sub2api.error.os_codename)"
  printf '%s\n' "$codename"
}
_validate_config_values() {
  app_validate_port "$PORT" "PORT"
  app_validate_domain "SUB2API_DOMAIN" "$SUB2API_DOMAIN"
  app_validate_systemd_name "SERVICE_NAME" "$SERVICE_NAME"
  app_validate_system_name "SERVICE_USER" "$SERVICE_USER"
  app_validate_github_repo "GITHUB_REPO" "$GITHUB_REPO"
  app_validate_db_identifier "PG_USER" "$PG_USER"
  app_validate_db_identifier "PG_DB" "$PG_DB"
  require_safe_path "INSTALL_DIR" "$INSTALL_DIR"
  _sub2api_require_safe_bin_path
  require_safe_path "DATA_DIR" "$DATA_DIR"
  require_safe_path "LOG_DIR" "$LOG_DIR"
  require_safe_path "CONFIG_DIR" "$CONFIG_DIR"
  require_safe_path "BACKUP_DIR" "$BACKUP_DIR"
}

_tag_to_ver() { echo "${1#v}"; }
get_download_url() {
  local tag="$1"
  local ver; ver=$(_tag_to_ver "$tag")
  echo "https://github.com/${GITHUB_REPO}/releases/download/${tag}/sub2api_${ver}_linux_${BIN_ARCH}.tar.gz"
}
get_checksum_url() {
  local tag="$1"
  echo "https://github.com/${GITHUB_REPO}/releases/download/${tag}/checksums.txt"
}
verify_checksum() {
  local archive="$1" tag="$2"
  local ver; ver=$(_tag_to_ver "$tag")
  local expected_name="sub2api_${ver}_linux_${BIN_ARCH}.tar.gz"
  local checksum_url; checksum_url=$(get_checksum_url "$tag")
  local tmp_sum
  if ! tmp_sum=$(mktemp); then
    if ! rm -f "$archive"; then
      warn "$(t app.sub2api.warn.tmp_archive_cleanup_failed "$archive")"
    fi
    error "$(t app.sub2api.error.checksum_temp)"
  fi
  if ! curl -fsSL --max-time 15 -o "$tmp_sum" "$checksum_url" 2>/dev/null; then
    rm -f "$tmp_sum"
    if ! rm -f "$archive"; then
      warn "$(t app.sub2api.warn.tmp_archive_cleanup_failed "$archive")"
    fi
    error "$(t app.sub2api.error.checksum_download)"
  fi
  local expected_hash
  expected_hash=$(grep " ${expected_name}$" "$tmp_sum" 2>/dev/null | awk '{print $1}' || true)
  rm -f "$tmp_sum"
  if [[ -z "$expected_hash" ]]; then
    if ! rm -f "$archive"; then
      warn "$(t app.sub2api.warn.tmp_archive_cleanup_failed "$archive")"
    fi
    error "$(t app.sub2api.error.checksum_missing "$expected_name")"
  fi
  local actual_hash
  if command -v sha256sum &>/dev/null; then
    actual_hash=$(sha256sum "$archive" | awk '{print $1}')
  elif command -v shasum &>/dev/null; then
    actual_hash=$(shasum -a 256 "$archive" | awk '{print $1}')
  else
    if ! rm -f "$archive"; then
      warn "$(t app.sub2api.warn.tmp_archive_cleanup_failed "$archive")"
    fi
    error "$(t app.sub2api.error.sha_tool_missing)"
  fi
  if [[ "$actual_hash" != "$expected_hash" ]]; then
    if ! rm -f "$archive"; then
      warn "$(t app.sub2api.warn.tmp_archive_cleanup_failed "$archive")"
    fi
    error "$(t app.sub2api.error.sha_failed "$expected_hash" "$actual_hash")"
  fi
  success "$(t app.sub2api.success.sha_ok "${actual_hash:0:16}")"
}
extract_and_verify() {
  local archive="$1" dest_dir="$2"
  local tmp_extract
  if ! tmp_extract=$(mktemp -d "${dest_dir}/sub2api-extract.XXXXXX"); then
    if ! rm -f "$archive"; then
      warn "$(t app.sub2api.warn.tmp_archive_cleanup_failed "$archive")"
    fi
    error "$(t app.sub2api.error.tar_extract)"
  fi
  if ! tar -xzf "$archive" -C "$tmp_extract" >&2; then
    if ! rm -f "$archive"; then
      warn "$(t app.sub2api.warn.tmp_archive_cleanup_failed "$archive")"
    fi
    rm -rf "$tmp_extract"
    error "$(t app.sub2api.error.tar_extract)"
  fi
  local bin_path
  bin_path=$(find "$tmp_extract" -maxdepth 2 -name "sub2api" -type f 2>/dev/null | head -1 || true)
  if [[ -z "$bin_path" ]]; then
    if ! rm -f "$archive"; then
      warn "$(t app.sub2api.warn.tmp_archive_cleanup_failed "$archive")"
    fi
    rm -rf "$tmp_extract"
    error "$(t app.sub2api.error.archive_missing_binary)"
  fi
  local magic
  magic=$(dd if="$bin_path" bs=1 count=4 2>/dev/null | od -An -tx1 | tr -d ' \n' 2>/dev/null || true)
  if [[ "$magic" != "7f454c46" ]]; then
    if ! rm -f "$archive"; then
      warn "$(t app.sub2api.warn.tmp_archive_cleanup_failed "$archive")"
    fi
    rm -rf "$tmp_extract"
    error "$(t app.sub2api.error.not_elf "${magic:-read failed}")"
  fi
  local emachine
  emachine=$(dd if="$bin_path" bs=1 skip=18 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n' 2>/dev/null || true)
  if [[ "$emachine" != "$ELF_MACHINE" ]]; then
    if ! rm -f "$archive"; then
      warn "$(t app.sub2api.warn.tmp_archive_cleanup_failed "$archive")"
    fi
    rm -rf "$tmp_extract"
    error "$(t app.sub2api.error.elf_machine "$emachine" "$ELF_MACHINE" "$BIN_ARCH")"
  fi
  local size; size=$(wc -c < "$bin_path")
  local size_mb=$(( size / 1024 / 1024 ))
  success "$(t app.sub2api.success.elf_ok "$BIN_ARCH" "$size_mb")"
  local tmp_bin
  if ! tmp_bin=$(mktemp "${dest_dir}/sub2api.tmp.XXXXXX"); then
    if ! rm -f "$archive"; then
      warn "$(t app.sub2api.warn.tmp_archive_cleanup_failed "$archive")"
    fi
    rm -rf "$tmp_extract"
    error "$(t app.sub2api.error.archive_missing_binary)"
  fi
  if ! mv "$bin_path" "$tmp_bin"; then
    if ! rm -f "$archive"; then
      warn "$(t app.sub2api.warn.tmp_archive_cleanup_failed "$archive")"
    fi
    if ! rm -f "$tmp_bin"; then
      warn "$(t app.sub2api.warn.tmp_binary_cleanup_failed "$tmp_bin")"
    fi
    rm -rf "$tmp_extract"
    error "$(t app.sub2api.error.archive_missing_binary)"
  fi
  rm -rf "$tmp_extract"
  echo "$tmp_bin"
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
    error "$(t app.sub2api.error.binary_install "$BIN_PATH")"
  fi
}
_health_check() {
  local elapsed=0 HTTP_CODE
  until HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}" --max-time 5 \
      "http://127.0.0.1:${PORT}/" 2>/dev/null || echo "000") \
      && [[ "$HTTP_CODE" =~ ^(200|301|302)$ ]]; do
    sleep 1; elapsed=$(( elapsed + 1 ))
    [[ $elapsed -ge 20 ]] && break
  done
  if [[ "$HTTP_CODE" =~ ^(200|301|302)$ ]]; then
    success "$(t app.sub2api.success.http_health "$HTTP_CODE")"
    return 0
  else
    warn "$(t app.sub2api.warn.http_health "$HTTP_CODE")"
    warn "$(t app.sub2api.warn.debug_command "$SERVICE_NAME")"
    warn "$(t app.sub2api.warn.setup_wizard "$PORT")"
    return 1
  fi
}
_install_base_deps() {
  info "$(t app.sub2api.info.install_base_deps)"
  if [[ "$PKG_MANAGER" == "apt" ]]; then
    if ! apt-get update -qq; then
      error "$(t app.sub2api.error.apt_update)"
    fi
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
      curl ca-certificates gnupg lsb-release; then
      error "$(t app.sub2api.error.base_deps_install)"
    fi
  elif [[ "$PKG_MANAGER" == "dnf" ]]; then
    dnf install -y -q curl ca-certificates || error "$(t app.sub2api.error.base_deps_install_pkg)"
  elif [[ "$PKG_MANAGER" == "yum" ]]; then
    yum install -y -q curl ca-certificates || error "$(t app.sub2api.error.base_deps_install_pkg)"
  fi
  success "$(t app.sub2api.success.base_deps)"
}
_ensure_postgres_running() {
  local pg_ver="${1:-15}"
  if systemctl is-active --quiet postgresql 2>/dev/null || \
      systemctl is-active --quiet "postgresql-${pg_ver}" 2>/dev/null; then
    return 0
  fi
  warn "$(t app.sub2api.warn.postgres_not_running)"
  if systemctl start postgresql 2>/dev/null; then
    return 0
  fi
  if systemctl start "postgresql-${pg_ver}" 2>/dev/null; then
    return 0
  fi
  error "$(t app.sub2api.error.postgres_start)"
}
_install_postgres() {
  if command -v psql &>/dev/null; then
    local pg_ver
    pg_ver=$(psql --version 2>/dev/null | grep -oE '[0-9]+' | head -1 || echo "0")
    if [[ "$pg_ver" -ge 15 ]]; then
      if ! systemctl enable postgresql 2>/dev/null && \
          ! systemctl enable "postgresql-${pg_ver}" 2>/dev/null; then
        warn "$(t app.sub2api.warn.service_enable_failed "postgresql-${pg_ver}" "postgresql-${pg_ver}")"
      fi
      _ensure_postgres_running "$pg_ver"
      success "$(t app.sub2api.success.postgres_exists "$pg_ver")"
      return 0
    fi
    warn "$(t app.sub2api.warn.postgres_old "$pg_ver")"
  fi
  if [[ "$PKG_MANAGER" == "apt" ]]; then
    info "$(t app.sub2api.info.postgres_apt_source)"
    local pg_keyring_dir="/usr/share/postgresql-common/pgdg"
    if ! install -d "$pg_keyring_dir"; then
      error "$(t app.sub2api.error.postgres_keyring_dir "$pg_keyring_dir")"
    fi
    local pg_keyring pg_key_tmp
    pg_keyring="${pg_keyring_dir}/apt.postgresql.org.asc"
    if ! pg_key_tmp="$(mktemp "${pg_keyring}.XXXXXX")"; then
      error "$(t app.sub2api.error.postgres_key)"
    fi
    if ! curl -fsSL --max-time 30 -o "$pg_key_tmp" \
        "https://www.postgresql.org/media/keys/ACCC4CF8.asc" \
        || ! chmod 644 "$pg_key_tmp" \
        || ! chown root:root "$pg_key_tmp" \
        || ! mv "$pg_key_tmp" "$pg_keyring"; then
      rm -f "$pg_key_tmp"
      error "$(t app.sub2api.error.postgres_key)"
    fi
    local codename
    codename="$(_apt_codename)"
    local apt_source_dir="/etc/apt/sources.list.d"
    if ! mkdir -p "$apt_source_dir"; then
      error "$(t app.sub2api.error.postgres_source_dir "$apt_source_dir")"
    fi
    local pg_source_list="/etc/apt/sources.list.d/pgdg.list"
    local pg_source_tmp
    if ! pg_source_tmp=$(mktemp "${pg_source_list}.XXXXXX"); then
      error "$(t app.sub2api.error.postgres_source)"
    fi
    if ! printf '%s\n' "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt ${codename}-pgdg main" > "$pg_source_tmp" \
        || ! chmod 644 "$pg_source_tmp" \
        || ! chown root:root "$pg_source_tmp" \
        || ! mv "$pg_source_tmp" "$pg_source_list"; then
      rm -f "$pg_source_tmp"
      error "$(t app.sub2api.error.postgres_source)"
    fi
    if ! apt-get update -qq; then
      error "$(t app.sub2api.error.postgres_apt_update)"
    fi
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-15 postgresql-client-15; then
      error "$(t app.sub2api.error.postgres_apt_install)"
    fi
    if ! systemctl enable postgresql 2>/dev/null; then
      warn "$(t app.sub2api.warn.service_enable_failed "postgresql" "postgresql")"
    fi
    _ensure_postgres_running "15"
    success "$(t app.sub2api.success.postgres15)"
  elif [[ "$PKG_MANAGER" == "dnf" || "$PKG_MANAGER" == "yum" ]]; then
    info "$(t app.sub2api.info.postgres_rpm_source)"
    local el_ver
    el_ver=$(rpm -E '%{rhel}' 2>/dev/null || echo "8")
    local pgdg_rpm="https://download.postgresql.org/pub/repos/yum/reporpms/EL-${el_ver}-${ARCH}/pgdg-redhat-repo-latest.noarch.rpm"
    local pg_data_version="/var/lib/pgsql/15/data/PG_VERSION"
    if [[ "$PKG_MANAGER" == "dnf" ]]; then
      dnf install -y "$pgdg_rpm" || error "$(t app.sub2api.error.postgres_repo)"
      dnf -qy module disable postgresql || error "$(t app.sub2api.error.postgres_module)"
      dnf install -y postgresql15-server postgresql15-contrib || error "$(t app.sub2api.error.postgres_rpm_install)"
    else
      yum install -y "$pgdg_rpm" || error "$(t app.sub2api.error.postgres_repo)"
      yum install -y postgresql15-server postgresql15-contrib || error "$(t app.sub2api.error.postgres_rpm_install)"
    fi
    if [[ ! -f "$pg_data_version" ]]; then
      /usr/pgsql-15/bin/postgresql-15-setup initdb || error "$(t app.sub2api.error.postgres_initdb)"
    fi
    if ! systemctl enable postgresql-15 2>/dev/null; then
      warn "$(t app.sub2api.warn.service_enable_failed "postgresql-15" "postgresql-15")"
    fi
    _ensure_postgres_running "15"
    success "$(t app.sub2api.success.postgres15)"
  fi
}
_ensure_redis_running() {
  local redis_unit
  for redis_unit in redis-server redis; do
    if systemctl is-active --quiet "$redis_unit" 2>/dev/null; then
      return 0
    fi
  done
  for redis_unit in redis-server redis; do
    if systemctl start "$redis_unit" 2>/dev/null; then
      if ! systemctl enable "$redis_unit" 2>/dev/null; then
        warn "$(t app.sub2api.warn.service_enable_failed "$redis_unit" "$redis_unit")"
      fi
      return 0
    fi
  done
  return 1
}
_install_redis() {
  if command -v redis-server &>/dev/null; then
    local redis_ver
    redis_ver=$(redis-server --version 2>/dev/null \
      | grep -oE 'v=[0-9]+' | grep -oE '[0-9]+' || echo "0")
    if [[ "$redis_ver" -ge 7 ]]; then
      _ensure_redis_running || error "$(t app.sub2api.error.redis_start)"
      success "$(t app.sub2api.success.redis_exists "$redis_ver")"
      return 0
    fi
    warn "$(t app.sub2api.warn.redis_old "$redis_ver")"
  fi
  if [[ "$PKG_MANAGER" == "apt" ]]; then
    info "$(t app.sub2api.info.redis_apt_source)"
    local redis_keyring_dir="/usr/share/keyrings"
    if ! install -d "$redis_keyring_dir"; then
      error "$(t app.sub2api.error.redis_keyring_dir "$redis_keyring_dir")"
    fi
    local redis_keyring redis_key_tmp
    redis_keyring="${redis_keyring_dir}/redis-archive-keyring.gpg"
    if ! redis_key_tmp="$(mktemp "${redis_keyring}.tmp.XXXXXX")"; then
      error "$(t app.sub2api.error.redis_key)"
    fi
    if ! curl -fsSL --max-time 30 "https://packages.redis.io/gpg" \
        | gpg --batch --yes --dearmor -o "$redis_key_tmp"; then
      rm -f "$redis_key_tmp"
      error "$(t app.sub2api.error.redis_key)"
    fi
    if ! chmod 644 "$redis_key_tmp" \
        || ! chown root:root "$redis_key_tmp" \
        || ! mv "$redis_key_tmp" "$redis_keyring"; then
      rm -f "$redis_key_tmp"
      error "$(t app.sub2api.error.redis_key)"
    fi
    local codename
    codename="$(_apt_codename)"
    local apt_source_dir="/etc/apt/sources.list.d"
    if ! mkdir -p "$apt_source_dir"; then
      error "$(t app.sub2api.error.redis_source_dir "$apt_source_dir")"
    fi
    local redis_source_list="/etc/apt/sources.list.d/redis.list"
    local redis_source_tmp
    if ! redis_source_tmp=$(mktemp "${redis_source_list}.XXXXXX"); then
      error "$(t app.sub2api.error.redis_source)"
    fi
    if ! printf '%s\n' "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb ${codename} main" > "$redis_source_tmp" \
        || ! chmod 644 "$redis_source_tmp" \
        || ! chown root:root "$redis_source_tmp" \
        || ! mv "$redis_source_tmp" "$redis_source_list"; then
      rm -f "$redis_source_tmp"
      error "$(t app.sub2api.error.redis_source)"
    fi
    if ! apt-get update -qq; then
      error "$(t app.sub2api.error.redis_apt_update)"
    fi
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y redis; then
      error "$(t app.sub2api.error.redis_apt_install)"
    fi
    _ensure_redis_running || error "$(t app.sub2api.error.redis_start)"
    success "$(t app.sub2api.success.redis7)"
  elif [[ "$PKG_MANAGER" == "dnf" ]]; then
    dnf install -y redis || error "$(t app.sub2api.error.redis_pkg_install)"
    _ensure_redis_running || error "$(t app.sub2api.error.redis_start)"
    success "$(t app.sub2api.success.redis)"
  elif [[ "$PKG_MANAGER" == "yum" ]]; then
    yum install -y redis || error "$(t app.sub2api.error.redis_pkg_install)"
    _ensure_redis_running || error "$(t app.sub2api.error.redis_start)"
    success "$(t app.sub2api.success.redis)"
  fi
}
_ensure_nginx_running() {
  if systemctl is-active --quiet nginx 2>/dev/null; then
    return 0
  fi
  if ! systemctl start nginx 2>/dev/null; then
    error "$(t app.sub2api.error.nginx_start)"
  fi
  if ! systemctl is-active --quiet nginx 2>/dev/null; then
    error "$(t app.sub2api.error.nginx_start)"
  fi
}
_uri_encode() {
  local value="$1" output="" i char encoded
  # Case-pattern classes and printf %02X are collation-dependent: under UTF-8
  # locales the ASCII arm can miss accented characters and "'$char" yields the
  # code point instead of UTF-8 bytes. Pin C so non-ASCII is percent-encoded
  # as its UTF-8 bytes in the PostgreSQL DSN.
  local LC_ALL=C
  for ((i = 0; i < ${#value}; i++)); do
    char="${value:i:1}"
    case "$char" in
      [A-Za-z0-9.~_-]) output+="$char" ;;
      *) printf -v encoded '%%%02X' "'$char"; output+="$encoded" ;;
    esac
  done
  printf '%s' "$output"
}
_setup_postgres() {
  if ! systemctl is-active --quiet postgresql 2>/dev/null && \
     ! systemctl is-active --quiet postgresql-15 2>/dev/null; then
    warn "$(t app.sub2api.warn.postgres_not_running)"
    if ! systemctl start postgresql 2>/dev/null \
        && ! systemctl start postgresql-15 2>/dev/null; then
      error "$(t app.sub2api.error.postgres_start)"
    fi
  fi
  if [[ -z "${PG_PASS:-}" ]]; then
    PG_PASS=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 24; true)
    info "$(t app.sub2api.info.pg_password_generated)"
  else
    info "$(t app.sub2api.info.pg_password_reused)"
  fi
  info "$(t app.sub2api.info.pg_setup)"
  local user_exists
  user_exists=$(sudo -u postgres psql -tAc \
    "SELECT 1 FROM pg_roles WHERE rolname='${PG_USER}'" 2>/dev/null || echo "")
  if [[ "$user_exists" == "1" ]]; then
    info "$(t app.sub2api.info.pg_user_exists "$PG_USER")"
    sudo -u postgres psql -v pg_pass="$PG_PASS" -c \
      "ALTER USER ${PG_USER} WITH PASSWORD :'pg_pass';" > /dev/null
  else
    sudo -u postgres psql -v pg_pass="$PG_PASS" -c \
      "CREATE USER ${PG_USER} WITH PASSWORD :'pg_pass';" > /dev/null
    success "$(t app.sub2api.success.pg_user_created "$PG_USER")"
  fi
  local db_exists
  db_exists=$(sudo -u postgres psql -tAc \
    "SELECT 1 FROM pg_database WHERE datname='${PG_DB}'" 2>/dev/null || echo "")
  if [[ "$db_exists" == "1" ]]; then
    info "$(t app.sub2api.info.pg_db_exists "$PG_DB")"
  else
    sudo -u postgres psql -c \
      "CREATE DATABASE ${PG_DB} OWNER ${PG_USER};" > /dev/null
    success "$(t app.sub2api.success.pg_db_created "$PG_DB" "$PG_USER")"
  fi
  PG_DSN="postgresql://${PG_USER}:$(_uri_encode "$PG_PASS")@localhost:5432/${PG_DB}?sslmode=disable"
  success "$(t app.sub2api.success.pg_dsn)"
}
_install_nginx() {
  if command -v nginx &>/dev/null; then
    info "$(t app.sub2api.info.nginx_exists)"
  else
    info "$(t app.sub2api.info.install_nginx)"
    if [[ "$PKG_MANAGER" == "apt" ]]; then
      if ! DEBIAN_FRONTEND=noninteractive apt-get install -y nginx; then
        error "$(t app.sub2api.error.nginx_install)"
      fi
    elif [[ "$PKG_MANAGER" == "dnf" ]]; then
      dnf install -y nginx || error "$(t app.sub2api.error.nginx_install)"
    elif [[ "$PKG_MANAGER" == "yum" ]]; then
      yum install -y nginx || error "$(t app.sub2api.error.nginx_install)"
    fi
  fi
  if ! systemctl enable nginx; then
    warn "$(t app.sub2api.warn.service_enable_failed "nginx" "nginx")"
  fi
  _ensure_nginx_running
  success "$(t app.sub2api.success.nginx_installed)"
}
_write_nginx_config() {
  local server_name_line
  if [[ -n "${SUB2API_DOMAIN:-}" ]]; then
    server_name_line="    server_name ${SUB2API_DOMAIN};"
  else
    server_name_line="    server_name _;"
  fi
  if ! mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled; then
    error "$(t app.sub2api.error.nginx_config_write)"
  fi
  local nginx_conf="/etc/nginx/sites-available/sub2api"
  app_write_nginx_config_file "$nginx_conf" "app.sub2api.error.nginx_config_write" << NGINX
server {
    listen 80;
${server_name_line}

    # Allow larger API request bodies.
    client_max_body_size 64m;

    location / {
        proxy_pass         http://127.0.0.1:${PORT};
        proxy_http_version 1.1;

        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;

        # Keep SSE and AI streaming responses unbuffered.
        proxy_buffering    off;
        proxy_cache        off;

        # AI inference can take longer than a typical web request.
        proxy_read_timeout    300s;
        proxy_connect_timeout  10s;
        proxy_send_timeout     60s;

        # Preserve WebSocket upgrade support for future compatibility.
        proxy_set_header   Upgrade    \$http_upgrade;
        proxy_set_header   Connection "upgrade";
    }
}
NGINX
  app_write_nginx_site_link "$nginx_conf" /etc/nginx/sites-enabled/sub2api "app.sub2api.error.nginx_config_write"
  if [[ "$PKG_MANAGER" != "apt" ]]; then
    if ! grep -q "sites-enabled" /etc/nginx/nginx.conf 2>/dev/null; then
      local nginx_main_conf="/etc/nginx/nginx.conf"
      local nginx_main_tmp
      if ! nginx_main_tmp=$(mktemp "${nginx_main_conf}.XXXXXX"); then
        warn "$(t app.sub2api.warn.nginx_include)"
        return 0
      fi
      if awk '
          /^[[:space:]]*http[[:space:]]*{/ && !inserted {
            print
            print "    include /etc/nginx/sites-enabled/*;"
            inserted=1
            next
          }
          { print }
          END { if (!inserted) exit 1 }
        ' "$nginx_main_conf" > "$nginx_main_tmp" 2>/dev/null \
          && chmod 644 "$nginx_main_tmp" \
          && chown root:root "$nginx_main_tmp" \
          && mv "$nginx_main_tmp" "$nginx_main_conf"; then
        :
      else
        rm -f "$nginx_main_tmp"
        warn "$(t app.sub2api.warn.nginx_include)"
      fi
    fi
  fi
  if nginx -t 2>/dev/null; then
    if systemctl reload nginx; then
      if [[ -n "${SUB2API_DOMAIN:-}" ]]; then
        success "$(t app.sub2api.success.nginx_domain "$SUB2API_DOMAIN" "$PORT")"
      else
        success "$(t app.sub2api.success.nginx_fallback "$PORT")"
      fi
    else
      warn "$(t app.sub2api.warn.nginx_reload_failed)"
    fi
  else
    warn "$(t app.sub2api.warn.nginx_test_failed)"
    nginx -t >&2 || true
  fi
}
_write_systemd_unit() {
  local unit_path="/etc/systemd/system/${SERVICE_NAME}.service"
  if ! systemd_write_unit "$unit_path" << EOF
[Unit]
Description=Sub2API - AI API Gateway Platform
Documentation=https://github.com/${GITHUB_REPO}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_USER}
WorkingDirectory=${DATA_DIR}

ExecStart=${BIN_PATH}

# Restart automatically, with burst limits to avoid a crash loop.
Restart=always
RestartSec=5
StartLimitInterval=60
StartLimitBurst=5

# Environment variables.
Environment="SERVER_HOST=${SUB2API_BIND_ADDR}"
Environment="SERVER_PORT=${PORT}"
Environment="TZ=${SUB2API_TZ}"
# Prefer Go DNS resolution to reduce SSE timeout stalls.
Environment="GODEBUG=netdns=go"

# File descriptor and process limits for API gateway workloads.
LimitNOFILE=65536
LimitNPROC=512

# Security hardening.
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
# Keep the filesystem read-only except for runtime directories.
ReadWritePaths=${DATA_DIR} ${LOG_DIR} ${CONFIG_DIR}

StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}

[Install]
WantedBy=multi-user.target
EOF
  then
    error "$(t app.sub2api.error.systemd_unit "$SERVICE_NAME")"
  fi
}
_write_backup_script() {
  if ! mkdir -p "$BACKUP_DIR"; then
    error "$(t app.sub2api.error.backup_dir_create "$BACKUP_DIR")"
  fi
  local backup_dir_literal data_dir_literal config_dir_literal service_name_literal keep_days_literal pg_dsn_literal
  printf -v backup_dir_literal '%q' "$BACKUP_DIR"
  printf -v data_dir_literal '%q' "$DATA_DIR"
  printf -v config_dir_literal '%q' "$CONFIG_DIR"
  printf -v service_name_literal '%q' "$SERVICE_NAME"
  printf -v keep_days_literal '%q' "$BACKUP_KEEP_DAYS"
  printf -v pg_dsn_literal '%q' "$PG_DSN"
  local msg_start msg_backup_dir_failed msg_pg_dump_start msg_pg_dump_ok msg_pg_dump_failed msg_pg_dsn_missing msg_pg_dump_missing
  local msg_config_ok msg_config_failed msg_data_ok msg_data_failed msg_removed_old msg_remove_failed msg_done
  msg_start="$(t app.sub2api.backup.log.start)"
  msg_backup_dir_failed="$(t app.sub2api.backup.log.dir_failed '%s')"
  msg_pg_dump_start="$(t app.sub2api.backup.log.pg_dump_start)"
  msg_pg_dump_ok="$(t app.sub2api.backup.log.pg_dump_ok '%s' '%s')"
  msg_pg_dump_failed="$(t app.sub2api.backup.log.pg_dump_failed)"
  msg_pg_dsn_missing="$(t app.sub2api.backup.log.pg_dsn_missing)"
  msg_pg_dump_missing="$(t app.sub2api.backup.log.pg_dump_missing)"
  msg_config_ok="$(t app.sub2api.backup.log.config_ok '%s')"
  msg_config_failed="$(t app.sub2api.backup.log.config_failed)"
  msg_data_ok="$(t app.sub2api.backup.log.data_ok '%s' '%s')"
  msg_data_failed="$(t app.sub2api.backup.log.data_failed)"
  msg_removed_old="$(t app.sub2api.backup.log.removed_old '%s' '%s')"
  msg_remove_failed="$(t app.sub2api.backup.log.remove_failed '%s')"
  msg_done="$(t app.sub2api.backup.log.done)"
  local backup_script="/usr/local/bin/sub2api-backup"
  local backup_tmp
  if ! backup_tmp=$(mktemp "${backup_script}.XXXXXX"); then
    error "$(t app.sub2api.error.backup_script)"
  fi
  if ! cat > "$backup_tmp" << BKSH_HEADER
#!/bin/bash
# Auto-generated Sub2API backup script. Do not edit this file manually.
# Regenerate it with: sudo bash install_sub2api.sh install
set -euo pipefail
umask 077

BACKUP_DIR=${backup_dir_literal}
DATA_DIR=${data_dir_literal}
CONFIG_DIR=${config_dir_literal}
SERVICE_NAME=${service_name_literal}
KEEP_DAYS=${keep_days_literal}
[[ "\$KEEP_DAYS" =~ ^[0-9]+$ ]] || KEEP_DAYS=0
PG_DSN=${pg_dsn_literal}
MSG_START="${msg_start}"
MSG_BACKUP_DIR_FAILED="${msg_backup_dir_failed}"
MSG_PG_DUMP_START="${msg_pg_dump_start}"
MSG_PG_DUMP_OK="${msg_pg_dump_ok}"
MSG_PG_DUMP_FAILED="${msg_pg_dump_failed}"
MSG_PG_DSN_MISSING="${msg_pg_dsn_missing}"
MSG_PG_DUMP_MISSING="${msg_pg_dump_missing}"
MSG_CONFIG_OK="${msg_config_ok}"
MSG_CONFIG_FAILED="${msg_config_failed}"
MSG_DATA_OK="${msg_data_ok}"
MSG_DATA_FAILED="${msg_data_failed}"
MSG_REMOVED_OLD="${msg_removed_old}"
MSG_REMOVE_FAILED="${msg_remove_failed}"
MSG_DONE="${msg_done}"
BKSH_HEADER
  then
    rm -f "$backup_tmp"
    error "$(t app.sub2api.error.backup_script)"
  fi
  if ! cat >> "$backup_tmp" << 'BKSH_BODY'

LOG="${BACKUP_DIR}/backup.log"
TS=$(date +%Y%m%d_%H%M%S)
ARCHIVE="${BACKUP_DIR}/sub2api_${TS}.tar.gz"
ARCHIVE_TMP="${ARCHIVE}.tmp"
PG_DUMP_FILE="${BACKUP_DIR}/sub2api_db_${TS}.sql.gz"
PG_DUMP_TMP="${PG_DUMP_FILE}.tmp"

_log() { echo "$(date '+%F %T')  $*" >> "$LOG"; }
if ! mkdir -p "${BACKUP_DIR}"; then
  printf '%s  %s\n' "$(date '+%F %T')" "$(printf "$MSG_BACKUP_DIR_FAILED" "$BACKUP_DIR")" >&2
  exit 1
fi
_log "── ${MSG_START} ────────────────────────────────────"

# ── 1. PostgreSQL database backup ─────────────────────────────
if [[ -n "${PG_DSN}" ]] && command -v pg_dump &>/dev/null; then
  _log "${MSG_PG_DUMP_START}"
  if pg_dump "${PG_DSN}" 2> >(
      while IFS= read -r line; do
        _log "[PG_DUMP] ${line}"
      done
    ) | gzip > "${PG_DUMP_TMP}"; then
    if mv "${PG_DUMP_TMP}" "${PG_DUMP_FILE}"; then
      # Integrity sidecar for the database dump.
      if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "${PG_DUMP_FILE}" | awk '{print $1"  "$(NF)}' > "${PG_DUMP_FILE}.sha256" || true
        chmod 600 "${PG_DUMP_FILE}.sha256" 2>/dev/null || true
      elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "${PG_DUMP_FILE}" | awk '{print $1"  "$(NF)}' > "${PG_DUMP_FILE}.sha256" || true
        chmod 600 "${PG_DUMP_FILE}.sha256" 2>/dev/null || true
      fi
      DB_SIZE=$(du -sh "${PG_DUMP_FILE}" 2>/dev/null | awk '{print $1}')
      _log "$(printf "$MSG_PG_DUMP_OK" "$PG_DUMP_FILE" "$DB_SIZE")"
    else
      rm -f "${PG_DUMP_TMP}"
      _log "${MSG_PG_DUMP_FAILED}"
    fi
  else
    rm -f "${PG_DUMP_TMP}"
    _log "${MSG_PG_DUMP_FAILED}"
  fi
else
  if [[ -z "${PG_DSN}" ]]; then
    _log "${MSG_PG_DSN_MISSING}"
  else
    _log "${MSG_PG_DUMP_MISSING}"
  fi
fi

# ── 2. Configuration and local data backup ───────────────────
TAR_ARGS=()
if [[ -d "${DATA_DIR}" ]]; then
  TAR_ARGS+=(-C "$(dirname "${DATA_DIR}")" "$(basename "${DATA_DIR}")")
fi

if [[ -d "${CONFIG_DIR}" ]]; then
  EXTRA_CONF_ARCHIVE="${BACKUP_DIR}/sub2api_conf_${TS}.tar.gz"
  EXTRA_CONF_TMP="${EXTRA_CONF_ARCHIVE}.tmp"
  if tar -czf "${EXTRA_CONF_TMP}" \
      -C "$(dirname "${CONFIG_DIR}")" "$(basename "${CONFIG_DIR}")" 2>&1 | \
      while IFS= read -r line; do _log "[TAR-CONF] ${line}"; done; then
    if mv "${EXTRA_CONF_TMP}" "${EXTRA_CONF_ARCHIVE}"; then
      # Integrity sidecar for the config archive.
      if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "${EXTRA_CONF_ARCHIVE}" | awk '{print $1"  "$(NF)}' > "${EXTRA_CONF_ARCHIVE}.sha256" || true
        chmod 600 "${EXTRA_CONF_ARCHIVE}.sha256" 2>/dev/null || true
      elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "${EXTRA_CONF_ARCHIVE}" | awk '{print $1"  "$(NF)}' > "${EXTRA_CONF_ARCHIVE}.sha256" || true
        chmod 600 "${EXTRA_CONF_ARCHIVE}.sha256" 2>/dev/null || true
      fi
      _log "$(printf "$MSG_CONFIG_OK" "$EXTRA_CONF_ARCHIVE")"
    else
      rm -f "${EXTRA_CONF_TMP}"
      _log "${MSG_CONFIG_FAILED}"
    fi
  else
    rm -f "${EXTRA_CONF_TMP}"
    _log "${MSG_CONFIG_FAILED}"
  fi
fi

if [[ ${#TAR_ARGS[@]} -gt 0 ]]; then
  if tar -czf "${ARCHIVE_TMP}" \
      --exclude="*.log" --exclude="*.log.*" \
      "${TAR_ARGS[@]}" 2>&1 | \
      while IFS= read -r line; do _log "[TAR] ${line}"; done; then
    if mv "${ARCHIVE_TMP}" "${ARCHIVE}"; then
      # Integrity sidecar for the data archive.
      if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "${ARCHIVE}" | awk '{print $1"  "$(NF)}' > "${ARCHIVE}.sha256" || true
        chmod 600 "${ARCHIVE}.sha256" 2>/dev/null || true
      elif command -v shasum >/dev/null 2>&1; then
        shasum -a 256 "${ARCHIVE}" | awk '{print $1"  "$(NF)}' > "${ARCHIVE}.sha256" || true
        chmod 600 "${ARCHIVE}.sha256" 2>/dev/null || true
      fi
      SIZE=$(du -sh "${ARCHIVE}" 2>/dev/null | awk '{print $1}')
      _log "$(printf "$MSG_DATA_OK" "$ARCHIVE" "$SIZE")"
    else
      rm -f "${ARCHIVE_TMP}"
      _log "${MSG_DATA_FAILED}"
    fi
  else
    rm -f "${ARCHIVE_TMP}"
    _log "${MSG_DATA_FAILED}"
  fi
fi

# ── 3. Retention cleanup ─────────────────────────────────────
if [[ "${KEEP_DAYS}" -gt 0 ]]; then
  REMOVED=0
  while IFS= read -r f; do
    if rm -f "$f"; then
      REMOVED=$(( REMOVED + 1 ))
    else
      _log "$(printf "$MSG_REMOVE_FAILED" "$f")"
    fi
  done < <(find "${BACKUP_DIR}" -maxdepth 1 \
    \( -name "sub2api_*.tar.gz" -o -name "sub2api_db_*.sql.gz" \
    -o -name "sub2api_conf_*.tar.gz" \) \
    -mtime "+${KEEP_DAYS}" 2>/dev/null)
  if [[ $REMOVED -gt 0 ]]; then
    _log "$(printf "$MSG_REMOVED_OLD" "$REMOVED" "$KEEP_DAYS")"
  fi
fi

_log "── ${MSG_DONE} ────────────────────────────────────"
BKSH_BODY
  then
    rm -f "$backup_tmp"
    error "$(t app.sub2api.error.backup_script)"
  fi
  if ! chmod 750 "$backup_tmp" \
      || ! chown root:root "$backup_tmp" \
      || ! mv "$backup_tmp" "$backup_script"; then
    rm -f "$backup_tmp"
    error "$(t app.sub2api.error.backup_script)"
  fi
  success "$(t app.sub2api.success.backup_script)"
}
_backup_silent() {
  local label="${1:-manual}"
  local backup_failed=0
  local backup_log="${BACKUP_DIR}/backup.log"
  _log_backup_helper() {
    [[ -d "$BACKUP_DIR" ]] || return 1
    printf '%s  %s\n' "$(date '+%F %T')" "$1" >> "$backup_log"
  }
  if ! mkdir -p "$BACKUP_DIR"; then
    warn "$(t app.sub2api.warn.backup_dir_unwritable "$BACKUP_DIR")"
    return 1
  fi
  if [[ -n "${PG_DSN:-}" ]] && command -v pg_dump &>/dev/null; then
    local pg_archive
    pg_archive="${BACKUP_DIR}/sub2api_db_${label}_$(date +%Y%m%d_%H%M%S).sql.gz"
    local pg_tmp="${pg_archive}.tmp"
    if pg_dump "${PG_DSN}" 2> >(sed 's/^/  /' >&2) | gzip > "$pg_tmp"; then
      if mv "$pg_tmp" "$pg_archive"; then
        local sz; sz=$(du -sh "$pg_archive" 2>/dev/null | awk '{print $1}')
        success "$(t app.sub2api.success.silent_pg_dump "$pg_archive" "$sz")"
      else
        rm -f "$pg_tmp"
        _log_backup_helper "$(t app.sub2api.backup.log.pg_dump_failed)"
        warn "$(t app.sub2api.warn.pg_dump_failed)"
        backup_failed=1
      fi
    else
      rm -f "$pg_tmp"
      _log_backup_helper "$(t app.sub2api.backup.log.pg_dump_failed)"
      warn "$(t app.sub2api.warn.pg_dump_failed)"
      backup_failed=1
    fi
  else
    _log_backup_helper "$(t app.sub2api.backup.log.pg_dump_missing)"
    warn "$(t app.sub2api.warn.pg_snapshot_skip)"
  fi
  if [[ -d "$CONFIG_DIR" ]]; then
    local conf_archive
    conf_archive="${BACKUP_DIR}/sub2api_conf_${label}_$(date +%Y%m%d_%H%M%S).tar.gz"
    local conf_tmp="${conf_archive}.tmp"
    if tar -czf "$conf_tmp" \
        -C "$(dirname "$CONFIG_DIR")" "$(basename "$CONFIG_DIR")" >&2; then
      if mv "$conf_tmp" "$conf_archive"; then
        local sz; sz=$(du -sh "$conf_archive" 2>/dev/null | awk '{print $1}')
        success "$(t app.sub2api.success.config_backup "$conf_archive" "$sz")"
      else
        rm -f "$conf_tmp"
        _log_backup_helper "$(t app.sub2api.backup.log.config_failed)"
        warn "$(t app.sub2api.warn.config_backup_failed)"
        backup_failed=1
      fi
    else
      rm -f "$conf_tmp"
      _log_backup_helper "$(t app.sub2api.backup.log.config_failed)"
      warn "$(t app.sub2api.warn.config_backup_failed)"
      backup_failed=1
    fi
  fi
  [[ "$backup_failed" -eq 0 ]]
}
_print_install_summary() {
  local version="$1"
  local summary_state="${2:-ready}"
  local INTERNAL_IP
  INTERNAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
  INTERNAL_IP="${INTERNAL_IP:-YOUR_SERVER_IP}"
  local access_url
  local summary_title next_step_two
  if [[ -n "${SUB2API_DOMAIN:-}" ]]; then
    access_url="http://${SUB2API_DOMAIN}/"
  else
    access_url="http://${INTERNAL_IP}:${PORT}/"
  fi
  if [[ "$summary_state" == "pending" ]]; then
    summary_title="$(t app.sub2api.summary.title_pending)"
    next_step_two="$(t app.sub2api.summary.next2_pending)"
  else
    summary_title="$(t app.sub2api.summary.title_ready)"
    next_step_two="$(t app.sub2api.summary.next2_ready)"
  fi
  echo ""
  echo -e "${BOLD}${GREEN}"
  echo "  ╔════════════════════════════════════════════════════════════════╗"
  echo "  ║              ${summary_title}                            ║"
  echo "  ╠════════════════════════════════════════════════════════════════╣"
  echo -e "  ║  Setup Wizard   ${CYAN}${access_url}${GREEN}"
  echo -e "  ║  $(t app.sub2api.summary.version)           ${YELLOW}${version}${GREEN}"
  echo "  ╠════════════════════════════════════════════════════════════════╣"
  echo -e "  ║  ${BOLD}$(t app.sub2api.summary.postgres_title)${GREEN}"
  echo -e "  ║    $(t app.sub2api.summary.host)         ${CYAN}localhost${GREEN}"
  echo -e "  ║    $(t app.sub2api.summary.port)         ${CYAN}5432${GREEN}"
  echo -e "  ║    $(t app.sub2api.summary.username)       ${CYAN}${PG_USER}${GREEN}"
  echo -e "  ║    $(t app.sub2api.summary.password)         ${YELLOW}$(t app.sub2api.summary.password_written "$CONF_FILE")${GREEN}"
  echo -e "  ║    $(t app.sub2api.summary.database)     ${CYAN}${PG_DB}${GREEN}"
  echo -e "  ║    $(t app.sub2api.summary.ssl_mode)     ${CYAN}$(t app.sub2api.summary.ssl_disable)${GREEN}"
  echo "  ╠════════════════════════════════════════════════════════════════╣"
  echo -e "  ║  ${BOLD}$(t app.sub2api.summary.redis_title)${GREEN}"
  echo -e "  ║    $(t app.sub2api.summary.host)         ${CYAN}localhost${GREEN}"
  echo -e "  ║    $(t app.sub2api.summary.port)         ${CYAN}6379${GREEN}"
  echo -e "  ║    $(t app.sub2api.summary.password)         ${CYAN}$(t app.sub2api.summary.empty)${GREEN}"
  echo "  ╠════════════════════════════════════════════════════════════════╣"
  echo -e "  ║  $(t app.sub2api.summary.install_dir)       ${YELLOW}${INSTALL_DIR}${GREEN}"
  echo -e "  ║  $(t app.sub2api.summary.data_dir)       ${YELLOW}${DATA_DIR}${GREEN}"
  echo -e "  ║  $(t app.sub2api.summary.config_dir)       ${YELLOW}${CONFIG_DIR}${GREEN}"
  echo -e "  ║  $(t app.sub2api.summary.log_dir)       ${YELLOW}${LOG_DIR}${GREEN}"
  echo -e "  ║  $(t app.sub2api.summary.backup_dir)       ${YELLOW}${BACKUP_DIR}${GREEN}"
  echo "  ╠════════════════════════════════════════════════════════════════╣"
  echo "  ║  $(t app.sub2api.summary.next_steps)"
  echo -e "  ║    1) $(t app.sub2api.summary.next1)"
  echo -e "  ║    2) ${next_step_two}"
  echo -e "  ║    3) $(t app.sub2api.summary.next3 "$CONF_FILE")"
  echo "  ╚════════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
  echo -e "  ${BOLD}$(t app.sub2api.summary.management)${NC}"
  echo -e "    ${CYAN}bash $0 status${NC}      - $(t app.sub2api.summary.cmd_status)"
  echo -e "    ${CYAN}bash $0 update${NC}      - $(t app.sub2api.summary.cmd_update)"
  echo -e "    ${CYAN}bash $0 backup${NC}      - $(t app.sub2api.summary.cmd_backup)"
  echo -e "    ${CYAN}bash $0 uninstall${NC}   - $(t app.sub2api.summary.cmd_uninstall)"
  echo ""
  echo -e "  ${BOLD}$(t app.sub2api.summary.systemd)${NC}"
  echo -e "    ${CYAN}systemctl status ${SERVICE_NAME}${NC}      $(t app.sub2api.summary.systemd_status)"
  echo -e "    ${CYAN}journalctl -u ${SERVICE_NAME} -f${NC}      $(t app.sub2api.summary.systemd_logs)"
  echo -e "    ${CYAN}systemctl restart ${SERVICE_NAME}${NC}     $(t app.sub2api.summary.systemd_restart)"
  echo ""
}
do_install() {
  show_banner
  preflight_check "install"
  acquire_lock
  step "$(t app.sub2api.step.latest)"
  check_connectivity
  info "$(t app.sub2api.info.query_release)"
  local LATEST
  LATEST=$(github_latest_release_tag "$GITHUB_REPO" "app.sub2api.warn.github_api")
  [[ -z "$LATEST" ]] && error "$(t app.sub2api.error.version_lookup)"
  success "$(t app.sub2api.success.latest_version "${BOLD}${LATEST}${NC}")"
  local DOWNLOAD_URL; DOWNLOAD_URL=$(get_download_url "$LATEST")
  info "$(t app.sub2api.info.download_url "$DOWNLOAD_URL")"
  step "$(t app.sub2api.step.base_deps)"
  _install_base_deps
  step "$(t app.sub2api.step.postgres)"
  _install_postgres
  step "$(t app.sub2api.step.redis)"
  _install_redis
  app_load_config _SUB2API_DERIVE_PATHS
  step "$(t app.sub2api.step.pg_account)"
  _setup_postgres
  step "$(t app.sub2api.step.user_dirs)"
  if ! id "$SERVICE_USER" &>/dev/null; then
    if ! useradd -r -s /usr/sbin/nologin -d "$INSTALL_DIR" "$SERVICE_USER"; then
      error "$(t app.sub2api.error.user_create "$SERVICE_USER")"
    fi
    success "$(t app.sub2api.success.user_created "$SERVICE_USER")"
  else
    info "$(t app.sub2api.info.user_exists "$SERVICE_USER")"
  fi
  require_safe_path "INSTALL_DIR" "$INSTALL_DIR"
  require_safe_path "DATA_DIR" "$DATA_DIR"
  require_safe_path "LOG_DIR" "$LOG_DIR"
  require_safe_path "CONFIG_DIR" "$CONFIG_DIR"
  require_safe_path "BACKUP_DIR" "$BACKUP_DIR"
  if ! mkdir -p "$INSTALL_DIR" "$DATA_DIR" "$LOG_DIR" "$CONFIG_DIR" "$BACKUP_DIR"; then
    error "$(t app.sub2api.error.dir_create "$INSTALL_DIR" "$BACKUP_DIR")"
  fi
  if ! chown -R "${SERVICE_USER}:${SERVICE_USER}" "$INSTALL_DIR" "$LOG_DIR" "$CONFIG_DIR"; then
    error "$(t app.sub2api.error.dir_owner "${SERVICE_USER}:${SERVICE_USER}" "$INSTALL_DIR")"
  fi
  if ! chmod 750 "$CONFIG_DIR"; then
    error "$(t app.sub2api.error.config_dir_mode "$CONFIG_DIR")"
  fi
  success "$(t app.sub2api.success.dirs_created)"
  step "$(t app.sub2api.step.download_binary "$BIN_ARCH")"
  local TMP_ARCHIVE
  if ! TMP_ARCHIVE=$(mktemp "${INSTALL_DIR}/sub2api-release.XXXXXX.tar.gz"); then
    error "$(t app.sub2api.error.download_failed "$GITHUB_REPO")"
  fi
  if ! curl -fL --progress-bar -o "$TMP_ARCHIVE" "$DOWNLOAD_URL"; then
    if ! rm -f "$TMP_ARCHIVE"; then
      warn "$(t app.sub2api.warn.tmp_archive_cleanup_failed "$TMP_ARCHIVE")"
    fi
    error "$(t app.sub2api.error.download_failed "$GITHUB_REPO")"
  fi
  verify_checksum "$TMP_ARCHIVE" "$LATEST"
  local TMP_BIN
  TMP_BIN=$(extract_and_verify "$TMP_ARCHIVE" "$INSTALL_DIR")
  rm -f "$TMP_ARCHIVE"
  local OLD_BIN_BAK=""
  if [[ -f "$BIN_PATH" ]]; then
    local OLD_TS; OLD_TS=$(date +%Y%m%d_%H%M%S)
    OLD_BIN_BAK="${INSTALL_DIR}/sub2api.bak.${OLD_TS}"
  fi
  if ! _install_binary_candidate "$TMP_BIN" "$OLD_BIN_BAK"; then
    error "$(t app.sub2api.error.binary_install "$BIN_PATH")"
  fi
  if [[ -n "$OLD_BIN_BAK" ]]; then
    warn "$(t app.sub2api.warn.old_binary_backup "$(basename "$OLD_BIN_BAK")")"
  fi
  success "$(t app.sub2api.success.binary_installed "$BIN_PATH")"
  step "$(t app.sub2api.step.systemd)"
  _write_systemd_unit
  success "$(t app.sub2api.success.systemd_unit "$SERVICE_NAME")"
  step "$(t app.sub2api.step.nginx)"
  _install_nginx
  _write_nginx_config
  step "$(t app.sub2api.step.firewall)"
  app_configure_firewall "$PORT" "app.sub2api" "Sub2API" true
  step "$(t app.sub2api.step.logrotate)"
  app_write_logrotate "/etc/logrotate.d/sub2api" "$LOG_DIR" "app.sub2api.error.logrotate" "app.sub2api.success.logrotate"
  step "$(t app.sub2api.step.cron_backup)"
  _write_backup_script
  local cron_file="/etc/cron.d/sub2api-backup"
  local cron_tmp
  if ! cron_tmp=$(mktemp "${cron_file}.XXXXXX"); then
    error "$(t app.sub2api.error.cron_backup)"
  fi
  if ! printf '%s\n' "30 3 * * * root /bin/bash /usr/local/bin/sub2api-backup" > "$cron_tmp" \
      || ! chmod 644 "$cron_tmp" \
      || ! chown root:root "$cron_tmp" \
      || ! mv "$cron_tmp" "$cron_file"; then
    rm -f "$cron_tmp"
    error "$(t app.sub2api.error.cron_backup)"
  fi
  success "$(t app.sub2api.success.cron_backup "$BACKUP_KEEP_DAYS")"
  step "$(t app.sub2api.step.start_service)"
  local _install_summary_state="ready"
  app_check_port_conflict "$PORT"
  if ! systemctl daemon-reload; then
    error "$(t app.sub2api.error.systemd_reload "$SERVICE_NAME")"
  fi
  if ! systemctl enable "$SERVICE_NAME" --quiet; then
    warn "$(t app.sub2api.warn.service_enable_failed "$SERVICE_NAME" "$SERVICE_NAME")"
  fi
  if systemctl restart "$SERVICE_NAME" && wait_for_service "$SERVICE_NAME" 25; then
    success "$(t app.sub2api.success.service_started)"
    systemctl status "$SERVICE_NAME" --no-pager -l 2>/dev/null | head -12 | sed 's/^/  /' >&2 || true
  else
    if systemctl is-failed --quiet "$SERVICE_NAME" 2>/dev/null; then
      warn "$(t app.sub2api.warn.service_failed_rollback)"
      if ! systemctl stop "$SERVICE_NAME" 2>/dev/null; then
        warn "$(t app.sub2api.warn.cleanup_stop_failed "$SERVICE_NAME" "$SERVICE_NAME")"
      fi
      if ! systemctl disable "$SERVICE_NAME" 2>/dev/null; then
        warn "$(t app.sub2api.warn.cleanup_disable_failed "$SERVICE_NAME" "$SERVICE_NAME")"
      fi
      _sub2api_remove_file_or_error "/etc/systemd/system/${SERVICE_NAME}.service" "SUB2API_SERVICE_FILE"
      if ! systemctl daemon-reload 2>/dev/null; then
        warn "$(t app.sub2api.warn.cleanup_reload_failed)"
      fi
      if [[ -n "${OLD_BIN_BAK:-}" && -f "$OLD_BIN_BAK" ]]; then
        _restore_binary_backup "$OLD_BIN_BAK" \
          || error "$(t app.sub2api.error.install_failed_rollback "$SERVICE_NAME")"
      else
        _sub2api_require_safe_bin_path
        _sub2api_remove_file_or_error "$BIN_PATH" "BIN_PATH"
      fi
      error "$(t app.sub2api.error.install_failed_rollback "$SERVICE_NAME")"
    else
      warn "$(t app.sub2api.warn.waiting_deps)"
      warn "$(t app.sub2api.warn.setup_status_later)"
      _install_summary_state="pending"
    fi
  fi
  step "$(t app.sub2api.step.health_save)"
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
  app_load_config _SUB2API_DERIVE_PATHS
  acquire_lock
  [[ ! -x "$BIN_PATH" ]] \
    && error "$(t app.sub2api.error.binary_missing_install "$BIN_PATH")"
  step "$(t app.sub2api.step.check_update)"
  check_connectivity
  info "$(t app.sub2api.info.query_release)"
  local LATEST; LATEST=$(github_latest_release_tag "$GITHUB_REPO" "app.sub2api.warn.github_api")
  [[ -z "$LATEST" ]] && error "$(t app.sub2api.error.latest_lookup)"
  local CURRENT="${INSTALLED_VERSION:-unknown}"
  info "$(t app.sub2api.info.current_version "${YELLOW}${CURRENT}${NC}")"
  info "$(t app.sub2api.info.github_latest "${YELLOW}${LATEST}${NC}")"
  if [[ "$CURRENT" == "$LATEST" ]]; then
    success "$(t app.sub2api.success.already_latest "$LATEST")"
    exit 0
  fi
  local _pre_svc_state
  _pre_svc_state=$(systemctl is-active "$SERVICE_NAME" 2>/dev/null || echo "inactive")
  if [[ "$_pre_svc_state" == "failed" ]]; then
    warn "$(t app.sub2api.warn.update_failed_state)"
  fi
  step "$(t app.sub2api.step.pre_update_backup)"
  if ! _backup_silent "pre-update"; then
    warn "$(t app.sub2api.warn.pre_update_backup)"
  fi
  step "$(t app.sub2api.step.download_update "$CURRENT" "$LATEST")"
  local DOWNLOAD_URL; DOWNLOAD_URL=$(get_download_url "$LATEST")
  info "$(t app.sub2api.info.download_url "$DOWNLOAD_URL")"
  local TMP_ARCHIVE
  if ! TMP_ARCHIVE=$(mktemp "${INSTALL_DIR}/sub2api-release.XXXXXX.tar.gz"); then
    error "$(t app.sub2api.error.update_download)"
  fi
  if ! curl -fL --progress-bar -o "$TMP_ARCHIVE" "$DOWNLOAD_URL"; then
    if ! rm -f "$TMP_ARCHIVE"; then
      warn "$(t app.sub2api.warn.tmp_archive_cleanup_failed "$TMP_ARCHIVE")"
    fi
    error "$(t app.sub2api.error.update_download)"
  fi
  verify_checksum "$TMP_ARCHIVE" "$LATEST"
  local TMP_BIN
  TMP_BIN=$(extract_and_verify "$TMP_ARCHIVE" "$INSTALL_DIR")
  rm -f "$TMP_ARCHIVE"
  step "$(t app.sub2api.step.replace_restart)"
  local BAK_TS; BAK_TS=$(date +%Y%m%d_%H%M%S)
  local BAK_PATH="${INSTALL_DIR}/sub2api.bak.${BAK_TS}"
  _backup_current_binary "$BAK_PATH" \
    || error "$(t app.sub2api.error.binary_install "$BIN_PATH")"
  info "$(t app.sub2api.info.old_binary_backup "$BAK_PATH")"
  info "$(t app.sub2api.info.stopping_service)"
  if ! systemctl stop "$SERVICE_NAME" 2>/dev/null; then
    if ! rm -f "$TMP_BIN"; then
      warn "$(t app.sub2api.warn.tmp_binary_cleanup_failed "$TMP_BIN")"
    fi
    error "$(t app.sub2api.error.stop_service_failed "$SERVICE_NAME" "$SERVICE_NAME")"
  fi
  if ! _install_binary_candidate "$TMP_BIN"; then
    if _restore_binary_backup "$BAK_PATH"; then
      if ! systemctl start "$SERVICE_NAME"; then
        warn "$(t app.sub2api.warn.rollback_start_failed "$SERVICE_NAME")"
      fi
    fi
    error "$(t app.sub2api.error.binary_install "$BIN_PATH")"
  fi
  if ! systemctl daemon-reload; then
    error "$(t app.sub2api.error.systemd_reload "$SERVICE_NAME")"
  fi
  if systemctl start "$SERVICE_NAME" && wait_for_service "$SERVICE_NAME" 25; then
    success "$(t app.sub2api.success.new_version_started)"
    INSTALLED_VERSION="$LATEST"
    app_save_config
    local -a _old_baks
    local _old_bak_entry
    while IFS= read -r -d '' _old_bak_entry; do
      _old_baks+=("${_old_bak_entry#* }")
    done < <(
      find "$INSTALL_DIR" -maxdepth 1 -name "sub2api.bak.*" -type f \
        -printf '%T@ %p\0' 2>/dev/null | sort -z -rn | tail -z -n +4
    )
    if [[ ${#_old_baks[@]} -gt 0 ]]; then
      local _cleaned_old=0
      local _old_bak
      for _old_bak in "${_old_baks[@]}"; do
        if rm -f "$_old_bak"; then
          _cleaned_old=$(( _cleaned_old + 1 ))
        else
          warn "$(t app.sub2api.warn.cleanup_old_binary_failed "$_old_bak")"
        fi
      done
      if [[ $_cleaned_old -gt 0 ]]; then
        info "$(t app.sub2api.info.cleaned_old_binaries "$_cleaned_old")"
      fi
    fi
    if ! _health_check; then
      :
    fi
    echo ""
    echo -e "  ${BOLD}${GREEN}$(t app.sub2api.success.update_done "${YELLOW}${CURRENT}${GREEN}" "${YELLOW}${LATEST}${NC}")"
    echo ""
  else
    warn "$(t app.sub2api.warn.new_version_failed "$LATEST" "$CURRENT")"
    if ! systemctl stop "$SERVICE_NAME" 2>/dev/null; then
      error "$(t app.sub2api.error.rollback_stop_failed "$SERVICE_NAME" "$BAK_PATH" "$SERVICE_NAME")"
    fi
    if ! _restore_binary_backup "$BAK_PATH"; then
      warn "$(t app.sub2api.warn.rollback_start_failed "$SERVICE_NAME")"
      error "$(t app.sub2api.error.update_failed "$CURRENT" "$SERVICE_NAME")"
    fi
    if systemctl start "$SERVICE_NAME"; then
      if wait_for_service "$SERVICE_NAME" 15; then
        success "$(t app.sub2api.success.rollback "$CURRENT")"
      else
        warn "$(t app.sub2api.warn.rollback_start_failed "$SERVICE_NAME")"
      fi
    else
      warn "$(t app.sub2api.warn.rollback_start_failed "$SERVICE_NAME")"
    fi
    error "$(t app.sub2api.error.update_failed "$CURRENT" "$SERVICE_NAME")"
  fi
}
do_backup() {
  show_banner
  preflight_check "backup"
  app_load_config _SUB2API_DERIVE_PATHS
  acquire_lock
  step "$(t app.sub2api.step.manual_backup)"
  if ! mkdir -p "$BACKUP_DIR"; then
    error "$(t app.sub2api.error.backup_dir_create "$BACKUP_DIR")"
  fi
  if [[ -n "${PG_DSN:-}" ]]; then
    if command -v pg_dump &>/dev/null; then
      local PG_ARCHIVE; PG_ARCHIVE="${BACKUP_DIR}/sub2api_db_$(date +%Y%m%d_%H%M%S).sql.gz"
      local PG_TMP="${PG_ARCHIVE}.tmp"
      info "$(t app.sub2api.info.pg_dump)"
      if pg_dump "${PG_DSN}" | gzip > "$PG_TMP"; then
        if mv "$PG_TMP" "$PG_ARCHIVE"; then
          local pg_sz; pg_sz=$(du -sh "$PG_ARCHIVE" 2>/dev/null | awk '{print $1}')
          success "$(t app.sub2api.success.db_backup "$PG_ARCHIVE" "$pg_sz")"
        else
          rm -f "$PG_TMP"
          warn "$(t app.sub2api.warn.pg_dump_check_dsn)"
        fi
      else
        rm -f "$PG_TMP"
        warn "$(t app.sub2api.warn.pg_dump_check_dsn)"
      fi
    else
      warn "$(t app.sub2api.warn.pg_dump_missing)"
    fi
  else
    warn "$(t app.sub2api.warn.pg_dsn_missing)"
  fi
  if [[ -d "$CONFIG_DIR" ]]; then
    local CONF_ARCHIVE; CONF_ARCHIVE="${BACKUP_DIR}/sub2api_conf_$(date +%Y%m%d_%H%M%S).tar.gz"
    local CONF_TMP="${CONF_ARCHIVE}.tmp"
    if tar -czf "$CONF_TMP" \
        -C "$(dirname "$CONFIG_DIR")" "$(basename "$CONFIG_DIR")" >&2; then
      if mv "$CONF_TMP" "$CONF_ARCHIVE"; then
        local cf_sz; cf_sz=$(du -sh "$CONF_ARCHIVE" 2>/dev/null | awk '{print $1}')
        success "$(t app.sub2api.success.config_backup "$CONF_ARCHIVE" "$cf_sz")"
      else
        rm -f "$CONF_TMP"
        warn "$(t app.sub2api.warn.config_backup_failed)"
      fi
    else
      rm -f "$CONF_TMP"
      warn "$(t app.sub2api.warn.config_backup_failed)"
    fi
  else
    warn "$(t app.sub2api.warn.config_missing "$CONFIG_DIR")"
  fi
  if [[ -d "$DATA_DIR" ]]; then
    local DATA_ARCHIVE; DATA_ARCHIVE="${BACKUP_DIR}/sub2api_data_$(date +%Y%m%d_%H%M%S).tar.gz"
    local DATA_TMP="${DATA_ARCHIVE}.tmp"
    if tar -czf "$DATA_TMP" \
        --exclude="*.log" --exclude="*.log.*" \
        -C "$(dirname "$DATA_DIR")" "$(basename "$DATA_DIR")" >&2; then
      if mv "$DATA_TMP" "$DATA_ARCHIVE"; then
        local da_sz; da_sz=$(du -sh "$DATA_ARCHIVE" 2>/dev/null | awk '{print $1}')
        success "$(t app.sub2api.success.data_backup "$DATA_ARCHIVE" "$da_sz")"
      else
        rm -f "$DATA_TMP"
        warn "$(t app.sub2api.warn.data_backup_failed)"
      fi
    else
      rm -f "$DATA_TMP"
      warn "$(t app.sub2api.warn.data_backup_failed)"
    fi
  else
    warn "$(t app.sub2api.warn.data_missing "$DATA_DIR")"
  fi
  local _keep_days="${BACKUP_KEEP_DAYS}"
  [[ "$_keep_days" =~ ^[0-9]+$ ]] || _keep_days=0
  if [[ "$_keep_days" -gt 0 ]]; then
    local _cleaned=0 _old_backup
    while IFS= read -r -d '' _old_backup; do
      if rm -f "$_old_backup"; then
        _cleaned=$(( _cleaned + 1 ))
      else
        warn "$(t app.sub2api.warn.backup_cleanup_failed "$_old_backup")"
      fi
    done < <(find "$BACKUP_DIR" -maxdepth 1 \
      \( -name "sub2api_*.tar.gz" -o -name "sub2api_db_*.sql.gz" \
      -o -name "sub2api_conf_*.tar.gz" \) \
      -mtime "+${_keep_days}" -type f -print0 2>/dev/null)
    if [[ $_cleaned -gt 0 ]]; then
      info "$(t app.sub2api.info.cleaned_old_backups "$_cleaned" "$_keep_days")"
    fi
  fi
  success "$(t app.sub2api.success.backup_done "$BACKUP_DIR")"
}
do_status() {
  show_banner
  preflight_check "status"
  app_load_config _SUB2API_DERIVE_PATHS
  [[ $EUID -ne 0 ]] && warn "$(t app.sub2api.warn.non_root_status "$0")"
  step "$(t app.sub2api.step.status)"
  echo -e "\n${BOLD}[$(t app.sub2api.status.systemd)]${NC}"
  if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    echo -e "  ${GREEN}[✓]${NC} $(t app.sub2api.status.service_running)${NC}"
  elif systemctl is-failed --quiet "$SERVICE_NAME" 2>/dev/null; then
    echo -e "  ${RED}[✗]${NC} $(t app.sub2api.status.service_failed)${NC}"
  else
    echo -e "  ${YELLOW}[!]${NC} $(t app.sub2api.status.service_inactive)${NC}"
  fi
  local _pid
  _pid=$(systemctl show -p MainPID --value "$SERVICE_NAME" 2>/dev/null || echo "0")
  if [[ "$_pid" != "0" && -d "/proc/${_pid}" ]]; then
    local _mem _cpu _uptime
    _mem=$(cat "/proc/${_pid}/status" 2>/dev/null \
      | grep -i 'VmRSS' | awk '{printf "%.1f MB", $2/1024}' || echo "N/A")
    _cpu=$(ps -p "$_pid" -o %cpu --no-headers 2>/dev/null | tr -d ' ' || echo "N/A")
    _uptime=$(ps -p "$_pid" -o etime --no-headers 2>/dev/null | tr -d ' ' || echo "N/A")
    echo -e "  $(t app.sub2api.status.pid):        ${_pid}"
    echo -e "  $(t app.sub2api.status.memory): ${_mem}"
    echo -e "  $(t app.sub2api.status.cpu):   ${_cpu}%"
    echo -e "  $(t app.sub2api.status.uptime):   ${_uptime}"
  fi
  echo -e "\n${BOLD}[$(t app.sub2api.status.version_info)]${NC}"
  echo -e "  $(t app.sub2api.status.installed_version): ${YELLOW}${INSTALLED_VERSION:-$(t app.sub2api.status.unknown)}${NC}"
  if [[ -x "$BIN_PATH" ]]; then
    local _bin_ver
    _bin_ver=$("$BIN_PATH" --version 2>/dev/null | head -1 || t app.sub2api.status.binary_no_version)
    echo -e "  $(t app.sub2api.status.binary_version):    ${_bin_ver}"
  fi
  echo -e "\n${BOLD}[$(t app.sub2api.status.nginx)]${NC}"
  if command -v nginx &>/dev/null; then
    if systemctl is-active --quiet nginx 2>/dev/null; then
      echo -e "  ${GREEN}[✓]${NC} $(t app.sub2api.status.nginx_running)"
    else
      echo -e "  ${RED}[✗]${NC} $(t app.sub2api.status.nginx_stopped)"
    fi
    local nginx_conf="/etc/nginx/sites-available/sub2api"
    local nginx_link="/etc/nginx/sites-enabled/sub2api"
    if [[ -f "$nginx_conf" ]]; then
      echo -e "  ${GREEN}[✓]${NC} $(t app.sub2api.status.nginx_config_exists "$nginx_conf")"
      local proxy_pass
      proxy_pass=$(grep -oE 'proxy_pass[[:space:]]+[^;]+' "$nginx_conf" 2>/dev/null | awk '{print $2}' | head -1 || echo "N/A")
      echo -e "       $(t app.sub2api.status.proxy_target "$proxy_pass")"
      local sn
      sn=$(grep -oE 'server_name[[:space:]]+[^;]+' "$nginx_conf" 2>/dev/null | awk '{$1=""; print $0}' | tr -d ' ' | head -1 || echo "_")
      echo -e "       $(t app.sub2api.status.server_name "$sn")"
    else
      echo -e "  ${YELLOW}[!]${NC} $(t app.sub2api.status.nginx_config_missing "$nginx_conf")"
    fi
    if [[ -L "$nginx_link" ]]; then
      echo -e "  ${GREEN}[✓]${NC} $(t app.sub2api.status.nginx_link_active)"
    else
      echo -e "  ${YELLOW}[!]${NC} $(t app.sub2api.status.nginx_link_missing "$nginx_conf" "$nginx_link")"
    fi
    if nginx -t 2>/dev/null; then
      echo -e "  ${GREEN}[✓]${NC} $(t app.sub2api.status.nginx_test_ok)"
    else
      echo -e "  ${RED}[✗]${NC} $(t app.sub2api.status.nginx_test_failed)"
    fi
  else
    echo -e "  ${YELLOW}[!]${NC} $(t app.sub2api.status.nginx_missing)"
  fi
  echo -e "\n${BOLD}[$(t app.sub2api.status.dependencies)]${NC}"
  for _svc_port in "PostgreSQL:5432" "Redis:6379"; do
    local _name="${_svc_port%%:*}" _port="${_svc_port##*:}"
    if (echo >/dev/tcp/127.0.0.1/"${_port}") 2>/dev/null; then
      echo -e "  ${GREEN}[✓]${NC} $(t app.sub2api.status.port_reachable "$_name" "$_port")"
    else
      echo -e "  ${YELLOW}[!]${NC} $(t app.sub2api.status.port_unreachable "$_name" "$_port")"
    fi
  done
  if [[ -n "${PG_DSN:-}" ]]; then
    local _dsn_masked
    if [[ "$PG_DSN" =~ ^([^:]+)://([^:@]+):([^@]*)@(.*)$ ]]; then
      _dsn_masked="${BASH_REMATCH[1]}://${BASH_REMATCH[2]}:***@${BASH_REMATCH[4]}"
    else
      _dsn_masked="$PG_DSN"
    fi
    echo -e "  $(t app.sub2api.status.pg_dsn_masked "$_dsn_masked")"
  else
    echo -e "  ${YELLOW}[!]${NC} $(t app.sub2api.status.pg_dsn_missing)"
  fi
  echo -e "\n${BOLD}[$(t app.sub2api.status.directories)]${NC}"
  for _d in "$INSTALL_DIR" "$DATA_DIR" "$LOG_DIR" "$CONFIG_DIR"; do
    if [[ -d "$_d" ]]; then
      local _sz; _sz=$(du -sh "$_d" 2>/dev/null | awk '{print $1}' || t app.sub2api.status.unknown)
      echo -e "  ${GREEN}[✓]${NC} ${_d} (${_sz})"
    else
      echo -e "  ${YELLOW}[!]${NC} $(t app.sub2api.status.dir_missing "$_d")"
    fi
  done
  echo -e "\n${BOLD}[$(t app.sub2api.status.backup_info)]${NC}"
  if [[ -d "$BACKUP_DIR" ]]; then
    local bak_count bak_total_size
    bak_count=$(find "$BACKUP_DIR" -maxdepth 1 \
      \( -name "sub2api_*.tar.gz" -o -name "sub2api_db_*.sql.gz" \
         -o -name "sub2api_conf_*.tar.gz" \) \
      2>/dev/null | wc -l)
    bak_total_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | awk '{print $1}' || t app.sub2api.status.unknown)
    echo -e "  $(t app.sub2api.status.backup_dir "$BACKUP_DIR" "$bak_total_size" "$bak_count")"
    local _cnt=0
    local _bak_entry
    while IFS= read -r -d '' _bak_entry; do
      f="${_bak_entry#* }"
      local _sz; _sz=$(du -sh "$f" 2>/dev/null | cut -f1 || echo "?")
      echo -e "  $((_cnt+1)). $(basename "$f")（${_sz}）"
      _cnt=$(( _cnt + 1 ))
    done < <(find "$BACKUP_DIR" -maxdepth 1 \
      \( -name "sub2api_*.tar.gz" -o -name "sub2api_db_*.sql.gz" \) \
      -printf '%T@ %p\0' 2>/dev/null | sort -z -rn | head -z -n 5)
    if [[ $_cnt -eq 0 ]]; then
      echo -e "  ${YELLOW}[!]${NC} $(t app.sub2api.status.no_backup_files)"
    fi
  else
    echo -e "  ${YELLOW}[!]${NC} $(t app.sub2api.status.backup_missing "$BACKUP_DIR")"
  fi
  echo -e "\n${BOLD}[$(t app.sub2api.status.disk)]${NC}"
  local disk_fmt
  disk_fmt="$(t app.sub2api.status.disk_usage)"
  df -h "$INSTALL_DIR" 2>/dev/null \
    | awk -v fmt="$disk_fmt" 'NR==2{printf "  " fmt "\n", $6,$3,$2,$5}' || true
  echo -e "\n${BOLD}[$(t app.sub2api.status.http_health "$PORT")]${NC}"
  local HTTP_CODE
  HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}" --max-time 5 \
    "http://127.0.0.1:${PORT}/" 2>/dev/null || echo "000")
  if [[ "$HTTP_CODE" =~ ^(200|301|302)$ ]]; then
    echo -e "  ${GREEN}[✓]${NC} $(t app.sub2api.status.local_ok "$HTTP_CODE")"
  else
    echo -e "  ${YELLOW}[!]${NC} $(t app.sub2api.status.local_warn "$HTTP_CODE")"
  fi
  echo -e "\n${BOLD}[$(t app.sub2api.status.firewall "$PORT")]${NC}"
  if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
    local ufw_rule
    ufw_rule=$(ufw status 2>/dev/null | grep -E "(^|[[:space:]])${PORT}/tcp([[:space:]]|$)" || true)
    if [[ -n "$ufw_rule" ]]; then
      echo -e "  ${GREEN}[✓]${NC} $(t app.sub2api.status.ufw_allowed "$PORT")"
    else
      echo -e "  ${YELLOW}[!]${NC} $(t app.sub2api.status.ufw_missing "$PORT")"
    fi
  elif command -v iptables &>/dev/null; then
    if iptables -C INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null; then
      echo -e "  ${GREEN}[✓]${NC} $(t app.sub2api.status.iptables_allowed "$PORT")"
    else
      echo -e "  ${YELLOW}[!]${NC} $(t app.sub2api.status.iptables_missing "$PORT")"
    fi
  else
    echo -e "  ${YELLOW}[!]${NC} $(t app.sub2api.status.no_firewall)"
  fi
  echo ""
}
do_uninstall() {
  show_banner
  preflight_check "uninstall"
  app_load_config _SUB2API_DERIVE_PATHS
  acquire_lock
  [[ -z "${INSTALL_DIR:-}" ]] && error "$(t app.sub2api.error.install_dir_empty "$CONF_FILE")"
  [[ -z "${DATA_DIR:-}"    ]] && error "$(t app.sub2api.error.data_dir_empty)"
  [[ -z "${BACKUP_DIR:-}"  ]] && error "$(t app.sub2api.error.backup_dir_empty)"
  [[ "${INSTALL_DIR}" == "/" ]] && error "$(t app.sub2api.error.install_dir_root)"
  [[ "${DATA_DIR}"    == "/" ]] && error "$(t app.sub2api.error.data_dir_root)"
  [[ "${BACKUP_DIR}"  == "/" ]] && error "$(t app.sub2api.error.backup_dir_root)"
  step "$(t app.sub2api.step.uninstall)"
  echo -e "${RED}${BOLD}"
  echo "  $(t app.sub2api.uninstall.removes)"
  echo "     - $(t app.sub2api.uninstall.binary "$INSTALL_DIR")"
  echo "     - $(t app.sub2api.uninstall.systemd "$SERVICE_NAME")"
  echo "     - $(t app.sub2api.uninstall.nginx_config)"
  echo "     - $(t app.sub2api.uninstall.nginx_link)"
  echo "     - $(t app.sub2api.uninstall.logrotate)"
  echo "     - $(t app.sub2api.uninstall.cron)"
  echo "     - $(t app.sub2api.uninstall.backup_script)"
  echo "     - $(t app.sub2api.uninstall.deploy_config "$CONF_FILE")"
  echo ""
  echo "  $(t app.sub2api.uninstall.keep_database)"
  echo "  $(t app.sub2api.uninstall.keep_dirs "$DATA_DIR" "$CONFIG_DIR")"
  echo -e "${NC}"
  local _c
  if deploy_assume_yes; then
    _c="YES"
  else
    prompt "$(t app.sub2api.prompt.continue)"
    read -r _c
  fi
  [[ "$_c" != "YES" ]] && { info "$(t app.sub2api.info.cancelled)"; exit 0; }
  local DELETE_DATA=false
  if deploy_assume_yes; then
    deploy_env_truthy DEPLOY_DELETE_DATA && DELETE_DATA=true
  else
    prompt "$(t app.sub2api.prompt.delete_data "$DATA_DIR")"
    local _del_data; read -r _del_data
    [[ "${_del_data,,}" == "y" ]] && DELETE_DATA=true
  fi
  local DELETE_CONF=false
  if deploy_assume_yes; then
    deploy_env_truthy DEPLOY_DELETE_CONFIG && DELETE_CONF=true
  else
    prompt "$(t app.sub2api.prompt.delete_config "$CONFIG_DIR")"
    local _del_conf; read -r _del_conf
    [[ "${_del_conf,,}" == "y" ]] && DELETE_CONF=true
  fi
  local DELETE_BACKUP=false
  if deploy_assume_yes; then
    deploy_env_truthy DEPLOY_DELETE_BACKUP && DELETE_BACKUP=true
  else
    prompt "$(t app.sub2api.prompt.delete_backup "$BACKUP_DIR")"
    local _del_bak; read -r _del_bak
    [[ "${_del_bak,,}" == "y" ]] && DELETE_BACKUP=true
  fi
  info "$(t app.sub2api.info.stop_disable "$SERVICE_NAME")"
  if ! systemctl stop "$SERVICE_NAME" 2>/dev/null; then
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
      error "$(t app.sub2api.error.uninstall_stop_failed "$SERVICE_NAME" "$SERVICE_NAME")"
    fi
    warn "$(t app.sub2api.warn.uninstall_stop_failed "$SERVICE_NAME" "$SERVICE_NAME")"
  fi
  if ! systemctl disable "$SERVICE_NAME" 2>/dev/null; then
    warn "$(t app.sub2api.warn.uninstall_disable_failed "$SERVICE_NAME" "$SERVICE_NAME")"
  fi
  _sub2api_remove_file_or_error "/etc/systemd/system/${SERVICE_NAME}.service" "SUB2API_SERVICE_FILE"
  if ! systemctl daemon-reload; then
    error "$(t app.sub2api.error.systemd_reload "$SERVICE_NAME")"
  fi
  success "$(t app.sub2api.success.removed_systemd)"
  _sub2api_require_safe_bin_path
  _sub2api_remove_file_or_error "$BIN_PATH" "BIN_PATH"
  require_safe_path "INSTALL_DIR" "$INSTALL_DIR"
  local _cleanup_path
  while IFS= read -r -d '' _cleanup_path; do
    if ! rm -f "$_cleanup_path"; then
      warn "$(t app.sub2api.warn.cleanup_old_binary_failed "$_cleanup_path")"
    fi
  done < <(find "$INSTALL_DIR" -maxdepth 1 \( -name "sub2api.bak.*" -o -name "sub2api.tmp.*" -o -name "sub2api-release.*.tar.gz" \) -type f -print0 2>/dev/null)
  while IFS= read -r -d '' _cleanup_path; do
    if ! rm -rf "$_cleanup_path"; then
      warn "$(t app.sub2api.warn.cleanup_old_binary_failed "$_cleanup_path")"
    fi
  done < <(find "$INSTALL_DIR" -maxdepth 1 -name "sub2api-extract.*" -type d -print0 2>/dev/null)
  success "$(t app.sub2api.success.removed_binary)"
  _sub2api_remove_file_or_error "/etc/nginx/sites-enabled/sub2api" "SUB2API_NGINX_LINK"
  _sub2api_remove_file_or_error "/etc/nginx/sites-available/sub2api" "SUB2API_NGINX_CONF"
  if command -v nginx &>/dev/null; then
    if nginx -t >/dev/null 2>&1; then
      if systemctl reload nginx >/dev/null 2>&1; then
        success "$(t app.sub2api.success.removed_nginx_reload)"
      else
        nginx -t >&2 || true
        warn "$(t app.sub2api.warn.uninstall_nginx_reload_failed)"
        success "$(t app.sub2api.success.removed_nginx)"
      fi
    else
      nginx -t >&2 || true
      warn "$(t app.sub2api.warn.uninstall_nginx_test_failed)"
      success "$(t app.sub2api.success.removed_nginx)"
    fi
  else
    success "$(t app.sub2api.success.removed_nginx)"
  fi
  _sub2api_remove_file_or_error "/etc/cron.d/sub2api-backup" "SUB2API_CRON_FILE"
  _sub2api_remove_file_or_error "/usr/local/bin/sub2api-backup" "SUB2API_BACKUP_SCRIPT"
  _sub2api_remove_file_or_error "/etc/logrotate.d/sub2api" "SUB2API_LOGROTATE_FILE"
  success "$(t app.sub2api.success.removed_scheduled)"
  _sub2api_remove_file_or_error "$CONF_FILE" "CONF_FILE"
  success "$(t app.sub2api.success.removed_config)"
  if [[ -n "${LOG_DIR:-}" && "$LOG_DIR" != "." && "$LOG_DIR" != "/" && -d "$LOG_DIR" ]]; then
    _sub2api_remove_dir_or_error "$LOG_DIR" "LOG_DIR" "$(t app.sub2api.success.deleted_log "$LOG_DIR")"
  else
    warn "$(t app.sub2api.warn.log_path "${LOG_DIR:-$(t app.sub2api.status.unset)}")"
  fi
  if $DELETE_DATA; then
    _sub2api_remove_dir_or_error "$DATA_DIR" "DATA_DIR" "$(t app.sub2api.success.deleted_data "$DATA_DIR")"
    if [[ -d "$INSTALL_DIR" ]] && [[ -z "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]]; then
      if ! safe_rm_dir "$INSTALL_DIR" "INSTALL_DIR"; then
        warn "$(t app.sub2api.warn.cleanup_install_failed "$INSTALL_DIR")"
      else
        success "$(t app.sub2api.success.cleaned_install "$INSTALL_DIR")"
      fi
    fi
  else
    info "$(t app.sub2api.info.kept_data "$DATA_DIR")"
  fi
  if $DELETE_CONF; then
    _sub2api_remove_dir_or_error "$CONFIG_DIR" "CONFIG_DIR" "$(t app.sub2api.success.deleted_config "$CONFIG_DIR")"
  else
    info "$(t app.sub2api.info.kept_config "$CONFIG_DIR")"
  fi
  if $DELETE_BACKUP; then
    _sub2api_remove_dir_or_error "$BACKUP_DIR" "BACKUP_DIR" "$(t app.sub2api.success.deleted_backup "$BACKUP_DIR")"
  else
    info "$(t app.sub2api.info.kept_backup "$BACKUP_DIR")"
  fi
  if $DELETE_DATA && $DELETE_CONF && id "$SERVICE_USER" &>/dev/null; then
    if userdel "$SERVICE_USER" 2>/dev/null; then
      success "$(t app.sub2api.success.deleted_user "$SERVICE_USER")"
    else
      warn "$(t app.sub2api.warn.delete_user "$SERVICE_USER")"
    fi
  fi
  echo ""
  echo -e "${BOLD}${GREEN}  $(t app.sub2api.success.uninstalled)${NC}"
  echo ""
  echo -e "  ${YELLOW}[hint]${NC} $(t app.sub2api.hint.database_kept)"
  echo -e "  ${YELLOW}[hint]${NC} $(t app.sub2api.hint.clean_database)"
  echo -e "    ${CYAN}sudo -u postgres psql -c 'DROP DATABASE ${PG_DB};'${NC}"
  echo -e "    ${CYAN}sudo -u postgres psql -c 'DROP USER ${PG_USER};'${NC}"
  echo ""
}

do_verify() {
  show_banner
  require_root "verify"
  app_load_config _SUB2API_DERIVE_PATHS
  step "$(t backup.verify.step)"
  require_safe_path "BACKUP_DIR" "$BACKUP_DIR"
  app_verify_latest_backup "$BACKUP_DIR" 'sub2api_*.tar.gz' 'sub2api_db_*.sql.gz'
}

# Restore from the three artifacts do_backup/cron produce: the data tar
# (sub2api_data_*.tar.gz), the optional config tar (sub2api_conf_*.tar.gz),
# and the optional pg_dump (sub2api_db_*.sql.gz). The service is stopped
# while data and config are swapped atomically; the database restore pipes
# the dump back through psql. Each stage aside-copies its target so a failed
# extraction or a service that will not restart rolls back cleanly.
do_restore() {
  show_banner
  require_root "restore"
  app_load_config _SUB2API_DERIVE_PATHS
  acquire_lock
  step "$(t backup.restore.step)"
  require_safe_path "BACKUP_DIR" "$BACKUP_DIR"
  require_safe_path "DATA_DIR" "$DATA_DIR"
  require_safe_path "CONFIG_DIR" "$CONFIG_DIR"
  [[ -d "$BACKUP_DIR" ]] || error "$(t backup.restore.no_backups "$BACKUP_DIR")"
  local data_archive conf_archive="" db_archive=""
  data_archive="${SUB2API_RESTORE_ARCHIVE:-}"
  if [[ -n "$data_archive" ]]; then
    [[ "$data_archive" == "$BACKUP_DIR"/sub2api_data_*.tar.gz && -f "$data_archive" ]] \
      || data_archive="$(backup_latest_archive "$BACKUP_DIR" 'sub2api_data_*.tar.gz' || true)"
  else
    data_archive="$(backup_latest_archive "$BACKUP_DIR" 'sub2api_data_*.tar.gz' || true)"
  fi
  conf_archive="$(backup_latest_archive "$BACKUP_DIR" 'sub2api_conf_*.tar.gz' || true)"
  db_archive="$(backup_latest_archive "$BACKUP_DIR" 'sub2api_db_*.sql.gz' || true)"
  [[ -n "$data_archive" ]] \
    || error "$(t backup.restore.no_backups "$BACKUP_DIR")"

  local member_list
  if ! member_list="$(tar -tzf "$data_archive" 2>/dev/null)"; then
    error "$(t backup.restore.invalid_archive "$data_archive")"
  fi
  local member
  while IFS= read -r member; do
    case "$member" in
      ""|/*|*'/../'*|../*|*'/..'|..|*"\\"*)
        error "$(t backup.restore.invalid_archive "$(basename "$data_archive")")"
        ;;
    esac
  done <<< "$member_list"
  if [[ -n "$conf_archive" ]]; then
    if ! member_list="$(tar -tzf "$conf_archive" 2>/dev/null)"; then
      error "$(t backup.restore.invalid_archive "$conf_archive")"
    fi
    while IFS= read -r member; do
      case "$member" in
        ""|/*|*'/../'*|../*|*'/..'|..|*"\\"*)
          error "$(t backup.restore.invalid_archive "$(basename "$conf_archive")")"
          ;;
      esac
    done <<< "$member_list"
  fi
  info "$(t backup.restore.using "$data_archive")"

  systemctl stop "$SERVICE_NAME" \
    || error "$(t backup.restore.stop_failed "$SERVICE_NAME")"
  # ── data directory: atomic swap with aside copy, shared helper semantics.
  if ! backup_restore_data_dir "$DATA_DIR" "" "$data_archive"; then
    : # helper already restarted nothing; keep going to config/db stages
  fi
  # The helper starts $2 (empty here) — systemctl start "" would fail, so
  # guard by restoring the stopped state ourselves below.

  # ── config directory: aside + swap when a config archive exists.
  if [[ -n "$conf_archive" ]]; then
    local aside_dir stamp extract_ok=true
    stamp="$(date +%Y%m%d%H%M%S)"
    if ! aside_dir=$(mktemp -d "${BACKUP_DIR}/.restore-aside.XXXXXX"); then
      systemctl start "$SERVICE_NAME" || true
      error "$(t backup.restore.invalid_archive "$conf_archive")"
    fi
    if [[ -d "$CONFIG_DIR" ]]; then
      mv "$CONFIG_DIR" "${aside_dir}/conf.restore.${stamp}" || true
    fi
    mkdir -p "$(dirname "$CONFIG_DIR")"
    tar -xzf "$conf_archive" -C "$(dirname "$CONFIG_DIR")" >&2 || extract_ok=false
    if [[ "$extract_ok" != "true" ]]; then
      rm -rf "$CONFIG_DIR"
      [[ -d "${aside_dir}/conf.restore.${stamp}" ]] && mv "${aside_dir}/conf.restore.${stamp}" "$CONFIG_DIR"
      rm -rf "$aside_dir"
      systemctl start "$SERVICE_NAME" || true
      error "$(t backup.restore.invalid_archive "$conf_archive")"
    fi
    rm -rf "$aside_dir"
  fi

  # ── database: pipe the newest dump back through psql when one exists.
  if [[ -n "$db_archive" ]]; then
    if command -v psql >/dev/null 2>&1 && [[ -n "${PG_DSN:-}" ]]; then
      if ! gunzip -c "$db_archive" | psql "$PG_DSN" >&2; then
        warn "$(t binary_app.warn.rollback_start_failed "$SERVICE_NAME")"
      fi
    else
      warn "$(t binary_app.error.backup_failed)"
    fi
  fi

  systemctl start "$SERVICE_NAME" \
    || error "$(t binary_app.error.install_start_failed "$SERVICE_NAME" "$SERVICE_NAME")"
  wait_for_service "$SERVICE_NAME" 20 || true
  success "$(t backup.restore.restored "$(basename "$data_archive")")"
}
