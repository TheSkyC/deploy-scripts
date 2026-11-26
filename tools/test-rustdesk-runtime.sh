#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034
set -euo pipefail
umask 077

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

source lib/core.sh
source impl/install_rustdesk.sh

command -v timeout >/dev/null 2>&1 || error "coreutils timeout is required"
compose_require_runtime

TEST_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/rustdesk-runtime.XXXXXX")"
TEST_BRIDGE_PORT=""

cleanup() {
  local mode project_dir compose_cmd
  set +e
  compose_cmd="$(compose_command)"
  for mode in host bridge; do
    project_dir="${TEST_ROOT}/rustdesk-${mode}"
    [[ -f "${project_dir}/compose.yaml" ]] || continue
    case "$compose_cmd" in
      "docker compose")
        docker compose --project-directory "$project_dir" -f "${project_dir}/compose.yaml" \
          down --volumes --remove-orphans >/dev/null 2>&1
        ;;
      docker-compose)
        docker-compose --project-directory "$project_dir" -f "${project_dir}/compose.yaml" \
          down --volumes --remove-orphans >/dev/null 2>&1
        ;;
    esac
  done
  if [[ "$TEST_ROOT" == */rustdesk-runtime.* && -d "$TEST_ROOT" ]]; then
    rm -rf -- "$TEST_ROOT"
  fi
}
trap cleanup EXIT

_rustdesk_runtime_probe_tcp() {
  local port="$1"
  # The nested Bash expands $1 when it opens the TCP connection.
  # shellcheck disable=SC2016
  timeout 2 bash -c 'exec 3<>"/dev/tcp/127.0.0.1/$1"' _ "$port" >/dev/null 2>&1
}

_rustdesk_runtime_test_mode() {
  local mode="$1" project_dir="${TEST_ROOT}/rustdesk-${1}"
  local nat_port=21115 id_port=21116 relay_port=21117 attempt

  if [[ "$mode" == bridge ]]; then
    nat_port="$TEST_BRIDGE_PORT"
    id_port=$((TEST_BRIDGE_PORT + 1))
    relay_port=$((TEST_BRIDGE_PORT + 2))
  fi

  RUSTDESK_INSTALL_DIR="$project_dir"
  RUSTDESK_DATA_DIR="${project_dir}/data"
  RUSTDESK_COMPOSE_FILE="${project_dir}/compose.yaml"
  RUSTDESK_BACKUP_DIR="${project_dir}/backups"
  RUSTDESK_RELAY_HOST=127.0.0.1
  RUSTDESK_NETWORK_MODE="$mode"
  RUSTDESK_BIND_ADDR=127.0.0.1
  RUSTDESK_NAT_PORT="$nat_port"
  RUSTDESK_ID_PORT="$id_port"
  RUSTDESK_RELAY_PORT="$relay_port"

  mkdir -p "$RUSTDESK_INSTALL_DIR" "$RUSTDESK_DATA_DIR"
  _rustdesk_write_compose
  compose_run "$RUSTDESK_INSTALL_DIR" "$RUSTDESK_COMPOSE_FILE" config --quiet
  compose_run "$RUSTDESK_INSTALL_DIR" "$RUSTDESK_COMPOSE_FILE" up -d
  _rustdesk_wait_healthy || error "RustDesk services failed in ${mode} mode"

  for ((attempt = 0; attempt < 10; attempt++)); do
    [[ -s "${RUSTDESK_DATA_DIR}/id_ed25519.pub" ]] && break
    sleep 1
  done
  [[ -s "${RUSTDESK_DATA_DIR}/id_ed25519.pub" ]] \
    || error "RustDesk did not generate its public identity key in ${mode} mode"

  for port in "$nat_port" "$id_port" "$relay_port"; do
    _rustdesk_runtime_probe_tcp "$port" \
      || error "RustDesk TCP listener ${port} is not reachable in ${mode} mode"
  done
  success "RustDesk ${mode} runtime check passed"
}

TEST_BRIDGE_PORT=$((30000 + $$ % 30000))
for port in 21115 21116 21117 "$TEST_BRIDGE_PORT" "$((TEST_BRIDGE_PORT + 1))" "$((TEST_BRIDGE_PORT + 2))"; do
  _rustdesk_runtime_probe_tcp "$port" \
    && error "TCP port ${port} is already accepting connections"
done

_rustdesk_runtime_test_mode bridge
_rustdesk_runtime_test_mode host
