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
  [[ $EUID -ne 0 ]] && error "请用 root 权限运行：sudo bash $0"
  if ! command -v apt-get &>/dev/null; then
    error "此脚本仅支持 Debian / Ubuntu（apt-get 未找到）"
  fi
  ARCH=$(uname -m)
  case $ARCH in
    x86_64)  : ;;
    aarch64) : ;;
    armv7l)  : ;;
    *) error "不支持的架构：$ARCH（支持 x86_64 / aarch64 / armv7l）" ;;
  esac
}
LOCK_FILE="/var/lock/vaultwarden-deploy.lock"
check_connectivity() {
  check_connectivity_urls \
    "https://auth.docker.io/token" \
    "https://registry-1.docker.io/v2/" \
    "https://api.github.com" && return 0
  error "网络不通，无法访问 Docker Registry / GitHub，请检查网络或代理后重试"
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
  [[ -x "$VW_BIN" ]] && "$VW_BIN" --version 2>/dev/null | awk '{print $2}' || echo "未安装"
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
  info "下载 docker-image-extract 工具..."
  curl -fsSL --max-time 30 -o "${workdir}/docker-image-extract" "$EXTRACT_TOOL_URL" \
    || error "无法下载 docker-image-extract，请检查网络连接"
  [[ -s "${workdir}/docker-image-extract" ]] || error "docker-image-extract 下载后为空文件"
  head -1 "${workdir}/docker-image-extract" | grep -q '^#!' \
    || error "docker-image-extract 不是合法的 shell 脚本（shebang 缺失），可能下载损坏"
  local _die_size
  _die_size=$(wc -c < "${workdir}/docker-image-extract")
  [[ "$_die_size" -lt 4096 ]] \
    && error "docker-image-extract 文件过小（${_die_size} 字节），疑似下载不完整或被篡改"
  grep -q 'registry' "${workdir}/docker-image-extract" \
    || error "docker-image-extract 内容异常（缺少 registry 关键字），疑似被篡改，已中止"
  if [[ -n "${EXTRACT_TOOL_SHA256:-}" ]]; then
    local _actual_sha256
    _actual_sha256=$(sha256sum "${workdir}/docker-image-extract" | awk '{print $1}')
    if [[ "$_actual_sha256" != "$EXTRACT_TOOL_SHA256" ]]; then
      error "docker-image-extract SHA256 校验失败！\n  期望: ${EXTRACT_TOOL_SHA256}\n  实际: ${_actual_sha256}\n  请更新脚本中的 EXTRACT_TOOL_SHA256 或检查网络安全性"
    fi
    success "docker-image-extract SHA256 校验通过"
  else
    warn "未配置 EXTRACT_TOOL_SHA256，跳过 checksum 校验（建议为生产环境配置此项）"
  fi
  chmod +x "${workdir}/docker-image-extract"
  info "从镜像仓库提取 ${VW_IMAGE_REPO}:${VW_IMAGE_TAG}（平台：${platform}）..."
  info "（首次下载需要几分钟，请耐心等待）"
  local out_dir="${workdir}/image_output"
  mkdir -p "$out_dir"
  bash "${workdir}/docker-image-extract" \
    -p "$platform" \
    -o "$out_dir" \
    "${VW_IMAGE_REPO}:${VW_IMAGE_TAG}" >&2 \
    || error "镜像提取失败，请检查网络或稍后重试"
  local bin_path
  bin_path=$(find "$out_dir" -type f -name "vaultwarden" | head -1)
  [[ -z "$bin_path" ]] && error "未在镜像中找到 vaultwarden 二进制"
  local _bin_size
  _bin_size=$(wc -c < "$bin_path")
  [[ "$_bin_size" -lt 1048576 ]] \
    && error "提取的 vaultwarden 二进制过小（${_bin_size} 字节），疑似不完整或被篡改"
  if ! head -c 4 "$bin_path" | grep -qP '^\x7fELF' 2>/dev/null; then
    local _magic
    _magic=$(od -A n -t x1 -N 4 "$bin_path" 2>/dev/null | tr -d ' \n' || true)
    [[ "$_magic" != "7f454c46" ]] \
      && error "提取的文件不是合法的 ELF 二进制（magic bytes 不匹配），疑似下载损坏"
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
      error "ELF e_machine 不匹配！期望 ${_expected_em}（${platform}），实际 ${_actual_em}。\n  镜像平台参数可能有误，或镜像 manifest 解析异常，请重试"
    fi
  fi
  chmod +x "$bin_path"
  local webvault_path
  webvault_path=$(find "$out_dir" -type d -name "web-vault" | head -1)
  echo "$webvault_path" > "${workdir}/.webvault_path"
  echo "$bin_path"
}
do_install() {
  show_banner
  preflight_check
  acquire_lock
  check_connectivity
  local _c
  if [[ -x "$VW_BIN" ]]; then
    warn "检测到 Vaultwarden 已安装（${VW_BIN}），版本：$(get_installed_version)"
    warn "重新安装会覆盖现有二进制和配置（数据目录保留）。"
    prompt "是否强制重新安装？（y/N）："
    read -r _c; [[ "${_c,,}" != "y" ]] && { info "已取消，如需更新请使用 update 命令"; exit 0; }
  fi
  step "配置向导"
  if [[ "$VW_DOMAIN" == "vault.example.com" ]]; then
    while true; do
      prompt "请输入你的域名（如 vault.yourdomain.com）："
      local _input; read -r _input
      [[ -z "$_input" ]] && { warn "域名不能为空，请重新输入"; continue; }
      if [[ ! "$_input" =~ ^[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?(\.[a-zA-Z0-9]([a-zA-Z0-9\-]{0,61}[a-zA-Z0-9])?)*\.[a-zA-Z]{2,}$ ]]; then
        warn "域名格式无效（${_input}），请重新输入"
        continue
      fi
      VW_DOMAIN="$_input"
      break
    done
  fi
  if [[ "$ENABLE_HTTPS" == "true" ]] && [[ -z "$CERTBOT_EMAIL" ]]; then
    while true; do
      prompt "请输入 Let's Encrypt 通知邮箱："
      local _email; read -r _email
      [[ -z "$_email" ]] && { warn "邮箱不能为空，请重新输入"; continue; }
      if [[ ! "$_email" =~ ^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$ ]]; then
        warn "邮箱格式无效（${_email}），请重新输入"
        continue
      fi
      CERTBOT_EMAIL="$_email"
      break
    done
  fi
  echo ""
  if ! [[ "$VW_PORT" =~ ^[0-9]+$ ]] || [[ "$VW_PORT" -lt 1 || "$VW_PORT" -gt 65535 ]]; then
    error "VW_PORT 无效：'${VW_PORT}'，请在脚本顶部设置 1-65535 之间的端口号"
  fi
  info "域名     : ${VW_DOMAIN}"
  info "监听端口 : ${VW_PORT}（仅本机，经 Nginx 反代）"
  info "二进制   : ${VW_BIN}"
  info "数据目录 : ${VW_DATA_DIR}"
  info "Web Vault: ${VW_WEB_DIR}"
  info "运行用户 : ${VW_USER}"
  info "HTTPS    : ${ENABLE_HTTPS}"
  echo ""
  prompt "配置是否正确？（y/N）："
  read -r _c; [[ "${_c,,}" != "y" ]] && { info "已取消，请修改脚本顶部配置项后重试"; exit 0; }
  step "Step 1  安装系统依赖"
  DEBIAN_FRONTEND=noninteractive apt-get update -qq \
    || warn "apt-get update 部分仓库失败，将尝试继续安装（可能影响包版本）"
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    curl wget ca-certificates \
    nginx certbot python3-certbot-nginx \
    sqlite3 argon2 openssl fail2ban \
    logrotate
  success "系统依赖安装完成"
  step "Step 2  创建系统用户与目录"
  if ! id "$VW_USER" &>/dev/null; then
    useradd --system --no-create-home \
      --home-dir "$VW_DATA_DIR" \
      --shell /usr/sbin/nologin \
      --comment "Vaultwarden Service Account" \
      "$VW_USER"
    success "系统用户 ${VW_USER} 已创建"
  else
    warn "用户 ${VW_USER} 已存在，跳过"
  fi
  mkdir -p "$VW_DATA_DIR" "$(dirname "$VW_LOG_FILE")" "$VW_BACKUP_DIR"
  chown -R "${VW_USER}:${VW_GROUP}" "$VW_DATA_DIR" "$(dirname "$VW_LOG_FILE")"
  chmod 750 "$VW_DATA_DIR"
  success "目录已创建并设置权限"
  step "Step 3  提取 Vaultwarden 静态二进制"
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
  success "二进制提取成功：${BIN_PATH}"
  mkdir -p "$VW_BIN_DIR"
  install -m 755 -o root -g root "$BIN_PATH" "$VW_BIN"
  success "二进制已安装：${VW_BIN}"
  VW_VER=$("$VW_BIN" --version 2>/dev/null || echo "unknown")
  info "Vaultwarden 版本：${VW_VER}"
  step "Step 4  安装 Web Vault"
  if [[ -n "$EXTRACTED_WEBVAULT_PATH" && -d "$EXTRACTED_WEBVAULT_PATH" ]]; then
    info "使用镜像中提取的 Web Vault（与二进制版本一致）..."
    rm -rf "$VW_WEB_DIR"
    cp -a "$EXTRACTED_WEBVAULT_PATH" "$VW_WEB_DIR"
    success "Web Vault 已安装（来自 Alpine 镜像）"
  else
    info "从 GitHub 下载最新 Web Vault..."
    local _wv_ver="${WEB_VAULT_VER:-}"
    if [[ -z "$_wv_ver" ]]; then
      _wv_ver=$(get_latest_webvault_ver)
      [[ -z "$_wv_ver" ]] && error "无法获取 Web Vault 版本，请检查网络"
    fi
    info "Web Vault 版本：v${_wv_ver}"
    local WV_URL="https://github.com/dani-garcia/bw_web_builds/releases/download/v${_wv_ver}/bw_web_v${_wv_ver}.tar.gz"
    info "下载：${WV_URL}"
    wget -q --show-progress -O "${WORK_DIR}/web-vault.tar.gz" "$WV_URL" \
      || error "Web Vault 下载失败"
    rm -rf "$VW_WEB_DIR"
    mkdir -p "$(dirname "$VW_WEB_DIR")"
    tar -xzf "${WORK_DIR}/web-vault.tar.gz" -C "$(dirname "$VW_WEB_DIR")"
    success "Web Vault v${_wv_ver} 已安装"
  fi
  chown -R "${VW_USER}:${VW_GROUP}" "$VW_WEB_DIR"
  chmod -R 750 "$VW_WEB_DIR"
  info "Web Vault 位置：${VW_WEB_DIR}"
  step "Step 5  生成 Admin Token（Argon2id 哈希）"
  local ADMIN_PLAIN ADMIN_HASH SALT
  ADMIN_PLAIN=$(openssl rand -hex 24)
  info "使用 vaultwarden hash --preset owasp 生成哈希..."
  ADMIN_HASH=$(printf '%s' "$ADMIN_PLAIN" | "$VW_BIN" hash --preset owasp 2>/dev/null \
    | grep '^\$argon2' | head -1 || true)
  if [[ -z "$ADMIN_HASH" ]]; then
    warn "vaultwarden hash 输出解析失败，回退至 argon2 CLI（OWASP preset）..."
    SALT=$(openssl rand -base64 32)
    ADMIN_HASH=$(printf '%s' "$ADMIN_PLAIN" | \
      argon2 "$SALT" -e -id -k 19456 -t 2 -p 1 -l 32 2>/dev/null || true)
    [[ -z "$ADMIN_HASH" ]] && error "argon2 CLI 也失败，无法生成安全的 Admin Token。\n  请确认已安装 argon2：apt-get install -y argon2\n  修复后重新运行 install。（使用明文 Token 在新版 Vaultwarden 中已废弃且不安全，拒绝继续）"
  fi
  success "Admin Token 生成完成"
  step "Step 6  写入 ${VW_ENV_FILE}"
  cat > "$VW_ENV_FILE" << ENV
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
  chmod 600 "$VW_ENV_FILE"
  chown root:root "$VW_ENV_FILE"
  success "环境配置文件已写入：${VW_ENV_FILE}（权限 600）"
  step "Step 7  创建 systemd 服务"
  cat > /etc/systemd/system/vaultwarden.service << UNIT
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
  systemctl daemon-reload
  systemctl enable vaultwarden --quiet
  success "systemd 服务已创建并设为开机自启"
  step "Step 8  启动 Vaultwarden 服务"
  if ss -ltn 2>/dev/null | grep -qE ":${VW_PORT}[[:space:]]"; then
    local _port_owner
    _port_owner=$(ss -ltnp 2>/dev/null | grep ":${VW_PORT}" | awk '{print $NF}' | head -1 || echo "未知进程")
    warn "端口 ${VW_PORT} 已被占用（${_port_owner}）"
    warn "若不是旧的 vaultwarden 进程，请先释放端口再安装，否则服务将无法启动"
  fi
  systemctl start vaultwarden
  if wait_for_service vaultwarden 20; then
    success "Vaultwarden 服务启动成功"
    systemctl status vaultwarden --no-pager -l | head -12 | sed 's/^/  /'
  else
    warn "服务在 20 秒内未能正常启动，正在清理已安装文件..."
    systemctl stop    vaultwarden 2>/dev/null || true
    systemctl disable vaultwarden 2>/dev/null || true
    rm -f /etc/systemd/system/vaultwarden.service
    systemctl daemon-reload 2>/dev/null || true
    rm -f "$VW_BIN"
    error "安装失败：服务无法启动，已回滚二进制与 systemd 单元。\n  调试命令：journalctl -u vaultwarden -n 30 --no-pager\n  （数据目录、env 文件、Nginx 配置已保留，修复原因后重新 install）"
  fi
  step "Step 9  配置 Nginx 反向代理（HTTP-only，HTTPS 由 Step 10 certbot 补全）"
  local NGINX_CONF="/etc/nginx/sites-available/vaultwarden"
  mkdir -p /var/www/certbot
  cat > "$NGINX_CONF" << NGINX
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
  ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/vaultwarden
  if [[ -L /etc/nginx/sites-enabled/default ]]; then
    warn "已移除 Nginx 默认站点（/etc/nginx/sites-enabled/default）。如有其他站点依赖它，请手动恢复。"
    rm -f /etc/nginx/sites-enabled/default
  fi
  nginx -t || error "Nginx 配置验证失败（HTTP 阶段）"
  success "Nginx HTTP 配置完成"
  step "Step 10  申请 HTTPS 证书"
  systemctl enable nginx --quiet
  systemctl restart nginx
  if ! wait_for_service nginx 10; then
    error "Nginx 未能在 10 秒内成功启动，请检查配置：nginx -t\n  journalctl -u nginx -n 20 --no-pager"
  fi
  success "Nginx 已就绪，继续申请证书"
  if [[ "$ENABLE_HTTPS" == "true" ]]; then
    info "申请证书（${VW_DOMAIN} / ${CERTBOT_EMAIL}）..."
    if certbot certonly --webroot \
      -w /var/www/certbot \
      -d "$VW_DOMAIN" \
      --email "$CERTBOT_EMAIL" \
      --agree-tos \
      --non-interactive 2>&1; then
      success "Let's Encrypt 证书申请成功"
    else
      warn "Certbot 证书申请失败（见上方输出）"
      warn "请解决 DNS/防火墙问题后手动运行：certbot certonly --webroot -w /var/www/certbot -d ${VW_DOMAIN} --email ${CERTBOT_EMAIL} --agree-tos --non-interactive"
    fi
    if systemctl list-timers certbot* 2>/dev/null | grep -q certbot; then
      success "Certbot 自动续签定时器已就绪"
    else
      if crontab -l 2>/dev/null | grep -q "certbot renew"; then
        success "Certbot 自动续签 cron 条目已存在，跳过"
      else
        (crontab -l 2>/dev/null; echo "30 2 * * * certbot renew --quiet --post-hook 'systemctl reload nginx'") | crontab -
        success "Certbot 自动续签（每天 02:30）已加入 crontab"
      fi
    fi
    local CERT_PATH_FULL="/etc/letsencrypt/live/${VW_DOMAIN}/fullchain.pem"
    local CERT_KEY_FULL="/etc/letsencrypt/live/${VW_DOMAIN}/privkey.pem"
    if [[ -f "$CERT_PATH_FULL" ]]; then
      local _nginx_ver _http2_directive _listen_https
      _nginx_ver=$(nginx -v 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "0.0.0")
      if [[ "$_nginx_ver" == "0.0.0" ]]; then
        warn "无法检测 Nginx 版本，默认使用旧版 http2 语法（listen 行附加）"
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
      cat > "$NGINX_CONF" << NGINX2
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
      {
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
      } >> "$NGINX_CONF"
      nginx -t && systemctl reload nginx \
        && success "Nginx HTTPS 完整配置已生效" \
        || warn "Nginx HTTPS 配置测试失败，请检查：nginx -t"
    else
      warn "证书文件未找到，跳过 HTTPS 配置写入，当前仍使用 HTTP 模式"
    fi
  else
    warn "跳过 HTTPS 配置（Vaultwarden Web Crypto API 需要 HTTPS！）"
  fi
  step "Step 11  配置 Fail2Ban 防暴力破解"
  cat > /etc/fail2ban/filter.d/vaultwarden.conf << F2B
[INCLUDES]
before = common.conf

[Definition]
failregex = ^.*Username or password is incorrect\. Try again\. IP: <ADDR>.*$
            ^.*TOTP, Duo or recovery code is incorrect\. Try again\. IP: <ADDR>.*$
ignoreregex =
F2B
  cat > /etc/fail2ban/filter.d/vaultwarden-admin.conf << F2B2
[INCLUDES]
before = common.conf

[Definition]
failregex = ^.*Invalid admin token\. IP: <ADDR>.*$
ignoreregex =
F2B2
  cat > /etc/fail2ban/jail.d/vaultwarden.conf << JAIL
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
  systemctl enable fail2ban --quiet
  systemctl restart fail2ban
  success "Fail2Ban 已配置（登录失败 5 次/小时封禁 1h，Admin 3 次/天封禁 24h）"
  step "Step 12  配置日志轮转"
  cat > /etc/logrotate.d/vaultwarden << LOGR
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
  success "日志轮转已配置（每日轮转，保留 14 天，自动压缩）"
  step "Step 13  配置防火墙"
  local FW_DONE=false
  if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
    ufw allow "Nginx Full" >/dev/null 2>&1 && success "ufw 已放行 HTTP/HTTPS" && FW_DONE=true
  fi
  if ! $FW_DONE && command -v iptables &>/dev/null; then
    for P in 80 443; do
      iptables -C INPUT -p tcp --dport "$P" -j ACCEPT 2>/dev/null \
        || iptables -A INPUT -p tcp --dport "$P" -j ACCEPT
    done
    success "iptables 已放行 80/443" && FW_DONE=true
    if command -v netfilter-persistent &>/dev/null; then
      netfilter-persistent save 2>/dev/null && success "iptables 规则已持久化（netfilter-persistent）" || true
    else
      warn "iptables 规则未持久化（重启后失效）。建议：apt-get install -y iptables-persistent && netfilter-persistent save"
    fi
  fi
  $FW_DONE || warn "未检测到活跃防火墙，请手动放行 80/443 端口"
  step "Step 14  配置自动备份（每日 03:30）"
  _write_backup_script
  echo "30 3 * * * root /bin/bash /usr/local/bin/vaultwarden-backup >> ${VW_BACKUP_DIR}/backup.log 2>&1" \
    > /etc/cron.d/vaultwarden-backup
  chmod 644 /etc/cron.d/vaultwarden-backup
  success "自动备份已配置（每日 03:30，保留 ${BACKUP_KEEP_DAYS} 天）"
  step "Step 15  健康检查"
  save_config
  local _hc_elapsed=0
  local HTTP_CODE
  until HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}" --max-time 5 "http://127.0.0.1:${VW_PORT}/" || echo "000") \
      && [[ "$HTTP_CODE" =~ ^(200|301|302)$ ]]; do
    sleep 1; _hc_elapsed=$(( _hc_elapsed + 1 ))
    [[ $_hc_elapsed -ge 10 ]] && break
  done
  if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "302" ]]; then
    success "Vaultwarden 本地接口响应正常（HTTP ${HTTP_CODE}）"
  else
    warn "本地健康检查返回 ${HTTP_CODE}，服务可能仍在初始化，稍后再试"
    warn "调试命令：journalctl -u vaultwarden -n 30 --no-pager"
  fi
  local INTERNAL_IP PROTO INSTALLED_VER
  INTERNAL_IP=$(hostname -I | awk '{print $1}')
  if [[ "$ENABLE_HTTPS" == "true" ]]; then PROTO="https"; else PROTO="http"; fi
  INSTALLED_VER=$(get_installed_version)
  local _token_tmp
  _token_tmp=$(mktemp /tmp/vw_token_XXXXXX)
  chmod 600 "$_token_tmp"
  printf '%s\n' "$ADMIN_PLAIN" > "$_token_tmp"
  echo ""
  echo -e "${BOLD}${GREEN}"
  echo "  ╔═══════════════════════════════════════════════════════════════╗"
  echo "  ║             🎉  Vaultwarden 部署完成！（二进制版）            ║"
  echo "  ╠═══════════════════════════════════════════════════════════════╣"
  echo -e "  ║  访问地址    ${CYAN}${PROTO}://${VW_DOMAIN}${GREEN}"
  echo -e "  ║  Admin 面板  ${CYAN}${PROTO}://${VW_DOMAIN}/admin${GREEN}"
  echo -e "  ║  内网测试    ${CYAN}http://${INTERNAL_IP}:${VW_PORT}${GREEN}"
  echo "  ╠═══════════════════════════════════════════════════════════════╣"
  echo -e "  ║  版本        ${YELLOW}${INSTALLED_VER}${GREEN}"
  echo -e "  ║  二进制      ${YELLOW}${VW_BIN}${GREEN}"
  echo -e "  ║  数据目录    ${YELLOW}${VW_DATA_DIR}${GREEN}"
  echo -e "  ║  Web Vault   ${YELLOW}${VW_WEB_DIR}${GREEN}"
  echo -e "  ║  环境配置    ${YELLOW}${VW_ENV_FILE}${GREEN}  (600 权限)"
  echo -e "  ║  日志        ${YELLOW}${VW_LOG_FILE}${GREEN}"
  echo -e "  ║  备份目录    ${YELLOW}${VW_BACKUP_DIR}${GREEN}"
  echo "  ╠═══════════════════════════════════════════════════════════════╣"
  echo -e "  ║  ${RED}${BOLD}⚠  Admin 明文 Token 已写入临时文件（仅 root 可读）${GREEN}         ║"
  echo -e "  ║  查看命令：${YELLOW}cat ${_token_tmp}${GREEN}"
  echo -e "  ║  查看后请立即运行：${YELLOW}rm -f ${_token_tmp}${GREEN}"
  echo "  ╚═══════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
  echo -e "  ${BOLD}⚡  首次使用步骤：${NC}"
  echo ""
  echo -e "  ${CYAN}# 0. 查看并保存 Admin Token（查看后立即删除临时文件！）${NC}"
  echo -e "     cat ${_token_tmp}"
  echo -e "     rm -f ${_token_tmp}"
  echo ""
  echo -e "  ${CYAN}# 1. 用浏览器访问，创建你的账号${NC}"
  echo -e "     ${PROTO}://${VW_DOMAIN}  →  点击「创建账号」"
  echo ""
  echo -e "  ${CYAN}# 2. 完成后关闭公开注册（两种方式二选一）${NC}"
  echo -e "     方式 A - Admin 面板：${PROTO}://${VW_DOMAIN}/admin → General settings"
  echo -e "     方式 B - 编辑配置文件：sed -i 's/SIGNUPS_ALLOWED=true/SIGNUPS_ALLOWED=false/' ${VW_ENV_FILE}"
  echo -e "              然后：systemctl restart vaultwarden"
  echo ""
  echo -e "  ${CYAN}# 3. 配置 Bitwarden 客户端（浏览器扩展 / App）连接自托管${NC}"
  echo -e "     登录页 → 选择「自托管」→ 服务器地址填：${PROTO}://${VW_DOMAIN}"
  echo ""
  echo -e "  ${CYAN}# 4. 常用管理命令${NC}"
  echo -e "     systemctl status vaultwarden          # 查看服务状态"
  echo -e "     journalctl -u vaultwarden -f          # 实时日志"
  echo -e "     systemctl restart vaultwarden         # 重启服务"
  echo -e "     vaultwarden-backup                    # 立即备份"
  echo ""
  echo -e "  ${YELLOW}${BOLD}[重要]${NC} Admin Token 临时文件查看后请立即删除，避免遗留在磁盘！"
  echo ""
}
do_update() {
  show_banner
  preflight_check
  load_config
  acquire_lock
  check_connectivity
  step "更新 Vaultwarden 二进制与 Web Vault"
  [[ ! -x "$VW_BIN" ]] && error "未检测到已安装的 Vaultwarden，请先执行 install"
  local OLD_VER NEW_VER PLATFORM WORK_DIR NEW_BIN_PATH EXTRACTED_WEBVAULT_PATH
  OLD_VER=$(get_installed_version)
  info "当前版本：${OLD_VER}"
  info "更新前自动备份数据..."
  _backup_silent "pre-update"
  local _pre_update_svc_state
  _pre_update_svc_state=$(systemctl is-active vaultwarden 2>/dev/null || echo "inactive")
  if [[ "$_pre_update_svc_state" == "failed" ]]; then
    warn "注意：更新前 vaultwarden 服务处于 failed 状态，本次更新将同时重置该故障状态"
    warn "如果更新后仍有问题，请检查更新前已存在的错误：journalctl -u vaultwarden -n 50 --no-pager"
  fi
  info "停止 Vaultwarden 服务..."
  systemctl stop --timeout=30 vaultwarden 2>/dev/null || true
  case $ARCH in
    x86_64)  PLATFORM="linux/amd64"  ;;
    aarch64) PLATFORM="linux/arm64"  ;;
    armv7l)  PLATFORM="linux/arm/v7" ;;
    *)       error "不支持的架构：$ARCH" ;;
  esac
  WORK_DIR=$(mktemp -d /tmp/vaultwarden_update_XXXXXX)
  _cleanup_update() {
    flock -u 9 2>/dev/null; exec 9>&- 2>/dev/null
    [[ -d "${WORK_DIR:-}" ]] && rm -rf "$WORK_DIR"
  }
  trap '_cleanup_update' EXIT
  step "提取新版本二进制"
  NEW_BIN_PATH=$(extract_binary "$WORK_DIR" "$PLATFORM")
  EXTRACTED_WEBVAULT_PATH=$(cat "${WORK_DIR}/.webvault_path" 2>/dev/null || true)
  cp "$VW_BIN" "${VW_BIN}.bak.$(date +%Y%m%d%H%M%S)"
  mkdir -p "$VW_BIN_DIR"
  install -m 755 -o root -g root "$NEW_BIN_PATH" "$VW_BIN"
  success "二进制已更新"
  NEW_VER=$(get_installed_version)
  step "更新 Web Vault"
  local _wv_bak_ts="${VW_WEB_DIR}.bak.$(date +%Y%m%d%H%M%S)"
  if [[ -n "$EXTRACTED_WEBVAULT_PATH" && -d "$EXTRACTED_WEBVAULT_PATH" ]]; then
    [[ -d "$VW_WEB_DIR" ]] && mv "$VW_WEB_DIR" "$_wv_bak_ts"
    cp -a "$EXTRACTED_WEBVAULT_PATH" "$VW_WEB_DIR"
    chown -R "${VW_USER}:${VW_GROUP}" "$VW_WEB_DIR"
    success "Web Vault 已更新（来自 Alpine 镜像）"
  else
    local _fetched_wv_ver
    _fetched_wv_ver=$(get_latest_webvault_ver)
    if [[ -n "$_fetched_wv_ver" ]]; then
      local WV_URL="https://github.com/dani-garcia/bw_web_builds/releases/download/v${_fetched_wv_ver}/bw_web_v${_fetched_wv_ver}.tar.gz"
      if wget -q --show-progress -O "${WORK_DIR}/web-vault.tar.gz" "$WV_URL"; then
        [[ -d "$VW_WEB_DIR" ]] && mv "$VW_WEB_DIR" "$_wv_bak_ts"
        if tar -xzf "${WORK_DIR}/web-vault.tar.gz" -C "$(dirname "$VW_WEB_DIR")"; then
          chown -R "${VW_USER}:${VW_GROUP}" "$VW_WEB_DIR"
          success "Web Vault v${_fetched_wv_ver} 已更新"
        else
          warn "Web Vault 解压失败，尝试恢复旧版本..."
          [[ -d "$_wv_bak_ts" ]] && mv "$_wv_bak_ts" "$VW_WEB_DIR" || true
        fi
      else
        warn "Web Vault 下载失败，跳过 Web Vault 更新"
      fi
    else
      warn "无法获取 Web Vault 版本，跳过 Web Vault 更新"
    fi
  fi
  if ss -ltn 2>/dev/null | grep -qE ":${VW_PORT}[[:space:]]"; then
    local _port_owner_upd
    _port_owner_upd=$(ss -ltnp 2>/dev/null | grep ":${VW_PORT}" | awk '{print $NF}' | head -1 || echo "未知进程")
    warn "端口 ${VW_PORT} 仍被占用（${_port_owner_upd}），服务可能无法绑定端口"
  fi
  systemctl start vaultwarden
  if wait_for_service vaultwarden 20; then
    success "Vaultwarden 服务重启成功"
    if [[ "$OLD_VER" != "$NEW_VER" ]]; then
      success "版本已更新：${OLD_VER}  →  ${NEW_VER}"
    else
      success "已是最新版本（${NEW_VER}），无需更新"
    fi
  else
    warn "服务重启失败！正在回滚二进制..."
    NEWEST_BAK=$(find "$(dirname "$VW_BIN")" -maxdepth 1 \
      -name "vaultwarden.bak.*" -type f -printf '%T@ %p\n' 2>/dev/null \
      | sort -rn | awk 'NR==1{print $2}' || true)
    if [[ -n "$NEWEST_BAK" ]]; then
      install -m 755 -o root -g root "$NEWEST_BAK" "$VW_BIN"
      if [[ -d "$_wv_bak_ts" ]]; then
        rm -rf "$VW_WEB_DIR"
        mv "$_wv_bak_ts" "$VW_WEB_DIR"
        chown -R "${VW_USER}:${VW_GROUP}" "$VW_WEB_DIR"
        chmod -R 750 "$VW_WEB_DIR"
        warn "Web Vault 已回滚"
      fi
      systemctl start vaultwarden
      if wait_for_service vaultwarden 20; then
        success "回滚完成，服务已恢复至旧版本（${OLD_VER}）"
        error "更新失败，已回滚至旧版本 ${OLD_VER}。\n  如需排查新版本问题：journalctl -u vaultwarden -n 50 --no-pager\n  新版本二进制备份保留在：$(find "$(dirname "$VW_BIN")" -maxdepth 1 -name "vaultwarden.bak.*" -type f | sort -r | head -1 || echo '未知')"
      else
        error "回滚后服务仍无法启动，请手动检查：journalctl -u vaultwarden -n 30 --no-pager"
      fi
    else
      error "未找到备份二进制，回滚失败！请手动检查：journalctl -u vaultwarden -n 30 --no-pager"
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
    info "已清理 ${#_old_wv_baks[@]} 个过期 web-vault 备份目录（保留最近 3 个）"
  fi
  save_config
}
_write_backup_script() {
  cat > /usr/local/bin/vaultwarden-backup << 'BKSH'
#!/bin/bash
# Auto-generated Vaultwarden backup script.
set -euo pipefail
umask 077   # Backup files include secrets and must be root-readable only.
BKSH
  cat >> /usr/local/bin/vaultwarden-backup << BKSH_VARS
BACKUP_DIR="${VW_BACKUP_DIR}"
DATA_DIR="${VW_DATA_DIR}"
ENV_FILE="${VW_ENV_FILE}"
KEEP_DAYS="${BACKUP_KEEP_DAYS}"
BKSH_VARS
  cat >> /usr/local/bin/vaultwarden-backup << 'BKSH'
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
ARCHIVE="${BACKUP_DIR}/vaultwarden_${TIMESTAMP}.tar.gz"
ARCHIVE_TMP="${ARCHIVE}.tmp"   # Write to a temp file before moving it into place.
mkdir -p "${BACKUP_DIR}"

# Refuse to create an empty archive when the data directory is missing.
if [[ ! -d "${DATA_DIR}" ]]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S')  [ERROR] 数据目录不存在（${DATA_DIR}），备份已中止"
  exit 1
fi

# Checkpoint SQLite WAL data before archiving.
if [[ -f "${DATA_DIR}/db.sqlite3" ]]; then
  sqlite3 "${DATA_DIR}/db.sqlite3" "PRAGMA wal_checkpoint(FULL);" 2>/dev/null || true
  # Warn about database corruption without blocking file-level backups.
  INTEGRITY=$(sqlite3 "${DATA_DIR}/db.sqlite3" "PRAGMA integrity_check;" 2>/dev/null || echo "error")
  if [[ "$INTEGRITY" != "ok" ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S')  [WARN] SQLite 完整性校验失败（${INTEGRITY}），备份仍将继续但数据库可能已损坏"
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
  "${TAR_EXTRA[@]+"${TAR_EXTRA[@]}"}" 2>&1; then
  mv "${ARCHIVE_TMP}" "${ARCHIVE}"
  ARCHIVE_SIZE=$(du -sh "${ARCHIVE}" | cut -f1)
  echo "$(date '+%Y-%m-%d %H:%M:%S')  [OK] 备份成功：${ARCHIVE} (${ARCHIVE_SIZE})"
else
  rm -f "${ARCHIVE_TMP}"
  echo "$(date '+%Y-%m-%d %H:%M:%S')  [ERROR] 备份失败，临时文件已清理"
  exit 1
fi

# Remove expired backups.
if [[ "${KEEP_DAYS}" -gt 0 ]]; then
  REMOVED=$(find "${BACKUP_DIR}" -name "vaultwarden_*.tar.gz" -mtime +"${KEEP_DAYS}" -print -delete | wc -l)
  [[ "${REMOVED}" -gt 0 ]] && echo "$(date '+%Y-%m-%d %H:%M:%S')  [OK] 已清理 ${REMOVED} 个过期备份（>${KEEP_DAYS} 天）"
fi
BKSH
  chmod +x /usr/local/bin/vaultwarden-backup
}
_backup_silent() {
  local label="${1:-manual}"
  mkdir -p "$VW_BACKUP_DIR"
  local archive="${VW_BACKUP_DIR}/vaultwarden_${label}_$(date +%Y%m%d_%H%M%S).tar.gz"
  local archive_tmp="${archive}.tmp"
  if [[ ! -d "$VW_DATA_DIR" ]]; then
    warn "备份跳过：数据目录不存在（${VW_DATA_DIR}）"
    return 1
  fi
  if [[ -f "${VW_DATA_DIR}/db.sqlite3" ]]; then
    sqlite3 "${VW_DATA_DIR}/db.sqlite3" "PRAGMA wal_checkpoint(FULL);" 2>/dev/null || true
    local _ic
    _ic=$(sqlite3 "${VW_DATA_DIR}/db.sqlite3" "PRAGMA integrity_check;" 2>/dev/null || echo "error")
    [[ "$_ic" != "ok" ]] && warn "SQLite 完整性校验警告（${_ic}），备份继续但数据库可能已损坏"
  fi
  local tar_extra=()
  [[ -f "$VW_ENV_FILE" ]] && tar_extra=(-C / "${VW_ENV_FILE#/}")
  if tar -czf "$archive_tmp" --exclude="*.log" --exclude="*.log.*" \
    -C "$(dirname "$VW_DATA_DIR")" "$(basename "$VW_DATA_DIR")" \
    "${tar_extra[@]+"${tar_extra[@]}"}" 2>&1 >&2; then
    mv "$archive_tmp" "$archive"
    success "备份已创建：${archive}"
  else
    rm -f "$archive_tmp"
    warn "备份失败，临时文件已清理，继续..."
  fi
}
do_backup() {
  show_banner
  [[ $EUID -ne 0 ]] && error "请用 root 权限运行：sudo bash $0"
  load_config
  acquire_lock
  step "手动备份 Vaultwarden"
  [[ ! -d "$VW_DATA_DIR" ]] && error "数据目录不存在：${VW_DATA_DIR}，请先执行安装"
  _backup_silent "manual"
  echo ""
  info "当前所有备份（最近 10 个）："
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
    warn "暂无备份文件"
  fi
  echo ""
  local _total _total_size
  _total=$(find "${VW_BACKUP_DIR}" -maxdepth 1 -name "vaultwarden_*.tar.gz" 2>/dev/null | wc -l)
  _total_size=$(du -sh "${VW_BACKUP_DIR}" 2>/dev/null | cut -f1 || echo "0")
  info "共 ${_total} 个备份，合计 ${_total_size}"
  release_lock
}
do_status() {
  local DB_SIZE CERT_PATH EXPIRY DAYS HTTP_CODE
  show_banner
  load_config
  if [[ $EUID -ne 0 ]]; then
    warn "当前以非 root 用户运行，部分状态信息（fail2ban、systemd 详情等）可能不完整"
    warn "如需完整状态，请：sudo bash $0 status"
  fi
  step "Vaultwarden 系统状态"
  echo -e "\n${BOLD}【systemd 服务状态】${NC}"
  systemctl status vaultwarden --no-pager -l 2>/dev/null | head -15 | sed 's/^/  /' \
    || echo -e "  ${RED}[✗]${NC} vaultwarden 服务未安装或未运行"
  echo -e "\n${BOLD}【版本信息】${NC}"
  if [[ -x "$VW_BIN" ]]; then
    echo -e "  二进制版本：$(get_installed_version)"
    echo -e "  二进制路径：${VW_BIN}（$(du -sh "$VW_BIN" | cut -f1)）"
    echo -e "  二进制时间：$(stat -c '%y' "$VW_BIN" | cut -d'.' -f1)"
  else
    echo -e "  ${RED}[✗]${NC} 未找到 Vaultwarden 二进制：${VW_BIN}"
  fi
  echo -e "\n${BOLD}【数据目录（${VW_DATA_DIR}）】${NC}"
  if [[ -d "$VW_DATA_DIR" ]]; then
    ls -lh "${VW_DATA_DIR}" 2>/dev/null | tail -n +2 | awk '{printf "  %-12s  %s\n", $5, $NF}'
    echo "  ──────────────────────────"
    echo "  合计：$(du -sh "$VW_DATA_DIR" | cut -f1)"
    if [[ -f "${VW_DATA_DIR}/db.sqlite3" ]]; then
      DB_SIZE=$(du -sh "${VW_DATA_DIR}/db.sqlite3" | cut -f1)
      echo -e "  数据库：db.sqlite3（${DB_SIZE}）"
    fi
  else
    echo -e "  ${RED}[✗]${NC} 数据目录不存在"
  fi
  echo -e "\n${BOLD}【备份文件（最近 5 个）】${NC}"
  if find "${VW_BACKUP_DIR}" -maxdepth 1 -name "vaultwarden_*.tar.gz" 2>/dev/null | grep -q .; then
    ls -lht "${VW_BACKUP_DIR}"/vaultwarden_*.tar.gz 2>/dev/null | head -5 \
      | awk '{printf "  %-60s  %s\n", $NF, $5}'
    echo -e "  共 $(find "${VW_BACKUP_DIR}" -maxdepth 1 -name "vaultwarden_*.tar.gz" 2>/dev/null | wc -l) 个备份"
  else
    echo -e "  ${YELLOW}[!]${NC} 暂无备份文件"
  fi
  echo -e "\n${BOLD}【Nginx 状态】${NC}"
  systemctl is-active nginx &>/dev/null \
    && echo -e "  ${GREEN}[✓]${NC} nginx 运行中" \
    || echo -e "  ${RED}[✗]${NC} nginx 未运行"
  echo -e "\n${BOLD}【Fail2Ban 状态】${NC}"
  if systemctl is-active fail2ban &>/dev/null; then
    fail2ban-client status vaultwarden 2>/dev/null | sed 's/^/  /' \
      || echo -e "  ${YELLOW}[!]${NC} fail2ban 运行中，但 vaultwarden jail 未加载"
  else
    echo -e "  ${RED}[✗]${NC} fail2ban 未运行"
  fi
  echo -e "\n${BOLD}【HTTP 健康检查】${NC}"
  HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}" --max-time 5 "http://127.0.0.1:${VW_PORT}/" 2>/dev/null || echo "000")
  [[ "$HTTP_CODE" =~ ^(200|302|301)$ ]] \
    && echo -e "  ${GREEN}[✓]${NC} 本地接口响应：HTTP ${HTTP_CODE}" \
    || echo -e "  ${YELLOW}[!]${NC} 本地接口响应：HTTP ${HTTP_CODE}（服务未运行或端口错误？）"
  echo -e "\n${BOLD}【TLS 证书】${NC}"
  CERT_PATH="/etc/letsencrypt/live/${VW_DOMAIN}/fullchain.pem"
  if [[ -f "$CERT_PATH" ]]; then
    EXPIRY=$(openssl x509 -enddate -noout -in "$CERT_PATH" | sed 's/notAfter=//')
    DAYS=$(( ( $(date -d "$EXPIRY" +%s 2>/dev/null || echo 0) - $(date +%s) ) / 86400 ))
    if [[ $DAYS -gt 30 ]]; then
      echo -e "  ${GREEN}[✓]${NC} 证书有效，剩余 ${DAYS} 天（${EXPIRY}）"
    elif [[ $DAYS -gt 0 ]]; then
      echo -e "  ${YELLOW}[!]${NC} 证书即将到期（剩余 ${DAYS} 天），请尽快执行：certbot renew"
    else
      echo -e "  ${RED}[✗]${NC} 证书已过期（${DAYS} 天前），请立即执行：certbot renew"
    fi
  else
    echo -e "  ${YELLOW}[!]${NC} 未找到证书（未配置 HTTPS 或证书路径有误）"
  fi
  echo ""
}
do_uninstall() {
  show_banner
  preflight_check
  load_config
  acquire_lock
  [[ -z "${VW_BIN:-}"        ]] && error "VW_BIN 未设置，请先执行 install 或确认配置文件存在"
  [[ -z "${VW_DATA_DIR:-}"   ]] && error "VW_DATA_DIR 未设置，卸载已中止"
  [[ -z "${VW_BACKUP_DIR:-}" ]] && error "VW_BACKUP_DIR 未设置，卸载已中止"
  [[ "${VW_DATA_DIR}"   == "/" ]] && error "VW_DATA_DIR 为根目录（/），拒绝卸载"
  [[ "${VW_BACKUP_DIR}" == "/" ]] && error "VW_BACKUP_DIR 为根目录（/），拒绝卸载"
  step "卸载 Vaultwarden"
  echo -e "${RED}${BOLD}"
  echo "  ⚠️  此操作将删除："
  echo "     · Vaultwarden 二进制（${VW_BIN}）"
  echo "     · systemd 服务单元"
  echo "     · Nginx 配置"
  echo "     · Fail2Ban 规则"
  echo "     · 环境变量文件（${VW_ENV_FILE}）"
  echo "     · 定时备份任务"
  echo "  数据目录（${VW_DATA_DIR}）默认保留，可选是否删除。"
  echo -e "${NC}"
  prompt "确认继续卸载？（输入 YES 确认）："
  read -r _c
  [[ "$_c" != "YES" ]] && { info "已取消"; exit 0; }
  prompt "是否同时删除数据目录（${VW_DATA_DIR}）？（y/N）："
  local _del_data; read -r _del_data
  local DELETE_DATA=false; [[ "${_del_data,,}" == "y" ]] && DELETE_DATA=true
  prompt "是否同时删除备份目录（${VW_BACKUP_DIR}）？（y/N）："
  local _del_bak; read -r _del_bak
  local DELETE_BACKUP=false; [[ "${_del_bak,,}" == "y" ]] && DELETE_BACKUP=true
  info "停止 Vaultwarden 服务..."
  systemctl stop    vaultwarden 2>/dev/null || true
  systemctl disable vaultwarden 2>/dev/null || true
  rm -f /etc/systemd/system/vaultwarden.service
  systemctl daemon-reload
  success "systemd 服务已移除"
  rm -f "${VW_BIN}"
  find "$(dirname "$VW_BIN")" -maxdepth 1 -name "vaultwarden.bak.*" -type f -delete 2>/dev/null || true
  success "二进制已删除"
  rm -f /etc/nginx/sites-enabled/vaultwarden /etc/nginx/sites-available/vaultwarden
  nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null || true
  success "Nginx 配置已清除"
  rm -f /etc/fail2ban/filter.d/vaultwarden.conf \
        /etc/fail2ban/filter.d/vaultwarden-admin.conf \
        /etc/fail2ban/jail.d/vaultwarden.conf
  systemctl restart fail2ban 2>/dev/null || true
  success "Fail2Ban 规则已清除"
  rm -f /etc/cron.d/vaultwarden-backup \
        /usr/local/bin/vaultwarden-backup \
        /etc/logrotate.d/vaultwarden
  success "定时任务、备份脚本、日志轮转已清除"
  rm -f "$VW_ENV_FILE" "$CONF_FILE"
  success "配置文件已清除"
  local _log_dir
  _log_dir=$(dirname "$VW_LOG_FILE")
  if [[ -n "$_log_dir" && "$_log_dir" != "." && "$_log_dir" != "/" && -d "$_log_dir" ]]; then
    rm -rf "$_log_dir"
    success "日志目录已删除：${_log_dir}"
  else
    warn "日志目录路径异常（${_log_dir}），已跳过删除"
  fi
  if $DELETE_DATA; then
    rm -rf "$VW_DATA_DIR"
    success "数据目录已删除：${VW_DATA_DIR}"
  else
    info "数据目录已保留：${VW_DATA_DIR}"
  fi
  if $DELETE_BACKUP; then
    rm -rf "$VW_BACKUP_DIR"
    success "备份目录已删除：${VW_BACKUP_DIR}"
  else
    info "备份目录已保留：${VW_BACKUP_DIR}"
  fi
  if $DELETE_DATA && id "$VW_USER" &>/dev/null; then
    userdel "$VW_USER" 2>/dev/null && success "系统用户 ${VW_USER} 已删除" || true
  fi
  echo ""
  echo -e "${BOLD}${GREEN}  ✅  Vaultwarden 已完全卸载${NC}"
  if ! $DELETE_DATA; then
    echo -e "  ${YELLOW}[提示]${NC} 数据保留在：${VW_DATA_DIR}"
    echo -e "  ${YELLOW}[提示]${NC} 如确认不再需要，可手动执行：rm -rf ${VW_DATA_DIR}"
  fi
  echo ""
}
