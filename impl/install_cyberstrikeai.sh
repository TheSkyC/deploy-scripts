#!/usr/bin/env bash
set -euo pipefail
umask 077
CSAI_DOMAIN="${CSAI_DOMAIN:-}"
PORT="${PORT:-8083}"
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
_CSAI_DERIVE_PATHS() {
  BIN_PATH="${INSTALL_DIR}/${BIN_NAME}"
  CONFIG_FILE="${INSTALL_DIR}/config.yaml"
  VENV_DIR="${INSTALL_DIR}/venv"
  LOG_DIR="${INSTALL_DIR}/logs"
}
APP_CONFIG_DERIVE_HOOK=_CSAI_DERIVE_PATHS
_csai_status_backup() {
  local conf_file backup_dir latest_archive archive_name archive_mtime last_success_at
  conf_file="$(app_conf_file 2>/dev/null || true)"
  backup_dir="${BACKUP_DIR:-}"
  if [[ -f "$conf_file" ]]; then
    local owner mode configured_dir
    owner="$(stat -c '%U' "$conf_file" 2>/dev/null || printf unknown)"
    mode="$(stat -c '%a' "$conf_file" 2>/dev/null || printf unknown)"
    if [[ "$owner" != root || ( "$mode" != 600 && "$mode" != 400 ) ]]; then
      printf '{"state":"unknown","last_success_at":null,"path":null,"message":"configuration file is not trusted"}'
      return
    fi
    configured_dir="$(awk -F= '
        /^[[:space:]]*BACKUP_DIR=/ {
          value=$0
          sub(/^[^=]*=[[:space:]]*/, "", value)
          gsub(/^"|"$/, "", value)
          gsub(/[[:space:]]+$/, "", value)
          print value
          exit
        }
      ' "$conf_file" 2>/dev/null)"
    [[ -n "$configured_dir" ]] && backup_dir="$configured_dir"
  fi
  if [[ -z "$backup_dir" ]] || ! is_safe_path "$backup_dir"; then
    printf '{"state":"unknown","last_success_at":null,"path":%s,"message":"backup directory is unsafe"}' "$(app_json_string "$backup_dir")"
    return
  fi
  if ! latest_archive="$(find "$backup_dir" -maxdepth 1 -type f -name 'cyberstrike-ai_*.tar.gz' -printf '%T@ %p\n' 2>/dev/null | sort -nr)"; then
    printf '{"state":"failed","last_success_at":null,"path":%s,"message":"cannot inspect backup directory"}' "$(app_json_string "$backup_dir")"
    return
  fi
  latest_archive="${latest_archive%%$'\n'*}"
  if [[ -z "$latest_archive" ]]; then
    printf '{"state":"missing","last_success_at":null,"path":%s,"message":"no backup archive found"}' "$(app_json_string "$backup_dir")"
    return
  fi
  archive_name="${latest_archive#* }"
  archive_mtime="${latest_archive%% *}"
  if ! last_success_at="$(date -d "@${archive_mtime%.*}" '+%Y-%m-%dT%H:%M:%S%:z' 2>/dev/null)"; then
    printf '{"state":"unknown","last_success_at":null,"path":%s,"message":"cannot read backup timestamp"}' "$(app_json_string "$archive_name")"
    return
  fi
  printf '{"state":"available","last_success_at":%s,"path":%s,"message":null}' \
    "$(app_json_string "$last_success_at")" "$(app_json_string "$archive_name")"
}
APP_STATUS_BACKUP_FN=_csai_status_backup
_csai_remove_dir_or_error() {
  local path="$1" name="$2" success_message="$3"
  if ! safe_rm_dir "$path" "$name"; then
    error "$(t app.cyberstrikeai.error.remove_dir "$path")"
  fi
  success "$success_message"
}
_csai_remove_file_or_error() {
  local path="$1" name="$2"
  require_safe_path "$name" "$path"
  if ! rm -f "$path"; then
    error "$(t app.cyberstrikeai.error.remove_file "$path")"
  fi
}
_bool_true() {
  case "${1,,}" in
    1|true|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}
app_conf_register_legacy "/etc/cyberstrike-ai-deploy.conf"
CONF_FILE="$(app_conf_file)"
LOCK_FILE="$(app_lock_file)"
_validate_config_values() {
  app_validate_port "$PORT" "PORT"
  app_validate_port "$PUBLIC_PORT" "PUBLIC_PORT"
  app_validate_domain "CSAI_DOMAIN" "$CSAI_DOMAIN"
  app_validate_bool "ENABLE_NGINX" "$ENABLE_NGINX"
  app_validate_bool "CSAI_HTTPS" "$CSAI_HTTPS"
  app_validate_bool "OPEN_FIREWALL" "$OPEN_FIREWALL"
  app_validate_systemd_name "SERVICE_NAME" "$SERVICE_NAME"
  app_validate_system_name "SERVICE_USER" "$SERVICE_USER"
  app_validate_github_repo "GITHUB_REPO" "$GITHUB_REPO"
  app_validate_git_ref "GITHUB_BRANCH" "$GITHUB_BRANCH"
  app_validate_http_url "PIP_INDEX_URL" "$PIP_INDEX_URL"
  app_validate_goproxy "GOPROXY" "$GOPROXY"
  require_safe_path "INSTALL_DIR" "$INSTALL_DIR"
  require_safe_path "BIN_PATH" "$BIN_PATH"
  require_safe_path "CONFIG_FILE" "$CONFIG_FILE"
  require_safe_path "VENV_DIR" "$VENV_DIR"
  require_safe_path "LOG_DIR" "$LOG_DIR"
  require_safe_path "BACKUP_DIR" "$BACKUP_DIR"
}
preflight_check() {
  [[ "${1:-}" == "status" || $EUID -eq 0 ]] || error "$(t error.root_required "$0" "${1:-}")"
  command -v apt-get >/dev/null 2>&1 || error "$(t app.cyberstrikeai.error.apt_only)"
  command -v systemctl >/dev/null 2>&1 || error "$(t app.cyberstrikeai.error.systemd_required)"
  local arch
  arch=$(uname -m)
  case "$arch" in
    x86_64|aarch64|arm64) ;;
    *) error "$(t app.cyberstrikeai.error.arch "$arch")" ;;
  esac
  _validate_config_values
}
check_connectivity() {
  app_check_connectivity app.cyberstrikeai.error.github_unreachable \
    "https://api.github.com" \
    "https://github.com" \
    "https://objects.githubusercontent.com"
}
restore_old_go_toolchain() {
  local old_go_backup="$1"
  [[ -n "$old_go_backup" && -e "$old_go_backup" ]] || return 0
  [[ ! -e /usr/local/go ]] || return 1
  mv "$old_go_backup" /usr/local/go
}
write_tool_symlink() {
  local target="$1" link_path="$2"
  if ! atomic_symlink "$target" "$link_path"; then
    error "$(t app.cyberstrikeai.error.go_failed)"
  fi
}
write_backup_file() {
  local source_path="$1" backup_path="$2"
  [[ -f "$source_path" ]] || return 0
  atomic_copy_file "$source_path" "$backup_path"
}
go_release_sha256() {
  local release_json="$1" tarball="$2"
  printf '%s\n' "$release_json" | awk -v target="$tarball" '
    index($0, "\"filename\": \"" target "\"") { in_file=1; next }
    in_file && /"sha256"[[:space:]]*:/ {
      sub(/^.*"sha256"[[:space:]]*:[[:space:]]*"/, "")
      sub(/".*$/, "")
      print
      exit
    }
    in_file && /^[[:space:]]*}/ { in_file=0 }
  '
}
verify_go_archive_checksum() {
  local archive="$1" expected_sha="$2" tarball="$3" actual_sha=""
  if ! [[ "$expected_sha" =~ ^[0-9a-fA-F]{64}$ ]]; then
    if ! rm -f "$archive"; then
      warn "$(t app.cyberstrikeai.warn.go_archive_cleanup_failed "$archive")"
    fi
    error "$(t app.cyberstrikeai.error.go_checksum_missing "$tarball")"
  fi
  if command -v sha256sum >/dev/null 2>&1; then
    if ! actual_sha=$(sha256sum "$archive" | awk '{print $1}'); then
      if ! rm -f "$archive"; then
        warn "$(t app.cyberstrikeai.warn.go_archive_cleanup_failed "$archive")"
      fi
      error "$(t app.cyberstrikeai.error.go_sha_failed "$expected_sha" "${actual_sha:-unavailable}")"
    fi
  elif command -v shasum >/dev/null 2>&1; then
    if ! actual_sha=$(shasum -a 256 "$archive" | awk '{print $1}'); then
      if ! rm -f "$archive"; then
        warn "$(t app.cyberstrikeai.warn.go_archive_cleanup_failed "$archive")"
      fi
      error "$(t app.cyberstrikeai.error.go_sha_failed "$expected_sha" "${actual_sha:-unavailable}")"
    fi
  else
    if ! rm -f "$archive"; then
      warn "$(t app.cyberstrikeai.warn.go_archive_cleanup_failed "$archive")"
    fi
    error "$(t app.cyberstrikeai.error.go_sha_tool_missing)"
  fi
  if [[ "$actual_sha" != "$expected_sha" ]]; then
    if ! rm -f "$archive"; then
      warn "$(t app.cyberstrikeai.warn.go_archive_cleanup_failed "$archive")"
    fi
    error "$(t app.cyberstrikeai.error.go_sha_failed "$expected_sha" "$actual_sha")"
  fi
  info "$(t app.cyberstrikeai.info.go_sha_ok "${actual_sha:0:16}")"
}
apt_install_base() {
  step "$(t app.cyberstrikeai.step.install_deps)"
  if ! apt-get update -qq; then
    error "$(t app.cyberstrikeai.error.apt_update)"
  fi
  if ! apt-get install -y -qq \
    ca-certificates curl git build-essential \
    python3 python3-venv python3-pip \
    sqlite3 tar gzip openssl lsof; then
    error "$(t app.cyberstrikeai.error.deps_install)"
  fi
  if _bool_true "$ENABLE_NGINX"; then
    if ! apt-get install -y -qq nginx; then
      error "$(t app.cyberstrikeai.error.nginx_deps_install)"
    fi
  fi
  success "$(t app.cyberstrikeai.success.deps)"
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
      warn "$(t app.cyberstrikeai.warn.go_old "$ver")"
    fi
  fi
  if ! $need_install; then
    success "$(t app.cyberstrikeai.success.go_ready "$(go version)")"
    return 0
  fi
  step "$(t app.cyberstrikeai.step.install_go)"
  if ! apt-get install -y -qq golang-go; then
    warn "$(t app.cyberstrikeai.warn.go_repo_install_failed)"
  fi
  if command -v go >/dev/null 2>&1; then
    local ver major minor
    ver=$(go version | awk '{print $3}' | sed 's/^go//')
    major="${ver%%.*}"
    minor="${ver#*.}"; minor="${minor%%.*}"
    if [[ "$major" -gt 1 || ( "$major" -eq 1 && "$minor" -ge 21 ) ]]; then
      success "$(t app.cyberstrikeai.success.go_installed "$(go version)")"
      return 0
    fi
    warn "$(t app.cyberstrikeai.warn.go_repo_old "$ver")"
  fi
  local arch go_arch latest_json version tarball expected_sha url tmp extract_dir old_go_backup
  arch=$(uname -m)
  case "$arch" in
    x86_64) go_arch="amd64" ;;
    aarch64|arm64) go_arch="arm64" ;;
    *) error "$(t app.cyberstrikeai.error.go_arch "$arch")" ;;
  esac
  latest_json=$(curl -fsSL --max-time 20 "https://go.dev/dl/?mode=json" 2>/dev/null) \
    || error "$(t app.cyberstrikeai.error.go_query)"
  version=$(printf '%s\n' "$latest_json" | grep -oE '"version"[[:space:]]*:[[:space:]]*"go[0-9]+\.[0-9]+(\.[0-9]+)?"' | head -1 | sed 's/.*"\(go[^"]*\)".*/\1/' || true)
  [[ -n "$version" ]] || error "$(t app.cyberstrikeai.error.go_parse)"
  tarball="${version}.linux-${go_arch}.tar.gz"
  expected_sha=$(go_release_sha256 "$latest_json" "$tarball" || true)
  url="https://go.dev/dl/${tarball}"
  if ! tmp=$(mktemp); then
    error "$(t app.cyberstrikeai.error.go_query)"
  fi
  info "$(t app.cyberstrikeai.info.download "$url")"
  if ! curl -fL --retry 3 --connect-timeout 15 -o "$tmp" "$url"; then
    rm -f "$tmp"
    error "$(t app.cyberstrikeai.error.go_query)"
  fi
  if [[ ! -s "$tmp" ]]; then
    rm -f "$tmp"
    error "$(t app.cyberstrikeai.error.go_empty)"
  fi
  verify_go_archive_checksum "$tmp" "$expected_sha" "$tarball"
  if ! extract_dir=$(mktemp -d /usr/local/go.extract.XXXXXX); then
    rm -f "$tmp"
    error "$(t app.cyberstrikeai.error.go_extract)"
  fi
  if ! tar -C "$extract_dir" -xzf "$tmp" || [[ ! -d "$extract_dir/go" ]]; then
    rm -f "$tmp"
    rm -rf "$extract_dir"
    error "$(t app.cyberstrikeai.error.go_extract)"
  fi
  rm -f "$tmp"
  old_go_backup=""
  if [[ -e /usr/local/go ]]; then
    if ! old_go_backup=$(mktemp -d /usr/local/go.previous.XXXXXX); then
      rm -rf "$extract_dir"
      error "$(t app.cyberstrikeai.error.go_failed)"
    fi
    if ! rmdir "$old_go_backup"; then
      rm -rf "$extract_dir" "$old_go_backup"
      error "$(t app.cyberstrikeai.error.go_failed)"
    fi
    if ! mv /usr/local/go "$old_go_backup"; then
      rm -rf "$extract_dir"
      error "$(t app.cyberstrikeai.error.go_failed)"
    fi
  fi
  if ! mv "$extract_dir/go" /usr/local/go; then
    if [[ -n "$old_go_backup" && -e "$old_go_backup" && ! -e /usr/local/go ]]; then
      if ! restore_old_go_toolchain "$old_go_backup"; then
        warn "$(t app.cyberstrikeai.warn.go_restore_failed)"
      fi
    fi
    rm -rf "$extract_dir"
    error "$(t app.cyberstrikeai.error.go_failed)"
  fi
  rm -rf "$extract_dir"
  if [[ -n "$old_go_backup" ]]; then
    rm -rf "$old_go_backup"
  fi
  write_tool_symlink /usr/local/go/bin/go /usr/local/bin/go \
    || error "$(t app.cyberstrikeai.error.go_failed)"
  write_tool_symlink /usr/local/go/bin/gofmt /usr/local/bin/gofmt \
    || error "$(t app.cyberstrikeai.error.go_failed)"
  hash -r 2>/dev/null || true
  command -v go >/dev/null 2>&1 || error "$(t app.cyberstrikeai.error.go_failed)"
  success "$(t app.cyberstrikeai.success.go_installed "$(go version)")"
}
ensure_service_user() {
  if ! id "$SERVICE_USER" >/dev/null 2>&1; then
    if ! useradd --system --home "$INSTALL_DIR" --shell /usr/sbin/nologin "$SERVICE_USER"; then
      error "$(t app.cyberstrikeai.error.user_create "$SERVICE_USER")"
    fi
    success "$(t app.cyberstrikeai.success.user_created "$SERVICE_USER")"
  fi
}
sync_repo_branch() {
  if ! git -C "$INSTALL_DIR" fetch --prune origin "$GITHUB_BRANCH"; then
    error "$(t app.cyberstrikeai.error.repo_fetch "$GITHUB_BRANCH" "$INSTALL_DIR" "$INSTALL_DIR" "$GITHUB_BRANCH")"
  fi
  if ! git -C "$INSTALL_DIR" checkout -q "$GITHUB_BRANCH"; then
    error "$(t app.cyberstrikeai.error.repo_checkout "$INSTALL_DIR" "$GITHUB_BRANCH" "$INSTALL_DIR" "$GITHUB_BRANCH")"
  fi
  if ! git -C "$INSTALL_DIR" pull --ff-only origin "$GITHUB_BRANCH"; then
    error "$(t app.cyberstrikeai.error.repo_pull "$INSTALL_DIR" "$GITHUB_BRANCH" "$INSTALL_DIR" "$GITHUB_BRANCH")"
  fi
}
clone_or_update_repo() {
  step "$(t app.cyberstrikeai.step.fetch_source)"
  if ! mkdir -p "$(dirname "$INSTALL_DIR")"; then
    error "$(t app.cyberstrikeai.error.source_parent_dir "$INSTALL_DIR")"
  fi
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    info "$(t app.cyberstrikeai.info.repo_fetch "$GITHUB_BRANCH")"
    sync_repo_branch
  elif [[ -d "$INSTALL_DIR" && -n "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]]; then
    error "$(t app.cyberstrikeai.error.nonempty_dir "$INSTALL_DIR")"
  else
    safe_rm_dir "$INSTALL_DIR" "INSTALL_DIR"
    if ! git clone --depth 1 --branch "$GITHUB_BRANCH" "https://github.com/${GITHUB_REPO}.git" "$INSTALL_DIR"; then
      safe_rm_dir "$INSTALL_DIR" "INSTALL_DIR"
      error "$(t app.cyberstrikeai.error.repo_clone "$GITHUB_REPO" "$INSTALL_DIR" "$GITHUB_BRANCH" "$GITHUB_REPO" "$INSTALL_DIR")"
    fi
  fi
  success "$(t app.cyberstrikeai.success.source_ready "$INSTALL_DIR")"
}
patch_config_port_and_paths() {
  [[ -f "$CONFIG_FILE" ]] || error "$(t app.cyberstrikeai.error.config_missing "$CONFIG_FILE")"
  local backup
  backup="${CONFIG_FILE}.bak.$(date +%Y%m%d_%H%M%S)"
  write_backup_file "$CONFIG_FILE" "$backup" \
    || error "$(t app.cyberstrikeai.error.backup_write "$backup")"
  python3 - "$CONFIG_FILE" "$PORT" "$LOG_DIR/cyberstrike-ai.log" "$CSAI_HTTPS" <<'PY'
import os
from pathlib import Path
import re
import sys
import tempfile

path = Path(sys.argv[1])
port = sys.argv[2]
log_file = sys.argv[3]
https_enabled = sys.argv[4].strip().lower() in {"1", "true", "yes", "y", "on"}
text = path.read_text(encoding="utf-8")
file_stat = path.stat()

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

tmp_path = None
try:
    with tempfile.NamedTemporaryFile(
        "w",
        encoding="utf-8",
        dir=str(path.parent),
        prefix=f".{path.name}.tmp.",
        delete=False,
    ) as handle:
        handle.write(text)
        handle.flush()
        os.fsync(handle.fileno())
        tmp_path = handle.name
    os.chmod(tmp_path, file_stat.st_mode & 0o777)
    if hasattr(os, "chown"):
        os.chown(tmp_path, file_stat.st_uid, file_stat.st_gid)
    os.replace(tmp_path, path)
except Exception:
    if tmp_path:
        Path(tmp_path).unlink(missing_ok=True)
    raise
PY
  success "$(t app.cyberstrikeai.success.config_adjusted "$PORT")"
}
setup_python_env() {
  step "$(t app.cyberstrikeai.step.python_env)"
  if ! cd "$INSTALL_DIR"; then
    error "$(t app.cyberstrikeai.error.install_dir_missing "$INSTALL_DIR")"
  fi
  if [[ ! -d "$VENV_DIR" ]]; then
    if ! python3 -m venv "$VENV_DIR"; then
      error "$(t app.cyberstrikeai.error.python_venv "$VENV_DIR")"
    fi
  fi
  if ! source "$VENV_DIR/bin/activate"; then
    error "$(t app.cyberstrikeai.error.python_activate "$VENV_DIR")"
  fi
  if ! python -m pip install --index-url "$PIP_INDEX_URL" --upgrade pip >/dev/null 2>&1; then
    warn "$(t app.cyberstrikeai.warn.pip_upgrade)"
  fi
  if [[ -f requirements.txt ]]; then
    local pip_log
    if ! pip_log=$(mktemp); then
      warn "$(t app.cyberstrikeai.warn.python_requirements)"
      return 0
    fi
    if python -m pip install --index-url "$PIP_INDEX_URL" -r requirements.txt >"$pip_log" 2>&1; then
      success "$(t app.cyberstrikeai.success.python_requirements)"
    else
      warn "$(t app.cyberstrikeai.warn.python_requirements)"
      tail -n 20 "$pip_log" | sed 's/^/  /' >&2 || true
    fi
    rm -f "$pip_log"
  else
    warn "$(t app.cyberstrikeai.warn.requirements_missing)"
  fi
}
build_binary() {
  step "$(t app.cyberstrikeai.step.build)"
  if ! cd "$INSTALL_DIR"; then
    error "$(t app.cyberstrikeai.error.install_dir_missing "$INSTALL_DIR")"
  fi
  export GOPROXY="$GOPROXY"
  if ! go mod download; then
    error "$(t app.cyberstrikeai.error.go_modules "$INSTALL_DIR")"
  fi
  local tmp_bin
  if ! tmp_bin=$(mktemp "${BIN_PATH}.tmp.XXXXXX"); then
    error "$(t app.cyberstrikeai.error.binary_build)"
  fi
  if ! go build -trimpath -ldflags="-s -w" -o "$tmp_bin" cmd/server/main.go; then
    if ! rm -f "$tmp_bin"; then
      warn "$(t app.cyberstrikeai.warn.tmp_binary_cleanup_failed "$tmp_bin")"
    fi
    error "$(t app.cyberstrikeai.error.binary_build)"
  fi
  if [[ ! -s "$tmp_bin" ]]; then
    if ! rm -f "$tmp_bin"; then
      warn "$(t app.cyberstrikeai.warn.tmp_binary_cleanup_failed "$tmp_bin")"
    fi
    error "$(t app.cyberstrikeai.error.binary_empty)"
  fi
  if ! chmod 0755 "$tmp_bin"; then
    if ! rm -f "$tmp_bin"; then
      warn "$(t app.cyberstrikeai.warn.tmp_binary_cleanup_failed "$tmp_bin")"
    fi
    error "$(t app.cyberstrikeai.error.binary_build)"
  fi
  if ! mv "$tmp_bin" "$BIN_PATH"; then
    if ! rm -f "$tmp_bin"; then
      warn "$(t app.cyberstrikeai.warn.tmp_binary_cleanup_failed "$tmp_bin")"
    fi
    error "$(t app.cyberstrikeai.error.binary_build)"
  fi
  success "$(t app.cyberstrikeai.success.binary_built "$BIN_PATH")"
}
restore_update_backup() {
  local bin_backup="$1" config_backup="$2"
  local bin_restore_tmp config_restore_tmp
  [[ -f "$bin_backup" ]] || return 1
  if ! bin_restore_tmp=$(mktemp "${BIN_PATH}.restore.XXXXXX"); then
    return 1
  fi
  if ! cp "$bin_backup" "$bin_restore_tmp" \
      || ! chmod 0755 "$bin_restore_tmp" \
      || ! chown "${SERVICE_USER}:${SERVICE_USER}" "$bin_restore_tmp" \
      || ! mv "$bin_restore_tmp" "$BIN_PATH"; then
    rm -f "$bin_restore_tmp"
    return 1
  fi
  if [[ -f "$config_backup" ]]; then
    if ! config_restore_tmp=$(mktemp "${CONFIG_FILE}.restore.XXXXXX"); then
      return 1
    fi
    if ! cp "$config_backup" "$config_restore_tmp" \
        || ! chown "${SERVICE_USER}:${SERVICE_USER}" "$config_restore_tmp" \
        || ! mv "$config_restore_tmp" "$CONFIG_FILE"; then
      rm -f "$config_restore_tmp"
      return 1
    fi
  fi
}
install_runtime_dirs() {
  step "$(t app.cyberstrikeai.step.runtime_dirs)"
  require_safe_path "INSTALL_DIR" "$INSTALL_DIR"
  require_safe_path "LOG_DIR" "$LOG_DIR"
  require_safe_path "BACKUP_DIR" "$BACKUP_DIR"
  if ! mkdir -p "$LOG_DIR" "$INSTALL_DIR/data" "$INSTALL_DIR/tmp" "$BACKUP_DIR"; then
    error "$(t app.cyberstrikeai.error.runtime_dirs "$INSTALL_DIR" "$BACKUP_DIR")"
  fi
  if ! chown -R "${SERVICE_USER}:${SERVICE_USER}" "$INSTALL_DIR" "$BACKUP_DIR"; then
    error "$(t app.cyberstrikeai.error.runtime_dirs "$INSTALL_DIR" "$BACKUP_DIR")"
  fi
  if ! chmod 750 "$INSTALL_DIR" "$BACKUP_DIR"; then
    error "$(t app.cyberstrikeai.error.runtime_dirs "$INSTALL_DIR" "$BACKUP_DIR")"
  fi
  if ! chmod 750 "$LOG_DIR" "$INSTALL_DIR/data" "$INSTALL_DIR/tmp"; then
    error "$(t app.cyberstrikeai.error.runtime_dirs "$INSTALL_DIR" "$BACKUP_DIR")"
  fi
  success "$(t app.cyberstrikeai.success.runtime_dirs)"
}
write_systemd_unit() {
  step "$(t app.cyberstrikeai.step.systemd)"
  local https_env="false"
  _bool_true "$CSAI_HTTPS" && https_env="true"
  local unit_path="/etc/systemd/system/${SERVICE_NAME}.service"
  if ! systemd_write_unit "$unit_path" <<SERVICE
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
  then
    error "$(t app.cyberstrikeai.error.systemd "$unit_path")"
  fi
  if ! systemctl daemon-reload; then
    error "$(t app.cyberstrikeai.error.systemd_reload "$SERVICE_NAME")"
  fi
  if ! systemctl enable "$SERVICE_NAME" --quiet; then
    warn "$(t app.cyberstrikeai.warn.service_enable_failed "$SERVICE_NAME" "$SERVICE_NAME")"
  fi
  success "$(t app.cyberstrikeai.success.systemd "$SERVICE_NAME")"
}
write_nginx_config() {
  _bool_true "$ENABLE_NGINX" || return 0
  step "$(t app.cyberstrikeai.step.nginx)"
  local server_name="_"
  [[ -n "$CSAI_DOMAIN" ]] && server_name="$CSAI_DOMAIN"
  local upstream_scheme="http"
  _bool_true "$CSAI_HTTPS" && upstream_scheme="https"
  if ! mkdir -p "$(dirname "$NGINX_CONF")" "$(dirname "$NGINX_LINK")"; then
    error "$(t app.cyberstrikeai.error.nginx_dirs "$NGINX_CONF")"
  fi
  app_write_nginx_config_file "$NGINX_CONF" "app.cyberstrikeai.error.nginx" <<NGINX
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
  app_write_nginx_site_link "$NGINX_CONF" "$NGINX_LINK" "app.cyberstrikeai.error.nginx"
  if ! nginx -t; then
    error "$(t app.cyberstrikeai.error.nginx_test)"
  fi
  if ! systemctl enable nginx --quiet; then
    warn "$(t app.cyberstrikeai.warn.service_enable_failed "nginx" "nginx")"
  fi
  if systemctl is-active --quiet nginx; then
    if ! systemctl reload nginx; then
      if ! systemctl restart nginx; then
        error "$(t app.cyberstrikeai.error.nginx_start)"
      fi
    fi
  elif ! systemctl restart nginx; then
    error "$(t app.cyberstrikeai.error.nginx_start)"
  fi
  if ! wait_for_service nginx 10; then
    error "$(t app.cyberstrikeai.error.nginx_start)"
  fi
  success "$(t app.cyberstrikeai.success.nginx)"
}
open_firewall_ports() {
  _bool_true "$OPEN_FIREWALL" || return 0
  step "$(t app.cyberstrikeai.step.firewall)"
  local port_to_open="$PORT"
  _bool_true "$ENABLE_NGINX" && port_to_open="$PUBLIC_PORT"
  app_configure_firewall "$port_to_open" "app.cyberstrikeai" "CyberStrikeAI"
}
write_backup_script() {
  local install_dir_literal config_file_literal backup_dir_literal keep_days_literal service_name_literal log_file_literal
  printf -v install_dir_literal '%q' "$INSTALL_DIR"
  printf -v config_file_literal '%q' "$CONFIG_FILE"
  printf -v backup_dir_literal '%q' "$BACKUP_DIR"
  printf -v keep_days_literal '%q' "$BACKUP_KEEP_DAYS"
  printf -v service_name_literal '%q' "$SERVICE_NAME"
  printf -v log_file_literal '%q' "${LOG_DIR}/backup.log"
  local msg_install_missing msg_backup_dir_failed msg_sqlite_integrity msg_backup_created msg_remove_failed
  msg_install_missing="$(t app.cyberstrikeai.backup.error.install_missing '%s')"
  msg_backup_dir_failed="$(t app.cyberstrikeai.backup.error.backup_dir_create '%s')"
  msg_sqlite_integrity="$(t app.cyberstrikeai.backup.warn.sqlite_integrity '%s' '%s')"
  msg_backup_created="$(t app.cyberstrikeai.backup.ok.created '%s')"
  msg_remove_failed="$(t app.cyberstrikeai.backup.warn.remove_failed '%s')"
  local backup_tmp
  if ! backup_tmp=$(mktemp "${BACKUP_SCRIPT}.XXXXXX"); then
    error "$(t app.cyberstrikeai.error.backup_script)"
  fi
  if ! cat > "$backup_tmp" <<BACKUP
#!/usr/bin/env bash
set -euo pipefail
umask 077

INSTALL_DIR=${install_dir_literal}
CONFIG_FILE=${config_file_literal}
BACKUP_DIR=${backup_dir_literal}
KEEP_DAYS=${keep_days_literal}
[[ "\$KEEP_DAYS" =~ ^[0-9]+$ ]] || KEEP_DAYS=0
SERVICE_NAME=${service_name_literal}
LOG_FILE=${log_file_literal}
MSG_INSTALL_MISSING="${msg_install_missing}"
MSG_BACKUP_DIR_FAILED="${msg_backup_dir_failed}"
MSG_SQLITE_INTEGRITY="${msg_sqlite_integrity}"
MSG_BACKUP_CREATED="${msg_backup_created}"
MSG_REMOVE_FAILED="${msg_remove_failed}"

_log() { echo "\$(date '+%F %T') \$*" >> "\$LOG_FILE"; }

if ! mkdir -p "\$BACKUP_DIR"; then
  printf "\$(date '+%F %T') [ERROR] %s\n" "\$(printf "\$MSG_BACKUP_DIR_FAILED" "\$BACKUP_DIR")" >&2
  exit 1
fi
if [[ ! -d "\$INSTALL_DIR" ]]; then
  _log "[ERROR] \$(printf "\$MSG_INSTALL_MISSING" "\$INSTALL_DIR")"
  printf "\$(date '+%F %T') [ERROR] %s\n" "\$(printf "\$MSG_INSTALL_MISSING" "\$INSTALL_DIR")" >&2
  exit 1
fi

if command -v sqlite3 >/dev/null 2>&1; then
  while IFS= read -r -d '' db; do
    sqlite3 "\$db" "PRAGMA wal_checkpoint(TRUNCATE);" >/dev/null 2>&1 || true
    integrity=\$(sqlite3 "\$db" "PRAGMA integrity_check;" 2>/dev/null || echo "error")
    if [[ "\$integrity" != "ok" ]]; then
      _log "[WARN] \$(printf "\$MSG_SQLITE_INTEGRITY" "\$db" "\$integrity")"
      printf "\$(date '+%F %T') [WARN] %s\n" "\$(printf "\$MSG_SQLITE_INTEGRITY" "\$db" "\$integrity")" >&2
    fi
  done < <(find "\$INSTALL_DIR/data" -maxdepth 1 -name "*.db" -type f -print0 2>/dev/null)
fi

ts=\$(date +%Y%m%d_%H%M%S)
archive="\$BACKUP_DIR/cyberstrike-ai_\${ts}.tar.gz"
tmp="\${archive}.tmp"

if tar -czf "\$tmp" \
  --exclude=".git" \
  --exclude="venv" \
  --exclude="cyberstrike-ai" \
  --exclude="*.tmp" \
  --exclude="logs/*.log" \
  -C "\$(dirname "\$INSTALL_DIR")" "\$(basename "\$INSTALL_DIR")"; then
  if ! mv "\$tmp" "\$archive"; then
    rm -f "\$tmp"
    exit 1
  fi
else
  rm -f "\$tmp"
  exit 1
fi

if [[ "\$KEEP_DAYS" -gt 0 ]]; then
  while IFS= read -r -d '' old_backup; do
    if ! rm -f "\$old_backup"; then
      _log "[WARN] \$(printf "\$MSG_REMOVE_FAILED" "\$old_backup")"
    fi
  done < <(find "\$BACKUP_DIR" -maxdepth 1 -name "cyberstrike-ai_*.tar.gz" -mtime "+\$KEEP_DAYS" -type f -print0 2>/dev/null)
fi

_log "[OK] \$(printf "\$MSG_BACKUP_CREATED" "\$archive")"
printf "\$(date '+%F %T') [OK] %s\n" "\$(printf "\$MSG_BACKUP_CREATED" "\$archive")"
BACKUP
  then
    rm -f "$backup_tmp"
    error "$(t app.cyberstrikeai.error.backup_script "$BACKUP_SCRIPT")"
  fi
  if ! chmod 750 "$backup_tmp" \
      || ! chown root:root "$backup_tmp" \
      || ! mv "$backup_tmp" "$BACKUP_SCRIPT"; then
    rm -f "$backup_tmp"
    error "$(t app.cyberstrikeai.error.backup_script "$BACKUP_SCRIPT")"
  fi
  local cron_tmp
  if ! cron_tmp=$(mktemp "${CRON_FILE}.XXXXXX"); then
    error "$(t app.cyberstrikeai.error.cron)"
  fi
  if ! cat > "$cron_tmp" <<CRON
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
30 3 * * * root ${BACKUP_SCRIPT} >> ${LOG_DIR}/backup.log 2>&1
CRON
  then
    rm -f "$cron_tmp"
    error "$(t app.cyberstrikeai.error.cron "$CRON_FILE")"
  fi
  if ! chmod 644 "$cron_tmp" \
      || ! chown root:root "$cron_tmp" \
      || ! mv "$cron_tmp" "$CRON_FILE"; then
    rm -f "$cron_tmp"
    error "$(t app.cyberstrikeai.error.cron "$CRON_FILE")"
  fi
}
start_service() {
  step "$(t app.cyberstrikeai.step.start)"
  app_check_port_conflict "$PORT"
  if systemctl restart "$SERVICE_NAME" && wait_for_service "$SERVICE_NAME" 35; then
    success "$(t app.cyberstrikeai.success.running "$SERVICE_NAME")"
  else
    journalctl -u "$SERVICE_NAME" -n 40 --no-pager >&2 || true
    error "$(t app.cyberstrikeai.error.start_failed "$SERVICE_NAME")"
  fi
}
health_check() {
  step "$(t app.cyberstrikeai.step.health)"
  local scheme="http"
  _bool_true "$CSAI_HTTPS" && scheme="https"
  local code backend_url public_url
  local health_pending=0
  backend_url="${scheme}://127.0.0.1:${PORT}/"
  code=$(curl -k -o /dev/null -s -w "%{http_code}" --max-time 8 "$backend_url" || echo "000")
  if [[ "$code" =~ ^(200|301|302|308)$ ]]; then
    success "$(t app.cyberstrikeai.success.backend_health "$backend_url" "$code")"
  else
    warn "$(t app.cyberstrikeai.warn.backend_health "$code")"
    health_pending=1
  fi
  if _bool_true "$ENABLE_NGINX"; then
    public_url="http://127.0.0.1:${PUBLIC_PORT}/"
    code=$(curl -H "Host: ${CSAI_DOMAIN:-localhost}" -o /dev/null -s -w "%{http_code}" --max-time 8 "$public_url" || echo "000")
    if [[ "$code" =~ ^(200|301|302|308)$ ]]; then
      success "$(t app.cyberstrikeai.success.nginx_health "$public_url" "$code")"
    else
      warn "$(t app.cyberstrikeai.warn.nginx_health "$code")"
      health_pending=1
    fi
  fi
  [[ "$health_pending" -eq 0 ]]
}
print_summary() {
  local summary_state="${1:-ready}"
  local ip
  ip=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
  ip="${ip:-YOUR_SERVER_IP}"
  local backend_scheme="http"
  _bool_true "$CSAI_HTTPS" && backend_scheme="https"
  echo ""
  if [[ "$summary_state" == "pending" ]]; then
    echo -e "${BOLD}${GREEN}$(t app.cyberstrikeai.summary.title_pending)${NC}"
  else
    echo -e "${BOLD}${GREEN}$(t app.cyberstrikeai.summary.title_ready)${NC}"
  fi
  printf '  %-12s %s\n' "$(t app.cyberstrikeai.summary.service):" "$SERVICE_NAME"
  printf '  %-12s %s\n' "$(t app.cyberstrikeai.summary.install_dir):" "$INSTALL_DIR"
  printf '  %-12s %s\n' "$(t app.cyberstrikeai.summary.config):" "$CONFIG_FILE"
  printf '  %-12s %s\n' "$(t app.cyberstrikeai.summary.logs):" "$LOG_DIR"
  printf '  %-12s %s\n' "$(t app.cyberstrikeai.summary.backups):" "$BACKUP_DIR"
  printf '  %-12s %s\n' "$(t app.cyberstrikeai.summary.backend):" "${backend_scheme}://127.0.0.1:${PORT}/"
  if _bool_true "$ENABLE_NGINX"; then
    if [[ -n "$CSAI_DOMAIN" ]]; then
      printf '  %-12s %s\n' "$(t app.cyberstrikeai.summary.public):" "http://${CSAI_DOMAIN}:${PUBLIC_PORT}/"
    elif [[ -n "${ip:-}" ]]; then
      printf '  %-12s %s\n' "$(t app.cyberstrikeai.summary.public):" "http://${ip}:${PUBLIC_PORT}/"
    else
      printf '  %-12s %s\n' "$(t app.cyberstrikeai.summary.public):" "http://<server-ip>:${PUBLIC_PORT}/"
    fi
  fi
  echo ""
  echo "$(t app.cyberstrikeai.summary.commands)"
  echo "  systemctl status ${SERVICE_NAME} --no-pager"
  echo "  journalctl -u ${SERVICE_NAME} -n 80 --no-pager"
  echo "  bash $0 status"
  echo ""
  warn "$(t app.cyberstrikeai.warn.configure_model "$CONFIG_FILE")"
  warn "$(t app.cyberstrikeai.warn.authorized_only)"
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
  patch_config_port_and_paths
  setup_python_env
  build_binary
  install_runtime_dirs
  write_systemd_unit
  write_nginx_config
  app_write_logrotate "$LOGROTATE_FILE" "$LOG_DIR" "app.cyberstrikeai.error.logrotate" "app.cyberstrikeai.success.logrotate"
  write_backup_script
  open_firewall_ports
  app_save_config
  start_service
  local _install_summary_state="ready"
  if ! health_check; then
    _install_summary_state="pending"
  fi
  print_summary "$_install_summary_state"
  release_lock
}
do_backup() {
  show_banner
  preflight_check "backup"
  app_load_config _CSAI_DERIVE_PATHS
  acquire_lock
  step "$(t app.cyberstrikeai.step.manual_backup)"
  "$BACKUP_SCRIPT"
  info "$(t app.cyberstrikeai.info.latest_backups)"
  local _backup_entry file
  while IFS= read -r -d '' _backup_entry; do
    file="${_backup_entry#* }"
    [[ -n "$file" ]] || continue
    printf '  %-70s %s\n' "$(basename "$file")" "$(du -sh "$file" 2>/dev/null | awk '{print $1}' || t status.unknown)" >&2
  done < <(find "$BACKUP_DIR" -maxdepth 1 -name "cyberstrike-ai_*.tar.gz" -printf '%T@ %p\0' 2>/dev/null \
    | sort -z -rn | head -z -n 10) || true
  release_lock
}
do_update() {
  show_banner
  preflight_check "update"
  app_load_config _CSAI_DERIVE_PATHS
  acquire_lock
  check_connectivity
  [[ -d "$INSTALL_DIR/.git" ]] || error "$(t app.cyberstrikeai.error.not_git "$INSTALL_DIR")"
  step "$(t app.cyberstrikeai.step.preupdate_backup)"
  if [[ -x "$BACKUP_SCRIPT" ]]; then
    if ! "$BACKUP_SCRIPT"; then
      warn "$(t app.cyberstrikeai.warn.preupdate_backup)"
    fi
  fi
  local old_rev new_rev bin_bak config_bak service_was_active=false
  old_rev=$(git -C "$INSTALL_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
  systemctl is-active --quiet "$SERVICE_NAME" && service_was_active=true
  bin_bak="${BIN_PATH}.bak.$(date +%Y%m%d_%H%M%S)"
  config_bak="${CONFIG_FILE}.preupdate.$(date +%Y%m%d_%H%M%S)"
  write_backup_file "$BIN_PATH" "$bin_bak" \
    || error "$(t app.cyberstrikeai.error.backup_write "$bin_bak")"
  write_backup_file "$CONFIG_FILE" "$config_bak" \
    || error "$(t app.cyberstrikeai.error.backup_write "$config_bak")"
  step "$(t app.cyberstrikeai.step.update_source)"
  sync_repo_branch
  new_rev=$(git -C "$INSTALL_DIR" rev-parse --short HEAD 2>/dev/null || echo "unknown")
  setup_python_env
  patch_config_port_and_paths
  build_binary
  if ! chown -R "${SERVICE_USER}:${SERVICE_USER}" "$INSTALL_DIR"; then
    error "$(t app.cyberstrikeai.error.install_dir_owner "$INSTALL_DIR" "$SERVICE_USER")"
  fi
  if $service_was_active; then
    step "$(t app.cyberstrikeai.step.restart_updated)"
    if systemctl restart "$SERVICE_NAME" && wait_for_service "$SERVICE_NAME" 35; then
      success "$(t app.cyberstrikeai.success.update_complete "$old_rev" "$new_rev")"
      if ! health_check; then
        :
      fi
    else
      warn "$(t app.cyberstrikeai.warn.update_start_failed)"
      if ! systemctl stop "$SERVICE_NAME" 2>/dev/null; then
        error "$(t app.cyberstrikeai.error.rollback_stop_failed "$SERVICE_NAME" "$bin_bak" "$config_bak" "$SERVICE_NAME")"
      fi
      if restore_update_backup "$bin_bak" "$config_bak"; then
        if systemctl start "$SERVICE_NAME"; then
          if wait_for_service "$SERVICE_NAME" 35; then
            error "$(t app.cyberstrikeai.error.update_rollback_ok "$SERVICE_NAME")"
          else
            error "$(t app.cyberstrikeai.error.update_rollback_failed "$SERVICE_NAME")"
          fi
        else
          error "$(t app.cyberstrikeai.error.update_rollback_failed "$SERVICE_NAME")"
        fi
      else
        error "$(t app.cyberstrikeai.error.update_rollback_failed "$SERVICE_NAME")"
      fi
    fi
  else
    success "$(t app.cyberstrikeai.success.update_inactive "$old_rev" "$new_rev")"
  fi
  local _cleaned_old=0 _old_bak
  while IFS= read -r -d '' _old_bak; do
    if rm -f "$_old_bak"; then
      _cleaned_old=$(( _cleaned_old + 1 ))
    else
      warn "$(t app.cyberstrikeai.warn.cleanup_old_binary_failed "$_old_bak")"
    fi
  done < <(
    find "$INSTALL_DIR" -maxdepth 1 -name "${BIN_NAME}.bak.*" -type f -printf '%T@ %p\0' 2>/dev/null \
      | sort -z -rn | tail -z -n +4 | cut -z -d ' ' -f 2-
  )
  if [[ $_cleaned_old -gt 0 ]]; then
    info "$(t app.cyberstrikeai.info.cleaned_old_binaries "$_cleaned_old")"
  fi
  release_lock
}
do_status() {
  show_banner
  preflight_check "status"
  app_load_config _CSAI_DERIVE_PATHS
  [[ $EUID -ne 0 ]] && warn "$(t app.cyberstrikeai.warn.non_root_status "$0")"
  step "$(t app.cyberstrikeai.step.service_status)"
  if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
    echo -e "  ${GREEN}[+]${NC} ${SERVICE_NAME}: $(t app.cyberstrikeai.status.running)"
  elif systemctl is-failed --quiet "$SERVICE_NAME" 2>/dev/null; then
    echo -e "  ${RED}[x]${NC} ${SERVICE_NAME}: $(t app.cyberstrikeai.status.failed)"
  else
    echo -e "  ${YELLOW}[!]${NC} ${SERVICE_NAME}: $(t app.cyberstrikeai.status.inactive)"
  fi
  systemctl status "$SERVICE_NAME" --no-pager -l 2>/dev/null | head -16 | sed 's/^/  /' >&2 || true
  step "$(t app.cyberstrikeai.step.version_paths)"
  if [[ -d "$INSTALL_DIR/.git" ]]; then
    printf '  %-12s %s\n' "$(t app.cyberstrikeai.status.git_revision):" "$(git -C "$INSTALL_DIR" rev-parse --short HEAD 2>/dev/null || t status.unknown)"
    printf '  %-12s %s\n' "$(t app.cyberstrikeai.status.git_branch):" "$(git -C "$INSTALL_DIR" rev-parse --abbrev-ref HEAD 2>/dev/null || t status.unknown)"
  fi
  if [[ -x "$BIN_PATH" ]]; then
    printf '  %-12s %s (%s)\n' "$(t app.cyberstrikeai.status.binary):" "$BIN_PATH" "$(du -sh "$BIN_PATH" 2>/dev/null | awk '{print $1}' || t status.unknown)"
  else
    printf '  %-12s %s\n' "$(t app.cyberstrikeai.status.binary):" "$(t app.cyberstrikeai.status.missing)"
  fi
  printf '  %-12s %s\n' "$(t app.cyberstrikeai.summary.config):" "$CONFIG_FILE"
  printf '  %-12s %s\n' "$(t app.cyberstrikeai.summary.logs):" "$LOG_DIR"
  printf '  %-12s %s\n' "$(t app.cyberstrikeai.summary.backups):" "$BACKUP_DIR"
  step "$(t app.cyberstrikeai.step.resources)"
  local pid
  pid=$(systemctl show "$SERVICE_NAME" --property=MainPID --value 2>/dev/null || echo "0")
  if [[ "$pid" != "0" && -d "/proc/$pid" ]]; then
    echo "  PID:          $pid"
    printf '  %-12s %s\n' "$(t app.cyberstrikeai.status.memory_rss):" "$(awk '/VmRSS/{printf "%.1f MB", $2/1024}' "/proc/$pid/status" 2>/dev/null || echo N/A)"
    printf '  %-12s %s%%\n' "$(t app.cyberstrikeai.status.cpu):" "$(ps -p "$pid" -o %cpu= 2>/dev/null | tr -d ' ')"
    printf '  %-12s %s\n' "$(t app.cyberstrikeai.status.uptime):" "$(ps -p "$pid" -o etime= 2>/dev/null | tr -d ' ')"
  else
    printf '  %-12s %s\n' "$(t app.cyberstrikeai.status.process):" "$(t app.cyberstrikeai.status.not_running)"
  fi
  step "$(t app.cyberstrikeai.step.health)"
  if ! health_check; then
    :
  fi
  step "$(t app.cyberstrikeai.step.nginx)"
  if _bool_true "$ENABLE_NGINX"; then
    if command -v nginx >/dev/null 2>&1; then
      systemctl is-active --quiet nginx \
        && printf '  %-12s %s\n' "$(t app.cyberstrikeai.status.nginx):" "$(t app.cyberstrikeai.status.running)" \
        || printf '  %-12s %s\n' "$(t app.cyberstrikeai.status.nginx):" "$(t app.cyberstrikeai.status.not_running)"
      [[ -f "$NGINX_CONF" ]] \
        && printf '  %-12s %s\n' "$(t app.cyberstrikeai.summary.config):" "$NGINX_CONF" \
        || printf '  %-12s %s\n' "$(t app.cyberstrikeai.summary.config):" "$(t app.cyberstrikeai.status.missing)"
      nginx -t >/dev/null 2>&1 \
        && printf '  %-12s %s\n' "$(t app.cyberstrikeai.status.syntax):" "$(t app.cyberstrikeai.status.ok)" \
        || printf '  %-12s %s\n' "$(t app.cyberstrikeai.status.syntax):" "$(t app.cyberstrikeai.status.failed)"
    else
      printf '  %-12s %s\n' "$(t app.cyberstrikeai.status.nginx):" "$(t app.cyberstrikeai.status.not_installed)"
    fi
  else
    printf '  %-12s %s\n' "$(t app.cyberstrikeai.status.nginx):" "$(t app.cyberstrikeai.status.disabled)"
  fi
  step "$(t app.cyberstrikeai.step.backups)"
  if [[ -d "$BACKUP_DIR" ]]; then
    local count size
    count=$(find "$BACKUP_DIR" -maxdepth 1 -name "cyberstrike-ai_*.tar.gz" 2>/dev/null | wc -l)
    size=$(du -sh "$BACKUP_DIR" 2>/dev/null | awk '{print $1}' || t status.unknown)
    printf '  %-12s %s (%s, %s)\n' "$(t app.cyberstrikeai.status.backup_dir):" "$BACKUP_DIR" "$size" "$(t app.cyberstrikeai.status.files "$count")"
    local _backup_entry file
    while IFS= read -r -d '' _backup_entry; do
      file="${_backup_entry#* }"
      [[ -n "$file" ]] || continue
      printf '  %-70s %s\n' "$(basename "$file")" "$(du -sh "$file" 2>/dev/null | awk '{print $1}' || t status.unknown)" >&2
    done < <(find "$BACKUP_DIR" -maxdepth 1 -name "cyberstrike-ai_*.tar.gz" -printf '%T@ %p\0' 2>/dev/null \
      | sort -z -rn | head -z -n 5) || true
  else
    printf '  %-12s %s\n' "$(t app.cyberstrikeai.status.backup_dir):" "$(t app.cyberstrikeai.status.missing)"
  fi
  echo ""
}
do_uninstall() {
  show_banner
  preflight_check "uninstall"
  app_load_config _CSAI_DERIVE_PATHS
  acquire_lock
  require_safe_path "INSTALL_DIR" "${INSTALL_DIR:-}"
  require_safe_path "BACKUP_DIR" "${BACKUP_DIR:-}"
  step "$(t app.cyberstrikeai.step.uninstall)"
  echo -e "${RED}${BOLD}"
  echo "$(t app.cyberstrikeai.uninstall.removes)"
  echo "  - $(t app.cyberstrikeai.uninstall.systemd "$SERVICE_NAME")"
  echo "  - $(t app.cyberstrikeai.uninstall.nginx "$NGINX_CONF")"
  echo "  - $(t app.cyberstrikeai.uninstall.logrotate_cron)"
  echo "  - $(t app.cyberstrikeai.uninstall.deploy_config "$CONF_FILE")"
  echo ""
  echo "$(t app.cyberstrikeai.uninstall.keep_default)"
  echo -e "${NC}"
  local confirm
  if deploy_assume_yes; then
    confirm="YES"
  else
    prompt "$(t app.cyberstrikeai.prompt.continue)"
    read -r confirm
  fi
  [[ "$confirm" == "YES" ]] || { info "$(t app.cyberstrikeai.info.cancelled)"; exit 0; }
  local del_install
  if deploy_assume_yes; then
    if deploy_env_truthy DEPLOY_DELETE_INSTALL; then
      del_install="yes"
    else
      del_install="no"
    fi
  else
    prompt "$(t app.cyberstrikeai.prompt.delete_install "$INSTALL_DIR")"
    read -r del_install
  fi
  local del_backup
  if deploy_assume_yes; then
    if deploy_env_truthy DEPLOY_DELETE_BACKUP; then
      del_backup="yes"
    else
      del_backup="no"
    fi
  else
    prompt "$(t app.cyberstrikeai.prompt.delete_backup "$BACKUP_DIR")"
    read -r del_backup
  fi
  info "$(t app.cyberstrikeai.info.stop_disable "$SERVICE_NAME")"
  if ! systemctl stop "$SERVICE_NAME" 2>/dev/null; then
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
      error "$(t app.cyberstrikeai.error.uninstall_stop_failed "$SERVICE_NAME" "$SERVICE_NAME")"
    fi
    warn "$(t app.cyberstrikeai.warn.uninstall_stop_failed "$SERVICE_NAME" "$SERVICE_NAME")"
  fi
  if ! systemctl disable "$SERVICE_NAME" 2>/dev/null; then
    warn "$(t app.cyberstrikeai.warn.uninstall_disable_failed "$SERVICE_NAME" "$SERVICE_NAME")"
  fi
  _csai_remove_file_or_error "/etc/systemd/system/${SERVICE_NAME}.service" "CSAI_SERVICE_FILE"
  if ! systemctl daemon-reload; then
    error "$(t app.cyberstrikeai.error.systemd_reload "$SERVICE_NAME")"
  fi
  success "$(t app.cyberstrikeai.success.removed_systemd)"
  _csai_remove_file_or_error "$NGINX_LINK" "NGINX_LINK"
  _csai_remove_file_or_error "$NGINX_CONF" "NGINX_CONF"
  if command -v nginx >/dev/null 2>&1; then
    if nginx -t >/dev/null 2>&1; then
      if ! systemctl reload nginx >/dev/null 2>&1; then
        nginx -t >&2 || true
        warn "$(t app.cyberstrikeai.warn.uninstall_nginx_reload_failed)"
      fi
    else
      nginx -t >&2 || true
      warn "$(t app.cyberstrikeai.warn.uninstall_nginx_reload_failed)"
    fi
  fi
  success "$(t app.cyberstrikeai.success.removed_nginx)"
  _csai_remove_file_or_error "$LOGROTATE_FILE" "LOGROTATE_FILE"
  _csai_remove_file_or_error "$CRON_FILE" "CRON_FILE"
  _csai_remove_file_or_error "$BACKUP_SCRIPT" "BACKUP_SCRIPT"
  _csai_remove_file_or_error "$CONF_FILE" "CONF_FILE"
  success "$(t app.cyberstrikeai.success.removed_configs)"
  if [[ "${del_install,,}" == "y" ]]; then
    _csai_remove_dir_or_error "$INSTALL_DIR" "INSTALL_DIR" "$(t app.cyberstrikeai.success.deleted_install "$INSTALL_DIR")"
  else
    info "$(t app.cyberstrikeai.info.kept_install "$INSTALL_DIR")"
  fi
  if [[ "${del_backup,,}" == "y" ]]; then
    _csai_remove_dir_or_error "$BACKUP_DIR" "BACKUP_DIR" "$(t app.cyberstrikeai.success.deleted_backup "$BACKUP_DIR")"
  else
    info "$(t app.cyberstrikeai.info.kept_backup "$BACKUP_DIR")"
  fi
  if [[ "${del_install,,}" == "y" ]] && id "$SERVICE_USER" >/dev/null 2>&1; then
    if userdel "$SERVICE_USER" 2>/dev/null; then
      success "$(t app.cyberstrikeai.success.deleted_user "$SERVICE_USER")"
    else
      warn "$(t app.cyberstrikeai.warn.delete_user "$SERVICE_USER")"
    fi
  fi
  echo ""
  success "$(t app.cyberstrikeai.success.uninstalled)"
  release_lock
}
