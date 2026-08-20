# shellcheck shell=bash

check_state_json_contract() {
  local output
  set +e
  output="$(DEPLOY_STATUS_NO_PROBE=1 "$BASH_BIN" deploy.sh status-all --json --include newapi)"
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
  output="$(DEPLOY_STATUS_NO_PROBE=1 "$BASH_BIN" deploy.sh status-all --json --include newapi,ntfy --exclude ntfy)"
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
  local output json
  output="$($BASH_BIN -c '
    source lib/core.sh
    value="quote\"back\\slash"
    json=$(printf "{\\"message\\":%s,\\"nested\\":{\\"value\\":%s}}" "$(app_json_string "$value")" "$(app_json_string "$value")")
    parsed=$(state_json_field "$json" message)
    nested=$(state_json_field "$json" nested.value)
    [[ "$parsed" == "$value" && "$nested" == "$value" ]] || exit 1
    [[ "$(state_json_field "{\\"value\\":null}" value)" == null ]] || exit 1
    [[ "$(state_severity installed true false not_managed unsupported unknown null)" == critical ]] || exit 1
    printf ok
  ')"
  [[ "$output" == ok ]]
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
  output="$(DEPLOY_STATUS_NO_PROBE=1 "$BASH_BIN" deploy.sh problems --json --include newapi)"
  json_file="$(mktemp)"
  printf '%s' "$output" > "$json_file"
  python -c 'import json,sys; x=json.load(open(sys.argv[1])); assert x["apps"] == []; assert x["summary"]["registered"] == 16; assert x["summary"]["selected"] == 1' "$json_file"
  rm -f "$json_file"
}
