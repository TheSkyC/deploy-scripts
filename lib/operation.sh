#!/usr/bin/env bash

DEPLOY_OPERATION_ROOT="${DEPLOY_OPERATION_ROOT:-/var/lib/deploy-scripts}"
DEPLOY_OPERATION_LOG_ROOT="${DEPLOY_OPERATION_LOG_ROOT:-/var/log/deploy-scripts}"
DEPLOY_OPERATION_LOGROTATE_FILE="${DEPLOY_OPERATION_LOGROTATE_FILE:-/etc/logrotate.d/deploy-scripts}"
DEPLOY_OPERATION_LOGROTATE_DAYS="${DEPLOY_OPERATION_LOGROTATE_DAYS:-30}"
DEPLOY_OPERATION_LOGROTATE_FILES="${DEPLOY_OPERATION_LOGROTATE_FILES:-20}"
DEPLOY_OPERATION_STATE_DIR="${DEPLOY_OPERATION_ROOT}/state"
DEPLOY_OPERATION_HISTORY_DIR="${DEPLOY_OPERATION_ROOT}/history"
DEPLOY_OPERATION_HISTORY_FILE="${DEPLOY_OPERATION_HISTORY_DIR}/operations.jsonl"

operation_is_valid_app_id() { [[ "${1:-}" =~ ^[a-z][a-z0-9_-]{0,63}$ ]]; }
operation_is_valid_scope() { case "${1:-}" in app|manager|self_update) return 0;; *) return 1;; esac; }
operation_is_valid_action() { [[ "${1:-}" =~ ^[a-z][a-z0-9_-]{0,63}$ ]]; }
operation_timestamp() { date '+%Y-%m-%dT%H:%M:%S%:z'; }
operation_run_timestamp() { date '+%Y%m%dT%H%M%S%z'; }

# Shared JSON string escaper core: escapes backslash, quote, and every C0
# control character, printing the escaped text WITHOUT surrounding quotes.
# Lives in operation.sh (loaded before app.sh by core.sh and the release
# bundle, and usable standalone) so both operation_json_escape and
# app_json_string delegate to one implementation — operation records and
# status JSON can never disagree about escaping again.
__deploy_json_escape_unquoted() {
  local value="${1:-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\b'/\\b}"
  value="${value//$'\f'/\\f}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  # Escape the remaining C0 control characters (U+0001..U+001F), which JSON
  # forbids literally. NUL (U+0000) cannot appear in bash strings. Do this
  # unconditionally: Bash regex ranges over control bytes vary across builds.
  local i byte hex octal
  for ((i = 1; i < 32; i++)); do
    case "$i" in 8|9|10|12|13) continue ;; esac
    printf -v octal '%03o' "$i"
    printf -v byte '%b' "\0$octal"
    printf -v hex '%02x' "$i"
    value="${value//"$byte"/"\u00${hex}"}"
  done
  printf '%s' "$value"
}

# Delegate to the shared escaper core: operation records previously escaped
# fewer characters than app_json_string (missing \b, \f, and most C0 controls),
# so a step name containing a control byte produced invalid JSON here while
# status JSON escaped it correctly.
operation_json_escape() {
  __deploy_json_escape_unquoted "${1:-}"
}

operation_json_nullable() {
  if [[ -n "${1:-}" ]]; then
    printf '"%s"' "$(operation_json_escape "$1")"
  else
    printf 'null'
  fi
}

operation_safe_summary() {
  local value="${1:-}" max_bytes="${2:-512}"
  value="${value//$'\n'/ }"; value="${value//$'\r'/ }"
  value="$(printf '%s' "$value" | sed -E \
    -e 's/([[:alnum:]_.-]*(TOKEN|PASSWORD|SECRET|API_KEY|PRIVATE_KEY|KEY)[[:alnum:]_.-]*[[:space:]]*=[[:space:]]*)[^[:space:]]+/\1[REDACTED]/Ig' \
    -e 's#(Authorization:[[:space:]]*Bearer[[:space:]]+)[^[:space:]]+#\1[REDACTED]#Ig' \
    -e 's#(https?://[^:/[:space:]]+):[^@/[:space:]]+@#\1:[REDACTED]@#g')"
  (( ${#value} > max_bytes )) && value="${value:0:max_bytes}"
  printf '%s' "$value"
}

operation_redact_line() {
  local line="$1"
  printf '%s\n' "$line" | sed -E \
    -e 's/([[:alnum:]_.-]*(TOKEN|PASSWORD|SECRET|API_KEY|PRIVATE_KEY|KEY)[[:alnum:]_.-]*[[:space:]]*=[[:space:]]*)[^[:space:]]+/\1[REDACTED]/Ig' \
    -e 's#(Authorization:[[:space:]]*Bearer[[:space:]]+)[^[:space:]]+#\1[REDACTED]#Ig' \
    -e 's#(https?://[^:/[:space:]]+):[^@/[:space:]]+@#\1:[REDACTED]@#g'
}

operation_log_stream() {
  local log_path="$1" line=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    printf '%s\n' "$line"
    operation_redact_line "$line" >>"$log_path"
    line=""
  done
}

operation_stream_output() {
  local log_path="$1"
  operation_log_stream "$log_path"
}

operation_stream_error() {
  local log_path="$1"
  operation_log_stream "$log_path" >&2
}

operation_discard_output_streams() {
  local output_dir="${OPERATION_OUTPUT_DIR:-}" stdout_pid="${OPERATION_STDOUT_PID:-}" stderr_pid="${OPERATION_STDERR_PID:-}" saved_stdout_fd="${OPERATION_SAVED_STDOUT_FD:-}" saved_stderr_fd="${OPERATION_SAVED_STDERR_FD:-}"
  [[ -n "$output_dir" ]] || return 0
  [[ -z "$stdout_pid" ]] || kill "$stdout_pid" 2>/dev/null || true
  [[ -z "$stderr_pid" ]] || kill "$stderr_pid" 2>/dev/null || true
  [[ -z "$stdout_pid" ]] || wait "$stdout_pid" 2>/dev/null || true
  [[ -z "$stderr_pid" ]] || wait "$stderr_pid" 2>/dev/null || true
  [[ -z "$saved_stdout_fd" ]] || eval "exec ${saved_stdout_fd}>&-" || true
  [[ -z "$saved_stderr_fd" ]] || eval "exec ${saved_stderr_fd}>&-" || true
  rm -rf -- "$output_dir"
  unset OPERATION_OUTPUT_DIR OPERATION_STDOUT_PID OPERATION_STDERR_PID OPERATION_SAVED_STDOUT_FD OPERATION_SAVED_STDERR_FD
}
operation_finish_output_streams() {
  local output_dir="${OPERATION_OUTPUT_DIR:-}" stdout_pid="${OPERATION_STDOUT_PID:-}" stderr_pid="${OPERATION_STDERR_PID:-}" saved_stdout_fd="${OPERATION_SAVED_STDOUT_FD:-}" saved_stderr_fd="${OPERATION_SAVED_STDERR_FD:-}"
  [[ -n "$output_dir" ]] || return 0
  [[ -z "$stdout_pid" ]] || wait "$stdout_pid" || true
  [[ -z "$stderr_pid" ]] || wait "$stderr_pid" || true
  [[ -z "$saved_stdout_fd" ]] || eval "exec ${saved_stdout_fd}>&-" || true
  [[ -z "$saved_stderr_fd" ]] || eval "exec ${saved_stderr_fd}>&-" || true
  rm -rf -- "$output_dir"
  unset OPERATION_OUTPUT_DIR OPERATION_STDOUT_PID OPERATION_STDERR_PID OPERATION_SAVED_STDOUT_FD OPERATION_SAVED_STDERR_FD
}

operation_set_owner_and_mode() {
  local path="$1" mode="$2"; chmod "$mode" "$path" || return 1
  if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then chown root:root "$path" || return 1; fi
}
operation_write_logrotate() {
  local target="${DEPLOY_OPERATION_LOGROTATE_FILE:-}" tmp days files log_root
  [[ -n "$target" ]] || return 0
  [[ "$target" != *$'\n'* && "$target" != *$'\r'* ]] || return 1
  days="${DEPLOY_OPERATION_LOGROTATE_DAYS:-30}"
  files="${DEPLOY_OPERATION_LOGROTATE_FILES:-20}"
  [[ "$days" =~ ^[1-9][0-9]*$ && "$files" =~ ^[1-9][0-9]*$ ]] || return 1
  log_root="${DEPLOY_OPERATION_LOG_ROOT%/}"
  [[ -n "$log_root" && "$log_root" != *$'\n'* && "$log_root" != *$'\r'* ]] || return 1
  mkdir -p "$(dirname "$target")" || return 1
  tmp="$(mktemp "$(dirname "$target")/.$(basename "$target").XXXXXX")" || return 1
  if ! cat >"$tmp" <<LOGROTATE
${log_root}/*/*.log {
    daily
    rotate ${files}
    maxage ${days}
    compress
    delaycompress
    missingok
    notifempty
    create 0640 root root
}
LOGROTATE
  then
    rm -f "$tmp"
    return 1
  fi
  if ! chmod 644 "$tmp" || { [[ "${EUID:-$(id -u)}" -eq 0 ]] && ! chown root:root "$tmp"; }; then
    rm -f "$tmp"
    return 1
  fi
  mv -f "$tmp" "$target" || { rm -f "$tmp"; return 1; }
}

operation_ensure_logrotate() {
  # Framework installation owns the system policy; unprivileged dry-runs and
  # tests must not repeatedly attempt to mutate /etc.
  [[ "${EUID:-$(id -u)}" -eq 0 ]] || return 0
  operation_write_logrotate || {
    printf 'warning: unable to write operation logrotate policy: %s\n' "${DEPLOY_OPERATION_LOGROTATE_FILE:-unset}" >&2
    return 0
  }
}

operation_ensure_directories() {
  local dir
  for dir in "$DEPLOY_OPERATION_ROOT" "$DEPLOY_OPERATION_STATE_DIR" "$DEPLOY_OPERATION_HISTORY_DIR" "$DEPLOY_OPERATION_LOG_ROOT"; do
    mkdir -p "$dir" || return 1; operation_set_owner_and_mode "$dir" 750 || return 1
  done
  operation_ensure_logrotate
}
operation_state_file_for() {
  local scope="$1" app_id="${2:-}"
  case "$scope" in
    app) operation_is_valid_app_id "$app_id" || return 1; printf '%s/%s.json\n' "$DEPLOY_OPERATION_STATE_DIR" "$app_id";;
    manager) printf '%s/manager.json\n' "$DEPLOY_OPERATION_STATE_DIR";;
    self_update) printf '%s/self-update.json\n' "$DEPLOY_OPERATION_ROOT";;
    *) return 1;;
  esac
}
operation_log_path_for() {
  local scope="$1" app_id="$2" run_id="$3" directory
  case "$scope" in
    app) operation_is_valid_app_id "$app_id" || return 1; directory="${DEPLOY_OPERATION_LOG_ROOT}/${app_id}";;
    manager) directory="${DEPLOY_OPERATION_LOG_ROOT}/manager";;
    self_update) directory="${DEPLOY_OPERATION_LOG_ROOT}/self-update";;
    *) return 1;;
  esac
  mkdir -p "$directory" || return 1; operation_set_owner_and_mode "$directory" 750 || return 1
  printf '%s/%s.log\n' "$directory" "$run_id"
}
operation_new_run_id() { printf '%s-%s-%s-%04x%04x\n' "$(operation_run_timestamp)" "${2:-$1}" "$3" "$RANDOM" "$RANDOM"; }
operation_reset() { unset OPERATION_ACTIVE OPERATION_RUN_ID OPERATION_SCOPE OPERATION_APP_ID OPERATION_ACTION OPERATION_STARTED_AT OPERATION_FINISHED_AT OPERATION_STATE OPERATION_LAST_STEP OPERATION_EXIT_CODE OPERATION_ERROR_SUMMARY OPERATION_LOG_PATH OPERATION_STEPS_FILE OPERATION_CAPTURE_DIR OPERATION_OUTPUT_DIR OPERATION_STDOUT_PID OPERATION_STDERR_PID OPERATION_SAVED_STDOUT_FD OPERATION_SAVED_STDERR_FD OPERATION_PREVIOUS_EXIT_TRAP OPERATION_PREVIOUS_INT_TRAP OPERATION_PREVIOUS_TERM_TRAP OPERATION_PREVIOUS_HUP_TRAP OPERATION_INTERRUPTED_SIGNAL OPERATION_INTERRUPTION_CLEANUP_FN OPERATION_INTERRUPTION_SUMMARY; }
operation_restore_exit_trap() {
  local previous_trap="${1:-}"
  if [[ -n "$previous_trap" ]]; then
    eval "$previous_trap"
  else
    trap - EXIT
  fi
}

operation_return_status() {
  return "$1"
}

operation_restore_signal_trap() {
  local signal="$1" previous_trap="${2:-}"
  if [[ -n "$previous_trap" ]]; then
    eval "$previous_trap"
  else
    trap - "$signal"
  fi
}

operation_restore_signal_traps() {
  operation_restore_signal_trap INT "${OPERATION_PREVIOUS_INT_TRAP:-}"
  operation_restore_signal_trap TERM "${OPERATION_PREVIOUS_TERM_TRAP:-}"
  operation_restore_signal_trap HUP "${OPERATION_PREVIOUS_HUP_TRAP:-}"
}

operation_signal_exit_code() {
  case "${1:-TERM}" in
    INT) printf '130' ;;
    HUP) printf '129' ;;
    TERM) printf '143' ;;
    *) printf '1' ;;
  esac
}

operation_action_signal_trap() {
  local signal="${1:-TERM}" exit_code
  [[ -n "${OPERATION_INTERRUPTED_SIGNAL:-}" ]] && return 0
  OPERATION_INTERRUPTED_SIGNAL="$signal"
  exit_code="$(operation_signal_exit_code "$signal")"
  trap - INT TERM HUP
  exit "$exit_code"
}
operation_invoke_exit_trap() {
  local status="$1" previous_trap="${2:-}" command had_errexit=0
  [[ -n "$previous_trap" ]] || exit "$status"
  command="${previous_trap#trap -- }"
  command="${command% EXIT}"
  if [[ "$command" == "'__deploy_run_exit_handlers'" &&
        "$(type -t __deploy_run_exit_handlers 2>/dev/null || true)" == function ]]; then
    __DEPLOY_EXIT_STATUS="$status"
    __deploy_run_exit_handlers
  fi
  [[ "$-" == *e* ]] && had_errexit=1
  set +e
  # Make the original status available as `$?` to an arbitrary prior EXIT
  # trap. The status-setting function is deliberately the command immediately
  # before eval; assignments and local declarations would otherwise erase it.
  operation_return_status "$status"
  eval "$command"
  (( had_errexit == 1 )) && set -e
  exit "$status"
}

operation_steps_json() {
  local first=1 name state started_at finished_at; printf '['
  while IFS=$'\t' read -r name state started_at finished_at; do
    [[ -n "$name" ]] || continue; [[ "$first" -eq 1 ]] || printf ','; first=0
    printf '{"name":"%s","state":"%s","started_at":"%s","finished_at":%s}' "$(operation_json_escape "$name")" "$(operation_json_escape "$state")" "$(operation_json_escape "$started_at")" "$(operation_json_nullable "$finished_at")"
  done < "$OPERATION_STEPS_FILE"; printf ']'
}
operation_write_record() {
  [[ "${OPERATION_ACTIVE:-0}" == 1 ]] || return 1
  local state_file tmp_file app_json=null finished_json=null error_json=null steps_json='[]' last_step_json=null
  state_file="$(operation_state_file_for "$OPERATION_SCOPE" "${OPERATION_APP_ID:-}")" || return 1
  [[ -n "${OPERATION_APP_ID:-}" ]] && app_json="\"$(operation_json_escape "$OPERATION_APP_ID")\""
  [[ -n "${OPERATION_FINISHED_AT:-}" ]] && finished_json="\"$(operation_json_escape "$OPERATION_FINISHED_AT")\""
  [[ -n "${OPERATION_ERROR_SUMMARY:-}" ]] && error_json="\"$(operation_json_escape "$OPERATION_ERROR_SUMMARY")\""
  [[ -n "${OPERATION_LAST_STEP:-}" ]] && last_step_json="\"$(operation_json_escape "$OPERATION_LAST_STEP")\""
  [[ -f "${OPERATION_STEPS_FILE:-}" ]] && steps_json="$(operation_steps_json)"
  tmp_file="$(mktemp "${state_file}.tmp.XXXXXX")" || return 1
  printf '{"schema_version":1,"run_id":"%s","scope":"%s","app_id":%s,"action":"%s","state":"%s","started_at":"%s","finished_at":%s,"last_step":%s,"steps":%s,"exit_code":%s,"error":%s,"log_path":"%s"}\n' "$(operation_json_escape "$OPERATION_RUN_ID")" "$(operation_json_escape "$OPERATION_SCOPE")" "$app_json" "$(operation_json_escape "$OPERATION_ACTION")" "$(operation_json_escape "$OPERATION_STATE")" "$(operation_json_escape "$OPERATION_STARTED_AT")" "$finished_json" "$last_step_json" "$steps_json" "${OPERATION_EXIT_CODE:-null}" "$error_json" "$(operation_json_escape "$OPERATION_LOG_PATH")" > "$tmp_file" || { rm -f "$tmp_file"; return 1; }
  operation_set_owner_and_mode "$tmp_file" 640 || { rm -f "$tmp_file"; return 1; }; mv -f "$tmp_file" "$state_file" || { rm -f "$tmp_file"; return 1; }
}
operation_append_history() { local state_file; state_file="$(operation_state_file_for "$OPERATION_SCOPE" "${OPERATION_APP_ID:-}")" || return 1; [[ -f "$state_file" ]] || return 1; cat "$state_file" >> "$DEPLOY_OPERATION_HISTORY_FILE" || return 1; operation_set_owner_and_mode "$DEPLOY_OPERATION_HISTORY_FILE" 640; }
operation_start() {
  local scope="$1" app_id="$2" action="$3"
  operation_is_valid_scope "$scope" || return 2
  operation_is_valid_action "$action" || return 2
  [[ "$scope" != app || -n "$app_id" ]] || return 2
  [[ "$scope" != app ]] || operation_is_valid_app_id "$app_id" || return 2
  operation_ensure_directories || return 1
  operation_reset

  OPERATION_ACTIVE=1
  OPERATION_SCOPE="$scope"
  OPERATION_APP_ID="$app_id"
  OPERATION_ACTION="$action"
  OPERATION_RUN_ID="$(operation_new_run_id "$scope" "$app_id" "$action")"
  OPERATION_STARTED_AT="$(operation_timestamp)"
  OPERATION_STATE=running
  OPERATION_LOG_PATH="$(operation_log_path_for "$scope" "$app_id" "$OPERATION_RUN_ID")" || { operation_reset; return 1; }
  OPERATION_STEPS_FILE="$(mktemp "${DEPLOY_OPERATION_ROOT}/.operation-steps.XXXXXX")" || { operation_reset; return 1; }
  operation_set_owner_and_mode "$OPERATION_STEPS_FILE" 600 || { rm -f "$OPERATION_STEPS_FILE"; operation_reset; return 1; }
  : > "$OPERATION_LOG_PATH" || { rm -f "$OPERATION_STEPS_FILE"; operation_reset; return 1; }
  operation_set_owner_and_mode "$OPERATION_LOG_PATH" 640 || { rm -f "$OPERATION_STEPS_FILE"; operation_reset; return 1; }
  operation_write_record || { rm -f "$OPERATION_STEPS_FILE"; operation_reset; return 1; }
}
operation_step_start() { local name="$1" now updated; [[ "${OPERATION_ACTIVE:-0}" == 1 && "$name" =~ ^[a-z][a-z0-9_-]{0,63}$ ]] || return 1; now="$(operation_timestamp)"; updated="$(mktemp "${OPERATION_STEPS_FILE}.XXXXXX")" || return 1; awk -F '\t' -v name="$name" '$1 != name { print }' "$OPERATION_STEPS_FILE" > "$updated" || return 1; printf '%s\trunning\t%s\t\n' "$name" "$now" >> "$updated"; mv -f "$updated" "$OPERATION_STEPS_FILE"; OPERATION_LAST_STEP="$name"; operation_write_record; }
operation_step_finish() { local name="$1" state="${2:-succeeded}" now updated found=0 step_name step_state started_at finished_at; [[ "${OPERATION_ACTIVE:-0}" == 1 ]] || return 1; case "$state" in succeeded|failed|skipped) ;; *) return 2;; esac; now="$(operation_timestamp)"; updated="$(mktemp "${OPERATION_STEPS_FILE}.XXXXXX")" || return 1; while IFS=$'\t' read -r step_name step_state started_at finished_at; do [[ -n "$step_name" ]] || continue; if [[ "$step_name" == "$name" ]]; then printf '%s\t%s\t%s\t%s\n' "$name" "$state" "$started_at" "$now" >> "$updated"; found=1; else printf '%s\t%s\t%s\t%s\n' "$step_name" "$step_state" "$started_at" "$finished_at" >> "$updated"; fi; done < "$OPERATION_STEPS_FILE"; [[ "$found" -eq 1 ]] || { rm -f "$updated"; return 1; }; mv -f "$updated" "$OPERATION_STEPS_FILE"; OPERATION_LAST_STEP="$name"; operation_write_record; }
operation_finish() { local exit_code="${1:-1}" state="${2:-}" summary="${3:-}"; [[ "${OPERATION_ACTIVE:-0}" == 1 && "$exit_code" =~ ^[0-9]+$ ]] || return 1; [[ -n "$state" ]] || { [[ "$exit_code" -eq 0 ]] && state=succeeded || state=failed; }; case "$state" in succeeded|failed|cancelled|interrupted|rolled_back|rollback_failed) ;; *) return 2;; esac; OPERATION_STATE="$state"; OPERATION_EXIT_CODE="$exit_code"; OPERATION_FINISHED_AT="$(operation_timestamp)"; OPERATION_ERROR_SUMMARY="$(operation_safe_summary "$summary")"; operation_write_record || return 1; operation_append_history || return 1; rm -f "$OPERATION_STEPS_FILE"; operation_reset; }
operation_action_exit_trap() {
  local status="$?" action="${OPERATION_ACTION:-unknown}" previous_trap="${OPERATION_PREVIOUS_EXIT_TRAP:-}"
  if [[ -n "${OPERATION_SAVED_STDOUT_FD:-}" ]]; then
    eval "exec 1>&${OPERATION_SAVED_STDOUT_FD} 2>&${OPERATION_SAVED_STDERR_FD}" || true
  fi
  trap - EXIT
  if [[ "${OPERATION_ACTIVE:-0}" == 1 ]]; then
    operation_restore_signal_traps || true
    if [[ -n "${OPERATION_INTERRUPTED_SIGNAL:-}" && -n "${OPERATION_INTERRUPTION_CLEANUP_FN:-}" ]] \
      && declare -f "${OPERATION_INTERRUPTION_CLEANUP_FN}" >/dev/null 2>&1; then
      "${OPERATION_INTERRUPTION_CLEANUP_FN}" "$status" || true
    fi
    if [[ -n "${OPERATION_INTERRUPTED_SIGNAL:-}" ]]; then
      operation_discard_output_streams || true
    else
      operation_finish_output_streams || true
    fi
    if [[ "$status" -eq 0 ]]; then
      operation_step_finish execute succeeded || true
    else
      operation_step_finish execute failed || true
    fi
    if [[ -n "${OPERATION_INTERRUPTED_SIGNAL:-}" ]]; then
      operation_finish "$status" interrupted "${OPERATION_INTERRUPTION_SUMMARY:-${action} interrupted by SIG${OPERATION_INTERRUPTED_SIGNAL}}" || true
    else
      operation_finish "$status" "" "${action} exited with status ${status}" || true
    fi
  fi
  operation_invoke_exit_trap "$status" "$previous_trap"
}

operation_run_app_action() {
  local action="$1" function_name="$2" status output_dir log_path
  shift 2
  operation_is_valid_action "$action" || return 2
  [[ "$function_name" =~ ^[a-zA-Z_][a-zA-Z0-9_]*$ ]] || return 2
  declare -f "$function_name" >/dev/null 2>&1 || return 2
  # A non-root invocation cannot create the framework's root-owned operation
  # paths. Let the action's own root guard produce the established, actionable
  # error instead of masking it with an operation-record setup failure.
  if [[ "${EUID:-$(id -u)}" -ne 0 &&
        "${DEPLOY_OPERATION_ROOT:-/var/lib/deploy-scripts}" == /var/lib/deploy-scripts &&
        "${DEPLOY_OPERATION_LOG_ROOT:-/var/log/deploy-scripts}" == /var/log/deploy-scripts ]]; then
    "$function_name" "$@"
    return $?
  fi
  operation_start app "${APP_ID:-}" "$action" || error "Unable to start operation record for ${APP_NAME:-app} ${action}"
  if ! operation_step_start execute; then
    operation_finish 1 failed "failed to start execute step" || true
    error "Unable to record operation step for ${APP_NAME:-app} ${action}"
  fi
  local previous_trap previous_int_trap previous_term_trap previous_hup_trap
  previous_trap="$(trap -p EXIT)"
  previous_int_trap="$(trap -p INT)"
  previous_term_trap="$(trap -p TERM)"
  previous_hup_trap="$(trap -p HUP)"
  OPERATION_PREVIOUS_EXIT_TRAP="$previous_trap"
  OPERATION_PREVIOUS_INT_TRAP="$previous_int_trap"
  OPERATION_PREVIOUS_TERM_TRAP="$previous_term_trap"
  OPERATION_PREVIOUS_HUP_TRAP="$previous_hup_trap"
  trap 'operation_action_exit_trap' EXIT
  trap 'operation_action_signal_trap INT' INT
  trap 'operation_action_signal_trap TERM' TERM
  trap 'operation_action_signal_trap HUP' HUP
  log_path="$OPERATION_LOG_PATH"
  output_dir="$(mktemp -d "${TMPDIR:-/tmp}/deploy-operation-output.XXXXXX")" || {
    operation_restore_exit_trap "$previous_trap" || true
    operation_finish 1 failed 'failed to create operation output directory' || true
    return 1
  }
  chmod 700 "$output_dir" || {
    rm -rf -- "$output_dir"
    operation_restore_exit_trap "$previous_trap" || true
    operation_finish 1 failed 'failed to secure operation output directory' || true
    return 1
  }
  command -v mkfifo >/dev/null 2>&1 || {
    rm -rf -- "$output_dir"
    operation_restore_exit_trap "$previous_trap" || true
    operation_finish 1 failed 'mkfifo is required for operation logging' || true
    return 1
  }
  mkfifo "${output_dir}/stdout" "${output_dir}/stderr" || {
    rm -rf -- "$output_dir"
    operation_restore_exit_trap "$previous_trap" || true
    operation_finish 1 failed 'failed to create operation output pipes' || true
    return 1
  }
  OPERATION_OUTPUT_DIR="$output_dir"
  ( trap - EXIT; operation_stream_output "$log_path" <"${output_dir}/stdout" ) &
  OPERATION_STDOUT_PID=$!
  ( trap - EXIT; operation_stream_error "$log_path" <"${output_dir}/stderr" ) &
  OPERATION_STDERR_PID=$!
  # Readers are open before the action starts, so its output remains visible
  # immediately while a separately redacted copy is appended to the log.
  exec {OPERATION_SAVED_STDOUT_FD}>&1
  exec {OPERATION_SAVED_STDERR_FD}>&2
  # Keep the action in the current shell so application functions retain
  # their normal shell semantics. The wrapper EXIT trap records an explicit
  # `exit`, errexit termination, and ordinary non-zero returns alike.
  "$function_name" "$@" >"${output_dir}/stdout" 2>"${output_dir}/stderr"
  status=$?
  operation_finish_output_streams || true
  operation_restore_signal_traps || true
  operation_restore_exit_trap "$previous_trap" || true
  if [[ "$status" -eq 0 ]]; then
    operation_step_finish execute succeeded || operation_finish 1 failed "failed to finish execute step"
    operation_finish 0 || return 1
  else
    operation_step_finish execute failed || true
    operation_finish "$status" "" "${action} exited with status ${status}" || true
  fi
  # Per-app outcome notification (install/update/backup/restore/uninstall):
  # fail-open via notify_send, redacted, never changes the result. When the
  # notification library is not loaded (isolated/embedded use), the hook is
  # skipped silently — a missing notifier must not fail the action.
  if [[ -z "${DEPLOY_NOTIFY_SUPPRESS:-}" ]] && declare -F notify_send >/dev/null 2>&1; then
    case "$action" in
      install|update|backup|restore|uninstall)
        notify_send \
          "deploy-scripts: ${APP_ID:-app} ${action} $( [[ $status -eq 0 ]] && echo succeeded || echo FAILED )" \
          "${APP_ID:-app} ${action} on $(hostname 2>/dev/null || echo localhost) finished with status ${status}."
        ;;
    esac
  fi
  return "$status"
}
