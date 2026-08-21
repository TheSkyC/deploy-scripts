#!/usr/bin/env bash

MANAGER_BACKUP_USAGE="Usage: deploy.sh backup-all [--dry-run] [--yes] [--json] [--include id,id,...] [--exclude id,id,...]"

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
  local app_id="$1" install_state="$2" capability="$3" action="$4" reason="${5:-}" error_summary="${6:-}" status="${7:-}"
  local status_json=null
  [[ "$status" =~ ^[0-9]+$ ]] && status_json="$status"
  printf '{"app_id":%s,"install_state":%s,"backup":%s,"action":%s,"reason":%s,"status":%s,"error":%s}' \
    "$(app_json_string "$app_id")" "$(app_json_string "$install_state")" \
    "$(app_json_string "$capability")" "$(app_json_string "$action")" \
    "$(state_json_nullable "$reason")" "$status_json" \
    "$(state_json_nullable "$(operation_safe_summary "$error_summary")")"
}

manager_backup_confirm() {
  local yes="$1" planned="$2" answer
  [[ "$yes" == 1 || "${DEPLOY_ASSUME_YES:-0}" == 1 ]] && return 0
  if [[ ! -t 0 ]]; then
    echo 'backup-all requires --yes or DEPLOY_ASSUME_YES=1 when standard input is not interactive.' >&2
    return 2
  fi
  printf 'Backup %s application(s)? [y/N] ' "$planned" >&2
  read -r answer
  [[ "${answer,,}" == y || "${answer,,}" == yes ]]
}

manager_backup_operation_log() {
  [[ "${MANAGER_BACKUP_OPERATION_ACTIVE:-0}" == 1 ]] || return 0
  operation_redact_line "$1" >>"$OPERATION_LOG_PATH" || true
}

manager_backup_operation_exit_handler() {
  local status=$?
  [[ "${MANAGER_BACKUP_OPERATION_ACTIVE:-0}" == 1 ]] || return 0
  MANAGER_BACKUP_OPERATION_ACTIVE=0
  operation_step_finish execute failed >/dev/null 2>&1 || true
  operation_finish "$status" "" "backup-all exited with status ${status}" >/dev/null 2>&1 || true
}

manager_backup_operation_start() {
  operation_start manager "" backup-all || return 1
  operation_step_start execute >/dev/null 2>&1 || {
    operation_finish 1 failed "failed to start execute step" >/dev/null 2>&1 || true
    return 1
  }
  MANAGER_BACKUP_OPERATION_ACTIVE=1
  deploy_add_exit_handler manager_backup_operation_exit_handler
  manager_backup_operation_log "backup-all started planned=${MANAGER_BACKUP_PLANNED:-0}"
}

manager_backup_operation_finish() {
  local status="$1" summary="${2:-}"
  [[ "${MANAGER_BACKUP_OPERATION_ACTIVE:-0}" == 1 ]] || return 0
  MANAGER_BACKUP_OPERATION_ACTIVE=0
  if (( status == 0 )); then
    operation_step_finish execute succeeded >/dev/null 2>&1 || true
  else
    operation_step_finish execute failed >/dev/null 2>&1 || true
  fi
  operation_finish "$status" "" "$summary" >/dev/null 2>&1 || true
}

manager_backup_execute_app() {
  local app_id="$1"
  manager_load_app "$app_id"
  dispatch_action backup
}

manager_backup_main() {
  local dry_run=0 json=0 yes=0 include_csv="" exclude_csv="" arg selected app_id state_file err_file install_state capability collection_error
  local planned=0 skipped=0 errors=0 updated=0 failed=0 status=0 first=1 record plan_record action
  local -a ids=() records=() plan_records=()
  while (($#)); do
    arg="$1"; shift
    case "$arg" in
      --dry-run) dry_run=1 ;;
      --yes) yes=1 ;;
      --json) json=1 ;;
      --include) (($#)) || { manager_backup_print_usage; return 2; }; include_csv="$1"; shift ;;
      --exclude) (($#)) || { manager_backup_print_usage; return 2; }; exclude_csv="$1"; shift ;;
      --include=*) include_csv="${arg#*=}" ;;
      --exclude=*) exclude_csv="${arg#*=}" ;;
      --help|-h) manager_backup_print_usage; return 0 ;;
      *) manager_backup_print_usage; return 2 ;;
    esac
  done
  if ! selected="$(manager_status_selected_ids "$include_csv" "$exclude_csv")"; then return 2; fi
  [[ -n "$selected" ]] && mapfile -t ids < <(printf '%s\n' "$selected")

  for app_id in "${ids[@]}"; do
    state_file="$(mktemp)"; err_file="$(mktemp)"
    if ! ( DEPLOY_STATUS_NO_PROBE=1 DEPLOY_STATUS_NO_NETWORK=1
           manager_status_collect_app_json "$app_id" "$state_file" "$err_file" ); then
      collection_error="$(tr '\n' ' ' < "$err_file" 2>/dev/null || true)"
      plan_records+=("$(manager_backup_record "$app_id" unknown unknown error collection_failed "$collection_error")")
      errors=$((errors + 1))
      rm -f "$state_file" "$err_file"
      continue
    fi
    install_state="$(manager_status_json_field "$state_file" install_state 2>/dev/null || printf unknown)"
    if [[ "$install_state" != installed ]]; then
      plan_records+=("$(manager_backup_record "$app_id" "$install_state" unsupported skip not_installed)")
      skipped=$((skipped + 1))
      rm -f "$state_file" "$err_file"
      continue
    fi
    if capability="$(manager_backup_capability "$app_id" 2>/dev/null)" && [[ "$capability" == supported || "$capability" == unsupported ]]; then
      if [[ "$capability" == supported ]]; then
        planned=$((planned + 1))
        plan_records+=("$(manager_backup_record "$app_id" "$install_state" "$capability" plan supported)")
      else
        skipped=$((skipped + 1))
        plan_records+=("$(manager_backup_record "$app_id" "$install_state" "$capability" skip unsupported)")
      fi
    else
      collection_error="backup capability detection failed"
      plan_records+=("$(manager_backup_record "$app_id" "$install_state" unknown error capability_failed "$collection_error")")
      errors=$((errors + 1))
    fi
    rm -f "$state_file" "$err_file"
  done

  if (( dry_run )); then
    if (( json )); then
      printf '{"schema_version":1,"generated_at":%s,"dry_run":true,"summary":{"selected":%s,"planned":%s,"skipped":%s,"errors":%s},"records":[' \
        "$(app_json_string "$(state_now)")" "${#ids[@]}" "$planned" "$skipped" "$errors"
      for record in "${plan_records[@]}"; do (( first )) || printf ','; first=0; printf '%s' "$record"; done
      printf ']}\n'
    else
      printf 'backup-all dry-run: selected=%s planned=%s skipped=%s errors=%s\n' "${#ids[@]}" "$planned" "$skipped" "$errors"
      for record in "${plan_records[@]}"; do printf '%s\n' "$record"; done
    fi
    (( errors == 0 )) || return 1
    return 0
  fi

  if (( planned > 0 )); then
    if (( json )) && [[ "$yes" != 1 && "${DEPLOY_ASSUME_YES:-0}" != 1 ]]; then
      echo 'backup-all --json with planned backups requires --yes or DEPLOY_ASSUME_YES=1.' >&2
      return 2
    fi
    manager_backup_confirm "$yes" "$planned" || return $?
    manager_update_acquire_lock
    status=$?
    if (( status != 0 )); then
      echo 'Unable to acquire the manager backup lock.' >&2
      return "$status"
    fi
    MANAGER_BACKUP_PLANNED="$planned"
    manager_backup_operation_start || {
      manager_update_release_lock
      echo 'Unable to start manager backup operation record.' >&2
      return 1
    }
  fi

  for plan_record in "${plan_records[@]}"; do
    action="$(state_json_field "$plan_record" action)"
    if [[ "$action" != plan ]]; then
      records+=("$plan_record")
      continue
    fi
    app_id="$(state_json_field "$plan_record" app_id)"
    if (( json )); then
      if ( manager_backup_execute_app "$app_id" ) >&2; then status=0; else status=$?; fi
    else
      printf '\n== Backing up %s ==\n' "$app_id"
      if ( manager_backup_execute_app "$app_id" ); then status=0; else status=$?; fi
    fi
    if (( status == 0 )); then
      updated=$((updated + 1))
      records+=("$(manager_backup_record "$app_id" installed supported succeeded completed "" "$status")")
      manager_backup_operation_log "app=${app_id} state=succeeded status=${status}"
    else
      failed=$((failed + 1))
      records+=("$(manager_backup_record "$app_id" installed supported failed backup_failed "$status" "$status")")
      manager_backup_operation_log "app=${app_id} state=failed status=${status}"
    fi
  done
  (( planned > 0 )) && manager_update_release_lock
  if (( failed == 0 && errors == 0 )); then
    manager_backup_operation_finish 0 "backup-all completed successfully"
  else
    manager_backup_operation_finish 1 "backup-all completed with ${failed} failed application(s)"
  fi

  if (( json )); then
    first=1
    printf '{"schema_version":1,"generated_at":%s,"dry_run":false,"summary":{"selected":%s,"planned":%s,"updated":%s,"failed":%s,"skipped":%s,"errors":%s},"records":[' \
      "$(app_json_string "$(state_now)")" "${#ids[@]}" "$planned" "$updated" "$failed" "$skipped" "$errors"
    for record in "${records[@]}"; do (( first )) || printf ','; first=0; printf '%s' "$record"; done
    printf ']}\n'
  else
    printf '\nbackup-all: selected=%s planned=%s completed=%s failed=%s skipped=%s errors=%s\n' \
      "${#ids[@]}" "$planned" "$updated" "$failed" "$skipped" "$errors"
  fi
  (( failed == 0 && errors == 0 )) || return 1
}
