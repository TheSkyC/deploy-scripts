#!/usr/bin/env bash
set -euo pipefail
umask 077

TICKFLOW_DOMAIN="${TICKFLOW_DOMAIN:-}"
TICKFLOW_REPO="${TICKFLOW_REPO:-shy3130/tickflow-stock-panel}"
TICKFLOW_BRANCH="${TICKFLOW_BRANCH:-main}"
TICKFLOW_INSTALL_DIR="${TICKFLOW_INSTALL_DIR:-/opt/tickflow-stock-panel}"
TICKFLOW_DATA_DIR="${TICKFLOW_DATA_DIR:-${TICKFLOW_INSTALL_DIR}/data}"
TICKFLOW_ENV_FILE="${TICKFLOW_ENV_FILE:-${TICKFLOW_INSTALL_DIR}/.env}"
TICKFLOW_COMPOSE_FILE="${TICKFLOW_COMPOSE_FILE:-${TICKFLOW_INSTALL_DIR}/docker-compose.yml}"
TICKFLOW_TIERS_FILE="${TICKFLOW_TIERS_FILE:-${TICKFLOW_INSTALL_DIR}/tiers.yaml}"
TICKFLOW_SERVICE_NAME="${TICKFLOW_SERVICE_NAME:-tickflow-stock-panel}"
TICKFLOW_PORT="${TICKFLOW_PORT:-3018}"
TICKFLOW_LOG_DIR="${TICKFLOW_LOG_DIR:-${TICKFLOW_INSTALL_DIR}/logs}"
TICKFLOW_AUTH_PASSWORD="${TICKFLOW_AUTH_PASSWORD:-}"
TICKFLOW_BACKEND_EXTRAS="${TICKFLOW_BACKEND_EXTRAS:-}"

CONFIG_KEYS=(
  TICKFLOW_DOMAIN TICKFLOW_REPO TICKFLOW_BRANCH TICKFLOW_INSTALL_DIR
  TICKFLOW_DATA_DIR TICKFLOW_ENV_FILE TICKFLOW_COMPOSE_FILE TICKFLOW_TIERS_FILE
  TICKFLOW_SERVICE_NAME TICKFLOW_PORT TICKFLOW_LOG_DIR TICKFLOW_AUTH_PASSWORD
  TICKFLOW_BACKEND_EXTRAS
)

# Backward-compat: check for old-style config path.
app_conf_register_legacy "/etc/tickflow-deploy.conf"
CONF_FILE="$(app_conf_file)"
LOCK_FILE="$(app_lock_file)"

_tickflow_doctor_service_name() {
  printf '%s\n' "$TICKFLOW_SERVICE_NAME"
}
APP_DOCTOR_SERVICE_FN=_tickflow_doctor_service_name
# Central check-update adapter: TickFlow updates from a git branch, so the
# shared git-branch checker compares the local HEAD with origin. Saved
# configuration is reloaded so custom install paths are honored without
# running an app action.
_tickflow_check_update_json() {
  local conf_file
  conf_file="$(app_conf_file 2>/dev/null || true)"
  [[ -n "$conf_file" && -f "$conf_file" ]] && load_config_file "$conf_file" "${CONFIG_KEYS[@]}"
  version_check_git_branch_json "$TICKFLOW_INSTALL_DIR" "${TICKFLOW_BRANCH:-main}" "${3:-0}"
}
APP_CHECK_UPDATE_FN=_tickflow_check_update_json

_tickflow_status_backup() {
  local install_dir="${TICKFLOW_INSTALL_DIR:-}" backup_dir configured_dir
  if configured_dir="$(app_conf_trusted_value "$(app_conf_file 2>/dev/null || true)" "TICKFLOW_INSTALL_DIR")"; then
    install_dir="$configured_dir"
  fi
  if [[ -z "$install_dir" ]] || ! is_safe_path "$install_dir"; then
    printf '{"state":"unknown","last_success_at":null,"path":null,"message":"install directory is unsafe or missing"}'
    return
  fi
  backup_dir="${install_dir}-backups"
  if ! is_safe_path "$backup_dir"; then
    printf '{"state":"unknown","last_success_at":null,"path":null,"message":"backup directory is unsafe"}'
    return
  fi
  if [[ ! -d "$backup_dir" ]]; then
    printf '{"state":"missing","last_success_at":null,"path":%s,"message":"backup directory is missing"}' "$(app_json_string "$backup_dir")"
    return
  fi
  app_backup_latest_archive_json "$backup_dir" 'tickflow-data-*.tar.gz'
}
APP_STATUS_BACKUP_FN=_tickflow_status_backup

preflight_check() {
  [[ "${1:-}" == "status" || $EUID -eq 0 ]] || error "$(t error.root_required "$0" "${1:-}")"
  command -v apt-get >/dev/null 2>&1 || error "$(t app.tickflow.error.apt_only)"
  command -v systemctl >/dev/null 2>&1 || error "$(t app.tickflow.error.systemd_required)"
  case "$(uname -m)" in
    x86_64|aarch64|arm64) ;;
    *) error "$(t app.tickflow.error.arch "$(uname -m)")" ;;
  esac
  _validate_config_values
}

check_connectivity() {
  app_check_connectivity app.tickflow.error.repo_unreachable \
    "https://github.com" \
    "https://api.github.com"
}

_validate_config_values() {
  app_validate_port "$TICKFLOW_PORT" "TICKFLOW_PORT"
  app_validate_domain "TICKFLOW_DOMAIN" "$TICKFLOW_DOMAIN"
  app_validate_systemd_name "TICKFLOW_SERVICE_NAME" "$TICKFLOW_SERVICE_NAME"
  app_validate_github_repo "TICKFLOW_REPO" "$TICKFLOW_REPO"
  app_validate_git_ref "TICKFLOW_BRANCH" "$TICKFLOW_BRANCH"
  require_safe_path "TICKFLOW_INSTALL_DIR" "$TICKFLOW_INSTALL_DIR"
  require_safe_path "TICKFLOW_DATA_DIR" "$TICKFLOW_DATA_DIR"
  require_safe_path "TICKFLOW_LOG_DIR" "$TICKFLOW_LOG_DIR"
  require_safe_path "TICKFLOW_ENV_FILE" "$TICKFLOW_ENV_FILE"
  require_safe_path "TICKFLOW_COMPOSE_FILE" "$TICKFLOW_COMPOSE_FILE"
  require_safe_path "TICKFLOW_TIERS_FILE" "$TICKFLOW_TIERS_FILE"
  if [[ -n "$TICKFLOW_AUTH_PASSWORD" ]] && [[ ${#TICKFLOW_AUTH_PASSWORD} -lt 6 ]]; then
    warn "$(t app.tickflow.warn.auth_password_short)"
  fi
}

_compose_bin() {
  if docker compose version >/dev/null 2>&1; then
    echo "docker compose"
  else
    echo "docker-compose"
  fi
}

_require_compose_runtime() {
  command -v docker >/dev/null 2>&1 || error "$(t app.tickflow.error.docker_missing)"
  if ! docker compose version >/dev/null 2>&1 && ! command -v docker-compose >/dev/null 2>&1; then
    error "$(t app.tickflow.error.compose_missing)"
  fi
}

_env_value_from_file() {
  local key="$1"
  local env_file="${2:-$TICKFLOW_ENV_FILE}"
  local line value
  [[ -f "$env_file" ]] || return 1

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" == "${key}="* ]] || continue
    value="${line#*=}"
    if [[ "$value" =~ ^\"(.*)\"$ ]]; then
      value="${BASH_REMATCH[1]}"
    fi
    printf '%s' "$value"
    return 0
  done < "$env_file"

  return 1
}

_clone_or_update_repo() {
  local parent repo_dir
  parent="$(dirname "$TICKFLOW_INSTALL_DIR")"
  repo_dir="$TICKFLOW_INSTALL_DIR"
  require_safe_path "TICKFLOW_INSTALL_DIR" "$repo_dir"
  if ! mkdir -p "$parent"; then
    error "$(t app.tickflow.error.install_parent_dir "$parent")"
  fi
  if [[ -d "$repo_dir/.git" ]]; then
    info "$(t app.tickflow.info.repo_exists "$TICKFLOW_BRANCH")"
    git -C "$repo_dir" fetch --prune origin "$TICKFLOW_BRANCH" || error "$(t app.tickflow.error.repo_update "$repo_dir")"
    git -C "$repo_dir" checkout "$TICKFLOW_BRANCH" || error "$(t app.tickflow.error.repo_update "$repo_dir")"
    git -C "$repo_dir" pull --ff-only origin "$TICKFLOW_BRANCH" || error "$(t app.tickflow.error.repo_update "$repo_dir")"
  else
    if [[ -e "$repo_dir" || -L "$repo_dir" ]]; then
      error "$(t app.tickflow.error.install_dir_not_repo "$repo_dir")"
    fi
    git clone --depth 1 --branch "$TICKFLOW_BRANCH" "https://github.com/${TICKFLOW_REPO}.git" "$repo_dir" \
      || error "$(t app.tickflow.error.repo_clone "$TICKFLOW_REPO" "$repo_dir")"
  fi
  success "$(t app.tickflow.success.source_ready "$repo_dir")"
}

_ensure_data_layout() {
  if ! mkdir -p "$TICKFLOW_DATA_DIR" "$TICKFLOW_LOG_DIR"; then
    error "$(t app.tickflow.error.runtime_dirs "$TICKFLOW_DATA_DIR" "$TICKFLOW_LOG_DIR")"
  fi
  if [[ ! -f "$TICKFLOW_TIERS_FILE" ]]; then
    atomic_write_file "$TICKFLOW_TIERS_FILE" 644 <<'EOF' \
      || error "$(t app.tickflow.error.tiers_write "$TICKFLOW_TIERS_FILE")"
# Managed by deploy-scripts.
# This file is required by tickflow-stock-panel docker compose.
EOF
  fi
}

_write_env_file() {
  local tickflow_api_key=""
  local ai_provider="openai_compat"
  local ai_base_url="https://api.deepseek.com/v1"
  local ai_api_key=""
  local ai_model="deepseek-chat"
  local ai_daily_token_budget="500000"
  local log_level="INFO"
  local existing_value
  mkdir -p "$(dirname "$TICKFLOW_ENV_FILE")"
  if existing_value="$(_env_value_from_file TICKFLOW_API_KEY)"; then
    tickflow_api_key="$existing_value"
  fi
  if existing_value="$(_env_value_from_file AI_PROVIDER)"; then
    ai_provider="$existing_value"
  fi
  if existing_value="$(_env_value_from_file AI_BASE_URL)"; then
    ai_base_url="$existing_value"
  fi
  if existing_value="$(_env_value_from_file AI_API_KEY)"; then
    ai_api_key="$existing_value"
  fi
  if existing_value="$(_env_value_from_file AI_MODEL)"; then
    ai_model="$existing_value"
  fi
  if existing_value="$(_env_value_from_file AI_DAILY_TOKEN_BUDGET)"; then
    ai_daily_token_budget="$existing_value"
  fi
  if existing_value="$(_env_value_from_file LOG_LEVEL)"; then
    log_level="$existing_value"
  fi
  atomic_write_file "$TICKFLOW_ENV_FILE" 600 <<EOF \
    || error "$(t app.tickflow.error.env_write "$TICKFLOW_ENV_FILE")"
TICKFLOW_API_KEY=${tickflow_api_key}
AI_PROVIDER=${ai_provider}
AI_BASE_URL=${ai_base_url}
AI_API_KEY=${ai_api_key}
AI_MODEL=${ai_model}
AI_DAILY_TOKEN_BUDGET=${ai_daily_token_budget}
HOST=0.0.0.0
PORT=${TICKFLOW_PORT}
LOG_LEVEL=${log_level}
AUTH_PASSWORD=${TICKFLOW_AUTH_PASSWORD}
BACKEND_EXTRAS=${TICKFLOW_BACKEND_EXTRAS}
DATA_DIR=./data
EOF
}

_write_compose_file() {
  atomic_write_file "$TICKFLOW_COMPOSE_FILE" 644 <<'EOF' \
    || error "$(t app.tickflow.error.compose_write "$TICKFLOW_COMPOSE_FILE")"
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
      args:
        BACKEND_EXTRAS: ${BACKEND_EXTRAS:-}
    container_name: TickFlow_Stock_Panel
    ports:
      - "${PORT:-3018}:3018"
    env_file:
      - .env
    volumes:
      - ./data:/app/data
      - ./tiers.yaml:/app/tiers.yaml:ro
    restart: unless-stopped
EOF
}

_write_systemd_unit() {
  local unit_path="/etc/systemd/system/${TICKFLOW_SERVICE_NAME}.service"
  local compose_cmd install_dir_literal compose_file_literal
  if docker compose version >/dev/null 2>&1; then
    compose_cmd='docker compose'
  else
    compose_cmd='docker-compose'
  fi
  printf -v install_dir_literal '%q' "$TICKFLOW_INSTALL_DIR"
  printf -v compose_file_literal '%q' "$TICKFLOW_COMPOSE_FILE"
  if ! systemd_write_unit "$unit_path" <<EOF
[Unit]
Description=TickFlow Stock Panel
After=network-online.target docker.service
Wants=network-online.target docker.service

[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=${TICKFLOW_INSTALL_DIR}
ExecStart=/bin/bash -lc 'cd ${install_dir_literal} && ${compose_cmd} -f ${compose_file_literal} up -d --build'
ExecStop=/bin/bash -lc 'cd ${install_dir_literal} && ${compose_cmd} -f ${compose_file_literal} down'
ExecReload=/bin/bash -lc 'cd ${install_dir_literal} && ${compose_cmd} -f ${compose_file_literal} up -d --build'
TimeoutStartSec=0
TimeoutStopSec=120

[Install]
WantedBy=multi-user.target
EOF
  then
    error "$(t app.tickflow.error.service_write "$unit_path")"
  fi
  systemctl daemon-reload || error "$(t app.tickflow.error.service_reload "$TICKFLOW_SERVICE_NAME")"
  success "$(t app.tickflow.success.systemd "$TICKFLOW_SERVICE_NAME")"
}

_print_service_diagnostics() {
  warn "$(t app.tickflow.warn.service_diagnostics)"
  systemctl status "$TICKFLOW_SERVICE_NAME" --no-pager -l 2>/dev/null \
    | head -20 | sed 's/^/  /' >&2 || true
}

_print_status_path() {
  local label="$1" path="$2"
  if [[ -e "$path" ]]; then
    echo -e "  ${GREEN}[✓]${NC} $(t app.tickflow.status.path_ok "$label" "$path")"
  else
    echo -e "  ${YELLOW}[!]${NC} $(t app.tickflow.status.path_missing "$label" "$path")"
  fi
}

_health_check() {
  local code elapsed=0
  until code=$(curl -o /dev/null -s -w "%{http_code}" --max-time 5 "http://127.0.0.1:${TICKFLOW_PORT}/" 2>/dev/null || echo 000) \
      && [[ "$code" =~ ^(200|301|302)$ ]]; do
    sleep 1
    elapsed=$((elapsed + 1))
    [[ $elapsed -ge 20 ]] && break
  done
  if [[ "$code" =~ ^(200|301|302)$ ]]; then
    success "$(t app.tickflow.success.health "$code")"
    return 0
  fi
  warn "$(t app.tickflow.warn.health "$code")"
  return 1
}

_print_summary() {
  local state="$1"
  local internal_ip
  internal_ip="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  internal_ip="${internal_ip:-YOUR_SERVER_IP}"
  echo ""
  echo -e "${BOLD}${GREEN}"
  echo "  ╔══════════════════════════════════════════════════════╗"
  if [[ "$state" == "pending" ]]; then
    printf "  ║               %s                     ║\n" "$(t app.tickflow.summary.title_pending)"
  else
    printf "  ║               %s                     ║\n" "$(t app.tickflow.summary.title_ready)"
  fi
  echo "  ╠══════════════════════════════════════════════════════╣"
  if [[ -n "$TICKFLOW_DOMAIN" ]]; then
    echo -e "  ║  $(t app.tickflow.summary.public)  ${CYAN}http://${TICKFLOW_DOMAIN}${GREEN}"
  fi
  echo -e "  ║  $(t app.tickflow.summary.internal)  ${CYAN}http://${internal_ip}:${TICKFLOW_PORT}${GREEN}"
  echo "  ╠══════════════════════════════════════════════════════╣"
  echo -e "  ║  $(t app.tickflow.summary.repo)  ${YELLOW}${TICKFLOW_REPO}${GREEN}"
  echo -e "  ║  $(t app.tickflow.summary.compose)  ${YELLOW}${TICKFLOW_INSTALL_DIR}${GREEN}"
  echo -e "  ║  $(t app.tickflow.summary.data)  ${YELLOW}${TICKFLOW_DATA_DIR}${GREEN}"
  echo -e "  ║  $(t app.tickflow.summary.env)  ${YELLOW}${TICKFLOW_ENV_FILE}${GREEN}"
  echo "  ╚══════════════════════════════════════════════════════╝"
  echo -e "${NC}"
  echo -e "  ${BOLD}$(t app.tickflow.summary.systemd)${NC}"
  echo ""
  echo -e "  ${CYAN}systemctl status ${TICKFLOW_SERVICE_NAME}${NC}      $(t app.tickflow.summary.status_cmd)"
  echo -e "  ${CYAN}journalctl -u ${TICKFLOW_SERVICE_NAME} -f${NC}      $(t app.tickflow.summary.logs_cmd)"
  echo -e "  ${CYAN}systemctl restart ${TICKFLOW_SERVICE_NAME}${NC}     $(t app.tickflow.summary.restart_cmd)"
}

tickflow_remove_dir_or_error() {
  local path="$1" name="$2" success_message="$3"
  if ! safe_rm_dir "$path" "$name"; then
    error "$(t app.tickflow.error.remove_dir "$path")"
  fi
  success "$success_message"
}

tickflow_remove_file_or_error() {
  local path="$1" name="$2"
  require_safe_path "$name" "$path"
  if ! rm -f "$path"; then
    error "$(t app.tickflow.error.remove_file "$path")"
  fi
}

do_install() {
  show_banner
  preflight_check "install"
  acquire_lock
  step "$(t app.tickflow.step.deps)"
  if ! apt-get update -qq; then
    warn "$(t app.tickflow.warn.apt_update)"
  fi
  if ! apt-get install -y -qq git curl ca-certificates docker.io docker-compose-plugin; then
    if ! apt-get install -y -qq git curl ca-certificates docker.io docker-compose; then
      error "$(t app.tickflow.error.deps_install)"
    fi
  fi
  if ! systemctl enable --now docker >/dev/null 2>&1; then
    warn "$(t app.tickflow.warn.docker_enable_failed)"
  fi
  _require_compose_runtime
  success "$(t app.tickflow.success.deps)"
  step "$(t app.tickflow.step.fetch_source)"
  _clone_or_update_repo
  step "$(t app.tickflow.step.config)"
  _ensure_data_layout
  _write_env_file
  _write_compose_file
  success "$(t app.tickflow.success.config)"
  step "$(t app.tickflow.step.systemd)"
  _write_systemd_unit
  step "$(t app.tickflow.step.start)"
  app_check_port_conflict "$TICKFLOW_PORT" "TICKFLOW_PORT"
  if ! systemctl enable "$TICKFLOW_SERVICE_NAME" >/dev/null 2>&1; then
    warn "$(t app.tickflow.warn.service_enable_failed "$TICKFLOW_SERVICE_NAME" "$TICKFLOW_SERVICE_NAME")"
  fi
  if ! systemctl start "$TICKFLOW_SERVICE_NAME"; then
    _print_service_diagnostics
    error "$(t app.tickflow.error.service_start "$TICKFLOW_SERVICE_NAME")"
  fi
  success "$(t app.tickflow.success.started)"
  local state="ready"
  if ! _health_check; then
    state="pending"
  fi
  app_save_config
  _print_summary "$state"
}

do_update() {
  show_banner
  preflight_check "update"
  acquire_lock
  app_load_config
  _require_compose_runtime
  step "$(t app.tickflow.step.fetch_source)"
  _clone_or_update_repo
  step "$(t app.tickflow.step.config)"
  _ensure_data_layout
  _write_env_file
  _write_compose_file
  step "$(t app.tickflow.step.start)"
  app_check_port_conflict "$TICKFLOW_PORT" "TICKFLOW_PORT"
  if ! systemctl restart "$TICKFLOW_SERVICE_NAME"; then
    _print_service_diagnostics
    error "$(t app.tickflow.error.service_start "$TICKFLOW_SERVICE_NAME")"
  fi
  local state="ready"
  if ! _health_check; then
    state="pending"
  fi
  app_save_config
  _print_summary "$state"
}

do_backup() {
  show_banner
  preflight_check "backup"
  acquire_lock
  app_load_config
  require_safe_path "TICKFLOW_INSTALL_DIR" "$TICKFLOW_INSTALL_DIR"
  local backup_dir="${TICKFLOW_INSTALL_DIR}-backups"
  require_safe_path "TICKFLOW_BACKUP_DIR" "$backup_dir"
  if ! mkdir -p "$backup_dir"; then
    error "$(t app.tickflow.backup.error_dir "$backup_dir")"
  fi
  local backup_source
  for backup_source in data tiers.yaml .env; do
    if [[ ! -e "${TICKFLOW_INSTALL_DIR}/${backup_source}" ]]; then
      error "$(t app.tickflow.backup.error_source_missing "${TICKFLOW_INSTALL_DIR}/${backup_source}")"
    fi
  done
  local archive
  archive="${backup_dir}/tickflow-data-$(date +%Y%m%d%H%M%S).tar.gz"
  local archive_tmp="${archive}.tmp"
  if ! tar -czf "$archive_tmp" -C "$TICKFLOW_INSTALL_DIR" data tiers.yaml .env >&2; then
    rm -f "$archive_tmp"
    error "$(t app.tickflow.backup.error_archive "$archive")"
  fi
  if ! chmod 600 "$archive_tmp" || ! mv "$archive_tmp" "$archive"; then
    rm -f "$archive_tmp"
    error "$(t app.tickflow.backup.error_archive "$archive")"
  fi
  success "$(t app.tickflow.backup.success "$archive")"
}

do_status() {
  show_banner
  preflight_check "status"
  app_load_config
  [[ $EUID -ne 0 ]] && warn "$(t app.tickflow.warn.non_root_status "$0")"
  echo -e "\n${BOLD}[$(t app.tickflow.status.systemd)]${NC}"
  if systemctl is-active --quiet "$TICKFLOW_SERVICE_NAME" 2>/dev/null; then
    echo -e "  ${GREEN}[✓]${NC} $(t app.tickflow.status.service_active "$TICKFLOW_SERVICE_NAME")"
  else
    echo -e "  ${RED}[✗]${NC} $(t app.tickflow.status.service_inactive "$TICKFLOW_SERVICE_NAME")"
  fi
  if systemctl is-enabled --quiet "$TICKFLOW_SERVICE_NAME" 2>/dev/null; then
    echo -e "  ${GREEN}[✓]${NC} $(t app.tickflow.status.service_enabled "$TICKFLOW_SERVICE_NAME")"
  else
    echo -e "  ${YELLOW}[!]${NC} $(t app.tickflow.status.service_disabled "$TICKFLOW_SERVICE_NAME")"
  fi
  systemctl status "$TICKFLOW_SERVICE_NAME" --no-pager -l 2>/dev/null \
    | head -12 | sed 's/^/  /' || true
  echo -e "\n${BOLD}[$(t app.tickflow.status.paths)]${NC}"
  _print_status_path "$(t app.tickflow.status.install_dir)" "$TICKFLOW_INSTALL_DIR"
  _print_status_path "$(t app.tickflow.status.data_dir)" "$TICKFLOW_DATA_DIR"
  _print_status_path "$(t app.tickflow.status.env_file)" "$TICKFLOW_ENV_FILE"
  _print_status_path "$(t app.tickflow.status.compose_file)" "$TICKFLOW_COMPOSE_FILE"
  _print_status_path "$(t app.tickflow.status.tiers_file)" "$TICKFLOW_TIERS_FILE"
  _print_status_path "$(t app.tickflow.status.log_dir)" "$TICKFLOW_LOG_DIR"
  echo -e "\n${BOLD}[$(t app.tickflow.status.backups)]${NC}"
  local backup_dir="${TICKFLOW_INSTALL_DIR}-backups"
  if [[ -d "$backup_dir" ]]; then
    local backup_count backup_size
    backup_count=$(find "$backup_dir" -maxdepth 1 -name "tickflow-data-*.tar.gz" -type f 2>/dev/null | wc -l | tr -d ' ' || printf '0')
    backup_size=$(du -sh "$backup_dir" 2>/dev/null | awk '{print $1}' || t status.unknown)
    echo -e "  ${GREEN}[✓]${NC} $(t app.tickflow.status.backup_count "$backup_count" "$backup_size")"
  else
    echo -e "  ${YELLOW}[!]${NC} $(t app.tickflow.status.backup_missing "$backup_dir")"
  fi
  echo -e "\n${BOLD}[$(t app.tickflow.status.http_health)]${NC}"
  if command -v curl >/dev/null 2>&1; then
    local http_code
    http_code=$(curl -o /dev/null -s -w "%{http_code}" --max-time 5 "http://127.0.0.1:${TICKFLOW_PORT}/" 2>/dev/null || echo 000)
    if [[ "$http_code" =~ ^(200|301|302)$ ]]; then
      echo -e "  ${GREEN}[✓]${NC} $(t app.tickflow.status.local_response "$http_code")"
    else
      echo -e "  ${YELLOW}[!]${NC} $(t app.tickflow.status.local_response_warn "$http_code")"
    fi
  else
    echo -e "  ${YELLOW}[!]${NC} $(t app.tickflow.status.curl_missing)"
  fi
  echo ""
}

do_uninstall() {
  show_banner
  preflight_check "uninstall"
  acquire_lock
  app_load_config
  require_safe_path "TICKFLOW_INSTALL_DIR" "$TICKFLOW_INSTALL_DIR"
  local backup_dir="${TICKFLOW_INSTALL_DIR}-backups"
  require_safe_path "TICKFLOW_BACKUP_DIR" "$backup_dir"
  echo -e "${RED}${BOLD}"
  echo "  $(t app.tickflow.uninstall.removes)"
  echo "  $(t app.tickflow.uninstall.keep_install "$TICKFLOW_INSTALL_DIR")"
  echo "  $(t app.tickflow.uninstall.keep_backup "$backup_dir")"
  echo -e "${NC}"
  local confirm
  if deploy_assume_yes; then
    confirm="YES"
  else
    prompt "$(t app.tickflow.prompt.continue)"
    read -r confirm
  fi
  [[ "$confirm" != "YES" ]] && { info "$(t app.tickflow.info.cancelled)"; exit 0; }
  local DELETE_INSTALL=false
  if deploy_assume_yes; then
    deploy_env_truthy DEPLOY_DELETE_INSTALL && DELETE_INSTALL=true
  else
    prompt "$(t app.tickflow.prompt.delete_install "$TICKFLOW_INSTALL_DIR")"
    local delete_install; read -r delete_install
    [[ "${delete_install,,}" == "y" ]] && DELETE_INSTALL=true
  fi
  local DELETE_BACKUP=false
  if deploy_assume_yes; then
    deploy_env_truthy DEPLOY_DELETE_BACKUP && DELETE_BACKUP=true
  else
    prompt "$(t app.tickflow.prompt.delete_backup "$backup_dir")"
    local delete_backup; read -r delete_backup
    [[ "${delete_backup,,}" == "y" ]] && DELETE_BACKUP=true
  fi
  if ! systemctl stop "$TICKFLOW_SERVICE_NAME" >/dev/null 2>&1; then
    if systemctl is-active --quiet "$TICKFLOW_SERVICE_NAME" 2>/dev/null; then
      error "$(t app.tickflow.error.service_stop_failed_active "$TICKFLOW_SERVICE_NAME" "$TICKFLOW_SERVICE_NAME")"
    fi
    warn "$(t app.tickflow.warn.service_stop_failed "$TICKFLOW_SERVICE_NAME" "$TICKFLOW_SERVICE_NAME")"
  fi
  if ! systemctl disable "$TICKFLOW_SERVICE_NAME" >/dev/null 2>&1; then
    warn "$(t app.tickflow.warn.service_disable_failed "$TICKFLOW_SERVICE_NAME" "$TICKFLOW_SERVICE_NAME")"
  fi
  tickflow_remove_file_or_error "/etc/systemd/system/${TICKFLOW_SERVICE_NAME}.service" "TICKFLOW_SERVICE_FILE"
  if ! systemctl daemon-reload; then
    error "$(t app.tickflow.error.service_reload "$TICKFLOW_SERVICE_NAME")"
  fi
  if $DELETE_INSTALL && [[ -e "$TICKFLOW_INSTALL_DIR" || -L "$TICKFLOW_INSTALL_DIR" ]]; then
    tickflow_remove_dir_or_error "$TICKFLOW_INSTALL_DIR" "TICKFLOW_INSTALL_DIR" "$(t app.tickflow.success.deleted_install "$TICKFLOW_INSTALL_DIR")"
  else
    info "$(t app.tickflow.info.kept_install "$TICKFLOW_INSTALL_DIR")"
  fi
  if $DELETE_BACKUP && [[ -e "$backup_dir" || -L "$backup_dir" ]]; then
    tickflow_remove_dir_or_error "$backup_dir" "TICKFLOW_BACKUP_DIR" "$(t app.tickflow.success.deleted_backup "$backup_dir")"
  else
    info "$(t app.tickflow.info.kept_backup "$backup_dir")"
  fi
  tickflow_remove_file_or_error "$CONF_FILE" "CONF_FILE"
  success "$(t app.tickflow.success.removed)"
}
