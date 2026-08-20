#!/usr/bin/env bash

MANAGER_HISTORY_USAGE="Usage: deploy.sh history [app-id] [--json] [--limit N]"

manager_history_print_usage() { echo "$MANAGER_HISTORY_USAGE" >&2; }

manager_history_validate_app() {
  local app_id="$1"
  [[ -z "$app_id" ]] && return 0
  deploy_app_offset_for "$app_id" >/dev/null 2>&1
}

manager_history_raw_or_null() {
  local record="$1" field="$2" raw
  raw="$(state_json_raw_field "$record" "$field" 2>/dev/null || true)"
  [[ -n "$raw" ]] && printf '%s' "$raw" || printf 'null'
}

manager_history_record_json() {
  local record="$1" expected_app="${2:-}" app_id scope run_id action state started_at finished_at exit_code error log_path
  app_id="$(state_json_field "$record" app_id 2>/dev/null || true)"
  [[ -z "$expected_app" || "$app_id" == "$expected_app" ]] || return 3
  scope="$(state_json_field "$record" scope 2>/dev/null || true)"
  run_id="$(state_json_field "$record" run_id 2>/dev/null || true)"
  action="$(state_json_field "$record" action 2>/dev/null || true)"
  state="$(state_json_field "$record" state 2>/dev/null || true)"
  started_at="$(state_json_field "$record" started_at 2>/dev/null || true)"
  [[ -n "$scope" && -n "$run_id" && -n "$action" && -n "$state" && -n "$started_at" ]] || return 1
  finished_at="$(state_json_field "$record" finished_at 2>/dev/null || true)"
  exit_code="$(manager_history_raw_or_null "$record" exit_code)"
  [[ "$exit_code" =~ ^[0-9]+$ ]] || exit_code=null
  error="$(state_json_field "$record" error 2>/dev/null || true)"
  log_path="$(state_json_field "$record" log_path 2>/dev/null || true)"
  printf '{"run_id":%s,"scope":%s,"app_id":%s,"action":%s,"state":%s,"started_at":%s,"finished_at":%s,"exit_code":%s,"error":%s,"log_path":%s}\n' \
    "$(app_json_string "$run_id")" "$(app_json_string "$scope")" "$(state_json_nullable "$app_id")" \
    "$(app_json_string "$action")" "$(app_json_string "$state")" "$(app_json_string "$started_at")" \
    "$(state_json_nullable "$finished_at")" "$exit_code" "$(state_json_nullable "$(operation_safe_summary "$error")")" "$(state_json_nullable "$log_path")"
}

manager_history_collect() {
  local app_id="${1:-}" limit="$2" history_file record index
  MANAGER_HISTORY_RECORDS=()
  MANAGER_HISTORY_SKIPPED=0
  history_file="${DEPLOY_OPERATION_HISTORY_FILE}"
  [[ -f "$history_file" ]] || return 0
  mapfile -t records < <(tail -n "$limit" "$history_file" 2>/dev/null || true)
  for ((index = ${#records[@]} - 1; index >= 0; index--)); do
    if record="$(manager_history_record_json "${records[index]}" "$app_id" 2>/dev/null)"; then
      MANAGER_HISTORY_RECORDS+=("$record")
    else
      case $? in
        3) ;;
        *) MANAGER_HISTORY_SKIPPED=$((MANAGER_HISTORY_SKIPPED + 1)) ;;
      esac
    fi
  done
}

manager_history_render_json() {
  local app_id="$1" first=1 record
  printf '{"schema_version":1,"generated_at":%s,"app_id":%s,"records":[' "$(app_json_string "$(state_now)")" "$(state_json_nullable "$app_id")"
  for record in "${MANAGER_HISTORY_RECORDS[@]}"; do
    (( first )) || printf ','
    first=0
    printf '%s' "$record"
  done
  printf '],"skipped_records":%s}\n' "$MANAGER_HISTORY_SKIPPED"
}

manager_history_render_table() {
  local record run_id app_id action state started_at finished_at error
  printf '%-30s %-16s %-14s %-14s %-25s %-25s %s\n' Run App Action State Started Finished Error
  printf '%-30s %-16s %-14s %-14s %-25s %-25s %s\n' '------------------------------' '----------------' '--------------' '--------------' '-------------------------' '-------------------------' '-----'
  for record in "${MANAGER_HISTORY_RECORDS[@]}"; do
    run_id="$(state_json_field "$record" run_id)"
    app_id="$(state_json_field "$record" app_id)"
    action="$(state_json_field "$record" action)"
    state="$(state_json_field "$record" state)"
    started_at="$(state_json_field "$record" started_at)"
    finished_at="$(state_json_field "$record" finished_at)"
    error="$(state_json_field "$record" error 2>/dev/null || true)"
    printf '%-30s %-16s %-14s %-14s %-25s %-25s %s\n' "$run_id" "$app_id" "$action" "$state" "$started_at" "$finished_at" "$error"
  done
  (( MANAGER_HISTORY_SKIPPED == 0 )) || printf 'Skipped malformed history records: %s\n' "$MANAGER_HISTORY_SKIPPED" >&2
}

manager_history_main() {
  local app_id="" limit=20 json=0 arg
  while (($#)); do
    arg="$1"; shift
    case "$arg" in
      --json) json=1 ;;
      --limit)
        (($#)) || { manager_history_print_usage; return 2; }
        limit="$1"; shift
        ;;
      --limit=*) limit="${arg#*=}" ;;
      --help|-h) manager_history_print_usage; return 0 ;;
      --*) manager_history_print_usage; return 2 ;;
      *)
        [[ -z "$app_id" ]] || { manager_history_print_usage; return 2; }
        app_id="$arg"
        ;;
    esac
  done
  [[ "$limit" =~ ^[1-9][0-9]*$ && "$limit" -le 200 ]] || { manager_history_print_usage; return 2; }
  manager_history_validate_app "$app_id" || return 2
  manager_history_collect "$app_id" "$limit"
  if (( json )); then manager_history_render_json "$app_id"; else manager_history_render_table; fi
}
