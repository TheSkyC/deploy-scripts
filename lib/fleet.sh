#!/usr/bin/env bash

# Fleet / multi-machine management: run status-all / update-all / backup-all
# across a host inventory over SSH with per-host timeouts, bounded concurrency
# and failure isolation, then merge the per-host JSON results. SSH credentials
# are never written to logs: hosts connect through the local SSH agent / keys
# only, and no password/token values are accepted in the inventory.
#
# Inventory format (/etc/deploy-hosts.conf, root:600, one host per line):
#   alias|user@host[:port]
# Blank lines and # comments are ignored; alias must be a simple token.

FLEET_HOSTS_FILE="${FLEET_HOSTS_FILE:-/etc/deploy-hosts.conf}"
FLEET_CONCURRENCY="${FLEET_CONCURRENCY:-4}"
FLEET_TIMEOUT="${FLEET_TIMEOUT:-120}"
FLEET_SSH_OPTS=(-o BatchMode=yes -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new)

fleet_load_hosts() {
  FLEET_HOSTS=()
  local line alias target
  [[ -f "$FLEET_HOSTS_FILE" ]] || return 0
  # Same trust gate as app/notify/schedule configs: a world-writable host
  # inventory could redirect batch operations to an attacker-controlled
  # host, so non-root-owned or loose-mode files are ignored entirely.
  # (The inventory lines carry no key=value shape, so the owner/mode check
  # is done inline rather than through app_conf_trusted_value.)
  local owner mode
  owner="$(stat -c '%U' "$FLEET_HOSTS_FILE" 2>/dev/null || printf unknown)"
  mode="$(stat -c '%a' "$FLEET_HOSTS_FILE" 2>/dev/null || printf unknown)"
  if [[ "$owner" != root || ( "$mode" != 600 && "$mode" != 400 ) ]]; then
    echo "fleet: ignoring untrusted host inventory: $FLEET_HOSTS_FILE" >&2
    return 0
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"
    [[ -n "$line" ]] || continue
    alias="${line%%|*}"
    target="${line#*|}"
    case "$alias" in
      *[!A-Za-z0-9_-]*|"") continue ;;
    esac
    case "$target" in
      *[!A-Za-z0-9@.:\[\]_-]*|""|*" "*)
        echo "fleet: skipping host with invalid target: $alias" >&2
        continue
        ;;
    esac
    FLEET_HOSTS+=("$alias|$target")
  done < "$FLEET_HOSTS_FILE"
}

# SSH destination with an explicit -p port when the target carries one.
fleet_target_ssh_args() {
  local target="$1" port=""
  if [[ "$target" == *:* ]]; then
    port="${target##*:}"
    target="${target%:*}"
    [[ "$port" =~ ^[0-9]+$ ]] || port=""
  fi
  printf '%s' "$target"
  [[ -n "$port" ]] && printf ' -p %s' "$port"
}

# Run one remote command for one host; prints a single-line JSON record.
fleet_run_host() {
  local alias="$1" target="$2" remote_script="$3"
  local output record
  # Each SSH opt is a single token (no spaces), and fleet_target_ssh_args
  # emits space-separated "host [-p port]" pieces; expansion is deliberate.
  # shellcheck disable=SC2046,SC2048,SC2086
  output="$(timeout "${FLEET_TIMEOUT}" ssh ${FLEET_SSH_OPTS[*]} \
    $(fleet_target_ssh_args "$target") \
    "bash -s" <<REMOTE 2>/dev/null
set -euo pipefail
${remote_script}
REMOTE
  )" || {
    printf '{"host":%s,"ok":false,"error":"ssh or remote command failed"}' \
      "$(app_json_string "$alias")"
    return 0
  }
  # The remote side is this same framework; keep its last non-empty line.
  record="$(printf '%s\n' "$output" | tr -d '\r' | sed '/^[[:space:]]*$/d' | tail -n 1)"
  # A polluted or non-JSON remote line would corrupt the merged summary, so
  # validate the record is parseable JSON before embedding it.
  if ! printf '%s' "$record" | grep -qE '^\{.*\}$'; then
    record="{\"error\":$(app_json_string "$record")}"
  fi
  printf '{"host":%s,"ok":true,"result":%s}' \
    "$(app_json_string "$alias")" "$record"
}

fleet_main() {
  local subcommand="${1:-status-all}"
  shift || true
  case "${subcommand,,}" in
    status-all|update-all|backup-all) ;;
    *)
      echo "Usage: sudo bash $0 fleet [status-all|update-all|backup-all] [--hosts FILE] [--concurrency N] [--timeout SEC]" >&2
      return 2
      ;;
  esac
  local action="${subcommand,,}"
  while (($#)); do
    case "$1" in
      --hosts) FLEET_HOSTS_FILE="${2:-}"; shift 2 ;;
      --concurrency) FLEET_CONCURRENCY="${2:-}"; shift 2 ;;
      --timeout) FLEET_TIMEOUT="${2:-}"; shift 2 ;;
      *) echo "fleet: unknown option: $1" >&2; return 2 ;;
    esac
  done
  [[ "$FLEET_CONCURRENCY" =~ ^[0-9]+$ ]] && (( FLEET_CONCURRENCY >= 1 )) || FLEET_CONCURRENCY=4
  [[ "$FLEET_TIMEOUT" =~ ^[0-9]+$ ]] && (( FLEET_TIMEOUT >= 10 )) || FLEET_TIMEOUT=120
  fleet_load_hosts
  if [[ ${#FLEET_HOSTS[@]} -eq 0 ]]; then
    echo "fleet: no hosts configured in $FLEET_HOSTS_FILE" >&2
    return 1
  fi
  local remote_script
  remote_script="cd /opt/deploy-scripts 2>/dev/null && bash deploy.sh ${action} --json 2>/dev/null || echo '{\"state\":\"failed\"}'"
  # Run with bounded concurrency; each host writes its JSON record to its
  # own temp file, and failures are isolated per host.
  local tmp_root alias target entry pid
  tmp_root="$(mktemp -d)"
  local -a pids=() running=()
  for entry in "${FLEET_HOSTS[@]}"; do
    alias="${entry%%|*}"
    target="${entry#*|}"
    out_file="$tmp_root/${alias}.json"
    ( fleet_run_host "$alias" "$target" "$remote_script" > "$out_file" ) &
    pids+=($!)
    running+=("$alias")
    if (( ${#pids[@]} >= FLEET_CONCURRENCY )); then
      wait "${pids[0]}" 2>/dev/null || true
      pids=("${pids[@]:1}")
      running=("${running[@]:1}")
    fi
  done
  for pid in "${pids[@]}"; do
    wait "$pid" 2>/dev/null || true
  done
  local first=1 record
  local summary
  summary="$(printf '{"schema_version":1,"action":"%s","concurrency":%s,"hosts":[' \
    "$action" "$FLEET_CONCURRENCY")"
  for entry in "${FLEET_HOSTS[@]}"; do
    alias="${entry%%|*}"
    record="$(cat "$tmp_root/${alias}.json" 2>/dev/null || true)"
    [[ -n "$record" ]] || record="{\"host\":$(app_json_string "$alias"),\"ok\":false,\"error\":\"no result\"}"
    (( first )) || summary+=","
    first=0
    summary+="$record"
  done
  summary+="]}"
  printf '%s\n' "$summary"
  # Machine-level operation history: one JSON line per fleet run, appended
  # under the framework log root. Best-effort; never fails the command.
  local history_dir history_file
  history_dir="${DEPLOY_OPERATION_LOG_ROOT:-/var/log/deploy-scripts}"
  history_file="${history_dir}/fleet-history.jsonl"
  mkdir -p "$history_dir" 2>/dev/null || true
  printf '%s\n' "$summary" >> "$history_file" 2>/dev/null || true
  rm -rf "$tmp_root"
}
