#!/usr/bin/env bash

MANAGER_STATUS_USAGE="Usage: deploy.sh status-all|overview|problems [--json] [--short] [--strict] [--errors-only] [--only-installed] [--no-probe] [--no-network] [--include id,id,...] [--exclude id,id,...]"

manager_status_print_usage() { echo "$MANAGER_STATUS_USAGE" >&2; }

manager_status_csv_ids() {
  local csv="$1" item id
  IFS=',' read -r -a items <<< "$csv"
  for item in "${items[@]}"; do
    id="$(deploy_trim "$item")"
    [[ -n "$id" ]] || continue
    deploy_app_offset_for "$id" >/dev/null 2>&1 || return 2
    printf '%s\n' "$id"
  done
}

manager_status_selected_ids() {
  local include_csv="${1:-}" exclude_csv="${2:-}" id excluded=0 parsed parse_status item
  local -a includes=() excludes=()
  if [[ -n "$include_csv" ]]; then
    set +e
    parsed="$(manager_status_csv_ids "$include_csv")"; parse_status=$?
    set -e
    (( parse_status == 0 )) || return 2
    [[ -n "$parsed" ]] && mapfile -t includes < <(printf '%s\n' "$parsed")
  else
    includes=("${DEPLOY_APP_IDS[@]}")
  fi
  if [[ -n "$exclude_csv" ]]; then
    set +e
    parsed="$(manager_status_csv_ids "$exclude_csv")"; parse_status=$?
    set -e
    (( parse_status == 0 )) || return 2
    [[ -n "$parsed" ]] && mapfile -t excludes < <(printf '%s\n' "$parsed")
  fi
  for id in "${includes[@]}"; do
    excluded=0
    for item in "${excludes[@]}"; do [[ "$id" == "$item" ]] && excluded=1; done
    (( excluded == 0 )) && printf '%s\n' "$id"
  done
  return 0
}

manager_status_collect_app_json() {
  local app_id="$1" output_file="$2" error_file="$3" status pid start timeout_seconds
  : >"$output_file"; : >"$error_file"
  ( manager_load_app "$app_id"; app_status_collect_json ) >"$output_file" 2>"$error_file" &
  pid=$!
  timeout_seconds="${DEPLOY_STATUS_TIMEOUT_SECONDS:-8}"
  if [[ "$timeout_seconds" =~ ^[0-9]+([.][0-9]+)?$ ]] && awk "BEGIN { exit !($timeout_seconds > 0) }"; then
    # `date` is relatively expensive on Git Bash/Windows. Calling it from the
    # polling loop used to add enough process churn to make healthy collectors
    # miss the timeout window. Bash's monotonic SECONDS variable avoids that
    # overhead while retaining the existing integer-second contract.
    local start_seconds=$SECONDS timeout_limit="${timeout_seconds%.*}"
    (( timeout_limit > 0 )) || timeout_limit=1
    while kill -0 "$pid" 2>/dev/null; do
      if (( SECONDS - start_seconds >= timeout_limit )); then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        printf 'status collection timed out after %ss' "$timeout_seconds" >>"$error_file"
        return 124
      fi
      sleep 0.1
    done
  fi
  if wait "$pid"; then
    status=0
  else
    status=$?
  fi
  [[ "$status" -eq 0 ]] || return "$status"
  [[ "$(wc -l < "$output_file")" -eq 1 ]] || { printf 'status collector returned multiple lines' >>"$error_file"; return 1; }
  [[ "$(head -c 1 "$output_file")" == "{" ]] || { printf 'status collector did not return a JSON object' >>"$error_file"; return 1; }
}

manager_status_json_field() {
  local file="$1" key="$2" object
  object="$(cat "$file")" || return 1
  state_json_field "$object" "$key"
}

manager_status_collect() {
  local include_csv="${1:-}" exclude_csv="${2:-}" only_installed="${3:-0}"
  local temp_dir app_id output error_file status parsed_ids
  local -a ids=() json_files=() errors=()
  temp_dir="$(mktemp -d)" || return 1
  chmod 700 "$temp_dir" || { rm -rf "$temp_dir"; return 1; }
  set +e
  parsed_ids="$(manager_status_selected_ids "$include_csv" "$exclude_csv")"; status=$?
  set -e
  if (( status != 0 )); then rm -rf "$temp_dir"; return 2; fi
  [[ -n "$parsed_ids" ]] && mapfile -t ids < <(printf '%s\n' "$parsed_ids")
  for app_id in "${ids[@]}"; do
    output="${temp_dir}/${app_id}.json"; error_file="${temp_dir}/${app_id}.err"
    if manager_status_collect_app_json "$app_id" "$output" "$error_file"; then
      if [[ "$only_installed" == 1 ]] && [[ "$(manager_status_json_field "$output" install_state)" != installed ]]; then continue; fi
      json_files+=("$output")
    else
      status=$?
      errors+=("${app_id}:${status}:$(operation_safe_summary "$(tr '\n' ' ' < "$error_file" 2>/dev/null)")")
    fi
  done
  printf '%s\n' "${json_files[@]}" >"${temp_dir}/files"
  printf '%s\n' "${errors[@]}" >"${temp_dir}/errors"
  MANAGER_STATUS_REGISTERED_COUNT="${#DEPLOY_APP_IDS[@]}"
  MANAGER_STATUS_SELECTED_COUNT="${#ids[@]}"
  MANAGER_STATUS_TEMP_DIR="$temp_dir"
}

manager_status_render_json() {
  local temp_dir="$1" problems="${2:-0}" errors_only="${3:-0}" file first=1 app_count=0 installed=0 healthy=0 degraded=0 unhealthy=0 not_installed=0 updates=0 error_count=0 severity registered
  registered="${MANAGER_STATUS_REGISTERED_COUNT:-0}"
  local selected="${MANAGER_STATUS_SELECTED_COUNT:-0}"
  local framework_mode=checkout framework_version=unknown
  [[ -f "${DEPLOY_ROOT_DIR}/.git/HEAD" ]] || framework_mode=standalone_dist
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    severity="$(manager_status_human_field "$file" severity)"
    manager_status_should_render "$severity" 0 "$problems" "$errors_only" || continue
    app_count=$((app_count + 1))
    [[ "$(manager_status_json_field "$file" install_state)" == installed ]] && installed=$((installed + 1))
    case "$(manager_status_json_field "$file" health.state 2>/dev/null || true)" in healthy) healthy=$((healthy + 1));; degraded) degraded=$((degraded + 1));; unhealthy) unhealthy=$((unhealthy + 1));; esac
    [[ "$(manager_status_json_field "$file" install_state)" == not_installed ]] && not_installed=$((not_installed + 1))
    [[ "$(manager_status_json_field "$file" version_info.update_state 2>/dev/null || true)" == update_available ]] && updates=$((updates + 1))
  done <"${temp_dir}/files"
  error_count="$(grep -c . "${temp_dir}/errors" 2>/dev/null || true)"
  printf '{"schema_version":1,"generated_at":%s,"framework":{"version":%s,"install_mode":%s,"channel":"stable"},"summary":{"registered":%s,"selected":%s,"installed":%s,"healthy":%s,"degraded":%s,"unhealthy":%s,"not_installed":%s,"update_available":%s,"errors":%s},"apps":[' "$(app_json_string "$(state_now)")" "$(app_json_string "$framework_version")" "$(app_json_string "$framework_mode")" "$registered" "$selected" "$installed" "$healthy" "$degraded" "$unhealthy" "$not_installed" "$updates" "$error_count"
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    severity="$(manager_status_human_field "$file" severity)"
    manager_status_should_render "$severity" 0 "$problems" "$errors_only" || continue
    (( first )) || printf ','; first=0; cat "$file"
  done <"${temp_dir}/files"
  printf '],"errors":['; first=1
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    (( first )) || printf ','; first=0
    local app_id code summary; app_id="${file%%:*}"; code="${file#*:}"; code="${code%%:*}"; summary="${file#*:*:}"
    printf '{"app_id":%s,"code":%s,"summary":%s}' "$(app_json_string "$app_id")" "$code" "$(app_json_string "$summary")"
  done <"${temp_dir}/errors"
  printf ']}\n'
}

manager_status_human_field() { local file="$1" key="$2"; manager_status_json_field "$file" "$key" 2>/dev/null || printf unknown; }

manager_status_should_render() {
  local severity="$1" short="${2:-0}" problems="${3:-0}" errors_only="${4:-0}"
  if [[ "$errors_only" == 1 ]]; then
    [[ "$severity" == critical || "$severity" == error ]]
  elif [[ "$problems" == 1 || "$short" == 1 ]]; then
    [[ "$severity" == critical || "$severity" == error || "$severity" == warning ]]
  else
    return 0
  fi
}

manager_status_render_table() {
  local temp_dir="$1" short="${2:-0}" problems="${3:-0}" errors_only="${4:-0}" file app_id name install severity service health version
  printf '%-16s %-24s %-15s %-10s %-12s %-12s %-18s\n' App Name Install Severity Service Health Version
  printf '%-16s %-24s %-15s %-10s %-12s %-12s %-18s\n' '----------------' '------------------------' '---------------' '----------' '------------' '------------' '------------------'
  while IFS= read -r file; do
    [[ -n "$file" ]] || continue
    install="$(manager_status_human_field "$file" install_state)"; severity="$(manager_status_human_field "$file" severity)"
    manager_status_should_render "$severity" "$short" "$problems" "$errors_only" || continue
    app_id="$(manager_status_human_field "$file" app_id)"; name="$(manager_status_human_field "$file" app_name)"; service="$(manager_status_human_field "$file" service.state)"; health="$(manager_status_human_field "$file" health.state)"; version="$(manager_status_human_field "$file" version_info.installed)"
    printf '%-16s %-24s %-15s %-10s %-12s %-12s %-18s\n' "$app_id" "$name" "$install" "$severity" "$service" "$health" "$version"
  done <"${temp_dir}/files"
  while IFS= read -r file; do [[ -n "$file" ]] && printf 'error: %s\n' "$file" >&2; done <"${temp_dir}/errors"
}

manager_status_main() {
  local command="$1" arg json=0 short=0 strict=0 errors_only=0 only_installed=0 include_csv="" exclude_csv="" temp_dir status
  shift || true
  while (($#)); do
    arg="$1"; shift
    case "$arg" in
      --json) json=1 ;;
      --short) short=1 ;;
      --strict) strict=1 ;;
      --errors-only) errors_only=1 ;;
      --only-installed) only_installed=1 ;;
      --no-probe) export DEPLOY_STATUS_NO_PROBE=1 ;;
      --no-network) export DEPLOY_STATUS_NO_NETWORK=1 ;;
      --include) (($#)) || { manager_status_print_usage; return 2; }; include_csv="$1"; shift ;;
      --exclude) (($#)) || { manager_status_print_usage; return 2; }; exclude_csv="$1"; shift ;;
      --include=*) include_csv="${arg#*=}" ;;
      --exclude=*) exclude_csv="${arg#*=}" ;;
      *) manager_status_print_usage; return 2 ;;
    esac
  done
  [[ "$command" != problems ]] || strict=1
  [[ "$command" != health-all ]] || only_installed=1
  manager_status_collect "$include_csv" "$exclude_csv" "$only_installed" || return $?
  temp_dir="$MANAGER_STATUS_TEMP_DIR"
  if (( json )); then
    manager_status_render_json "$temp_dir" "$([[ "$command" == problems ]] && printf 1 || printf 0)" "$errors_only"
  else
    manager_status_render_table "$temp_dir" "$short" "$([[ "$command" == problems ]] && printf 1 || printf 0)" "$errors_only"
  fi
  status=0
  if (( strict )); then
    if [[ -s "/errors" ]]; then
      status=1
    fi
    while IFS= read -r file; do
      [[ -n "$file" ]] || continue
      case "$(manager_status_human_field "$file" severity)" in
        critical) status=7 ;;
        error)
          case "$(manager_status_human_field "$file" service.state)" in failed|stopped) (( status < 4 )) && status=4 ;; esac
          case "$(manager_status_human_field "$file" health.state)" in unhealthy) (( status < 5 )) && status=5 ;; esac
          (( status == 0 )) && status=1
          ;;
        warning)
          case "$(manager_status_human_field "$file" health.state)" in degraded) (( status < 5 )) && status=5 ;; *) (( status < 1 )) && status=1 ;; esac
          ;;
      esac
    done <"${temp_dir}/files"
  fi
  rm -rf "$temp_dir"
  return "$status"
}
