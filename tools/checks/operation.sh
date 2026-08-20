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
  python3 - "$temp_root/state/state/newapi.json" "$temp_root/state/history/operations.jsonl" <<'PY'
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