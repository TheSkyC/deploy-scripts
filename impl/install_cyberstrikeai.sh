#!/usr/bin/env bash
set -euo pipefail
umask 077
CSAI_DOMAIN="${CSAI_DOMAIN:-}"
PORT="${PORT:-8080}"
PUBLIC_PORT="${PUBLIC_PORT:-80}"
INSTALL_DIR="${INSTALL_DIR:-/opt/cyberstrike-ai}"
SERVICE_NAME="${SERVICE_NAME:-cyberstrike-ai}"
SERVICE_USER="${SERVICE_USER:-cyberstrike}"
GITHUB_REPO="${GITHUB_REPO:-Ed1s0nZ/CyberStrikeAI}"
GITHUB_BRANCH="${GITHUB_BRANCH:-main}"
BACKUP_DIR="${BACKUP_DIR:-/opt/cyberstrike-ai-backups}"
BACKUP_KEEP_DAYS="${BACKUP_KEEP_DAYS:-30}"
ENABLE_NGINX="${ENABLE_NGINX:-true}"
CSAI_HTTPS="${CSAI_HTTPS:-true}"
OPEN_FIREWALL="${OPEN_FIREWALL:-true}"
PIP_INDEX_URL="${PIP_INDEX_URL:-https://pypi.tuna.tsinghua.edu.cn/simple}"
GOPROXY="${GOPROXY:-https://goproxy.cn,direct}"
BIN_NAME="cyberstrike-ai"
BIN_PATH="${INSTALL_DIR}/${BIN_NAME}"
CONFIG_FILE="${INSTALL_DIR}/config.yaml"
VENV_DIR="${INSTALL_DIR}/venv"
LOG_DIR="${INSTALL_DIR}/logs"
LOCK_FILE="/var/lock/cyberstrike-ai-deploy.lock"
CONF_FILE="/etc/cyberstrike-ai-deploy.conf"
NGINX_CONF="/etc/nginx/sites-available/cyberstrike-ai"
NGINX_LINK="/etc/nginx/sites-enabled/cyberstrike-ai"
BACKUP_SCRIPT="/usr/local/bin/cyberstrike-ai-backup"
CRON_FILE="/etc/cron.d/cyberstrike-ai-backup"
LOGROTATE_FILE="/etc/logrotate.d/cyberstrike-ai"
CONFIG_KEYS=(
  CSAI_DOMAIN PORT PUBLIC_PORT INSTALL_DIR SERVICE_NAME SERVICE_USER
  GITHUB_REPO GITHUB_BRANCH BACKUP_DIR BACKUP_KEEP_DAYS ENABLE_NGINX
  CSAI_HTTPS OPEN_FIREWALL PIP_INDEX_URL GOPROXY
)
_bool_true() {
  case "${1,,}" in
    1|true|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}
save_config() {
  write_config_file "$CONF_FILE" "${CONFIG_KEYS[@]}"
  success "$(t config.saved "$CONF_FILE")"
}
load_config() {
  [[ ! -f "$CONF_FILE" ]] && return 0
  load_config_file "$CONF_FILE" "${CONFIG_KEYS[@]}" || return 0
  BIN_PATH="${INSTALL_DIR}/${BIN_NAME}"
  CONFIG_FILE="${INSTALL_DIR}/config.yaml"
  VENV_DIR="${INSTALL_DIR}/venv"
  LOG_DIR="${INSTALL_DIR}/logs"
}
preflight_check() {
  [[ $EUID -eq 0 ]] || error "$(t error.root_required "$0" "${1:-}")"
  command -v apt-get >/dev/null 2>&1 || error "$(t app.cyberstrikeai.error.apt_only)"
  command -v systemctl >/dev/null 2>&1 || error "$(t app.cyberstrikeai.error.systemd_required)"
  local arch
  arch=$(uname -m)
  case "$arch" in
    x86_64|aarch64|arm64) ;;
    *) error "$(t app.cyberstrikeai.error.arch "$arch")" ;;
  esac
}
check_connectivity() {
  check_connectivity_urls \
    "https://api.github.com" \
    "https://github.com" \
    "https://objects.githubusercontent.com" && return 0
  error "$(t app.cyberstrikeai.error.github_unreachable)"
}
apt_install_base() {
  step "Install system dependencies"
  apt-get update -qq
  apt-get install -y -qq \
    ca-certificates curl git build-essential \
    python3 python3-venv python3-pip \
    sqlite3 tar gzip openssl lsof
  if _bool_true "$ENABLE_NGINX"; then
    apt-get install -y -qq nginx
  fi
  success "Base dependencies installed"
}
install_go_if_needed() {
  local need_install=false
  if ! command -v go >/dev/null 2>&1; then
    need_install=true
  else
    local ver major minor
    ver=$(go version | awk '{print $3}' | sed 's/^go//')
    major="${ver%%.*}"
    minor="${ver#*.}"; minor="${minor%%.*}"
    if [[ "$major" -lt 1 || ( "$major" -eq 1 && "$minor" -lt 21 ) ]]; then
      need_install=true
      warn "Go version is too old: $ver"
    fi
  fi
  if ! $need_install; then
    success "Go is ready: $(go version)"
    return 0
  fi
  step "Install Go"
  apt-get install -y -qq golang-go || true
  if command -v go >/dev/null 2>&1; then
    local ver major minor
    ver=$(go version | awk '{print $3}' | sed 's/^go//')
    major="${ver%%.*}"
    minor="${ver#*.}"; minor="${minor%%.*}"
    if [[ "$major" -gt 1 || ( "$major" -eq 1 && "$minor" -ge 21 ) ]]; then
      success "Go installed: $(go version)"
      return 0
    fi
    warn "Repository Go is still too old: $ver. Installing official Go toolchain."
  fi
  local arch go_arch latest_json version tarball url tmp
  arch=$(uname -m)
  case "$arch" in
    x86_64) go_arch="amd64" ;;
    aarch64|arm64) go_arch="arm64" ;;
    *) error "Unsupported architecture for Go install: $arch" ;;
  esac
  latest_json=$(curl -fsSL --max-time 20 "https://go.dev/dl/?mode=json" 2>/dev/null) \
    || error "Failed to query official Go releases"
  version=$(printf '%s\n' "$latest_json" | grep -oE '"version"[[:space:]]*:[[:space:]]*"go[0-9]+\.[0-9]+(\.[0-9]+)?"' | head -1 | sed 's/.*"\(go[^"]*\)".*/\1/')
  [[ -n "$version" ]] || error "Failed to parse latest Go version"
  tarball="${version}.linux-${go_arch}.tar.gz"
  url="https://go.dev/dl/${tarball}"
  tmp=$(mktemp)
  info "Downloading ${url}"
  curl -fL --retry 3 --connect-timeout 15 -o "$tmp" "$url"
  [[ -s "$tmp" ]] || error "Downloaded Go archive is empty"
  rm -rf /usr/local/go
  tar -C /usr/local -xzf "$tmp"
  rm -f "$tmp"
  ln -sf /usr/local/go/bin/go /usr/local/bin/go
  ln -sf /usr/local/go/bin/gofmt /usr/local/bin/gofmt
  hash -r 2>/dev/null || true
  command -v go >/dev/null 2>&1 || error "Go installation failed. Please install Go 1.21+ manually."
  success "Go installed: $(go version)"
}
ensure_service_user() {
  if ! id "$SERVICE_USER" >/dev/null 2>&1; then
    useradd --system --home "$INSTALL_DIR" --shell /usr/sbin/nologin "$SERVICE_USER"
    success "Created service user: $SERVICE_USER"
  fi
}
clone_or_update_repo() {
  step "Fetch CyberStrikeAI source"
  mkdir -p "$(dirname "$INSTALL_DIR")"
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    info "Repository exists, fetching latest branch: $GITHUB_BRANCH"
    git -C "$INSTALL_DIR" fetch --prune origin "$GITHUB_BRANCH"
    git -C "$INSTALL_DIR" checkout -q "$GITHUB_BRANCH"
    git -C "$INSTALL_DIR" pull --ff-only origin "$GITHUB_BRANCH"
  elif [[ -d "$INSTALL_DIR" && -n "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]]; then
    error "$INSTALL_DIR exists and is not an empty git checkout"
  else
    rm -rf "$INSTALL_DIR"
    git clone --depth 1 --branch "$GITHUB_BRANCH" "https://github.com/${GITHUB_REPO}.git" "$INSTALL_DIR"
  fi
  success "Source ready: $INSTALL_DIR"
}
patch_config_port_and_paths() {
  [[ -f "$CONFIG_FILE" ]] || error "Missing config.yaml at $CONFIG_FILE"
  local backup="${CONFIG_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
  cp "$CONFIG_FILE" "$backup"
  python3 - "$CONFIG_FILE" "$PORT" "$LOG_DIR/cyberstrike-ai.log" "$CSAI_HTTPS" <<'PY'
from pathlib import Path
import re
import sys

path = Path(sys.argv[1])
port = sys.argv[2]
log_file = sys.argv[3]
https_enabled = sys.argv[4].strip().lower() in {"1", "true", "yes", "y", "on"}
text = path.read_text(encoding="utf-8")

def replace_in_section(src, section, key, value):
    pattern = re.compile(
        rf"(^[ \t]*{re.escape(section)}:[^\n]*\n)(.*?)(?=^[^ \t#][^:\n]*:|\Z)",
        re.M | re.S,
    )
    m = pattern.search(src)
    if not m:
        return src + f"\n{section}:\n  {key}: {value}\n"
    block = m.group(2)
    key_pattern = re.compile(rf"(^[ \t]*{re.escape(key)}:[^\n]*$)", re.M)
    if key_pattern.search(block):
        block = key_pattern.sub(f"  {key}: {value}", block, count=1)
    else:
        block = block.rstrip() + f"\n  {key}: {value}\n"
    return src[:m.start(2)] + block + src[m.end(2):]

text = replace_in_section(text, "server", "host", "127.0.0.1")
text = replace_in_section(text, "server", "port", port)
text = replace_in_section(text, "server", "tls_enabled", "true" if https_enabled else "false")
text = replace_in_section(text, "server", "tls_auto_self_sign", "true" if https_enabled else "false")
text = replace_in_section(text, "log", "output", log_file)

path.write_text(text, encoding="utf-8")
PY
  success "Adjusted config.yaml: local host, port $PORT, log file"
}
setup_python_env() {
  step "Prepare Python environment"
  cd "$INSTALL_DIR"
  if [[ ! -d "$VENV_DIR" ]]; then
    python3 -m venv "$VENV_DIR"
  fi
  source "$VENV_DIR/bin/activate"
  python -m pip install --index-url "$PIP_INDEX_URL" --upgrade pip >/dev/null 2>&1 || true
  if [[ -f requirements.txt ]]; then
    local pip_log
    pip_log=$(mktemp)
    if python -m pip install --index-url "$PIP_INDEX_URL" -r requirements.txt >"$pip_log" 2>&1; then
      success "Python requirements installed"
    else
      warn "Some Python requirements failed to install; continuing because several tools are optional"
      tail -n 20 "$pip_log" | sed 's/^/  /' >&2 || true
    fi
    rm -f "$pip_log"
  else
    warn "requirements.txt not found; skipping Python dependency install"
  fi
}
build_binary() {
  step "Build Go binary"
  cd "$INSTALL_DIR"
  export GOPROXY="$GOPROXY"
  go mod download
  local tmp_bin="${BIN_PATH}.tmp.$$"
  go build -trimpath -ldflags="-s -w" -o "$tmp_bin" cmd/server/main.go
  [[ -s "$tmp_bin" ]] || error "Built binary is empty"
  chmod 0755 "$tmp_bin"
  mv "$tmp_bin" "$BIN_PATH"
  success "Built binary: $BIN_PATH"
}
install_runtime_dirs() {
  step "Prepare runtime directories"
  mkdir -p "$LOG_DIR" "$INSTALL_DIR/data" "$INSTALL_DIR/tmp" "$BACKUP_DIR"
  chown -R "${SERVICE_USER}:${SERVICE_USER}" "$INSTALL_DIR" "$BACKUP_DIR"
  chmod 750 "$INSTALL_DIR" "$BACKUP_DIR"
  chmod 750 "$LOG_DIR" "$INSTALL_DIR/data" "$INSTALL_DIR/tmp"
  success "Runtime directories prepared"
}
write_systemd_unit() {
  step "Install systemd service"
  local https_env="false"
  _bool_true "$CSAI_HTTPS" && https_env="true"
  cat > "/etc/systemd/system/${SERVICE_NAME}.service" <<SERVICE
[Unit]
Description=CyberStrikeAI
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_USER}
WorkingDirectory=${INSTALL_DIR}
Environment=CYBERSTRIKE_HTTPS=${https_env}
Environment=PATH=${VENV_DIR}/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
ExecStart=${BIN_PATH} -config ${CONFIG_FILE}
Restart=on-failure
RestartSec=5
TimeoutStopSec=30
KillSignal=SIGTERM
LimitNOFILE=65536
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ReadWritePaths=${INSTALL_DIR} ${BACKUP_DIR}
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE
  systemctl daemon-reload
  systemctl enable "$SERVICE_NAME" --quiet
  success "systemd unit installed: $SERVICE_NAME"
}
write_nginx_config() {
  _bool_true "$ENABLE_NGINX" || return 0
  step "Configure Nginx reverse proxy"
  local server_name="_"
  [[ -n "$CSAI_DOMAIN" ]] && server_name="$CSAI_DOMAIN"
  local upstream_scheme="http"
  _bool_true "$CSAI_HTTPS" && upstream_scheme="https"
  cat > "$NGINX_CONF" <<NGINX
server {
    listen ${PUBLIC_PORT};
    listen [::]:${PUBLIC_PORT};
    server_name ${server_name};

    client_max_body_size 256m;
    charset utf-8;

    location / {
        proxy_pass ${upstream_scheme}://127.0.0.1:${PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_buffering off;
        proxy_ssl_verify off;
    }

    location /api/ {
        proxy_pass ${upstream_scheme}://127.0.0.1:${PORT};
        proxy_http_version 1.1;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_buffering off;
        proxy_ssl_verify off;
    }

    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;

    access_log /var/log/nginx/cyberstrike-ai_access.log;
    error_log  /var/log/nginx/cyberstrike-ai_error.log;
}
NGINX
  ln -sf "$NGINX_CONF" "$NGINX_LINK"
  nginx -t
  systemctl enable nginx --quiet
  systemctl reload nginx 2>/dev/null || systemctl restart nginx
  success "Nginx reverse proxy installed"
}
open_firewall_ports() {
  _bool_true "$OPEN_FIREWALL" || return 0
  step "Configure firewall"
  if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -q "Status: active"; then
    if _bool_true "$ENABLE_NGINX"; then
      ufw allow "${PUBLIC_PORT}/tcp" >/dev/null 2>&1 || true
      success "ufw allows public port: $PUBLIC_PORT/tcp"
    else
      ufw allow "${PORT}/tcp" >/dev/null 2>&1 || true
      success "ufw allows backend port: $PORT/tcp"
    fi
    return 0
  fi
  if command -v iptables >/dev/null 2>&1; then
    local port_to_open="$PORT"
    _bool_true "$ENABLE_NGINX" && port_to_open="$PUBLIC_PORT"
    if ! iptables -C INPUT -p tcp --dport "$port_to_open" -j ACCEPT 2>/dev/null; then
      iptables -A INPUT -p tcp --dport "$port_to_open" -j ACCEPT
    fi
    success "iptables allows port: $port_to_open/tcp"
    return 0
  fi
  warn "No active ufw/iptables detected. Cloud security groups may still need manual rules."
}
write_logrotate() {
  cat > "$LOGROTATE_FILE" <<ROTATE
${LOG_DIR}/*.log {
    daily
    rotate 14
    missingok
    notifempty
    copytruncate
    compress
}
ROTATE
  chmod 644 "$LOGROTATE_FILE"
}
write_backup_script() {
  cat > "$BACKUP_SCRIPT" <<BACKUP
#!/usr/bin/env bash
set -euo pipefail
umask 077

INSTALL_DIR="${INSTALL_DIR}"
CONFIG_FILE="${CONFIG_FILE}"
BACKUP_DIR="${BACKUP_DIR}"
KEEP_DAYS="${BACKUP_KEEP_DAYS}"
SERVICE_NAME="${SERVICE_NAME}"

mkdir -p "\$BACKUP_DIR"
if [[ ! -d "\$INSTALL_DIR" ]]; then
  echo "\$(date '+%F %T') [ERROR] install dir missing: \$INSTALL_DIR" >&2
  exit 1
fi

if command -v sqlite3 >/dev/null 2>&1; then
  find "\$INSTALL_DIR/data" -maxdepth 1 -name "*.db" -type f 2>/dev/null | while read -r db; do
    sqlite3 "\$db" "PRAGMA wal_checkpoint(TRUNCATE);" >/dev/null 2>&1 || true
    integrity=\$(sqlite3 "\$db" "PRAGMA integrity_check;" 2>/dev/null || echo "error")
    [[ "\$integrity" == "ok" ]] || echo "\$(date '+%F %T') [WARN] SQLite integrity warning for \$db: \$integrity" >&2
  done
fi

ts=\$(date +%Y%m%d_%H%M%S)
archive="\$BACKUP_DIR/cyberstrike-ai_\${ts}.tar.gz"
tmp="\${archive}.tmp"

tar -czf "\$tmp" \
  --exclude=".git" \
  --exclude="venv" \
  --exclude="cyberstrike-ai" \
  --exclude="*.tmp" \
  --exclude="logs/*.log" \
  -C "\$(dirname "\$INSTALL_DIR")" "\$(basename "\$INSTALL_DIR")"
mv "\$tmp" "\$archive"

if [[ "\$KEEP_DAYS" -gt 0 ]]; then
  find "\$BACKUP_DIR" -maxdepth 1 -name "cyberstrike-ai_*.tar.gz" -mtime "+\$KEEP_DAYS" -delete 2>/dev/null || true
fi

echo "\$(date '+%F %T') [OK] backup created: \$archive"
BACKUP
  chmod 755 "$BACKUP_SCRIPT"
  cat > "$CRON_FILE" <<CRON
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
30 3 * * * root ${BACKUP_SCRIPT} >> ${LOG_DIR}/backup.log 2>&1
CRON
  chmod 644 "$CRON_FILE"
}
check_port_conflict() {
  local port="$1"
  if command -v ss >/dev/null 2>&1 && ss -ltn "( sport = :$port )" | tail -n +2 | grep -q .; then
    warn "Port $port appears to be in use:"
    ss -ltnp "( sport = :$port )" 2>/dev/null | sed 's/^/  /' >&2 || true
  elif command -v lsof >/dev/null 2>&1 && lsof -iTCP:"$port" -sTCP:LISTEN -Pn >/dev/null 2>&1; then
    warn "Port $port appears to be in use:"
    lsof -iTCP:"$port" -sTCP:LISTEN -Pn | sed 's/^/  /' >&2 || true
  fi
}
start_service() {
  step "Start CyberStrikeAI"
  check_port_conflict "$PORT"
  systemctl restart "$SERVICE_NAME"
  if wait_for_service "$SERVICE_NAME" 35; then
    success "$SERVICE_NAME is running"
  else
    journalctl -u "$SERVICE_NAME" -n 40 --no-pager >&2 || true
    error "$SERVICE_NAME failed to start"
  fi
}
health_check() {
  step "Health check"
  local scheme="http"
  _bool_true "$CSAI_HTTPS" && scheme="https"
  local code
  code=$(curl -k -o /dev/null -s -w "%{http_code}" --max-time 8 "${scheme}://127.0.0.1:${PORT}/" || echo "000")
  if [[ "$code" =~ ^(200|301|302|308)$ ]]; then
    success "Backend health OK: ${scheme}://127.0.0.1:${PORT}/ HTTP $code"
  else
    warn "Backend health returned HTTP $code"
  fi
  if _bool_true "$ENABLE_NGINX"; then
    code=$(curl -o /dev/null -s -w "%{http_code}" --max-time 8 "http://127.0.0.1:${PUBLIC_PORT}/" || echo "000")
    if [[ "$code" =~ ^(200|301|302|308)$ ]]; then
      success "Nginx health OK: http://127.0.0.1:${PUBLIC_PORT}/ HTTP $code"
    else
      warn "Nginx health returned HTTP $code"
    fi
  fi
}
print_summary() {
  local ip
  ip=$(hostname -I 2>/dev/null | awk '{print $1}')
  local backend_scheme="http"
  _bool_true "$CSAI_HTTPS" && backend_scheme="https"
  echo ""
  echo -e "${BOLD}${GREEN}CyberStrikeAI deployment complete${NC}"
  echo "  service:      ${SERVICE_NAME}"
  echo "  install dir:  ${INSTALL_DIR}"
  echo "  config:       ${CONFIG_FILE}"
  echo "  logs:         ${LOG_DIR}"
  echo "  backups:      ${BACKUP_DIR}"
  echo "  backend:      ${backend_scheme}://127.0.0.1:${PORT}/"
  if _bool_true "$ENABLE_NGINX"; then
    if [[ -n "$CSAI_DOMAIN" ]]; then
      echo "  public:       http://${CSAI_DOMAIN}:${PUBLIC_PORT}/"
    elif [[ -n "${ip:-}" ]]; then
      echo "  public:       http://${ip}:${PUBLIC_PORT}/"
    else
      echo "  public:       http://<server-ip>:${PUBLIC_PORT}/"
    fi
  fi
  echo ""
  echo "Useful commands:"
  echo "  systemctl status ${SERVICE_NAME} --no-pager"
  echo "  journalctl -u ${SERVICE_NAME} -n 80 --no-pager"
  echo "  bash $0 status"
  echo ""
  warn "Set your model API key/base_url/model in the Web Settings page or edit ${CONFIG_FILE}."
  warn "Use this platform only for authorized security testing."
}
do_install() {
  show_banner
  preflight_check "install"
  acquire_lock
  check_connectivity
  apt_install_base
  install_go_if_needed
  ensure_service_user
  clone_or_update_repo
  mkdir -p "$LOG_DIR"
  patch_config_port_and_paths
  setup_python_env
  build_binary
  install_runtime_dirs
  write_systemd_unit
  write_nginx_config
  write_logrotate
  write_backup_script
  open_firewall_ports
  save_config
  start_service
  health_check
  print_summary
  release_lock
}
do_backup() {
  show_banner
  preflight_check "backup"
  load_config
  acquire_lock
  step "Manual backup"
  "$BACKUP_SCRIPT"
  info "Latest backups:"
  find "$BACKUP_DIR" -maxdepth 1 -name "cyberstrike-ai_*.tar.gz" -printf '%T@ %p\n' 2>/dev/null \
    | sort -rn | head -10 | awk '{print $2}' | while read -r file; do
        [[ -n "$file" ]] || continue
        printf '  %-70s %s\n' "$(basename "$file")" "$(du -sh "$file" 2>/dev/null | awk '{print $1}')" >&2
      done
  release_lock
}
do_update() {
  show_banner
  preflight_check "update"
  load_config
  acquire_lock
  check_connectivity
  [[ -d "$INSTALL_DIR/.git" ]] || error "$INSTALL_DIR is not a git checkout. Run install first."
  step "Pre-update backup"
  if [[ -x "$BACKUP_SCRIPT" ]]; then
    "$BACKUP_SCRIPT" || warn "Pre-update backup failed; continuing cautiously"
  fi
  local old_rev new_rev bin_bak config_bak service_was_active=false
  old_rev=$(git -C "$INSTALL_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
  systemctl is-active --quiet "$SERVICE_NAME" && service_was_active=true
  bin_bak="${BIN_PATH}.bak.$(date +%Y%m%d_%H%M%S)"
  config_bak="${CONFIG_FILE}.preupdate.$(date +%Y%m%d_%H%M%S)"
  [[ -f "$BIN_PATH" ]] && cp "$BIN_PATH" "$bin_bak"
  [[ -f "$CONFIG_FILE" ]] && cp "$CONFIG_FILE" "$config_bak"
  step "Update source"
  git -C "$INSTALL_DIR" fetch --prune origin "$GITHUB_BRANCH"
  git -C "$INSTALL_DIR" checkout -q "$GITHUB_BRANCH"
  git -C "$INSTALL_DIR" pull --ff-only origin "$GITHUB_BRANCH"
  new_rev=$(git -C "$INSTALL_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
  setup_python_env
  patch_config_port_and_paths
  build_binary
  chown -R "${SERVICE_USER}:${SERVICE_USER}" "$INSTALL_DIR"
  if $service_was_active; then
    step "Restart updated service"
    systemctl restart "$SERVICE_NAME"
    if wait_for_service "$SERVICE_NAME" 35; then
      success "Update complete: $old_rev -> $new_rev"
      health_check
    else
      warn "Updated version failed to start. Rolling back binary and config."
      systemctl stop "$SERVICE_NAME" 2>/dev/null || true
      [[ -f "$bin_bak" ]] && cp "$bin_bak" "$BIN_PATH"
      [[ -f "$config_bak" ]] && cp "$config_bak" "$CONFIG_FILE"
      chown "${SERVICE_USER}:${SERVICE_USER}" "$BIN_PATH" "$CONFIG_FILE" 2>/dev/null || true
      systemctl start "$SERVICE_NAME" 2>/dev/null || true
      if wait_for_service "$SERVICE_NAME" 35; then
        error "Update failed and rollback succeeded. Inspect: journalctl -u ${SERVICE_NAME} -n 80 --no-pager"
      else
        error "Update failed and rollback also failed. Inspect: journalctl -u ${SERVICE_NAME} -n 120 --no-pager"
      fi
    fi
  else
    success "Update complete while service was inactive: $old_rev -> $new_rev"
  fi
  find "$INSTALL_DIR" -maxdepth 1 -name "${BIN_NAME}.bak.*" -type f -printf '%T@ %p\n' 2>/dev/null \
    | sort -rn | tail -n +4 | awk '{print $2}' | xargs -r rm -f
  release_lock
}
do_status() {
  show_banner
  preflight_check "status"
  load_config
  step "Service status"
  if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    echo -e "  ${GREEN}[+]${NC} ${SERVICE_NAME}: running"
  elif systemctl is-failed --quiet "$SERVICE_NAME" 2>/dev/null; then
    echo -e "  ${RED}[x]${NC} ${SERVICE_NAME}: failed"
  else
    echo -e "  ${YELLOW}[!]${NC} ${SERVICE_NAME}: inactive / unknown"
  fi
  systemctl status "$SERVICE_NAME" --no-pager -l 2>/dev/null | head -16 | sed 's/^/  /' >&2 || true
  step "Version and paths"
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    echo "  git revision: $(git -C "$INSTALL_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    echo "  git branch:   $(git -C "$INSTALL_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
  fi
  [[ -x "$BIN_PATH" ]] && echo "  binary:       $BIN_PATH ($(du -sh "$BIN_PATH" | awk '{print $1}'))" || echo "  binary:       missing"
  echo "  config:       $CONFIG_FILE"
  echo "  logs:         $LOG_DIR"
  echo "  backups:      $BACKUP_DIR"
  step "Process resources"
  local pid
  pid=$(systemctl show "$SERVICE_NAME" --property=MainPID --value 2>/dev/null || echo "0")
  if [[ "$pid" != "0" && -d "/proc/$pid" ]]; then
    echo "  PID:          $pid"
    echo "  memory RSS:   $(awk '/VmRSS/{printf "%.1f MB", $2/1024}' "/proc/$pid/status" 2>/dev/null || echo N/A)"
    echo "  CPU:          $(ps -p "$pid" -o %cpu= 2>/dev/null | tr -d ' ')%"
    echo "  uptime:       $(ps -p "$pid" -o etime= 2>/dev/null | tr -d ' ')"
  else
    echo "  process:      not running"
  fi
  step "Health"
  health_check
  step "Nginx"
  if _bool_true "$ENABLE_NGINX"; then
    if command -v nginx >/dev/null 2>&1; then
      systemctl is-active --quiet nginx && echo "  nginx:        running" || echo "  nginx:        not running"
      [[ -f "$NGINX_CONF" ]] && echo "  config:       $NGINX_CONF" || echo "  config:       missing"
      nginx -t >/dev/null 2>&1 && echo "  syntax:       OK" || echo "  syntax:       failed"
    else
      echo "  nginx:        not installed"
    fi
  else
    echo "  nginx:        disabled by config"
  fi
  step "Backups"
  if [[ -d "$BACKUP_DIR" ]]; then
    local count size
    count=$(find "$BACKUP_DIR" -maxdepth 1 -name "cyberstrike-ai_*.tar.gz" 2>/dev/null | wc -l)
    size=$(du -sh "$BACKUP_DIR" 2>/dev/null | awk '{print $1}')
    echo "  backup dir:   $BACKUP_DIR ($size, $count files)"
    find "$BACKUP_DIR" -maxdepth 1 -name "cyberstrike-ai_*.tar.gz" -printf '%T@ %p\n' 2>/dev/null \
      | sort -rn | head -5 | awk '{print $2}' | while read -r file; do
          [[ -n "$file" ]] || continue
          printf '  %-70s %s\n' "$(basename "$file")" "$(du -sh "$file" 2>/dev/null | awk '{print $1}')" >&2
        done
  else
    echo "  backup dir:   missing"
  fi
  echo ""
}
do_uninstall() {
  show_banner
  preflight_check "uninstall"
  load_config
  acquire_lock
  require_safe_path "INSTALL_DIR" "${INSTALL_DIR:-}"
  require_safe_path "BACKUP_DIR" "${BACKUP_DIR:-}"
  step "Uninstall CyberStrikeAI"
  echo -e "${RED}${BOLD}"
  echo "This will remove:"
  echo "  - systemd service: ${SERVICE_NAME}"
  echo "  - Nginx config: ${NGINX_CONF}"
  echo "  - logrotate and cron backup config"
  echo "  - deploy config: ${CONF_FILE}"
  echo ""
  echo "Install dir and backup dir are kept by default unless you choose deletion."
  echo -e "${NC}"
  prompt "Type YES to continue:"
  local confirm
  read -r confirm
  [[ "$confirm" == "YES" ]] || { info "Cancelled"; exit 0; }
  prompt "Delete install directory ${INSTALL_DIR}? [y/N]:"
  local del_install
  read -r del_install
  prompt "Delete backup directory ${BACKUP_DIR}? [y/N]:"
  local del_backup
  read -r del_backup
  systemctl stop "$SERVICE_NAME" 2>/dev/null || true
  systemctl disable "$SERVICE_NAME" 2>/dev/null || true
  rm -f "/etc/systemd/system/${SERVICE_NAME}.service"
  systemctl daemon-reload
  success "Removed systemd service"
  rm -f "$NGINX_LINK" "$NGINX_CONF"
  if command -v nginx >/dev/null 2>&1 && nginx -t >/dev/null 2>&1; then
    systemctl reload nginx 2>/dev/null || true
  fi
  success "Removed Nginx config"
  rm -f "$LOGROTATE_FILE" "$CRON_FILE" "$BACKUP_SCRIPT" "$CONF_FILE"
  success "Removed deploy configs"
  if [[ "${del_install,,}" == "y" ]]; then
    safe_rm_dir "$INSTALL_DIR" "INSTALL_DIR"
    success "Deleted install dir: $INSTALL_DIR"
  else
    info "Kept install dir: $INSTALL_DIR"
  fi
  if [[ "${del_backup,,}" == "y" ]]; then
    safe_rm_dir "$BACKUP_DIR" "BACKUP_DIR"
    success "Deleted backup dir: $BACKUP_DIR"
  else
    info "Kept backup dir: $BACKUP_DIR"
  fi
  if [[ "${del_install,,}" == "y" ]] && id "$SERVICE_USER" >/dev/null 2>&1; then
    userdel "$SERVICE_USER" 2>/dev/null && success "Deleted user: $SERVICE_USER" || warn "Could not delete user: $SERVICE_USER"
  fi
  echo ""
  success "CyberStrikeAI uninstalled"
  release_lock
}
