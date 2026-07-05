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
