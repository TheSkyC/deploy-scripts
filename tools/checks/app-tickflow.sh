# shellcheck shell=bash
# shellcheck source=../verify.sh
# Verify checks for the tickflow app (apps/tickflow.sh).

check_tickflow_status_backup_projection() {
  local output
  output="$($BASH_BIN -c '
    set -euo pipefail
    tmp_dir="$(mktemp -d)"
    install_dir="$tmp_dir/tickflow"
    backup_dir="${install_dir}-backups"
    mkdir -p "$backup_dir"
    touch -d "2026-08-20 12:34:56 UTC" "$backup_dir/tickflow-data-20260820123456.tar.gz"
    source lib/core.sh
    APP_ID=tickflow
    APP_NAME="TickFlow"
    TICKFLOW_INSTALL_DIR="$install_dir"
    app_conf_file() { printf "%s" "$tmp_dir/missing.conf"; }
    source impl/install_tickflow.sh
    _tickflow_status_backup
    rm -rf "$tmp_dir"
  ')"
  python -c 'import json,sys; x=json.loads(sys.argv[1]); assert x["state"] == "available"; assert x["path"].endswith("tickflow-data-20260820123456.tar.gz"); assert x["last_success_at"]' "$output"
}

check_tickflow_uninstall_supports_noninteractive_mode() {
  awk '
      /app\.tickflow\.prompt\.continue/ { saw_continue_msg=1 }
      /app\.tickflow\.prompt\.delete_install/ { saw_delete_msg=1 }
      /app\.tickflow\.prompt\.delete_backup/ { saw_delete_backup_msg=1 }
      /app\.tickflow\.success\.removed/ { saw_success_msg=1 }
      END {
        if (!(saw_continue_msg && saw_delete_msg && saw_delete_backup_msg && saw_success_msg)) {
          print "TickFlow uninstall prompts and success output must be localized." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/tickflow.sh
  awk '
      /do_uninstall\(\)/ { in_uninstall=1; saw_continue_prompt=0; saw_confirm_assume=0; saw_confirm_yes=0; saw_delete_env=0; saw_delete_prompt=0; saw_delete_default=0; saw_backup_env=0; saw_backup_prompt=0; saw_backup_default=0; saw_guarded_rm=0; saw_keep=0; saw_backup_keep=0; saw_success=0; next }
      in_uninstall && /if deploy_assume_yes; then/ && !saw_confirm_assume { saw_confirm_assume=1; next }
      in_uninstall && saw_confirm_assume && /confirm="YES"/ { saw_confirm_yes=1 }
      in_uninstall && /prompt "\$\(t app\.tickflow\.prompt\.continue\)"/ { saw_continue_prompt=1 }
      in_uninstall && /deploy_env_truthy DEPLOY_DELETE_INSTALL && DELETE_INSTALL=true/ { saw_delete_env=1 }
      in_uninstall && /prompt "\$\(t app\.tickflow\.prompt\.delete_install "\$TICKFLOW_INSTALL_DIR"\)"/ { saw_delete_prompt=1 }
      in_uninstall && /local DELETE_INSTALL=false/ { saw_delete_default=1 }
      in_uninstall && /deploy_env_truthy DEPLOY_DELETE_BACKUP && DELETE_BACKUP=true/ { saw_backup_env=1 }
      in_uninstall && /prompt "\$\(t app\.tickflow\.prompt\.delete_backup "\$backup_dir"\)"/ { saw_backup_prompt=1 }
      in_uninstall && /local DELETE_BACKUP=false/ { saw_backup_default=1 }
      in_uninstall && /if \$DELETE_INSTALL && \[\[ -e "\$TICKFLOW_INSTALL_DIR" \|\| -L "\$TICKFLOW_INSTALL_DIR" \]\]; then/ { saw_guarded_rm=1 }
      in_uninstall && /info "\$\(t app\.tickflow\.info\.kept_install "\$TICKFLOW_INSTALL_DIR"\)"/ { saw_keep=1 }
      in_uninstall && /info "\$\(t app\.tickflow\.info\.kept_backup "\$backup_dir"\)"/ { saw_backup_keep=1 }
      in_uninstall && /success "\$\(t app\.tickflow\.success\.removed\)"/ { saw_success=1 }
      in_uninstall && /^}/ {
        if (!(saw_continue_prompt && saw_confirm_assume && saw_confirm_yes && saw_delete_env && saw_delete_prompt && saw_delete_default && saw_backup_env && saw_backup_prompt && saw_backup_default && saw_guarded_rm && saw_keep && saw_backup_keep && saw_success)) {
          printf "%s TickFlow uninstall must confirm removal and require explicit env flags before deleting install data or backups in non-interactive mode\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_uninstall=0
      }
    ' impl/install_tickflow.sh
}

check_tickflow_uninstall_checks_directory_removal_errors() {
  grep -Fq 'tickflow_remove_dir_or_error() {' impl/install_tickflow.sh \
    && grep -Fq 'app_remove_dir_or_error "$1" "$2" "$3" "app.tickflow.error.remove_dir"' impl/install_tickflow.sh \
    && grep -Fq 'tickflow_remove_dir_or_error "$TICKFLOW_INSTALL_DIR" "TICKFLOW_INSTALL_DIR" "$(t app.tickflow.success.deleted_install "$TICKFLOW_INSTALL_DIR")"' impl/install_tickflow.sh \
    && grep -Fq 'tickflow_remove_dir_or_error "$backup_dir" "TICKFLOW_BACKUP_DIR" "$(t app.tickflow.success.deleted_backup "$backup_dir")"' impl/install_tickflow.sh \
    && grep -Fq 'app.tickflow.error.remove_dir' apps/tickflow.sh \
    || {
      echo "TickFlow uninstall must report directory removal failures instead of mislabeling them as unsafe paths." >&2
      return 1
    }
}

check_tickflow_uninstall_checks_file_removal_errors() {
  grep -Fq 'tickflow_remove_file_or_error() {' impl/install_tickflow.sh \
    && grep -Fq 'app_remove_file_or_error "$1" "$2" "app.tickflow.error.remove_file"' impl/install_tickflow.sh \
    && grep -Fq 'tickflow_remove_file_or_error "/etc/systemd/system/${TICKFLOW_SERVICE_NAME}.service" "TICKFLOW_SERVICE_FILE"' impl/install_tickflow.sh \
    && grep -Fq 'tickflow_remove_file_or_error "$CONF_FILE" "CONF_FILE"' impl/install_tickflow.sh \
    && grep -Fq 'app.tickflow.error.remove_file' apps/tickflow.sh \
    || {
      echo "TickFlow uninstall must surface file removal failures instead of reporting unconditional success." >&2
      return 1
    }
}

check_tickflow_preflight_defers_docker_runtime_checks() {
  awk '
      /preflight_check\(\)/ { in_func=1; saw_docker=0; saw_compose=0; next }
      in_func && /command -v docker/ { saw_docker=1 }
      in_func && /docker compose version/ { saw_compose=1 }
      in_func && /^}/ {
        if (saw_docker || saw_compose) {
          printf "%s TickFlow preflight must not require Docker before install dependencies are present\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_tickflow.sh
}

check_tickflow_env_rewrites_preserve_existing_secrets() {
  "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    source impl/install_tickflow.sh

    tmp_dir="$(mktemp -d)"
    trap '"'"'rm -rf "$tmp_dir"'"'"' EXIT

    TICKFLOW_INSTALL_DIR="${tmp_dir}/tickflow"
    TICKFLOW_ENV_FILE="${TICKFLOW_INSTALL_DIR}/.env"
    TICKFLOW_PORT="4010"
    TICKFLOW_AUTH_PASSWORD="newpass123"
    TICKFLOW_BACKEND_EXTRAS="alpha,beta"

    mkdir -p "$TICKFLOW_INSTALL_DIR"
    cat > "$TICKFLOW_ENV_FILE" <<'"'"'EOF'"'"'
TICKFLOW_API_KEY=existing-panel-key
AI_PROVIDER=anthropic_compat
AI_BASE_URL=https://example.com/v1
AI_API_KEY=existing-ai-key
AI_MODEL=claude-like
AI_DAILY_TOKEN_BUDGET=123
HOST=127.0.0.1
PORT=9999
LOG_LEVEL=DEBUG
AUTH_PASSWORD=oldpass
BACKEND_EXTRAS=old
DATA_DIR=./old-data
EOF

    _write_env_file

    grep -Fxq "TICKFLOW_API_KEY=existing-panel-key" "$TICKFLOW_ENV_FILE"
    grep -Fxq "AI_PROVIDER=anthropic_compat" "$TICKFLOW_ENV_FILE"
    grep -Fxq "AI_BASE_URL=https://example.com/v1" "$TICKFLOW_ENV_FILE"
    grep -Fxq "AI_API_KEY=existing-ai-key" "$TICKFLOW_ENV_FILE"
    grep -Fxq "AI_MODEL=claude-like" "$TICKFLOW_ENV_FILE"
    grep -Fxq "AI_DAILY_TOKEN_BUDGET=123" "$TICKFLOW_ENV_FILE"
    grep -Fxq "LOG_LEVEL=DEBUG" "$TICKFLOW_ENV_FILE"
    grep -Fxq "PORT=4010" "$TICKFLOW_ENV_FILE"
    grep -Fxq "AUTH_PASSWORD=newpass123" "$TICKFLOW_ENV_FILE"
    grep -Fxq "BACKEND_EXTRAS=alpha,beta" "$TICKFLOW_ENV_FILE"
    grep -Fxq "DATA_DIR=./data" "$TICKFLOW_ENV_FILE"
  '
}

check_tickflow_paths_are_guarded() {
  awk '
      /_clone_or_update_repo\(\)/ { in_clone=1; saw_clone_guard=0; saw_non_repo_error=0; next }
      in_clone && /require_safe_path "TICKFLOW_INSTALL_DIR" "\$repo_dir"/ { saw_clone_guard=1 }
      in_clone && /safe_rm_dir "\$repo_dir" "TICKFLOW_INSTALL_DIR"/ {
        printf "%s TickFlow install must not automatically delete an existing non-git install directory\n", FILENAME > "/dev/stderr"
        exit 1
      }
      in_clone && /error "\$\(t app\.tickflow\.error\.install_dir_not_repo "\$repo_dir"\)"/ { saw_non_repo_error=1 }
      in_clone && /^}/ {
        if (!(saw_clone_guard && saw_non_repo_error)) {
          printf "%s TickFlow repo setup must guard the install directory and fail closed when it already exists outside git\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_clone=0
      }
      /do_uninstall\(\)/ { in_uninstall=1; saw_uninstall_rm=0; next }
      in_uninstall && /tickflow_remove_dir_or_error "\$TICKFLOW_INSTALL_DIR" "TICKFLOW_INSTALL_DIR"/ { saw_uninstall_rm=1 }
      in_uninstall && /^}/ {
        if (!saw_uninstall_rm) {
          printf "%s TickFlow uninstall must route install-directory deletion through the guarded remove helper\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_uninstall=0
      }
    ' impl/install_tickflow.sh
  awk '
      /app\.tickflow\.error\.install_dir_not_repo/ { saw_key=1 }
      END {
        if (!saw_key) {
          print "TickFlow must explain how to recover when the install directory already exists outside git." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/tickflow.sh
}

check_tickflow_directory_setup_failures_are_explicit() {
  awk '
      /app\.tickflow\.error\.install_parent_dir/ { saw_parent_key=1 }
      /app\.tickflow\.error\.runtime_dirs/ { saw_runtime_key=1 }
      END {
        if (!(saw_parent_key && saw_runtime_key)) {
          print "TickFlow directory setup failures must have localized recovery messages." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/tickflow.sh
  awk '
      /_clone_or_update_repo\(\)/ { in_clone=1; saw_parent_if=0; saw_parent_error=0; next }
      in_clone && /if ! mkdir -p "\$parent"; then/ { saw_parent_if=1 }
      in_clone && /error "\$\(t app\.tickflow\.error\.install_parent_dir "\$parent"\)"/ { saw_parent_error=1 }
      in_clone && /^}/ {
        if (!(saw_parent_if && saw_parent_error)) {
          printf "%s TickFlow source setup must report install parent directory creation failures explicitly\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_clone=0
      }
      /_ensure_data_layout\(\)/ { in_layout=1; saw_dirs_if=0; saw_dirs_error=0; next }
      in_layout && /if ! mkdir -p "\$TICKFLOW_DATA_DIR" "\$TICKFLOW_LOG_DIR"; then/ { saw_dirs_if=1 }
      in_layout && /error "\$\(t app\.tickflow\.error\.runtime_dirs "\$TICKFLOW_DATA_DIR" "\$TICKFLOW_LOG_DIR"\)"/ { saw_dirs_error=1 }
      in_layout && /atomic_write_file "\$TICKFLOW_TIERS_FILE"/ {
        if (!(saw_dirs_if && saw_dirs_error)) {
          printf "%s TickFlow data layout setup must report runtime directory creation failures explicitly\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_layout=0
      }
    ' impl/install_tickflow.sh
}

check_tickflow_dependency_failures_are_reported() {
  awk '
      /app\.tickflow\.warn\.apt_update/ { saw_update_key=1 }
      /app\.tickflow\.error\.deps_install/ { saw_install_key=1 }
      END {
        if (!(saw_update_key && saw_install_key)) {
          print "TickFlow dependency failures must provide localized update/install guidance." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/tickflow.sh
  awk '
      /step "\$\(t app\.tickflow\.step\.deps\)"/ { in_deps=1; saw_update_if=0; saw_update_warn=0; saw_plugin_if=0; saw_fallback_if=0; saw_install_error=0; next }
      in_deps && /if ! apt-get update -qq; then/ { saw_update_if=1 }
      in_deps && /warn "\$\(t app\.tickflow\.warn\.apt_update\)"/ { saw_update_warn=1 }
      in_deps && /if ! apt-get install -y -qq git curl ca-certificates docker\.io docker-compose-plugin; then/ { saw_plugin_if=1 }
      in_deps && /if ! apt-get install -y -qq git curl ca-certificates docker\.io docker-compose; then/ { saw_fallback_if=1 }
      in_deps && /error "\$\(t app\.tickflow\.error\.deps_install\)"/ { saw_install_error=1 }
      in_deps && /systemctl enable --now docker/ {
        if (!(saw_update_if && saw_update_warn && saw_plugin_if && saw_fallback_if && saw_install_error)) {
          printf "%s TickFlow install must warn on apt-get update failures and error explicitly when both compose dependency installs fail\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_deps=0
      }
    ' impl/install_tickflow.sh
}

check_tickflow_config_files_are_atomic() {
  if grep -R -nE '^[[:space:]]*cat > "\$TICKFLOW_(ENV|COMPOSE|TIERS)_FILE"|^[[:space:]]*} > "\$env_tmp"' \
      impl/install_tickflow.sh 2>/dev/null; then
    echo "TickFlow config files must be written with atomic_write_file." >&2
    return 1
  fi
  awk '
      /_ensure_data_layout\(\)/ { in_tiers=1; saw_tiers=0; next }
      in_tiers && /atomic_write_file "\$TICKFLOW_TIERS_FILE" 644/ { saw_tiers=1 }
      in_tiers && /^}/ { in_tiers=0 }
      /_write_env_file\(\)/ { in_env=1; saw_env=0; next }
      in_env && /atomic_write_file "\$TICKFLOW_ENV_FILE" 600/ { saw_env=1 }
      in_env && /^}/ { in_env=0 }
      /_write_compose_file\(\)/ { in_compose=1; saw_compose=0; next }
      in_compose && /atomic_write_file "\$TICKFLOW_COMPOSE_FILE" 644/ { saw_compose=1 }
      in_compose && /^}/ { in_compose=0 }
      END {
        if (!(saw_tiers && saw_env && saw_compose)) {
          printf "%s TickFlow must atomically write tiers, env, and compose files\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_tickflow.sh
}

check_tickflow_systemd_shell_paths_are_quoted() {
  if grep -R -nE 'Exec(Start|Stop|Reload)=/bin/bash -lc '\''cd "\$\{TICKFLOW_INSTALL_DIR\}"| -f "\$\{TICKFLOW_COMPOSE_FILE\}"' \
      impl/install_tickflow.sh 2>/dev/null; then
    echo "TickFlow systemd shell commands must not interpolate raw paths." >&2
    return 1
  fi
  awk '
      /_write_systemd_unit\(\)/ { in_func=1; saw_install=0; saw_compose=0; saw_exec=0; next }
      in_func && /printf -v install_dir_literal '\''%q'\'' "\$TICKFLOW_INSTALL_DIR"/ { saw_install=1 }
      in_func && /printf -v compose_file_literal '\''%q'\'' "\$TICKFLOW_COMPOSE_FILE"/ { saw_compose=1 }
      in_func && /ExecStart=\/bin\/bash -lc '\''cd \$\{install_dir_literal\} && \$\{compose_cmd\} -f \$\{compose_file_literal\} up -d --build'\''/ { saw_exec=1 }
      in_func && /^}/ {
        if (!(saw_install && saw_compose && saw_exec)) {
          printf "%s TickFlow systemd shell command paths must use printf %%q literals\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_tickflow.sh
}

check_tickflow_systemctl_failures_are_reported() {
  if grep -R -nE 'systemctl (enable --now docker|enable "\$TICKFLOW_SERVICE_NAME"|stop "\$TICKFLOW_SERVICE_NAME"|disable "\$TICKFLOW_SERVICE_NAME"|daemon-reload).* \|\| true' \
      impl/install_tickflow.sh 2>/dev/null; then
    echo "TickFlow systemctl failures must be reported instead of silently ignored." >&2
    return 1
  fi
  awk '
      /app\.tickflow\.warn\.docker_enable_failed/ { saw_docker_key=1 }
      /app\.tickflow\.warn\.service_enable_failed/ { saw_enable_key=1 }
      /app\.tickflow\.warn\.service_stop_failed/ { saw_stop_key=1 }
      /app\.tickflow\.warn\.service_disable_failed/ { saw_disable_key=1 }
      END {
        if (!(saw_docker_key && saw_enable_key && saw_stop_key && saw_disable_key)) {
          print "TickFlow must provide localized warnings for nonfatal systemctl failures." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/tickflow.sh
  awk '
      /systemctl enable --now docker/ { saw_docker=1 }
      saw_docker && /warn "\$\(t app\.tickflow\.warn\.docker_enable_failed\)"/ { saw_docker_warn=1; saw_docker=0 }
      /systemctl enable "\$TICKFLOW_SERVICE_NAME"/ { saw_enable=1 }
      saw_enable && /warn "\$\(t app\.tickflow\.warn\.service_enable_failed "\$TICKFLOW_SERVICE_NAME" "\$TICKFLOW_SERVICE_NAME"\)"/ { saw_enable_warn=1; saw_enable=0 }
      /systemctl stop "\$TICKFLOW_SERVICE_NAME"/ { saw_stop=1 }
      saw_stop && /warn "\$\(t app\.tickflow\.warn\.service_stop_failed "\$TICKFLOW_SERVICE_NAME" "\$TICKFLOW_SERVICE_NAME"\)"/ { saw_stop_warn=1; saw_stop=0 }
      /systemctl disable "\$TICKFLOW_SERVICE_NAME"/ { saw_disable=1 }
      saw_disable && /warn "\$\(t app\.tickflow\.warn\.service_disable_failed "\$TICKFLOW_SERVICE_NAME" "\$TICKFLOW_SERVICE_NAME"\)"/ { saw_disable_warn=1; saw_disable=0 }
      END {
        if (!(saw_docker_warn && saw_enable_warn && saw_stop_warn && saw_disable_warn)) {
          printf "%s TickFlow must warn on nonfatal systemctl failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_tickflow.sh
}

check_tickflow_uninstall_daemon_reload_failure_is_fatal() {
  awk '
      /do_uninstall\(\)/ { in_uninstall=1; saw_reload_if=0; saw_reload_error=0; next }
      in_uninstall && /if ! systemctl daemon-reload; then/ { saw_reload_if=1; next }
      in_uninstall && saw_reload_if && /error "\$\(t app\.tickflow\.error\.service_reload "\$TICKFLOW_SERVICE_NAME"\)"/ { saw_reload_error=1 }
      in_uninstall && /^}/ {
        if (!(saw_reload_if && saw_reload_error)) {
          printf "%s TickFlow uninstall must abort when systemd daemon-reload fails after removing the service unit\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_uninstall=0
      }
    ' impl/install_tickflow.sh
}

check_tickflow_uninstall_stop_disable_failures_are_reported() {
  awk '
      /app\.tickflow\.error\.service_stop_failed_active/ { saw_stop_error=1 }
      /app\.tickflow\.warn\.service_stop_failed/ { saw_stop_warn=1 }
      /app\.tickflow\.warn\.service_disable_failed/ { saw_disable_warn=1 }
      END {
        if (!(saw_stop_error && saw_stop_warn && saw_disable_warn)) {
          print "TickFlow must provide localized uninstall stop and disable failure messages." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/tickflow.sh
  awk '
      /do_uninstall\(\)/ { in_func=1 }
      in_func && /if ! systemctl stop "\$TICKFLOW_SERVICE_NAME" >\/dev\/null 2>&1; then/ { in_uninstall=1; saw_stop_if=1; saw_active_if=0; saw_stop_error=0; saw_stop_warn=0; saw_disable_if=0; saw_disable_warn=0; next }
      in_uninstall && /if systemctl is-active --quiet "\$TICKFLOW_SERVICE_NAME" 2>\/dev\/null; then/ { saw_active_if=1 }
      in_uninstall && /error "\$\(t app\.tickflow\.error\.service_stop_failed_active "\$TICKFLOW_SERVICE_NAME" "\$TICKFLOW_SERVICE_NAME"\)"/ { saw_stop_error=1 }
      in_uninstall && /warn "\$\(t app\.tickflow\.warn\.service_stop_failed "\$TICKFLOW_SERVICE_NAME" "\$TICKFLOW_SERVICE_NAME"\)"/ { saw_stop_warn=1 }
      in_uninstall && /if ! systemctl disable "\$TICKFLOW_SERVICE_NAME" >\/dev\/null 2>&1; then/ { saw_disable_if=1 }
      in_uninstall && /warn "\$\(t app\.tickflow\.warn\.service_disable_failed "\$TICKFLOW_SERVICE_NAME" "\$TICKFLOW_SERVICE_NAME"\)"/ { saw_disable_warn=1 }
      in_uninstall && /rm -f "\/etc\/systemd\/system\/\$\{TICKFLOW_SERVICE_NAME\}\.service"/ {
        if (!(saw_stop_if && saw_active_if && saw_stop_error && saw_stop_warn && saw_disable_if && saw_disable_warn)) {
          printf "%s TickFlow uninstall must abort when an active service cannot be stopped and warn on disable failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_uninstall=0
      }
      in_func && /^}/ { in_func=0 }
    ' impl/install_tickflow.sh
}

check_tickflow_service_start_failures_show_diagnostics() {
  awk '
      /app\.tickflow\.warn\.service_diagnostics/ { saw_key=1 }
      END {
        if (!saw_key) {
          print "TickFlow service start failures must have localized diagnostics heading." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/tickflow.sh
  awk '
      /_print_service_diagnostics\(\)/ { in_helper=1; saw_warn=0; saw_status=0; saw_nonfatal=0; next }
      in_helper && /warn "\$\(t app\.tickflow\.warn\.service_diagnostics\)"/ { saw_warn=1 }
      in_helper && /systemctl status "\$TICKFLOW_SERVICE_NAME" --no-pager -l 2>\/dev\/null/ { saw_status=1 }
      in_helper && /\| head -20 \| sed '\''s\/\^\/  \/'\'' >&2 \|\| true/ { saw_nonfatal=1 }
      in_helper && /^}/ {
        if (!(saw_warn && saw_status && saw_nonfatal)) {
          printf "%s TickFlow service diagnostics helper must print recent systemd status nonfatally\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_helper=0
      }
      /if ! systemctl start "\$TICKFLOW_SERVICE_NAME"; then/ { in_start=1; saw_start_diag=0; saw_start_error=0; next }
      in_start && /_print_service_diagnostics/ { saw_start_diag=1 }
      in_start && /error "\$\(t app\.tickflow\.error\.service_start "\$TICKFLOW_SERVICE_NAME"\)"/ { saw_start_error=1 }
      in_start && /^  fi$/ {
        if (!(saw_start_diag && saw_start_error)) {
          printf "%s TickFlow install start failure must print diagnostics before exiting\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_start=0
      }
      /if ! systemctl restart "\$TICKFLOW_SERVICE_NAME"; then/ { in_restart=1; saw_restart_diag=0; saw_restart_error=0; next }
      in_restart && /_print_service_diagnostics/ { saw_restart_diag=1 }
      in_restart && /error "\$\(t app\.tickflow\.error\.service_start "\$TICKFLOW_SERVICE_NAME"\)"/ { saw_restart_error=1 }
      in_restart && /^  fi$/ {
        if (!(saw_restart_diag && saw_restart_error)) {
          printf "%s TickFlow update restart failure must print diagnostics before exiting\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_restart=0
      }
    ' impl/install_tickflow.sh
}

check_tickflow_status_is_structured() {
  awk '
      /app\.tickflow\.status\.systemd/ { saw_systemd=1 }
      /app\.tickflow\.status\.paths/ { saw_paths=1 }
      /app\.tickflow\.status\.backups/ { saw_backups=1 }
      /app\.tickflow\.status\.http_health/ { saw_health=1 }
      /app\.tickflow\.status\.path_ok/ { saw_path_ok=1 }
      /app\.tickflow\.status\.backup_count/ { saw_backup_count=1 }
      /app\.tickflow\.status\.local_response_warn/ { saw_health_warn=1 }
      END {
        if (!(saw_systemd && saw_paths && saw_backups && saw_health && saw_path_ok && saw_backup_count && saw_health_warn)) {
          print "TickFlow status must provide localized structured sections and status messages." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/tickflow.sh
  awk '
      /_print_status_path\(\)/ { in_helper=1; saw_exists=0; saw_missing=0; next }
      in_helper && /t app\.tickflow\.status\.path_ok/ { saw_exists=1 }
      in_helper && /t app\.tickflow\.status\.path_missing/ { saw_missing=1 }
      in_helper && /^}/ {
        if (!(saw_exists && saw_missing)) {
          printf "%s TickFlow status path helper must report both existing and missing paths\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_helper=0
      }
      /do_status\(\)/ { in_status=1; saw_active=0; saw_enabled=0; saw_limited_status=0; saw_paths=0; saw_backup=0; saw_health=0; saw_curl_guard=0; next }
      in_status && /systemctl is-active --quiet "\$TICKFLOW_SERVICE_NAME"/ { saw_active=1 }
      in_status && /systemctl is-enabled --quiet "\$TICKFLOW_SERVICE_NAME"/ { saw_enabled=1 }
      in_status && /systemctl status "\$TICKFLOW_SERVICE_NAME" --no-pager -l 2>\/dev\/null/ { saw_status_cmd=1 }
      in_status && /\| head -12 \| sed '\''s\/\^\/  \/'\'' \|\| true/ { saw_limited_status=1 }
      in_status && /_print_status_path "\$\(t app\.tickflow\.status\.install_dir\)" "\$TICKFLOW_INSTALL_DIR"/ { saw_install_path=1 }
      in_status && /_print_status_path "\$\(t app\.tickflow\.status\.env_file\)" "\$TICKFLOW_ENV_FILE"/ { saw_env_path=1 }
      in_status && /local backup_dir="\$\{TICKFLOW_INSTALL_DIR\}-backups"/ { saw_backup=1 }
      in_status && /find "\$backup_dir" -maxdepth 1 -name "tickflow-data-\*\.tar\.gz" -type f/ { saw_backup_count=1 }
      in_status && /command -v curl >\/dev\/null 2>&1/ { saw_curl_guard=1 }
      in_status && /http:\/\/127\.0\.0\.1:\$\{TICKFLOW_PORT\}\// { saw_health=1 }
      in_status && /^}/ {
        if (!(saw_active && saw_enabled && saw_status_cmd && saw_limited_status && saw_install_path && saw_env_path && saw_backup && saw_backup_count && saw_curl_guard && saw_health)) {
          printf "%s TickFlow status must show bounded systemd details, key paths, backup count, and local HTTP health nonfatally\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_status=0
      }
    ' impl/install_tickflow.sh
}

check_tickflow_manual_backup_is_explicit() {
  awk '
      /app\.tickflow\.backup\.error_dir/ { saw_dir_key=1 }
      /app\.tickflow\.backup\.error_source_missing/ { saw_source_key=1 }
      /app\.tickflow\.backup\.error_archive/ { saw_archive_key=1 }
      /app\.tickflow\.backup\.success/ { saw_success_key=1 }
      END {
        if (!(saw_dir_key && saw_source_key && saw_archive_key && saw_success_key)) {
          print "TickFlow manual backup must provide localized backup messages." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/tickflow.sh
  awk '
      /do_backup\(\)/ { in_backup=1; saw_dir=0; saw_dir_error=0; saw_source_loop=0; saw_source_error=0; saw_tmp=0; saw_tar=0; saw_cleanup=0; saw_chmod=0; saw_mv=0; saw_success=0; next }
      in_backup && /if ! mkdir -p "\$backup_dir"; then/ { saw_dir=1 }
      in_backup && /error "\$\(t app\.tickflow\.backup\.error_dir "\$backup_dir"\)"/ { saw_dir_error=1 }
      in_backup && /for backup_source in data tiers\.yaml \.env; do/ { saw_source_loop=1 }
      in_backup && /error "\$\(t app\.tickflow\.backup\.error_source_missing "\$\{TICKFLOW_INSTALL_DIR\}\/\$\{backup_source\}"\)"/ { saw_source_error=1 }
      in_backup && /local archive_tmp="\$\{archive\}\.tmp"/ { saw_tmp=1 }
      in_backup && /if ! tar -czf "\$archive_tmp" -C "\$TICKFLOW_INSTALL_DIR" data tiers\.yaml \.env >&2; then/ { saw_tar=1 }
      in_backup && /rm -f "\$archive_tmp"/ { saw_cleanup=1 }
      in_backup && /chmod 600 "\$archive_tmp"/ { saw_chmod=1 }
      in_backup && /mv "\$archive_tmp" "\$archive"/ { saw_mv=1 }
      in_backup && /success "\$\(t app\.tickflow\.backup\.success "\$archive"\)"/ { saw_success=1 }
      in_backup && /release_lock/ {
        if (!(saw_dir && saw_dir_error && saw_source_loop && saw_source_error && saw_tmp && saw_tar && saw_cleanup && saw_chmod && saw_mv && saw_success)) {
          printf "%s TickFlow manual backup must handle directory, missing source, tar, permission, and move failures explicitly\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_backup=0
      }
    ' impl/install_tickflow.sh
}


check_tickflow_git_commit_version_contract() {
  "$BASH_BIN" -c '
    set -euo pipefail
    tmp_dir="$(mktemp -d)"
    trap '"'"'rm -rf "$tmp_dir"'"'"' EXIT
    repo="$tmp_dir/repo"
    git init -q "$repo"
    git -C "$repo" config user.email test@example.invalid
    git -C "$repo" config user.name test
    printf base > "$repo/version.txt"
    git -C "$repo" add version.txt
    git -C "$repo" commit -q -m base
    base="$(git -C "$repo" rev-parse HEAD)"
    printf target > "$repo/version.txt"
    git -C "$repo" commit -qa -m target
    target="$(git -C "$repo" rev-parse HEAD)"
    git -C "$repo" checkout -q "$base"

    source lib/core.sh
    APP_ID=tickflow
    APP_NAME=TickFlow
    TICKFLOW_INSTALL_DIR="$repo"
    TICKFLOW_COMMIT="$target"
    app_conf_file() { printf "%s" "$tmp_dir/missing.conf"; }
    source impl/install_tickflow.sh

    result="$(_tickflow_check_update_json "" "" 0)"
    [[ "$(state_json_field "$result" installed)" == "$base" ]]
    [[ "$(state_json_field "$result" latest)" == "$target" ]]
    [[ "$(state_json_field "$result" update_state)" == update_available ]]
    [[ "$(state_json_field "$result" source)" == git_commit ]]
    [[ "$(state_json_field "$result" cache_state)" == pinned ]]

    status="$(_tickflow_status_version_json)"
    [[ "$(state_json_field "$status" update_state)" == update_available ]]
    [[ "$(state_json_field "$status" source)" == git_commit ]]
    git -C "$repo" checkout -q --detach "$target"
    result="$(_tickflow_check_update_json "" "" 0)"
    [[ "$(state_json_field "$result" update_state)" == up_to_date ]]

    invalid="$(version_check_git_commit_json "$repo" short)"
    [[ "$(state_json_field "$invalid" update_state)" == unsupported ]]
  '
  grep -Fq 'TICKFLOW_COMMIT INSTALLED_VERSION' impl/install_tickflow.sh
  grep -Fq 'APP_STATUS_VERSION_FN=_tickflow_status_version_json' impl/install_tickflow.sh
  grep -Fq 'version_check_git_commit_json "$TICKFLOW_INSTALL_DIR" "$TICKFLOW_COMMIT"' impl/install_tickflow.sh
  grep -Fq 'git -C "$repo_dir" fetch --quiet --depth 1 origin "$TICKFLOW_COMMIT"' impl/install_tickflow.sh
  grep -Fq 'git -C "$repo_dir" checkout --detach "$TICKFLOW_COMMIT"' impl/install_tickflow.sh
  grep -Fq 'app.tickflow.error.commit_invalid' apps/tickflow.sh
}
