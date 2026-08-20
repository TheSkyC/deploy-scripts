#!/usr/bin/env bash

MANAGER_UPDATE_USAGE="Usage: deploy.sh check-update [--json] [--refresh|--no-network] [--include id,id,...] [--exclude id,id,...]"

manager_update_print_usage() { echo "$MANAGER_UPDATE_USAGE" >&2; }

manager_update_record() {
  local app_id="$1" app_name="$2" install_state="$3" state="$4" reason="$5" version_json="$6"
  printf '{"app_id":%s,"app_name":%s,"install_state":%s,"state":%s,"reason":%s,"version":%s}' \
    "$(app_json_string "$app_id")" "$(app_json_string "$app_name")" \
    "$(app_json_string "$install_state")" "$(app_json_string "$state")" \
    "$(state_json_nullable "$reason")" "$version_json"
}

manager_update_unsupported_version_json() {
  local installed="$1" reason="$2"
  version_check_emit_json "$installed" "" "" unsupported config unsupported "$reason"
}

# All application loading happens in a subshell. Implementations set global
# defaults and hooks, and isolation prevents one application's BA_* settings
# from being mistaken for another application's capability.
manager_update_check_app_version() {
  local app_id="$1" installed="$2" refresh="$3" no_network="$4"
  manager_load_app "$app_id" || return 1
  if [[ -z "${BA_BIN_NAME:-}" ]] || ! declare -f bapp_check_update_json >/dev/null 2>&1; then
    manager_update_unsupported_version_json "$installed" "version checking is not supported"
    return 0
  fi
  bapp_check_update_json "$installed" "$refresh" "$no_network"
}

manager_update_main() {
  local json=0 refresh=0 no_network=0 include_csv="" exclude_csv="" arg selected app_id app_name
  local state_file err_file install_state config_safe installed version_json update_state record_state reason collection_error
  local installed_count=0 update_available=0 up_to_date=0 unsupported=0 unknown=0 stale=0 check_failed=0 errors=0
  local -a ids=() records=()
  while (($#)); do
    arg="$1"; shift
    case "$arg" in
      --json) json=1 ;;
      --refresh) refresh=1 ;;
      --no-network) no_network=1 ;;
      --include) (($#)) || { manager_update_print_usage; return 2; }; include_csv="$1"; shift ;;
      --exclude) (($#)) || { manager_update_print_usage; return 2; }; exclude_csv="$1"; shift ;;
      --include=*) include_csv="${arg#*=}" ;;
      --exclude=*) exclude_csv="${arg#*=}" ;;
      --only-installed|--continue-on-error) ;;
      --help|-h) manager_update_print_usage; return 0 ;;
      *) manager_update_print_usage; return 2 ;;
    esac
  done
  (( refresh && no_network )) && { manager_update_print_usage; return 2; }
  if ! selected="$(manager_status_selected_ids "$include_csv" "$exclude_csv")"; then return 2; fi
  [[ -n "$selected" ]] && mapfile -t ids < <(printf '%s\n' "$selected")

  for app_id in "${ids[@]}"; do
    app_name="$(deploy_app_name_for "$app_id")"
    state_file="$(mktemp)"; err_file="$(mktemp)"
    if ! manager_status_collect_app_json "$app_id" "$state_file" "$err_file"; then
      collection_error="$(tr '\n' ' ' < "$err_file" 2>/dev/null || true)"
      version_json="$(version_check_emit_json "" "" "" check_failed config miss "$collection_error")"
      records+=("$(manager_update_record "$app_id" "$app_name" unknown error status_collection_failed "$version_json")")
      errors=$((errors + 1))
      rm -f "$state_file" "$err_file"
      continue
    fi
    install_state="$(manager_status_json_field "$state_file" install_state 2>/dev/null || printf unknown)"
    if [[ "$install_state" != installed ]]; then
      version_json="$(manager_update_unsupported_version_json "" "application is not installed")"
      records+=("$(manager_update_record "$app_id" "$app_name" "$install_state" skipped not_installed "$version_json")")
      rm -f "$state_file" "$err_file"
      continue
    fi
    installed_count=$((installed_count + 1))
    config_safe="$(manager_status_json_field "$state_file" config.safe 2>/dev/null || printf false)"
    installed="$(manager_status_json_field "$state_file" version.installed 2>/dev/null || true)"
    [[ "$installed" == null ]] && installed=""
    if [[ "$config_safe" != true ]]; then
      version_json="$(version_check_emit_json "$installed" "" "" unknown config blocked "managed configuration is unsafe")"
      records+=("$(manager_update_record "$app_id" "$app_name" "$install_state" skipped unsafe_config "$version_json")")
      unknown=$((unknown + 1))
      rm -f "$state_file" "$err_file"
      continue
    fi
    if version_json="$(manager_update_check_app_version "$app_id" "$installed" "$refresh" "$no_network" 2>"$err_file")"; then
      update_state="$(state_json_field "$version_json" update_state 2>/dev/null || printf check_failed)"
      reason=""
      record_state=checked
      case "$update_state" in
        update_available) update_available=$((update_available + 1)) ;;
        up_to_date) up_to_date=$((up_to_date + 1)) ;;
        unsupported) unsupported=$((unsupported + 1)); record_state=skipped; reason=unsupported ;;
        stale) stale=$((stale + 1)) ;;
        unknown) unknown=$((unknown + 1)) ;;
        check_failed) check_failed=$((check_failed + 1)); record_state=error; reason=release_check_failed ;;
        *) check_failed=$((check_failed + 1)); record_state=error; reason=invalid_version_result ;;
      esac
      records+=("$(manager_update_record "$app_id" "$app_name" "$install_state" "$record_state" "$reason" "$version_json")")
    else
      collection_error="$(tr '\n' ' ' < "$err_file" 2>/dev/null || true)"
      version_json="$(version_check_emit_json "$installed" "" "" check_failed config miss "$collection_error")"
      records+=("$(manager_update_record "$app_id" "$app_name" "$install_state" error version_adapter_failed "$version_json")")
      errors=$((errors + 1))
    fi
    rm -f "$state_file" "$err_file"
  done

  if (( json )); then
    local first=1 record
    printf '{"schema_version":1,"generated_at":%s,"refresh":%s,"no_network":%s,"summary":{"selected":%s,"installed":%s,"update_available":%s,"up_to_date":%s,"unsupported":%s,"unknown":%s,"stale":%s,"check_failed":%s,"errors":%s},"records":[' \
      "$(app_json_string "$(state_now)")" "$([[ "$refresh" == 1 ]] && printf true || printf false)" "$([[ "$no_network" == 1 ]] && printf true || printf false)" \
      "${#ids[@]}" "$installed_count" "$update_available" "$up_to_date" "$unsupported" "$unknown" "$stale" "$check_failed" "$errors"
    for record in "${records[@]}"; do (( first )) || printf ','; first=0; printf '%s' "$record"; done
    printf ']}\n'
  else
    printf 'check-update: selected=%s installed=%s update_available=%s up_to_date=%s unsupported=%s unknown=%s stale=%s check_failed=%s errors=%s\n' \
      "${#ids[@]}" "$installed_count" "$update_available" "$up_to_date" "$unsupported" "$unknown" "$stale" "$check_failed" "$errors"
    printf '%-16s %-12s %-18s %-18s %s\n' App State Update Cache Reason
    for record in "${records[@]}"; do
      printf '%-16s %-12s %-18s %-18s %s\n' \
        "$(state_json_field "$record" app_id)" "$(state_json_field "$record" state)" \
        "$(state_json_field "$record" version.update_state)" "$(state_json_field "$record" version.cache_state)" \
        "$(state_json_field "$record" reason)"
    done
  fi
  (( errors == 0 )) || return 1
  (( check_failed == 0 )) || return 10
}