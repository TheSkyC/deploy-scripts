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
  [[ -s "$bin" ]] || error "二进制文件为空，疑似下载失败"
  local size
  size=$(wc -c < "$bin")
  [[ $size -lt 1048576 ]] \
    && error "二进制文件过小（${size} 字节），疑似下载不完整或 URL 返回了错误页（如 404 HTML）"
  local magic
  magic=$(dd if="$bin" bs=1 count=4 2>/dev/null | od -An -tx1 | tr -d ' \n' 2>/dev/null || true)
  if [[ "$magic" != "7f454c46" ]]; then
    error "二进制文件不是有效的 ELF 格式（magic: ${magic:-读取失败}）\n  请检查下载 URL 或网络环境是否有拦截/302 跳转"
  fi
  local size_mb=$(( size / 1024 / 1024 ))
  success "二进制校验通过（ELF，${size_mb} MB）"
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
    success "HTTP 健康检查通过（状态码 ${HTTP_CODE}）"
  else
    warn "健康检查返回 ${HTTP_CODE}，服务可能仍在初始化（属正常现象，稍后可用 status 再次确认）"
    warn "调试命令：journalctl -u ${SERVICE_NAME} -n 30 --no-pager"
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
    success "ufw 已放行端口 ${PORT}"
    FW_DONE=true
  fi
  if ! $FW_DONE && command -v iptables &>/dev/null; then
    if ! iptables -C INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null; then
      iptables -A INPUT -p tcp --dport "$PORT" -j ACCEPT
    fi
    if command -v netfilter-persistent &>/dev/null; then
      netfilter-persistent save 2>/dev/null \
        && success "iptables 规则已持久化（netfilter-persistent）" || true
    elif command -v iptables-save &>/dev/null; then
      mkdir -p /etc/iptables
      iptables-save > /etc/iptables/rules.v4 2>/dev/null \
        && info "iptables 规则已写入 /etc/iptables/rules.v4" \
        || warn "iptables 规则写入失败，重启后规则可能丢失"
    else
      warn "iptables 规则未持久化（重启后失效）。建议：apt-get install -y iptables-persistent && netfilter-persistent save"
    fi
    success "iptables 已放行端口 ${PORT}"
    FW_DONE=true
  fi
  $FW_DONE || warn "未检测到活跃防火墙，如有云安全组（如 AWS/阿里云/腾讯云）请手动放行端口 ${PORT}"
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
  success "日志轮转已配置（每日轮转，保留 14 天，自动压缩）"
}
_write_backup_script() {
  mkdir -p "$BACKUP_DIR"
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
BKSH_HEADER
  cat >> /usr/local/bin/new-api-backup << 'BKSH_BODY'

LOG="${BACKUP_DIR}/backup.log"
TS=$(date +%Y%m%d_%H%M%S)
ARCHIVE="${BACKUP_DIR}/new-api_${TS}.tar.gz"
ARCHIVE_TMP="${ARCHIVE}.tmp"

_log() { echo "$(date '+%F %T')  $*" >> "$LOG"; }
_log "── 开始备份 ────────────────────────────────────"

# Refuse to create an empty backup when the data directory is missing.
if [[ ! -d "${DATA_DIR}" ]]; then
  _log "[ERROR] 数据目录不存在（${DATA_DIR}），备份中止"
  exit 1
fi

mkdir -p "${BACKUP_DIR}"

# Flush SQLite WAL data and run an integrity check before archiving.
DB_FILE="${DATA_DIR}/one-api.db"
if command -v sqlite3 &>/dev/null && [[ -f "${DB_FILE}" ]]; then
  if sqlite3 "${DB_FILE}" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null; then
    _log "[OK] SQLite WAL checkpoint(TRUNCATE) 成功"
  else
    _log "[WARN] SQLite WAL flush 失败，备份继续（数据库可能有未落盘数据）"
  fi
  IC=$(sqlite3 "${DB_FILE}" "PRAGMA integrity_check;" 2>/dev/null || echo "error")
  if [[ "$IC" != "ok" ]]; then
    _log "[WARN] SQLite integrity_check 返回：${IC}，备份继续但数据库可能已损坏"
  fi
fi

# Write to a temporary archive first, then move it into place atomically.
if tar -czf "${ARCHIVE_TMP}" \
    --exclude="*.log" --exclude="*.log.*" \
    -C "$(dirname "${DATA_DIR}")" "$(basename "${DATA_DIR}")" 2>&1 | \
    while IFS= read -r line; do _log "[TAR] ${line}"; done; then
  mv "${ARCHIVE_TMP}" "${ARCHIVE}"
  SIZE=$(du -sh "${ARCHIVE}" 2>/dev/null | awk '{print $1}')
  _log "[OK] 备份成功：${ARCHIVE}（${SIZE}）"
else
  rm -f "${ARCHIVE_TMP}"
  _log "[ERROR] tar 失败，临时文件已清理"
  exit 1
fi

# Remove backups older than the configured retention window.
if [[ "${KEEP_DAYS}" -gt 0 ]]; then
  REMOVED=0
  while IFS= read -r f; do
    rm -f "$f" && REMOVED=$(( REMOVED + 1 )) || true
  done < <(find "${BACKUP_DIR}" -maxdepth 1 -name "new-api_*.tar.gz" -mtime "+${KEEP_DAYS}" 2>/dev/null)
  [[ $REMOVED -gt 0 ]] && _log "[OK] 已清理 ${REMOVED} 个超过 ${KEEP_DAYS} 天的旧备份"
fi

_log "── 备份完成 ────────────────────────────────────"
BKSH_BODY
  chmod 750 /usr/local/bin/new-api-backup
  success "备份脚本已写入：/usr/local/bin/new-api-backup"
}
_backup_silent() {
  local label="${1:-manual}"
  if [[ ! -d "$DATA_DIR" ]]; then
    warn "_backup_silent: 数据目录不存在（${DATA_DIR}），跳过备份"
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
    [[ "$_ic" != "ok" ]] && warn "SQLite integrity_check 警告（${_ic}），备份继续"
  fi
  if tar -czf "$archive_tmp" \
      --exclude="*.log" --exclude="*.log.*" \
      -C "$(dirname "$DATA_DIR")" "$(basename "$DATA_DIR")" 2>&1 >&2; then
    mv "$archive_tmp" "$archive"
    local sz; sz=$(du -sh "$archive" 2>/dev/null | awk '{print $1}')
    success "静默备份已创建：${archive}（${sz}）"
  else
    rm -f "$archive_tmp"
    warn "静默备份失败（tar 报错），继续执行..."
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
  echo "  ║           🎉  New API 部署完成！                     ║"
  echo "  ╠══════════════════════════════════════════════════════╣"
  echo -e "  ║  公网访问  ${CYAN}https://${DOMAIN}${GREEN}              ║"
  echo -e "  ║  内网直连  ${CYAN}http://${INTERNAL_IP}:${PORT}${GREEN}               ║"
  echo "  ╠══════════════════════════════════════════════════════╣"
  echo -e "  ║  默认账号  ${YELLOW}root${GREEN}                               ║"
  echo -e "  ║  默认密码  ${YELLOW}123456${GREEN}  ← 请登录后立即修改！      ║"
  echo "  ╠══════════════════════════════════════════════════════╣"
  echo -e "  ║  API 地址  ${CYAN}https://${DOMAIN}/v1${GREEN}             ║"
  echo -e "  ║  版本      ${YELLOW}${version}${GREEN}"
  echo "  ╠══════════════════════════════════════════════════════╣"
  echo -e "  ║  数据目录  ${YELLOW}${DATA_DIR}${GREEN}"
  echo -e "  ║  日志目录  ${YELLOW}${LOG_DIR}${GREEN}"
  echo -e "  ║  备份目录  ${YELLOW}${BACKUP_DIR}${GREEN}"
  echo "  ╚══════════════════════════════════════════════════════╝"
  echo -e "${NC}"
  echo -e "  ${BOLD}管理命令：${NC}"
  echo -e "    ${CYAN}bash $0 status${NC}      — 查看运行状态"
  echo -e "    ${CYAN}bash $0 update${NC}      — 更新到最新版"
  echo -e "    ${CYAN}bash $0 backup${NC}      — 立即备份数据"
  echo -e "    ${CYAN}bash $0 uninstall${NC}   — 卸载服务"
  echo ""
  echo -e "  ${BOLD}systemd 命令：${NC}"
  echo -e "    ${CYAN}systemctl status ${SERVICE_NAME}${NC}     查看状态"
  echo -e "    ${CYAN}journalctl -u ${SERVICE_NAME} -f${NC}     实时日志"
  echo -e "    ${CYAN}systemctl restart ${SERVICE_NAME}${NC}    重启服务"
  echo ""
  echo -e "  ${YELLOW}${BOLD}[CF 提醒]${NC} SSL/TLS 模式请设为「灵活」"
  echo -e "  ${YELLOW}${BOLD}[CF 提醒]${NC} 如遇流式响应（SSE）卡顿，在 CF 规则中关闭该域名的缓冲/缓存"
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
  local DOWNLOAD_URL
  DOWNLOAD_URL=$(get_download_url "$LATEST")
  step "Step 2  安装系统依赖"
  apt-get update -qq
  apt-get install -y -qq curl ca-certificates sqlite3
  success "依赖安装完成（curl / ca-certificates / sqlite3）"
  step "Step 3  创建用户与目录"
  if ! id "$SERVICE_USER" &>/dev/null; then
    useradd -r -s /usr/sbin/nologin -d "$INSTALL_DIR" "$SERVICE_USER"
    success "系统用户 ${SERVICE_USER} 已创建（低权限，无登录 shell）"
  else
    info "用户 ${SERVICE_USER} 已存在，跳过创建"
  fi
  mkdir -p "$INSTALL_DIR" "$DATA_DIR" "$LOG_DIR" "$BACKUP_DIR"
  chown -R "${SERVICE_USER}:${SERVICE_USER}" "$INSTALL_DIR" "$LOG_DIR" "$BACKUP_DIR"
  success "目录创建完成：${INSTALL_DIR} / ${DATA_DIR} / ${LOG_DIR}"
  step "Step 4  下载 New API 二进制（架构：${BIN_ARCH}）"
  info "下载地址：${DOWNLOAD_URL}"
  local TMP_BIN
  TMP_BIN=$(mktemp "${INSTALL_DIR}/new-api.tmp.XXXXXX")
  if ! curl -fL --progress-bar -o "$TMP_BIN" "$DOWNLOAD_URL"; then
    rm -f "$TMP_BIN"
    error "下载失败，请检查网络或前往 https://github.com/${GITHUB_REPO}/releases 确认版本存在"
  fi
  verify_binary "$TMP_BIN"
  if [[ -f "$BIN_PATH" ]]; then
    local OLD_TS; OLD_TS=$(date +%Y%m%d_%H%M%S)
    mv "$BIN_PATH" "${INSTALL_DIR}/new-api.bak.${OLD_TS}"
    warn "已备份旧二进制 → new-api.bak.${OLD_TS}"
  fi
  mv "$TMP_BIN" "$BIN_PATH"
  chmod +x "$BIN_PATH"
  chown -R "${SERVICE_USER}:${SERVICE_USER}" "$INSTALL_DIR"
  success "二进制安装完成：${BIN_PATH}"
  step "Step 5  生成安全配置"
  local SESSION_SECRET
  SESSION_SECRET=$(tr -dc 'A-Za-z0-9!@#$%^&*' </dev/urandom 2>/dev/null | head -c 40; true)
  success "SESSION_SECRET 已随机生成（40 位混合字符）"
  step "Step 6  配置 systemd 服务"
  _write_systemd_unit "$SESSION_SECRET"
  success "systemd 服务文件已写入：/etc/systemd/system/${SERVICE_NAME}.service"
  step "Step 7  配置防火墙"
  _configure_firewall
  step "Step 8  配置日志轮转"
  _write_logrotate
  step "Step 9  配置定时备份（每日 03:30）"
  _write_backup_script
  echo "30 3 * * * root /bin/bash /usr/local/bin/new-api-backup" \
    > /etc/cron.d/new-api-backup
  chmod 644 /etc/cron.d/new-api-backup
  success "定时备份已配置（每日 03:30，保留 ${BACKUP_KEEP_DAYS} 天）"
  step "Step 10  启动服务"
  if ss -ltn 2>/dev/null | grep -qE ":${PORT}[[:space:]]"; then
    local _port_owner
    _port_owner=$(ss -ltnp 2>/dev/null | grep ":${PORT}" | awk '{print $NF}' | head -1 || echo "未知进程")
    warn "端口 ${PORT} 已被占用（${_port_owner}）"
    warn "若不是旧的 new-api 进程，请先释放端口，否则服务将无法绑定"
  fi
  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME" --quiet
  systemctl restart "$SERVICE_NAME"
  if wait_for_service "$SERVICE_NAME" 20; then
    success "服务启动成功"
    systemctl status "$SERVICE_NAME" --no-pager -l | head -12 | sed 's/^/  /' >&2
  else
    warn "服务在 20 秒内未能正常启动，正在回滚已安装文件..."
    systemctl stop    "$SERVICE_NAME" 2>/dev/null || true
    systemctl disable "$SERVICE_NAME" 2>/dev/null || true
    rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
    systemctl daemon-reload 2>/dev/null || true
    rm -f "$BIN_PATH"
    error "安装失败：服务无法启动，已回滚二进制与 systemd unit。\n  调试命令：journalctl -u ${SERVICE_NAME} -n 30 --no-pager\n  （数据目录、日志目录已保留，修复原因后可重新执行 install）"
  fi
  step "Step 11  健康检查"
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
    && error "未检测到已安装的 New API 二进制（${BIN_PATH}），请先执行 install"
  step "检查更新"
  check_connectivity
  info "查询 GitHub 最新 Release..."
  local LATEST
  LATEST=$(get_latest_release)
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
    warn "注意：更新前服务处于 failed 状态，本次更新将同时重置故障标记"
    warn "如更新后仍有问题，请先检查已有错误：journalctl -u ${SERVICE_NAME} -n 50 --no-pager"
  fi
  step "更新前备份数据"
  _backup_silent "pre-update" || warn "更新前备份失败，继续执行更新（建议手动检查数据目录完整性）"
  step "下载新版本二进制（${CURRENT} → ${LATEST}）"
  local DOWNLOAD_URL
  DOWNLOAD_URL=$(get_download_url "$LATEST")
  info "下载地址：${DOWNLOAD_URL}"
  local TMP_BIN
  TMP_BIN=$(mktemp "${INSTALL_DIR}/new-api.tmp.XXXXXX")
  if ! curl -fL --progress-bar -o "$TMP_BIN" "$DOWNLOAD_URL"; then
    rm -f "$TMP_BIN"
    error "下载失败，更新中止（当前版本未受影响）"
  fi
  verify_binary "$TMP_BIN"
  step "替换二进制并重启服务"
  local BAK_TS; BAK_TS=$(date +%Y%m%d_%H%M%S)
  local BAK_PATH="${INSTALL_DIR}/new-api.bak.${BAK_TS}"
  info "停止服务..."
  systemctl stop "$SERVICE_NAME" 2>/dev/null || true
  cp "$BIN_PATH" "$BAK_PATH"
  info "旧二进制已备份：${BAK_PATH}"
  mv "$TMP_BIN" "$BIN_PATH"
  chmod +x "$BIN_PATH"
  chown "${SERVICE_USER}:${SERVICE_USER}" "$BIN_PATH"
  systemctl daemon-reload
  systemctl start "$SERVICE_NAME"
  if wait_for_service "$SERVICE_NAME" 20; then
    success "服务以新版本启动成功"
    INSTALLED_VERSION="$LATEST"
    save_config
    local -a _old_baks
    mapfile -t _old_baks < <(
      find "$INSTALL_DIR" -maxdepth 1 -name "new-api.bak.*" -type f \
        -printf '%T@ %p\n' 2>/dev/null | sort -rn | awk 'NR>3{print $2}'
    )
    if [[ ${#_old_baks[@]} -gt 0 ]]; then
      rm -f "${_old_baks[@]}"
      info "已清理 ${#_old_baks[@]} 个过期旧备份（保留最近 3 个）"
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
    error "更新失败，已自动回滚至 ${CURRENT}。\n  新版本诊断：journalctl -u ${SERVICE_NAME} -n 50 --no-pager\n  新版二进制已保留在：${BAK_PATH}（实为回滚前的新版）如需手动测试可重命名使用"
  fi
}
do_backup() {
  show_banner
  preflight_check "backup"
  load_config
  acquire_lock
  [[ ! -d "$DATA_DIR" ]] \
    && error "数据目录不存在（${DATA_DIR}），请先执行安装"
  step "手动备份 New API 数据"
  mkdir -p "$BACKUP_DIR"
  local DB_FILE="${DATA_DIR}/one-api.db"
  if command -v sqlite3 &>/dev/null && [[ -f "$DB_FILE" ]]; then
    sqlite3 "$DB_FILE" "PRAGMA wal_checkpoint(TRUNCATE);" 2>/dev/null \
      && success "SQLite WAL checkpoint 成功" \
      || warn "SQLite WAL flush 失败，备份继续（可能有少量未落盘数据）"
    local _ic
    _ic=$(sqlite3 "$DB_FILE" "PRAGMA integrity_check;" 2>/dev/null || echo "error")
    if [[ "$_ic" == "ok" ]]; then
      success "SQLite 完整性校验通过"
    else
      warn "SQLite 完整性校验失败（${_ic}），备份继续，但数据库可能已损坏"
    fi
  fi
  local TS; TS=$(date +%Y%m%d_%H%M%S)
  local ARCHIVE="${BACKUP_DIR}/new-api_${TS}.tar.gz"
  local ARCHIVE_TMP="${ARCHIVE}.tmp"
  info "备份中：${DATA_DIR} → ${ARCHIVE}"
  if tar -czf "$ARCHIVE_TMP" \
      --exclude="*.log" --exclude="*.log.*" \
      -C "$(dirname "$DATA_DIR")" "$(basename "$DATA_DIR")" 2>&1; then
    mv "$ARCHIVE_TMP" "$ARCHIVE"
    local SZ; SZ=$(du -sh "$ARCHIVE" 2>/dev/null | awk '{print $1}')
    success "备份完成：${ARCHIVE}（${SZ}）"
  else
    rm -f "$ARCHIVE_TMP"
    error "备份失败，请检查磁盘空间（${BACKUP_DIR} 所在磁盘）"
  fi
  local _cleaned=0
  while IFS= read -r f; do
    rm -f "$f" && _cleaned=$(( _cleaned + 1 )) || true
  done < <(find "$BACKUP_DIR" -maxdepth 1 -name "new-api_*.tar.gz" \
           -mtime "+${BACKUP_KEEP_DAYS}" 2>/dev/null)
  [[ $_cleaned -gt 0 ]] && info "已清理 ${_cleaned} 个超过 ${BACKUP_KEEP_DAYS} 天的旧备份"
  echo ""
  info "备份列表（${BACKUP_DIR}，最近 10 个）："
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
    info "合计 ${_total} 个备份"
  else
    warn "暂无备份文件"
  fi
  echo ""
  release_lock
}
do_status() {
  show_banner
  preflight_check "status"
  load_config
  [[ $EUID -ne 0 ]] && warn "以非 root 运行，部分状态信息可能不完整（建议：sudo bash $0 status）"
  step "New API 系统状态"
  echo -e "\n${BOLD}【systemd 服务状态】${NC}"
  systemctl is-active --quiet "$SERVICE_NAME" \
    && echo -e "  ${GREEN}[✓]${NC} ${SERVICE_NAME} 运行中" \
    || echo -e "  ${RED}[✗]${NC} ${SERVICE_NAME} 未运行"
  systemctl status "$SERVICE_NAME" --no-pager -l 2>/dev/null \
    | tail -n +3 | head -10 | sed 's/^/  /' || true
  echo -e "\n${BOLD}【版本信息】${NC}"
  if [[ -x "$BIN_PATH" ]]; then
    echo -e "  记录版本：  ${YELLOW}${INSTALLED_VERSION:-未知}${NC}"
    echo -e "  二进制路径：${BIN_PATH}"
    echo -e "  二进制时间：$(stat -c '%y' "$BIN_PATH" 2>/dev/null | cut -d'.' -f1 || echo '未知')"
    echo -e "  二进制大小：$(du -sh "$BIN_PATH" 2>/dev/null | cut -f1 || echo '未知')"
  else
    echo -e "  ${RED}[✗]${NC} 未找到二进制：${BIN_PATH}"
  fi
  echo -e "\n${BOLD}【进程资源】${NC}"
  local pid
  pid=$(systemctl show "$SERVICE_NAME" --property=MainPID --value 2>/dev/null || echo "0")
  if [[ "$pid" -gt 0 ]] 2>/dev/null; then
    local mem cpu
    mem=$(ps -p "$pid" -o rss= 2>/dev/null | awk '{printf "%.1f MB", $1/1024}' || echo "N/A")
    cpu=$(ps -p "$pid" -o %cpu= 2>/dev/null | tr -d ' ' || echo "N/A")
    echo -e "  进程 PID：  ${pid}"
    echo -e "  内存占用：  ${mem}"
    echo -e "  CPU 使用：  ${cpu}%"
    echo -e "  启动时间：  $(ps -p "$pid" -o lstart= 2>/dev/null | tr -s ' ' || echo 'N/A')"
  else
    echo -e "  ${YELLOW}[!]${NC} 服务未运行，无进程信息"
  fi
  echo -e "\n${BOLD}【目录信息】${NC}"
  if [[ -d "$DATA_DIR" ]]; then
    local data_size; data_size=$(du -sh "$DATA_DIR" 2>/dev/null | awk '{print $1}')
    echo -e "  数据目录：  ${DATA_DIR}（${data_size}）"
    if [[ -f "${DATA_DIR}/one-api.db" ]]; then
      local db_size; db_size=$(du -sh "${DATA_DIR}/one-api.db" 2>/dev/null | awk '{print $1}')
      echo -e "  数据库：    one-api.db（${db_size}）"
    fi
  else
    echo -e "  ${RED}[✗]${NC} 数据目录不存在：${DATA_DIR}"
  fi
  echo -e "  日志目录：  ${LOG_DIR}"
  echo -e "\n${BOLD}【备份信息】${NC}"
  if [[ -d "$BACKUP_DIR" ]]; then
    local bak_count bak_total_size
    bak_count=$(find "$BACKUP_DIR" -maxdepth 1 -name "new-api_*.tar.gz" 2>/dev/null | wc -l)
    bak_total_size=$(du -sh "$BACKUP_DIR" 2>/dev/null | awk '{print $1}')
    echo -e "  备份目录：  ${BACKUP_DIR}（${bak_total_size}，共 ${bak_count} 个）"
    local _cnt=0
    while IFS= read -r f; do
      local _sz; _sz=$(du -sh "$f" 2>/dev/null | cut -f1 || echo "?")
      echo -e "  $((_cnt+1)). $(basename "$f")（${_sz}）"
      _cnt=$(( _cnt + 1 ))
    done < <(find "$BACKUP_DIR" -maxdepth 1 -name "new-api_*.tar.gz" \
             -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -3 | awk '{print $2}')
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
    echo -e "  ${YELLOW}[!]${NC} 本地接口响应：HTTP ${HTTP_CODE}（服务未运行、端口错误或仍在初始化？）"
  fi
  echo -e "\n${BOLD}【防火墙规则（端口 ${PORT}）】${NC}"
  if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
    local ufw_rule
    ufw_rule=$(ufw status 2>/dev/null | grep "${PORT}" || true)
    if [[ -n "$ufw_rule" ]]; then
      echo -e "  ${GREEN}[✓]${NC} ufw 端口 ${PORT} 已放行"
      echo "$ufw_rule" | sed 's/^/  /'
    else
      echo -e "  ${YELLOW}[!]${NC} ufw 端口 ${PORT} 未在规则中（服务可能无法从外部访问）"
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
  [[ -z "${INSTALL_DIR:-}" ]] && error "INSTALL_DIR 未设置，卸载中止（请确认配置文件 ${CONF_FILE} 存在）"
  [[ -z "${DATA_DIR:-}"    ]] && error "DATA_DIR 未设置，卸载中止"
  [[ -z "${BACKUP_DIR:-}"  ]] && error "BACKUP_DIR 未设置，卸载中止"
  [[ "${INSTALL_DIR}" == "/" ]] && error "INSTALL_DIR 为根目录（/），拒绝执行卸载"
  [[ "${DATA_DIR}"    == "/" ]] && error "DATA_DIR 为根目录（/），拒绝执行卸载"
  [[ "${BACKUP_DIR}"  == "/" ]] && error "BACKUP_DIR 为根目录（/），拒绝执行卸载"
  step "卸载 New API"
  echo -e "${RED}${BOLD}"
  echo "  ⚠️  此操作将删除："
  echo "     · New API 二进制及旧版备份（${INSTALL_DIR}/new-api*）"
  echo "     · systemd 服务单元（/etc/systemd/system/${SERVICE_NAME}.service）"
  echo "     · 日志轮转配置（/etc/logrotate.d/new-api）"
  echo "     · 定时备份任务（/etc/cron.d/new-api-backup）"
  echo "     · 备份脚本（/usr/local/bin/new-api-backup）"
  echo "     · 部署配置文件（${CONF_FILE}）"
  echo ""
  echo "  数据目录（${DATA_DIR}）默认保留，可选是否删除。"
  echo "  备份目录（${BACKUP_DIR}）默认保留，可选是否删除。"
  echo -e "${NC}"
  prompt "确认继续卸载？（输入 YES 确认）："
  local _c; read -r _c
  [[ "$_c" != "YES" ]] && { info "已取消卸载"; exit 0; }
  prompt "是否同时删除数据目录（${DATA_DIR}）？[y/N]："
  local _del_data; read -r _del_data
  local DELETE_DATA=false
  [[ "${_del_data,,}" == "y" ]] && DELETE_DATA=true
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
  find "$INSTALL_DIR" -maxdepth 1 -name "new-api.bak.*" -type f -delete 2>/dev/null || true
  find "$INSTALL_DIR" -maxdepth 1 -name "new-api.tmp.*" -type f -delete 2>/dev/null || true
  success "二进制及相关文件已删除"
  rm -f /etc/cron.d/new-api-backup \
        /usr/local/bin/new-api-backup \
        /etc/logrotate.d/new-api
  success "定时任务、备份脚本、日志轮转配置已清除"
  rm -f "$CONF_FILE"
  success "部署配置文件已清除"
  if [[ -n "${LOG_DIR:-}" && "$LOG_DIR" != "." && "$LOG_DIR" != "/" && -d "$LOG_DIR" ]]; then
    rm -rf "$LOG_DIR"
    success "日志目录已删除：${LOG_DIR}"
  else
    warn "日志目录路径异常（${LOG_DIR:-未设置}），已跳过删除，请手动清理"
  fi
  if $DELETE_DATA; then
    rm -rf "$DATA_DIR"
    success "数据目录已删除：${DATA_DIR}"
    if [[ -d "$INSTALL_DIR" ]] && [[ -z "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]]; then
      rm -rf "$INSTALL_DIR"
      success "安装目录已清理：${INSTALL_DIR}"
    fi
  else
    info "数据目录已保留：${DATA_DIR}"
  fi
  if $DELETE_BACKUP; then
    rm -rf "$BACKUP_DIR"
    success "备份目录已删除：${BACKUP_DIR}"
  else
    info "备份目录已保留：${BACKUP_DIR}"
  fi
  if $DELETE_DATA && id "$SERVICE_USER" &>/dev/null; then
    userdel "$SERVICE_USER" 2>/dev/null \
      && success "系统用户 ${SERVICE_USER} 已删除" \
      || warn "系统用户 ${SERVICE_USER} 删除失败，可能被其他服务引用"
  fi
  echo ""
  echo -e "${BOLD}${GREEN}  ✅  New API 已完全卸载${NC}"
  if ! $DELETE_DATA; then
    echo -e "  ${YELLOW}[提示]${NC} 数据保留在：${DATA_DIR}"
    echo -e "  ${YELLOW}[提示]${NC} 确认不再需要时，可手动执行：${CYAN}rm -rf ${DATA_DIR}${NC}"
  fi
  if ! $DELETE_BACKUP; then
    echo -e "  ${YELLOW}[提示]${NC} 备份保留在：${BACKUP_DIR}"
  fi
  echo ""
}
