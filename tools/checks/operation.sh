# shellcheck shell=bash
# Foundational semantic-version and operation-record checks. These checks are
# intentionally self-contained and use temporary roots instead of system paths.

check_version_helpers() {
  "$BASH_BIN" -c '
    set -euo pipefail
    source lib/version.sh
    [[ "$(deploy_version_compare v1.2.3 1.2.4)" == -1 ]]
    [[ "$(deploy_version_compare 1.0.0-alpha 1.0.0)" == -1 ]]
    [[ "$(deploy_version_compare 1.0.0-alpha.1 1.0.0-alpha.beta)" == -1 ]]
    [[ "$(deploy_version_compare 1.0.0+build.1 1.0.0+build.2)" == 0 ]]
    ! deploy_version_normalize 01.0.0
    ! deploy_version_normalize 1.0
  '
}

# operation_json_escape and app_json_string must escape identically: the
# escapers used to disagree (\b, \f, and C0 controls were unescaped in
# operation records), letting a control byte in a step name or error summary
# produce invalid JSON there while status JSON handled it correctly.
check_operation_json_escape_matches_app_json_string() {
  "$BASH_BIN" -c '
    set -euo pipefail
    source "$1/lib/core.sh"
    check_pair() {
      local input="$1" a b
      a="$(app_json_string "$input")"
      a="${a:1:${#a}-2}"
      b="$(operation_json_escape "$input")"
      [[ "$a" == "$b" ]] || { printf "escaper mismatch for %q: app=[%s] op=[%s]\n" "$input" "$a" "$b" >&2; exit 1; }
    }
    check_pair "plain text"
    check_pair "back\\slash"
    check_pair "quote\"inside"
    check_pair "$(printf "tab\there")"
    check_pair "$(printf "bell\a vtab\x0b unit\x1f sep")"
    check_pair ""
    exit 0
  ' _ "$ROOT_DIR"
}

check_operation_records() {
  local temp_root
  temp_root="$(mktemp -d)"
  if ! DEPLOY_OPERATION_ROOT="${temp_root}/state" \
    DEPLOY_OPERATION_LOG_ROOT="${temp_root}/log" \
    "$BASH_BIN" -c '
      set -euo pipefail
      source lib/operation.sh
      operation_start app newapi update
      operation_step_start download
      operation_step_finish download
      operation_finish 0
    '; then
    rm -rf "$temp_root"
    return 1
  fi
  set +e
  python - "$temp_root/state/state/newapi.json" "$temp_root/state/history/operations.jsonl" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    record = json.load(handle)
assert record["state"] == "succeeded"
assert record["steps"][0]["name"] == "download"
assert record["steps"][0]["finished_at"]
with open(sys.argv[2], encoding="utf-8") as handle:
    assert len(handle.readlines()) == 1
PY
  local status=$?
  rm -rf "$temp_root"
  return "$status"
}

check_operation_logrotate_policy() {
  local temp_root policy_path
  temp_root="$(mktemp -d)"
  policy_path="${temp_root}/etc/logrotate.d/deploy-scripts"
  if ! DEPLOY_OPERATION_LOG_ROOT="${temp_root}/var/log/deploy-scripts" \
    DEPLOY_OPERATION_LOGROTATE_FILE="$policy_path" \
    DEPLOY_OPERATION_LOGROTATE_DAYS=30 \
    DEPLOY_OPERATION_LOGROTATE_FILES=20 \
    "$BASH_BIN" -c '
      set -euo pipefail
      source lib/operation.sh
      operation_write_logrotate
    '; then
    rm -rf "$temp_root"
    return 1
  fi
  if ! grep -Fqx "${temp_root}/var/log/deploy-scripts/*/*.log {" "$policy_path" \
    || ! grep -Fqx '    daily' "$policy_path" \
    || ! grep -Fqx '    rotate 20' "$policy_path" \
    || ! grep -Fqx '    maxage 30' "$policy_path" \
    || ! grep -Fqx '    create 0640 root root' "$policy_path" \
    || [[ "$(stat -c '%a' "$policy_path" 2>/dev/null || true)" != 644 ]]; then
    rm -rf "$temp_root"
    return 1
  fi
  rm -rf "$temp_root"
}

check_app_action_operation_wrapping() {
  local temp_root status
  temp_root="$(mktemp -d)"
  if ! DEPLOY_OPERATION_ROOT="${temp_root}/state" DEPLOY_OPERATION_LOG_ROOT="${temp_root}/log" "$BASH_BIN" -c '
    set -euo pipefail
    source lib/operation.sh
    APP_ID=newapi
    APP_NAME="New API"
    error() { return 1; }
    do_succeed() {
      printf "stdout TOKEN=top-secret\n"
      printf "stderr PASSWORD=secret-value\n" >&2
      printf "https://user:password@example.invalid/private\n" >&2
    }
    operation_run_app_action update do_succeed
  '; then
    rm -rf "$temp_root"
    return 1
  fi
  if ! python - "${temp_root}/state/state/newapi.json" "${temp_root}/state/history/operations.jsonl" "$temp_root" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    record = json.load(handle)
assert record["action"] == "update"
assert record["state"] == "succeeded"
assert record["exit_code"] == 0
assert record["steps"] == [{"name": "execute", "state": "succeeded", "started_at": record["steps"][0]["started_at"], "finished_at": record["steps"][0]["finished_at"]}]
assert record["steps"][0]["finished_at"]
log_path = record["log_path"]
if sys.platform == "win32" and log_path.startswith("/"):
    log_path = sys.argv[3] + log_path[log_path.find("/log/"):]
with open(log_path, encoding="utf-8") as handle:
    log = handle.read()
assert "stdout TOKEN=[REDACTED]" in log
assert "stderr PASSWORD=[REDACTED]" in log
assert "https://user:[REDACTED]@example.invalid/private" in log
assert "top-secret" not in log and "secret-value" not in log and "user:password@" not in log
with open(sys.argv[2], encoding="utf-8") as handle:
    assert len(handle.readlines()) == 1
PY
  then
    rm -rf "$temp_root"
    return 1
  fi
  set +e
  DEPLOY_OPERATION_ROOT="${temp_root}/failure-state" DEPLOY_OPERATION_LOG_ROOT="${temp_root}/failure-log" "$BASH_BIN" -c '
    set -euo pipefail
    source lib/operation.sh
    APP_ID=newapi
    APP_NAME="New API"
    error() { return 1; }
    do_fail() { printf "failure TOKEN=failed-secret\n"; exit 7; }
    operation_run_app_action update do_fail
  '
  status=$?
  set -e
  if [[ "$status" -ne 7 ]]; then
    rm -rf "$temp_root"
    return 1
  fi
  python - "${temp_root}/failure-state/state/newapi.json" "${temp_root}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    record = json.load(handle)
assert record["action"] == "update"
assert record["state"] == "failed"
assert record["exit_code"] == 7
assert record["steps"][0]["name"] == "execute"
assert record["steps"][0]["state"] == "failed"
assert record["steps"][0]["finished_at"]
log_path = record["log_path"]
if sys.platform == "win32" and log_path.startswith("/"):
    log_path = sys.argv[2] + log_path[log_path.find("/failure-log/"):]
with open(log_path, encoding="utf-8") as handle:
    log = handle.read()
assert "failure TOKEN=[REDACTED]" in log
assert "failed-secret" not in log
PY
  status=$?
  rm -rf "$temp_root"
  return "$status"
}
check_operation_failure_traps() {
  local temp_root status
  temp_root="$(mktemp -d)"
  set +e
  DEPLOY_OPERATION_ROOT="${temp_root}/state" DEPLOY_OPERATION_LOG_ROOT="${temp_root}/log" "$BASH_BIN" -c '
    set -euo pipefail
    source lib/lock.sh
    source lib/operation.sh
    APP_ID=newapi
    APP_NAME="New API"
    marker="$1"
    error() { return 1; }
    record_first() { printf "first:%s\n" "$?" >> "$marker"; }
    record_second() { printf "second:%s\n" "$?" >> "$marker"; }
    deploy_add_exit_handler record_first
    deploy_add_exit_handler record_second
    do_fail() { printf "return PASSWORD=failed-secret\n"; return 7; }
    operation_run_app_action update do_fail
    status=$?
    exit "$status"
  ' _ "${temp_root}/marker"
  status=$?
  set -e
  if [[ "$status" -ne 7 ]] ||
     ! grep -qx 'second:7' "${temp_root}/marker" 2>/dev/null ||
     ! grep -qx 'first:7' "${temp_root}/marker" 2>/dev/null ||
     [[ "$(wc -l < "${temp_root}/marker" 2>/dev/null)" -ne 2 ]]; then
    rm -rf "$temp_root"
    return 1
  fi
  set +e
  DEPLOY_OPERATION_ROOT="${temp_root}/sete-state" DEPLOY_OPERATION_LOG_ROOT="${temp_root}/sete-log" "$BASH_BIN" -c '
    set -euo pipefail
    source lib/operation.sh
    APP_ID=newapi
    APP_NAME="New API"
    error() { return 1; }
    do_sete() { set -e; printf "set-e SECRET=failed-secret\n"; false; printf "unreachable\n"; }
    operation_run_app_action update do_sete
  '
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    rm -rf "$temp_root"
    return 1
  fi
  python - "${temp_root}/sete-state/state/newapi.json" "${temp_root}" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    record = json.load(handle)
assert record["state"] == "failed"
assert record["exit_code"] != 0
log_path = record["log_path"]
if log_path.startswith("/") and sys.platform == "win32":
    log_path = sys.argv[2] + log_path[log_path.find("/sete-log/"):]
with open(log_path, encoding="utf-8") as handle:
    log = handle.read()
assert "set-e SECRET=[REDACTED]" in log
assert "unreachable" not in log
PY
  status=$?
  rm -rf "$temp_root"
  return "$status"
}
check_operation_scopes_are_distinct() {
  local temp_root
  temp_root="$(mktemp -d)"
  if ! DEPLOY_OPERATION_ROOT="${temp_root}/state" DEPLOY_OPERATION_LOG_ROOT="${temp_root}/log" "$BASH_BIN" -c '
    set -euo pipefail
    source lib/operation.sh
    APP_ID=newapi
    operation_start app newapi update
    operation_finish 0
    operation_start manager "" update-all
    operation_finish 0
    operation_start self_update "" self-update
    operation_finish 0
  '; then
    rm -rf "$temp_root"
    return 1
  fi
  python - "${temp_root}/state/state/newapi.json" "${temp_root}/state/state/manager.json" "${temp_root}/state/self-update.json" <<'PY'
import json
import sys

app, manager, self_update = [json.load(open(path, encoding="utf-8")) for path in sys.argv[1:]]
assert (app["scope"], app["app_id"], app["action"]) == ("app", "newapi", "update")
assert (manager["scope"], manager["app_id"], manager["action"]) == ("manager", None, "update-all")
assert (self_update["scope"], self_update["app_id"], self_update["action"]) == ("self_update", None, "self-update")
PY
  local status=$?
  rm -rf "$temp_root"
  return "$status"
}
check_history_command() {
  local temp_root output json_file
  temp_root="$(mktemp -d)"
  DEPLOY_OPERATION_ROOT="${temp_root}/state" DEPLOY_OPERATION_LOG_ROOT="${temp_root}/log" "$BASH_BIN" -c '
    set -euo pipefail
    source lib/operation.sh
    operation_start app newapi update
    operation_finish 0
  '
  output="$(DEPLOY_OPERATION_ROOT="${temp_root}/state" DEPLOY_OPERATION_LOG_ROOT="${temp_root}/log" "$BASH_BIN" deploy.sh history --json --limit 5)"
  json_file="$(mktemp)"
  printf '%s' "$output" > "$json_file"
  python -c 'import json,sys; x=json.load(open(sys.argv[1])); assert x["schema_version"] == 1; assert len(x["records"]) == 1; assert x["records"][0]["app_id"] == "newapi"; assert x["records"][0]["state"] == "succeeded"' "$json_file"
  rm -f "$json_file"
  rm -rf "$temp_root"
}


check_batch_target_selection_is_local_only() {
  local output
  output="$($BASH_BIN -c '
    set -euo pipefail
    source lib/core.sh
    manager_status_selected_ids() { printf "newapi\n"; }
    manager_status_collect_app_json() {
      [[ "${DEPLOY_STATUS_NO_PROBE:-0}" == 1 ]] || return 91
      [[ "${DEPLOY_STATUS_NO_NETWORK:-0}" == 1 ]] || return 92
      printf "%s" "{\"install_state\":\"not_installed\"}" > "$2"
      : > "$3"
    }
    manager_doctor_main --json --include newapi >/dev/null
    manager_backup_main --dry-run --json --include newapi >/dev/null
    printf ok
  ')"
  [[ "$output" == ok ]]
}

check_doctor_all_target() {
  local output json_file
  output="$($BASH_BIN <<'DOCTORTEST'
set -euo pipefail
source lib/core.sh
manager_status_selected_ids() { printf 'newapi\n'; }
manager_status_collect_app_json() {
  [[ "${DEPLOY_STATUS_NO_PROBE:-0}" == 1 ]] || return 91
  [[ "${DEPLOY_STATUS_NO_NETWORK:-0}" == 1 ]] || return 92
  printf '%s' '{"install_state":"not_installed"}' > "$2"
  : > "$3"
}
manager_main doctor-all --json --include newapi
DOCTORTEST
  )"
  json_file="$(mktemp)"
  printf '%s' "$output" > "$json_file"
  python -c 'import json,sys; x=json.load(open(sys.argv[1])); assert x["schema_version"] == 1; assert x["summary"]["selected"] == 1; assert x["summary"]["skipped"] == 1; assert x["records"][0]["state"] == "skipped"' "$json_file"
  rm -f "$json_file"
}

check_backup_all_dry_run() {
  local output json_file
  output="$($BASH_BIN deploy.sh backup-all --dry-run --json --include newapi)"
  json_file="$(mktemp)"
  printf '%s' "$output" > "$json_file"
  python - "$json_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)
assert payload["schema_version"] == 1
assert payload["dry_run"] is True
assert payload["summary"]["selected"] == 1
assert len(payload["records"]) == 1
assert payload["records"][0]["app_id"] == "newapi"
assert payload["records"][0]["action"] in {"skip", "plan", "error"}
PY
  local status=$?
  rm -f "$json_file"
  return "$status"
}

check_operation_signal_interruption() {
  local temp_root signal status expected marker
  temp_root="$(mktemp -d)"
  for signal in INT TERM HUP; do
    case "$signal" in
      INT) expected=130 ;;
      TERM) expected=143 ;;
      HUP) expected=129 ;;
    esac
    marker="${temp_root}/${signal}.marker"
    set +e
    DEPLOY_OPERATION_ROOT="${temp_root}/${signal}-state" DEPLOY_OPERATION_LOG_ROOT="${temp_root}/${signal}-log" "$BASH_BIN" -c '
      set -euo pipefail
      source lib/lock.sh
      source lib/operation.sh
      APP_ID=newapi
      APP_NAME="New API"
      marker="$1"
      signal="$2"
      record_exit() { printf "exit:%s\n" "$?" >> "$marker"; }
      deploy_add_exit_handler record_exit
      do_interrupt() {
        printf "before interrupt %s\n" "$signal"
        kill -s "$signal" "$$"
      }
      operation_run_app_action update do_interrupt
    ' _ "$marker" "$signal"
    status=$?
    set -e
    [[ "$status" -eq "$expected" ]] || { rm -rf "$temp_root"; return 1; }
    python - "${temp_root}/${signal}-state/state/newapi.json" "$marker" "$signal" "$expected" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    record = json.load(handle)
assert record["state"] == "interrupted"
assert record["exit_code"] == int(sys.argv[4])
assert f"SIG{sys.argv[3]}" in record["error"]
assert record["steps"][0]["name"] == "execute"
assert record["steps"][0]["state"] == "failed"
with open(sys.argv[2], encoding="utf-8") as handle:
    assert handle.read() == f"exit:{sys.argv[4]}\n"
PY
    status=$?
    [[ "$status" -eq 0 ]] || { rm -rf "$temp_root"; return "$status"; }
  done
  rm -rf "$temp_root"
}
