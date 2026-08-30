#!/usr/bin/env bash

manager_security_doctor_print_usage() {
  printf '%s\n' "$(t security_doctor.usage "${DEPLOY_SCRIPT_NAME:-deploy.sh}")" >&2
}

security_doctor_path() {
  local relative_path="$1" root="${DEPLOY_SECURITY_AUDIT_ROOT:-/}"
  if [[ "$root" == "/" ]]; then
    printf '/%s\n' "${relative_path#/}"
  else
    printf '%s/%s\n' "${root%/}" "${relative_path#/}"
  fi
}

security_doctor_reset() {
  SECURITY_DOCTOR_CHECKS=()
  SECURITY_DOCTOR_STATES=()
  SECURITY_DOCTOR_PATHS=()
  SECURITY_DOCTOR_MESSAGES=()
  SECURITY_DOCTOR_OK=0
  SECURITY_DOCTOR_WARNING=0
  SECURITY_DOCTOR_ERROR=0
  SECURITY_DOCTOR_NOT_CHECKED=0
}

security_doctor_record() {
  local check="$1" state="$2" path="$3" message="$4"
  SECURITY_DOCTOR_CHECKS+=("$check")
  SECURITY_DOCTOR_STATES+=("$state")
  SECURITY_DOCTOR_PATHS+=("$path")
  SECURITY_DOCTOR_MESSAGES+=("$message")
  case "$state" in
    ok) SECURITY_DOCTOR_OK=$((SECURITY_DOCTOR_OK + 1)) ;;
    warning) SECURITY_DOCTOR_WARNING=$((SECURITY_DOCTOR_WARNING + 1)) ;;
    error) SECURITY_DOCTOR_ERROR=$((SECURITY_DOCTOR_ERROR + 1)) ;;
    not_checked) SECURITY_DOCTOR_NOT_CHECKED=$((SECURITY_DOCTOR_NOT_CHECKED + 1)) ;;
  esac
}

security_doctor_file_contains_plain_sub2api_dsn() {
  local path="$1"
  grep -Eq '^[[:space:]]*(export[[:space:]]+)?PG_DSN[[:space:]]*=[[:space:]]*(postgres|postgresql)://' "$path" 2>/dev/null \
    || grep -Eq '(postgres|postgresql)://[^[:space:]]+@' "$path" 2>/dev/null
}

security_doctor_check_vaultwarden_tokens() {
  local root_dir tmp_dir candidate
  local -a matches=()
  root_dir="$(security_doctor_path /root)"
  tmp_dir="$(security_doctor_path /tmp)"

  if [[ -d "$root_dir" && ! -r "$root_dir" ]]; then
    security_doctor_record vaultwarden_legacy_token error "$root_dir" "$(t security_doctor.token.inspect_error)"
    return
  fi
  if [[ -d "$tmp_dir" && ! -r "$tmp_dir" ]]; then
    security_doctor_record vaultwarden_legacy_token error "$tmp_dir" "$(t security_doctor.token.tmp_inspect_error)"
    return
  fi

  shopt -s nullglob
  for candidate in "$root_dir"/.vaultwarden-admin-token.* "$tmp_dir"/vaultwarden-admin-token* "$tmp_dir"/vaultwarden-token*; do
    [[ -e "$candidate" || -L "$candidate" ]] && matches+=("$candidate")
  done
  shopt -u nullglob

  if ((${#matches[@]})); then
    security_doctor_record vaultwarden_legacy_token warning "${matches[0]}" "$(t security_doctor.token.found)"
  else
    security_doctor_record vaultwarden_legacy_token ok "$root_dir" "$(t security_doctor.token.none)"
  fi
}

security_doctor_check_sub2api_dsn() {
  local candidate inspected=0
  local -a candidates=()
  candidates=(
    "$(security_doctor_path /usr/local/bin/sub2api-backup)"
    "$(security_doctor_path /etc/sub2api-deploy.conf)"
  )
  for candidate in "${candidates[@]}"; do
    [[ -e "$candidate" ]] || continue
    inspected=1
    if [[ ! -r "$candidate" ]]; then
      security_doctor_record sub2api_plaintext_dsn error "$candidate" "$(t security_doctor.dsn.inspect_error)"
      return
    fi
    if security_doctor_file_contains_plain_sub2api_dsn "$candidate"; then
      security_doctor_record sub2api_plaintext_dsn warning "$candidate" "$(t security_doctor.dsn.found)"
      return
    fi
  done
  if ((inspected == 0)); then
    security_doctor_record sub2api_plaintext_dsn not_checked "$(security_doctor_path /usr/local/bin/sub2api-backup)" "$(t security_doctor.dsn.missing)"
  else
    security_doctor_record sub2api_plaintext_dsn ok "$(security_doctor_path /usr/local/bin/sub2api-backup)" "$(t security_doctor.dsn.none)"
  fi
}

security_doctor_config_value() {
  local path="$1" key="$2" line value
  line="$(grep -E "^[[:space:]]*${key}[[:space:]]*=" "$path" 2>/dev/null | head -n 1 || true)"
  [[ -n "$line" ]] || return 1
  value="${line#*=}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  if [[ "$value" == '"'*'"' && ${#value} -ge 2 ]]; then
    value="${value:1:${#value}-2}"
  fi
  printf '%s\n' "$value"
}

security_doctor_check_public_binds() {
  local etc_dir conf_file key bind_addr tls_enabled inspected=0
  local -a conf_files=()
  etc_dir="$(security_doctor_path /etc)"
  if [[ ! -d "$etc_dir" ]]; then
    security_doctor_record public_listener not_checked "$etc_dir" "$(t security_doctor.listener.missing_dir)"
    return
  fi
  if [[ ! -r "$etc_dir" ]]; then
    security_doctor_record public_listener error "$etc_dir" "$(t security_doctor.listener.inspect_error)"
    return
  fi

  shopt -s nullglob
  conf_files=("$etc_dir"/*-deploy.conf "$etc_dir"/vaultwarden_deploy.conf "$etc_dir"/tickflow-deploy.conf "$etc_dir"/cyberstrike-ai-deploy.conf "$etc_dir"/sub2api-deploy.conf)
  shopt -u nullglob
  if ((${#conf_files[@]} == 0)); then
    security_doctor_record public_listener not_checked "$etc_dir" "No managed deployment configuration files found."
    return
  fi

  declare -A seen_conf_files=()
  for conf_file in "${conf_files[@]}"; do
    [[ -f "$conf_file" ]] || continue
    [[ -n "${seen_conf_files[$conf_file]:-}" ]] && continue
    seen_conf_files["$conf_file"]=1
    if [[ ! -r "$conf_file" ]]; then
      security_doctor_record public_listener error "$conf_file" "Cannot read the managed deployment configuration."
      continue
    fi
    for key in BA_BIND_ADDR SUB2API_BIND_ADDR TICKFLOW_BIND_ADDR; do
      bind_addr="$(security_doctor_config_value "$conf_file" "$key" 2>/dev/null || true)"
      [[ -n "$bind_addr" ]] || continue
      inspected=$((inspected + 1))
      if ! app_public_bind_is_wildcard "$bind_addr"; then
        security_doctor_record public_listener ok "$conf_file" "$(t security_doctor.listener.not_wildcard "$key")"
        continue
      fi
      if [[ "$key" == BA_BIND_ADDR && "${conf_file##*/}" == "frps-deploy.conf" ]]; then
        security_doctor_record public_listener ok "$conf_file" "$(t security_doctor.listener.frps_exception)"
        continue
      fi
      tls_enabled=0
      if [[ "$key" == BA_BIND_ADDR ]]; then
        tls_enabled="$(security_doctor_config_value "$conf_file" BA_ENABLE_HTTPS 2>/dev/null || true)"
        if deploy_value_truthy "$tls_enabled"; then
          security_doctor_record public_listener ok "$conf_file" "$(t security_doctor.listener.tls "$key")"
          continue
        fi
      fi
      security_doctor_record public_listener warning "$conf_file" "$(t security_doctor.listener.plain "$key")"
    done
  done

  if ((inspected == 0)); then
    security_doctor_record public_listener not_checked "$etc_dir" "$(t security_doctor.listener.none)"
  fi
}

security_doctor_root_crontab_content() {
  local override_path="$1" output status
  SECURITY_DOCTOR_CRONTAB_SOURCE=""
  if [[ -n "$override_path" ]]; then
    if [[ ! -e "$override_path" ]]; then
      return 2
    fi
    [[ -r "$override_path" ]] || return 3
    SECURITY_DOCTOR_CRONTAB_SOURCE="$override_path"
    cat "$override_path"
    return 0
  fi
  command -v crontab >/dev/null 2>&1 || return 4
  set +e
  output="$(crontab -l -u root 2>/dev/null)"
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    SECURITY_DOCTOR_CRONTAB_SOURCE="root crontab"
    printf '%s\n' "$output"
    return 0
  fi
  [[ "$status" -eq 1 ]] && return 2
  return 4
}

security_doctor_contains_legacy_backup_schedule() {
  grep -Eq '(/usr/local/bin/(vaultwarden-backup|sub2api-backup)|new-api-backup|cyberstrike-ai-backup)' 2>/dev/null
}

security_doctor_check_cron_residue() {
  local crontab_content status cron_dir cron_file base found=0
  local -a expected_files=(vaultwarden-backup certbot-renew sub2api-backup new-api-backup cyberstrike-ai-backup deploy-scripts-batch)

  set +e
  crontab_content="$(security_doctor_root_crontab_content "${DEPLOY_SECURITY_AUDIT_ROOT_CRONTAB_FILE:-}")"
  status=$?
  set -e
  case "$status" in
    0)
      if printf '%s\n' "$crontab_content" | security_doctor_contains_legacy_backup_schedule; then
        security_doctor_record legacy_root_crontab warning "${SECURITY_DOCTOR_CRONTAB_SOURCE:-root crontab}" "$(t security_doctor.cron.legacy_root)"
      else
        security_doctor_record legacy_root_crontab ok "${SECURITY_DOCTOR_CRONTAB_SOURCE:-root crontab}" "No legacy application backup schedule found in root crontab."
      fi
      ;;
    2) security_doctor_record legacy_root_crontab ok "root crontab" "$(t security_doctor.cron.empty)" ;;
    3) security_doctor_record legacy_root_crontab error "${DEPLOY_SECURITY_AUDIT_ROOT_CRONTAB_FILE}" "Cannot inspect the supplied root crontab fixture." ;;
    *) security_doctor_record legacy_root_crontab not_checked "root crontab" "$(t security_doctor.cron.inspect_error)"
       ;;
  esac

  cron_dir="$(security_doctor_path /etc/cron.d)"
  if [[ ! -d "$cron_dir" ]]; then
    security_doctor_record legacy_cron_file not_checked "$cron_dir" "$(t security_doctor.cron.dir_missing)"
    return
  fi
  if [[ ! -r "$cron_dir" ]]; then
    security_doctor_record legacy_cron_file error "$cron_dir" "$(t security_doctor.cron.dir_error)"
    return
  fi

  shopt -s nullglob
  for cron_file in "$cron_dir"/*; do
    [[ -f "$cron_file" && -r "$cron_file" ]] || continue
    base="${cron_file##*/}"
    case " ${expected_files[*]} " in
      *" ${base} "*) continue ;;
    esac
    if security_doctor_contains_legacy_backup_schedule < "$cron_file"; then
      security_doctor_record legacy_cron_file warning "$cron_file" "$(t security_doctor.cron.legacy_file)"
      found=1
    fi
  done
  shopt -u nullglob
  if ((found == 0)); then
    security_doctor_record legacy_cron_file ok "$cron_dir" "$(t security_doctor.cron.none)"
  fi
}

security_doctor_print_json() {
  local index first=1
  printf '{"schema_version":1,"generated_at":%s,"summary":{"ok":%s,"warning":%s,"error":%s,"not_checked":%s},"records":[' \
    "$(app_json_string "$(state_now)")" "$SECURITY_DOCTOR_OK" "$SECURITY_DOCTOR_WARNING" "$SECURITY_DOCTOR_ERROR" "$SECURITY_DOCTOR_NOT_CHECKED"
  for index in "${!SECURITY_DOCTOR_CHECKS[@]}"; do
    ((first)) || printf ','
    first=0
    printf '{"check":%s,"state":%s,"path":%s,"message":%s}' \
      "$(app_json_string "${SECURITY_DOCTOR_CHECKS[$index]}")" \
      "$(app_json_string "${SECURITY_DOCTOR_STATES[$index]}")" \
      "$(app_json_string "${SECURITY_DOCTOR_PATHS[$index]}")" \
      "$(app_json_string "${SECURITY_DOCTOR_MESSAGES[$index]}")"
  done
  printf ']}\n'
}

security_doctor_print_human() {
  local index
  printf '%-26s %-13s %-42s %s\n' Check State Path Detail
  for index in "${!SECURITY_DOCTOR_CHECKS[@]}"; do
    printf '%-26s %-13s %-42s %s\n' \
      "${SECURITY_DOCTOR_CHECKS[$index]}" "${SECURITY_DOCTOR_STATES[$index]}" \
      "${SECURITY_DOCTOR_PATHS[$index]}" "${SECURITY_DOCTOR_MESSAGES[$index]}"
  done
  printf '\nSummary: %s ok, %s warning, %s error, %s not checked.\n' \
    "$SECURITY_DOCTOR_OK" "$SECURITY_DOCTOR_WARNING" "$SECURITY_DOCTOR_ERROR" "$SECURITY_DOCTOR_NOT_CHECKED"
}

manager_security_doctor_main() {
  local json arg
  for arg in "$@"; do
    case "$arg" in
      --help|-h)
        manager_security_doctor_print_usage
        return 0
        ;;
    esac
  done
  if ! manager_parse_args "--json --help" manager_security_doctor_print_usage "$@"; then
    return $?
  fi
  json="$MANAGER_ARG_JSON"

  security_doctor_reset
  security_doctor_check_vaultwarden_tokens
  security_doctor_check_sub2api_dsn
  security_doctor_check_public_binds
  security_doctor_check_cron_residue

  if ((json)); then
    security_doctor_print_json
  else
    security_doctor_print_human
  fi
  ((SECURITY_DOCTOR_ERROR == 0))
}
