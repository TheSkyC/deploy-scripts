#!/usr/bin/env bash

# Strict-ASCII validators must stay ASCII-only on every server locale:
# character classes such as [A-Za-z] are collation-dependent and, under UTF-8
# locales, also match accented Latin characters (for example é). Each
# validator pins LC_ALL=C so validation is byte-exact regardless of locale.
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
  host="${value#"${scheme}"://}"
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
  # Character ranges in regexes are collation-dependent: under en_US.UTF-8 /
  # zh_CN.UTF-8, [a-z0-9] also matches uppercase. Pin the C locale so image
  # repo validation accepts lowercase-only names on every server locale.
  local LC_ALL=C
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
  local LC_ALL=C
  if ! [[ "$value" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}$ ]]; then
    error "$(t error.image_tag_invalid "$name" "$value")"
  fi
}

app_validate_sha256() {
  local name="$1" value="$2"
  local LC_ALL=C
  if ! [[ "$value" =~ ^[A-Fa-f0-9]{64}$ ]]; then
    error "$(t error.sha256_invalid "$name" "$value")"
  fi
}

app_is_valid_email() {
  local value="${1:-}" local_part domain
  local LC_ALL=C
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
  local LC_ALL=C
  if ! [[ "$value" =~ ^[0-9]+[.][0-9]+([.][0-9]+)?([-.][A-Za-z0-9][A-Za-z0-9_.-]*)?$ ]]; then
    error "$(t error.release_version_invalid "$name" "$value")"
  fi
}

app_validate_system_name() {
  local name="$1" value="$2"
  local LC_ALL=C
  if ! [[ "$value" =~ ^[A-Za-z_][A-Za-z0-9_-]{0,63}$ ]]; then
    error "$(t error.system_name_invalid "$name" "$value")"
  fi
}

app_validate_systemd_name() {
  local name="$1" value="$2"
  local LC_ALL=C
  if ! [[ "$value" =~ ^[A-Za-z0-9_.@-]+$ ]] \
      || [[ "$value" == .* || "$value" == *. || "$value" == *..* || "$value" == *"/"* ]]; then
    error "$(t error.systemd_name_invalid "$name" "$value")"
  fi
}

app_validate_github_repo() {
  local name="$1" value="$2"
  local LC_ALL=C
  if ! [[ "$value" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] \
      || [[ "$value" == *..* || "$value" == .* || "$value" == */.* || "$value" == *. || "$value" == *.*/ ]]; then
    error "$(t error.github_repo_invalid "$name" "$value")"
  fi
}

app_validate_git_ref() {
  local name="$1" value="$2"
  local LC_ALL=C
  if ! [[ "$value" =~ ^[A-Za-z0-9._/-]+$ ]] \
      || [[ "$value" == -* || "$value" == */ || "$value" == *. || "$value" == *..* || "$value" == *@\{* || "$value" == *//* ]]; then
    error "$(t error.git_ref_invalid "$name" "$value")"
  fi
}

app_validate_db_identifier() {
  local name="$1" value="$2"
  local LC_ALL=C
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

# Move /etc/nginx/sites-enabled/default out of the way instead of deleting it
# so an existing site is never lost. The backup lives in sites-available as
# .<app>-default.deploy-bak and is restored by app_nginx_default_site_restore
# during uninstall. Fails explicitly when the move fails (the caller aborts
# the install because nginx -t would then fail on port conflicts).
app_nginx_default_site_backup() {
  local link="/etc/nginx/sites-enabled/default"
  local backup="/etc/nginx/sites-available/.${APP_ID:-app}-default.deploy-bak"
  [[ -e "$link" || -L "$link" ]] || return 0
  if [[ -e "$backup" || -L "$backup" ]]; then
    rm -f "$backup" 2>/dev/null || true
  fi
  if mv "$link" "$backup"; then
    success "$(t common.default_site_backed_up "$backup")"
    return 0
  fi
  error "$(t common.default_site_backup_failed "$link")"
}

# Restore the default Nginx site that app_nginx_default_site_backup moved
# away, unless the app's own site is still using port 80. Called during
# uninstall; failures are warnings because the app is being removed anyway.
app_nginx_default_site_restore() {
  local backup="/etc/nginx/sites-available/.${APP_ID:-app}-default.deploy-bak"
  local link="/etc/nginx/sites-enabled/default"
  [[ -e "$backup" || -L "$backup" ]] || return 0
  [[ -e "$link" || -L "$link" ]] && return 0
  if mv "$backup" "$link"; then
    success "$(t common.default_site_restored "$link")"
  else
    warn "$(t common.default_site_restore_failed "$backup" "$link")"
  fi
}

deploy_env_truthy() {
  local name="$1"
  local value="${!name:-}"
  case "${value,,}" in
    1|true|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}

deploy_assume_yes() {
  deploy_env_truthy DEPLOY_ASSUME_YES
}

app_doctor_service_name() {
  if [[ -n "${APP_DOCTOR_SERVICE_FN:-}" ]] && declare -f "$APP_DOCTOR_SERVICE_FN" >/dev/null 2>&1; then
    "$APP_DOCTOR_SERVICE_FN" && return 0
    return 1
  fi
  if [[ -n "${SERVICE_NAME:-}" ]]; then
    printf '%s\n' "$SERVICE_NAME"
    return 0
  fi
  return 1
}

# The config-derive hook is app-declared: an app that derives paths from
# saved configuration sets APP_CONFIG_DERIVE_HOOK to its hook function name.
app_doctor_config_derive_hook() {
  local hook="${APP_CONFIG_DERIVE_HOOK:-}"
  if [[ -n "$hook" ]] && declare -f "$hook" >/dev/null 2>&1; then
    printf '%s\n' "$hook"
    return 0
  fi
  return 1
}
app_doctor_validate_saved_config() {
  local conf_file="$1"
  (
    load_config_file "$conf_file" "${CONFIG_KEYS[@]}"
    local derive_hook=""
    if derive_hook="$(app_doctor_config_derive_hook 2>/dev/null)"; then
      "$derive_hook"
    fi
    if declare -f _validate_config_values >/dev/null 2>&1; then
      _validate_config_values
    fi
  )
}

# JSON string escaper: delegates to the shared core in operation.sh (loaded
# before app.sh) so operation records and status JSON escape identically.
app_json_string() {
  printf '"%s"' "$(__deploy_json_escape_unquoted "${1:-}")"
}

app_json_bool() {
  if [[ "${1:-false}" == "true" ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

app_json_value() {
  local value="${1:-}"
  case "$value" in
    true|false|null) printf '%s' "$value" ;;
    *) app_json_string "$value" ;;
  esac
}

# Emit one JSON service object for a systemd unit name.
app_json_service_object() {
  local service_name="$1"
  local unit_exists=null active=null enabled=null
  if command -v systemctl >/dev/null 2>&1; then
    if systemctl list-unit-files "${service_name}.service" --no-legend 2>/dev/null | grep -q .; then
      unit_exists=true
      if systemctl is-active --quiet "$service_name" 2>/dev/null; then
        active=true
      else
        active=false
      fi
      if systemctl is-enabled --quiet "$service_name" 2>/dev/null; then
        enabled=true
      else
        enabled=false
      fi
    else
      unit_exists=false
    fi
  fi
  printf '{"name":%s,"unit_exists":%s,"active":%s,"enabled":%s}' \
    "$(app_json_string "$service_name")" \
    "$(app_json_value "$unit_exists")" \
    "$(app_json_value "$active")" \
    "$(app_json_value "$enabled")"
}

# Print the INSTALLED_VERSION recorded in a deployment config file, if any.
app_config_installed_version() {
  local conf_file="$1"
  [[ -f "$conf_file" ]] || return 1
  local value
  value="$(awk -F= '
      /^[[:space:]]*INSTALLED_VERSION=/ {
        sub(/^[^=]*=[[:space:]]*/, "")
        gsub(/^"|"$/, "")
        gsub(/[[:space:]]+$/, "")
        print
        exit
      }
    ' "$conf_file" 2>/dev/null)" || return 1
  [[ -n "$value" ]] || return 1
  printf '%s\n' "$value"
}

# Read one KEY=value entry from the deployment config file, but only when the
# file is owned by root with mode 600/400. Status projections must not adopt
# paths from a config an unprivileged user could have rewritten; callers get
# empty output (exit 1) instead of a trusted value when the gate fails.
app_conf_trusted_value() {
  local conf_file="$1" key="$2" owner mode value
  [[ -f "$conf_file" ]] || return 1
  owner="$(stat -c '%U' "$conf_file" 2>/dev/null || printf unknown)"
  mode="$(stat -c '%a' "$conf_file" 2>/dev/null || printf unknown)"
  if [[ "$owner" != root || ( "$mode" != 600 && "$mode" != 400 ) ]]; then
    return 1
  fi
  value="$(awk -F= -v key="$key" '
    $0 ~ "^[[:space:]]*" key "=" {
      value=$0
      sub(/^[^=]*=[[:space:]]*/, "", value)
      gsub(/^"|"$/, "", value)
      gsub(/[[:space:]]+$/, "", value)
      print value
      exit
    }
  ' "$conf_file" 2>/dev/null)" || return 1
  [[ -n "$value" ]] || return 1
  printf '%s\n' "$value"
}

# Shared check-update adapter for binary GitHub releases: loads the saved
# deployment config (so INSTALLED_VERSION and GITHUB_REPO are current) and
# delegates the comparison to the central version checker. Binary apps use
# bapp_check_update_json; this variant is for hand-written apps whose impl
# previously inlined the same three lines (newapi, sub2api).
app_check_update_json() {
  local app_id="$1" installed="$2" refresh="${3:-0}" no_network="${4:-0}" conf_file
  conf_file="$(app_conf_file 2>/dev/null || true)"
  [[ -n "$conf_file" && -f "$conf_file" ]] && load_config_file "$conf_file" "${CONFIG_KEYS[@]}"
  version_check_binary_release_json "$app_id" "${GITHUB_REPO:-}" "$installed" "$refresh" "$no_network"
}

# Print the state JSON for the newest backup archive in backup_dir matching
# one or more archive globs. Shared tail of every APP_STATUS_BACKUP_FN
# projection: inspect failures report state=failed, an empty directory reports
# state=missing, and an unreadable mtime reports state=unknown.
app_backup_latest_archive_json() {
  local backup_dir="$1" glob find_args=() latest_archive archive_name archive_mtime last_success_at
  shift
  # The name tests must stay inside explicit \( ... \): find's default
  # precedence would otherwise bind -printf to the last -name only and let
  # earlier OR clauses fall back to plain -print, corrupting the projection.
  for glob in "$@"; do
    [[ ${#find_args[@]} -eq 0 ]] || find_args+=(-o)
    find_args+=(-name "$glob")
  done
  if ! latest_archive="$(find "$backup_dir" -maxdepth 1 -type f \( "${find_args[@]}" \) -printf '%T@|%p\n' 2>/dev/null | sort -t'|' -k1,1nr)"; then
    printf '{"state":"failed","last_success_at":null,"path":%s,"message":"cannot inspect backup directory"}' "$(app_json_string "$backup_dir")"
    return
  fi
  latest_archive="${latest_archive%%$'\n'*}"
  if [[ -z "$latest_archive" ]]; then
    printf '{"state":"missing","last_success_at":null,"path":%s,"message":"no backup archive found"}' "$(app_json_string "$backup_dir")"
    return
  fi
  archive_name="${latest_archive#*|}"
  archive_mtime="${latest_archive%%|*}"
  if ! last_success_at="$(date -d "@${archive_mtime%.*}" '+%Y-%m-%dT%H:%M:%S%:z' 2>/dev/null)"; then
    printf '{"state":"unknown","last_success_at":null,"path":%s,"message":"cannot read backup timestamp"}' "$(app_json_string "$archive_name")"
    return
  fi
  local integrity="unverified"
  if backup_verify_archive "$latest_archive" 2>/dev/null; then
    integrity="verified"
  elif [[ -f "${latest_archive}.sha256" ]]; then
    integrity="failed"
  fi
  printf '{"state":"available","last_success_at":%s,"path":%s,"integrity":"%s","message":null}' \
    "$(app_json_string "$last_success_at")" "$(app_json_string "$archive_name")" "$integrity"
}

# Full status-backup projection shared by every app: resolve the backup
# directory from the default variable, override it from the saved config only
# after the root/600/400 trust gate passes, then project the newest archive as
# JSON. A config file that exists but fails the trust gate is reported
# explicitly instead of being silently ignored. unsafe_dir_message customizes
# the unsafe-path message text; remaining arguments are archive globs.
# Locals deliberately avoid the name `conf_file`: Bash locals are dynamically
# scoped, so an app_conf_file override reading `$conf_file` must still see the
# caller's value, not this function's scratch copy.
app_status_backup_json() {
  local conf_key="$1" default_dir="$2" unsafe_dir_message="$3"
  shift 3
  local app_conf_path backup_dir configured_dir
  backup_dir="$default_dir"
  app_conf_path="$(app_conf_file 2>/dev/null || true)"
  if [[ -f "$app_conf_path" ]]; then
    if ! configured_dir="$(app_conf_trusted_value "$app_conf_path" "$conf_key")"; then
      printf '{"state":"unknown","last_success_at":null,"path":null,"message":"configuration file is not trusted"}'
      return
    fi
    [[ -n "$configured_dir" ]] && backup_dir="$configured_dir"
  fi
  if [[ -z "$backup_dir" ]] || ! is_safe_path "$backup_dir"; then
    printf '{"state":"unknown","last_success_at":null,"path":%s,"message":%s}' \
      "$(app_json_string "$backup_dir")" "$(app_json_string "$unsafe_dir_message")"
    return
  fi
  if [[ ! -d "$backup_dir" ]]; then
    printf '{"state":"missing","last_success_at":null,"path":%s,"message":"backup directory is missing"}' "$(app_json_string "$backup_dir")"
    return
  fi
  app_backup_latest_archive_json "$backup_dir" "$@"
}

do_status_json() {
  app_status_collect_json
}

# Writes an Nginx site config from stdin through an atomic helper.
app_write_nginx_config_file() {
  local nginx_conf="$1" error_key="$2"
  if ! atomic_write_file "$nginx_conf" 644 root:root; then
    error "$(t "$error_key" "$nginx_conf")"
  fi
}

# Creates an Nginx sites-enabled symlink atomically.
app_write_nginx_site_link() {
  local target="$1" link_path="$2" error_key="$3"
  if ! atomic_symlink "$target" "$link_path"; then
    error "$(t "$error_key" "$target")"
  fi
}

# Writes a per-app logrotate policy for the service log directory, staging the
# file through atomic_write_file. The log directory, target file, and localized
# error/success keys are app-supplied.
app_write_logrotate() {
  local logrotate_file="$1" log_dir="$2" error_key="$3" success_key="$4"
  if ! atomic_write_file "$logrotate_file" 644 root:root << LOGR
${log_dir}/*.log {
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
  then
    error "$(t "$error_key")"
  fi
  success "$(t "$success_key")"
}

# Remove one file with a safe-path guard, surfacing removal failures through
# the app-supplied localized error key. Shared replacement for the per-app
# `_*_remove_file_or_error` clones.
app_remove_file_or_error() {
  local path="$1" name="$2" error_key="$3"
  require_safe_path "$name" "$path"
  if ! rm -f "$path"; then
    error "$(t "$error_key" "$path")"
  fi
}

# Remove one directory with a safe-path guard, printing the app-supplied
# success message on success and surfacing failures through the localized
# error key. Shared replacement for the per-app `_*_remove_dir_or_error`
# clones.
app_remove_dir_or_error() {
  local path="$1" name="$2" success_message="$3" error_key="$4"
  if ! safe_rm_dir "$path" "$name"; then
    error "$(t "$error_key" "$path")"
  fi
  success "$success_message"
}

# Opens the service port through the active firewall manager: ufw first, then
# optionally firewalld (opt-in for apps that support it), then iptables with
# persistence. Localized keys are addressed through the app key prefix and the
# app label appears in the ufw rule comment.
app_configure_firewall() {
  local port="$1" app_prefix="$2" app_label="$3" enable_firewalld="${4:-false}"
  local FW_DONE=false FW_ERROR=false
  if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
    if ufw allow "${port}/tcp" comment "$app_label" > /dev/null; then
      success "$(t "${app_prefix}.success.ufw_port" "$port")"
      FW_DONE=true
    else
      FW_ERROR=true
    fi
  fi
  if $enable_firewalld && ! $FW_DONE && command -v firewall-cmd &>/dev/null && \
      firewall-cmd --state &>/dev/null; then
    if firewall-cmd --permanent --add-port="${port}/tcp" >/dev/null 2>&1 \
        && firewall-cmd --reload >/dev/null 2>&1; then
      success "$(t "${app_prefix}.success.firewalld_port" "$port")"
      FW_DONE=true
    else
      FW_ERROR=true
    fi
  fi
  if ! $FW_DONE && command -v iptables &>/dev/null; then
    if iptables -C INPUT -p tcp --dport "$port" -j ACCEPT 2>/dev/null \
        || iptables -A INPUT -p tcp --dport "$port" -j ACCEPT; then
      if command -v netfilter-persistent &>/dev/null; then
        if netfilter-persistent save 2>/dev/null; then
          success "$(t "${app_prefix}.success.iptables_saved")"
        else
          warn "$(t "${app_prefix}.warn.iptables_not_persisted")"
        fi
      elif command -v iptables-save &>/dev/null; then
        local iptables_dir="/etc/iptables"
        if mkdir -p "$iptables_dir"; then
          local iptables_rules="${iptables_dir}/rules.v4"
          local iptables_tmp
          if ! iptables_tmp=$(mktemp "${iptables_rules}.XXXXXX"); then
            warn "$(t "${app_prefix}.warn.iptables_write_failed")"
          elif iptables-save > "$iptables_tmp" 2>/dev/null \
              && chmod 644 "$iptables_tmp" \
              && chown root:root "$iptables_tmp" \
              && mv "$iptables_tmp" "$iptables_rules"; then
            info "$(t "${app_prefix}.info.iptables_rules_written")"
          else
            rm -f "$iptables_tmp"
            warn "$(t "${app_prefix}.warn.iptables_write_failed")"
          fi
        else
          warn "$(t "${app_prefix}.warn.iptables_write_failed")"
        fi
      else
        warn "$(t "${app_prefix}.warn.iptables_not_persisted")"
      fi
      success "$(t "${app_prefix}.success.iptables_port" "$port")"
      FW_DONE=true
    else
      FW_ERROR=true
    fi
  fi
  if ! $FW_DONE; then
    if $FW_ERROR; then
      warn "$(t "${app_prefix}.warn.firewall_config_failed" "$port")"
    else
      warn "$(t "${app_prefix}.warn.no_firewall" "$port")"
    fi
  fi
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
  local conf_safe=false
  if [[ -f "$conf_file" ]]; then
    local conf_owner="unknown" conf_mode="unknown"
    # GNU stat (coreutils) is assumed: -c '%U'/'%a' is not portable to BSD stat.
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
      conf_safe=true
    fi
    if $conf_safe; then
      if app_doctor_validate_saved_config "$conf_file"; then
        doctor_ok "$(t doctor.config_parse_ok "$conf_file")"
      else
        doctor_fail "$(t doctor.config_parse_bad "$conf_file")"
      fi
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
