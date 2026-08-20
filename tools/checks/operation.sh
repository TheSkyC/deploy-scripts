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


check_doctor_all_target() {
  local output json_file
  output="$($BASH_BIN deploy.sh doctor-all --json --include newapi)"
  json_file="$(mktemp)"
  printf '%s' "$output" > "$json_file"
  python -c 'import json,sys; x=json.load(open(sys.argv[1])); assert x["schema_version"] == 1; assert x["records"] == []' "$json_file"
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
