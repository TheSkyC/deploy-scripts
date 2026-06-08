#!/bin/bash
set -euo pipefail
umask 077
PORT=8082
INSTALL_DIR="/opt/sub2api"
DATA_DIR="/opt/sub2api/data"
LOG_DIR="/opt/sub2api/logs"
CONFIG_DIR="/etc/sub2api"
SERVICE_NAME="sub2api"
SERVICE_USER="sub2api"
GITHUB_REPO="Wei-Shaw/sub2api"
BACKUP_DIR="/opt/sub2api-backups"
BACKUP_KEEP_DAYS=30
SUB2API_DOMAIN=""
PG_USER="sub2api"
PG_PASS=""
PG_DB="sub2api"
PG_DSN=""
BIN_PATH="${INSTALL_DIR}/sub2api"
CONF_FILE="/etc/sub2api-deploy.conf"
CONFIG_KEYS=(
  PORT INSTALL_DIR DATA_DIR LOG_DIR CONFIG_DIR SERVICE_NAME SERVICE_USER
  GITHUB_REPO BACKUP_DIR BACKUP_KEEP_DAYS PG_USER PG_PASS PG_DB PG_DSN
  SUB2API_DOMAIN INSTALLED_VERSION
)
preflight_check() {
  [[ $EUID -ne 0 ]] && error "$(t error.root_required "$0" "${1:-}")"
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
}
LOCK_FILE="/var/lock/sub2api-deploy.lock"
check_connectivity() {
  check_connectivity_urls \
    "https://api.github.com" \
    "https://github.com" \
    "https://objects.githubusercontent.com" && return 0
  error "$(t app.sub2api.error.github_unreachable)"
}
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
save_config() {
  write_config_file "$CONF_FILE" "${CONFIG_KEYS[@]}"
  success "$(t config.saved "$CONF_FILE")"
}
load_config() {
  [[ -f "$CONF_FILE" ]] || return 0
  load_config_file "$CONF_FILE" "${CONFIG_KEYS[@]}" || return 0
  BIN_PATH="${INSTALL_DIR}/sub2api"
  success "$(t config.loaded "$CONF_FILE")"
}
get_latest_release() {
  local json tag
  json=$(curl -fsSL --max-time 15 \
    "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" 2>/dev/null) \
    || { warn "$(t app.sub2api.warn.github_api)"; echo ""; return; }
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
  local tmp_sum; tmp_sum=$(mktemp)
  if ! curl -fsSL --max-time 15 -o "$tmp_sum" "$checksum_url" 2>/dev/null; then
    warn "$(t app.sub2api.warn.checksum_download)"
    rm -f "$tmp_sum"
    return 0
  fi
  local expected_hash
  expected_hash=$(grep " ${expected_name}$" "$tmp_sum" 2>/dev/null | awk '{print $1}' || true)
  rm -f "$tmp_sum"
  if [[ -z "$expected_hash" ]]; then
    warn "$(t app.sub2api.warn.checksum_missing "$expected_name")"
    return 0
  fi
  local actual_hash
  if command -v sha256sum &>/dev/null; then
    actual_hash=$(sha256sum "$archive" | awk '{print $1}')
  elif command -v shasum &>/dev/null; then
    actual_hash=$(shasum -a 256 "$archive" | awk '{print $1}')
  else
    warn "$(t app.sub2api.warn.sha_tool_missing)"
    return 0
  fi
  if [[ "$actual_hash" != "$expected_hash" ]]; then
    error "$(t app.sub2api.error.sha_failed "$expected_hash" "$actual_hash")"
  fi
  success "$(t app.sub2api.success.sha_ok "${actual_hash:0:16}")"
}
extract_and_verify() {
  local archive="$1" dest_dir="$2"
  local tmp_extract; tmp_extract=$(mktemp -d "${dest_dir}/sub2api-extract.XXXXXX")
  if ! tar -xzf "$archive" -C "$tmp_extract" 2>&1; then
    rm -rf "$tmp_extract"
    error "$(t app.sub2api.error.tar_extract)"
  fi
  local bin_path
  bin_path=$(find "$tmp_extract" -maxdepth 2 -name "sub2api" -type f 2>/dev/null | head -1 || true)
  if [[ -z "$bin_path" ]]; then
    rm -rf "$tmp_extract"
    error "$(t app.sub2api.error.archive_missing_binary)"
  fi
  local magic
  magic=$(dd if="$bin_path" bs=1 count=4 2>/dev/null | od -An -tx1 | tr -d ' \n' 2>/dev/null || true)
  if [[ "$magic" != "7f454c46" ]]; then
    rm -rf "$tmp_extract"
    error "$(t app.sub2api.error.not_elf "${magic:-read failed}")"
  fi
  local emachine
  emachine=$(dd if="$bin_path" bs=1 skip=18 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n' 2>/dev/null || true)
  if [[ "$emachine" != "$ELF_MACHINE" ]]; then
    rm -rf "$tmp_extract"
    error "$(t app.sub2api.error.elf_machine "$emachine" "$ELF_MACHINE" "$BIN_ARCH")"
  fi
  local size; size=$(wc -c < "$bin_path")
  local size_mb=$(( size / 1024 / 1024 ))
  success "$(t app.sub2api.success.elf_ok "$BIN_ARCH" "$size_mb")"
  local tmp_bin; tmp_bin=$(mktemp "${dest_dir}/sub2api.tmp.XXXXXX")
  if ! mv "$bin_path" "$tmp_bin"; then
    rm -f "$tmp_bin"
    rm -rf "$tmp_extract"
    error "$(t app.sub2api.error.archive_missing_binary)"
  fi
  rm -rf "$tmp_extract"
  echo "$tmp_bin"
}
_install_binary_candidate() {
  local tmp_bin="$1"
  local backup_path="${2:-}"
  if [[ -n "$backup_path" && -f "$BIN_PATH" ]]; then
    if ! mv "$BIN_PATH" "$backup_path"; then
      rm -f "$tmp_bin"
      return 1
    fi
  fi
  if ! mv "$tmp_bin" "$BIN_PATH"; then
    rm -f "$tmp_bin"
    [[ -n "$backup_path" && -f "$backup_path" && ! -e "$BIN_PATH" ]] \
      && mv "$backup_path" "$BIN_PATH" 2>/dev/null || true
    return 1
  fi
  if ! chmod +x "$BIN_PATH" || ! chown "${SERVICE_USER}:${SERVICE_USER}" "$BIN_PATH"; then
    rm -f "$BIN_PATH"
    [[ -n "$backup_path" && -f "$backup_path" ]] \
      && mv "$backup_path" "$BIN_PATH" 2>/dev/null || true
    return 1
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
  else
    warn "$(t app.sub2api.warn.http_health "$HTTP_CODE")"
    warn "$(t app.sub2api.warn.debug_command "$SERVICE_NAME")"
    warn "$(t app.sub2api.warn.setup_wizard "$PORT")"
  fi
}
_install_base_deps() {
  info "$(t app.sub2api.info.install_base_deps)"
  if [[ "$PKG_MANAGER" == "apt" ]]; then
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
      curl ca-certificates gnupg lsb-release
  elif [[ "$PKG_MANAGER" == "dnf" ]]; then
    dnf install -y -q curl ca-certificates
  elif [[ "$PKG_MANAGER" == "yum" ]]; then
    yum install -y -q curl ca-certificates
  fi
  success "$(t app.sub2api.success.base_deps)"
}
_install_postgres() {
  if command -v psql &>/dev/null; then
    local pg_ver
    pg_ver=$(psql --version 2>/dev/null | grep -oE '[0-9]+' | head -1 || echo "0")
    if [[ "$pg_ver" -ge 15 ]]; then
      success "$(t app.sub2api.success.postgres_exists "$pg_ver")"
      systemctl enable postgresql 2>/dev/null || \
        systemctl enable "postgresql-${pg_ver}" 2>/dev/null || true
      systemctl start  postgresql 2>/dev/null || \
        systemctl start  "postgresql-${pg_ver}" 2>/dev/null || true
      return 0
    fi
    warn "$(t app.sub2api.warn.postgres_old "$pg_ver")"
  fi
  if [[ "$PKG_MANAGER" == "apt" ]]; then
    info "$(t app.sub2api.info.postgres_apt_source)"
    install -d /usr/share/postgresql-common/pgdg
    if ! curl -fsSL --max-time 30 \
        -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
        "https://www.postgresql.org/media/keys/ACCC4CF8.asc"; then
      error "$(t app.sub2api.error.postgres_key)"
    fi
    local codename
    codename="$(_apt_codename)"
    mkdir -p /etc/apt/sources.list.d
    local pg_source_list="/etc/apt/sources.list.d/pgdg.list"
    local pg_source_tmp
    pg_source_tmp=$(mktemp "${pg_source_list}.XXXXXX")
    if ! printf '%s\n' "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] https://apt.postgresql.org/pub/repos/apt ${codename}-pgdg main" > "$pg_source_tmp" \
        || ! chmod 644 "$pg_source_tmp" \
        || ! chown root:root "$pg_source_tmp" \
        || ! mv "$pg_source_tmp" "$pg_source_list"; then
      rm -f "$pg_source_tmp"
      error "$(t app.sub2api.error.postgres_source)"
    fi
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-15 postgresql-client-15
    systemctl enable --now postgresql
    success "$(t app.sub2api.success.postgres15)"
  elif [[ "$PKG_MANAGER" == "dnf" || "$PKG_MANAGER" == "yum" ]]; then
    info "$(t app.sub2api.info.postgres_rpm_source)"
    local el_ver
    el_ver=$(rpm -E '%{rhel}' 2>/dev/null || echo "8")
    local pgdg_rpm="https://download.postgresql.org/pub/repos/yum/reporpms/EL-${el_ver}-${ARCH}/pgdg-redhat-repo-latest.noarch.rpm"
    if [[ "$PKG_MANAGER" == "dnf" ]]; then
      dnf install -y "$pgdg_rpm" 2>/dev/null || true
      dnf -qy module disable postgresql 2>/dev/null || true
      dnf install -y postgresql15-server postgresql15-contrib
    else
      yum install -y "$pgdg_rpm" 2>/dev/null || true
      yum install -y postgresql15-server postgresql15-contrib
    fi
    /usr/pgsql-15/bin/postgresql-15-setup initdb 2>/dev/null || true
    systemctl enable --now postgresql-15
    success "$(t app.sub2api.success.postgres15)"
  fi
}
_install_redis() {
  if command -v redis-server &>/dev/null; then
    local redis_ver
    redis_ver=$(redis-server --version 2>/dev/null \
      | grep -oE 'v=[0-9]+' | grep -oE '[0-9]+' || echo "0")
    if [[ "$redis_ver" -ge 7 ]]; then
      success "$(t app.sub2api.success.redis_exists "$redis_ver")"
      systemctl enable --now redis-server 2>/dev/null || \
        systemctl enable --now redis 2>/dev/null || true
      return 0
    fi
    warn "$(t app.sub2api.warn.redis_old "$redis_ver")"
  fi
  if [[ "$PKG_MANAGER" == "apt" ]]; then
    info "$(t app.sub2api.info.redis_apt_source)"
    local redis_keyring redis_key_tmp
    redis_keyring="/usr/share/keyrings/redis-archive-keyring.gpg"
    redis_key_tmp="$(mktemp "${redis_keyring}.tmp.XXXXXX")"
    if ! curl -fsSL --max-time 30 "https://packages.redis.io/gpg" \
        | gpg --batch --yes --dearmor -o "$redis_key_tmp"; then
      rm -f "$redis_key_tmp"
      error "$(t app.sub2api.error.redis_key)"
    fi
    chmod 644 "$redis_key_tmp"
    mv "$redis_key_tmp" "$redis_keyring"
    local codename
    codename="$(_apt_codename)"
    mkdir -p /etc/apt/sources.list.d
    local redis_source_list="/etc/apt/sources.list.d/redis.list"
    local redis_source_tmp
    redis_source_tmp=$(mktemp "${redis_source_list}.XXXXXX")
    if ! printf '%s\n' "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] https://packages.redis.io/deb ${codename} main" > "$redis_source_tmp" \
        || ! chmod 644 "$redis_source_tmp" \
        || ! chown root:root "$redis_source_tmp" \
        || ! mv "$redis_source_tmp" "$redis_source_list"; then
      rm -f "$redis_source_tmp"
      error "$(t app.sub2api.error.redis_source)"
    fi
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y redis
    systemctl enable --now redis-server
    success "$(t app.sub2api.success.redis7)"
  elif [[ "$PKG_MANAGER" == "dnf" ]]; then
    dnf install -y redis
    systemctl enable --now redis
    success "$(t app.sub2api.success.redis)"
  elif [[ "$PKG_MANAGER" == "yum" ]]; then
    yum install -y redis
    systemctl enable --now redis
    success "$(t app.sub2api.success.redis)"
  fi
}
_setup_postgres() {
  if ! systemctl is-active --quiet postgresql 2>/dev/null && \
     ! systemctl is-active --quiet postgresql-15 2>/dev/null; then
    warn "$(t app.sub2api.warn.postgres_not_running)"
    systemctl start postgresql 2>/dev/null || \
      systemctl start postgresql-15 2>/dev/null || \
      error "$(t app.sub2api.error.postgres_start)"
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
    sudo -u postgres psql -c \
      "ALTER USER ${PG_USER} WITH PASSWORD '${PG_PASS}';" > /dev/null
  else
    sudo -u postgres psql -c \
      "CREATE USER ${PG_USER} WITH PASSWORD '${PG_PASS}';" > /dev/null
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
  PG_DSN="postgresql://${PG_USER}:${PG_PASS}@localhost:5432/${PG_DB}?sslmode=disable"
  success "$(t app.sub2api.success.pg_dsn)"
}
_install_nginx() {
  if command -v nginx &>/dev/null; then
    info "$(t app.sub2api.info.nginx_exists)"
  else
    info "$(t app.sub2api.info.install_nginx)"
    if [[ "$PKG_MANAGER" == "apt" ]]; then
      DEBIAN_FRONTEND=noninteractive apt-get install -y nginx
    elif [[ "$PKG_MANAGER" == "dnf" ]]; then
      dnf install -y nginx
    elif [[ "$PKG_MANAGER" == "yum" ]]; then
      yum install -y nginx
    fi
    success "$(t app.sub2api.success.nginx_installed)"
  fi
  systemctl enable nginx
  systemctl start nginx 2>/dev/null || true
}
_write_nginx_config() {
  local server_name_line
  if [[ -n "${SUB2API_DOMAIN:-}" ]]; then
    server_name_line="    server_name ${SUB2API_DOMAIN};"
  else
    server_name_line="    server_name _;"
  fi
  mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled
  local nginx_conf="/etc/nginx/sites-available/sub2api"
  local nginx_tmp
  nginx_tmp=$(mktemp "${nginx_conf}.XXXXXX")
  if ! cat > "$nginx_tmp" << NGINX
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
  then
    rm -f "$nginx_tmp"
    error "$(t app.sub2api.error.nginx_config_write)"
  fi
  if ! chmod 644 "$nginx_tmp" \
      || ! chown root:root "$nginx_tmp" \
      || ! mv "$nginx_tmp" "$nginx_conf"; then
    rm -f "$nginx_tmp"
    error "$(t app.sub2api.error.nginx_config_write)"
  fi
  if [[ ! -L /etc/nginx/sites-enabled/sub2api ]]; then
    ln -s "$nginx_conf" /etc/nginx/sites-enabled/sub2api
  fi
  if [[ "$PKG_MANAGER" != "apt" ]]; then
    if ! grep -q "sites-enabled" /etc/nginx/nginx.conf 2>/dev/null; then
      sed -i '/^http[[:space:]]*{/a\    include /etc/nginx/sites-enabled/*;' \
        /etc/nginx/nginx.conf 2>/dev/null || \
        warn "$(t app.sub2api.warn.nginx_include)"
    fi
  fi
  if nginx -t 2>/dev/null; then
    systemctl reload nginx
    if [[ -n "${SUB2API_DOMAIN:-}" ]]; then
      success "$(t app.sub2api.success.nginx_domain "$SUB2API_DOMAIN" "$PORT")"
    else
      success "$(t app.sub2api.success.nginx_fallback "$PORT")"
    fi
  else
    warn "$(t app.sub2api.warn.nginx_test_failed)"
    nginx -t >&2 2>/dev/null || true
  fi
}
_write_systemd_unit() {
  local unit_path="/etc/systemd/system/${SERVICE_NAME}.service"
  local unit_tmp
  unit_tmp=$(mktemp "${unit_path}.XXXXXX")
  if ! cat > "$unit_tmp" << EOF
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
Environment="SERVER_HOST=0.0.0.0"
Environment="SERVER_PORT=${PORT}"
Environment="TZ=Asia/Shanghai"
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
    rm -f "$unit_tmp"
    error "$(t app.sub2api.error.systemd_unit "$SERVICE_NAME")"
  fi
  if ! chmod 644 "$unit_tmp" \
      || ! chown root:root "$unit_tmp" \
      || ! mv "$unit_tmp" "$unit_path"; then
    rm -f "$unit_tmp"
    error "$(t app.sub2api.error.systemd_unit "$SERVICE_NAME")"
  fi
}
_configure_firewall() {
  local FW_DONE=false
  if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw allow "${PORT}/tcp" comment "Sub2API" > /dev/null
    success "$(t app.sub2api.success.ufw_port "$PORT")"
    FW_DONE=true
  fi
  if ! $FW_DONE && command -v firewall-cmd &>/dev/null && \
      firewall-cmd --state &>/dev/null; then
    firewall-cmd --permanent --add-port="${PORT}/tcp" >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
    success "$(t app.sub2api.success.firewalld_port "$PORT")"
    FW_DONE=true
  fi
  if ! $FW_DONE && command -v iptables &>/dev/null; then
    if ! iptables -C INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null; then
      iptables -A INPUT -p tcp --dport "$PORT" -j ACCEPT
    fi
    if command -v netfilter-persistent &>/dev/null; then
      netfilter-persistent save 2>/dev/null && \
        success "$(t app.sub2api.success.iptables_saved)" || true
    elif command -v iptables-save &>/dev/null; then
      mkdir -p /etc/iptables
      iptables-save > /etc/iptables/rules.v4 2>/dev/null && \
        info "$(t app.sub2api.info.iptables_written)" || \
        warn "$(t app.sub2api.warn.iptables_write_failed)"
    else
      warn "$(t app.sub2api.warn.iptables_not_persisted)"
    fi
    success "$(t app.sub2api.success.iptables_port "$PORT")"
    FW_DONE=true
  fi
  $FW_DONE || warn "$(t app.sub2api.warn.no_firewall "$PORT")"
}
_write_logrotate() {
  local logrotate_file="/etc/logrotate.d/sub2api"
  local logrotate_tmp
  logrotate_tmp=$(mktemp "${logrotate_file}.XXXXXX")
  if ! cat > "$logrotate_tmp" << LOGR
${LOG_DIR}/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
}
LOGR
  then
    rm -f "$logrotate_tmp"
    error "$(t app.sub2api.error.logrotate)"
  fi
  if ! chmod 644 "$logrotate_tmp" \
      || ! chown root:root "$logrotate_tmp" \
      || ! mv "$logrotate_tmp" "$logrotate_file"; then
    rm -f "$logrotate_tmp"
    error "$(t app.sub2api.error.logrotate)"
  fi
  success "$(t app.sub2api.success.logrotate)"
}
_write_backup_script() {
  mkdir -p "$BACKUP_DIR"
  local msg_start msg_pg_dump_start msg_pg_dump_ok msg_pg_dump_failed msg_pg_dsn_missing msg_pg_dump_missing
  local msg_config_ok msg_config_failed msg_data_ok msg_data_failed msg_removed_old msg_done
  msg_start="$(t app.sub2api.backup.log.start)"
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
  msg_done="$(t app.sub2api.backup.log.done)"
  local backup_script="/usr/local/bin/sub2api-backup"
  local backup_tmp
  backup_tmp=$(mktemp "${backup_script}.XXXXXX")
  if ! cat > "$backup_tmp" << BKSH_HEADER
#!/bin/bash
# Auto-generated Sub2API backup script. Do not edit this file manually.
# Regenerate it with: sudo bash install_sub2api.sh install
set -euo pipefail
umask 077

BACKUP_DIR="${BACKUP_DIR}"
DATA_DIR="${DATA_DIR}"
CONFIG_DIR="${CONFIG_DIR}"
SERVICE_NAME="${SERVICE_NAME}"
KEEP_DAYS="${BACKUP_KEEP_DAYS}"
PG_DSN="${PG_DSN}"
MSG_START="${msg_start}"
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
_log "── ${MSG_START} ────────────────────────────────────"

mkdir -p "${BACKUP_DIR}"

# ── 1. PostgreSQL database backup ─────────────────────────────
if [[ -n "${PG_DSN}" ]] && command -v pg_dump &>/dev/null; then
  _log "${MSG_PG_DUMP_START}"
  if pg_dump "${PG_DSN}" 2>&1 | gzip > "${PG_DUMP_TMP}"; then
    if mv "${PG_DUMP_TMP}" "${PG_DUMP_FILE}"; then
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
    rm -f "$f" && REMOVED=$(( REMOVED + 1 )) || true
  done < <(find "${BACKUP_DIR}" -maxdepth 1 \
    \( -name "sub2api_*.tar.gz" -o -name "sub2api_db_*.sql.gz" \
    -o -name "sub2api_conf_*.tar.gz" \) \
    -mtime "+${KEEP_DAYS}" 2>/dev/null)
  [[ $REMOVED -gt 0 ]] && _log "$(printf "$MSG_REMOVED_OLD" "$REMOVED" "$KEEP_DAYS")"
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
  mkdir -p "$BACKUP_DIR"
  if [[ -n "${PG_DSN:-}" ]] && command -v pg_dump &>/dev/null; then
    local pg_archive="${BACKUP_DIR}/sub2api_db_${label}_$(date +%Y%m%d_%H%M%S).sql.gz"
    local pg_tmp="${pg_archive}.tmp"
    if pg_dump "${PG_DSN}" 2>/dev/null | gzip > "$pg_tmp"; then
      if mv "$pg_tmp" "$pg_archive"; then
        local sz; sz=$(du -sh "$pg_archive" 2>/dev/null | awk '{print $1}')
        success "$(t app.sub2api.success.silent_pg_dump "$pg_archive" "$sz")"
      else
        rm -f "$pg_tmp"
        warn "$(t app.sub2api.warn.pg_dump_failed)"
      fi
    else
      rm -f "$pg_tmp"
      warn "$(t app.sub2api.warn.pg_dump_failed)"
    fi
  else
    warn "$(t app.sub2api.warn.pg_snapshot_skip)"
  fi
  if [[ -d "$CONFIG_DIR" ]]; then
    local conf_archive="${BACKUP_DIR}/sub2api_conf_${label}_$(date +%Y%m%d_%H%M%S).tar.gz"
    local conf_tmp="${conf_archive}.tmp"
    if tar -czf "$conf_tmp" \
        -C "$(dirname "$CONFIG_DIR")" "$(basename "$CONFIG_DIR")" 2>&1 >&2; then
      if mv "$conf_tmp" "$conf_archive"; then
        local sz; sz=$(du -sh "$conf_archive" 2>/dev/null | awk '{print $1}')
        success "$(t app.sub2api.success.config_backup "$conf_archive" "$sz")"
      else
        rm -f "$conf_tmp"
        warn "$(t app.sub2api.warn.config_backup_failed)"
      fi
    else
      rm -f "$conf_tmp"
      warn "$(t app.sub2api.warn.config_backup_failed)"
    fi
  fi
}
_print_install_summary() {
  local version="$1"
  local INTERNAL_IP
  INTERNAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || echo "YOUR_SERVER_IP")
  local access_url
  if [[ -n "${SUB2API_DOMAIN:-}" ]]; then
    access_url="http://${SUB2API_DOMAIN}/"
  else
    access_url="http://${INTERNAL_IP}:${PORT}/"
  fi
  echo ""
  echo -e "${BOLD}${GREEN}"
  echo "  ╔════════════════════════════════════════════════════════════════╗"
  echo "  ║              $(t app.sub2api.summary.title)                            ║"
  echo "  ╠════════════════════════════════════════════════════════════════╣"
  echo -e "  ║  Setup Wizard   ${CYAN}${access_url}${GREEN}"
  echo -e "  ║  $(t app.sub2api.summary.version)           ${YELLOW}${version}${GREEN}"
  echo "  ╠════════════════════════════════════════════════════════════════╣"
  echo -e "  ║  ${BOLD}$(t app.sub2api.summary.postgres_title)${GREEN}"
  echo -e "  ║    $(t app.sub2api.summary.host)         ${CYAN}localhost${GREEN}"
  echo -e "  ║    $(t app.sub2api.summary.port)         ${CYAN}5432${GREEN}"
  echo -e "  ║    $(t app.sub2api.summary.username)       ${CYAN}${PG_USER}${GREEN}"
  echo -e "  ║    $(t app.sub2api.summary.password)         ${YELLOW}${PG_PASS}${GREEN}   <- $(t app.sub2api.summary.password_written "$CONF_FILE")"
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
  echo -e "  ║    2) $(t app.sub2api.summary.next2)"
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
  LATEST=$(get_latest_release)
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
  load_config
  step "$(t app.sub2api.step.pg_account)"
  _setup_postgres
  step "$(t app.sub2api.step.user_dirs)"
  if ! id "$SERVICE_USER" &>/dev/null; then
    useradd -r -s /usr/sbin/nologin -d "$INSTALL_DIR" "$SERVICE_USER"
    success "$(t app.sub2api.success.user_created "$SERVICE_USER")"
  else
    info "$(t app.sub2api.info.user_exists "$SERVICE_USER")"
  fi
  mkdir -p "$INSTALL_DIR" "$DATA_DIR" "$LOG_DIR" "$CONFIG_DIR" "$BACKUP_DIR"
  chown -R "${SERVICE_USER}:${SERVICE_USER}" "$INSTALL_DIR" "$LOG_DIR" "$CONFIG_DIR"
  chmod 750 "$CONFIG_DIR"
  success "$(t app.sub2api.success.dirs_created)"
  step "$(t app.sub2api.step.download_binary "$BIN_ARCH")"
  local TMP_ARCHIVE; TMP_ARCHIVE=$(mktemp "${INSTALL_DIR}/sub2api-release.XXXXXX.tar.gz")
  if ! curl -fL --progress-bar -o "$TMP_ARCHIVE" "$DOWNLOAD_URL"; then
    rm -f "$TMP_ARCHIVE"
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
  _configure_firewall
  step "$(t app.sub2api.step.logrotate)"
  _write_logrotate
  step "$(t app.sub2api.step.cron_backup)"
  _write_backup_script
  local cron_file="/etc/cron.d/sub2api-backup"
  local cron_tmp
  cron_tmp=$(mktemp "${cron_file}.XXXXXX")
  if ! printf '%s\n' "30 3 * * * root /bin/bash /usr/local/bin/sub2api-backup" > "$cron_tmp" \
      || ! chmod 644 "$cron_tmp" \
      || ! chown root:root "$cron_tmp" \
      || ! mv "$cron_tmp" "$cron_file"; then
    rm -f "$cron_tmp"
    error "$(t app.sub2api.error.cron_backup)"
  fi
  success "$(t app.sub2api.success.cron_backup "$BACKUP_KEEP_DAYS")"
  step "$(t app.sub2api.step.start_service)"
  if ss -ltn 2>/dev/null | grep -qE ":${PORT}[[:space:]]"; then
    local _port_owner
    _port_owner=$(ss -ltnp 2>/dev/null | grep ":${PORT}" | awk '{print $NF}' | head -1 || t app.sub2api.status.unknown_process)
    warn "$(t app.sub2api.warn.port_used "$PORT" "$_port_owner")"
    warn "$(t app.sub2api.warn.port_hint)"
  fi
  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME" --quiet
  systemctl restart "$SERVICE_NAME"
  if wait_for_service "$SERVICE_NAME" 25; then
    success "$(t app.sub2api.success.service_started)"
    systemctl status "$SERVICE_NAME" --no-pager -l 2>/dev/null | head -12 | sed 's/^/  /' >&2
  else
    if systemctl is-failed --quiet "$SERVICE_NAME" 2>/dev/null; then
      warn "$(t app.sub2api.warn.service_failed_rollback)"
      systemctl stop    "$SERVICE_NAME" 2>/dev/null || true
      systemctl disable "$SERVICE_NAME" 2>/dev/null || true
      rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
      systemctl daemon-reload 2>/dev/null || true
      if [[ -n "${OLD_BIN_BAK:-}" && -f "$OLD_BIN_BAK" ]]; then
        rm -f "$BIN_PATH"
        mv "$OLD_BIN_BAK" "$BIN_PATH" 2>/dev/null || true
        chmod +x "$BIN_PATH" 2>/dev/null || true
        chown "${SERVICE_USER}:${SERVICE_USER}" "$BIN_PATH" 2>/dev/null || true
      else
        rm -f "$BIN_PATH"
      fi
      error "$(t app.sub2api.error.install_failed_rollback "$SERVICE_NAME")"
    else
      warn "$(t app.sub2api.warn.waiting_deps)"
      warn "$(t app.sub2api.warn.setup_status_later)"
    fi
  fi
  step "$(t app.sub2api.step.health_save)"
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
    && error "$(t app.sub2api.error.binary_missing_install "$BIN_PATH")"
  step "$(t app.sub2api.step.check_update)"
  check_connectivity
  info "$(t app.sub2api.info.query_release)"
  local LATEST; LATEST=$(get_latest_release)
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
  _backup_silent "pre-update" || warn "$(t app.sub2api.warn.pre_update_backup)"
  step "$(t app.sub2api.step.download_update "$CURRENT" "$LATEST")"
  local DOWNLOAD_URL; DOWNLOAD_URL=$(get_download_url "$LATEST")
  info "$(t app.sub2api.info.download_url "$DOWNLOAD_URL")"
  local TMP_ARCHIVE; TMP_ARCHIVE=$(mktemp "${INSTALL_DIR}/sub2api-release.XXXXXX.tar.gz")
  if ! curl -fL --progress-bar -o "$TMP_ARCHIVE" "$DOWNLOAD_URL"; then
    rm -f "$TMP_ARCHIVE"
    error "$(t app.sub2api.error.update_download)"
  fi
  verify_checksum "$TMP_ARCHIVE" "$LATEST"
  local TMP_BIN
  TMP_BIN=$(extract_and_verify "$TMP_ARCHIVE" "$INSTALL_DIR")
  rm -f "$TMP_ARCHIVE"
  step "$(t app.sub2api.step.replace_restart)"
  local BAK_TS; BAK_TS=$(date +%Y%m%d_%H%M%S)
  local BAK_PATH="${INSTALL_DIR}/sub2api.bak.${BAK_TS}"
  cp "$BIN_PATH" "$BAK_PATH"
  info "$(t app.sub2api.info.old_binary_backup "$BAK_PATH")"
  info "$(t app.sub2api.info.stopping_service)"
  systemctl stop "$SERVICE_NAME" 2>/dev/null || true
  if ! _install_binary_candidate "$TMP_BIN"; then
    [[ -f "$BAK_PATH" ]] && cp "$BAK_PATH" "$BIN_PATH" 2>/dev/null || true
    chmod +x "$BIN_PATH" 2>/dev/null || true
    chown "${SERVICE_USER}:${SERVICE_USER}" "$BIN_PATH" 2>/dev/null || true
    systemctl start "$SERVICE_NAME" 2>/dev/null || true
    error "$(t app.sub2api.error.binary_install "$BIN_PATH")"
  fi
  systemctl daemon-reload
  systemctl start "$SERVICE_NAME"
  if wait_for_service "$SERVICE_NAME" 25; then
    success "$(t app.sub2api.success.new_version_started)"
    INSTALLED_VERSION="$LATEST"
    save_config
    local -a _old_baks
    mapfile -t _old_baks < <(
      find "$INSTALL_DIR" -maxdepth 1 -name "sub2api.bak.*" -type f \
        -printf '%T@ %p\n' 2>/dev/null | sort -rn | awk 'NR>3{print $2}'
    )
    if [[ ${#_old_baks[@]} -gt 0 ]]; then
      rm -f "${_old_baks[@]}"
      info "$(t app.sub2api.info.cleaned_old_binaries "${#_old_baks[@]}")"
    fi
    _health_check
    echo ""
    echo -e "  ${BOLD}${GREEN}$(t app.sub2api.success.update_done "${YELLOW}${CURRENT}${GREEN}" "${YELLOW}${LATEST}${NC}")"
    echo ""
  else
    warn "$(t app.sub2api.warn.new_version_failed "$LATEST" "$CURRENT")"
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    if ! mv "$BAK_PATH" "$BIN_PATH"; then
      warn "$(t app.sub2api.warn.rollback_start_failed "$SERVICE_NAME")"
      error "$(t app.sub2api.error.update_failed "$CURRENT" "$SERVICE_NAME")"
    fi
    chmod +x "$BIN_PATH" 2>/dev/null || true
    chown "${SERVICE_USER}:${SERVICE_USER}" "$BIN_PATH" 2>/dev/null || true
    systemctl start "$SERVICE_NAME" 2>/dev/null || true
    if wait_for_service "$SERVICE_NAME" 15; then
      success "$(t app.sub2api.success.rollback "$CURRENT")"
    else
      warn "$(t app.sub2api.warn.rollback_start_failed "$SERVICE_NAME")"
    fi
    error "$(t app.sub2api.error.update_failed "$CURRENT" "$SERVICE_NAME")"
  fi
}
do_backup() {
  show_banner
  preflight_check "backup"
  load_config
  acquire_lock
  step "$(t app.sub2api.step.manual_backup)"
  mkdir -p "$BACKUP_DIR"
  if [[ -n "${PG_DSN:-}" ]]; then
    if command -v pg_dump &>/dev/null; then
      local PG_ARCHIVE; PG_ARCHIVE="${BACKUP_DIR}/sub2api_db_$(date +%Y%m%d_%H%M%S).sql.gz"
      local PG_TMP="${PG_ARCHIVE}.tmp"
      info "$(t app.sub2api.info.pg_dump)"
      if pg_dump "${PG_DSN}" 2>&1 | gzip > "$PG_TMP"; then
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
        -C "$(dirname "$CONFIG_DIR")" "$(basename "$CONFIG_DIR")" 2>&1; then
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
        -C "$(dirname "$DATA_DIR")" "$(basename "$DATA_DIR")" 2>&1; then
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
  fi
  release_lock
  success "$(t app.sub2api.success.backup_done "$BACKUP_DIR")"
}
do_status() {
  show_banner
  preflight_check "status"
  load_config
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
    if (echo >/dev/tcp/127.0.0.1/${_port}) 2>/dev/null; then
      echo -e "  ${GREEN}[✓]${NC} $(t app.sub2api.status.port_reachable "$_name" "$_port")"
    else
      echo -e "  ${YELLOW}[!]${NC} $(t app.sub2api.status.port_unreachable "$_name" "$_port")"
    fi
  done
  if [[ -n "${PG_DSN:-}" ]]; then
    local _dsn_masked
    _dsn_masked=$(echo "$PG_DSN" | sed 's|:\([^:@]*\)@|:***@|')
    echo -e "  $(t app.sub2api.status.pg_dsn_masked "$_dsn_masked")"
  else
    echo -e "  ${YELLOW}[!]${NC} $(t app.sub2api.status.pg_dsn_missing)"
  fi
  echo -e "\n${BOLD}[$(t app.sub2api.status.directories)]${NC}"
  for _d in "$INSTALL_DIR" "$DATA_DIR" "$LOG_DIR" "$CONFIG_DIR"; do
    if [[ -d "$_d" ]]; then
      local _sz; _sz=$(du -sh "$_d" 2>/dev/null | awk '{print $1}' || echo "?")
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
    bak_total_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | awk '{print $1}')
    echo -e "  $(t app.sub2api.status.backup_dir "$BACKUP_DIR" "$bak_total_size" "$bak_count")"
    local _cnt=0
    while IFS= read -r f; do
      local _sz; _sz=$(du -sh "$f" 2>/dev/null | cut -f1 || echo "?")
      echo -e "  $((_cnt+1)). $(basename "$f")（${_sz}）"
      _cnt=$(( _cnt + 1 ))
    done < <(find "$BACKUP_DIR" -maxdepth 1 \
      \( -name "sub2api_*.tar.gz" -o -name "sub2api_db_*.sql.gz" \) \
      -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -5 | awk '{print $2}')
    [[ $_cnt -eq 0 ]] && echo -e "  ${YELLOW}[!]${NC} $(t app.sub2api.status.no_backup_files)"
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
    ufw_rule=$(ufw status 2>/dev/null | grep "${PORT}" || true)
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
  load_config
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
  prompt "$(t app.sub2api.prompt.continue)"
  local _c; read -r _c
  [[ "$_c" != "YES" ]] && { info "$(t app.sub2api.info.cancelled)"; exit 0; }
  prompt "$(t app.sub2api.prompt.delete_data "$DATA_DIR")"
  local _del_data; read -r _del_data
  local DELETE_DATA=false
  [[ "${_del_data,,}" == "y" ]] && DELETE_DATA=true
  prompt "$(t app.sub2api.prompt.delete_config "$CONFIG_DIR")"
  local _del_conf; read -r _del_conf
  local DELETE_CONF=false
  [[ "${_del_conf,,}" == "y" ]] && DELETE_CONF=true
  prompt "$(t app.sub2api.prompt.delete_backup "$BACKUP_DIR")"
  local _del_bak; read -r _del_bak
  local DELETE_BACKUP=false
  [[ "${_del_bak,,}" == "y" ]] && DELETE_BACKUP=true
  info "$(t app.sub2api.info.stop_disable "$SERVICE_NAME")"
  systemctl stop    "$SERVICE_NAME" 2>/dev/null || true
  systemctl disable "$SERVICE_NAME" 2>/dev/null || true
  rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
  systemctl daemon-reload
  success "$(t app.sub2api.success.removed_systemd)"
  rm -f "$BIN_PATH"
  find "$INSTALL_DIR" -maxdepth 1 -name "sub2api.bak.*"       -type f -delete 2>/dev/null || true
  find "$INSTALL_DIR" -maxdepth 1 -name "sub2api.tmp.*"       -type f -delete 2>/dev/null || true
  find "$INSTALL_DIR" -maxdepth 1 -name "sub2api-release.*.tar.gz" -type f -delete 2>/dev/null || true
  find "$INSTALL_DIR" -maxdepth 1 -name "sub2api-extract.*"   -type d -exec rm -rf {} + 2>/dev/null || true
  success "$(t app.sub2api.success.removed_binary)"
  rm -f /etc/nginx/sites-enabled/sub2api
  rm -f /etc/nginx/sites-available/sub2api
  if command -v nginx &>/dev/null && nginx -t 2>/dev/null; then
    systemctl reload nginx 2>/dev/null || true
    success "$(t app.sub2api.success.removed_nginx_reload)"
  else
    success "$(t app.sub2api.success.removed_nginx)"
  fi
  rm -f /etc/cron.d/sub2api-backup \
        /usr/local/bin/sub2api-backup \
        /etc/logrotate.d/sub2api
  success "$(t app.sub2api.success.removed_scheduled)"
  rm -f "$CONF_FILE"
  success "$(t app.sub2api.success.removed_config)"
  if [[ -n "${LOG_DIR:-}" && "$LOG_DIR" != "." && "$LOG_DIR" != "/" && -d "$LOG_DIR" ]]; then
    safe_rm_dir "$LOG_DIR" "LOG_DIR"
    success "$(t app.sub2api.success.deleted_log "$LOG_DIR")"
  else
    warn "$(t app.sub2api.warn.log_path "${LOG_DIR:-$(t app.sub2api.status.unset)}")"
  fi
  if $DELETE_DATA; then
    safe_rm_dir "$DATA_DIR" "DATA_DIR"
    success "$(t app.sub2api.success.deleted_data "$DATA_DIR")"
    if [[ -d "$INSTALL_DIR" ]] && [[ -z "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]]; then
      safe_rm_dir "$INSTALL_DIR" "INSTALL_DIR"
      success "$(t app.sub2api.success.cleaned_install "$INSTALL_DIR")"
    fi
  else
    info "$(t app.sub2api.info.kept_data "$DATA_DIR")"
  fi
  if $DELETE_CONF; then
    safe_rm_dir "$CONFIG_DIR" "CONFIG_DIR"
    success "$(t app.sub2api.success.deleted_config "$CONFIG_DIR")"
  else
    info "$(t app.sub2api.info.kept_config "$CONFIG_DIR")"
  fi
  if $DELETE_BACKUP; then
    safe_rm_dir "$BACKUP_DIR" "BACKUP_DIR"
    success "$(t app.sub2api.success.deleted_backup "$BACKUP_DIR")"
  else
    info "$(t app.sub2api.info.kept_backup "$BACKUP_DIR")"
  fi
  if $DELETE_DATA && $DELETE_CONF && id "$SERVICE_USER" &>/dev/null; then
    userdel "$SERVICE_USER" 2>/dev/null \
      && success "$(t app.sub2api.success.deleted_user "$SERVICE_USER")" \
      || warn "$(t app.sub2api.warn.delete_user "$SERVICE_USER")"
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
