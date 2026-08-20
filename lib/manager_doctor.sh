#!/usr/bin/env bash

MANAGER_DOCTOR_USAGE="Usage: deploy.sh doctor-all [--json] [--only-installed] [--include id,id,...] [--exclude id,id,...]"

manager_doctor_print_usage() { echo "$MANAGER_DOCTOR_USAGE" >&2; }

manager_doctor_record() {
  local app_id="$1" state="$2" status="$3" output="$4" reason="${5:-}"
  local status_json=null
  [[ "$status" =~ ^[0-9]+$ ]] && status_json="$status"
  printf '{"app_id":%s,"state":%s,"status":%s,"reason":%s,"output":%s}' \
    "$(app_json_string "$app_id")" "$(app_json_string "$state")" "$status_json" \
    "$(state_json_nullable "$(operation_safe_summary "$reason")")" \
    "$(state_json_nullable "$(operation_safe_summary "$output" 4096)")"
}

manager_doctor_main() {
  local json=0 only_installed=1 include_csv="" exclude_csv="" arg app_id selected
  local installed=0 succeeded=0 failed=0 skipped=0 errors=0
  local -a ids=() records=()
  while (($#)); do
    arg="$1"; shift
    case "$arg" in
      --json) json=1 ;;
      --only-installed) only_installed=1 ;;
      --include) (($#)) || { manager_doctor_print_usage; return 2; }; include_csv="$1"; shift ;;
      --exclude) (($#)) || { manager_doctor_print_usage; return 2; }; exclude_csv="$1"; shift ;;
      --include=*) include_csv="${arg#*=}" ;;
      --exclude=*) exclude_csv="${arg#*=}" ;;
      --help|-h) manager_doctor_print_usage; return 0 ;;
      *) manager_doctor_print_usage; return 2 ;;
    esac
  done
  if ! selected="$(manager_status_selected_ids "$include_csv" "$exclude_csv")"; then return 2; fi
  [[ -n "$selected" ]] && mapfile -t ids < <(printf '%s\n' "$selected")

  for app_id in "${ids[@]}"; do
    local state_file err_file install_state collection_error
    state_file="$(mktemp)"; err_file="$(mktemp)"
    if ! manager_status_collect_app_json "$app_id" "$state_file" "$err_file"; then
      collection_error="$(tr '\n' ' ' < "$err_file" 2>/dev/null || true)"
      records+=("$(manager_doctor_record "$app_id" error "" "$collection_error" "status_collection_failed")")
      errors=$((errors + 1))
      rm -f "$state_file" "$err_file"
      continue
    fi
    install_state="$(manager_status_json_field "$state_file" install_state 2>/dev/null || printf unknown)"
    if [[ "$only_installed" == 1 && "$install_state" != installed ]]; then
      records+=("$(manager_doctor_record "$app_id" skipped null "" "not_installed")")
      skipped=$((skipped + 1))
      rm -f "$state_file" "$err_file"
      continue
    fi
    installed=$((installed + 1))
    local doctor_output doctor_status
    if doctor_output="$(manager_load_app "$app_id" 2>&1 && do_doctor 2>&1)"; then
      doctor_status=0
      succeeded=$((succeeded + 1))
      records+=("$(manager_doctor_record "$app_id" succeeded "$doctor_status" "$doctor_output")")
    else
      doctor_status=$?
      failed=$((failed + 1))
      records+=("$(manager_doctor_record "$app_id" failed "$doctor_status" "$doctor_output" "doctor_failed")")
    fi
    rm -f "$state_file" "$err_file"
  done

  if (( json )); then
    local first=1 record
    printf '{"schema_version":1,"generated_at":%s,"summary":{"selected":%s,"installed":%s,"succeeded":%s,"failed":%s,"skipped":%s,"errors":%s},"records":[' \
      "$(app_json_string "$(state_now)")" "${#ids[@]}" "$installed" "$succeeded" "$failed" "$skipped" "$errors"
    for record in "${records[@]}"; do (( first )) || printf ','; first=0; printf '%s' "$record"; done
    printf ']}\n'
  else
    printf '%-16s %-12s %-8s %-18s %s\n' App State Status Reason Output
    for record in "${records[@]}"; do
      printf '%-16s %-12s %-8s %-18s %s\n' \
        "$(state_json_field "$record" app_id)" "$(state_json_field "$record" state)" \
        "$(state_json_field "$record" status)" "$(state_json_field "$record" reason)" \
        "$(state_json_field "$record" output)"
    done
  fi
  (( failed == 0 && errors == 0 ))
}
