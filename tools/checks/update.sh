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