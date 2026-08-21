# shellcheck shell=bash

check_state_json_contract() {
  local output
  set +e
  output="$(DEPLOY_STATUS_TIMEOUT_SECONDS=30 DEPLOY_STATUS_NO_PROBE=1 "$BASH_BIN" deploy.sh status-all --json --include newapi)"
  local command_status=$?
  set -e
  [[ "$command_status" -eq 0 ]] || return "$command_status"
  local json_file
  json_file="$(mktemp)"
  printf '%s' "$output" > "$json_file"
  python -c 'import json,sys; x=json.load(open(sys.argv[1])); assert x["schema_version"] == 1; assert len(x["apps"]) == 1; a=x["apps"][0]; assert a["schema_version"] == 2; assert a["install_state"] in {"not_installed","installed","install_failed","unknown"}; assert a["health"]["state"] in {"not_checked","unsupported"}' "$json_file"
  rm -f "$json_file"
}

check_state_target_selection() {
  local output
  set +e
  output="$(DEPLOY_STATUS_TIMEOUT_SECONDS=30 DEPLOY_STATUS_NO_PROBE=1 "$BASH_BIN" deploy.sh status-all --json --include newapi,ntfy --exclude ntfy)"
  local command_status=$?
  set -e
  [[ "$command_status" -eq 0 ]] || return "$command_status"
  local json_file
  json_file="$(mktemp)"
  printf '%s' "$output" > "$json_file"
  python -c 'import json,sys; x=json.load(open(sys.argv[1])); assert [a["app_id"] for a in x["apps"]] == ["newapi"]' "$json_file"
  rm -f "$json_file"
  set +e
  "$BASH_BIN" deploy.sh status-all --include does-not-exist >/dev/null 2>&1
  local status=$?
  set -e
  [[ "$status" -eq 2 ]]
}

check_state_scalar_parser_and_severity() {
  local output
  output="$($BASH_BIN <<'BASH'
set -euo pipefail
source lib/core.sh
value='quote"back\slash'
json=$(printf '{"message":%s,"nested":{"value":%s}}' "$(app_json_string "$value")" "$(app_json_string "$value")")
parsed=$(state_json_field "$json" message)
nested=$(state_json_field "$json" nested.value)
[[ "$parsed" == "$value" && "$nested" == "$value" ]]
[[ "$(state_json_field '{"value":null}' value)" == null ]]
[[ "$(state_severity installed true false not_managed unsupported unknown null)" == critical ]]
printf ok
BASH
  )"
  [[ "$output" == ok ]]
}

check_state_operation_error_code_projection() {
  local temp_root output json_file
  temp_root="$(mktemp -d)"
  output="$(DEPLOY_OPERATION_ROOT="$temp_root/state" DEPLOY_OPERATION_LOG_ROOT="$temp_root/logs" STATUS_TEST_CONFIG="$temp_root/config" "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    APP_ID=newapi
    APP_NAME="New API"
    app_conf_file() { printf "%s" "$DEPLOY_OPERATION_ROOT/missing.conf"; }
    app_doctor_service_name() { return 1; }
    mkdir -p "$DEPLOY_OPERATION_STATE_DIR"
    cat >"$DEPLOY_OPERATION_STATE_DIR/newapi.json" <<"JSON"
{"schema_version":1,"run_id":"run","scope":"app","app_id":"newapi","action":"update","state":"failed","started_at":"2026-08-21T00:00:00+08:00","finished_at":"2026-08-21T00:01:00+08:00","last_step":"health","steps":[],"exit_code":7,"error":"TOKEN=[REDACTED]","log_path":"/tmp/deploy.log"}
JSON
    app_status_collect_json
  ')"
  json_file="$(mktemp)"
  printf '%s' "$output" >"$json_file"
  python - "$json_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)
operation = payload["operation"]
assert operation["last_result"] == "failed"
assert operation["last_error_code"] == 7
assert operation["last_error_summary"] == "TOKEN=[REDACTED]"
PY
  local status=$?
  rm -f "$json_file"
  rm -rf "$temp_root"
  return "$status"
}

check_state_backup_extension_contract() {
  local output json_file
  output="$($BASH_BIN -c '
    set -euo pipefail
    source lib/core.sh
    APP_ID=newapi
    APP_NAME="New API"
    : > /tmp/deploy-status-backup-test.conf
    app_conf_file() { printf "%s" /tmp/deploy-status-backup-test.conf; }
    app_doctor_service_name() { return 1; }
    APP_STATUS_BACKUP_FN=check_backup
    check_backup() {
      printf "%s" "{\"state\":\"available\",\"last_success_at\":\"2026-08-21T00:00:00+08:00\",\"path\":\"/var/backups/newapi\",\"message\":null}"
    }
    app_status_collect_json
  ')"
  json_file="$(mktemp)"
  printf '%s' "$output" >"$json_file"
  python - "$json_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)
backup = payload["backup"]
assert backup["state"] == "available"
assert backup["last_success_at"] == "2026-08-21T00:00:00+08:00"
assert backup["path"] == "/var/backups/newapi"
PY
  local status=$?
  rm -f "$json_file"
  return "$status"
}

check_state_no_network_locality() {
  local output
  output="$($BASH_BIN -c '
    source lib/core.sh
    state_health_url_is_local http://127.0.0.1:8080/health
    state_health_url_is_local http://localhost/health
    state_health_url_is_local http://[::1]/health
    ! state_health_url_is_local https://example.com/health
    printf ok
  ')"
  [[ "$output" == ok ]]
}


check_state_problems_filtering() {
  local output json_file
  output="$(DEPLOY_STATUS_TIMEOUT_SECONDS=30 DEPLOY_STATUS_NO_PROBE=1 "$BASH_BIN" deploy.sh problems --json --include newapi)"
  json_file="$(mktemp)"
  printf '%s' "$output" > "$json_file"
  python -c 'import json,sys; x=json.load(open(sys.argv[1])); assert x["apps"] == []; assert x["summary"]["registered"] == 16; assert x["summary"]["selected"] == 1' "$json_file"
  rm -f "$json_file"
}


check_health_all_target() {
  local output json_file
  output="$(DEPLOY_STATUS_TIMEOUT_SECONDS=30 DEPLOY_STATUS_NO_PROBE=1 "$BASH_BIN" deploy.sh health-all --json --include newapi)"
  json_file="$(mktemp)"
  printf '%s' "$output" > "$json_file"
  python -c 'import json,sys; x=json.load(open(sys.argv[1])); assert x["schema_version"] == 1; assert x["apps"] == []; assert x["summary"]["selected"] == 1' "$json_file"
  rm -f "$json_file"
}

check_state_status_matrix() {
  local output
  output="$($BASH_BIN -c '
    set -euo pipefail
    source lib/core.sh
    [[ "$(state_severity not_installed true true not_managed unsupported unknown null)" == info ]]
    [[ "$(state_severity installed true true stopped not_checked unknown unsupported)" == error ]]
    [[ "$(state_severity installed true true running unhealthy unknown unsupported)" == error ]]
    [[ "$(state_severity installed false true running healthy unknown unsupported)" == critical ]]
    [[ "$(state_severity installed true true running healthy unknown unsupported)" == ok ]]
    state_health_json installed running
    state_version_json /definitely/missing/config
  ')"
  [[ "$output" == *'"state":"not_checked"'* ]]
  [[ "$output" == *'"update_state":"unknown"'* ]]
}
check_state_load_failure_isolation() {
  local temp_root output status json_file
  temp_root="$(mktemp -d)"
  set +e
  output="$(DEPLOY_OPERATION_ROOT="$temp_root/state" DEPLOY_OPERATION_LOG_ROOT="$temp_root/log" "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    manager_status_selected_ids() { printf "broken\\nhealthy\\n"; }
    manager_status_collect_app_json() {
      if [[ "$1" == broken ]]; then
        printf "definition load failed" > "$3"
        return 1
      fi
      printf "%s" "{\"app_id\":\"healthy\",\"app_name\":\"Healthy\",\"install_state\":\"installed\",\"severity\":\"ok\",\"health\":{\"state\":\"healthy\"},\"version\":{\"update_state\":\"unknown\"},\"service\":{\"state\":\"running\"}}" > "$2"
    }
    manager_status_main status-all --json --strict
  ')"
  status=$?
  set -e
  json_file="$(mktemp)"
  printf '%s' "$output" > "$json_file"
  python - "$json_file" "$status" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)
assert int(sys.argv[2]) == 1
assert [app["app_id"] for app in payload["apps"]] == ["healthy"]
assert payload["errors"][0]["app_id"] == "broken"
assert payload["errors"][0]["summary"] == "definition load failed"
PY
  status=$?
  rm -f "$json_file"
  rm -rf "$temp_root"
  return "$status"
}
