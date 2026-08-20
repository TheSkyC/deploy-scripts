#!/usr/bin/env bash

MANAGER_DOCTOR_USAGE="Usage: deploy.sh doctor-all [--json] [--only-installed] [--include id,id,...] [--exclude id,id,...]"

manager_doctor_print_usage() { echo "$MANAGER_DOCTOR_USAGE" >&2; }

manager_doctor_main() {
  local json=0 include_csv="" exclude_csv="" arg app_id
  local -a ids=() records=()
  while (($#)); do
    arg="$1"; shift
    case "$arg" in
      --json) json=1 ;;
      --include) (($#)) || { manager_doctor_print_usage; return 2; }; include_csv="$1"; shift ;;
      --exclude) (($#)) || { manager_doctor_print_usage; return 2; }; exclude_csv="$1"; shift ;;
      --include=*) include_csv="${arg#*=}" ;;
      --exclude=*) exclude_csv="${arg#*=}" ;;
      --help|-h) manager_doctor_print_usage; return 0 ;;
      *) manager_doctor_print_usage; return 2 ;;
    esac
  done
  local selected
  if ! selected="$(manager_status_selected_ids "$include_csv" "$exclude_csv")"; then return 2; fi
  [[ -n "$selected" ]] && mapfile -t ids < <(printf '%s\n' "$selected")
  for app_id in "${ids[@]}"; do
    local state_file err_file
    state_file="$(mktemp)"; err_file="$(mktemp)"
    if ! manager_status_collect_app_json "$app_id" "$state_file" "$err_file"; then rm -f "$state_file" "$err_file"; continue; fi
    if [[ "$(manager_status_json_field "$state_file" install_state)" != installed ]]; then rm -f "$state_file" "$err_file"; continue; fi
    local doctor_output doctor_status
    if doctor_output="$(manager_load_app "$app_id"; do_doctor 2>&1)"; then doctor_status=0; else doctor_status=$?; fi
    records+=("$(printf '{"app_id":%s,"status":%s,"output":%s}' "$(app_json_string "$app_id")" "$doctor_status" "$(app_json_string "$(operation_safe_summary "$doctor_output" 4096)")")")
    rm -f "$state_file" "$err_file"
  done
  if (( json )); then
    local first=1 record
    printf '{"schema_version":1,"generated_at":%s,"records":[' "$(app_json_string "$(state_now)")"
    for record in "${records[@]}"; do (( first )) || printf ','; first=0; printf '%s' "$record"; done
    printf ']}\n'
  else
    printf '%-16s %-8s %s\n' App Status Output
    for record in "${records[@]}"; do
      printf '%s\n' "$record"
    done
  fi
}
