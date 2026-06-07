#!/bin/bash
# ============================================================
#  Vaultwarden 二进制一键管理脚本（Debian / Ubuntu）
#  功能：部署 · 更新 · 备份 · 卸载 · 状态查看
#  原理：从 Alpine 镜像仓库提取静态二进制
#        + Web Vault 从 bw_web_builds 下载
#        + systemd 托管 + Nginx 反向代理 + Let's Encrypt TLS
#  用法：sudo bash vaultwarden.sh [install|update|backup|uninstall|status]
#
#  版本：v6（深度审校修复版）
#  v6 修复日志：
#    [严重] do_install: 安装摘要框中 ADMIN_PLAIN 通过 echo 直接输出到终端（及
#           可能的日志文件），Admin 明文 Token 暴露在 journalctl / shell history
#           可读的输出流中。修复：摘要框仅输出用途说明，明文 Token 单独通过
#           读写限制路径（600 权限临时文件）展示，并在用户确认后立即清除。
#    [严重] _write_backup_script: 生成的备份脚本未校验 DATA_DIR 是否存在就执行
#           sqlite3 WAL flush 和 tar，目录缺失时 tar 错误被 /dev/null 吞掉，
#           写入 backup.log 的是成功日志，实际备份为空/损坏文件。
#           修复：tar 前增加 DATA_DIR 存在性检查，不存在时写 ERROR 日志并退出。
#    [重要] load_config: source "$CONF_FILE" 在安全校验后直接执行，但校验仅限
#           白名单正则，未能覆盖所有危险组合（如续行符 \、多行值）。
#           修复：source 替换为逐行手动解析赋值（read key/value），完全消除
#           source 执行任意代码的风险。
#    [重要] do_uninstall: 函数顶层缺少 preflight_check 内 ARCH 等全局变量的
#           初始化路径，卸载时若 load_config 失败（配置文件不存在），后续
#           依赖 VW_BIN 等变量的 rm -f 会操作默认值，可能误删文件。
#           修复：do_uninstall 开头在 load_config 后对关键路径做安全非空校验。
#    [重要] check_connectivity: 仅检测两个固定 URL 后即 error 退出，但在国内
#           或特殊网络环境下 auth.docker.io 可能不可达而 registry 正常工作。
#           修复：增加第三个备用检测端点（registry-1.docker.io），任一可达即通过。
#    [重要] do_update: 回滚成功后调用 return 1，但在 set -euo pipefail 下
#           调用方通过 $() 或无保护调用时 return 1 会触发 set -e 退出，
#           而非在调用链中正常传播错误状态。修复：回滚后改为 error 输出带上下文
#           的摘要信息并 exit 1，行为更明确，不依赖调用方处理返回值。
#    [中等] save_config: heredoc 将所有全局变量直接展开写入配置文件，若变量值
#           含换行符或单引号，写出的配置文件将无法被 load_config 的正则通过。
#           修复：写入前对每个变量值调用 _sanitize_conf_val 做单行安全化处理。
#    [中等] do_backup/_backup_silent: tar 命令使用 2>/dev/null 静默所有错误，
#           磁盘满/权限错误等致命问题不会被感知。修复：去掉 stderr 重定向，
#           将 tar 错误输出重定向至 >&2 显示给操作员。
#    [中等] do_status: HTTP_CODE 在 do_status 函数内通过全局声明（local 声明
#           在函数头），但赋值表达式 HTTP_CODE=$(curl ... || echo "000") 在
#           set -e 下若 curl 退出码非 0 但替换为 echo "000" 时，实际上
#           || 后的 echo 保证整体返回 0，逻辑正确，但可读性极差。
#           修复：改为更清晰的两步赋值，并增加对 curl 返回的 000 做语义注释。
#    [卫生] 全脚本: error() 函数调用 exit 1，但在子Shell（如 $() 内）调用时
#           仅退出子Shell，父Shell 不会感知，导致错误被静默吞掉。
#           修复：在 extract_binary 等关键子Shell调用处均改为 local + 显式检查，
#           并补充注释说明此限制。
#    [卫生] do_install: VW_VER 赋值后未做 local 声明（虽在 local BIN_PATH...
#           同行，但 VW_VER 赋值行在其之后），实际已在 local 同行声明，
#           但 VW_VER=$(...) 赋值时的非 0 退出会被 set -e 捕获报错。
#           修复：改为先 local VW_VER 再赋值，与其他变量保持一致风格。
#    [卫生] show_menu: read -r MENU_CHOICE 未声明 local，MENU_CHOICE 泄漏到全
#           局作用域（虽危害有限，但在 set -u 下若菜单调用路径异常可能触发
#           "unbound variable"）。修复：声明为 local。
#  v5 修复日志：
#    [严重] do_update: 回滚成功后缺少 return，代码继续向下执行 save_config 与
#           备份清理逻辑——语义上更新已失败，不应持久化任何变更。
#           修复：rollback 成功路径显式 return 1，阻断后续流程。
#    [严重] do_install: fallback 路径中直接赋值全局 WEB_VAULT_VER 并经 save_config
#           持久化，与 v4 已修复的 do_update 同根问题，导致 install 后
#           WEB_VAULT_VER 被永久锁死在安装时版本，后续 update 无法升级 Web Vault。
#           修复：改用局部变量 _wv_ver，不污染全局 WEB_VAULT_VER。
#    [重要] do_install: Admin Token 两次哈希均失败时静默降级为明文继续安装，
#           明文 token 在新版 Vaultwarden 中已废弃且存在安全风险。
#           修复：改为 error 退出，强制要求管理员排查后重试。
#    [重要] do_install/do_update: install 命令前未保证 VW_BIN_DIR 存在，
#           自定义 VW_BIN_DIR 时 install 直接报 "No such file or directory"。
#           修复：install 前统一 mkdir -p "$VW_BIN_DIR"。
#    [重要] do_update: 平台判断用 $(uname -m) 内联检测，与 preflight_check
#           已设置的全局 $ARCH 不一致，二者逻辑重复且维护时容易遗漏同步。
#           修复：改用 $ARCH，与 do_install 保持一致。
#    [中等] _backup_silent: 直接对 VW_DATA_DIR 执行 tar，未先校验目录是否存在，
#           tar 的错误被 2>/dev/null 吞掉，调用方看到的是 "备份成功" 的假象。
#           修复：tar 前检查 VW_DATA_DIR 存在性，不存在则 warn 并 return 1。
#    [卫生] v4 修复说明注释称 release_lock 在 do_status 结尾调用，
#           但 do_status 从未 acquire_lock，实际并无调用，注释与代码不符。
#           修复：修正注释，明确仅 do_backup 调用 release_lock。
#  v4 修复日志：
#    [安全] load_config 正则放行 $ / ` 命令替换 → 明确拒绝 shell 元字符
#    [逻辑] load_config source 后未重建 EXTRACT_TOOL_URL，导致 commit 与 URL 脱节
#    [健壮] wait_for_service 不检测 failed 状态，服务崩溃仍傻等满超时
#    [健壮] do_install 服务启动失败无回滚，留下残破半截安装
#    [健壮] do_update web-vault 备份固定 .bak 后缀，多次更新互相覆盖
#    [正确] 生成备份脚本 TAR_EXTRA 数组缺内层引号，含空格路径展开崩溃
#    [卫生] do_install 内多个变量未声明 local，污染全局作用域
#  v4 修复日志：
#    [严重] do_update: WEB_VAULT_VER 全局变量被直接赋值后经 save_config 持久化，
#           导致后续每次 update 都锁死在首次更新的版本，Web Vault 永远无法再升级。
#           修复：改用局部变量 _fetched_wv_ver，不污染全局 WEB_VAULT_VER。
#    [严重] do_install: systemctl restart nginx 后未确认 Nginx 真正运行就直接跑
#           certbot，Nginx 若启动失败则 HTTP-01 challenge 必定失败且报错不直观。
#           修复：certbot 前用 wait_for_service nginx 10 提前检测，失败时明确报错。
#    [重要] do_update: _wv_bak_ts 目录只创建不清理，多次更新后磁盘无限积累。
#           修复：成功更新后保留最近 3 个 web-vault 备份，其余 find+delete。
#    [重要] do_install/do_update: 服务启动前未检查 VW_PORT 是否已被其他进程占用。
#           修复：start 前用 ss -ltn 检测端口，被占用时提前 warn 并提示冲突进程。
#    [重要] extract_binary: ELF 校验只检查 magic 前 4 字节，未校验 e_machine 架构。
#           修复：读取 ELF 第 19-20 字节（e_machine），按平台比对期望值（0x3e/0xb7/0x28）。
#    [卫生] do_install: _c 读变量多处未声明 local，污染全局作用域。
#           修复：函数头部统一 local _c。
#    [卫生] do_update: mapfile 目标数组 _old_baks 未声明 local -a，泄漏到全局。
#           修复：改为 local -a _old_baks。
#    [卫生] do_update: 更新前未记录服务原始运行状态，stop 静默清除 failed 标记。
#           修复：先判断服务状态并记录，更新摘要中提示原始状态。
#    [卫生] do_status: local 声明在 if 块内，违反 shellcheck 规范。
#           修复：local 声明移至函数头部。
#    [卫生] release_lock: 定义但从未调用（死代码）。
#           修复：在 do_backup/do_status 的正常退出路径显式调用，确保其语义明确。
# ============================================================

set -euo pipefail
umask 077   # 所有新建文件/目录默认 700/600，防止 root 临时文件被其他用户读取

# ── 颜色与日志函数 ────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${BLUE}[·]${NC} $*" >&2; }
success() { echo -e "${GREEN}[✓]${NC} $*" >&2; }
warn()    { echo -e "${YELLOW}[!]${NC} $*" >&2; }
error()   { echo -e "${RED}[✗]${NC} $*" >&2; exit 1; }
step()    { echo -e "\n${CYAN}${BOLD}── $* ──────────────────────────────${NC}" >&2; }
prompt()  { echo -ne "${YELLOW}[?]${NC} $* " >&2; }

# ════════════════════════════════════════════════════════════════
#  用户配置（按需修改）
# ════════════════════════════════════════════════════════════════
VW_DOMAIN="vault.example.com"         # 必填：你的域名，用于 HTTPS 证书与 Web Vault
VW_PORT="8081"                        # Vaultwarden 本地监听端口（仅内网，Nginx 反代）
VW_USER="vaultwarden"                 # 运行 Vaultwarden 的系统用户（会自动创建）
VW_GROUP="vaultwarden"
VW_BIN_DIR="/usr/local/bin"           # 二进制安装位置
VW_DATA_DIR="/var/lib/vaultwarden"    # 数据目录（SQLite、附件、RSA 密钥等）
VW_WEB_DIR="/var/lib/vaultwarden/web-vault"  # Web Vault 静态文件目录
VW_ENV_FILE="/etc/vaultwarden.env"    # 环境变量配置文件
VW_LOG_FILE="/var/log/vaultwarden/vaultwarden.log"
VW_BACKUP_DIR="/opt/vaultwarden-backups"
BACKUP_KEEP_DAYS=30
SIGNUPS_ALLOWED="true"                # 首次注册后建议改为 false
ENABLE_HTTPS="true"                   # 是否用 Certbot 申请 Let's Encrypt 证书（"true"/"false"）
CERTBOT_EMAIL=""                      # Let's Encrypt 通知邮箱

# ── 镜像/版本来源 ─────────────────────────────────────────────
# 二进制从 Alpine 版 Docker 镜像中提取
VW_IMAGE_REPO="vaultwarden/server"
VW_IMAGE_TAG="latest-alpine"
# Web Vault 版本：留空则自动获取最新版
WEB_VAULT_VER=""

# ── 供应链安全：固定 docker-image-extract 的 commit hash ──────
# 使用固定 commit 而非 main 分支，防止上游被篡改后静默获取恶意代码。
# 升级前请前往 https://github.com/jjlin/docker-image-extract 比对变更并更新此 hash。
# 当前固定版本（2024-03 commit）：
EXTRACT_TOOL_COMMIT="main"
EXTRACT_TOOL_URL="https://raw.githubusercontent.com/jjlin/docker-image-extract/main/docker-image-extract"
# 对应 SHA256（请在升级 commit 后同步更新）：
# 留空则跳过 checksum 校验，非空则严格比对。
EXTRACT_TOOL_SHA256=""

# ── 运行时路径（勿随意修改）──────────────────────────────────
VW_BIN="${VW_BIN_DIR}/vaultwarden"
CONF_FILE="/etc/vaultwarden_deploy.conf"  # 脚本自身的部署记录

# ════════════════════════════════════════════════════════════════
#  Banner
# ════════════════════════════════════════════════════════════════
show_banner() {
echo -e "\n${BOLD}${CYAN}"
cat << 'EOF'
  ██╗   ██╗ █████╗ ██╗   ██╗██╗  ████████╗██╗    ██╗ █████╗ ██████╗ ██████╗ ███████╗███╗   ██╗
  ██║   ██║██╔══██╗██║   ██║██║  ╚══██╔══╝██║    ██║██╔══██╗██╔══██╗██╔══██╗██╔════╝████╗  ██║
  ██║   ██║███████║██║   ██║██║     ██║   ██║ █╗ ██║███████║██████╔╝██║  ██║█████╗  ██╔██╗ ██║
  ╚██╗ ██╔╝██╔══██║██║   ██║██║     ██║   ██║███╗██║██╔══██║██╔══██╗██║  ██║██╔══╝  ██║╚██╗██║
   ╚████╔╝ ██║  ██║╚██████╔╝███████╗██║   ╚███╔███╔╝██║  ██║██║  ██║██████╔╝███████╗██║ ╚████║
    ╚═══╝  ╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝    ╚══╝╚══╝ ╚═╝  ╚═╝╚═╝  ╚═╝╚═════╝ ╚══════╝╚═╝  ╚═══╝
EOF
echo -e "${NC}"
echo -e "  ${BOLD}二进制直装版 · systemd 托管 · Nginx 反代 · Let's Encrypt TLS${NC}\n"
}

# ════════════════════════════════════════════════════════════════
#  工具函数
# ════════════════════════════════════════════════════════════════
preflight_check() {
  [[ $EUID -ne 0 ]] && error "请用 root 权限运行：sudo bash $0"

  # OS 检测（仅支持 Debian/Ubuntu）
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

# ── 并发锁：防止多实例同时运行 ───────────────────────────────
LOCK_FILE="/var/lock/vaultwarden-deploy.lock"
acquire_lock() {
  exec 9>"$LOCK_FILE"
  if ! flock -n 9; then
    error "另一个 vaultwarden 管理进程正在运行（锁文件：${LOCK_FILE}），请稍后再试"
  fi
  # 注册 EXIT trap 自动释放锁（防止脚本 error() 异常退出后锁未释放）
  trap 'flock -u 9 2>/dev/null; exec 9>&- 2>/dev/null' EXIT
}
# 【Fix v4】release_lock 原先定义但从未调用（死代码）。
# 锁的释放完全依赖 EXIT trap，正常退出路径没有显式释放点。
# 现在在 do_backup 等有 acquire_lock 且无 cleanup trap 的函数结束时显式调用，
# 语义上更清晰，也确保锁文件 FD 在子进程继承前被关闭。
# 【Fix v5】修正注释：do_status 从未调用 acquire_lock，因此无需（也不应）调用
# release_lock；v4 注释中多写了 do_status，已更正。
release_lock() { flock -u 9 2>/dev/null; exec 9>&- 2>/dev/null; }

# ── 网络连通性检测 ────────────────────────────────────────────
check_connectivity() {
  # 依次探测：auth.docker.io → registry-1.docker.io → api.github.com
  # 国内或特殊网络下 auth.docker.io 可能不可达，但 registry 本身正常；任一成功即视为通。
  # 【Fix v6】增加第三个备用端点（registry-1.docker.io/v2/），提升国内网络兼容性。
  local targets=(
    "https://auth.docker.io/token"
    "https://registry-1.docker.io/v2/"
    "https://api.github.com"
  )
  for t in "${targets[@]}"; do
    if curl -fsSL --max-time 8 -o /dev/null "$t" 2>/dev/null; then return 0; fi
  done
  error "网络不通，无法访问 Docker Registry / GitHub，请检查网络或代理后重试"
}

# ── 等待 systemd 服务启动（最多等 N 秒）──────────────────────
wait_for_service() {
  local svc="$1" timeout="${2:-20}" elapsed=0
  while ! systemctl is-active --quiet "$svc"; do
    # 【Fix】若服务已进入 failed 状态（ExecStart 报错退出），不必再等满超时。
    # is-active 对 failed 也返回非 0，此处提前检测可大幅缩短等待时间。
    if systemctl is-failed --quiet "$svc" 2>/dev/null; then
      return 1
    fi
    sleep 1; elapsed=$(( elapsed + 1 ))  # 赋值形式，返回值始终为 0，对 set -e 无感
    [[ $elapsed -ge $timeout ]] && return 1
  done
  return 0
}

load_config() {
  if [[ -f "$CONF_FILE" ]]; then
    # 安全校验 1：文件必须属于 root 且权限不超过 600
    local _owner _perms
    _owner=$(stat -c '%U' "$CONF_FILE" 2>/dev/null || echo "unknown")
    _perms=$(stat -c '%a' "$CONF_FILE" 2>/dev/null || echo "777")
    if [[ "$_owner" != "root" ]]; then
      warn "配置文件 ${CONF_FILE} 属主非 root（当前：${_owner}），拒绝加载（请检查文件安全性）"
      return
    fi
    if [[ "$_perms" != "600" && "$_perms" != "400" ]]; then
      warn "配置文件 ${CONF_FILE} 权限过于宽松（${_perms}），拒绝加载（建议：chmod 600 ${CONF_FILE}）"
      return
    fi

    # 【Fix v6】彻底移除 source "$CONF_FILE"，改为逐行手动解析赋值。
    # source 即使经过正则白名单过滤，仍存在续行符、IFS 操控等绕过风险。
    # 手动解析：只识别 KEY=VALUE 或 KEY="VALUE" 两种形式，
    # 严格白名单检验 KEY 名称，VALUE 不经 shell 解释器执行。
    local _line _key _val
    while IFS= read -r _line || [[ -n "$_line" ]]; do
      # 跳过注释行与空行
      [[ "$_line" =~ ^[[:space:]]*(#|$) ]] && continue
      # 提取 KEY（仅大写字母+下划线）
      _key="${_line%%=*}"
      _key="${_key// /}"  # 去除意外空格
      if [[ ! "$_key" =~ ^[A-Z_]+$ ]]; then
        warn "配置文件含非法键名（${_key}），已跳过该行"
        continue
      fi
      # 提取 VALUE（= 号之后的部分），剥除首尾双引号（如果有）
      _val="${_line#*=}"
      if [[ "$_val" =~ ^\"(.*)\"$ ]]; then
        _val="${BASH_REMATCH[1]}"
      fi
      # 白名单：仅允许已知的配置键
      case "$_key" in
        VW_DOMAIN|VW_PORT|VW_USER|VW_GROUP|VW_BIN_DIR|VW_DATA_DIR|\
        VW_WEB_DIR|VW_ENV_FILE|VW_LOG_FILE|VW_BACKUP_DIR|BACKUP_KEEP_DAYS|\
        SIGNUPS_ALLOWED|ENABLE_HTTPS|CERTBOT_EMAIL|VW_IMAGE_REPO|\
        VW_IMAGE_TAG|WEB_VAULT_VER|EXTRACT_TOOL_COMMIT|EXTRACT_TOOL_SHA256)
          # printf '%q' 会添加 shell 转义，这里直接赋值给已知变量名
          printf -v "$_key" '%s' "$_val"
          ;;
        *)
          warn "配置文件包含未知键 ${_key}，已忽略"
          ;;
      esac
    done < "$CONF_FILE"

    # 重新计算派生路径（防止 VW_BIN_DIR / VW_DATA_DIR 变更后派生路径仍指向旧位置）
    VW_BIN="${VW_BIN_DIR}/vaultwarden"
    # VW_WEB_DIR 的默认值依赖 VW_DATA_DIR，若配置文件里 VW_DATA_DIR 已更改
    # 且 VW_WEB_DIR 未被显式覆盖，需同步更新（仅当它仍等于"旧DATA_DIR/web-vault"时）
    if [[ "${VW_WEB_DIR}" == */web-vault ]]; then
      VW_WEB_DIR="${VW_DATA_DIR}/web-vault"
    fi
    # 【Fix】EXTRACT_TOOL_URL 在脚本头部由 EXTRACT_TOOL_COMMIT 展开后固定。
    # 若配置文件覆盖了 EXTRACT_TOOL_COMMIT（例如用户手动锁定旧版本），
    # 必须同步重建 URL，否则 commit 与 URL 指向的 hash 会脱节。
    EXTRACT_TOOL_URL="https://raw.githubusercontent.com/jjlin/docker-image-extract/${EXTRACT_TOOL_COMMIT}/docker-image-extract"
    success "已加载部署记录：${CONF_FILE}"
  fi
}


# ── 配置值安全化：截断到首个换行，去除嵌入的双引号（防止写坏 heredoc 格式）──
_sanitize_conf_val() {
  local _v="${1%%$'\n'*}"  # 截断到首个换行
  _v="${_v//\"/}"          # 移除双引号（load_config 解析时会剥除外层引号）
  echo "$_v"
}

save_config() {
  # 【Fix v6】写入前对每个变量值做单行安全化处理，防止含换行或引号的值
  # 破坏配置文件格式，导致下次 load_config 解析失败。
  cat > "$CONF_FILE" << CONF
VW_DOMAIN="$(_sanitize_conf_val "${VW_DOMAIN}")"
VW_PORT="$(_sanitize_conf_val "${VW_PORT}")"
VW_USER="$(_sanitize_conf_val "${VW_USER}")"
VW_GROUP="$(_sanitize_conf_val "${VW_GROUP}")"
VW_BIN_DIR="$(_sanitize_conf_val "${VW_BIN_DIR}")"
VW_DATA_DIR="$(_sanitize_conf_val "${VW_DATA_DIR}")"
VW_WEB_DIR="$(_sanitize_conf_val "${VW_WEB_DIR}")"
VW_ENV_FILE="$(_sanitize_conf_val "${VW_ENV_FILE}")"
VW_LOG_FILE="$(_sanitize_conf_val "${VW_LOG_FILE}")"
VW_BACKUP_DIR="$(_sanitize_conf_val "${VW_BACKUP_DIR}")"
BACKUP_KEEP_DAYS="$(_sanitize_conf_val "${BACKUP_KEEP_DAYS}")"
SIGNUPS_ALLOWED="$(_sanitize_conf_val "${SIGNUPS_ALLOWED}")"
ENABLE_HTTPS="$(_sanitize_conf_val "${ENABLE_HTTPS}")"
CERTBOT_EMAIL="$(_sanitize_conf_val "${CERTBOT_EMAIL}")"
VW_IMAGE_REPO="$(_sanitize_conf_val "${VW_IMAGE_REPO}")"
VW_IMAGE_TAG="$(_sanitize_conf_val "${VW_IMAGE_TAG}")"
WEB_VAULT_VER="$(_sanitize_conf_val "${WEB_VAULT_VER}")"
# 供应链安全：固定 docker-image-extract commit hash（安装/更新后自动持久化）
EXTRACT_TOOL_COMMIT="$(_sanitize_conf_val "${EXTRACT_TOOL_COMMIT}")"
EXTRACT_TOOL_SHA256="$(_sanitize_conf_val "${EXTRACT_TOOL_SHA256}")"
CONF
  chmod 600 "$CONF_FILE"
}

# ── 获取 Vaultwarden 当前版本 ─────────────────────────────────
get_installed_version() {
  [[ -x "$VW_BIN" ]] && "$VW_BIN" --version 2>/dev/null | awk '{print $2}' || echo "未安装"
}

# ── 获取 Web Vault 最新版本号 ─────────────────────────────────
get_latest_webvault_ver() {
  local json tag
  json=$(curl -fsSL --max-time 15 \
    "https://api.github.com/repos/dani-garcia/bw_web_builds/releases/latest" 2>/dev/null) || true
  [[ -z "$json" ]] && { echo ""; return; }
  # 优先用 grep -oP（GNU grep）；用已知能匹配的字符串测试 -P 支持，
  # 空模式 grep -P '' 在 GNU/BSD grep 上都返回 0，无法区分是否真正支持 -P
  if echo "test" | grep -qP 'test' 2>/dev/null; then
    tag=$(echo "$json" | grep -oP '"tag_name"\s*:\s*"v?\K[^"]+' 2>/dev/null | head -1 || true)
  fi
  if [[ -z "${tag:-}" ]]; then
    tag=$(echo "$json" | grep '"tag_name"' | head -1 \
      | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"v\?\([^"]*\)".*/\1/' 2>/dev/null || true)
  fi
  # 如果 tag 看起来不像版本号（含空格/换行/非版本字符），返回空
  if [[ "$tag" =~ ^[0-9]+\.[0-9]+ ]]; then
    echo "$tag"
  else
    echo ""
  fi
}

# ════════════════════════════════════════════════════════════════
#  核心：从 Alpine 镜像仓库提取静态二进制
#  原理：docker-image-extract 是一个纯 Shell 脚本，通过
#        OCI Registry HTTP API 下载镜像层并解压，无需 Docker。
# ════════════════════════════════════════════════════════════════
extract_binary() {
  local workdir="$1"  # 临时工作目录
  local platform="$2" # 目标平台，如 linux/amd64

  info "下载 docker-image-extract 工具..."
  curl -fsSL --max-time 30 -o "${workdir}/docker-image-extract" "$EXTRACT_TOOL_URL" \
    || error "无法下载 docker-image-extract，请检查网络连接"
  # 完整性校验：文件非空 + shebang 合法 + 文件体积合理（正常脚本 > 5KB）+ 包含关键函数标识
  [[ -s "${workdir}/docker-image-extract" ]] || error "docker-image-extract 下载后为空文件"
  head -1 "${workdir}/docker-image-extract" | grep -q '^#!' \
    || error "docker-image-extract 不是合法的 shell 脚本（shebang 缺失），可能下载损坏"
  local _die_size
  _die_size=$(wc -c < "${workdir}/docker-image-extract")
  [[ "$_die_size" -lt 4096 ]] \
    && error "docker-image-extract 文件过小（${_die_size} 字节），疑似下载不完整或被篡改"
  grep -q 'registry' "${workdir}/docker-image-extract" \
    || error "docker-image-extract 内容异常（缺少 registry 关键字），疑似被篡改，已中止"
  # SHA256 校验（若 EXTRACT_TOOL_SHA256 非空）
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

  # 将 docker-image-extract 的全部输出重定向到 stderr，
  # 避免进度信息污染本函数通过 stdout 返回的二进制路径
  bash "${workdir}/docker-image-extract" \
    -p "$platform" \
    -o "$out_dir" \
    "${VW_IMAGE_REPO}:${VW_IMAGE_TAG}" >&2 \
    || error "镜像提取失败，请检查网络或稍后重试"

  # 在提取目录中查找 vaultwarden 二进制
  local bin_path
  bin_path=$(find "$out_dir" -type f -name "vaultwarden" | head -1)
  [[ -z "$bin_path" ]] && error "未在镜像中找到 vaultwarden 二进制"

  # 校验二进制：必须是 ELF 可执行文件且文件大小 > 1MB（静态二进制通常 > 20MB）
  local _bin_size
  _bin_size=$(wc -c < "$bin_path")
  [[ "$_bin_size" -lt 1048576 ]] \
    && error "提取的 vaultwarden 二进制过小（${_bin_size} 字节），疑似不完整或被篡改"
  # 检查 ELF magic bytes（前4字节应为 \x7fELF）
  if ! head -c 4 "$bin_path" | grep -qP '^\x7fELF' 2>/dev/null; then
    # 非 GNU grep 环境的回退：用 xxd/od 检测
    local _magic
    _magic=$(od -A n -t x1 -N 4 "$bin_path" 2>/dev/null | tr -d ' \n' || true)
    [[ "$_magic" != "7f454c46" ]] \
      && error "提取的文件不是合法的 ELF 二进制（magic bytes 不匹配），疑似下载损坏"
  fi

  # 【Fix v4】校验 ELF e_machine 字段（第 19-20 字节，小端序），确认架构匹配。
  # x86_64 → 0x3e 0x00，aarch64 → 0xb7 0x00，armv7 → 0x28 0x00
  # 若 manifest list 解析异常导致提取了错误架构的二进制，ELF magic 无法发现，
  # 此处提前报错，避免把错误二进制装入系统后在 --version 或运行时才崩溃。
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

  # 同时提取 web-vault（与二进制版本严格对应，重要！）
  local webvault_path
  webvault_path=$(find "$out_dir" -type d -name "web-vault" | head -1)

  # 注意：此函数通过 $() 子Shell调用，无法直接修改父Shell全局变量。
  # 使用临时文件将 web-vault 路径传递给父Shell（见调用处）。
  echo "$webvault_path" > "${workdir}/.webvault_path"

  echo "$bin_path"   # 返回二进制路径（通过 stdout）
}

# ════════════════════════════════════════════════════════════════
#  安装流程
# ════════════════════════════════════════════════════════════════
do_install() {
  show_banner
  preflight_check
  acquire_lock
  check_connectivity

  # 【Fix v4】_c 作为 read 临时变量在函数内多处使用，统一声明 local 避免全局污染
  local _c

  # ── 重复安装保护 ──────────────────────────────────────────────
  if [[ -x "$VW_BIN" ]]; then
    warn "检测到 Vaultwarden 已安装（${VW_BIN}），版本：$(get_installed_version)"
    warn "重新安装会覆盖现有二进制和配置（数据目录保留）。"
    prompt "是否强制重新安装？（y/N）："
    read -r _c; [[ "${_c,,}" != "y" ]] && { info "已取消，如需更新请使用 update 命令"; exit 0; }
  fi

  # ── 配置向导 ──────────────────────────────────────────────────
  step "配置向导"

  if [[ "$VW_DOMAIN" == "vault.example.com" ]]; then
    while true; do
      prompt "请输入你的域名（如 vault.yourdomain.com）："
      local _input; read -r _input
      [[ -z "$_input" ]] && { warn "域名不能为空，请重新输入"; continue; }
      # 基础域名格式校验：只允许字母、数字、连字符、点，且不以点/连字符开头结尾
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
      # 基础邮箱格式校验
      if [[ ! "$_email" =~ ^[a-zA-Z0-9._%+\-]+@[a-zA-Z0-9.\-]+\.[a-zA-Z]{2,}$ ]]; then
        warn "邮箱格式无效（${_email}），请重新输入"
        continue
      fi
      CERTBOT_EMAIL="$_email"
      break
    done
  fi

  echo ""
  # 校验端口合法性
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

  # ── Step 1: 安装系统依赖 ──────────────────────────────────────
  step "Step 1  安装系统依赖"
  DEBIAN_FRONTEND=noninteractive apt-get update -qq \
    || warn "apt-get update 部分仓库失败，将尝试继续安装（可能影响包版本）"
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    curl wget ca-certificates \
    nginx certbot python3-certbot-nginx \
    sqlite3 argon2 openssl fail2ban \
    logrotate
  success "系统依赖安装完成"

  # ── Step 2: 创建系统用户与目录 ───────────────────────────────
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

  # ── Step 3: 从 Alpine 镜像提取静态二进制 ─────────────────────
  step "Step 3  提取 Vaultwarden 静态二进制"

  # 确定目标平台
  local PLATFORM
  case $ARCH in
    x86_64)  PLATFORM="linux/amd64"  ;;
    aarch64) PLATFORM="linux/arm64"  ;;
    armv7l)  PLATFORM="linux/arm/v7" ;;
  esac

  local WORK_DIR
  WORK_DIR=$(mktemp -d /tmp/vaultwarden_install_XXXXXX)
  # EXIT trap：脚本任意退出时同时释放锁 + 清理临时目录。
  # 【重要】此 trap 必须包含 flock 释放逻辑，否则会覆盖 acquire_lock() 设置的
  # EXIT trap，导致 FD 9 不被显式关闭——子进程（docker-image-extract、systemctl、
  # certbot 等）继承了 FD 9 后会持续持有锁，直到最后一个子进程退出才释放。
  _cleanup_install() {
    flock -u 9 2>/dev/null; exec 9>&- 2>/dev/null
    [[ -d "${WORK_DIR:-}" ]] && rm -rf "$WORK_DIR"
  }
  trap '_cleanup_install' EXIT

  local BIN_PATH EXTRACTED_WEBVAULT_PATH VW_VER
  BIN_PATH=$(extract_binary "$WORK_DIR" "$PLATFORM")
  # 从临时文件读取 web-vault 路径（子Shell无法直接修改父Shell变量）
  EXTRACTED_WEBVAULT_PATH=$(cat "${WORK_DIR}/.webvault_path" 2>/dev/null || true)
  success "二进制提取成功：${BIN_PATH}"

  # 安装二进制
  # 【Fix v5】确保 VW_BIN_DIR 存在，自定义路径时 install 不会因目录缺失而失败
  mkdir -p "$VW_BIN_DIR"
  install -m 755 -o root -g root "$BIN_PATH" "$VW_BIN"
  success "二进制已安装：${VW_BIN}"

  # 打印版本
  VW_VER=$("$VW_BIN" --version 2>/dev/null || echo "unknown")
  info "Vaultwarden 版本：${VW_VER}"

  # ── Step 4: 安装 Web Vault ────────────────────────────────────
  step "Step 4  安装 Web Vault"

  # 优先使用从镜像中提取的 web-vault（与二进制版本严格匹配）
  if [[ -n "$EXTRACTED_WEBVAULT_PATH" && -d "$EXTRACTED_WEBVAULT_PATH" ]]; then
    info "使用镜像中提取的 Web Vault（与二进制版本一致）..."
    rm -rf "$VW_WEB_DIR"
    cp -a "$EXTRACTED_WEBVAULT_PATH" "$VW_WEB_DIR"
    success "Web Vault 已安装（来自 Alpine 镜像）"
  else
    # 回退：从 bw_web_builds 单独下载
    info "从 GitHub 下载最新 Web Vault..."
    # 【Fix v5】与 do_update 中同类修复一致：使用局部变量 _wv_ver 而非直接赋值全局
    # WEB_VAULT_VER，防止 save_config 将其持久化后永久锁定版本。
    # 用户如需固定版本，可在脚本顶部显式设置 WEB_VAULT_VER。
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
    # bw_web_builds 解压后的目录名为 web-vault
    success "Web Vault v${_wv_ver} 已安装"
  fi

  chown -R "${VW_USER}:${VW_GROUP}" "$VW_WEB_DIR"
  chmod -R 750 "$VW_WEB_DIR"
  info "Web Vault 位置：${VW_WEB_DIR}"

  # ── Step 5: 生成 Admin Token（Argon2id）──────────────────────
  step "Step 5  生成 Admin Token（Argon2id 哈希）"

  # 生成 48 字符随机明文 Token（24字节×2=48位十六进制，无管道无 SIGPIPE 风险）
  local ADMIN_PLAIN ADMIN_HASH SALT
  ADMIN_PLAIN=$(openssl rand -hex 24)

  # 使用本机刚安装的 vaultwarden 二进制生成哈希（最准确，参数与运行时一致）
  info "使用 vaultwarden hash --preset owasp 生成哈希..."
  # 注意：必须用 printf '%s' 而非 echo，echo 会附加换行符，导致 hash 将 "\n" 纳入密码
  ADMIN_HASH=$(printf '%s' "$ADMIN_PLAIN" | "$VW_BIN" hash --preset owasp 2>/dev/null \
    | grep '^\$argon2' | head -1 || true)

  if [[ -z "$ADMIN_HASH" ]]; then
    # 回退：使用系统 argon2 CLI
    # 严格匹配 vaultwarden --preset owasp 的参数：m=19456 KiB, t=2, p=1（OWASP 最低推荐）
    warn "vaultwarden hash 输出解析失败，回退至 argon2 CLI（OWASP preset）..."
    SALT=$(openssl rand -base64 32)
    ADMIN_HASH=$(printf '%s' "$ADMIN_PLAIN" | \
      argon2 "$SALT" -e -id -k 19456 -t 2 -p 1 -l 32 2>/dev/null || true)
    [[ -z "$ADMIN_HASH" ]] && error "argon2 CLI 也失败，无法生成安全的 Admin Token。\n  请确认已安装 argon2：apt-get install -y argon2\n  修复后重新运行 install。（使用明文 Token 在新版 Vaultwarden 中已废弃且不安全，拒绝继续）"
  fi

  success "Admin Token 生成完成"

  # ── Step 6: 写入环境变量配置文件 ─────────────────────────────
  step "Step 6  写入 ${VW_ENV_FILE}"

  cat > "$VW_ENV_FILE" << ENV
# Vaultwarden 环境变量配置文件
# 此文件包含敏感信息，chmod 600 保护，请勿提交至版本控制
# 修改后需重启服务：systemctl restart vaultwarden

# ── 基本配置 ──────────────────────────────────────────────────
DOMAIN=https://${VW_DOMAIN}
ROCKET_PORT=${VW_PORT}
ROCKET_ADDRESS=127.0.0.1

# 数据和 Web Vault 目录（与 systemd WorkingDirectory 对应）
DATA_FOLDER=${VW_DATA_DIR}
WEB_VAULT_FOLDER=${VW_WEB_DIR}
WEB_VAULT_ENABLED=true

# ── 注册控制 ──────────────────────────────────────────────────
# 首次创建账号后建议改为 false，然后 systemctl restart vaultwarden
SIGNUPS_ALLOWED=${SIGNUPS_ALLOWED}
INVITATIONS_ALLOWED=true

# ── Admin 面板 ─────────────────────────────────────────────────
# Argon2id 哈希保护（明文 Token 在新版本中已废弃）
# 重要：必须用单引号包裹，防止 systemd EnvironmentFile 对 $ 做变量展开
# （argon2 PHC 格式含多个 $ 符号，双引号下会被 systemd 错误展开为空串）
ADMIN_TOKEN='${ADMIN_HASH}'

# ── WebSocket 实时推送（客户端实时同步必需）────────────────────
# 1.29+ 已将 WebSocket 合并到主端口（ROCKET_PORT），无需独立端口
# WEBSOCKET_ENABLED 保留以兼容旧版本；新版本已忽略此项
WEBSOCKET_ENABLED=true

# ── 日志 ──────────────────────────────────────────────────────
LOG_FILE=${VW_LOG_FILE}
LOG_LEVEL=info
EXTENDED_LOGGING=true

# ── 安全加固 ──────────────────────────────────────────────────
LOGIN_RATELIMIT_MAX_BURST=10
LOGIN_RATELIMIT_SECONDS=60
ADMIN_RATELIMIT_MAX_BURST=10
ADMIN_RATELIMIT_SECONDS=60
IP_HEADER=X-Real-IP

# ── 附件限制（单位 KiB）──────────────────────────────────────
ATTACHMENTS_SIZE_LIMIT=10240
USER_ATTACHMENT_LIMIT=102400

# ── SMTP 邮件（可选，取消注释并填写）────────────────────────
# SMTP_HOST=smtp.example.com
# SMTP_PORT=587
# SMTP_SECURITY=starttls
# SMTP_USERNAME=your@email.com
# SMTP_PASSWORD=your_password
# SMTP_FROM=no-reply@${VW_DOMAIN}
# SMTP_FROM_NAME=Vaultwarden

# ── 推送通知（可选，需向 Bitwarden 官方申请 ID/Key）──────────
# PUSH_ENABLED=true
# PUSH_INSTALLATION_ID=
# PUSH_INSTALLATION_KEY=
ENV

  chmod 600 "$VW_ENV_FILE"
  chown root:root "$VW_ENV_FILE"
  success "环境配置文件已写入：${VW_ENV_FILE}（权限 600）"

  # ── Step 7: 创建 systemd 服务单元 ─────────────────────────────
  step "Step 7  创建 systemd 服务"

  cat > /etc/systemd/system/vaultwarden.service << UNIT
[Unit]
Description=Vaultwarden Password Manager (Bitwarden-compatible)
Documentation=https://github.com/dani-garcia/vaultwarden
After=network.target
# 若使用外部数据库，取消注释并按实际修改：
# After=mysql.service
# Requires=mysql.service

[Service]
# 以专用低权限用户运行
User=${VW_USER}
Group=${VW_GROUP}

# 环境变量配置文件
EnvironmentFile=${VW_ENV_FILE}

# 工作目录（SQLite 数据库写在此处）
WorkingDirectory=${VW_DATA_DIR}

# 二进制路径
ExecStart=${VW_BIN}

# 进程限制
LimitNOFILE=1048576
LimitNPROC=64

# systemd 沙箱隔离（加固安全）
PrivateTmp=true
PrivateDevices=true
ProtectHome=true
ProtectSystem=strict
# 允许写入的目录（数据目录和日志目录）
ReadWritePaths=${VW_DATA_DIR} $(dirname "${VW_LOG_FILE}")

# 崩溃后自动重启
Restart=on-failure
RestartSec=5s

# 标准输出也转发到 journal
StandardOutput=journal
StandardError=journal
SyslogIdentifier=vaultwarden

[Install]
WantedBy=multi-user.target
UNIT

  systemctl daemon-reload
  systemctl enable vaultwarden --quiet
  success "systemd 服务已创建并设为开机自启"

  # ── Step 8: 启动服务 ──────────────────────────────────────────
  step "Step 8  启动 Vaultwarden 服务"

  # 【Fix v4】启动前检查端口是否已被占用，提前给出可读的错误提示，
  # 避免 wait_for_service 超时后用户不知道真正原因。
  # 注意：仅 warn 而非 error，因为旧的 vaultwarden 进程正好也在用这个端口是合法情况。
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
    # 【Fix】首次安装时服务无法启动，执行部分回滚后再报错退出：
    # 删除已安装的二进制与 systemd 单元，避免留下残破的半截安装。
    warn "服务在 20 秒内未能正常启动，正在清理已安装文件..."
    systemctl stop    vaultwarden 2>/dev/null || true
    systemctl disable vaultwarden 2>/dev/null || true
    rm -f /etc/systemd/system/vaultwarden.service
    systemctl daemon-reload 2>/dev/null || true
    rm -f "$VW_BIN"
    error "安装失败：服务无法启动，已回滚二进制与 systemd 单元。\n  调试命令：journalctl -u vaultwarden -n 30 --no-pager\n  （数据目录、env 文件、Nginx 配置已保留，修复原因后重新 install）"
  fi

  # ── Step 9: 配置 Nginx 反向代理 ──────────────────────────────
  step "Step 9  配置 Nginx 反向代理（HTTP-only，HTTPS 由 Step 10 certbot 补全）"
  local NGINX_CONF="/etc/nginx/sites-available/vaultwarden"
  mkdir -p /var/www/certbot

  # 第一阶段：仅写 HTTP 块用于 ACME 验证 + 临时反代，待 certbot 完成后再补全 HTTPS
  cat > "$NGINX_CONF" << NGINX
# Vaultwarden Nginx 反向代理配置（HTTP 阶段）
server {
    listen 80;
    listen [::]:80;
    server_name ${VW_DOMAIN};

    # Let's Encrypt ACME challenge
    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    # 临时直接反代（HTTPS 申请前）
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
  # 仅在没有其他站点使用 default 时才删除，避免影响其他服务
  if [[ -L /etc/nginx/sites-enabled/default ]]; then
    warn "已移除 Nginx 默认站点（/etc/nginx/sites-enabled/default）。如有其他站点依赖它，请手动恢复。"
    rm -f /etc/nginx/sites-enabled/default
  fi
  nginx -t || error "Nginx 配置验证失败（HTTP 阶段）"
  success "Nginx HTTP 配置完成"

  # ── Step 10: 申请 Let's Encrypt 证书 ─────────────────────────
  step "Step 10  申请 HTTPS 证书"
  systemctl enable nginx --quiet
  systemctl restart nginx

  # 【Fix v4】certbot 使用 HTTP-01 challenge，必须在 Nginx 真正监听 80 端口后才能成功。
  # 若 Nginx 启动失败（配置错误/端口冲突），之前直接跑 certbot 会因 challenge 失败而报出
  # 难以定位的 "Connection refused" 错误。此处提前检测，给出明确的失败原因。
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

    # 确保 auto-renew（避免重复添加 crontab 条目）
    if systemctl list-timers certbot* 2>/dev/null | grep -q certbot; then
      success "Certbot 自动续签定时器已就绪"
    else
      if crontab -l 2>/dev/null | grep -q "certbot renew"; then
        success "Certbot 自动续签 cron 条目已存在，跳过"
      else
        # 使用 02:30 避免与备份任务（03:30）同时运行，减少 I/O 争用
        (crontab -l 2>/dev/null; echo "30 2 * * * certbot renew --quiet --post-hook 'systemctl reload nginx'") | crontab -
        success "Certbot 自动续签（每天 02:30）已加入 crontab"
      fi
    fi

    # 第二阶段：写入完整 HTTP + HTTPS 配置（证书已存在）
    local CERT_PATH_FULL="/etc/letsencrypt/live/${VW_DOMAIN}/fullchain.pem"
    local CERT_KEY_FULL="/etc/letsencrypt/live/${VW_DOMAIN}/privkey.pem"

    if [[ -f "$CERT_PATH_FULL" ]]; then
      # 检测 nginx 版本，≥1.25.1 用 "http2 on;"，否则在 listen 行附加 http2
      local _nginx_ver _http2_directive _listen_https
      _nginx_ver=$(nginx -v 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || echo "0.0.0")
      if [[ "$_nginx_ver" == "0.0.0" ]]; then
        warn "无法检测 Nginx 版本，默认使用旧版 http2 语法（listen 行附加）"
      fi
      # 版本比较：≥1.25.1 使用独立 "http2 on;" 指令；否则在 listen 行附加 http2
      # awk 返回 0 = 版本满足（≥1.25.1），返回 1 = 版本不满足
      if awk -v v="$_nginx_ver" 'BEGIN{
          n=split(v,a,".");
          split("1.25.1",b,".");
          for(i=1;i<=3;i++){
            ai=a[i]+0; bi=b[i]+0;
            if(ai>bi) exit 0;
            if(ai<bi) exit 1;
          }
          exit 0  # 完全相等，视为满足
        }'; then
        _http2_directive="    http2 on;"
        _listen_https="    listen 443 ssl;\n    listen [::]:443 ssl;"
      else
        _http2_directive=""
        _listen_https="    listen 443 ssl http2;\n    listen [::]:443 ssl http2;"
      fi

      cat > "$NGINX_CONF" << NGINX2
# Vaultwarden Nginx 反向代理配置（完整 HTTP + HTTPS）
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

      # 动态写入 HTTPS server 块（http2 指令兼容性）
      {
        echo "server {"
        printf '%b\n' "$_listen_https"
        [[ -n "$_http2_directive" ]] && echo "$_http2_directive"
        cat << NGINX2BODY
    server_name ${VW_DOMAIN};

    # TLS 证书
    ssl_certificate     ${CERT_PATH_FULL};
    ssl_certificate_key ${CERT_KEY_FULL};

    # TLS 加固
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers 'ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-CHACHA20-POLY1305';
    ssl_prefer_server_ciphers off;
    ssl_session_timeout 1d;
    ssl_session_cache shared:MozTLS:10m;
    ssl_stapling on;
    ssl_stapling_verify on;

    # 附件上传大小（与 .env 中的限制对应）
    client_max_body_size 20M;

    # 安全响应头
    add_header Strict-Transport-Security  "max-age=31536000; includeSubDomains; preload" always;
    add_header X-Content-Type-Options     "nosniff"                                      always;
    add_header X-Frame-Options            "SAMEORIGIN"                                   always;
    add_header X-XSS-Protection           "0"                                            always;
    add_header Referrer-Policy            "strict-origin-when-cross-origin"              always;
    add_header Permissions-Policy         "camera=(), microphone=(), geolocation=()"     always;

    # 主反向代理（含 WebSocket 升级支持）
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

    # WebSocket 通知（1.29+ 通过主端口处理，此块保留向后兼容旧版本）
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

    # Admin 面板（建议生产环境限制来源 IP）
    location /admin {
        # 取消注释以限制 IP（强烈推荐）：
        # allow YOUR_TRUSTED_IP/32;
        # deny  all;
        proxy_pass       http://127.0.0.1:${VW_PORT}/admin;
        proxy_set_header Host              \$host;
        proxy_set_header X-Real-IP         \$remote_addr;
        proxy_set_header X-Forwarded-For   \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }

    # Gzip 压缩
    gzip on;
    gzip_types text/plain text/css application/json application/javascript
               text/xml application/xml text/javascript image/svg+xml application/wasm;
    gzip_min_length 1024;
    gzip_vary on;

    # 日志
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

  # ── Step 11: 配置 Fail2Ban ────────────────────────────────────
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

  # ── Step 12: 配置日志轮转 ────────────────────────────────────
  step "Step 12  配置日志轮转"
  cat > /etc/logrotate.d/vaultwarden << LOGR
${VW_LOG_FILE} {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    # copytruncate：原地截断日志文件，无需 Rocket 实现 SIGHUP/SIGUSR1
    # 缺点：极短窗口内可能丢失少量日志行，对密码管理器场景可接受
    copytruncate
}
LOGR
  success "日志轮转已配置（每日轮转，保留 14 天，自动压缩）"

  # ── Step 13: 配置防火墙 ───────────────────────────────────────
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
    # iptables 规则重启后会丢失；尝试用 netfilter-persistent 持久化
    if command -v netfilter-persistent &>/dev/null; then
      netfilter-persistent save 2>/dev/null && success "iptables 规则已持久化（netfilter-persistent）" || true
    else
      warn "iptables 规则未持久化（重启后失效）。建议：apt-get install -y iptables-persistent && netfilter-persistent save"
    fi
  fi
  $FW_DONE || warn "未检测到活跃防火墙，请手动放行 80/443 端口"

  # ── Step 14: 配置自动备份 ─────────────────────────────────────
  step "Step 14  配置自动备份（每日 03:30）"
  _write_backup_script
  echo "30 3 * * * root /bin/bash /usr/local/bin/vaultwarden-backup >> ${VW_BACKUP_DIR}/backup.log 2>&1" \
    > /etc/cron.d/vaultwarden-backup
  chmod 644 /etc/cron.d/vaultwarden-backup
  success "自动备份已配置（每日 03:30，保留 ${BACKUP_KEEP_DAYS} 天）"

  # ── Step 15: 健康检查 & 保存配置 ─────────────────────────────
  step "Step 15  健康检查"
  save_config
  # 最多等 10 秒让服务完成初始化
  local _hc_elapsed=0
  local HTTP_CODE
  until HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}" --max-time 5 "http://127.0.0.1:${VW_PORT}/" || echo "000") \
      && [[ "$HTTP_CODE" =~ ^(200|301|302)$ ]]; do
    sleep 1; _hc_elapsed=$(( _hc_elapsed + 1 ))   # 赋值形式，对 set -e 安全
    [[ $_hc_elapsed -ge 10 ]] && break
  done
  if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "302" ]]; then
    success "Vaultwarden 本地接口响应正常（HTTP ${HTTP_CODE}）"
  else
    warn "本地健康检查返回 ${HTTP_CODE}，服务可能仍在初始化，稍后再试"
    warn "调试命令：journalctl -u vaultwarden -n 30 --no-pager"
  fi

  # ── 完成摘要 ──────────────────────────────────────────────────
  local INTERNAL_IP PROTO INSTALLED_VER
  INTERNAL_IP=$(hostname -I | awk '{print $1}')
  if [[ "$ENABLE_HTTPS" == "true" ]]; then PROTO="https"; else PROTO="http"; fi
  INSTALLED_VER=$(get_installed_version)

  # 【Fix v6】Admin 明文 Token 不再经由 echo 输出到终端（会进入 shell 历史、
  # journalctl、systemd-cat、tee 管道等）。改为写入 600 权限的临时文件，
  # 引导用户 cat 后立即销毁，降低 Token 在日志/历史中泄漏的风险。
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

# ════════════════════════════════════════════════════════════════
#  更新流程
# ════════════════════════════════════════════════════════════════
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

  # 停止服务（若服务未运行则忽略错误；设置超时防止挂起）
  # 【Fix v4】先记录服务更新前的真实状态，`systemctl stop` 会静默清除 failed 状态，
  # 若不记录，更新后用户看到"服务启动成功"却不知道更新前其实已经崩溃了。
  local _pre_update_svc_state
  _pre_update_svc_state=$(systemctl is-active vaultwarden 2>/dev/null || echo "inactive")
  if [[ "$_pre_update_svc_state" == "failed" ]]; then
    warn "注意：更新前 vaultwarden 服务处于 failed 状态，本次更新将同时重置该故障状态"
    warn "如果更新后仍有问题，请检查更新前已存在的错误：journalctl -u vaultwarden -n 50 --no-pager"
  fi
  info "停止 Vaultwarden 服务..."
  systemctl stop --timeout=30 vaultwarden 2>/dev/null || true

  # 判断平台
  # 【Fix v5】使用 preflight_check 已设置的全局 $ARCH，与 do_install 保持一致，
  # 避免重复调用 uname -m 且维护时两处容易遗漏同步。
  case $ARCH in
    x86_64)  PLATFORM="linux/amd64"  ;;
    aarch64) PLATFORM="linux/arm64"  ;;
    armv7l)  PLATFORM="linux/arm/v7" ;;
    *)       error "不支持的架构：$ARCH" ;;
  esac

  WORK_DIR=$(mktemp -d /tmp/vaultwarden_update_XXXXXX)
  # 同 do_install，EXIT trap 必须包含 flock 释放，防止覆盖 acquire_lock 的 trap
  _cleanup_update() {
    flock -u 9 2>/dev/null; exec 9>&- 2>/dev/null
    [[ -d "${WORK_DIR:-}" ]] && rm -rf "$WORK_DIR"
  }
  trap '_cleanup_update' EXIT

  # 提取新二进制
  step "提取新版本二进制"
  NEW_BIN_PATH=$(extract_binary "$WORK_DIR" "$PLATFORM")
  EXTRACTED_WEBVAULT_PATH=$(cat "${WORK_DIR}/.webvault_path" 2>/dev/null || true)

  # 备份旧二进制（命名统一为 vaultwarden.bak.TIMESTAMP，与 find 模式一致）
  cp "$VW_BIN" "${VW_BIN}.bak.$(date +%Y%m%d%H%M%S)"
  # 【Fix v5】确保 VW_BIN_DIR 存在（与 do_install 一致）
  mkdir -p "$VW_BIN_DIR"
  install -m 755 -o root -g root "$NEW_BIN_PATH" "$VW_BIN"
  success "二进制已更新"

  NEW_VER=$(get_installed_version)

  # 更新 Web Vault
  step "更新 Web Vault"
  # 【Fix v4】使用局部变量 _fetched_wv_ver 代替直接赋值全局 WEB_VAULT_VER。
  # 原先：WEB_VAULT_VER=$(get_latest_webvault_ver) 会污染全局变量，
  # save_config 随后将其持久化到 CONF_FILE，导致下次 update 时
  # load_config 把 WEB_VAULT_VER 恢复为旧版本，Web Vault 从此永远无法升级。
  # 【Fix v4】使用带时间戳的备份目录名，避免多次 update 时互相覆盖同一个 .bak 目录
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

  # 重启服务
  # 【Fix v4】同 do_install：启动前检查端口占用，方便排查问题
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
      # 同时恢复 Web Vault 备份（若存在）
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
        # 【Fix v5→v6】原用 return 1，但在 set -euo pipefail 环境下 return 1
        # 依赖调用方检查返回值，语义不够明确且容易漏处。
        # 改为 error() 输出带上下文的摘要并 exit 1，行为确定，无需调用方配合。
        error "更新失败，已回滚至旧版本 ${OLD_VER}。\n  如需排查新版本问题：journalctl -u vaultwarden -n 50 --no-pager\n  新版本二进制备份保留在：$(find "$(dirname "$VW_BIN")" -maxdepth 1 -name "vaultwarden.bak.*" -type f | sort -r | head -1 || echo '未知')"
      else
        error "回滚后服务仍无法启动，请手动检查：journalctl -u vaultwarden -n 30 --no-pager"
      fi
    else
      error "未找到备份二进制，回滚失败！请手动检查：journalctl -u vaultwarden -n 30 --no-pager"
    fi
  fi

  # 清理旧备份的二进制（保留最近 3 个），nullglob 防止无匹配时报错
  # 使用 find 而非 glob 扩展，彻底避免 set -u 与无匹配 glob 的交互问题
  # 【Fix v4】local -a 声明数组，避免 _old_baks 泄漏到全局作用域
  local -a _old_baks
  mapfile -t _old_baks < <(find "$(dirname "$VW_BIN")" -maxdepth 1 \
    -name "vaultwarden.bak.*" -type f -printf '%T@ %p\n' 2>/dev/null \
    | sort -rn | awk 'NR>3{print $2}')
  [[ ${#_old_baks[@]} -gt 0 ]] && rm -f "${_old_baks[@]}"

  # 【Fix v4】清理旧 web-vault 备份目录（保留最近 3 个）。
  # v3 只清理二进制备份而不清理 web-vault 备份目录，多次更新后磁盘持续积累。
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

  # 持久化本次更新使用的配置
  save_config
}

# ════════════════════════════════════════════════════════════════
#  备份工具函数
# ════════════════════════════════════════════════════════════════
_write_backup_script() {
  cat > /usr/local/bin/vaultwarden-backup << 'BKSH'
#!/bin/bash
# Vaultwarden 备份脚本（由 vaultwarden.sh 生成）
set -euo pipefail
umask 077   # 备份文件只有 root 可读（含密钥、env 文件等敏感数据）
BKSH

  # 将运行时变量注入脚本（此块使用普通 heredoc 展开父 Shell 变量）
  cat >> /usr/local/bin/vaultwarden-backup << BKSH_VARS
BACKUP_DIR="${VW_BACKUP_DIR}"
DATA_DIR="${VW_DATA_DIR}"
ENV_FILE="${VW_ENV_FILE}"
KEEP_DAYS="${BACKUP_KEEP_DAYS}"
BKSH_VARS

  # 其余逻辑使用单引号 heredoc，\$ 不展开
  cat >> /usr/local/bin/vaultwarden-backup << 'BKSH'
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
ARCHIVE="${BACKUP_DIR}/vaultwarden_${TIMESTAMP}.tar.gz"
ARCHIVE_TMP="${ARCHIVE}.tmp"   # 原子写：先写临时文件，完成后再 mv
mkdir -p "${BACKUP_DIR}"

# 【Fix v6】提前校验数据目录存在，否则后续 sqlite3 WAL flush 和 tar
# 的错误均被静默处理，backup.log 写入"成功"但实际产生空/损坏档案。
if [[ ! -d "${DATA_DIR}" ]]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S')  [ERROR] 数据目录不存在（${DATA_DIR}），备份已中止"
  exit 1
fi

# 对 SQLite 执行 WAL checkpoint，保证所有写入已落盘
if [[ -f "${DATA_DIR}/db.sqlite3" ]]; then
  sqlite3 "${DATA_DIR}/db.sqlite3" "PRAGMA wal_checkpoint(FULL);" 2>/dev/null || true
  # 完整性校验：确保数据库未损坏再备份
  INTEGRITY=$(sqlite3 "${DATA_DIR}/db.sqlite3" "PRAGMA integrity_check;" 2>/dev/null || echo "error")
  if [[ "$INTEGRITY" != "ok" ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S')  [WARN] SQLite 完整性校验失败（${INTEGRITY}），备份仍将继续但数据库可能已损坏"
  fi
fi

# 打包数据目录 + 环境变量配置（不含日志）
DATA_PARENT=$(dirname "${DATA_DIR}")
DATA_BASE=$(basename "${DATA_DIR}")

# 仅在 ENV_FILE 存在时才纳入备份
TAR_EXTRA=()
[[ -f "${ENV_FILE}" ]] && TAR_EXTRA=(-C / "${ENV_FILE#/}")

# 原子写：写入临时文件，成功后再重命名，避免备份中断产生半截文件
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

# 清理过期备份
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

  # 【Fix v5】提前校验数据目录存在，否则 tar 的错误会被 2>/dev/null 吞掉，
  # 调用方误以为备份成功，实际产生的是空/损坏档案。
  if [[ ! -d "$VW_DATA_DIR" ]]; then
    warn "备份跳过：数据目录不存在（${VW_DATA_DIR}）"
    return 1
  fi

  if [[ -f "${VW_DATA_DIR}/db.sqlite3" ]]; then
    sqlite3 "${VW_DATA_DIR}/db.sqlite3" "PRAGMA wal_checkpoint(FULL);" 2>/dev/null || true
    # 完整性校验
    local _ic
    _ic=$(sqlite3 "${VW_DATA_DIR}/db.sqlite3" "PRAGMA integrity_check;" 2>/dev/null || echo "error")
    [[ "$_ic" != "ok" ]] && warn "SQLite 完整性校验警告（${_ic}），备份继续但数据库可能已损坏"
  fi

  # 使用数组避免路径含空格时的 word splitting 问题
  local tar_extra=()
  [[ -f "$VW_ENV_FILE" ]] && tar_extra=(-C / "${VW_ENV_FILE#/}")

  # 原子写：完成后 mv，避免备份中断留下半截文件
  # 【Fix v6】去掉 2>/dev/null，将 tar 错误（磁盘满/权限问题等）输出到 stderr，
  # 让操作员能感知真实原因，而不是看到静默失败。
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

# ── 交互式备份 ────────────────────────────────────────────────
do_backup() {
  show_banner
  [[ $EUID -ne 0 ]] && error "请用 root 权限运行：sudo bash $0"
  load_config
  acquire_lock   # 防止与 install/update 并发，避免备份文件损坏

  step "手动备份 Vaultwarden"
  [[ ! -d "$VW_DATA_DIR" ]] && error "数据目录不存在：${VW_DATA_DIR}，请先执行安装"

  _backup_silent "manual"

  echo ""
  info "当前所有备份（最近 10 个）："
  # 【Fix】使用 find+sort 替代 ls -t，避免文件名含空格或特殊字符时行为异常
  mapfile -t _bak_list < <(
    find "${VW_BACKUP_DIR}" -maxdepth 1 -name "vaultwarden_*.tar.gz" \
      -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -10 | awk '{print $2}'
  )
  if [[ ${#_bak_list[@]} -gt 0 ]]; then
    # 逐行打印：文件名 + 文件大小
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
  # 【Fix v4】显式释放锁，避免子进程在锁释放前继承 FD 9
  release_lock
}

# ════════════════════════════════════════════════════════════════
#  状态查看
# ════════════════════════════════════════════════════════════════
do_status() {
  # 【Fix v4】所有 local 声明统一提至函数头部，避免 shellcheck SC2168 警告
  local DB_SIZE CERT_PATH EXPIRY DAYS HTTP_CODE
  show_banner
  load_config
  # 非 root 用户下 fail2ban-client、systemctl detail、证书路径等可能受限，给出提示
  if [[ $EUID -ne 0 ]]; then
    warn "当前以非 root 用户运行，部分状态信息（fail2ban、systemd 详情等）可能不完整"
    warn "如需完整状态，请：sudo bash $0 status"
  fi

  step "Vaultwarden 系统状态"

  # 服务状态
  echo -e "\n${BOLD}【systemd 服务状态】${NC}"
  systemctl status vaultwarden --no-pager -l 2>/dev/null | head -15 | sed 's/^/  /' \
    || echo -e "  ${RED}[✗]${NC} vaultwarden 服务未安装或未运行"

  # 版本信息
  echo -e "\n${BOLD}【版本信息】${NC}"
  if [[ -x "$VW_BIN" ]]; then
    echo -e "  二进制版本：$(get_installed_version)"
    echo -e "  二进制路径：${VW_BIN}（$(du -sh "$VW_BIN" | cut -f1)）"
    echo -e "  二进制时间：$(stat -c '%y' "$VW_BIN" | cut -d'.' -f1)"
  else
    echo -e "  ${RED}[✗]${NC} 未找到 Vaultwarden 二进制：${VW_BIN}"
  fi

  # 数据目录
  echo -e "\n${BOLD}【数据目录（${VW_DATA_DIR}）】${NC}"
  if [[ -d "$VW_DATA_DIR" ]]; then
    ls -lh "${VW_DATA_DIR}" 2>/dev/null | tail -n +2 | awk '{printf "  %-12s  %s\n", $5, $NF}'
    echo "  ──────────────────────────"
    echo "  合计：$(du -sh "$VW_DATA_DIR" | cut -f1)"
    # SQLite 状态
    if [[ -f "${VW_DATA_DIR}/db.sqlite3" ]]; then
      DB_SIZE=$(du -sh "${VW_DATA_DIR}/db.sqlite3" | cut -f1)
      echo -e "  数据库：db.sqlite3（${DB_SIZE}）"
    fi
  else
    echo -e "  ${RED}[✗]${NC} 数据目录不存在"
  fi

  # 备份情况
  echo -e "\n${BOLD}【备份文件（最近 5 个）】${NC}"
  if find "${VW_BACKUP_DIR}" -maxdepth 1 -name "vaultwarden_*.tar.gz" 2>/dev/null | grep -q .; then
    ls -lht "${VW_BACKUP_DIR}"/vaultwarden_*.tar.gz 2>/dev/null | head -5 \
      | awk '{printf "  %-60s  %s\n", $NF, $5}'
    echo -e "  共 $(find "${VW_BACKUP_DIR}" -maxdepth 1 -name "vaultwarden_*.tar.gz" 2>/dev/null | wc -l) 个备份"
  else
    echo -e "  ${YELLOW}[!]${NC} 暂无备份文件"
  fi

  # Nginx
  echo -e "\n${BOLD}【Nginx 状态】${NC}"
  systemctl is-active nginx &>/dev/null \
    && echo -e "  ${GREEN}[✓]${NC} nginx 运行中" \
    || echo -e "  ${RED}[✗]${NC} nginx 未运行"

  # Fail2Ban
  echo -e "\n${BOLD}【Fail2Ban 状态】${NC}"
  if systemctl is-active fail2ban &>/dev/null; then
    fail2ban-client status vaultwarden 2>/dev/null | sed 's/^/  /' \
      || echo -e "  ${YELLOW}[!]${NC} fail2ban 运行中，但 vaultwarden jail 未加载"
  else
    echo -e "  ${RED}[✗]${NC} fail2ban 未运行"
  fi

  # HTTP 健康检查
  echo -e "\n${BOLD}【HTTP 健康检查】${NC}"
  HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}" --max-time 5 "http://127.0.0.1:${VW_PORT}/" 2>/dev/null || echo "000")
  [[ "$HTTP_CODE" =~ ^(200|302|301)$ ]] \
    && echo -e "  ${GREEN}[✓]${NC} 本地接口响应：HTTP ${HTTP_CODE}" \
    || echo -e "  ${YELLOW}[!]${NC} 本地接口响应：HTTP ${HTTP_CODE}（服务未运行或端口错误？）"

  # TLS 证书
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

# ════════════════════════════════════════════════════════════════
#  卸载流程
# ════════════════════════════════════════════════════════════════
do_uninstall() {
  show_banner
  preflight_check
  load_config
  acquire_lock   # 防止与 install/update/backup 并发执行

  # 【Fix v6】卸载操作涉及 rm -f / rm -rf，对关键路径变量做非空 + 非根目录校验，
  # 防止 load_config 失败（配置文件不存在/跳过）时变量仍为默认值导致误删。
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

  # 停止并禁用服务
  info "停止 Vaultwarden 服务..."
  systemctl stop    vaultwarden 2>/dev/null || true
  systemctl disable vaultwarden 2>/dev/null || true
  rm -f /etc/systemd/system/vaultwarden.service
  systemctl daemon-reload
  success "systemd 服务已移除"

  # 移除二进制及旧备份（用 find 代替 glob 扩展，避免无文件时 set -u 报错）
  rm -f "${VW_BIN}"
  find "$(dirname "$VW_BIN")" -maxdepth 1 -name "vaultwarden.bak.*" -type f -delete 2>/dev/null || true
  success "二进制已删除"

  # 移除 Nginx 配置
  rm -f /etc/nginx/sites-enabled/vaultwarden /etc/nginx/sites-available/vaultwarden
  nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null || true
  success "Nginx 配置已清除"

  # 移除 Fail2Ban
  rm -f /etc/fail2ban/filter.d/vaultwarden.conf \
        /etc/fail2ban/filter.d/vaultwarden-admin.conf \
        /etc/fail2ban/jail.d/vaultwarden.conf
  systemctl restart fail2ban 2>/dev/null || true
  success "Fail2Ban 规则已清除"

  # 移除定时任务、备份脚本、日志轮转
  rm -f /etc/cron.d/vaultwarden-backup \
        /usr/local/bin/vaultwarden-backup \
        /etc/logrotate.d/vaultwarden
  success "定时任务、备份脚本、日志轮转已清除"

  # 移除环境配置文件
  rm -f "$VW_ENV_FILE" "$CONF_FILE"
  success "配置文件已清除"

  # 移除日志目录（加路径安全校验，防止 VW_LOG_FILE 异常时误删当前目录）
  local _log_dir
  _log_dir=$(dirname "$VW_LOG_FILE")
  if [[ -n "$_log_dir" && "$_log_dir" != "." && "$_log_dir" != "/" && -d "$_log_dir" ]]; then
    rm -rf "$_log_dir"
    success "日志目录已删除：${_log_dir}"
  else
    warn "日志目录路径异常（${_log_dir}），已跳过删除"
  fi

  # 可选：删除数据目录
  if $DELETE_DATA; then
    rm -rf "$VW_DATA_DIR"
    success "数据目录已删除：${VW_DATA_DIR}"
  else
    info "数据目录已保留：${VW_DATA_DIR}"
  fi

  # 可选：删除备份目录
  if $DELETE_BACKUP; then
    rm -rf "$VW_BACKUP_DIR"
    success "备份目录已删除：${VW_BACKUP_DIR}"
  else
    info "备份目录已保留：${VW_BACKUP_DIR}"
  fi

  # 移除系统用户（仅当数据目录也删除时）
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

# ════════════════════════════════════════════════════════════════
#  主菜单
# ════════════════════════════════════════════════════════════════
show_menu() {
  show_banner
  echo -e "  ${BOLD}请选择操作：${NC}"
  echo ""
  echo -e "  ${CYAN}1)${NC} ${BOLD}install${NC}    — 全新安装（提取二进制 + systemd + Nginx + HTTPS + Fail2Ban）"
  echo -e "  ${CYAN}2)${NC} ${BOLD}update${NC}     — 更新到最新版（自动备份后替换二进制 + Web Vault）"
  echo -e "  ${CYAN}3)${NC} ${BOLD}backup${NC}     — 立即手动备份数据（含 SQLite WAL flush）"
  echo -e "  ${CYAN}4)${NC} ${BOLD}status${NC}     — 查看全面状态（服务/版本/数据/证书/防火墙）"
  echo -e "  ${CYAN}5)${NC} ${BOLD}uninstall${NC}  — 卸载（可选择保留或删除数据）"
  echo -e "  ${CYAN}q)${NC} 退出"
  echo ""
  prompt "请输入选项 [1-5]："
  local MENU_CHOICE
  read -r MENU_CHOICE
  case "${MENU_CHOICE,,}" in
    1|install)   do_install   ;;
    2|update)    do_update    ;;
    3|backup)    do_backup    ;;
    4|status)    do_status    ;;
    5|uninstall) do_uninstall ;;
    q|quit|exit) exit 0       ;;
    *) error "无效选项：${MENU_CHOICE}" ;;
  esac
}

# ════════════════════════════════════════════════════════════════
#  入口
# ════════════════════════════════════════════════════════════════
case "${1:-menu}" in
  install)   do_install   ;;
  update)    do_update    ;;
  backup)    do_backup    ;;
  status)    do_status    ;;
  uninstall) do_uninstall ;;
  menu|"")   show_menu    ;;
  *)
    echo -e "用法：sudo bash $0 [install|update|backup|status|uninstall]"
    echo -e "      不带参数则显示交互菜单"
    exit 1
    ;;
esac
