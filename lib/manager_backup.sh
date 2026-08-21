#!/usr/bin/env bash

MANAGER_BACKUP_USAGE="Usage: deploy.sh backup-all --dry-run [--json] [--include id,id,...] [--exclude id,id,...]"

manager_backup_print_usage() { echo "$MANAGER_BACKUP_USAGE" >&2; }

manager_backup_capability() {
  local app_id="$1" body
  manager_load_app "$app_id" || return 1
  load_app_impl || return 1
  if ! declare -f do_backup >/dev/null 2>&1; then
    printf unsupported
    return 0
  fi
  body="$(declare -f do_backup)"
  if [[ "$body" == *unsupported_action* ]]; then
    printf unsupported
  else
    printf supported
  fi
}

manager_backup_record() {
  local app_id="$1" install_state="$2" capability="$3" action="$4" reason="${5:-}" error_summary="${6:-}"
  printf '{"app_id":%s,"install_state":%s,"backup":%s,"action":%s,"reason":%s,"error":%s}' \
    "$(app_json_string "$app_id")" "$(app_json_string "$install_state")" \
    "$(app_json_string "$capability")" "$(app_json_string "$action")" \
    "$(state_json_nullable "$reason")" "$(state_json_nullable "$(operation_safe_summary "$error_summary")")"
}

manager_backup_main() {
  local dry_run=0 json=0 include_csv="" exclude_csv="" arg selected app_id state_file err_file install_state capability collection_error
  local planned=0 skipped=0 errors=0
  local -a ids=() records=()
  while (($#)); do
    arg="$1"; shift
    case "$arg" in
      --dry-run) dry_run=1 ;;
      --json) json=1 ;;
      --include) (($#)) || { manager_backup_print_usage; return 2; }; include_csv="$1"; shift ;;
      --exclude) (($#)) || { manager_backup_print_usage; return 2; }; exclude_csv="$1"; shift ;;
      --include=*) include_csv="${arg#*=}" ;;
      --exclude=*) exclude_csv="${arg#*=}" ;;
      --help|-h) manager_backup_print_usage; return 0 ;;
      *) manager_backup_print_usage; return 2 ;;
    esac
  done
  (( dry_run )) || { echo 'backup-all currently requires --dry-run; direct backup execution is not enabled yet.' >&2; return 2; }
  if ! selected="$(manager_status_selected_ids "$include_csv" "$exclude_csv")"; then return 2; fi
  [[ -n "$selected" ]] && mapfile -t ids < <(printf '%s\n' "$selected")

  for app_id in "${ids[@]}"; do
    state_file="$(mktemp)"; err_file="$(mktemp)"
    # Target selection is a local read-only pass. Do not run health probes or
    # remote checks here; the batch action itself decides what to execute.
    if ! ( DEPLOY_STATUS_NO_PROBE=1 DEPLOY_STATUS_NO_NETWORK=1
           manager_status_collect_app_json "$app_id" "$state_file" "$err_file" ); then
      collection_error="$(tr '\n' ' ' < "$err_file" 2>/dev/null || true)"
      records+=("$(manager_backup_record "$app_id" unknown unknown error collection_failed "$collection_error")")
      errors=$((errors + 1))
      rm -f "$state_file" "$err_file"
      continue
    fi
    install_state="$(manager_status_json_field "$state_file" install_state 2>/dev/null || printf unknown)"
    if [[ "$install_state" != installed ]]; then
      records+=("$(manager_backup_record "$app_id" "$install_state" unsupported skip not_installed)")
      skipped=$((skipped + 1))
      rm -f "$state_file" "$err_file"
      continue
    fi
    if capability="$(manager_backup_capability "$app_id" 2>/dev/null)" && [[ "$capability" == supported || "$capability" == unsupported ]]; then
      if [[ "$capability" == supported ]]; then
        planned=$((planned + 1))
        records+=("$(manager_backup_record "$app_id" "$install_state" "$capability" plan supported)")
      else
        skipped=$((skipped + 1))
        records+=("$(manager_backup_record "$app_id" "$install_state" "$capability" skip unsupported)")
      fi
    else
      collection_error="backup capability detection failed"
      records+=("$(manager_backup_record "$app_id" "$install_state" unknown error capability_failed "$collection_error")")
      errors=$((errors + 1))
    fi
    rm -f "$state_file" "$err_file"
  done

  if (( json )); then
    local first=1 record
    printf '{"schema_version":1,"generated_at":%s,"dry_run":true,"summary":{"selected":%s,"planned":%s,"skipped":%s,"errors":%s},"records":[' \
      "$(app_json_string "$(state_now)")" "${#ids[@]}" "$planned" "$skipped" "$errors"
    for record in "${records[@]}"; do (( first )) || printf ','; first=0; printf '%s' "$record"; done
    printf ']}\n'
  else
    printf 'backup-all dry-run: selected=%s planned=%s skipped=%s errors=%s\n' "${#ids[@]}" "$planned" "$skipped" "$errors"
    for record in "${records[@]}"; do printf '%s\n' "$record"; done
  fi
  (( errors == 0 )) || return 1
}
