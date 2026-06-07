#!/bin/bash
set -euo pipefail
umask 077
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${BLUE}[·]${NC} $*" >&2; }
success() { echo -e "${GREEN}[✓]${NC} $*" >&2; }
warn()    { echo -e "${YELLOW}[!]${NC} $*" >&2; }
error()   { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }
step()    { echo -e "\n${CYAN}${BOLD}── $* ──────────────────────────────${NC}" >&2; }
prompt()  { echo -ne "${YELLOW}[?]${NC} $* " >&2; }
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
show_banner() {
  echo -e "\n${BOLD}${CYAN}"
  cat << 'EOF'
   ███████╗██╗   ██╗██████╗ ██████╗  █████╗ ██████╗ ██╗
   ██╔════╝██║   ██║██╔══██╗╚════██╗██╔══██╗██╔══██╗██║
   ███████╗██║   ██║██████╔╝ █████╔╝███████║██████╔╝██║
   ╚════██║██║   ██║██╔══██╗██╔═══╝ ██╔══██║██╔═══╝ ██║
   ███████║╚██████╔╝██████╔╝███████╗██║  ██║██║     ██║
   ╚══════╝ ╚═════╝ ╚═════╝ ╚══════╝╚═╝  ╚═╝╚═╝     ╚═╝
EOF
  echo -e "${NC}"
  echo -e "  ${BOLD}AI API 网关平台 · 订阅配额分发 · 二进制直装 · systemd 托管${NC}\n"
}
preflight_check() {
  [[ $EUID -ne 0 ]] && error "请用 root 权限运行：sudo bash $0 ${1:-}"
  if command -v apt-get &>/dev/null; then
    PKG_MANAGER="apt"
  elif command -v dnf &>/dev/null; then
    PKG_MANAGER="dnf"
  elif command -v yum &>/dev/null; then
    PKG_MANAGER="yum"
  else
    error "未找到支持的包管理器（apt / dnf / yum），请手动安装依赖"
  fi
  ARCH=$(uname -m)
  case "$ARCH" in
    x86_64)  BIN_ARCH="amd64" ; ELF_MACHINE="3e" ;;
    aarch64) BIN_ARCH="arm64" ; ELF_MACHINE="b7" ;;
    *) error "不支持的架构：${ARCH}（支持 x86_64 / aarch64）" ;;
  esac
}
LOCK_FILE="/var/lock/sub2api-deploy.lock"
acquire_lock() {
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    error "另一个 sub2api 管理进程正在运行（锁文件：${LOCK_FILE}），请稍后再试"
  fi
  trap 'flock -u 9 2>/dev/null; exec 9>&- 2>/dev/null' EXIT
}
release_lock() { flock -u 9 2>/dev/null; exec 9>&- 2>/dev/null; }
check_connectivity() {
  local targets=(
    "https://api.github.com"
    "https://github.com"
    "https://objects.githubusercontent.com"
  )
  for t in "${targets[@]}"; do
    if curl -fsSL --max-time 8 -o /dev/null "$t" 2>/dev/null; then
      return 0
    fi
  done
  error "网络不通，无法访问 GitHub，请检查网络或代理后重试"
}
wait_for_service() {
  local svc="$1" timeout="${2:-20}" elapsed=0
  while ! systemctl is-active --quiet "$svc"; do
    if systemctl is-failed --quiet "$svc" 2>/dev/null; then
      return 1
    fi
    sleep 1
    elapsed=$(( elapsed + 1 ))
    [[ $elapsed -ge $timeout ]] && return 1
  done
  return 0
}
_sanitize_conf_val() {
  local _v="${1%%$'\n'*}"
  _v="${_v//\"/}"
  echo "$_v"
}
save_config() {
  cat > "$CONF_FILE" << CONF
PORT="$(_sanitize_conf_val "${PORT}")"
INSTALL_DIR="$(_sanitize_conf_val "${INSTALL_DIR}")"
DATA_DIR="$(_sanitize_conf_val "${DATA_DIR}")"
LOG_DIR="$(_sanitize_conf_val "${LOG_DIR}")"
CONFIG_DIR="$(_sanitize_conf_val "${CONFIG_DIR}")"
SERVICE_NAME="$(_sanitize_conf_val "${SERVICE_NAME}")"
SERVICE_USER="$(_sanitize_conf_val "${SERVICE_USER}")"
GITHUB_REPO="$(_sanitize_conf_val "${GITHUB_REPO}")"
BACKUP_DIR="$(_sanitize_conf_val "${BACKUP_DIR}")"
BACKUP_KEEP_DAYS="$(_sanitize_conf_val "${BACKUP_KEEP_DAYS}")"
PG_USER="$(_sanitize_conf_val "${PG_USER}")"
PG_PASS="$(_sanitize_conf_val "${PG_PASS:-}")"
PG_DB="$(_sanitize_conf_val "${PG_DB}")"
PG_DSN="$(_sanitize_conf_val "${PG_DSN:-}")"
SUB2API_DOMAIN="$(_sanitize_conf_val "${SUB2API_DOMAIN:-}")"
INSTALLED_VERSION="$(_sanitize_conf_val "${INSTALLED_VERSION:-unknown}")"
CONF
  chmod 600 "$CONF_FILE"
  success "部署配置已持久化：${CONF_FILE}"
}
load_config() {
  [[ ! -f "$CONF_FILE" ]] && return
  local _owner _perms
  _owner=$(stat -c '%U' "$CONF_FILE" 2>/dev/null || echo "unknown")
  _perms=$(stat -c '%a' "$CONF_FILE" 2>/dev/null || echo "777")
  if [[ "$_owner" != "root" ]]; then
    warn "配置文件 ${CONF_FILE} 属主非 root（当前：${_owner}），拒绝加载"
    return
  fi
  if [[ "$_perms" != "600" && "$_perms" != "400" ]]; then
    warn "配置文件权限过于宽松（${_perms}），拒绝加载（建议：chmod 600 ${CONF_FILE}）"
    return
  fi
  local _line _key _val
  while IFS= read -r _line || [[ -n "$_line" ]]; do
    [[ "$_line" =~ ^[[:space:]]*(#|$) ]] && continue
    _key="${_line%%=*}"
    _key="${_key// /}"
    if [[ ! "$_key" =~ ^[A-Z_]+$ ]]; then
      warn "配置文件含非法键名（${_key}），已跳过"
      continue
    fi
    _val="${_line#*=}"
    if [[ "$_val" =~ ^\"(.*)\"$ ]]; then
      _val="${BASH_REMATCH[1]}"
    fi
    case "$_key" in
      PORT|INSTALL_DIR|DATA_DIR|LOG_DIR|CONFIG_DIR|SERVICE_NAME|\
      SERVICE_USER|GITHUB_REPO|BACKUP_DIR|BACKUP_KEEP_DAYS|\
      PG_USER|PG_PASS|PG_DB|PG_DSN|SUB2API_DOMAIN|INSTALLED_VERSION)
        printf -v "$_key" '%s' "$_val"
        ;;
      *)
        warn "配置文件包含未知键 ${_key}，已忽略"
        ;;
    esac
  done < "$CONF_FILE"
  BIN_PATH="${INSTALL_DIR}/sub2api"
  success "已加载部署记录：${CONF_FILE}"
}
get_latest_release() {
  local json tag
  json=$(curl -fsSL --max-time 15 \
    "https://api.github.com/repos/${GITHUB_REPO}/releases/latest" 2>/dev/null) \
    || { warn "无法访问 GitHub API"; echo ""; return; }
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
    warn "无法下载 checksums.txt，跳过 SHA256 校验（建议手动核验）"
    rm -f "$tmp_sum"
    return 0
  fi
  local expected_hash
  expected_hash=$(grep " ${expected_name}$" "$tmp_sum" 2>/dev/null | awk '{print $1}' || true)
  rm -f "$tmp_sum"
  if [[ -z "$expected_hash" ]]; then
    warn "checksums.txt 中未找到 ${expected_name} 的校验值，跳过校验"
    return 0
  fi
  local actual_hash
  if command -v sha256sum &>/dev/null; then
    actual_hash=$(sha256sum "$archive" | awk '{print $1}')
  elif command -v shasum &>/dev/null; then
    actual_hash=$(shasum -a 256 "$archive" | awk '{print $1}')
  else
    warn "未找到 sha256sum / shasum，跳过 SHA256 校验"
    return 0
  fi
  if [[ "$actual_hash" != "$expected_hash" ]]; then
    error "SHA256 校验失败！\n  期望：${expected_hash}\n  实际：${actual_hash}"
  fi
  success "SHA256 校验通过（${actual_hash:0:16}...）"
}
extract_and_verify() {
  local archive="$1" dest_dir="$2"
  local tmp_extract; tmp_extract=$(mktemp -d "${dest_dir}/sub2api-extract.XXXXXX")
  if ! tar -xzf "$archive" -C "$tmp_extract" 2>&1; then
    rm -rf "$tmp_extract"
    error "tar 解压失败，归档文件可能已损坏"
  fi
  local bin_path
  bin_path=$(find "$tmp_extract" -maxdepth 2 -name "sub2api" -type f 2>/dev/null | head -1 || true)
  if [[ -z "$bin_path" ]]; then
    rm -rf "$tmp_extract"
    error "tar.gz 中未找到 sub2api 二进制文件，请确认下载 URL 是否正确"
  fi
  local magic
  magic=$(dd if="$bin_path" bs=1 count=4 2>/dev/null | od -An -tx1 | tr -d ' \n' 2>/dev/null || true)
  if [[ "$magic" != "7f454c46" ]]; then
    rm -rf "$tmp_extract"
    error "二进制不是有效的 ELF 格式（magic: ${magic:-读取失败}）"
  fi
  local emachine
  emachine=$(dd if="$bin_path" bs=1 skip=18 count=1 2>/dev/null | od -An -tx1 | tr -d ' \n' 2>/dev/null || true)
  if [[ "$emachine" != "$ELF_MACHINE" ]]; then
    rm -rf "$tmp_extract"
    error "ELF 架构不匹配（e_machine=${emachine}，期望=${ELF_MACHINE}，当前平台=${BIN_ARCH}）"
  fi
  local size; size=$(wc -c < "$bin_path")
  local size_mb=$(( size / 1024 / 1024 ))
  success "ELF 校验通过（架构 ${BIN_ARCH}，${size_mb} MB）"
  local tmp_bin; tmp_bin=$(mktemp "${dest_dir}/sub2api.tmp.XXXXXX")
  mv "$bin_path" "$tmp_bin"
  rm -rf "$tmp_extract"
  echo "$tmp_bin"
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
    success "HTTP 健康检查通过（状态码 ${HTTP_CODE}）"
  else
    warn "健康检查返回 ${HTTP_CODE}，服务可能仍在初始化"
    warn "调试命令：journalctl -u ${SERVICE_NAME} -n 30 --no-pager"
    warn "完成数据库/Redis 配置后，请在浏览器访问 Setup Wizard：http://<IP>:${PORT}/"
  fi
}
_install_base_deps() {
  info "安装基础依赖..."
  if [[ "$PKG_MANAGER" == "apt" ]]; then
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
      curl ca-certificates gnupg lsb-release
  elif [[ "$PKG_MANAGER" == "dnf" ]]; then
    dnf install -y -q curl ca-certificates
  elif [[ "$PKG_MANAGER" == "yum" ]]; then
    yum install -y -q curl ca-certificates
  fi
  success "基础依赖安装完成"
}
_install_postgres() {
  if command -v psql &>/dev/null; then
    local pg_ver
    pg_ver=$(psql --version 2>/dev/null | grep -oE '[0-9]+' | head -1 || echo "0")
    if [[ "$pg_ver" -ge 15 ]]; then
      success "PostgreSQL ${pg_ver} 已安装，跳过安装"
      systemctl enable postgresql 2>/dev/null || \
        systemctl enable "postgresql-${pg_ver}" 2>/dev/null || true
      systemctl start  postgresql 2>/dev/null || \
        systemctl start  "postgresql-${pg_ver}" 2>/dev/null || true
      return 0
    fi
    warn "检测到 PostgreSQL ${pg_ver}（< 15），将从 PGDG 官方源安装 PostgreSQL 15"
  fi
  if [[ "$PKG_MANAGER" == "apt" ]]; then
    info "添加 PostgreSQL PGDG 官方 apt 源..."
    install -d /usr/share/postgresql-common/pgdg
    if ! curl -fsSL --max-time 30 \
        -o /usr/share/postgresql-common/pgdg/apt.postgresql.org.asc \
        "https://www.postgresql.org/media/keys/ACCC4CF8.asc"; then
      error "无法下载 PostgreSQL 签名密钥，请检查网络后重试"
    fi
    local codename
    codename=$(lsb_release -cs 2>/dev/null || . /etc/os-release && echo "$VERSION_CODENAME")
    echo "deb [signed-by=/usr/share/postgresql-common/pgdg/apt.postgresql.org.asc] \
https://apt.postgresql.org/pub/repos/apt ${codename}-pgdg main" \
      > /etc/apt/sources.list.d/pgdg.list
    chmod 644 /etc/apt/sources.list.d/pgdg.list
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-15 postgresql-client-15
    systemctl enable --now postgresql
    success "PostgreSQL 15 安装完成"
  elif [[ "$PKG_MANAGER" == "dnf" || "$PKG_MANAGER" == "yum" ]]; then
    info "添加 PostgreSQL PGDG RPM 源..."
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
    success "PostgreSQL 15 安装完成"
  fi
}
_install_redis() {
  if command -v redis-server &>/dev/null; then
    local redis_ver
    redis_ver=$(redis-server --version 2>/dev/null \
      | grep -oE 'v=[0-9]+' | grep -oE '[0-9]+' || echo "0")
    if [[ "$redis_ver" -ge 7 ]]; then
      success "Redis ${redis_ver} 已安装，跳过安装"
      systemctl enable --now redis-server 2>/dev/null || \
        systemctl enable --now redis 2>/dev/null || true
      return 0
    fi
    warn "检测到 Redis ${redis_ver}（< 7），将从官方源安装 Redis 7"
  fi
  if [[ "$PKG_MANAGER" == "apt" ]]; then
    info "添加 Redis 官方 apt 源..."
    curl -fsSL --max-time 30 "https://packages.redis.io/gpg" \
      | gpg --dearmor -o /usr/share/keyrings/redis-archive-keyring.gpg
    chmod 644 /usr/share/keyrings/redis-archive-keyring.gpg
    local codename
    codename=$(lsb_release -cs 2>/dev/null || . /etc/os-release && echo "$VERSION_CODENAME")
    echo "deb [signed-by=/usr/share/keyrings/redis-archive-keyring.gpg] \
https://packages.redis.io/deb ${codename} main" \
      > /etc/apt/sources.list.d/redis.list
    chmod 644 /etc/apt/sources.list.d/redis.list
    apt-get update -qq
    DEBIAN_FRONTEND=noninteractive apt-get install -y redis
    systemctl enable --now redis-server
    success "Redis 7 安装完成"
  elif [[ "$PKG_MANAGER" == "dnf" ]]; then
    dnf install -y redis
    systemctl enable --now redis
    success "Redis 安装完成"
  elif [[ "$PKG_MANAGER" == "yum" ]]; then
    yum install -y redis
    systemctl enable --now redis
    success "Redis 安装完成"
  fi
}
_setup_postgres() {
  if ! systemctl is-active --quiet postgresql 2>/dev/null && \
     ! systemctl is-active --quiet postgresql-15 2>/dev/null; then
    warn "PostgreSQL 服务未运行，尝试启动..."
    systemctl start postgresql 2>/dev/null || \
      systemctl start postgresql-15 2>/dev/null || \
      error "无法启动 PostgreSQL 服务，请检查：journalctl -u postgresql -n 30"
  fi
  if [[ -z "${PG_PASS:-}" ]]; then
    PG_PASS=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 24)
    info "已生成随机 PostgreSQL 密码（24 位）"
  else
    info "复用已有 PostgreSQL 密码"
  fi
  info "配置 PostgreSQL 用户和数据库..."
  local user_exists
  user_exists=$(sudo -u postgres psql -tAc \
    "SELECT 1 FROM pg_roles WHERE rolname='${PG_USER}'" 2>/dev/null || echo "")
  if [[ "$user_exists" == "1" ]]; then
    info "PostgreSQL 用户 '${PG_USER}' 已存在，同步密码..."
    sudo -u postgres psql -c \
      "ALTER USER ${PG_USER} WITH PASSWORD '${PG_PASS}';" > /dev/null
  else
    sudo -u postgres psql -c \
      "CREATE USER ${PG_USER} WITH PASSWORD '${PG_PASS}';" > /dev/null
    success "PostgreSQL 用户 '${PG_USER}' 已创建"
  fi
  local db_exists
  db_exists=$(sudo -u postgres psql -tAc \
    "SELECT 1 FROM pg_database WHERE datname='${PG_DB}'" 2>/dev/null || echo "")
  if [[ "$db_exists" == "1" ]]; then
    info "PostgreSQL 数据库 '${PG_DB}' 已存在，跳过创建"
  else
    sudo -u postgres psql -c \
      "CREATE DATABASE ${PG_DB} OWNER ${PG_USER};" > /dev/null
    success "PostgreSQL 数据库 '${PG_DB}' 已创建，属主：${PG_USER}"
  fi
  PG_DSN="postgresql://${PG_USER}:${PG_PASS}@localhost:5432/${PG_DB}?sslmode=disable"
  success "PostgreSQL DSN 已生成"
}
_install_nginx() {
  if command -v nginx &>/dev/null; then
    info "Nginx 已安装，跳过安装"
  else
    info "安装 Nginx..."
    if [[ "$PKG_MANAGER" == "apt" ]]; then
      DEBIAN_FRONTEND=noninteractive apt-get install -y nginx
    elif [[ "$PKG_MANAGER" == "dnf" ]]; then
      dnf install -y nginx
    elif [[ "$PKG_MANAGER" == "yum" ]]; then
      yum install -y nginx
    fi
    success "Nginx 安装完成"
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
  cat > /etc/nginx/sites-available/sub2api << NGINX
server {
    listen 80;
${server_name_line}

    # 最大请求体（API 上传场景）
    client_max_body_size 64m;

    location / {
        proxy_pass         http://127.0.0.1:${PORT};
        proxy_http_version 1.1;

        proxy_set_header   Host              \$host;
        proxy_set_header   X-Real-IP         \$remote_addr;
        proxy_set_header   X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;

        # SSE 流式响应支持（Server-Sent Events / AI 流式输出）
        # 禁用缓冲，确保 token 逐字节实时传输到客户端
        proxy_buffering    off;
        proxy_cache        off;

        # 超时设置（AI 推理可能耗时较长）
        proxy_read_timeout    300s;
        proxy_connect_timeout  10s;
        proxy_send_timeout     60s;

        # 支持 WebSocket 升级（如 Sub2API 后续支持）
        proxy_set_header   Upgrade    \$http_upgrade;
        proxy_set_header   Connection "upgrade";
    }
}
NGINX
  chmod 644 /etc/nginx/sites-available/sub2api
  if [[ ! -L /etc/nginx/sites-enabled/sub2api ]]; then
    ln -s /etc/nginx/sites-available/sub2api /etc/nginx/sites-enabled/sub2api
  fi
  if [[ "$PKG_MANAGER" != "apt" ]]; then
    if ! grep -q "sites-enabled" /etc/nginx/nginx.conf 2>/dev/null; then
      sed -i '/^http[[:space:]]*{/a\    include /etc/nginx/sites-enabled/*;' \
        /etc/nginx/nginx.conf 2>/dev/null || \
        warn "无法自动修改 /etc/nginx/nginx.conf，请手动在 http {} 块中添加：include /etc/nginx/sites-enabled/*;"
    fi
  fi
  if nginx -t 2>/dev/null; then
    systemctl reload nginx
    if [[ -n "${SUB2API_DOMAIN:-}" ]]; then
      success "Nginx 反代配置已生效（域名：${SUB2API_DOMAIN} → :${PORT}）"
    else
      success "Nginx 反代配置已生效（兜底 server_name _ → :${PORT}）"
    fi
  else
    warn "Nginx 配置校验失败（nginx -t），请检查配置文件后手动执行：nginx -t && systemctl reload nginx"
    nginx -t >&2 2>/dev/null || true
  fi
}
_write_systemd_unit() {
  cat > "/etc/systemd/system/${SERVICE_NAME}.service" << EOF
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

# 崩溃后自动重启（最多每 60 秒重启 5 次）
Restart=always
RestartSec=5
StartLimitInterval=60
StartLimitBurst=5

# 环境变量
Environment="SERVER_HOST=0.0.0.0"
Environment="SERVER_PORT=${PORT}"
Environment="TZ=Asia/Shanghai"
# SSE 流式响应优化：使用 Go 原生 DNS 解析，避免 CGO 依赖超时
Environment="GODEBUG=netdns=go"

# 文件描述符 / 进程限制（API 网关高并发场景）
LimitNOFILE=65536
LimitNPROC=512

# 安全加固
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
# 允许写入的路径：数据目录 + 日志目录 + 配置目录
ReadWritePaths=${DATA_DIR} ${LOG_DIR} ${CONFIG_DIR}

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
    ufw allow "${PORT}/tcp" comment "Sub2API" > /dev/null
    success "ufw 已放行端口 ${PORT}"
    FW_DONE=true
  fi
  if ! $FW_DONE && command -v firewall-cmd &>/dev/null && \
      firewall-cmd --state &>/dev/null; then
    firewall-cmd --permanent --add-port="${PORT}/tcp" >/dev/null 2>&1 || true
    firewall-cmd --reload >/dev/null 2>&1 || true
    success "firewalld 已放行端口 ${PORT}"
    FW_DONE=true
  fi
  if ! $FW_DONE && command -v iptables &>/dev/null; then
    if ! iptables -C INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null; then
      iptables -A INPUT -p tcp --dport "$PORT" -j ACCEPT
    fi
    if command -v netfilter-persistent &>/dev/null; then
      netfilter-persistent save 2>/dev/null && \
        success "iptables 规则已持久化（netfilter-persistent）" || true
    elif command -v iptables-save &>/dev/null; then
      mkdir -p /etc/iptables
      iptables-save > /etc/iptables/rules.v4 2>/dev/null && \
        info "iptables 规则已写入 /etc/iptables/rules.v4" || \
        warn "iptables 规则写入失败，重启后规则可能丢失"
    else
      warn "iptables 规则未持久化，重启后失效。建议安装 iptables-persistent"
    fi
    success "iptables 已放行端口 ${PORT}"
    FW_DONE=true
  fi
  $FW_DONE || warn "未检测到活跃防火墙，如有云安全组（AWS/阿里云/腾讯云）请手动放行端口 ${PORT}"
}
_write_logrotate() {
  cat > /etc/logrotate.d/sub2api << LOGR
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
  success "日志轮转已配置（每日轮转，保留 14 天，自动压缩）"
}
_write_backup_script() {
  mkdir -p "$BACKUP_DIR"
  cat > /usr/local/bin/sub2api-backup << BKSH_HEADER
#!/bin/bash
# Sub2API 自动备份脚本（由 install_sub2api.sh 自动生成，请勿手动修改）
# 重新生成：sudo bash install_sub2api.sh install
set -euo pipefail
umask 077

BACKUP_DIR="${BACKUP_DIR}"
DATA_DIR="${DATA_DIR}"
CONFIG_DIR="${CONFIG_DIR}"
SERVICE_NAME="${SERVICE_NAME}"
KEEP_DAYS="${BACKUP_KEEP_DAYS}"
PG_DSN="${PG_DSN}"
BKSH_HEADER
  cat >> /usr/local/bin/sub2api-backup << 'BKSH_BODY'

LOG="${BACKUP_DIR}/backup.log"
TS=$(date +%Y%m%d_%H%M%S)
ARCHIVE="${BACKUP_DIR}/sub2api_${TS}.tar.gz"
ARCHIVE_TMP="${ARCHIVE}.tmp"
PG_DUMP_FILE="${BACKUP_DIR}/sub2api_db_${TS}.sql.gz"
PG_DUMP_TMP="${PG_DUMP_FILE}.tmp"

_log() { echo "$(date '+%F %T')  $*" >> "$LOG"; }
_log "── 开始备份 ────────────────────────────────────"

mkdir -p "${BACKUP_DIR}"

# ── 1. PostgreSQL 数据库备份 ──────────────────────────────────
if [[ -n "${PG_DSN}" ]] && command -v pg_dump &>/dev/null; then
  _log "[DB] 开始 pg_dump..."
  if pg_dump "${PG_DSN}" 2>&1 | gzip > "${PG_DUMP_TMP}"; then
    mv "${PG_DUMP_TMP}" "${PG_DUMP_FILE}"
    DB_SIZE=$(du -sh "${PG_DUMP_FILE}" 2>/dev/null | awk '{print $1}')
    _log "[DB] pg_dump 成功：${PG_DUMP_FILE}（${DB_SIZE}）"
  else
    rm -f "${PG_DUMP_TMP}"
    _log "[WARN] pg_dump 失败，跳过数据库备份（继续备份配置文件）"
  fi
else
  if [[ -z "${PG_DSN}" ]]; then
    _log "[WARN] PG_DSN 未配置，跳过数据库备份"
  else
    _log "[WARN] pg_dump 命令不存在，跳过数据库备份"
  fi
fi

# ── 2. 配置目录 + 本地数据目录备份 ───────────────────────────
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
    mv "${EXTRA_CONF_TMP}" "${EXTRA_CONF_ARCHIVE}"
    _log "[OK] 配置目录备份：${EXTRA_CONF_ARCHIVE}"
  else
    rm -f "${EXTRA_CONF_TMP}"
    _log "[WARN] 配置目录备份失败"
  fi
fi

if [[ ${#TAR_ARGS[@]} -gt 0 ]]; then
  if tar -czf "${ARCHIVE_TMP}" \
      --exclude="*.log" --exclude="*.log.*" \
      "${TAR_ARGS[@]}" 2>&1 | \
      while IFS= read -r line; do _log "[TAR] ${line}"; done; then
    mv "${ARCHIVE_TMP}" "${ARCHIVE}"
    SIZE=$(du -sh "${ARCHIVE}" 2>/dev/null | awk '{print $1}')
    _log "[OK] 数据目录备份：${ARCHIVE}（${SIZE}）"
  else
    rm -f "${ARCHIVE_TMP}"
    _log "[ERROR] 数据目录 tar 失败，临时文件已清理"
  fi
fi

# ── 3. 清理超期备份 ──────────────────────────────────────────
if [[ "${KEEP_DAYS}" -gt 0 ]]; then
  REMOVED=0
  while IFS= read -r f; do
    rm -f "$f" && REMOVED=$(( REMOVED + 1 )) || true
  done < <(find "${BACKUP_DIR}" -maxdepth 1 \
    \( -name "sub2api_*.tar.gz" -o -name "sub2api_db_*.sql.gz" \
    -o -name "sub2api_conf_*.tar.gz" \) \
    -mtime "+${KEEP_DAYS}" 2>/dev/null)
  [[ $REMOVED -gt 0 ]] && _log "[OK] 已清理 ${REMOVED} 个超过 ${KEEP_DAYS} 天的旧备份"
fi

_log "── 备份完成 ────────────────────────────────────"
BKSH_BODY
  chmod 750 /usr/local/bin/sub2api-backup
  success "备份脚本已写入：/usr/local/bin/sub2api-backup"
}
_backup_silent() {
  local label="${1:-manual}"
  mkdir -p "$BACKUP_DIR"
  if [[ -n "${PG_DSN:-}" ]] && command -v pg_dump &>/dev/null; then
    local pg_archive="${BACKUP_DIR}/sub2api_db_${label}_$(date +%Y%m%d_%H%M%S).sql.gz"
    local pg_tmp="${pg_archive}.tmp"
    if pg_dump "${PG_DSN}" 2>/dev/null | gzip > "$pg_tmp"; then
      mv "$pg_tmp" "$pg_archive"
      local sz; sz=$(du -sh "$pg_archive" 2>/dev/null | awk '{print $1}')
      success "静默 pg_dump 备份：${pg_archive}（${sz}）"
    else
      rm -f "$pg_tmp"
      warn "pg_dump 失败，继续执行（可能影响数据恢复能力）"
    fi
  else
    warn "PG_DSN 未配置或 pg_dump 不存在，跳过数据库快照"
  fi
  if [[ -d "$CONFIG_DIR" ]]; then
    local conf_archive="${BACKUP_DIR}/sub2api_conf_${label}_$(date +%Y%m%d_%H%M%S).tar.gz"
    local conf_tmp="${conf_archive}.tmp"
    if tar -czf "$conf_tmp" \
        -C "$(dirname "$CONFIG_DIR")" "$(basename "$CONFIG_DIR")" 2>&1 >&2; then
      mv "$conf_tmp" "$conf_archive"
      local sz; sz=$(du -sh "$conf_archive" 2>/dev/null | awk '{print $1}')
      success "配置目录备份：${conf_archive}（${sz}）"
    else
      rm -f "$conf_tmp"
      warn "配置目录备份失败（tar 报错）"
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
  echo "  ║              🎉  Sub2API 部署完成！                            ║"
  echo "  ╠════════════════════════════════════════════════════════════════╣"
  echo -e "  ║  Setup Wizard   ${CYAN}${access_url}${GREEN}"
  echo -e "  ║  版本           ${YELLOW}${version}${GREEN}"
  echo "  ╠════════════════════════════════════════════════════════════════╣"
  echo -e "  ║  ${BOLD}📦 PostgreSQL 账号（Setup Wizard → 数据库配置）${GREEN}             ║"
  echo -e "  ║    主机         ${CYAN}localhost${GREEN}"
  echo -e "  ║    端口         ${CYAN}5432${GREEN}"
  echo -e "  ║    用户名       ${CYAN}${PG_USER}${GREEN}"
  echo -e "  ║    密码         ${YELLOW}${PG_PASS}${GREEN}   ← 已写入 ${CONF_FILE}"
  echo -e "  ║    数据库名     ${CYAN}${PG_DB}${GREEN}"
  echo -e "  ║    SSL 模式     ${CYAN}禁用${GREEN}"
  echo "  ╠════════════════════════════════════════════════════════════════╣"
  echo -e "  ║  ${BOLD}🔴 Redis 配置（Setup Wizard → Redis）${GREEN}                       ║"
  echo -e "  ║    主机         ${CYAN}localhost${GREEN}"
  echo -e "  ║    端口         ${CYAN}6379${GREEN}"
  echo -e "  ║    密码         ${CYAN}（留空）${GREEN}"
  echo "  ╠════════════════════════════════════════════════════════════════╣"
  echo -e "  ║  安装目录       ${YELLOW}${INSTALL_DIR}${GREEN}"
  echo -e "  ║  数据目录       ${YELLOW}${DATA_DIR}${GREEN}"
  echo -e "  ║  配置目录       ${YELLOW}${CONFIG_DIR}${GREEN}"
  echo -e "  ║  日志目录       ${YELLOW}${LOG_DIR}${GREEN}"
  echo -e "  ║  备份目录       ${YELLOW}${BACKUP_DIR}${GREEN}"
  echo "  ╠════════════════════════════════════════════════════════════════╣"
  echo "  ║  后续步骤：                                                      ║"
  echo -e "  ║    1) 打开 Setup Wizard，按上表填写数据库 / Redis 配置         ║"
  echo -e "  ║    2) 完成向导后服务自动就绪，可通过 Nginx 域名访问            ║"
  echo -e "  ║    3) PostgreSQL 密码已保存至 ${CONF_FILE}（chmod 600）     ║"
  echo "  ╚════════════════════════════════════════════════════════════════╝"
  echo -e "${NC}"
  echo -e "  ${BOLD}管理命令：${NC}"
  echo -e "    ${CYAN}bash $0 status${NC}      — 查看运行状态"
  echo -e "    ${CYAN}bash $0 update${NC}      — 更新到最新版"
  echo -e "    ${CYAN}bash $0 backup${NC}      — 立即备份数据"
  echo -e "    ${CYAN}bash $0 uninstall${NC}   — 卸载服务"
  echo ""
  echo -e "  ${BOLD}systemd 命令：${NC}"
  echo -e "    ${CYAN}systemctl status ${SERVICE_NAME}${NC}      查看状态"
  echo -e "    ${CYAN}journalctl -u ${SERVICE_NAME} -f${NC}      实时日志"
  echo -e "    ${CYAN}systemctl restart ${SERVICE_NAME}${NC}     重启服务"
  echo ""
}
do_install() {
  show_banner
  preflight_check "install"
  acquire_lock
  step "Step 1  获取最新版本"
  check_connectivity
  info "查询 GitHub 最新 Release..."
  local LATEST
  LATEST=$(get_latest_release)
  [[ -z "$LATEST" ]] && error "获取版本号失败，请检查网络后重试"
  success "最新版本：${BOLD}${LATEST}${NC}"
  local DOWNLOAD_URL; DOWNLOAD_URL=$(get_download_url "$LATEST")
  info "下载地址：${DOWNLOAD_URL}"
  step "Step 2  安装基础依赖（curl / gnupg / lsb-release）"
  _install_base_deps
  step "Step 3  安装 PostgreSQL 15+"
  _install_postgres
  step "Step 4  安装 Redis 7+"
  _install_redis
  load_config
  step "Step 6  配置 PostgreSQL 账号"
  _setup_postgres
  step "Step 7  创建用户与目录"
  if ! id "$SERVICE_USER" &>/dev/null; then
    useradd -r -s /usr/sbin/nologin -d "$INSTALL_DIR" "$SERVICE_USER"
    success "系统用户 ${SERVICE_USER} 已创建（低权限，无登录 shell）"
  else
    info "用户 ${SERVICE_USER} 已存在，跳过创建"
  fi
  mkdir -p "$INSTALL_DIR" "$DATA_DIR" "$LOG_DIR" "$CONFIG_DIR" "$BACKUP_DIR"
  chown -R "${SERVICE_USER}:${SERVICE_USER}" "$INSTALL_DIR" "$LOG_DIR" "$CONFIG_DIR"
  chmod 750 "$CONFIG_DIR"
  success "目录创建完成"
  step "Step 8  下载并校验 Sub2API 二进制（架构：${BIN_ARCH}）"
  local TMP_ARCHIVE; TMP_ARCHIVE=$(mktemp "${INSTALL_DIR}/sub2api-release.XXXXXX.tar.gz")
  if ! curl -fL --progress-bar -o "$TMP_ARCHIVE" "$DOWNLOAD_URL"; then
    rm -f "$TMP_ARCHIVE"
    error "下载失败，请检查网络或前往 https://github.com/${GITHUB_REPO}/releases 确认版本存在"
  fi
  verify_checksum "$TMP_ARCHIVE" "$LATEST"
  local TMP_BIN
  TMP_BIN=$(extract_and_verify "$TMP_ARCHIVE" "$INSTALL_DIR")
  rm -f "$TMP_ARCHIVE"
  if [[ -f "$BIN_PATH" ]]; then
    local OLD_TS; OLD_TS=$(date +%Y%m%d_%H%M%S)
    mv "$BIN_PATH" "${INSTALL_DIR}/sub2api.bak.${OLD_TS}"
    warn "已备份旧二进制 → sub2api.bak.${OLD_TS}"
  fi
  mv "$TMP_BIN" "$BIN_PATH"
  chmod +x "$BIN_PATH"
  chown "${SERVICE_USER}:${SERVICE_USER}" "$BIN_PATH"
  success "二进制安装完成：${BIN_PATH}"
  step "Step 9  配置 systemd 服务"
  _write_systemd_unit
  success "systemd 服务文件已写入：/etc/systemd/system/${SERVICE_NAME}.service"
  step "Step 10  安装并配置 Nginx 反向代理"
  _install_nginx
  _write_nginx_config
  step "Step 11  配置防火墙"
  _configure_firewall
  step "Step 12  配置日志轮转"
  _write_logrotate
  step "Step 13  配置定时备份（每日 03:30）"
  _write_backup_script
  echo "30 3 * * * root /bin/bash /usr/local/bin/sub2api-backup" \
    > /etc/cron.d/sub2api-backup
  chmod 644 /etc/cron.d/sub2api-backup
  success "定时备份已配置（每日 03:30，保留 ${BACKUP_KEEP_DAYS} 天）"
  step "Step 14  启动服务"
  if ss -ltn 2>/dev/null | grep -qE ":${PORT}[[:space:]]"; then
    local _port_owner
    _port_owner=$(ss -ltnp 2>/dev/null | grep ":${PORT}" | awk '{print $NF}' | head -1 || echo "未知进程")
    warn "端口 ${PORT} 已被占用（${_port_owner}）"
    warn "若不是旧的 sub2api 进程，请先释放端口，否则服务将无法绑定"
  fi
  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME" --quiet
  systemctl restart "$SERVICE_NAME"
  if wait_for_service "$SERVICE_NAME" 25; then
    success "服务启动成功"
    systemctl status "$SERVICE_NAME" --no-pager -l 2>/dev/null | head -12 | sed 's/^/  /' >&2
  else
    if systemctl is-failed --quiet "$SERVICE_NAME" 2>/dev/null; then
      warn "服务已 failed，正在回滚已安装文件..."
      systemctl stop    "$SERVICE_NAME" 2>/dev/null || true
      systemctl disable "$SERVICE_NAME" 2>/dev/null || true
      rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
      systemctl daemon-reload 2>/dev/null || true
      rm -f "$BIN_PATH"
      error "安装失败：服务进入 failed 状态，已回滚二进制与 systemd unit。\n  调试：journalctl -u ${SERVICE_NAME} -n 30 --no-pager"
    else
      warn "服务可能正在等待数据库/Redis 连接（属正常情况），继续安装流程"
      warn "请在 Setup Wizard 完成配置后再验证服务状态"
    fi
  fi
  step "Step 15  健康检查 & 保存配置"
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
    && error "未检测到已安装的 Sub2API 二进制（${BIN_PATH}），请先执行 install"
  step "检查更新"
  check_connectivity
  info "查询 GitHub 最新 Release..."
  local LATEST; LATEST=$(get_latest_release)
  [[ -z "$LATEST" ]] && error "获取最新版本失败，请检查网络后重试"
  local CURRENT="${INSTALLED_VERSION:-unknown}"
  info "当前版本（记录）：${YELLOW}${CURRENT}${NC}"
  info "GitHub 最新版本：${YELLOW}${LATEST}${NC}"
  if [[ "$CURRENT" == "$LATEST" ]]; then
    success "已是最新版本（${LATEST}），无需更新"
    exit 0
  fi
  local _pre_svc_state
  _pre_svc_state=$(systemctl is-active "$SERVICE_NAME" 2>/dev/null || echo "inactive")
  if [[ "$_pre_svc_state" == "failed" ]]; then
    warn "更新前服务处于 failed 状态，本次更新将同时重置故障标记"
  fi
  step "更新前备份数据"
  _backup_silent "pre-update" || warn "更新前备份失败，继续执行更新"
  step "下载新版本（${CURRENT} → ${LATEST}）"
  local DOWNLOAD_URL; DOWNLOAD_URL=$(get_download_url "$LATEST")
  info "下载地址：${DOWNLOAD_URL}"
  local TMP_ARCHIVE; TMP_ARCHIVE=$(mktemp "${INSTALL_DIR}/sub2api-release.XXXXXX.tar.gz")
  if ! curl -fL --progress-bar -o "$TMP_ARCHIVE" "$DOWNLOAD_URL"; then
    rm -f "$TMP_ARCHIVE"
    error "下载失败，更新中止（当前版本未受影响）"
  fi
  verify_checksum "$TMP_ARCHIVE" "$LATEST"
  local TMP_BIN
  TMP_BIN=$(extract_and_verify "$TMP_ARCHIVE" "$INSTALL_DIR")
  rm -f "$TMP_ARCHIVE"
  step "替换二进制并重启服务"
  local BAK_TS; BAK_TS=$(date +%Y%m%d_%H%M%S)
  local BAK_PATH="${INSTALL_DIR}/sub2api.bak.${BAK_TS}"
  info "停止服务..."
  systemctl stop "$SERVICE_NAME" 2>/dev/null || true
  cp "$BIN_PATH" "$BAK_PATH"
  info "旧二进制已备份：${BAK_PATH}"
  mv "$TMP_BIN" "$BIN_PATH"
  chmod +x "$BIN_PATH"
  chown "${SERVICE_USER}:${SERVICE_USER}" "$BIN_PATH"
  systemctl daemon-reload
  systemctl start "$SERVICE_NAME"
  if wait_for_service "$SERVICE_NAME" 25; then
    success "服务以新版本启动成功"
    INSTALLED_VERSION="$LATEST"
    save_config
    local -a _old_baks
    mapfile -t _old_baks < <(
      find "$INSTALL_DIR" -maxdepth 1 -name "sub2api.bak.*" -type f \
        -printf '%T@ %p\n' 2>/dev/null | sort -rn | awk 'NR>3{print $2}'
    )
    if [[ ${#_old_baks[@]} -gt 0 ]]; then
      rm -f "${_old_baks[@]}"
      info "已清理 ${#_old_baks[@]} 个过期旧二进制备份（保留最近 3 个）"
    fi
    _health_check
    echo ""
    echo -e "  ${BOLD}${GREEN}✅  更新完成：${YELLOW}${CURRENT}${GREEN} → ${YELLOW}${LATEST}${NC}"
    echo ""
  else
    warn "新版本（${LATEST}）启动失败，正在自动回滚到 ${CURRENT}..."
    systemctl stop "$SERVICE_NAME" 2>/dev/null || true
    mv "$BAK_PATH" "$BIN_PATH"
    chmod +x "$BIN_PATH"
    chown "${SERVICE_USER}:${SERVICE_USER}" "$BIN_PATH"
    systemctl start "$SERVICE_NAME" 2>/dev/null || true
    if wait_for_service "$SERVICE_NAME" 15; then
      success "已成功回滚到旧版本（${CURRENT}），服务已恢复"
    else
      warn "回滚后服务仍未正常启动，请手动检查：journalctl -u ${SERVICE_NAME} -n 30 --no-pager"
    fi
    error "更新失败，已自动回滚至 ${CURRENT}。\n  诊断：journalctl -u ${SERVICE_NAME} -n 50 --no-pager"
  fi
}
do_backup() {
  show_banner
  preflight_check "backup"
  load_config
  acquire_lock
  step "手动备份 Sub2API 数据"
  mkdir -p "$BACKUP_DIR"
  if [[ -n "${PG_DSN:-}" ]]; then
    if command -v pg_dump &>/dev/null; then
      local PG_ARCHIVE; PG_ARCHIVE="${BACKUP_DIR}/sub2api_db_$(date +%Y%m%d_%H%M%S).sql.gz"
      local PG_TMP="${PG_ARCHIVE}.tmp"
      info "执行 pg_dump..."
      if pg_dump "${PG_DSN}" 2>&1 | gzip > "$PG_TMP"; then
        mv "$PG_TMP" "$PG_ARCHIVE"
        local pg_sz; pg_sz=$(du -sh "$PG_ARCHIVE" 2>/dev/null | awk '{print $1}')
        success "数据库备份：${PG_ARCHIVE}（${pg_sz}）"
      else
        rm -f "$PG_TMP"
        warn "pg_dump 失败（请检查 PG_DSN 是否正确），继续备份配置文件"
      fi
    else
      warn "pg_dump 命令不存在，跳过数据库备份"
    fi
  else
    warn "PG_DSN 未配置，跳过数据库备份"
  fi
  if [[ -d "$CONFIG_DIR" ]]; then
    local CONF_ARCHIVE; CONF_ARCHIVE="${BACKUP_DIR}/sub2api_conf_$(date +%Y%m%d_%H%M%S).tar.gz"
    local CONF_TMP="${CONF_ARCHIVE}.tmp"
    if tar -czf "$CONF_TMP" \
        -C "$(dirname "$CONFIG_DIR")" "$(basename "$CONFIG_DIR")" 2>&1; then
      mv "$CONF_TMP" "$CONF_ARCHIVE"
      local cf_sz; cf_sz=$(du -sh "$CONF_ARCHIVE" 2>/dev/null | awk '{print $1}')
      success "配置目录备份：${CONF_ARCHIVE}（${cf_sz}）"
    else
      rm -f "$CONF_TMP"
      warn "配置目录备份失败（tar 报错）"
    fi
  else
    warn "配置目录不存在（${CONFIG_DIR}），跳过"
  fi
  if [[ -d "$DATA_DIR" ]]; then
    local DATA_ARCHIVE; DATA_ARCHIVE="${BACKUP_DIR}/sub2api_data_$(date +%Y%m%d_%H%M%S).tar.gz"
    local DATA_TMP="${DATA_ARCHIVE}.tmp"
    if tar -czf "$DATA_TMP" \
        --exclude="*.log" --exclude="*.log.*" \
        -C "$(dirname "$DATA_DIR")" "$(basename "$DATA_DIR")" 2>&1; then
      mv "$DATA_TMP" "$DATA_ARCHIVE"
      local da_sz; da_sz=$(du -sh "$DATA_ARCHIVE" 2>/dev/null | awk '{print $1}')
      success "数据目录备份：${DATA_ARCHIVE}（${da_sz}）"
    else
      rm -f "$DATA_TMP"
      warn "数据目录备份失败"
    fi
  fi
  release_lock
  success "备份流程完成，归档目录：${BACKUP_DIR}"
}
do_status() {
  show_banner
  preflight_check "status"
  load_config
  step "Sub2API 运行状态"
  echo -e "\n${BOLD}【systemd 服务】${NC}"
  if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    echo -e "  ${GREEN}[✓]${NC} 服务状态：${GREEN}running${NC}"
  elif systemctl is-failed --quiet "$SERVICE_NAME" 2>/dev/null; then
    echo -e "  ${RED}[✗]${NC} 服务状态：${RED}failed${NC}"
  else
    echo -e "  ${YELLOW}[!]${NC} 服务状态：${YELLOW}inactive / unknown${NC}"
  fi
  local _pid
  _pid=$(systemctl show -p MainPID --value "$SERVICE_NAME" 2>/dev/null || echo "0")
  if [[ "$_pid" != "0" && -d "/proc/${_pid}" ]]; then
    local _mem _cpu _uptime
    _mem=$(cat "/proc/${_pid}/status" 2>/dev/null \
      | grep -i 'VmRSS' | awk '{printf "%.1f MB", $2/1024}' || echo "N/A")
    _cpu=$(ps -p "$_pid" -o %cpu --no-headers 2>/dev/null | tr -d ' ' || echo "N/A")
    _uptime=$(ps -p "$_pid" -o etime --no-headers 2>/dev/null | tr -d ' ' || echo "N/A")
    echo -e "  PID：        ${_pid}"
    echo -e "  内存（RSS）：${_mem}"
    echo -e "  CPU 占用：   ${_cpu}%"
    echo -e "  运行时长：   ${_uptime}"
  fi
  echo -e "\n${BOLD}【版本信息】${NC}"
  echo -e "  已安装版本（记录）：${YELLOW}${INSTALLED_VERSION:-未知}${NC}"
  if [[ -x "$BIN_PATH" ]]; then
    local _bin_ver
    _bin_ver=$("$BIN_PATH" --version 2>/dev/null | head -1 || echo "（二进制不支持 --version）")
    echo -e "  二进制版本输出：    ${_bin_ver}"
  fi
  echo -e "\n${BOLD}【Nginx 状态】${NC}"
  if command -v nginx &>/dev/null; then
    if systemctl is-active --quiet nginx 2>/dev/null; then
      echo -e "  ${GREEN}[✓]${NC} nginx 服务运行中"
    else
      echo -e "  ${RED}[✗]${NC} nginx 服务未运行（systemctl start nginx）"
    fi
    local nginx_conf="/etc/nginx/sites-available/sub2api"
    local nginx_link="/etc/nginx/sites-enabled/sub2api"
    if [[ -f "$nginx_conf" ]]; then
      echo -e "  ${GREEN}[✓]${NC} 反代配置存在：${nginx_conf}"
      local proxy_pass
      proxy_pass=$(grep -oE 'proxy_pass[[:space:]]+[^;]+' "$nginx_conf" 2>/dev/null | awk '{print $2}' | head -1 || echo "N/A")
      echo -e "       代理目标：${proxy_pass}"
      local sn
      sn=$(grep -oE 'server_name[[:space:]]+[^;]+' "$nginx_conf" 2>/dev/null | awk '{$1=""; print $0}' | tr -d ' ' | head -1 || echo "_")
      echo -e "       server_name：${sn}"
    else
      echo -e "  ${YELLOW}[!]${NC} 未找到反代配置（${nginx_conf}）"
    fi
    if [[ -L "$nginx_link" ]]; then
      echo -e "  ${GREEN}[✓]${NC} sites-enabled 软链接已激活"
    else
      echo -e "  ${YELLOW}[!]${NC} sites-enabled 软链接不存在（ln -s ${nginx_conf} ${nginx_link}）"
    fi
    if nginx -t 2>/dev/null; then
      echo -e "  ${GREEN}[✓]${NC} nginx -t 语法校验通过"
    else
      echo -e "  ${RED}[✗]${NC} nginx -t 语法校验失败（请检查配置）"
    fi
  else
    echo -e "  ${YELLOW}[!]${NC} nginx 未安装"
  fi
  echo -e "\n${BOLD}【依赖服务连通性】${NC}"
  for _svc_port in "PostgreSQL:5432" "Redis:6379"; do
    local _name="${_svc_port%%:*}" _port="${_svc_port##*:}"
    if (echo >/dev/tcp/127.0.0.1/${_port}) 2>/dev/null; then
      echo -e "  ${GREEN}[✓]${NC} ${_name}（:${_port}）可达"
    else
      echo -e "  ${YELLOW}[!]${NC} ${_name}（:${_port}）不可达"
    fi
  done
  if [[ -n "${PG_DSN:-}" ]]; then
    local _dsn_masked
    _dsn_masked=$(echo "$PG_DSN" | sed 's|:\([^:@]*\)@|:***@|')
    echo -e "  PG_DSN（脱敏）：${_dsn_masked}"
  else
    echo -e "  ${YELLOW}[!]${NC} PG_DSN 未配置，pg_dump 备份不可用"
  fi
  echo -e "\n${BOLD}【目录信息】${NC}"
  for _d in "$INSTALL_DIR" "$DATA_DIR" "$LOG_DIR" "$CONFIG_DIR"; do
    if [[ -d "$_d" ]]; then
      local _sz; _sz=$(du -sh "$_d" 2>/dev/null | awk '{print $1}' || echo "?")
      echo -e "  ${GREEN}[✓]${NC} ${_d}（${_sz}）"
    else
      echo -e "  ${YELLOW}[!]${NC} ${_d}（不存在）"
    fi
  done
  echo -e "\n${BOLD}【备份信息】${NC}"
  if [[ -d "$BACKUP_DIR" ]]; then
    local bak_count bak_total_size
    bak_count=$(find "$BACKUP_DIR" -maxdepth 1 \
      \( -name "sub2api_*.tar.gz" -o -name "sub2api_db_*.sql.gz" \
         -o -name "sub2api_conf_*.tar.gz" \) \
      2>/dev/null | wc -l)
    bak_total_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | awk '{print $1}')
    echo -e "  备份目录：${BACKUP_DIR}（${bak_total_size}，共 ${bak_count} 个文件）"
    local _cnt=0
    while IFS= read -r f; do
      local _sz; _sz=$(du -sh "$f" 2>/dev/null | cut -f1 || echo "?")
      echo -e "  $((_cnt+1)). $(basename "$f")（${_sz}）"
      _cnt=$(( _cnt + 1 ))
    done < <(find "$BACKUP_DIR" -maxdepth 1 \
      \( -name "sub2api_*.tar.gz" -o -name "sub2api_db_*.sql.gz" \) \
      -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -5 | awk '{print $2}')
    [[ $_cnt -eq 0 ]] && echo -e "  ${YELLOW}[!]${NC} 暂无备份文件"
  else
    echo -e "  ${YELLOW}[!]${NC} 备份目录不存在：${BACKUP_DIR}"
  fi
  echo -e "\n${BOLD}【磁盘空间】${NC}"
  df -h "$INSTALL_DIR" 2>/dev/null \
    | awk 'NR==2{printf "  挂载点: %-15s  已用: %s / %s（%s 已用）\n", $6,$3,$2,$5}' || true
  echo -e "\n${BOLD}【HTTP 健康检查（本地 127.0.0.1:${PORT}）】${NC}"
  local HTTP_CODE
  HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}" --max-time 5 \
    "http://127.0.0.1:${PORT}/" 2>/dev/null || echo "000")
  if [[ "$HTTP_CODE" =~ ^(200|301|302)$ ]]; then
    echo -e "  ${GREEN}[✓]${NC} 本地接口响应正常：HTTP ${HTTP_CODE}"
  else
    echo -e "  ${YELLOW}[!]${NC} 本地接口响应：HTTP ${HTTP_CODE}（服务未运行 / 等待 DB 连接？）"
  fi
  echo -e "\n${BOLD}【防火墙规则（端口 ${PORT}）】${NC}"
  if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
    local ufw_rule
    ufw_rule=$(ufw status 2>/dev/null | grep "${PORT}" || true)
    if [[ -n "$ufw_rule" ]]; then
      echo -e "  ${GREEN}[✓]${NC} ufw 端口 ${PORT} 已放行"
    else
      echo -e "  ${YELLOW}[!]${NC} ufw 端口 ${PORT} 未在规则中"
    fi
  elif command -v iptables &>/dev/null; then
    if iptables -C INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null; then
      echo -e "  ${GREEN}[✓]${NC} iptables 端口 ${PORT} 已放行"
    else
      echo -e "  ${YELLOW}[!]${NC} iptables 端口 ${PORT} 未放行"
    fi
  else
    echo -e "  ${YELLOW}[!]${NC} 未检测到防火墙（可能依赖云安全组）"
  fi
  echo ""
}
do_uninstall() {
  show_banner
  preflight_check "uninstall"
  load_config
  acquire_lock
  [[ -z "${INSTALL_DIR:-}" ]] && error "INSTALL_DIR 未设置，卸载中止（配置文件：${CONF_FILE}）"
  [[ -z "${DATA_DIR:-}"    ]] && error "DATA_DIR 未设置，卸载中止"
  [[ -z "${BACKUP_DIR:-}"  ]] && error "BACKUP_DIR 未设置，卸载中止"
  [[ "${INSTALL_DIR}" == "/" ]] && error "INSTALL_DIR 为根目录（/），拒绝执行卸载"
  [[ "${DATA_DIR}"    == "/" ]] && error "DATA_DIR 为根目录（/），拒绝执行卸载"
  [[ "${BACKUP_DIR}"  == "/" ]] && error "BACKUP_DIR 为根目录（/），拒绝执行卸载"
  step "卸载 Sub2API"
  echo -e "${RED}${BOLD}"
  echo "  ⚠️  此操作将删除："
  echo "     · Sub2API 二进制及旧版备份（${INSTALL_DIR}/sub2api*）"
  echo "     · systemd 服务单元（/etc/systemd/system/${SERVICE_NAME}.service）"
  echo "     · Nginx 反代配置（/etc/nginx/sites-available/sub2api）"
  echo "     · Nginx sites-enabled 软链接（/etc/nginx/sites-enabled/sub2api）"
  echo "     · 日志轮转配置（/etc/logrotate.d/sub2api）"
  echo "     · 定时备份任务（/etc/cron.d/sub2api-backup）"
  echo "     · 备份脚本（/usr/local/bin/sub2api-backup）"
  echo "     · 部署配置文件（${CONF_FILE}）"
  echo ""
  echo "  ⚠️  PostgreSQL 数据库不会被删除（需手动清理）"
  echo "  数据目录（${DATA_DIR}）和配置目录（${CONFIG_DIR}）默认保留，可选是否删除。"
  echo -e "${NC}"
  prompt "确认继续卸载？（输入 YES 确认）："
  local _c; read -r _c
  [[ "$_c" != "YES" ]] && { info "已取消卸载"; exit 0; }
  prompt "是否同时删除本地数据目录（${DATA_DIR}）？[y/N]："
  local _del_data; read -r _del_data
  local DELETE_DATA=false
  [[ "${_del_data,,}" == "y" ]] && DELETE_DATA=true
  prompt "是否同时删除配置目录（${CONFIG_DIR}）？[y/N]："
  local _del_conf; read -r _del_conf
  local DELETE_CONF=false
  [[ "${_del_conf,,}" == "y" ]] && DELETE_CONF=true
  prompt "是否同时删除备份目录（${BACKUP_DIR}）？[y/N]："
  local _del_bak; read -r _del_bak
  local DELETE_BACKUP=false
  [[ "${_del_bak,,}" == "y" ]] && DELETE_BACKUP=true
  info "停止并禁用 ${SERVICE_NAME} 服务..."
  systemctl stop    "$SERVICE_NAME" 2>/dev/null || true
  systemctl disable "$SERVICE_NAME" 2>/dev/null || true
  rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
  systemctl daemon-reload
  success "systemd 服务已移除"
  rm -f "$BIN_PATH"
  find "$INSTALL_DIR" -maxdepth 1 -name "sub2api.bak.*"       -type f -delete 2>/dev/null || true
  find "$INSTALL_DIR" -maxdepth 1 -name "sub2api.tmp.*"       -type f -delete 2>/dev/null || true
  find "$INSTALL_DIR" -maxdepth 1 -name "sub2api-release.*.tar.gz" -type f -delete 2>/dev/null || true
  find "$INSTALL_DIR" -maxdepth 1 -name "sub2api-extract.*"   -type d -exec rm -rf {} + 2>/dev/null || true
  success "二进制及相关文件已删除"
  rm -f /etc/nginx/sites-enabled/sub2api
  rm -f /etc/nginx/sites-available/sub2api
  if command -v nginx &>/dev/null && nginx -t 2>/dev/null; then
    systemctl reload nginx 2>/dev/null || true
    success "Nginx 反代配置已清除，服务已重载"
  else
    success "Nginx 反代配置已清除"
  fi
  rm -f /etc/cron.d/sub2api-backup \
        /usr/local/bin/sub2api-backup \
        /etc/logrotate.d/sub2api
  success "定时任务、备份脚本、日志轮转配置已清除"
  rm -f "$CONF_FILE"
  success "部署配置文件已清除"
  if [[ -n "${LOG_DIR:-}" && "$LOG_DIR" != "." && "$LOG_DIR" != "/" && -d "$LOG_DIR" ]]; then
    rm -rf "$LOG_DIR"
    success "日志目录已删除：${LOG_DIR}"
  else
    warn "日志目录路径异常（${LOG_DIR:-未设置}），已跳过"
  fi
  if $DELETE_DATA; then
    rm -rf "$DATA_DIR"
    success "本地数据目录已删除：${DATA_DIR}"
    if [[ -d "$INSTALL_DIR" ]] && [[ -z "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]]; then
      rm -rf "$INSTALL_DIR"
      success "安装目录已清理：${INSTALL_DIR}"
    fi
  else
    info "本地数据目录已保留：${DATA_DIR}"
  fi
  if $DELETE_CONF; then
    rm -rf "$CONFIG_DIR"
    success "配置目录已删除：${CONFIG_DIR}"
  else
    info "配置目录已保留：${CONFIG_DIR}"
  fi
  if $DELETE_BACKUP; then
    rm -rf "$BACKUP_DIR"
    success "备份目录已删除：${BACKUP_DIR}"
  else
    info "备份目录已保留：${BACKUP_DIR}"
  fi
  if $DELETE_DATA && $DELETE_CONF && id "$SERVICE_USER" &>/dev/null; then
    userdel "$SERVICE_USER" 2>/dev/null \
      && success "系统用户 ${SERVICE_USER} 已删除" \
      || warn "系统用户 ${SERVICE_USER} 删除失败，可能被其他服务引用"
  fi
  echo ""
  echo -e "${BOLD}${GREEN}  ✅  Sub2API 已完全卸载${NC}"
  echo ""
  echo -e "  ${YELLOW}[提示]${NC} PostgreSQL 数据库数据未被删除"
  echo -e "  ${YELLOW}[提示]${NC} 手动清理数据库："
  echo -e "    ${CYAN}sudo -u postgres psql -c 'DROP DATABASE ${PG_DB};'${NC}"
  echo -e "    ${CYAN}sudo -u postgres psql -c 'DROP USER ${PG_USER};'${NC}"
  echo ""
}
