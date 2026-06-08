#!/bin/bash
set -euo pipefail
umask 077
VW_DOMAIN="vault.example.com"
VW_PORT="8081"
VW_USER="vaultwarden"
VW_GROUP="vaultwarden"
VW_BIN_DIR="/usr/local/bin"
VW_DATA_DIR="/var/lib/vaultwarden"
VW_WEB_DIR="/var/lib/vaultwarden/web-vault"
VW_ENV_FILE="/etc/vaultwarden.env"
VW_LOG_FILE="/var/log/vaultwarden/vaultwarden.log"
VW_BACKUP_DIR="/opt/vaultwarden-backups"
BACKUP_KEEP_DAYS=30
SIGNUPS_ALLOWED="true"
ENABLE_HTTPS="true"
CERTBOT_EMAIL=""
VW_IMAGE_REPO="vaultwarden/server"
VW_IMAGE_TAG="latest-alpine"
WEB_VAULT_VER=""
EXTRACT_TOOL_COMMIT="main"
EXTRACT_TOOL_URL="https://raw.githubusercontent.com/jjlin/docker-image-extract/main/docker-image-extract"
EXTRACT_TOOL_SHA256=""
VW_BIN="${VW_BIN_DIR}/vaultwarden"
CONF_FILE="/etc/vaultwarden_deploy.conf"
CONFIG_KEYS=(
  VW_DOMAIN VW_PORT VW_USER VW_GROUP VW_BIN_DIR VW_DATA_DIR VW_WEB_DIR
  VW_ENV_FILE VW_LOG_FILE VW_BACKUP_DIR BACKUP_KEEP_DAYS SIGNUPS_ALLOWED
  ENABLE_HTTPS CERTBOT_EMAIL VW_IMAGE_REPO VW_IMAGE_TAG WEB_VAULT_VER
  EXTRACT_TOOL_COMMIT EXTRACT_TOOL_SHA256
)
preflight_check() {
  [[ $EUID -ne 0 ]] && error "$(t error.root_required "$0" "")"
  if ! command -v apt-get &>/dev/null; then
    error "$(t app.vaultwarden.error.apt_only)"
  fi
  ARCH=$(uname -m)
  case $ARCH in
    x86_64)  : ;;
    aarch64) : ;;
    armv7l)  : ;;
    *) error "$(t app.vaultwarden.error.arch "$ARCH")" ;;
  esac
}
LOCK_FILE="/var/lock/vaultwarden-deploy.lock"
check_connectivity() {
  check_connectivity_urls \
    "https://auth.docker.io/token" \
    "https://registry-1.docker.io/v2/" \
    "https://api.github.com" && return 0
  error "$(t app.vaultwarden.error.registry_unreachable)"
}
load_config() {
  if [[ -f "$CONF_FILE" ]]; then
    load_config_file "$CONF_FILE" "${CONFIG_KEYS[@]}" || return 0
    VW_BIN="${VW_BIN_DIR}/vaultwarden"
    if [[ "${VW_WEB_DIR}" == */web-vault ]]; then
      VW_WEB_DIR="${VW_DATA_DIR}/web-vault"
    fi
    EXTRACT_TOOL_URL="https://raw.githubusercontent.com/jjlin/docker-image-extract/${EXTRACT_TOOL_COMMIT}/docker-image-extract"
    success "$(t config.loaded "$CONF_FILE")"
  fi
}
save_config() {
  write_config_file "$CONF_FILE" "${CONFIG_KEYS[@]}"
}
get_installed_version() {
  [[ -x "$VW_BIN" ]] && "$VW_BIN" --version 2>/dev/null | awk '{print $2}' || t app.vaultwarden.status.not_installed
}
get_latest_webvault_ver() {
  local json tag
  json=$(curl -fsSL --max-time 15 \
    "https://api.github.com/repos/dani-garcia/bw_web_builds/releases/latest" 2>/dev/null) || true
  [[ -z "$json" ]] && { echo ""; return; }
  if echo "test" | grep -qP 'test' 2>/dev/null; then
    tag=$(echo "$json" | grep -oP '"tag_name"\s*:\s*"v?\K[^"]+' 2>/dev/null | head -1 || true)
  fi
  if [[ -z "${tag:-}" ]]; then
    tag=$(echo "$json" | grep '"tag_name"' | head -1 \
      | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\?\([^"]*\)".*/\1/' 2>/dev/null || true)
  fi
  if [[ "$tag" =~ ^[0-9]+\.[0-9]+ ]]; then
    echo "$tag"
  else
    echo ""
  fi
}
extract_binary() {
  local workdir="$1"
  local platform="$2"
  info "$(t app.vaultwarden.info.download_extract_tool)"
  curl -fsSL --max-time 30 -o "${workdir}/docker-image-extract" "$EXTRACT_TOOL_URL" \
    || error "$(t app.vaultwarden.error.extract_tool_download)"
  [[ -s "${workdir}/docker-image-extract" ]] || error "$(t app.vaultwarden.error.extract_tool_empty)"
  head -1 "${workdir}/docker-image-extract" | grep -q '^#!' \
    || error "$(t app.vaultwarden.error.extract_tool_shebang)"
  local _die_size
  _die_size=$(wc -c < "${workdir}/docker-image-extract")
  [[ "$_die_size" -lt 4096 ]] \
    && error "$(t app.vaultwarden.error.extract_tool_small "$_die_size")"
  grep -q 'registry' "${workdir}/docker-image-extract" \
    || error "$(t app.vaultwarden.error.extract_tool_content)"
  if [[ -n "${EXTRACT_TOOL_SHA256:-}" ]]; then
    local _actual_sha256
    _actual_sha256=$(sha256sum "${workdir}/docker-image-extract" | awk '{print $1}')
    if [[ "$_actual_sha256" != "$EXTRACT_TOOL_SHA256" ]]; then
      error "$(t app.vaultwarden.error.extract_tool_sha "$EXTRACT_TOOL_SHA256" "$_actual_sha256")"
    fi
    success "$(t app.vaultwarden.success.extract_tool_sha)"
  else
    warn "$(t app.vaultwarden.warn.extract_tool_sha_missing)"
  fi
  chmod +x "${workdir}/docker-image-extract"
  info "$(t app.vaultwarden.info.extract_image "$VW_IMAGE_REPO" "$VW_IMAGE_TAG" "$platform")"
  info "$(t app.vaultwarden.info.first_download_wait)"
  local out_dir="${workdir}/image_output"
  mkdir -p "$out_dir"
  bash "${workdir}/docker-image-extract" \
    -p "$platform" \
    -o "$out_dir" \
    "${VW_IMAGE_REPO}:${VW_IMAGE_TAG}" >&2 \
    || error "$(t app.vaultwarden.error.image_extract)"
  local bin_path
  bin_path=$(find "$out_dir" -type f -name "vaultwarden" | head -1)
  [[ -z "$bin_path" ]] && error "$(t app.vaultwarden.error.binary_missing_image)"
  local _bin_size
  _bin_size=$(wc -c < "$bin_path")
  [[ "$_bin_size" -lt 1048576 ]] \
    && error "$(t app.vaultwarden.error.binary_too_small "$_bin_size")"
  if ! head -c 4 "$bin_path" | grep -qP '^\x7fELF' 2>/dev/null; then
    local _magic
    _magic=$(od -A n -t x1 -N 4 "$bin_path" 2>/dev/null | tr -d ' \n' || true)
    [[ "$_magic" != "7f454c46" ]] \
      && error "$(t app.vaultwarden.error.binary_not_elf)"
  fi
  local _expected_em _actual_em
  case "$platform" in
    linux/amd64)  _expected_em="3e00" ;;
    linux/arm64)  _expected_em="b700" ;;
    linux/arm/v7) _expected_em="2800" ;;
    *)            _expected_em="" ;;
  esac
  if [[ -n "$_expected_em" ]]; then
    _actual_em=$(od -A n -t x1 -j 18 -N 2 "$bin_path" 2>/dev/null | tr -d ' \n' || true)
    if [[ "$_actual_em" != "$_expected_em" ]]; then
      error "$(t app.vaultwarden.error.elf_machine "$_expected_em" "$platform" "$_actual_em")"
    fi
  fi
  chmod +x "$bin_path"
  local webvault_path
  webvault_path=$(find "$out_dir" -type d -name "web-vault" | head -1)
  echo "$webvault_path" > "${workdir}/.webvault_path"
  echo "$bin_path"
}
restore_web_vault_backup() {
  local backup_dir="$1"
  [[ -d "$backup_dir" ]] || return 1
  rm -rf "$VW_WEB_DIR" || return 1
  mv "$backup_dir" "$VW_WEB_DIR" || return 1
  chown -R "${VW_USER}:${VW_GROUP}" "$VW_WEB_DIR" || return 1
  chmod -R 750 "$VW_WEB_DIR" || return 1
}
deploy_web_vault_from_dir() {
  local source_dir="$1" backup_dir="$2"
  local staged_dir
  [[ -d "$source_dir" ]] || return 1
  mkdir -p "$(dirname "$VW_WEB_DIR")" || return 1
  staged_dir=$(mktemp -d "${VW_WEB_DIR}.new.XXXXXX") || return 1
  if ! cp -a "${source_dir}/." "$staged_dir/" \
      || ! chown -R "${VW_USER}:${VW_GROUP}" "$staged_dir" \
      || ! chmod -R 750 "$staged_dir"; then
    rm -rf "$staged_dir"
    return 1
  fi
  if [[ -e "$VW_WEB_DIR" || -L "$VW_WEB_DIR" ]]; then
    if ! mv "$VW_WEB_DIR" "$backup_dir"; then
      rm -rf "$staged_dir"
      return 1
    fi
  fi
  if mv "$staged_dir" "$VW_WEB_DIR"; then
    return 0
  fi
  rm -rf "$staged_dir"
  if [[ -d "$backup_dir" ]]; then
    restore_web_vault_backup "$backup_dir" || return 1
  fi
  return 1
}
install_vaultwarden_binary() {
  local source_bin="$1"
  local bin_tmp
  mkdir -p "$VW_BIN_DIR" || return 1
  bin_tmp=$(mktemp "${VW_BIN}.XXXXXX") || return 1
  if ! install -m 755 -o root -g root "$source_bin" "$bin_tmp" \
      || ! mv "$bin_tmp" "$VW_BIN"; then
    rm -f "$bin_tmp"
    return 1
  fi
}
backup_vaultwarden_binary() {
  local backup_path="$1"
  local backup_tmp
  backup_tmp=$(mktemp "${backup_path}.XXXXXX") || return 1
  if ! cp "$VW_BIN" "$backup_tmp" || ! mv "$backup_tmp" "$backup_path"; then
    rm -f "$backup_tmp"
    return 1
  fi
}
_write_nginx_config_file() {
  local nginx_conf="$1"
  local nginx_tmp
  nginx_tmp=$(mktemp "${nginx_conf}.XXXXXX")
  if ! cat > "$nginx_tmp"; then
    rm -f "$nginx_tmp"
    error "$(t app.vaultwarden.error.nginx_write "$nginx_conf")"
  fi
  if ! chmod 644 "$nginx_tmp" \
      || ! chown root:root "$nginx_tmp" \
      || ! mv "$nginx_tmp" "$nginx_conf"; then
    rm -f "$nginx_tmp"
    error "$(t app.vaultwarden.error.nginx_write "$nginx_conf")"
  fi
}
_write_nginx_site_link() {
  local target="$1" link_path="$2"
  local link_tmp
  mkdir -p "$(dirname "$link_path")" || return 1
  link_tmp=$(mktemp "${link_path}.XXXXXX") || return 1
  rm -f "$link_tmp"
  if ! ln -s "$target" "$link_tmp" || ! mv -Tf "$link_tmp" "$link_path"; then
    rm -f "$link_tmp"
    return 1
  fi
}
_write_fail2ban_config_file() {
  local fail2ban_conf="$1"
  local fail2ban_tmp
  fail2ban_tmp=$(mktemp "${fail2ban_conf}.XXXXXX")
  if ! cat > "$fail2ban_tmp"; then
    rm -f "$fail2ban_tmp"
    error "$(t app.vaultwarden.error.fail2ban_write "$fail2ban_conf")"
  fi
  if ! chmod 644 "$fail2ban_tmp" \
      || ! chown root:root "$fail2ban_tmp" \
      || ! mv "$fail2ban_tmp" "$fail2ban_conf"; then
    rm -f "$fail2ban_tmp"
    error "$(t app.vaultwarden.error.fail2ban_write "$fail2ban_conf")"
  fi
}
do_install() {
  show_banner
  preflight_check
  acquire_lock
  check_connectivity
  local _c
  if [[ -x "$VW_BIN" ]]; then
    warn "$(t app.vaultwarden.warn.installed "$VW_BIN" "$(get_installed_version)")"
    warn "$(t app.vaultwarden.warn.reinstall)"
    prompt "$(t app.vaultwarden.prompt.force_reinstall)"
    read -r _c; [[ "${_c,,}" != "y" ]] && { info "$(t app.vaultwarden.info.install_cancelled_update)"; exit 0; }
  fi
  step "$(t app.vaultwarden.step.wizard)"
  if [[ "$VW_DOMAIN" == "vault.example.com" ]]; then
    while true; do
      prompt "$(t app.vaultwarden.prompt.domain)"
      local _input; read -r _input
      [[ -z "$_input" ]] && { warn "$(t app.vaultwarden.warn.domain_empty)"; continue; }
      if [[ ! "$_input" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
        warn "$(t app.vaultwarden.warn.domain_invalid "$_input")"
        continue
      fi
      VW_DOMAIN="$_input"
      break
    done
  fi
  if [[ "$ENABLE_HTTPS" == "true" ]] && [[ -z "$CERTBOT_EMAIL" ]]; then
    while true; do
      prompt "$(t app.vaultwarden.prompt.email)"
      local _email; read -r _email
      [[ -z "$_email" ]] && { warn "$(t app.vaultwarden.warn.email_empty)"; continue; }
      if [[ ! "$_email" =~ ^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$ ]]; then
        warn "$(t app.vaultwarden.warn.email_invalid "$_email")"
        continue
      fi
      CERTBOT_EMAIL="$_email"
      break
    done
  fi
  echo ""
  if ! [[ "$VW_PORT" =~ ^[0-9]+$ ]] || [[ "$VW_PORT" -lt 1 || "$VW_PORT" -gt 65535 ]]; then
    error "$(t app.vaultwarden.error.port_invalid "$VW_PORT")"
  fi
  info "$(t app.vaultwarden.info.domain "$VW_DOMAIN")"
  info "$(t app.vaultwarden.info.listen_port "$VW_PORT")"
  info "$(t app.vaultwarden.info.binary "$VW_BIN")"
  info "$(t app.vaultwarden.info.data_dir "$VW_DATA_DIR")"
  info "Web Vault: ${VW_WEB_DIR}"
  info "$(t app.vaultwarden.info.run_user "$VW_USER")"
  info "HTTPS    : ${ENABLE_HTTPS}"
  echo ""
  prompt "$(t app.vaultwarden.prompt.confirm_config)"
  read -r _c; [[ "${_c,,}" != "y" ]] && { info "$(t app.vaultwarden.info.config_cancelled)"; exit 0; }
  step "$(t app.vaultwarden.step.deps)"
  if ! DEBIAN_FRONTEND=noninteractive apt-get update -qq; then
    warn "$(t app.vaultwarden.warn.apt_update)"
  fi
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    curl wget ca-certificates \
    nginx certbot python3-certbot-nginx \
    sqlite3 argon2 openssl fail2ban \
    logrotate
  success "$(t app.vaultwarden.success.deps)"
  step "$(t app.vaultwarden.step.user_dirs)"
  if ! id "$VW_USER" &>/dev/null; then
    useradd --system --no-create-home \
      --home-dir "$VW_DATA_DIR" \
      --shell /usr/sbin/nologin \
      --comment "Vaultwarden Service Account" \
      "$VW_USER"
    success "$(t app.vaultwarden.success.user_created "$VW_USER")"
  else
    warn "$(t app.vaultwarden.warn.user_exists "$VW_USER")"
  fi
  mkdir -p "$VW_DATA_DIR" "$(dirname "$VW_LOG_FILE")" "$VW_BACKUP_DIR"
  chown -R "${VW_USER}:${VW_GROUP}" "$VW_DATA_DIR" "$(dirname "$VW_LOG_FILE")"
  chmod 750 "$VW_DATA_DIR"
  success "$(t app.vaultwarden.success.dirs)"
  step "$(t app.vaultwarden.step.extract_binary)"
  local PLATFORM
  case $ARCH in
    x86_64)  PLATFORM="linux/amd64"  ;;
    aarch64) PLATFORM="linux/arm64"  ;;
    armv7l)  PLATFORM="linux/arm/v7" ;;
  esac
  local WORK_DIR
  WORK_DIR=$(mktemp -d /tmp/vaultwarden_install_XXXXXX)
  _cleanup_install() {
    flock -u 9 2>/dev/null; exec 9>&- 2>/dev/null
    [[ -d "${WORK_DIR:-}" ]] && rm -rf "$WORK_DIR"
  }
  trap '_cleanup_install' EXIT
  local BIN_PATH EXTRACTED_WEBVAULT_PATH VW_VER
  BIN_PATH=$(extract_binary "$WORK_DIR" "$PLATFORM")
  EXTRACTED_WEBVAULT_PATH=$(cat "${WORK_DIR}/.webvault_path" 2>/dev/null || true)
  success "$(t app.vaultwarden.success.binary_extracted "$BIN_PATH")"
  install_vaultwarden_binary "$BIN_PATH" \
    || error "$(t app.vaultwarden.error.binary_install "$VW_BIN")"
  success "$(t app.vaultwarden.success.binary_installed "$VW_BIN")"
  VW_VER=$("$VW_BIN" --version 2>/dev/null || echo "unknown")
  info "$(t app.vaultwarden.info.version "$VW_VER")"
  step "$(t app.vaultwarden.step.web_vault)"
  local _wv_install_bak="${VW_WEB_DIR}.bak.$(date +%Y%m%d%H%M%S)"
  if [[ -n "$EXTRACTED_WEBVAULT_PATH" && -d "$EXTRACTED_WEBVAULT_PATH" ]]; then
    info "$(t app.vaultwarden.info.web_vault_image)"
    if deploy_web_vault_from_dir "$EXTRACTED_WEBVAULT_PATH" "$_wv_install_bak"; then
      [[ -d "$_wv_install_bak" ]] && rm -rf "$_wv_install_bak"
      success "$(t app.vaultwarden.success.web_vault_image)"
    else
      warn "$(t app.vaultwarden.warn.web_vault_extract)"
      error "$(t app.vaultwarden.error.web_vault_install)"
    fi
  else
    info "$(t app.vaultwarden.info.web_vault_github)"
    local _wv_ver="${WEB_VAULT_VER:-}"
    if [[ -z "$_wv_ver" ]]; then
      _wv_ver=$(get_latest_webvault_ver)
      [[ -z "$_wv_ver" ]] && error "$(t app.vaultwarden.error.web_vault_version)"
    fi
    info "$(t app.vaultwarden.info.web_vault_version "$_wv_ver")"
    local WV_URL="https://github.com/dani-garcia/bw_web_builds/releases/download/v${_wv_ver}/bw_web_v${_wv_ver}.tar.gz"
    info "$(t app.vaultwarden.info.download "$WV_URL")"
    wget -q --show-progress -O "${WORK_DIR}/web-vault.tar.gz" "$WV_URL" \
      || error "$(t app.vaultwarden.error.web_vault_download)"
    local _wv_extract_root="${WORK_DIR}/web-vault-extract"
    mkdir -p "$_wv_extract_root"
    if tar -xzf "${WORK_DIR}/web-vault.tar.gz" -C "$_wv_extract_root"; then
      local _wv_source_dir
      _wv_source_dir=$(find "$_wv_extract_root" -type d -name "web-vault" | head -1)
      if [[ -n "$_wv_source_dir" ]] && deploy_web_vault_from_dir "$_wv_source_dir" "$_wv_install_bak"; then
        [[ -d "$_wv_install_bak" ]] && rm -rf "$_wv_install_bak"
        success "$(t app.vaultwarden.success.web_vault_version "$_wv_ver")"
      else
        warn "$(t app.vaultwarden.warn.web_vault_extract)"
        error "$(t app.vaultwarden.error.web_vault_install)"
      fi
    else
      warn "$(t app.vaultwarden.warn.web_vault_extract)"
      error "$(t app.vaultwarden.error.web_vault_install)"
    fi
  fi
  info "$(t app.vaultwarden.info.web_vault_path "$VW_WEB_DIR")"
  step "$(t app.vaultwarden.step.admin_token)"
  local ADMIN_PLAIN ADMIN_HASH SALT
  ADMIN_PLAIN=$(openssl rand -hex 24)
  info "$(t app.vaultwarden.info.hash_token)"
  ADMIN_HASH=$(printf '%s' "$ADMIN_PLAIN" | "$VW_BIN" hash --preset owasp 2>/dev/null \
    | grep '^\$argon2' | head -1 || true)
  if [[ -z "$ADMIN_HASH" ]]; then
    warn "$(t app.vaultwarden.warn.hash_parse)"
    SALT=$(openssl rand -base64 32)
    ADMIN_HASH=$(printf '%s' "$ADMIN_PLAIN" | \
      argon2 "$SALT" -e -id -k 19456 -t 2 -p 1 -l 32 2>/dev/null || true)
    [[ -z "$ADMIN_HASH" ]] && error "$(t app.vaultwarden.error.admin_token_hash)"
  fi
  success "$(t app.vaultwarden.success.admin_token)"
  step "$(t app.vaultwarden.step.env_file "$VW_ENV_FILE")"
  local _vw_env_tmp
  _vw_env_tmp=$(mktemp "$(dirname "$VW_ENV_FILE")/.vaultwarden.env.XXXXXX")
  if ! cat > "$_vw_env_tmp" << ENV
# Vaultwarden environment file.
# This file contains secrets; keep mode 600 and do not commit it.
# Restart the service after changes: systemctl restart vaultwarden

# ── Basic settings ────────────────────────────────────────────
DOMAIN=https://${VW_DOMAIN}
ROCKET_PORT=${VW_PORT}
ROCKET_ADDRESS=127.0.0.1

# Data and Web Vault directories. DATA_FOLDER should match WorkingDirectory.
DATA_FOLDER=${VW_DATA_DIR}
WEB_VAULT_FOLDER=${VW_WEB_DIR}
WEB_VAULT_ENABLED=true

# ── Registration control ──────────────────────────────────────
# After creating the first account, set this to false and restart the service.
SIGNUPS_ALLOWED=${SIGNUPS_ALLOWED}
INVITATIONS_ALLOWED=true

# ── Admin panel ───────────────────────────────────────────────
# Argon2id hash protection; plaintext tokens are deprecated.
# Single quotes prevent systemd EnvironmentFile expansion of $ in PHC hashes.
ADMIN_TOKEN='${ADMIN_HASH}'

# ── Realtime sync ─────────────────────────────────────────────
# Vaultwarden 1.29+ serves WebSocket traffic on the main ROCKET_PORT.
# WEBSOCKET_ENABLED is kept for compatibility with older versions.
WEBSOCKET_ENABLED=true

# ── Logging ───────────────────────────────────────────────────
LOG_FILE=${VW_LOG_FILE}
LOG_LEVEL=info
EXTENDED_LOGGING=true

# ── Security hardening ────────────────────────────────────────
LOGIN_RATELIMIT_MAX_BURST=10
LOGIN_RATELIMIT_SECONDS=60
ADMIN_RATELIMIT_MAX_BURST=10
ADMIN_RATELIMIT_SECONDS=60
IP_HEADER=X-Real-IP

# ── Attachment limits in KiB ──────────────────────────────────
ATTACHMENTS_SIZE_LIMIT=10240
USER_ATTACHMENT_LIMIT=102400

# ── Optional SMTP settings ────────────────────────────────────
# SMTP_HOST=smtp.example.com
# SMTP_PORT=587
# SMTP_SECURITY=starttls
# SMTP_USERNAME=your@email.com
# SMTP_PASSWORD=your_password
# SMTP_FROM=no-reply@${VW_DOMAIN}
# SMTP_FROM_NAME=Vaultwarden

# ── Optional push notifications; request ID/key from Bitwarden first ──
# PUSH_ENABLED=true
# PUSH_INSTALLATION_ID=
# PUSH_INSTALLATION_KEY=
ENV
  then
    rm -f "$_vw_env_tmp"
    error "$(t app.vaultwarden.error.env_file "$VW_ENV_FILE")"
  fi
  if ! chmod 600 "$_vw_env_tmp" \
      || ! chown root:root "$_vw_env_tmp" \
      || ! mv "$_vw_env_tmp" "$VW_ENV_FILE"; then
    rm -f "$_vw_env_tmp"
    error "$(t app.vaultwarden.error.env_file "$VW_ENV_FILE")"
  fi
  success "$(t app.vaultwarden.success.env_file "$VW_ENV_FILE")"
  step "$(t app.vaultwarden.step.systemd)"
  local unit_path="/etc/systemd/system/vaultwarden.service"
  local unit_tmp
  unit_tmp=$(mktemp "${unit_path}.XXXXXX")
  if ! cat > "$unit_tmp" << UNIT
[Unit]
Description=Vaultwarden Password Manager (Bitwarden-compatible)
Documentation=https://github.com/dani-garcia/vaultwarden
After=network.target
# Uncomment and adjust when using an external database.
# After=mysql.service
# Requires=mysql.service

[Service]
# Run as a dedicated low-privilege user.
User=${VW_USER}
Group=${VW_GROUP}

# Environment file.
EnvironmentFile=${VW_ENV_FILE}

# Working directory; SQLite data is stored here.
WorkingDirectory=${VW_DATA_DIR}

# Binary path.
ExecStart=${VW_BIN}

# Process limits.
LimitNOFILE=1048576
LimitNPROC=64

# systemd sandboxing for defense in depth.
PrivateTmp=true
PrivateDevices=true
ProtectHome=true
ProtectSystem=strict
# Keep the filesystem read-only except for data and log directories.
ReadWritePaths=${VW_DATA_DIR} $(dirname "${VW_LOG_FILE}")

# Restart after failures.
Restart=on-failure
RestartSec=5s

# Send stdout and stderr to the systemd journal.
StandardOutput=journal
StandardError=journal
SyslogIdentifier=vaultwarden

[Install]
WantedBy=multi-user.target
UNIT
  then
    rm -f "$unit_tmp"
    error "$(t app.vaultwarden.error.systemd)"
  fi
  if ! chmod 644 "$unit_tmp" \
      || ! chown root:root "$unit_tmp" \
      || ! mv "$unit_tmp" "$unit_path"; then
    rm -f "$unit_tmp"
    error "$(t app.vaultwarden.error.systemd)"
  fi
  systemctl daemon-reload
  if ! systemctl enable vaultwarden --quiet; then
    warn "$(t app.vaultwarden.warn.service_enable_failed "vaultwarden" "vaultwarden")"
  fi
  success "$(t app.vaultwarden.success.systemd)"
  step "$(t app.vaultwarden.step.start_service)"
  if ss -ltn 2>/dev/null | grep -qE ":${VW_PORT}[[:space:]]"; then
    local _port_owner
    _port_owner=$(ss -ltnp 2>/dev/null | grep ":${VW_PORT}" | awk '{print $NF}' | head -1 || t app.vaultwarden.status.unknown_process)
    warn "$(t app.vaultwarden.warn.port_used "$VW_PORT" "$_port_owner")"
    warn "$(t app.vaultwarden.warn.port_hint)"
  fi
  if systemctl start vaultwarden && wait_for_service vaultwarden 20; then
    success "$(t app.vaultwarden.success.service_started)"
    systemctl status vaultwarden --no-pager -l | head -12 | sed 's/^/  /'
  else
    warn "$(t app.vaultwarden.warn.service_cleanup)"
    systemctl stop    vaultwarden 2>/dev/null || true
    systemctl disable vaultwarden 2>/dev/null || true
    rm -f /etc/systemd/system/vaultwarden.service
    systemctl daemon-reload 2>/dev/null || true
    rm -f "$VW_BIN"
    error "$(t app.vaultwarden.error.install_failed_start)"
  fi
  step "$(t app.vaultwarden.step.nginx_http)"
  local NGINX_CONF="/etc/nginx/sites-available/vaultwarden"
  mkdir -p /var/www/certbot /etc/nginx/sites-available /etc/nginx/sites-enabled
  _write_nginx_config_file "$NGINX_CONF" << NGINX
# Vaultwarden reverse proxy configuration for the HTTP bootstrap phase.
server {
    listen 80;
    listen [::]:80;
    server_name ${VW_DOMAIN};

    # Let's Encrypt ACME challenge
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # Temporary direct proxy before HTTPS certificates are available.
    location / {
        proxy_pass         http://127.0.0.1:${VW_PORT};
        proxy_http_version 1.1;
        proxy_set_header   Upgrade             \$http_upgrade;
        proxy_set_header   Connection          "upgrade";
        proxy_set_header   Host                \$host;
        proxy_set_header   X-Real-IP           \$remote_addr;
        proxy_set_header   X-Forwarded-For     \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto   \$scheme;
        proxy_read_timeout 90s;
    }
}
NGINX
  _write_nginx_site_link "$NGINX_CONF" /etc/nginx/sites-enabled/vaultwarden \
    || error "$(t app.vaultwarden.error.nginx_write "$NGINX_CONF")"
  if [[ -L /etc/nginx/sites-enabled/default ]]; then
    warn "$(t app.vaultwarden.warn.default_site_removed)"
    rm -f /etc/nginx/sites-enabled/default
  fi
  nginx -t || error "$(t app.vaultwarden.error.nginx_http_test)"
  success "$(t app.vaultwarden.success.nginx_http)"
  step "$(t app.vaultwarden.step.certbot)"
  if ! systemctl enable nginx --quiet; then
    warn "$(t app.vaultwarden.warn.service_enable_failed "nginx" "nginx")"
  fi
  if ! systemctl restart nginx || ! wait_for_service nginx 10; then
    error "$(t app.vaultwarden.error.nginx_start)"
  fi
  success "$(t app.vaultwarden.success.nginx_ready)"
  if [[ "$ENABLE_HTTPS" == "true" ]]; then
    info "$(t app.vaultwarden.info.request_cert "$VW_DOMAIN" "$CERTBOT_EMAIL")"
    if certbot certonly --webroot \
      -w /var/www/certbot \
      -d "$VW_DOMAIN" \
      --email "$CERTBOT_EMAIL" \
      --agree-tos \
      --non-interactive >&2; then
      success "$(t app.vaultwarden.success.certbot)"
    else
      warn "$(t app.vaultwarden.warn.certbot_failed)"
      warn "$(t app.vaultwarden.warn.certbot_manual "$VW_DOMAIN" "$CERTBOT_EMAIL")"
    fi
    if systemctl list-timers certbot* 2>/dev/null | grep -q certbot; then
      success "$(t app.vaultwarden.success.certbot_timer)"
    else
      if crontab -l 2>/dev/null | grep -q "certbot renew"; then
        success "$(t app.vaultwarden.success.certbot_cron_exists)"
      else
        (crontab -l 2>/dev/null; echo "30 2 * * * certbot renew --quiet --post-hook 'systemctl reload nginx'") | crontab -
        success "$(t app.vaultwarden.success.certbot_cron)"
      fi
    fi
    local CERT_PATH_FULL="/etc/letsencrypt/live/${VW_DOMAIN}/fullchain.pem"
    local CERT_KEY_FULL="/etc/letsencrypt/live/${VW_DOMAIN}/privkey.pem"
    if [[ -f "$CERT_PATH_FULL" ]]; then
      local _nginx_ver _http2_directive _listen_https
      _nginx_ver=$(nginx -v 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "0.0.0")
      if [[ "$_nginx_ver" == "0.0.0" ]]; then
        warn "$(t app.vaultwarden.warn.nginx_version)"
      fi
      if awk -v v="$_nginx_ver" 'BEGIN{
          n=split(v,a,".");
          split("1.25.1",b,".");
          for(i=1;i<=3;i++){
            ai=a[i]+0; bi=b[i]+0;
            if(ai>bi) exit 0;
            if(ai<bi) exit 1;
          }
          exit 0
        }'; then
        _http2_directive="    http2 on;"
        _listen_https="    listen 443 ssl;\n    listen [::]:443 ssl;"
      else
        _http2_directive=""
        _listen_https="    listen 443 ssl http2;\n    listen [::]:443 ssl http2;"
      fi
      {
        cat << NGINX2
# Vaultwarden reverse proxy configuration for HTTP to HTTPS redirect.
server {
    listen 80;
    listen [::]:80;
    server_name ${VW_DOMAIN};

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }
    location / {
        return 301 https://\$host\$request_uri;
    }
}

NGINX2
        echo "server {"
        printf '%b\n' "$_listen_https"
        [[ -n "$_http2_directive" ]] && echo "$_http2_directive"
        cat << NGINX2BODY
    server_name ${VW_DOMAIN};

    # TLS certificates.
    ssl_certificate     ${CERT_PATH_FULL};
    ssl_certificate_key ${CERT_KEY_FULL};

    # TLS hardening.
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-CHACHA20-POLY1305';
    ssl_prefer_server_ciphers off;
    ssl_session_timeout 1d;
    ssl_session_cache shared:MozTLS:10m;
    ssl_stapling on;
    ssl_stapling_verify on;

    # Match the attachment size limit configured in the environment file.
    client_max_body_size 20M;

    # Security headers.
    add_header Strict-Transport-Security  "max-age=31536000; includeSubDomains; preload" always;
    add_header X-Content-Type-Options     "nosniff"                                      always;
    add_header X-Frame-Options            "SAMEORIGIN"                                   always;
    add_header X-XSS-Protection           "0"                                            always;
    add_header Referrer-Policy            "strict-origin-when-cross-origin"              always;
    add_header Permissions-Policy         "camera=(), microphone=(), geolocation=()"     always;

    # Main reverse proxy with WebSocket upgrade support.
    location / {
        proxy_pass         http://127.0.0.1:${VW_PORT};
        proxy_http_version 1.1;
        proxy_set_header   Upgrade             \$http_upgrade;
        proxy_set_header   Connection          "upgrade";
        proxy_set_header   Host                \$host;
        proxy_set_header   X-Real-IP           \$remote_addr;
        proxy_set_header   X-Forwarded-For     \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto   \$scheme;
        proxy_read_timeout 90s;
    }

    # Notification WebSocket path retained for older Vaultwarden versions.
    location /notifications/hub {
        proxy_pass         http://127.0.0.1:${VW_PORT};
        proxy_http_version 1.1;
        proxy_set_header   Upgrade    \$http_upgrade;
        proxy_set_header   Connection "upgrade";
        proxy_set_header   Host       \$host;
        proxy_read_timeout 3600s;
    }
    location /notifications/hub/negotiate {
        proxy_pass http://127.0.0.1:${VW_PORT};
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Admin panel. Restrict source IPs in production when possible.
    location /admin {
        # Uncomment to restrict access to trusted IPs:
        # allow YOUR_TRUSTED_IP/32;
        # deny  all;
        proxy_pass       http://127.0.0.1:${VW_PORT}/admin;
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Gzip compression.
    gzip on;
    gzip_types text/plain text/css application/json application/javascript
               text/xml application/xml text/javascript image/svg+xml application/wasm;
    gzip_min_length 1024;
    gzip_vary on;

    # Logs.
    access_log /var/log/nginx/vaultwarden_access.log;
    error_log  /var/log/nginx/vaultwarden_error.log;
}
NGINX2BODY
      } | _write_nginx_config_file "$NGINX_CONF"
      if nginx -t; then
        if systemctl reload nginx; then
          success "$(t app.vaultwarden.success.nginx_https)"
        else
          warn "$(t app.vaultwarden.warn.nginx_https_test)"
        fi
      else
        warn "$(t app.vaultwarden.warn.nginx_https_test)"
      fi
    else
      warn "$(t app.vaultwarden.warn.cert_missing)"
    fi
  else
    warn "$(t app.vaultwarden.warn.https_skipped)"
  fi
  step "$(t app.vaultwarden.step.fail2ban)"
  mkdir -p /etc/fail2ban/filter.d /etc/fail2ban/jail.d
  _write_fail2ban_config_file /etc/fail2ban/filter.d/vaultwarden.conf << F2B
[INCLUDES]
before = common.conf

[Definition]
failregex = ^.*Username or password is incorrect\. Try again\. IP: <ADDR>.*$
            ^.*TOTP, Duo or recovery code is incorrect\. Try again\. IP: <ADDR>.*$
ignoreregex =
F2B
  _write_fail2ban_config_file /etc/fail2ban/filter.d/vaultwarden-admin.conf << F2B2
[INCLUDES]
before = common.conf

[Definition]
failregex = ^.*Invalid admin token\. IP: <ADDR>.*$
ignoreregex =
F2B2
  _write_fail2ban_config_file /etc/fail2ban/jail.d/vaultwarden.conf << JAIL
[vaultwarden]
enabled  = true
port     = http,https
filter   = vaultwarden
logpath  = ${VW_LOG_FILE}
maxretry = 5
bantime  = 3600
findtime = 3600

[vaultwarden-admin]
enabled  = true
port     = http,https
filter   = vaultwarden-admin
logpath  = ${VW_LOG_FILE}
maxretry = 3
bantime  = 86400
findtime = 86400
JAIL
  if ! systemctl enable fail2ban --quiet; then
    warn "$(t app.vaultwarden.warn.service_enable_failed "fail2ban" "fail2ban")"
  fi
  if ! systemctl restart fail2ban; then
    error "$(t app.vaultwarden.error.fail2ban_start)"
  fi
  success "$(t app.vaultwarden.success.fail2ban)"
  step "$(t app.vaultwarden.step.logrotate)"
  local _vw_logrotate_file="/etc/logrotate.d/vaultwarden"
  local _vw_logrotate_tmp
  _vw_logrotate_tmp=$(mktemp "${_vw_logrotate_file}.XXXXXX")
  if ! cat > "$_vw_logrotate_tmp" << LOGR
${VW_LOG_FILE} {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    # copytruncate avoids requiring SIGHUP/SIGUSR1 support from Rocket.
    # A tiny number of log lines can be lost during rotation.
    copytruncate
}
LOGR
  then
    rm -f "$_vw_logrotate_tmp"
    error "$(t app.vaultwarden.error.logrotate)"
  fi
  if ! chmod 644 "$_vw_logrotate_tmp" \
      || ! chown root:root "$_vw_logrotate_tmp" \
      || ! mv "$_vw_logrotate_tmp" "$_vw_logrotate_file"; then
    rm -f "$_vw_logrotate_tmp"
    error "$(t app.vaultwarden.error.logrotate)"
  fi
  success "$(t app.vaultwarden.success.logrotate)"
  step "$(t app.vaultwarden.step.firewall)"
  local FW_DONE=false
  local FW_ERROR=false
  if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
    if ufw allow "Nginx Full" >/dev/null 2>&1; then
      success "$(t app.vaultwarden.success.ufw)"
      FW_DONE=true
    else
      FW_ERROR=true
    fi
  fi
  if ! $FW_DONE && command -v iptables &>/dev/null; then
    local iptables_ok=true
    for P in 80 443; do
      if ! iptables -C INPUT -p tcp --dport "$P" -j ACCEPT 2>/dev/null \
          && ! iptables -A INPUT -p tcp --dport "$P" -j ACCEPT; then
        iptables_ok=false
        break
      fi
    done
    if $iptables_ok; then
      success "$(t app.vaultwarden.success.iptables)"
      FW_DONE=true
      if command -v netfilter-persistent &>/dev/null; then
        if netfilter-persistent save 2>/dev/null; then
          success "$(t app.vaultwarden.success.iptables_saved)"
        else
          warn "$(t app.vaultwarden.warn.iptables_not_persisted)"
        fi
      else
        warn "$(t app.vaultwarden.warn.iptables_not_persisted)"
      fi
    else
      FW_ERROR=true
    fi
  fi
  if ! $FW_DONE; then
    if $FW_ERROR; then
      warn "$(t app.vaultwarden.warn.firewall_config_failed)"
    else
      warn "$(t app.vaultwarden.warn.no_firewall)"
    fi
  fi
  step "$(t app.vaultwarden.step.auto_backup)"
  _write_backup_script
  local _vw_cron_file="/etc/cron.d/vaultwarden-backup"
  local _vw_cron_tmp
  _vw_cron_tmp=$(mktemp "${_vw_cron_file}.XXXXXX")
  if ! printf '%s\n' "30 3 * * * root /bin/bash /usr/local/bin/vaultwarden-backup >> ${VW_BACKUP_DIR}/backup.log 2>&1" > "$_vw_cron_tmp" \
      || ! chmod 644 "$_vw_cron_tmp" \
      || ! chown root:root "$_vw_cron_tmp" \
      || ! mv "$_vw_cron_tmp" "$_vw_cron_file"; then
    rm -f "$_vw_cron_tmp"
    error "$(t app.vaultwarden.error.auto_backup)"
  fi
  success "$(t app.vaultwarden.success.auto_backup "$BACKUP_KEEP_DAYS")"
  step "$(t app.vaultwarden.step.health)"
  save_config
  local _hc_elapsed=0
  local HTTP_CODE
  until HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}" --max-time 5 "http://127.0.0.1:${VW_PORT}/" || echo "000") \
      && [[ "$HTTP_CODE" =~ ^(200|301|302)$ ]]; do
    sleep 1; _hc_elapsed=$(( _hc_elapsed + 1 ))
    [[ $_hc_elapsed -ge 10 ]] && break
  done
  if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "302" ]]; then
    success "$(t app.vaultwarden.success.local_health "$HTTP_CODE")"
  else
    warn "$(t app.vaultwarden.warn.local_health "$HTTP_CODE")"
    warn "$(t app.vaultwarden.warn.debug)"
  fi
  local INTERNAL_IP PROTO INSTALLED_VER
  INTERNAL_IP=$(hostname -I | awk '{print $1}')
  if [[ "$ENABLE_HTTPS" == "true" ]]; then PROTO="https"; else PROTO="http"; fi
  INSTALLED_VER=$(get_installed_version)
  local _token_tmp
  _token_tmp=$(mktemp /root/.vaultwarden-admin-token.XXXXXX)
  if ! chmod 600 "$_token_tmp" || ! printf '%s\n' "$ADMIN_PLAIN" > "$_token_tmp"; then
    rm -f "$_token_tmp"
    error "$(t app.vaultwarden.error.admin_token_hash)"
  fi
  echo ""
  echo -e "${BOLD}${GREEN}"
  echo "  ╔═══════════════════════════════════════════════════════════════╗"
  echo "  ║             $(t app.vaultwarden.summary.title)            ║"
  echo "  ╠═══════════════════════════════════════════════════════════════╣"
  echo -e "  ║  $(t app.vaultwarden.summary.url)    ${CYAN}${PROTO}://${VW_DOMAIN}${GREEN}"
  echo -e "  ║  $(t app.vaultwarden.summary.admin)  ${CYAN}${PROTO}://${VW_DOMAIN}/admin${GREEN}"
  echo -e "  ║  $(t app.vaultwarden.summary.lan)    ${CYAN}http://${INTERNAL_IP}:${VW_PORT}${GREEN}"
  echo "  ╠═══════════════════════════════════════════════════════════════╣"
  echo -e "  ║  $(t app.vaultwarden.summary.version)        ${YELLOW}${INSTALLED_VER}${GREEN}"
  echo -e "  ║  $(t app.vaultwarden.summary.binary)      ${YELLOW}${VW_BIN}${GREEN}"
  echo -e "  ║  $(t app.vaultwarden.summary.data)    ${YELLOW}${VW_DATA_DIR}${GREEN}"
  echo -e "  ║  Web Vault   ${YELLOW}${VW_WEB_DIR}${GREEN}"
  echo -e "  ║  $(t app.vaultwarden.summary.env)    ${YELLOW}${VW_ENV_FILE}${GREEN}  ($(t app.vaultwarden.summary.mode600))"
  echo -e "  ║  $(t app.vaultwarden.summary.log)        ${YELLOW}${VW_LOG_FILE}${GREEN}"
  echo -e "  ║  $(t app.vaultwarden.summary.backup)    ${YELLOW}${VW_BACKUP_DIR}${GREEN}"
  echo "  ╠═══════════════════════════════════════════════════════════════╣"
  echo -e "  ║  ${RED}${BOLD}$(t app.vaultwarden.summary.token_warning)${GREEN}"
  echo -e "  ║  $(t app.vaultwarden.summary.view_command) ${YELLOW}cat ${_token_tmp}${GREEN}"
  echo -e "  ║  $(t app.vaultwarden.summary.remove_command) ${YELLOW}rm -f ${_token_tmp}${GREEN}"
  echo "  ╚═══════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
  echo -e "  ${BOLD}$(t app.vaultwarden.summary.first_steps)${NC}"
  echo ""
  echo -e "  ${CYAN}# $(t app.vaultwarden.summary.step0)${NC}"
  echo -e "     cat ${_token_tmp}"
  echo -e "     rm -f ${_token_tmp}"
  echo ""
  echo -e "  ${CYAN}# $(t app.vaultwarden.summary.step1)${NC}"
  echo -e "     $(t app.vaultwarden.summary.create_account "${PROTO}://${VW_DOMAIN}")"
  echo ""
  echo -e "  ${CYAN}# $(t app.vaultwarden.summary.step2)${NC}"
  echo -e "     $(t app.vaultwarden.summary.method_admin "${PROTO}://${VW_DOMAIN}")"
  echo -e "     $(t app.vaultwarden.summary.method_config "$VW_ENV_FILE")"
  echo -e "              $(t app.vaultwarden.summary.then_restart)"
  echo ""
  echo -e "  ${CYAN}# $(t app.vaultwarden.summary.step3)${NC}"
  echo -e "     $(t app.vaultwarden.summary.self_hosted "${PROTO}://${VW_DOMAIN}")"
  echo ""
  echo -e "  ${CYAN}# $(t app.vaultwarden.summary.step4)${NC}"
  echo -e "     systemctl status vaultwarden          # $(t app.vaultwarden.summary.cmd_status)"
  echo -e "     journalctl -u vaultwarden -f          # $(t app.vaultwarden.summary.cmd_logs)"
  echo -e "     systemctl restart vaultwarden         # $(t app.vaultwarden.summary.cmd_restart)"
  echo -e "     vaultwarden-backup                    # $(t app.vaultwarden.summary.cmd_backup)"
  echo ""
  echo -e "  ${YELLOW}${BOLD}$(t app.vaultwarden.summary.important)${NC} $(t app.vaultwarden.summary.token_cleanup)"
  echo ""
}
do_update() {
  show_banner
  preflight_check
  load_config
  acquire_lock
  check_connectivity
  step "$(t app.vaultwarden.step.update)"
  [[ ! -x "$VW_BIN" ]] && error "$(t app.vaultwarden.error.not_installed_update)"
  local OLD_VER NEW_VER PLATFORM WORK_DIR NEW_BIN_PATH EXTRACTED_WEBVAULT_PATH
  OLD_VER=$(get_installed_version)
  info "$(t app.vaultwarden.info.current_version "$OLD_VER")"
  info "$(t app.vaultwarden.info.pre_update_backup)"
  _backup_silent "pre-update"
  local _pre_update_svc_state
  _pre_update_svc_state=$(systemctl is-active vaultwarden 2>/dev/null || echo "inactive")
  if [[ "$_pre_update_svc_state" == "failed" ]]; then
    warn "$(t app.vaultwarden.warn.pre_update_failed_state)"
    warn "$(t app.vaultwarden.warn.pre_update_existing_error)"
  fi
  info "$(t app.vaultwarden.info.stop_service)"
  systemctl stop vaultwarden 2>/dev/null || true
  case $ARCH in
    x86_64)  PLATFORM="linux/amd64"  ;;
    aarch64) PLATFORM="linux/arm64"  ;;
    armv7l)  PLATFORM="linux/arm/v7" ;;
    *)       error "$(t app.vaultwarden.error.arch "$ARCH")" ;;
  esac
  WORK_DIR=$(mktemp -d /tmp/vaultwarden_update_XXXXXX)
  _cleanup_update() {
    flock -u 9 2>/dev/null; exec 9>&- 2>/dev/null
    [[ -d "${WORK_DIR:-}" ]] && rm -rf "$WORK_DIR"
  }
  trap '_cleanup_update' EXIT
  step "$(t app.vaultwarden.step.extract_update_binary)"
  NEW_BIN_PATH=$(extract_binary "$WORK_DIR" "$PLATFORM")
  EXTRACTED_WEBVAULT_PATH=$(cat "${WORK_DIR}/.webvault_path" 2>/dev/null || true)
  backup_vaultwarden_binary "${VW_BIN}.bak.$(date +%Y%m%d%H%M%S)" \
    || error "$(t app.vaultwarden.error.binary_install "$VW_BIN")"
  install_vaultwarden_binary "$NEW_BIN_PATH" \
    || error "$(t app.vaultwarden.error.binary_install "$VW_BIN")"
  success "$(t app.vaultwarden.success.binary_updated)"
  NEW_VER=$(get_installed_version)
  step "$(t app.vaultwarden.step.update_web_vault)"
  local _wv_bak_ts="${VW_WEB_DIR}.bak.$(date +%Y%m%d%H%M%S)"
  if [[ -n "$EXTRACTED_WEBVAULT_PATH" && -d "$EXTRACTED_WEBVAULT_PATH" ]]; then
    if deploy_web_vault_from_dir "$EXTRACTED_WEBVAULT_PATH" "$_wv_bak_ts"; then
      success "$(t app.vaultwarden.success.web_vault_updated_image)"
    else
      warn "$(t app.vaultwarden.warn.web_vault_extract)"
    fi
  else
    local _fetched_wv_ver
    _fetched_wv_ver=$(get_latest_webvault_ver)
    if [[ -n "$_fetched_wv_ver" ]]; then
      local WV_URL="https://github.com/dani-garcia/bw_web_builds/releases/download/v${_fetched_wv_ver}/bw_web_v${_fetched_wv_ver}.tar.gz"
      if wget -q --show-progress -O "${WORK_DIR}/web-vault.tar.gz" "$WV_URL"; then
        local _wv_extract_root="${WORK_DIR}/web-vault-extract"
        mkdir -p "$_wv_extract_root"
        if tar -xzf "${WORK_DIR}/web-vault.tar.gz" -C "$_wv_extract_root"; then
          local _wv_source_dir
          _wv_source_dir=$(find "$_wv_extract_root" -type d -name "web-vault" | head -1)
          if [[ -n "$_wv_source_dir" ]] && deploy_web_vault_from_dir "$_wv_source_dir" "$_wv_bak_ts"; then
            success "$(t app.vaultwarden.success.web_vault_updated_version "$_fetched_wv_ver")"
          else
            warn "$(t app.vaultwarden.warn.web_vault_extract)"
          fi
        else
          warn "$(t app.vaultwarden.warn.web_vault_extract)"
        fi
      else
        warn "$(t app.vaultwarden.warn.web_vault_update_download)"
      fi
    else
      warn "$(t app.vaultwarden.warn.web_vault_update_version)"
    fi
  fi
  if ss -ltn 2>/dev/null | grep -qE ":${VW_PORT}[[:space:]]"; then
    local _port_owner_upd
    _port_owner_upd=$(ss -ltnp 2>/dev/null | grep ":${VW_PORT}" | awk '{print $NF}' | head -1 || t app.vaultwarden.status.unknown_process)
    warn "$(t app.vaultwarden.warn.update_port_used "$VW_PORT" "$_port_owner_upd")"
  fi
  if systemctl start vaultwarden && wait_for_service vaultwarden 20; then
    success "$(t app.vaultwarden.success.restart)"
    if [[ "$OLD_VER" != "$NEW_VER" ]]; then
      success "$(t app.vaultwarden.success.version_updated "$OLD_VER" "$NEW_VER")"
    else
      success "$(t app.vaultwarden.success.already_latest "$NEW_VER")"
    fi
  else
    warn "$(t app.vaultwarden.warn.restart_failed_rollback)"
    NEWEST_BAK=$(find "$(dirname "$VW_BIN")" -maxdepth 1 \
      -name "vaultwarden.bak.*" -type f -printf '%T@ %p\n' 2>/dev/null \
      | sort -rn | awk 'NR==1{print $2}' || true)
    if [[ -n "$NEWEST_BAK" ]]; then
      install_vaultwarden_binary "$NEWEST_BAK" \
        || error "$(t app.vaultwarden.error.rollback_start_failed)"
      if [[ -d "$_wv_bak_ts" ]]; then
        restore_web_vault_backup "$_wv_bak_ts" \
          || error "$(t app.vaultwarden.error.rollback_start_failed)"
        warn "$(t app.vaultwarden.warn.web_vault_rolled_back)"
      fi
      if systemctl start vaultwarden && wait_for_service vaultwarden 20; then
        success "$(t app.vaultwarden.success.rollback "$OLD_VER")"
        local _backup_kept
        _backup_kept=$(find "$(dirname "$VW_BIN")" -maxdepth 1 -name "vaultwarden.bak.*" -type f | sort -r | head -1 || t app.vaultwarden.status.not_installed)
        error "$(t app.vaultwarden.error.update_rolled_back "$OLD_VER" "$_backup_kept")"
      else
        error "$(t app.vaultwarden.error.rollback_start_failed)"
      fi
    else
      error "$(t app.vaultwarden.error.no_backup_binary)"
    fi
  fi
  local -a _old_baks
  mapfile -t _old_baks < <(find "$(dirname "$VW_BIN")" -maxdepth 1 \
    -name "vaultwarden.bak.*" -type f -printf '%T@ %p\n' 2>/dev/null \
    | sort -rn | awk 'NR>3{print $2}')
  [[ ${#_old_baks[@]} -gt 0 ]] && rm -f "${_old_baks[@]}"
  local _wv_parent
  _wv_parent=$(dirname "$VW_WEB_DIR")
  local _wv_basename
  _wv_basename=$(basename "$VW_WEB_DIR")
  local -a _old_wv_baks
  mapfile -t _old_wv_baks < <(find "$_wv_parent" -maxdepth 1 \
    -name "${_wv_basename}.bak.*" -type d -printf '%T@ %p\n' 2>/dev/null \
    | sort -rn | awk 'NR>3{print $2}')
  if [[ ${#_old_wv_baks[@]} -gt 0 ]]; then
    rm -rf "${_old_wv_baks[@]}"
    info "$(t app.vaultwarden.info.cleaned_webvault_backups "${#_old_wv_baks[@]}")"
  fi
  save_config
}
_write_backup_script() {
  local backup_script="/usr/local/bin/vaultwarden-backup"
  local backup_tmp
  backup_tmp=$(mktemp "${backup_script}.XXXXXX")
  if ! cat > "$backup_tmp" << 'BKSH'
#!/bin/bash
# Auto-generated Vaultwarden backup script.
set -euo pipefail
umask 077   # Backup files include secrets and must be root-readable only.
BKSH
  then
    rm -f "$backup_tmp"
    error "$(t app.vaultwarden.error.backup_script)"
  fi
  if ! cat >> "$backup_tmp" << BKSH_VARS
BACKUP_DIR="${VW_BACKUP_DIR}"
DATA_DIR="${VW_DATA_DIR}"
ENV_FILE="${VW_ENV_FILE}"
KEEP_DAYS="${BACKUP_KEEP_DAYS}"
MSG_DATA_MISSING="$(t app.vaultwarden.backup.script.data_missing)"
MSG_SQLITE_WARNING="$(t app.vaultwarden.backup.script.sqlite_warning)"
MSG_SUCCESS="$(t app.vaultwarden.backup.script.success)"
MSG_FAILED="$(t app.vaultwarden.backup.script.failed)"
MSG_CLEANED="$(t app.vaultwarden.backup.script.cleaned)"
BKSH_VARS
  then
    rm -f "$backup_tmp"
    error "$(t app.vaultwarden.error.backup_script)"
  fi
  if ! cat >> "$backup_tmp" << 'BKSH'
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
ARCHIVE="${BACKUP_DIR}/vaultwarden_${TIMESTAMP}.tar.gz"
ARCHIVE_TMP="${ARCHIVE}.tmp"   # Write to a temp file before moving it into place.
mkdir -p "${BACKUP_DIR}"

# Refuse to create an empty archive when the data directory is missing.
if [[ ! -d "${DATA_DIR}" ]]; then
  printf '%s  '"${MSG_DATA_MISSING}"'\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${DATA_DIR}"
  exit 1
fi

# Checkpoint SQLite WAL data before archiving.
if [[ -f "${DATA_DIR}/db.sqlite3" ]]; then
  sqlite3 "${DATA_DIR}/db.sqlite3" "PRAGMA wal_checkpoint(FULL);" 2>/dev/null || true
  # Warn about database corruption without blocking file-level backups.
  INTEGRITY=$(sqlite3 "${DATA_DIR}/db.sqlite3" "PRAGMA integrity_check;" 2>/dev/null || echo "error")
  if [[ "$INTEGRITY" != "ok" ]]; then
    printf '%s  '"${MSG_SQLITE_WARNING}"'\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${INTEGRITY}"
  fi
fi

# Archive data and environment configuration, excluding logs.
DATA_PARENT=$(dirname "${DATA_DIR}")
DATA_BASE=$(basename "${DATA_DIR}")

# Include the environment file only when it exists.
TAR_EXTRA=()
[[ -f "${ENV_FILE}" ]] && TAR_EXTRA=(-C / "${ENV_FILE#/}")

# Move the completed archive into place atomically.
if tar -czf "${ARCHIVE_TMP}" \
  --exclude="*.log" \
  --exclude="*.log.*" \
  -C "${DATA_PARENT}" "${DATA_BASE}" \
  "${TAR_EXTRA[@]+"${TAR_EXTRA[@]}"}" >&2; then
  if mv "${ARCHIVE_TMP}" "${ARCHIVE}"; then
    ARCHIVE_SIZE=$(du -sh "${ARCHIVE}" | cut -f1)
    printf '%s  '"${MSG_SUCCESS}"'\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${ARCHIVE}" "${ARCHIVE_SIZE}"
  else
    rm -f "${ARCHIVE_TMP}"
    printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${MSG_FAILED}"
    exit 1
  fi
else
  rm -f "${ARCHIVE_TMP}"
  printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${MSG_FAILED}"
  exit 1
fi

# Remove expired backups.
if [[ "${KEEP_DAYS}" -gt 0 ]]; then
  REMOVED=$(find "${BACKUP_DIR}" -name "vaultwarden_*.tar.gz" -mtime +"${KEEP_DAYS}" -print -delete | wc -l)
  [[ "${REMOVED}" -gt 0 ]] && printf '%s  '"${MSG_CLEANED}"'\n' "$(date '+%Y-%m-%d %H:%M:%S')" "${REMOVED}" "${KEEP_DAYS}"
fi
BKSH
  then
    rm -f "$backup_tmp"
    error "$(t app.vaultwarden.error.backup_script)"
  fi
  if ! chmod 750 "$backup_tmp" \
      || ! chown root:root "$backup_tmp" \
      || ! mv "$backup_tmp" "$backup_script"; then
    rm -f "$backup_tmp"
    error "$(t app.vaultwarden.error.backup_script)"
  fi
}
_backup_silent() {
  local label="${1:-manual}"
  local backup_log="${VW_BACKUP_DIR}/backup.log"
  _log_backup_helper() { printf '%s  %s\n' "$(date '+%F %T')" "$1" >> "$backup_log"; }
  mkdir -p "$VW_BACKUP_DIR"
  local archive="${VW_BACKUP_DIR}/vaultwarden_${label}_$(date +%Y%m%d_%H%M%S).tar.gz"
  local archive_tmp="${archive}.tmp"
  if [[ ! -d "$VW_DATA_DIR" ]]; then
    _log_backup_helper "$(t app.vaultwarden.backup.script.data_missing "$VW_DATA_DIR")"
    warn "$(t app.vaultwarden.warn.backup_data_missing "$VW_DATA_DIR")"
    return 1
  fi
  if [[ -f "${VW_DATA_DIR}/db.sqlite3" ]]; then
    sqlite3 "${VW_DATA_DIR}/db.sqlite3" "PRAGMA wal_checkpoint(FULL);" 2>/dev/null || true
    local _ic
    _ic=$(sqlite3 "${VW_DATA_DIR}/db.sqlite3" "PRAGMA integrity_check;" 2>/dev/null || echo "error")
    if [[ "$_ic" != "ok" ]]; then
      _log_backup_helper "$(t app.vaultwarden.backup.script.sqlite_warning "$_ic")"
      warn "$(t app.vaultwarden.warn.sqlite_integrity "$_ic")"
    fi
  fi
  local tar_extra=()
  [[ -f "$VW_ENV_FILE" ]] && tar_extra=(-C / "${VW_ENV_FILE#/}")
  if tar -czf "$archive_tmp" --exclude="*.log" --exclude="*.log.*" \
    -C "$(dirname "$VW_DATA_DIR")" "$(basename "$VW_DATA_DIR")" \
    "${tar_extra[@]+"${tar_extra[@]}"}" >&2; then
    if mv "$archive_tmp" "$archive"; then
      success "$(t app.vaultwarden.success.backup_created "$archive")"
    else
      rm -f "$archive_tmp"
      _log_backup_helper "$(t app.vaultwarden.backup.script.failed)"
      warn "$(t app.vaultwarden.warn.backup_failed_continue)"
      return 1
    fi
  else
    rm -f "$archive_tmp"
    _log_backup_helper "$(t app.vaultwarden.backup.script.failed)"
    warn "$(t app.vaultwarden.warn.backup_failed_continue)"
    return 1
  fi
}
do_backup() {
  show_banner
  [[ $EUID -ne 0 ]] && error "$(t error.root_required "$0" "")"
  load_config
  acquire_lock
  step "$(t app.vaultwarden.step.manual_backup)"
  [[ ! -d "$VW_DATA_DIR" ]] && error "$(t app.vaultwarden.error.data_missing_install "$VW_DATA_DIR")"
  _backup_silent "manual"
  echo ""
  info "$(t app.vaultwarden.info.backup_list)"
  mapfile -t _bak_list < <(
    find "${VW_BACKUP_DIR}" -maxdepth 1 -name "vaultwarden_*.tar.gz" \
      -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -10 | awk '{print $2}'
  )
  if [[ ${#_bak_list[@]} -gt 0 ]]; then
    local _sz
    for _f in "${_bak_list[@]}"; do
      _sz=$(du -sh "$_f" 2>/dev/null | cut -f1 || echo "?")
      printf '  %-60s  %s\n' "$_f" "$_sz"
    done
  else
    warn "$(t app.vaultwarden.warn.no_backups)"
  fi
  echo ""
  local _total _total_size
  _total=$(find "${VW_BACKUP_DIR}" -maxdepth 1 -name "vaultwarden_*.tar.gz" 2>/dev/null | wc -l)
  _total_size=$(du -sh "${VW_BACKUP_DIR}" 2>/dev/null | cut -f1 || echo "0")
  info "$(t app.vaultwarden.info.backup_total "$_total" "$_total_size")"
  release_lock
}
do_status() {
  local DB_SIZE CERT_PATH EXPIRY DAYS HTTP_CODE
  show_banner
  load_config
  if [[ $EUID -ne 0 ]]; then
    warn "$(t app.vaultwarden.warn.non_root_status)"
    warn "$(t app.vaultwarden.warn.root_status "$0")"
  fi
  step "$(t app.vaultwarden.step.status)"
  echo -e "\n${BOLD}[$(t app.vaultwarden.status.systemd)]${NC}"
  systemctl status vaultwarden --no-pager -l 2>/dev/null | head -15 | sed 's/^/  /' \
    || echo -e "  ${RED}[✗]${NC} $(t app.vaultwarden.status.service_missing)"
  echo -e "\n${BOLD}[$(t app.vaultwarden.status.version_info)]${NC}"
  if [[ -x "$VW_BIN" ]]; then
    echo -e "  $(t app.vaultwarden.status.binary_version "$(get_installed_version)")"
    echo -e "  $(t app.vaultwarden.status.binary_path "$VW_BIN" "$(du -sh "$VW_BIN" | cut -f1)")"
    echo -e "  $(t app.vaultwarden.status.binary_time "$(stat -c '%y' "$VW_BIN" | cut -d'.' -f1)")"
  else
    echo -e "  ${RED}[✗]${NC} $(t app.vaultwarden.status.binary_missing "$VW_BIN")"
  fi
  echo -e "\n${BOLD}[$(t app.vaultwarden.status.data_dir "$VW_DATA_DIR")]${NC}"
  if [[ -d "$VW_DATA_DIR" ]]; then
    ls -lh "${VW_DATA_DIR}" 2>/dev/null | tail -n +2 | awk '{printf "  %-12s  %s\n", $5, $NF}'
    echo "  ──────────────────────────"
    echo "  $(t app.vaultwarden.status.total "$(du -sh "$VW_DATA_DIR" | cut -f1)")"
    if [[ -f "${VW_DATA_DIR}/db.sqlite3" ]]; then
      DB_SIZE=$(du -sh "${VW_DATA_DIR}/db.sqlite3" | cut -f1)
      echo -e "  $(t app.vaultwarden.status.database "$DB_SIZE")"
    fi
  else
    echo -e "  ${RED}[✗]${NC} $(t app.vaultwarden.status.data_missing)"
  fi
  echo -e "\n${BOLD}[$(t app.vaultwarden.status.backup_files)]${NC}"
  if find "${VW_BACKUP_DIR}" -maxdepth 1 -name "vaultwarden_*.tar.gz" 2>/dev/null | grep -q .; then
    ls -lht "${VW_BACKUP_DIR}"/vaultwarden_*.tar.gz 2>/dev/null | head -5 \
      | awk '{printf "  %-60s  %s\n", $NF, $5}'
    echo -e "  $(t app.vaultwarden.status.backup_count "$(find "${VW_BACKUP_DIR}" -maxdepth 1 -name "vaultwarden_*.tar.gz" 2>/dev/null | wc -l)")"
  else
    echo -e "  ${YELLOW}[!]${NC} $(t app.vaultwarden.warn.no_backups)"
  fi
  echo -e "\n${BOLD}[$(t app.vaultwarden.status.nginx)]${NC}"
  systemctl is-active nginx &>/dev/null \
    && echo -e "  ${GREEN}[✓]${NC} $(t app.vaultwarden.status.nginx_running)" \
    || echo -e "  ${RED}[✗]${NC} $(t app.vaultwarden.status.nginx_stopped)"
  echo -e "\n${BOLD}[$(t app.vaultwarden.status.fail2ban)]${NC}"
  if systemctl is-active fail2ban &>/dev/null; then
    fail2ban-client status vaultwarden 2>/dev/null | sed 's/^/  /' \
      || echo -e "  ${YELLOW}[!]${NC} $(t app.vaultwarden.status.fail2ban_jail_missing)"
  else
    echo -e "  ${RED}[✗]${NC} $(t app.vaultwarden.status.fail2ban_stopped)"
  fi
  echo -e "\n${BOLD}[$(t app.vaultwarden.status.http_health)]${NC}"
  HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}" --max-time 5 "http://127.0.0.1:${VW_PORT}/" 2>/dev/null || echo "000")
  [[ "$HTTP_CODE" =~ ^(200|302|301)$ ]] \
    && echo -e "  ${GREEN}[✓]${NC} $(t app.vaultwarden.status.local_response "$HTTP_CODE")" \
    || echo -e "  ${YELLOW}[!]${NC} $(t app.vaultwarden.status.local_response_warn "$HTTP_CODE")"
  echo -e "\n${BOLD}[$(t app.vaultwarden.status.tls)]${NC}"
  CERT_PATH="/etc/letsencrypt/live/${VW_DOMAIN}/fullchain.pem"
  if [[ -f "$CERT_PATH" ]]; then
    EXPIRY=$(openssl x509 -enddate -noout -in "$CERT_PATH" | sed 's/notAfter=//')
    DAYS=$(( ( $(date -d "$EXPIRY" +%s 2>/dev/null || echo 0) - $(date +%s) ) / 86400 ))
    if [[ $DAYS -gt 30 ]]; then
      echo -e "  ${GREEN}[✓]${NC} $(t app.vaultwarden.status.cert_valid "$DAYS" "$EXPIRY")"
    elif [[ $DAYS -gt 0 ]]; then
      echo -e "  ${YELLOW}[!]${NC} $(t app.vaultwarden.status.cert_expiring "$DAYS")"
    else
      echo -e "  ${RED}[✗]${NC} $(t app.vaultwarden.status.cert_expired "$DAYS")"
    fi
  else
    echo -e "  ${YELLOW}[!]${NC} $(t app.vaultwarden.status.cert_missing)"
  fi
  echo ""
}
do_uninstall() {
  show_banner
  preflight_check
  load_config
  acquire_lock
  [[ -z "${VW_BIN:-}"        ]] && error "$(t app.vaultwarden.error.bin_empty)"
  [[ -z "${VW_DATA_DIR:-}"   ]] && error "$(t app.vaultwarden.error.data_dir_empty)"
  [[ -z "${VW_BACKUP_DIR:-}" ]] && error "$(t app.vaultwarden.error.backup_dir_empty)"
  [[ "${VW_DATA_DIR}"   == "/" ]] && error "$(t app.vaultwarden.error.data_dir_root)"
  [[ "${VW_BACKUP_DIR}" == "/" ]] && error "$(t app.vaultwarden.error.backup_dir_root)"
  step "$(t app.vaultwarden.step.uninstall)"
  echo -e "${RED}${BOLD}"
  echo "  $(t app.vaultwarden.uninstall.removes)"
  echo "     - $(t app.vaultwarden.uninstall.binary "$VW_BIN")"
  echo "     - $(t app.vaultwarden.uninstall.systemd)"
  echo "     - $(t app.vaultwarden.uninstall.nginx)"
  echo "     - $(t app.vaultwarden.uninstall.fail2ban)"
  echo "     - $(t app.vaultwarden.uninstall.env "$VW_ENV_FILE")"
  echo "     - $(t app.vaultwarden.uninstall.cron)"
  echo "  $(t app.vaultwarden.uninstall.keep_data "$VW_DATA_DIR")"
  echo -e "${NC}"
  prompt "$(t app.vaultwarden.prompt.continue)"
  read -r _c
  [[ "$_c" != "YES" ]] && { info "$(t app.vaultwarden.info.cancelled)"; exit 0; }
  prompt "$(t app.vaultwarden.prompt.delete_data "$VW_DATA_DIR")"
  local _del_data; read -r _del_data
  local DELETE_DATA=false; [[ "${_del_data,,}" == "y" ]] && DELETE_DATA=true
  prompt "$(t app.vaultwarden.prompt.delete_backup "$VW_BACKUP_DIR")"
  local _del_bak; read -r _del_bak
  local DELETE_BACKUP=false; [[ "${_del_bak,,}" == "y" ]] && DELETE_BACKUP=true
  info "$(t app.vaultwarden.info.stop_service)"
  systemctl stop    vaultwarden 2>/dev/null || true
  systemctl disable vaultwarden 2>/dev/null || true
  rm -f /etc/systemd/system/vaultwarden.service
  systemctl daemon-reload
  success "$(t app.vaultwarden.success.removed_systemd)"
  rm -f "${VW_BIN}"
  find "$(dirname "$VW_BIN")" -maxdepth 1 -name "vaultwarden.bak.*" -type f -delete 2>/dev/null || true
  success "$(t app.vaultwarden.success.removed_binary)"
  rm -f /etc/nginx/sites-enabled/vaultwarden /etc/nginx/sites-available/vaultwarden
  if command -v nginx >/dev/null 2>&1; then
    if nginx -t >/dev/null 2>&1; then
      systemctl reload nginx >/dev/null 2>&1 || nginx -t >&2 || true
    else
      nginx -t >&2 || true
    fi
  fi
  success "$(t app.vaultwarden.success.removed_nginx)"
  rm -f /etc/fail2ban/filter.d/vaultwarden.conf \
        /etc/fail2ban/filter.d/vaultwarden-admin.conf \
        /etc/fail2ban/jail.d/vaultwarden.conf
  if ! systemctl restart fail2ban 2>/dev/null; then
    warn "$(t app.vaultwarden.warn.fail2ban_restart)"
  fi
  success "$(t app.vaultwarden.success.removed_fail2ban)"
  rm -f /etc/cron.d/vaultwarden-backup \
        /usr/local/bin/vaultwarden-backup \
        /etc/logrotate.d/vaultwarden
  success "$(t app.vaultwarden.success.removed_scheduled)"
  rm -f "$VW_ENV_FILE" "$CONF_FILE"
  success "$(t app.vaultwarden.success.removed_config)"
  local _log_dir
  _log_dir=$(dirname "$VW_LOG_FILE")
  if [[ -n "$_log_dir" && "$_log_dir" != "." && "$_log_dir" != "/" && -d "$_log_dir" ]]; then
    safe_rm_dir "$_log_dir" "LOG_DIR"
    success "$(t app.vaultwarden.success.deleted_log "$_log_dir")"
  else
    warn "$(t app.vaultwarden.warn.log_path "$_log_dir")"
  fi
  if $DELETE_DATA; then
    safe_rm_dir "$VW_DATA_DIR" "VW_DATA_DIR"
    success "$(t app.vaultwarden.success.deleted_data "$VW_DATA_DIR")"
  else
    info "$(t app.vaultwarden.info.kept_data "$VW_DATA_DIR")"
  fi
  if $DELETE_BACKUP; then
    safe_rm_dir "$VW_BACKUP_DIR" "VW_BACKUP_DIR"
    success "$(t app.vaultwarden.success.deleted_backup "$VW_BACKUP_DIR")"
  else
    info "$(t app.vaultwarden.info.kept_backup "$VW_BACKUP_DIR")"
  fi
  if $DELETE_DATA && id "$VW_USER" &>/dev/null; then
    if userdel "$VW_USER" 2>/dev/null; then
      success "$(t app.vaultwarden.success.deleted_user "$VW_USER")"
    fi
  fi
  echo ""
  echo -e "${BOLD}${GREEN}  $(t app.vaultwarden.success.uninstalled)${NC}"
  if ! $DELETE_DATA; then
    echo -e "  ${YELLOW}[hint]${NC} $(t app.vaultwarden.hint.data_kept "$VW_DATA_DIR")"
    echo -e "  ${YELLOW}[hint]${NC} $(t app.vaultwarden.hint.remove_data "$VW_DATA_DIR")"
  fi
  echo ""
}
