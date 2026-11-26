# shellcheck shell=bash
# Runtime and source-contract checks for RustDesk Server OSS.

check_rustdesk_compose_preserves_identity_and_limits_ports() {
  "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    source impl/install_rustdesk.sh
    tmp="$(mktemp -d)"
    trap '\''rm -rf "$tmp"'\'' EXIT
    RUSTDESK_INSTALL_DIR="$tmp/project"
    RUSTDESK_DATA_DIR="$tmp/identity"
    RUSTDESK_COMPOSE_FILE="$tmp/project/compose.yaml"
    RUSTDESK_RELAY_HOST="relay.example.test"
    RUSTDESK_NETWORK_MODE=bridge
    mkdir -p "$RUSTDESK_INSTALL_DIR"
    _rustdesk_write_compose
    grep -Fq "${RUSTDESK_DATA_DIR}:/root" "$RUSTDESK_COMPOSE_FILE"
    grep -Fq "hbbs -r relay.example.test:21117" "$RUSTDESK_COMPOSE_FILE"
    grep -Fq "21116:21116/udp" "$RUSTDESK_COMPOSE_FILE"
    grep -Fq "21117:21117/tcp" "$RUSTDESK_COMPOSE_FILE"
    ! grep -Eq "21118|21119" "$RUSTDESK_COMPOSE_FILE"
  '
}

check_rustdesk_host_network_mode_and_instance_paths() {
  "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    source impl/install_rustdesk.sh
    [[ "$RUSTDESK_NETWORK_MODE" == host ]]
    [[ "$RUSTDESK_IMAGE" == rustdesk/rustdesk-server:1.1.16 ]]
    tmp="$(mktemp -d)"
    trap '\''rm -rf "$tmp"'\'' EXIT
    RUSTDESK_INSTALL_DIR="$tmp/project"
    RUSTDESK_DATA_DIR="$tmp/data"
    RUSTDESK_COMPOSE_FILE="$tmp/project/compose.yaml"
    RUSTDESK_RELAY_HOST="relay.example.test"
    RUSTDESK_NETWORK_MODE=host
    mkdir -p "$RUSTDESK_INSTALL_DIR"
    _rustdesk_write_compose
    grep -Fq "network_mode: host" "$RUSTDESK_COMPOSE_FILE"
    ! grep -Fq "    ports:" "$RUSTDESK_COMPOSE_FILE"
  '
  APP_INSTANCE=blue "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    source impl/install_rustdesk.sh
    [[ "$RUSTDESK_NETWORK_MODE" == bridge ]]
    [[ "$RUSTDESK_INSTALL_DIR" == /opt/rustdesk-server-blue ]]
    [[ "$RUSTDESK_DATA_DIR" == /var/lib/rustdesk-server-blue ]]
    [[ "$RUSTDESK_SERVICE_NAME" == rustdesk-server-blue ]]
    [[ "$RUSTDESK_BACKUP_DIR" == /opt/rustdesk-server-backups-blue ]]
  '
}

check_rustdesk_health_requires_both_components() {
  "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    source impl/install_rustdesk.sh
    tmp="$(mktemp -d)"
    trap '\''rm -rf "$tmp"'\'' EXIT
    RUSTDESK_INSTALL_DIR="$tmp/project"
    RUSTDESK_COMPOSE_FILE="$tmp/project/compose.yaml"
    mkdir -p "$RUSTDESK_INSTALL_DIR"
    : > "$RUSTDESK_COMPOSE_FILE"
    RUSTDESK_TEST_RUNNING_SERVICES=$'\''hbbs\nhbbr'\''
    docker() {
      if [[ "${1:-}" == compose && "${2:-}" == version ]]; then return 0; fi
      printf "%s\\n" "$RUSTDESK_TEST_RUNNING_SERVICES"
    }
    _rustdesk_stack_healthy
    RUSTDESK_TEST_RUNNING_SERVICES=hbbs
    ! _rustdesk_stack_healthy
  '
}

check_rustdesk_update_rollback_preserves_configured_image() {
  "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    source impl/install_rustdesk.sh
    tmp="$(mktemp -d)"
    trap '\''rm -rf "$tmp"'\'' EXIT
    RUSTDESK_INSTALL_DIR="$tmp/project"
    RUSTDESK_DATA_DIR="$tmp/data"
    RUSTDESK_COMPOSE_FILE="$tmp/project/compose.yaml"
    RUSTDESK_RELAY_HOST=relay.example.test
    mkdir -p "$RUSTDESK_INSTALL_DIR"
    docker() {
      [[ "$*" == "image tag sha256:previous rustdesk/rustdesk-server:target" ]]
    }
    compose_run() {
      [[ "$3" == up && "$4" == -d ]]
    }
    _rustdesk_restore_previous_image sha256:previous rustdesk/rustdesk-server:target
    [[ "$RUSTDESK_IMAGE" == rustdesk/rustdesk-server:target ]]
    grep -Fq "image: rustdesk/rustdesk-server:target" "$RUSTDESK_COMPOSE_FILE"
    ! grep -Fq "rollback:" "$RUSTDESK_COMPOSE_FILE"
  '
}

check_rustdesk_reinstall_restarts_managed_stack() {
  "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    source impl/install_rustdesk.sh
    tmp="$(mktemp -d)"
    trap '\''rm -rf "$tmp"'\'' EXIT
    RUSTDESK_INSTALL_DIR="$tmp/project"
    RUSTDESK_DATA_DIR="$tmp/data"
    RUSTDESK_COMPOSE_FILE="$tmp/project/compose.yaml"
    RUSTDESK_RELAY_HOST=relay.example.test
    mkdir -p "$RUSTDESK_INSTALL_DIR"
    preflight_check() { :; }
    acquire_lock() { :; }
    compose_command() { printf "docker compose"; }
    compose_require_runtime() { :; }
    _rustdesk_write_compose() { :; }
    _rustdesk_write_unit() { :; }
    app_save_config() { :; }
    _rustdesk_wait_healthy() { :; }
    _rustdesk_show_key() { :; }
    systemctl() { printf "%s\n" "$*" >> "$tmp/systemctl.log"; }
    do_install
    grep -Fxq "restart rustdesk-server" "$tmp/systemctl.log"
    ! grep -Fxq "start rustdesk-server" "$tmp/systemctl.log"
  '
}

check_rustdesk_backup_quiesces_and_restarts_stack() {
  "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    source impl/install_rustdesk.sh
    tmp="$(mktemp -d)"
    trap '\''rm -rf "$tmp"'\'' EXIT
    RUSTDESK_DATA_DIR="$tmp/data"
    RUSTDESK_BACKUP_DIR="$tmp/backups"
    RUSTDESK_SERVICE_NAME=rustdesk-test
    TEST_RUNNING=true
    TEST_FAIL_TAR=false
    TEST_FAIL_START=false
    mkdir -p "$RUSTDESK_DATA_DIR"
    printf identity > "$RUSTDESK_DATA_DIR/id_ed25519"
    systemctl() {
      case "$1" in
        is-active) [[ "$TEST_RUNNING" == true ]] ;;
        stop) printf "stop\n" >> "$tmp/lifecycle"; TEST_RUNNING=false ;;
        start)
          printf "start\n" >> "$tmp/lifecycle"
          [[ "$TEST_FAIL_START" == false ]] || return 1
          TEST_RUNNING=true
          ;;
      esac
    }
    tar() {
      [[ "$TEST_RUNNING" == false ]] || return 1
      [[ "$TEST_FAIL_TAR" == false ]] || return 2
      command tar "$@"
    }
    archive="$(_rustdesk_create_backup)"
    [[ "$TEST_RUNNING" == true ]]
    [[ "$(<"$tmp/lifecycle")" == $'\''stop\nstart'\'' ]]
    backup_verify_archive "$archive"
    TEST_FAIL_TAR=true
    if _rustdesk_create_backup >/dev/null 2>&1; then exit 1; fi
    [[ "$TEST_RUNNING" == true ]]
    [[ "$(<"$tmp/lifecycle")" == $'\''stop\nstart\nstop\nstart'\'' ]]
    [[ "$(find "$RUSTDESK_BACKUP_DIR" -type f | wc -l)" -eq 3 ]]
    TEST_FAIL_TAR=false
    TEST_FAIL_START=true
    if _rustdesk_create_backup >/dev/null 2>&1; then exit 1; fi
    [[ "$(find "$RUSTDESK_BACKUP_DIR" -type f | wc -l)" -eq 6 ]]
    latest="$(find "$RUSTDESK_BACKUP_DIR" -name '\''*.tar.gz'\'' -print | sort | tail -1)"
    backup_verify_archive "$latest"
  '
}

check_rustdesk_public_key_output_never_reads_private_key() {
  grep -Fq 'id_ed25519.pub' impl/install_rustdesk.sh \
    && ! grep -Eq 'cat .*id_ed25519([^.]|$)' impl/install_rustdesk.sh \
    || {
      echo "RustDesk status must expose only the public identity key" >&2
      return 1
    }
}

check_rustdesk_registration_exposes_backup_restore() {
  grep -Fq 'do_backup()' impl/install_rustdesk.sh \
    && grep -Fq 'do_restore()' impl/install_rustdesk.sh \
    && grep -Fq 'do_verify()' impl/install_rustdesk.sh \
    && grep -Fq '"rustdesk|RustDesk Server OSS|apps/rustdesk.sh|impl/install_rustdesk.sh|backup,restore"' lib/app_registry.sh
}

check_rustdesk_backup_restore_round_trip() {
  "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    tmp="$(mktemp -d)"
    trap '\''rm -rf "$tmp"'\'' EXIT
    data="$tmp/data"
    backups="$tmp/backups"
    mkdir -p "$data" "$backups"
    printf "identity-material\n" > "$data/id_ed25519"
    printf "public-key\n" > "$data/id_ed25519.pub"
    archive="$backups/rustdesk_test.tar.gz"
    backup_create_tar_archive "$archive" -C "$tmp" data
    backup_finalize_archive "$archive" rustdesk 1.1.14 1
    printf "changed\n" > "$data/id_ed25519.pub"
    backup_restore_data_dir "$data" "" "$archive"
    grep -Fxq "public-key" "$data/id_ed25519.pub"
    backup_verify_archive "$archive"
  '
}
