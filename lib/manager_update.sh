#!/usr/bin/env bash

MANAGER_UPDATE_USAGE="Usage: deploy.sh check-update [--json] [--refresh|--no-network] [--include id,id,...] [--exclude id,id,...]"
MANAGER_UPDATE_ALL_USAGE="Usage: deploy.sh update-all --dry-run [--json] [--refresh|--no-network] [--include id,id,...] [--exclude id,id,...]"

manager_update_print_usage() { echo "$MANAGER_UPDATE_USAGE" >&2; }
manager_update_all_print_usage() { echo "$MANAGER_UPDATE_ALL_USAGE" >&2; }

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

# Populate a reusable, stable assessment for check-update and update-all
# planning. This is intentionally serial: GitHub API requests should not burst
# across all apps, and the later write path must remain deterministic.
manager_update_collect() {
  local refresh="$1" no_network="$2" include_csv="$3" exclude_csv="$4"
  local selected app_id app_name state_file err_file install_state config_safe installed version_json update_state record_state reason collection_error
  MANAGER_UPDATE_SELECTED=0
  MANAGER_UPDATE_INSTALLED=0
  MANAGER_UPDATE_AVAILABLE=0
  MANAGER_UPDATE_CURRENT=0
  MANAGER_UPDATE_UNSUPPORTED=0
  MANAGER_UPDATE_UNKNOWN=0
  MANAGER_UPDATE_STALE=0
  MANAGER_UPDATE_CHECK_FAILED=0
  MANAGER_UPDATE_ERRORS=0
  MANAGER_UPDATE_RECORDS=()
  local -a ids=()

  if ! selected="$(manager_status_selected_ids "$include_csv" "$exclude_csv")"; then return 2; fi
  [[ -n "$selected" ]] && mapfile -t ids < <(printf '%s\n' "$selected")
  MANAGER_UPDATE_SELECTED="${#ids[@]}"
  for app_id in "${ids[@]}"; do
    app_name="$(deploy_app_name_for "$app_id")"
    state_file="$(mktemp)"; err_file="$(mktemp)"
    if ! manager_status_collect_app_json "$app_id" "$state_file" "$err_file"; then
      collection_error="$(tr '\n' ' ' < "$err_file" 2>/dev/null || true)"
      version_json="$(version_check_emit_json "" "" "" check_failed config miss "$collection_error")"
      MANAGER_UPDATE_RECORDS+=("$(manager_update_record "$app_id" "$app_name" unknown error status_collection_failed "$version_json")")
      MANAGER_UPDATE_ERRORS=$((MANAGER_UPDATE_ERRORS + 1))
      rm -f "$state_file" "$err_file"
      continue
    fi
    install_state="$(manager_status_json_field "$state_file" install_state 2>/dev/null || printf unknown)"
    if [[ "$install_state" != installed ]]; then
      version_json="$(manager_update_unsupported_version_json "" "application is not installed")"
      MANAGER_UPDATE_RECORDS+=("$(manager_update_record "$app_id" "$app_name" "$install_state" skipped not_installed "$version_json")")
      rm -f "$state_file" "$err_file"
      continue
    fi
    MANAGER_UPDATE_INSTALLED=$((MANAGER_UPDATE_INSTALLED + 1))
    config_safe="$(manager_status_json_field "$state_file" config.safe 2>/dev/null || printf false)"
    installed="$(manager_status_json_field "$state_file" version.installed 2>/dev/null || true)"
    [[ "$installed" == null ]] && installed=""
    if [[ "$config_safe" != true ]]; then
      version_json="$(version_check_emit_json "$installed" "" "" unknown config blocked "managed configuration is unsafe")"
      MANAGER_UPDATE_RECORDS+=("$(manager_update_record "$app_id" "$app_name" "$install_state" skipped unsafe_config "$version_json")")
      MANAGER_UPDATE_UNKNOWN=$((MANAGER_UPDATE_UNKNOWN + 1))
      rm -f "$state_file" "$err_file"
      continue
    fi
    if version_json="$(manager_update_check_app_version "$app_id" "$installed" "$refresh" "$no_network" 2>"$err_file")"; then
      update_state="$(state_json_field "$version_json" update_state 2>/dev/null || printf check_failed)"
      reason=""
      record_state=checked
      case "$update_state" in
        update_available) MANAGER_UPDATE_AVAILABLE=$((MANAGER_UPDATE_AVAILABLE + 1)) ;;
        up_to_date) MANAGER_UPDATE_CURRENT=$((MANAGER_UPDATE_CURRENT + 1)) ;;
        unsupported) MANAGER_UPDATE_UNSUPPORTED=$((MANAGER_UPDATE_UNSUPPORTED + 1)); record_state=skipped; reason=unsupported ;;
        stale) MANAGER_UPDATE_STALE=$((MANAGER_UPDATE_STALE + 1)) ;;
        unknown) MANAGER_UPDATE_UNKNOWN=$((MANAGER_UPDATE_UNKNOWN + 1)) ;;
        check_failed) MANAGER_UPDATE_CHECK_FAILED=$((MANAGER_UPDATE_CHECK_FAILED + 1)); record_state=error; reason=release_check_failed ;;
        *) MANAGER_UPDATE_CHECK_FAILED=$((MANAGER_UPDATE_CHECK_FAILED + 1)); record_state=error; reason=invalid_version_result ;;
      esac
      MANAGER_UPDATE_RECORDS+=("$(manager_update_record "$app_id" "$app_name" "$install_state" "$record_state" "$reason" "$version_json")")
    else
      collection_error="$(tr '\n' ' ' < "$err_file" 2>/dev/null || true)"
      version_json="$(version_check_emit_json "$installed" "" "" check_failed config miss "$collection_error")"
      MANAGER_UPDATE_RECORDS+=("$(manager_update_record "$app_id" "$app_name" "$install_state" error version_adapter_failed "$version_json")")
      MANAGER_UPDATE_ERRORS=$((MANAGER_UPDATE_ERRORS + 1))
    fi
    rm -f "$state_file" "$err_file"
  done
}

manager_update_collect_status() {
  (( MANAGER_UPDATE_ERRORS == 0 )) || return 1
  (( MANAGER_UPDATE_CHECK_FAILED == 0 )) || return 10
  return 0
}

manager_update_render_check_json() {
  local refresh="$1" no_network="$2" first=1 record
  printf '{"schema_version":1,"generated_at":%s,"refresh":%s,"no_network":%s,"summary":{"selected":%s,"installed":%s,"update_available":%s,"up_to_date":%s,"unsupported":%s,"unknown":%s,"stale":%s,"check_failed":%s,"errors":%s},"records":[' \
    "$(app_json_string "$(state_now)")" "$([[ "$refresh" == 1 ]] && printf true || printf false)" "$([[ "$no_network" == 1 ]] && printf true || printf false)" \
    "$MANAGER_UPDATE_SELECTED" "$MANAGER_UPDATE_INSTALLED" "$MANAGER_UPDATE_AVAILABLE" "$MANAGER_UPDATE_CURRENT" "$MANAGER_UPDATE_UNSUPPORTED" "$MANAGER_UPDATE_UNKNOWN" "$MANAGER_UPDATE_STALE" "$MANAGER_UPDATE_CHECK_FAILED" "$MANAGER_UPDATE_ERRORS"
  for record in "${MANAGER_UPDATE_RECORDS[@]}"; do (( first )) || printf ','; first=0; printf '%s' "$record"; done
  printf ']}\n'
}

manager_update_render_check_table() {
  local record
  printf 'check-update: selected=%s installed=%s update_available=%s up_to_date=%s unsupported=%s unknown=%s stale=%s check_failed=%s errors=%s\n' \
    "$MANAGER_UPDATE_SELECTED" "$MANAGER_UPDATE_INSTALLED" "$MANAGER_UPDATE_AVAILABLE" "$MANAGER_UPDATE_CURRENT" "$MANAGER_UPDATE_UNSUPPORTED" "$MANAGER_UPDATE_UNKNOWN" "$MANAGER_UPDATE_STALE" "$MANAGER_UPDATE_CHECK_FAILED" "$MANAGER_UPDATE_ERRORS"
  printf '%-16s %-12s %-18s %-18s %s\n' App State Update Cache Reason
  for record in "${MANAGER_UPDATE_RECORDS[@]}"; do
    printf '%-16s %-12s %-18s %-18s %s\n' \
      "$(state_json_field "$record" app_id)" "$(state_json_field "$record" state)" \
      "$(state_json_field "$record" version.update_state)" "$(state_json_field "$record" version.cache_state)" \
      "$(state_json_field "$record" reason)"
  done
}

manager_update_main() {
  local json=0 refresh=0 no_network=0 include_csv="" exclude_csv="" arg
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
  manager_update_collect "$refresh" "$no_network" "$include_csv" "$exclude_csv" || return $?
  if (( json )); then manager_update_render_check_json "$refresh" "$no_network"; else manager_update_render_check_table; fi
  manager_update_collect_status
}

manager_update_plan_record() {
  local record="$1" app_id app_name install_state state reason version_json action
  app_id="$(state_json_field "$record" app_id)"
  app_name="$(state_json_field "$record" app_name)"
  install_state="$(state_json_field "$record" install_state)"
  state="$(state_json_field "$record" state)"
  reason="$(state_json_field "$record" reason)"
  version_json="$(state_json_raw_field "$record" version)" || return 1
  if [[ "$install_state" == installed && "$state" == checked && "$(state_json_field "$record" version.update_state)" == update_available ]]; then
    action=plan
    reason=update_available
  else
    action=skip
    [[ -n "$reason" && "$reason" != null ]] || reason="$(state_json_field "$record" version.update_state)"
  fi
  printf '{"app_id":%s,"app_name":%s,"install_state":%s,"action":%s,"reason":%s,"version":%s}' \
    "$(app_json_string "$app_id")" "$(app_json_string "$app_name")" "$(app_json_string "$install_state")" \
    "$(app_json_string "$action")" "$(app_json_string "$reason")" "$version_json"
}

manager_update_all_main() {
  local dry_run=0 json=0 refresh=0 no_network=0 include_csv="" exclude_csv="" arg record plan_record action
  local planned=0 skipped=0 first=1 status
  local -a plan_records=()
  while (($#)); do
    arg="$1"; shift
    case "$arg" in
      --dry-run) dry_run=1 ;;
      --json) json=1 ;;
      --refresh) refresh=1 ;;
      --no-network) no_network=1 ;;
      --include) (($#)) || { manager_update_all_print_usage; return 2; }; include_csv="$1"; shift ;;
      --exclude) (($#)) || { manager_update_all_print_usage; return 2; }; exclude_csv="$1"; shift ;;
      --include=*) include_csv="${arg#*=}" ;;
      --exclude=*) exclude_csv="${arg#*=}" ;;
      --only-installed|--continue-on-error) ;;
      --help|-h) manager_update_all_print_usage; return 0 ;;
      *) manager_update_all_print_usage; return 2 ;;
    esac
  done
  (( dry_run )) || { echo 'update-all currently requires --dry-run; direct update execution is not enabled yet.' >&2; return 2; }
  (( refresh && no_network )) && { manager_update_all_print_usage; return 2; }
  set +e
  manager_update_collect "$refresh" "$no_network" "$include_csv" "$exclude_csv"
  status=$?
  set -e
  (( status == 0 )) || return "$status"
  for record in "${MANAGER_UPDATE_RECORDS[@]}"; do
    plan_record="$(manager_update_plan_record "$record")" || return 1
    action="$(state_json_field "$plan_record" action)"
    [[ "$action" == plan ]] && planned=$((planned + 1)) || skipped=$((skipped + 1))
    plan_records+=("$plan_record")
  done
  if (( json )); then
    printf '{"schema_version":1,"generated_at":%s,"dry_run":true,"refresh":%s,"no_network":%s,"summary":{"selected":%s,"planned":%s,"skipped":%s,"check_failed":%s,"errors":%s},"records":[' \
      "$(app_json_string "$(state_now)")" "$([[ "$refresh" == 1 ]] && printf true || printf false)" "$([[ "$no_network" == 1 ]] && printf true || printf false)" \
      "$MANAGER_UPDATE_SELECTED" "$planned" "$skipped" "$MANAGER_UPDATE_CHECK_FAILED" "$MANAGER_UPDATE_ERRORS"
    for plan_record in "${plan_records[@]}"; do (( first )) || printf ','; first=0; printf '%s' "$plan_record"; done
    printf ']}\n'
  else
    printf 'update-all dry-run: selected=%s planned=%s skipped=%s check_failed=%s errors=%s\n' \
      "$MANAGER_UPDATE_SELECTED" "$planned" "$skipped" "$MANAGER_UPDATE_CHECK_FAILED" "$MANAGER_UPDATE_ERRORS"
    printf '%-16s %-10s %-18s %s\n' App Action Update Reason
    for plan_record in "${plan_records[@]}"; do
      printf '%-16s %-10s %-18s %s\n' \
        "$(state_json_field "$plan_record" app_id)" "$(state_json_field "$plan_record" action)" \
        "$(state_json_field "$plan_record" version.update_state)" "$(state_json_field "$plan_record" reason)"
    done
  fi
  manager_update_collect_status
}