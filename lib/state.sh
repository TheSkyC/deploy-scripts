#!/usr/bin/env bash

DEPLOY_STATE_SCHEMA_VERSION=2
DEPLOY_STATUS_NO_PROBE="${DEPLOY_STATUS_NO_PROBE:-0}"
DEPLOY_STATUS_NO_NETWORK="${DEPLOY_STATUS_NO_NETWORK:-0}"
DEPLOY_STATUS_TIMEOUT_SECONDS="${DEPLOY_STATUS_TIMEOUT_SECONDS:-8}"

state_now() { date '+%Y-%m-%dT%H:%M:%S%:z'; }
state_json_nullable() { [[ -n "${1:-}" && "${1:-}" != null ]] && app_json_string "$1" || printf 'null'; }

# Parse one scalar or object member from JSON emitted by this framework. This is
# deliberately small, but handles escaped strings and nested objects without
# relying on jq or Python at runtime.
state_json_unescape() {
  local value="${1:-}" result='' i c next hex code char backslash=\\
  for ((i = 0; i < ${#value}; i++)); do
    c="${value:i:1}"
    if [[ "$c" != "$backslash" ]]; then
      result+="$c"
      continue
    fi
    i=$((i + 1))
    [[ $i -lt ${#value} ]] || return 1
    next="${value:i:1}"
    case "$next" in
      '"') result+='"' ;;
      "$backslash") result+="$backslash" ;;
      '/') result+='/' ;;
      b) result+=$'\b' ;;
      f) result+=$'\f' ;;
      n) result+=$'\n' ;;
      r) result+=$'\r' ;;
      t) result+=$'\t' ;;
      u)
        hex="${value:i+1:4}"
        [[ "$hex" =~ ^[0-9a-fA-F]{4}$ ]] || return 1
        [[ "${hex:0:2}" == 00 ]] || return 1
        code=$((16#${hex:2:2}))
        printf -v char '%b' "\\$(printf '%03o' "$code")"
        result+="$char"
        i=$((i + 4))
        ;;
      *) return 1 ;;
    esac
  done
  printf '%s' "$result"
}

state_json_scan_value() {
  local json="$1" start="$2" len=${#1} i c depth quote escaped
  while [[ $start -lt $len && "${json:start:1}" =~ [[:space:]] ]]; do start=$((start + 1)); done
  [[ $start -lt $len ]] || return 1
  c="${json:start:1}"
  if [[ "$c" == '"' ]]; then
    i=$((start + 1)); escaped=0
    while [[ $i -lt $len ]]; do
      c="${json:i:1}"
      if (( escaped )); then escaped=0
      elif [[ "$c" == \\ ]]; then escaped=1
      elif [[ "$c" == '"' ]]; then
        STATE_JSON_VALUE_RAW="${json:start:i-start+1}"
        STATE_JSON_VALUE_END=$((i + 1))
        return 0
      fi
      i=$((i + 1))
    done
    return 1
  fi
  if [[ "$c" == '{' || "$c" == '[' ]]; then
    depth=0; quote=0; escaped=0
    for ((i = start; i < len; i++)); do
      c="${json:i:1}"
      if (( quote )); then
        if (( escaped )); then escaped=0
        elif [[ "$c" == \\ ]]; then escaped=1
        elif [[ "$c" == '"' ]]; then quote=0
        fi
        continue
      fi
      if [[ "$c" == '"' ]]; then quote=1; continue; fi
      [[ "$c" == '{' || "$c" == '[' ]] && depth=$((depth + 1))
      if [[ "$c" == '}' || "$c" == ']' ]]; then
        depth=$((depth - 1))
        if (( depth == 0 )); then
          STATE_JSON_VALUE_RAW="${json:start:i-start+1}"
          STATE_JSON_VALUE_END=$((i + 1))
          return 0
        fi
      fi
    done
    return 1
  fi
  i=$start
  while [[ $i -lt $len && "${json:i:1}" != ',' && "${json:i:1}" != '}' && "${json:i:1}" != ']' ]]; do i=$((i + 1)); done
  STATE_JSON_VALUE_RAW="${json:start:i-start}"; STATE_JSON_VALUE_RAW="${STATE_JSON_VALUE_RAW%%[[:space:]]}"
  STATE_JSON_VALUE_END=$i
  [[ -n "$STATE_JSON_VALUE_RAW" ]]
}

state_json_raw_field() {
  local json="$1" key="$2" len=${#1} i=0 c token token_raw value_end
  while ((i < len)); do
    c="${json:i:1}"
    if [[ "$c" != '"' ]]; then i=$((i + 1)); continue; fi
    token_raw=''; i=$((i + 1))
    while ((i < len)); do
      c="${json:i:1}"
      if [[ "$c" == \\ ]]; then
        token_raw+="$c"; i=$((i + 1)); [[ $i -lt $len ]] || return 1; token_raw+="${json:i:1}"; i=$((i + 1)); continue
      fi
      [[ "$c" == '"' ]] && break
      token_raw+="$c"; i=$((i + 1))
    done
    [[ $i -lt $len && "${json:i:1}" == '"' ]] || return 1
    token="$(state_json_unescape "$token_raw")" || return 1
    i=$((i + 1))
    while [[ $i -lt $len && "${json:i:1}" =~ [[:space:]] ]]; do i=$((i + 1)); done
    [[ $i -lt $len && "${json:i:1}" == ':' ]] || continue
    i=$((i + 1))
    state_json_scan_value "$json" "$i" || return 1
    value_end=$STATE_JSON_VALUE_END
    if [[ "$token" == "$key" ]]; then
      printf '%s' "$STATE_JSON_VALUE_RAW"
      return 0
    fi
    i=$value_end
  done
  return 1
}

state_json_field() {
  local object="$1" path="$2" section raw
  if [[ "$path" == *.* ]]; then
    section="${path%%.*}"
    raw="$(state_json_raw_field "$object" "$section")" || return 1
    [[ "$raw" == \{*\} ]] || return 1
    state_json_field "$raw" "${path#*.}"
    return
  fi
  raw="$(state_json_raw_field "$object" "$path")" || return 1
  case "$raw" in
    null) printf 'null\n' ;;
    true|false) printf '%s\n' "$raw" ;;
    '"'*) state_json_unescape "${raw:1:${#raw}-2}"; printf '\n' ;;
    *) printf '%s\n' "$raw" ;;
  esac
}

state_json_object_field() { state_json_field "$1" "$2"; }
state_object_field() { state_json_field "$1" "$2"; }

state_operation_record() {
  local app_id="$1" file
  operation_is_valid_app_id "$app_id" || return 1
  file="$(operation_state_file_for app "$app_id")" || return 1
  [[ -f "$file" ]] || return 1
  cat "$file"
}

state_operation_field() {
  local app_id="$1" key="$2" object
  object="$(state_operation_record "$app_id")" || return 1
  state_json_field "$object" "$key"
}

state_service_object() {
  local name="$1" unit_exists=null active=null enabled=null state=unknown
  if ! command -v systemctl >/dev/null 2>&1; then
    state=unknown
  elif systemctl list-unit-files "${name}.service" --no-legend --no-pager 2>/dev/null | grep -q .; then
    unit_exists=true
    systemctl is-active --quiet "$name" 2>/dev/null && active=true || active=false
    systemctl is-enabled --quiet "$name" 2>/dev/null && enabled=true || enabled=false
    if [[ "$active" == true ]]; then state=running
    elif systemctl is-failed --quiet "$name" 2>/dev/null; then state=failed
    elif [[ "$enabled" == false ]]; then state=disabled
    else state=stopped
    fi
  else
    unit_exists=false; state=not_found
  fi
  printf '{"name":%s,"unit_exists":%s,"active":%s,"enabled":%s,"state":%s}' \
    "$(app_json_string "$name")" "$(app_json_value "$unit_exists")" \
    "$(app_json_value "$active")" "$(app_json_value "$enabled")" "$(app_json_string "$state")"
}

state_service_names() {
  local primary name
  if primary="$(app_doctor_service_name 2>/dev/null)"; then printf '%s\n' "$primary"; fi
  if [[ -n "${APP_DOCTOR_SERVICES_FN:-}" ]] && declare -f "$APP_DOCTOR_SERVICES_FN" >/dev/null 2>&1; then
    while IFS= read -r name; do
      [[ -n "$name" && "$name" != "${primary:-}" ]] && printf '%s\n' "$name"
    done < <("$APP_DOCTOR_SERVICES_FN" 2>/dev/null || true)
  fi
}

state_service_aggregate() {
  local state name found=0 has_failed=0 has_nonrunning=0 has_unknown=0
  while IFS= read -r name; do
    [[ -n "$name" ]] || continue
    found=1
    local service_json; service_json="$(state_service_object "$name")"; state="$(state_json_field "$service_json" state 2>/dev/null || true)"
    case "$state" in
      failed) has_failed=1 ;;
      running) ;;
      stopped|disabled|not_found) has_nonrunning=1 ;;
      *) has_unknown=1 ;;
    esac
  done < <(state_service_names)
  if (( ! found )); then printf '%s\n' not_managed
  elif (( has_failed )); then printf '%s\n' failed
  elif (( has_nonrunning )); then printf '%s\n' stopped
  elif (( has_unknown )); then printf '%s\n' unknown
  else printf '%s\n' running
  fi
}

state_health_url_is_local() {
  local url="$1" host
  host="${url#*://}"; host="${host%%/*}"; host="${host%%:*}"
  [[ "$host" == 127.0.0.1 || "$host" == localhost || "$host" == ::1 || "$host" == \[::1\] ]]
}

state_health_json() {
  local install_state="${1:-unknown}" service_state="${2:-unknown}" checked code output
  if [[ "$install_state" == not_installed || "$install_state" == install_failed || "$install_state" == uninstalling ]]; then
    printf '{"state":"unsupported","checked_at":null,"probe_type":null,"url":null,"http_code":null,"message":null}'
    return
  fi
  if [[ "$service_state" != running && -n "${BA_HEALTH_URL:-}" && -z "${APP_STATUS_HEALTH_FN:-}" ]]; then
    printf '{"state":"not_checked","checked_at":null,"probe_type":null,"url":%s,"http_code":null,"message":"service is not running"}' "$(app_json_string "$BA_HEALTH_URL")"
    return
  fi
  if [[ "$DEPLOY_STATUS_NO_PROBE" == 1 ]]; then
    printf '{"state":"not_checked","checked_at":null,"probe_type":null,"url":null,"http_code":null,"message":null}'
  elif [[ -n "${APP_STATUS_HEALTH_FN:-}" ]] && declare -f "$APP_STATUS_HEALTH_FN" >/dev/null 2>&1; then
    output="$("$APP_STATUS_HEALTH_FN" 2>/dev/null || true)"
    [[ "$(printf '%s\n' "$output" | wc -l)" -eq 1 && "$output" == \{*\} ]] || { printf '{"state":"unknown","checked_at":null,"probe_type":null,"url":null,"http_code":null,"message":"health probe returned invalid JSON"}'; return; }
    case "$(state_json_field "$output" state 2>/dev/null || true)" in healthy|degraded|unhealthy|not_checked|unsupported|unknown) printf '%s' "$output" ;; *) printf '{"state":"unknown","checked_at":null,"probe_type":null,"url":null,"http_code":null,"message":"health probe returned invalid state"}' ;; esac
  elif [[ -n "${BA_HEALTH_URL:-}" ]] && command -v curl >/dev/null 2>&1 && { [[ "$DEPLOY_STATUS_NO_NETWORK" != 1 ]] || state_health_url_is_local "$BA_HEALTH_URL"; }; then
    checked="$(state_now)"
    code="$(curl -sS -L --max-time "${DEPLOY_STATUS_HEALTH_TIMEOUT_SECONDS:-5}" -o /dev/null -w '%{http_code}' "$BA_HEALTH_URL" 2>/dev/null || printf 000)"
    if [[ "$code" =~ ^(2[0-9][0-9]|3[0-9][0-9])$ ]]; then
      printf '{"state":"healthy","checked_at":%s,"probe_type":"http","url":%s,"http_code":%s,"message":null}' "$(app_json_string "$checked")" "$(app_json_string "$BA_HEALTH_URL")" "$code"
    else
      printf '{"state":"unhealthy","checked_at":%s,"probe_type":"http","url":%s,"http_code":%s,"message":"HTTP health probe failed"}' "$(app_json_string "$checked")" "$(app_json_string "$BA_HEALTH_URL")" "$code"
    fi
  else
    printf '{"state":"not_checked","checked_at":null,"probe_type":null,"url":null,"http_code":null,"message":null}'
  fi
}

state_version_json() {
  local conf_file="$1" installed latest=null checked_at=null update_state=unknown source=config output
  installed="$(app_config_installed_version "$conf_file" 2>/dev/null || true)"
  [[ -n "$installed" ]] && installed="$(app_json_string "$installed")" || installed=null
  if [[ -n "${APP_STATUS_VERSION_FN:-}" ]] && declare -f "$APP_STATUS_VERSION_FN" >/dev/null 2>&1; then
    output="$("$APP_STATUS_VERSION_FN" 2>/dev/null || true)"
    if [[ "$(printf '%s\n' "$output" | wc -l)" -eq 1 && "$output" == \{*\} && -n "$(state_json_field "$output" installed 2>/dev/null || true)" ]]; then
      printf '%s' "$output"; return
    fi
  fi
  # BA_BIN_NAME is set only by implementations using the shared binary-app
  # lifecycle. Do not infer support from GITHUB_REPO alone: several custom
  # applications use GitHub for a non-comparable source/update workflow.
  if [[ -n "${BA_BIN_NAME:-}" ]] && declare -f bapp_status_version_json >/dev/null 2>&1; then
    output="$(bapp_status_version_json 2>/dev/null || true)"
    if [[ "$(printf '%s\n' "$output" | wc -l)" -eq 1 && "$output" == \{*\} && -n "$(state_json_field "$output" installed 2>/dev/null || true)" ]]; then
      printf '%s' "$output"; return
    fi
  fi
  printf '{"installed":%s,"latest":%s,"checked_at":%s,"update_state":%s,"source":%s}' "$installed" "$latest" "$checked_at" "$(app_json_string "$update_state")" "$(app_json_string "$source")"
}

state_severity() {
  local install="$1" safe="$2" valid="$3" service="$4" health="$5" update="$6" enabled="$7"
  [[ "$safe" == false || "$valid" == false ]] && { printf critical; return; }
  [[ "$install" == unknown ]] && { printf unknown; return; }
  [[ "$install" == not_installed ]] && { printf info; return; }
  [[ "$service" == failed || "$service" == stopped || "$health" == unhealthy ]] && { printf error; return; }
  [[ "$health" == degraded || "$enabled" == false || "$update" == update_available || "$update" == stale ]] && { printf warning; return; }
  printf ok
}

app_status_collect_json() {
  local conf_file config_exists=false config_safe=null config_valid=null owner=null mode=null
  local install_state=not_installed service_name="" service_state=not_managed service_enabled=null
  local health_json version_json services_json='[]' operation_state=idle
  local last_action="" last_result="" last_started="" last_finished="" last_step="" last_error_summary="" last_log_path="" last_error_code_json=null health_state="" update_state="" severity="" version_installed_json=""
  conf_file="$(app_conf_file)"
  if [[ -f "$conf_file" ]]; then
    config_exists=true; config_safe=true; install_state=installed
    if command -v stat >/dev/null 2>&1; then
      owner="$(stat -c '%U' "$conf_file" 2>/dev/null || printf unknown)"; mode="$(stat -c '%a' "$conf_file" 2>/dev/null || printf unknown)"
      [[ "$owner" == root && ( "$mode" == 600 || "$mode" == 400 ) ]] || config_safe=false
    fi
    if [[ "$config_safe" == true ]]; then app_doctor_validate_saved_config "$conf_file" >/dev/null 2>&1 && config_valid=true || config_valid=false; fi
  fi
  local service_unit_exists=null service_active=null service_systemctl=false
  if service_name="$(app_doctor_service_name 2>/dev/null)"; then
    service_state="$(state_service_aggregate)"
    local obj; obj="$(state_service_object "$service_name")"
    service_unit_exists="$(state_object_field "$obj" unit_exists || true)"
    service_active="$(state_object_field "$obj" active || true)"
    service_enabled="$(state_object_field "$obj" enabled || true)"
    command -v systemctl >/dev/null 2>&1 && service_systemctl=true
  fi
  health_json="$(state_health_json "$install_state" "$service_state" 2>/dev/null || printf '{"state":"unknown","checked_at":null,"probe_type":null,"url":null,"http_code":null,"message":"collection failed"}')"
  version_json="$(state_version_json "$conf_file")"
  if [[ -n "${APP_DOCTOR_SERVICES_FN:-}" ]] && declare -f "$APP_DOCTOR_SERVICES_FN" >/dev/null 2>&1; then
    local name first=1; services_json='['
    while IFS= read -r name; do [[ -n "$name" ]] || continue; (( first )) || services_json+=','; first=0; services_json+="$(state_service_object "$name")"; done < <("$APP_DOCTOR_SERVICES_FN" 2>/dev/null || true)
    services_json+=']'
  fi
  if [[ -n "${APP_ID:-}" ]]; then
    local operation_json=""
    operation_json="$(state_operation_record "$APP_ID" 2>/dev/null || true)"
    if [[ -n "$operation_json" ]]; then
      last_action="$(state_json_field "$operation_json" action || true)"; last_result="$(state_json_field "$operation_json" state || true)"; last_started="$(state_json_field "$operation_json" started_at || true)"; last_finished="$(state_json_field "$operation_json" finished_at || true)"; last_step="$(state_json_field "$operation_json" last_step || true)"; last_error_summary="$(state_json_field "$operation_json" error || true)"; last_log_path="$(state_json_field "$operation_json" log_path || true)"
      local operation_exit_code=""
      operation_exit_code="$(state_json_raw_field "$operation_json" exit_code 2>/dev/null || true)"
      if [[ "$operation_exit_code" =~ ^[1-9][0-9]*$ ]]; then
        last_error_code_json="$operation_exit_code"
      fi
    fi
    [[ "$last_result" == running ]] && operation_state=running
    if [[ "$last_result" == failed ]]; then
      case "$last_action" in
        install) [[ "$install_state" == not_installed ]] && install_state=install_failed ;;
        uninstall) install_state=uninstall_failed ;;
      esac
    elif [[ "$last_result" == running ]]; then
      case "$last_action" in
        install) install_state=installing ;;
        uninstall) install_state=uninstalling ;;
      esac
    fi
  fi
  health_state="$(state_json_field "$health_json" state 2>/dev/null || printf unknown)"
  update_state="$(state_json_field "$version_json" update_state 2>/dev/null || printf unknown)"
  severity="$(state_severity "$install_state" "$config_safe" "$config_valid" "$service_state" "$health_state" "$update_state" "$service_enabled")"
  version_installed_json="$(state_json_raw_field "$version_json" installed 2>/dev/null || true)"
  [[ -n "$version_installed_json" ]] || version_installed_json=null
  printf '{"schema_version":%s,"collected_at":%s,"app_id":%s,"app_name":%s,"root":%s,"install_state":%s,"severity":%s,"config":{"path":%s,"exists":%s,"owner":%s,"mode":%s,"safe":%s,"valid":%s},"version":%s,"version_info":%s,"service":{"name":%s,"systemctl_available":%s,"unit_exists":%s,"active":%s,"enabled":%s,"state":%s},"services":%s,"health":%s,"backup":{"state":"unsupported","last_success_at":null,"path":null,"message":null},"operation":{"state":%s,"last_action":%s,"last_result":%s,"last_started_at":%s,"last_finished_at":%s,"last_step":%s,"last_error_code":%s,"last_error_summary":%s,"log_path":%s}}\n' "$DEPLOY_STATE_SCHEMA_VERSION" "$(app_json_string "$(state_now)")" "$(app_json_string "${APP_ID:-}")" "$(app_json_string "${APP_NAME:-}")" "$(app_json_bool "$([[ ${EUID:-$(id -u)} -eq 0 ]] && printf true || printf false)")" "$(app_json_string "$install_state")" "$(app_json_string "$severity")" "$(app_json_string "$conf_file")" "$(app_json_bool "$config_exists")" "$(app_json_value "$owner")" "$(app_json_value "$mode")" "$(app_json_value "$config_safe")" "$(app_json_value "$config_valid")" "$version_installed_json" "$version_json" "$(state_json_nullable "$service_name")" "$(app_json_bool "$service_systemctl")" "$(app_json_value "$service_unit_exists")" "$(app_json_value "$service_active")" "$(app_json_value "$service_enabled")" "$(app_json_string "$service_state")" "$services_json" "$health_json" "$(app_json_string "$operation_state")" "$(state_json_nullable "$last_action")" "$(state_json_nullable "$last_result")" "$(state_json_nullable "$last_started")" "$(state_json_nullable "$last_finished")" "$(state_json_nullable "$last_step")" "$last_error_code_json" "$(state_json_nullable "$last_error_summary")" "$(state_json_nullable "$last_log_path")"
}





