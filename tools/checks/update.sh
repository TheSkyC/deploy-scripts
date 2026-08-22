#!/usr/bin/env bash

check_update_version_cache_and_network_failures() {
  local temp_root
  temp_root="$(mktemp -d)"
  if ! DEPLOY_VERSION_CACHE_ROOT="${temp_root}/cache" DEPLOY_VERSION_CACHE_TTL_SECONDS=60 DEPLOY_VERSION_NOW_EPOCH=100 "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    APP_ID=ntfy
    BA_BIN_NAME=ntfy
    GITHUB_REPO=binwiederhier/ntfy
    github_latest_release_tag_checked() { printf "v1.2.0\n"; }

    result="$(bapp_check_update_json v1.0.0 1 0)"
    [[ "$(state_json_field "$result" update_state)" == update_available ]]
    [[ "$(state_json_field "$result" cache_state)" == refreshed ]]
    [[ "$(state_json_field "$result" latest)" == v1.2.0 ]]

    github_latest_release_tag_checked() { echo "network should not be called" >&2; return 1; }
    result="$(bapp_check_update_json v1.0.0 0 0)"
    [[ "$(state_json_field "$result" update_state)" == update_available ]]
    [[ "$(state_json_field "$result" cache_state)" == fresh ]]
  '; then
    rm -rf "$temp_root"
    return 1
  fi
  if ! DEPLOY_VERSION_CACHE_ROOT="${temp_root}/cache" DEPLOY_VERSION_CACHE_TTL_SECONDS=60 DEPLOY_VERSION_NOW_EPOCH=200 "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    APP_ID=ntfy
    BA_BIN_NAME=ntfy
    GITHUB_REPO=binwiederhier/ntfy
    github_latest_release_tag_checked() { return 1; }

    result="$(bapp_check_update_json v1.0.0 0 0)"
    [[ "$(state_json_field "$result" update_state)" == stale ]]
    [[ "$(state_json_field "$result" latest)" == v1.2.0 ]]
    [[ "$(state_json_field "$result" cache_state)" == stale ]]

    rm -f "${DEPLOY_VERSION_CACHE_ROOT}/ntfy.json"
    result="$(bapp_check_update_json v1.0.0 0 0)"
    [[ "$(state_json_field "$result" update_state)" == check_failed ]]
    [[ "$(state_json_field "$result" latest)" == null ]]

    github_latest_release_tag_checked() { printf "v1.2.0\n"; }
    result="$(bapp_check_update_json bad-version 1 0)"
    [[ "$(state_json_field "$result" update_state)" == unknown ]]
  '; then
    rm -rf "$temp_root"
    return 1
  fi
  rm -rf "$temp_root"
}

check_check_update_target() {
  local output json_file status
  output="$($BASH_BIN deploy.sh check-update --json --include newapi)" || return 1
  json_file="$(mktemp)"
  printf '%s' "$output" > "$json_file"
  python - "$json_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)
assert payload["schema_version"] == 1
assert payload["summary"]["selected"] == 1
assert payload["records"][0]["app_id"] == "newapi"
assert payload["records"][0]["state"] == "skipped"
assert payload["records"][0]["version"]["update_state"] == "unsupported"
PY
  status=$?
  rm -f "$json_file"
  return "$status"
}

check_update_all_dry_run_target() {
  local output json_file status
  output="$($BASH_BIN deploy.sh update-all --dry-run --json --include newapi)" || return 1
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
assert payload["summary"]["planned"] == 0
assert payload["records"][0]["app_id"] == "newapi"
assert payload["records"][0]["action"] == "skip"
assert payload["records"][0]["reason"] == "not_installed"
PY
  status=$?
  rm -f "$json_file"
  return "$status"
}
check_update_target_selection_is_local_only() {
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
    manager_update_collect 0 0 "" ""
    [[ "$MANAGER_UPDATE_ERRORS" == 0 ]]
    [[ "$(state_json_field "${MANAGER_UPDATE_RECORDS[0]}" state)" == skipped ]]
    [[ "$(state_json_field "${MANAGER_UPDATE_RECORDS[0]}" reason)" == not_installed ]]
    printf ok
  ')"
  [[ "$output" == ok ]]
}

check_update_all_writes_manager_operation_record() {
  local temp_root output
  temp_root="$(mktemp -d)"
  output="$(DEPLOY_OPERATION_ROOT="$temp_root/state" DEPLOY_OPERATION_LOG_ROOT="$temp_root/logs" "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    available="$(version_check_emit_json v1.0.0 v1.1.0 now update_available github_release fresh)"
    manager_update_collect() {
      MANAGER_UPDATE_SELECTED=1
      MANAGER_UPDATE_INSTALLED=1
      MANAGER_UPDATE_AVAILABLE=1
      MANAGER_UPDATE_CURRENT=0
      MANAGER_UPDATE_UNSUPPORTED=0
      MANAGER_UPDATE_UNKNOWN=0
      MANAGER_UPDATE_STALE=0
      MANAGER_UPDATE_CHECK_FAILED=0
      MANAGER_UPDATE_ERRORS=0
      MANAGER_UPDATE_RECORDS=("$(manager_update_record alpha Alpha installed checked "" "$available")")
    }
    manager_update_collect_status() { return 0; }
    manager_update_acquire_lock() { return 0; }
    manager_update_release_lock() { :; }
    manager_update_execute_app() { return 0; }
    manager_update_all_main --yes --json >/dev/null
    cat "$DEPLOY_OPERATION_STATE_DIR/manager.json"
  ')"
  python -c 'import json,sys; x=json.loads(sys.argv[1]); assert x["scope"] == "manager"; assert x["action"] == "update-all"; assert x["state"] == "succeeded"; assert x["exit_code"] == 0; assert x["steps"][0]["name"] == "execute"; assert x["steps"][0]["state"] == "succeeded"' "$output"
  local status=$?
  rm -rf "$temp_root"
  return "$status"
}

check_update_all_execution_is_serial_and_safe() {
  local temp_root output json_file status
  temp_root="$(mktemp -d)"
  set +e
  output="$(ORDER_FILE="${temp_root}/order" DEPLOY_OPERATION_ROOT="${temp_root}/state" DEPLOY_OPERATION_LOG_ROOT="${temp_root}/log" "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    manager_update_collect() {
      local available current
      available="$(version_check_emit_json v1.0.0 v1.1.0 now update_available github_release fresh)"
      current="$(version_check_emit_json v1.0.0 v1.0.0 now up_to_date github_release fresh)"
      MANAGER_UPDATE_SELECTED=3
      MANAGER_UPDATE_INSTALLED=3
      MANAGER_UPDATE_AVAILABLE=2
      MANAGER_UPDATE_CURRENT=1
      MANAGER_UPDATE_UNSUPPORTED=0
      MANAGER_UPDATE_UNKNOWN=0
      MANAGER_UPDATE_STALE=0
      MANAGER_UPDATE_CHECK_FAILED=0
      MANAGER_UPDATE_ERRORS=0
      MANAGER_UPDATE_RECORDS=(
        "$(manager_update_record alpha Alpha installed checked "" "$available")"
        "$(manager_update_record beta Beta installed checked "" "$available")"
        "$(manager_update_record gamma Gamma installed checked "" "$current")"
      )
    }
    manager_update_collect_status() { return 0; }
    manager_update_acquire_lock() { return 0; }
    manager_update_release_lock() { return 0; }
    manager_update_execute_app() {
      printf "%s\\n" "$1" >> "$ORDER_FILE"
      [[ "$1" != beta ]]
    }
    manager_update_all_main --yes --json
  ')"
  status=$?
  set -e
  if [[ "$status" -ne 1 ]]; then
    rm -rf "$temp_root"
    return 1
  fi
  [[ "$(cat "${temp_root}/order")" == $'alpha\nbeta' ]] || { rm -rf "$temp_root"; return 1; }
  json_file="$(mktemp)"
  printf '%s' "$output" > "$json_file"
  python - "$json_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)
assert payload["dry_run"] is False
assert payload["summary"] == {
    "selected": 3,
    "planned": 2,
    "updated": 1,
    "failed": 1,
    "skipped": 1,
    "check_failed": 0,
    "errors": 0,
}
assert [record["state"] for record in payload["records"]] == ["succeeded", "failed", "skipped"]
assert [record["app_id"] for record in payload["records"]] == ["alpha", "beta", "gamma"]
PY
  status=$?
  rm -f "$json_file"
  rm -rf "$temp_root"
  return "$status"
}