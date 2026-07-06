#!/usr/bin/env bash

# Validate a port number is in range 1-65535.
app_validate_port() {
  local value="$1"
  local label="${2:-port}"
  if ! [[ "$value" =~ ^[0-9]+$ ]] || [[ "$value" -lt 1 || "$value" -gt 65535 ]]; then
    error "$(t error.port_invalid "$label" "$value")"
  fi
}

# Validate a boolean value.
app_validate_bool() {
  local name="$1" value="$2"
  case "${value,,}" in
    1|0|true|false|yes|no|y|n|on|off) ;;
    *) error "$(t error.bool_invalid "$name" "$value")" ;;
  esac
}

# Validate an optional domain name (empty string is allowed).
app_validate_domain() {
  local name="$1" value="$2"
  if [[ -n "$value" ]] && ! is_valid_dns_name "$value"; then
    error "$(t error.domain_invalid "$name" "$value")"
  fi
}

app_validate_http_url() {
  local name="$1" value="$2" scheme host
  case "$value" in
    http://*|https://*) ;;
    *) error "$(t error.url_invalid "$name" "$value")" ;;
  esac
  case "$value" in
    ""|*[[:space:]]*|*\"*|*"'"*|*"\\"*|*"<"*|*">"*|*"\`"*|*"|"*)
      error "$(t error.url_invalid "$name" "$value")"
      ;;
  esac
  scheme="${value%%://*}"
  host="${value#${scheme}://}"
  host="${host%%/*}"
  host="${host%%:*}"
  if [[ "$host" != "localhost" && ! "$host" =~ ^[0-9]+(\.[0-9]+){3}$ ]] && ! is_valid_dns_name "$host"; then
    error "$(t error.url_invalid "$name" "$value")"
  fi
}

app_validate_https_url() {
  local name="$1" value="$2"
  app_validate_http_url "$name" "$value"
  if [[ "$value" != https://* ]]; then
    error "$(t error.https_url_invalid "$name" "$value")"
  fi
}

app_validate_goproxy() {
  local name="$1" value="$2" token
  local -a _goproxy_parts
  [[ -n "$value" ]] || error "$(t error.goproxy_invalid "$name" "$value")"
  case "$value" in
    *[[:space:]]*|*\"*|*"'"*|*"\\"*|*"<"*|*">"*|*"\`"*)
      error "$(t error.goproxy_invalid "$name" "$value")"
      ;;
  esac
  local normalized="${value//|/,}"
  IFS=',' read -r -a _goproxy_parts <<< "$normalized"
  for token in "${_goproxy_parts[@]}"; do
    case "$token" in
      direct|off) ;;
      http://*|https://*)
        app_validate_http_url "$name" "$token"
        ;;
      *)
        error "$(t error.goproxy_invalid "$name" "$value")"
        ;;
    esac
  done
}

app_validate_image_repo() {
  local name="$1" value="$2" first rest part
  local -a _image_repo_parts
  [[ -n "$value" ]] || error "$(t error.image_repo_invalid "$name" "$value")"
  case "$value" in
    *[[:space:]]*|*\"*|*"'"*|*"\\"*|*"<"*|*">"*|*"\`"*|*"|"*|*";"*|*"&"*|*'$'*|*"("*|*")"*|*"["*|*"]"*|*"{"*|*"}"*|*"!"*|*"?"*|*"*"*|*@*)
      error "$(t error.image_repo_invalid "$name" "$value")"
      ;;
  esac
  [[ "$value" != /* && "$value" != */ && "$value" != *//* && "$value" != *..* ]] \
    || error "$(t error.image_repo_invalid "$name" "$value")"

  first="${value%%/*}"
  rest="$value"
  if [[ "$first" == *.* || "$first" == *:* || "$first" == localhost ]]; then
    [[ "$value" == */* ]] || error "$(t error.image_repo_invalid "$name" "$value")"
    [[ "$first" =~ ^[a-z0-9]([a-z0-9.-]*[a-z0-9])?(:[0-9]+)?$ ]] \
      || error "$(t error.image_repo_invalid "$name" "$value")"
    if [[ "$first" == *:* ]]; then
      local port="${first##*:}"
      [[ "$port" =~ ^[0-9]+$ && "$port" -ge 1 && "$port" -le 65535 ]] \
        || error "$(t error.image_repo_invalid "$name" "$value")"
    fi
    rest="${value#*/}"
  fi

  IFS='/' read -r -a _image_repo_parts <<< "$rest"
  for part in "${_image_repo_parts[@]}"; do
    [[ "$part" =~ ^[a-z0-9]+([._-][a-z0-9]+)*$ ]] \
      || error "$(t error.image_repo_invalid "$name" "$value")"
  done
}

app_validate_image_tag() {
  local name="$1" value="$2"
  if ! [[ "$value" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]]; then
    error "$(t error.image_tag_invalid "$name" "$value")"
  fi
}

app_validate_sha256() {
  local name="$1" value="$2"
  if ! [[ "$value" =~ ^[A-Fa-f0-9]{64}$ ]]; then
    error "$(t error.sha256_invalid "$name" "$value")"
  fi
}

app_is_valid_email() {
  local value="${1:-}" local_part domain
  [[ -n "$value" && ${#value} -le 254 ]] || return 1
  case "$value" in
    *[[:space:]]*|*\"*|*"'"*|*"\\"*|*"<"*|*">"*|*"\`"*|*"|"*|*";"*|*"&"*|*'$'*|*"("*|*")"*|*"["*|*"]"*|*"{"*|*"}"*|*"!"*|*"?"*|*"*"*|*/*|*@*@*)
      return 1
      ;;
  esac
  [[ "$value" == *@* ]] || return 1
  local_part="${value%@*}"
  domain="${value#*@}"
  [[ -n "$local_part" && ${#local_part} -le 64 ]] || return 1
  [[ "$local_part" != .* && "$local_part" != *. && "$local_part" != *..* ]] || return 1
  [[ "$local_part" =~ ^[A-Za-z0-9._%+-]+$ ]] || return 1
  is_valid_dns_name "$domain"
}

app_validate_email() {
  local name="$1" value="$2"
  if ! app_is_valid_email "$value"; then
    error "$(t error.email_invalid "$name" "$value")"
  fi
}

app_validate_release_version() {
  local name="$1" value="$2"
  if ! [[ "$value" =~ ^[0-9]+[.][0-9]+([.][0-9]+)?([-.][A-Za-z0-9][A-Za-z0-9_.-]*)?$ ]]; then
    error "$(t error.release_version_invalid "$name" "$value")"
  fi
}

app_validate_system_name() {
  local name="$1" value="$2"
  if ! [[ "$value" =~ ^[A-Za-z_][A-Za-z0-9_-]{0,63}$ ]]; then
    error "$(t error.system_name_invalid "$name" "$value")"
  fi
}

app_validate_systemd_name() {
  local name="$1" value="$2"
  if ! [[ "$value" =~ ^[A-Za-z0-9_.@-]+$ ]] \
      || [[ "$value" == .* || "$value" == *. || "$value" == *..* || "$value" == *"/"* ]]; then
    error "$(t error.systemd_name_invalid "$name" "$value")"
  fi
}

app_validate_github_repo() {
  local name="$1" value="$2"
  if ! [[ "$value" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] \
      || [[ "$value" == *..* || "$value" == .* || "$value" == */.* || "$value" == *. || "$value" == *.*/ ]]; then
    error "$(t error.github_repo_invalid "$name" "$value")"
  fi
}

app_validate_git_ref() {
  local name="$1" value="$2"
  if ! [[ "$value" =~ ^[A-Za-z0-9._/-]+$ ]] \
      || [[ "$value" == -* || "$value" == */ || "$value" == *. || "$value" == *..* || "$value" == *@\{* || "$value" == *//* ]]; then
    error "$(t error.git_ref_invalid "$name" "$value")"
  fi
}

app_validate_db_identifier() {
  local name="$1" value="$2"
  if ! [[ "$value" =~ ^[A-Za-z_][A-Za-z0-9_]{0,62}$ ]]; then
    error "$(t error.db_identifier_invalid "$name" "$value")"
  fi
}

# Echo the standard deployment config path for the current app.
app_conf_file() {
  local standard="/etc/${APP_ID:-app}-deploy.conf"
  if [[ -n "${_APP_CONF_LEGACY:-}" ]]; then
    echo "$_APP_CONF_LEGACY"
  else
    echo "$standard"
  fi
}

# Echo the standard lock file path for the current app.
app_lock_file() {
  echo "/var/lock/${APP_ID:-app}-deploy.lock"
}

# Standard config save — writes CONFIG_KEYS to the app conf file.
app_save_config() {
  local conf_file
  conf_file="$(app_conf_file)"
  if ! write_config_file "$conf_file" "${CONFIG_KEYS[@]}"; then
    error "$(t error.config_write "$conf_file")"
  fi
  success "$(t config.saved "$conf_file")"
}

# Standard config load — loads from the app conf file, then calls
# an optional hook to recompute derived paths, and re-validates if a
# _validate_config_values function exists.
# Usage: app_load_config [derive_hook_fn]
app_load_config() {
  local conf_file derive_hook
  conf_file="$(app_conf_file)"
  derive_hook="${1:-}"
  [[ -f "$conf_file" ]] || return 0
  load_config_file "$conf_file" "${CONFIG_KEYS[@]}"
  if [[ -n "$derive_hook" ]] && declare -f "$derive_hook" >/dev/null 2>&1; then
    "$derive_hook"
  fi
  if declare -f _validate_config_values >/dev/null 2>&1; then
    _validate_config_values
  fi
  success "$(t config.loaded "$conf_file")"
}

# Register a legacy config path so app_conf_file() returns it during
# load when the old file still exists on disk.
app_conf_register_legacy() {
  local legacy="$1"
  if [[ -f "$legacy" ]]; then
    _APP_CONF_LEGACY="$legacy"
  fi
}

app_doctor_service_name() {
  if [[ -n "${SERVICE_NAME:-}" ]]; then
    printf '%s\n' "$SERVICE_NAME"
    return 0
  fi
  if [[ -n "${TICKFLOW_SERVICE_NAME:-}" ]]; then
    printf '%s\n' "$TICKFLOW_SERVICE_NAME"
    return 0
  fi
  if [[ "${APP_ID:-}" == "vaultwarden" ]]; then
    printf '%s\n' "vaultwarden"
    return 0
  fi
  return 1
}

do_doctor() {
  local failures=0 warnings=0

  doctor_ok() { success "$*"; }
  doctor_warn() { warnings=$((warnings + 1)); warn "$*"; }
  doctor_fail() {
    failures=$((failures + 1))
    echo -e "${RED}[x]${NC} $*" >&2
  }

  show_banner
  step "$(t doctor.title)"

  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    doctor_ok "$(t doctor.root_ok)"
  else
    doctor_warn "$(t doctor.root_warn)"
  fi

  local conf_file
  conf_file="$(app_conf_file)"
  if [[ -f "$conf_file" ]]; then
    local conf_owner="unknown" conf_mode="unknown"
    if command -v stat >/dev/null 2>&1; then
      conf_owner="$(stat -c '%U' "$conf_file" 2>/dev/null || echo unknown)"
      conf_mode="$(stat -c '%a' "$conf_file" 2>/dev/null || echo unknown)"
    fi
    if [[ "$conf_owner" != "root" ]]; then
      doctor_fail "$(t doctor.config_owner_bad "$conf_owner" "$conf_file")"
    elif [[ "$conf_mode" != "600" && "$conf_mode" != "400" ]]; then
      doctor_fail "$(t doctor.config_mode_bad "$conf_mode" "$conf_file")"
    else
      doctor_ok "$(t doctor.config_ok "$conf_file")"
    fi
  else
    doctor_warn "$(t doctor.config_missing "$conf_file")"
  fi

  local cmd
  for cmd in bash awk sed grep mktemp; do
    if command -v "$cmd" >/dev/null 2>&1; then
      doctor_ok "$(t doctor.command_ok "$cmd")"
    else
      doctor_fail "$(t doctor.command_missing "$cmd")"
    fi
  done
  for cmd in curl systemctl; do
    if command -v "$cmd" >/dev/null 2>&1; then
      doctor_ok "$(t doctor.command_ok "$cmd")"
    else
      doctor_warn "$(t doctor.command_missing "$cmd")"
    fi
  done

  local service_name=""
  if service_name="$(app_doctor_service_name 2>/dev/null)"; then
    if command -v systemctl >/dev/null 2>&1; then
      if systemctl list-unit-files "${service_name}.service" --no-legend 2>/dev/null | grep -q .; then
        if systemctl is-active --quiet "$service_name" 2>/dev/null; then
          doctor_ok "$(t doctor.service_active "$service_name")"
        else
          doctor_warn "$(t doctor.service_inactive "$service_name")"
        fi
        if systemctl is-enabled --quiet "$service_name" 2>/dev/null; then
          doctor_ok "$(t doctor.service_enabled "$service_name")"
        else
          doctor_warn "$(t doctor.service_disabled "$service_name")"
        fi
      else
        doctor_warn "$(t doctor.service_unit_missing "$service_name")"
      fi
    else
      doctor_warn "$(t doctor.systemctl_missing)"
    fi
  fi

  if [[ "$failures" -gt 0 ]]; then
    echo -e "${RED}[x]${NC} $(t doctor.done_warn "$failures" "$warnings")" >&2
    return 1
  fi
  if [[ "$warnings" -gt 0 ]]; then
    doctor_warn "$(t doctor.done_warn "$failures" "$warnings")"
  else
    doctor_ok "$(t doctor.done_ok)"
  fi
}
