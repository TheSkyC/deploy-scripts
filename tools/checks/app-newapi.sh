# shellcheck shell=bash
# shellcheck source=../verify.sh
# Verify checks for the newapi app (apps/newapi.sh, impl/install_newapi.sh).

check_newapi_uninstall_supports_noninteractive_mode() {
  awk '
      /deploy_env_truthy\(\)/ { saw_truthy=1 }
      /deploy_assume_yes\(\)/ { saw_assume=1 }
      END {
        if (!(saw_truthy && saw_assume)) {
          print "Shared app helpers must provide environment-controlled non-interactive confirmation." > "/dev/stderr"
          exit 1
        }
      }
    ' lib/app.sh
  awk '
      /prompt "\$\(t app\.newapi\.prompt\.continue\)"/ { saw_continue_prompt=1 }
      /if deploy_assume_yes; then/ && !saw_continue { saw_continue=1; next }
      saw_continue && /_c="YES"/ { saw_yes=1 }
      /local DELETE_DATA=false/ { in_data=1; next }
      in_data && /deploy_env_truthy DEPLOY_DELETE_DATA && DELETE_DATA=true/ { saw_data_env=1 }
      in_data && /prompt "\$\(t app\.newapi\.prompt\.delete_data "\$DATA_DIR"\)"/ { saw_data_prompt=1; in_data=0 }
      /local DELETE_BACKUP=false/ { in_backup=1; next }
      in_backup && /deploy_env_truthy DEPLOY_DELETE_BACKUP && DELETE_BACKUP=true/ { saw_backup_env=1 }
      in_backup && /prompt "\$\(t app\.newapi\.prompt\.delete_backup "\$BACKUP_DIR"\)"/ { saw_backup_prompt=1; in_backup=0 }
      END {
        if (!(saw_continue_prompt && saw_continue && saw_yes && saw_data_env && saw_data_prompt && saw_backup_env && saw_backup_prompt)) {
          printf "%s NewAPI uninstall must support DEPLOY_ASSUME_YES while requiring explicit env flags for data and backup deletion\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_newapi.sh
}

check_newapi_uninstall_checks_directory_removal_errors() {
  grep -Fq '_newapi_remove_dir_or_error() {' impl/install_newapi.sh \
    && grep -Fq 'app_remove_dir_or_error "$1" "$2" "$3" "app.newapi.error.remove_dir"' impl/install_newapi.sh \
    && grep -Fq '_newapi_remove_dir_or_error "$LOG_DIR" "LOG_DIR" "$(t app.newapi.success.deleted_log "$LOG_DIR")"' impl/install_newapi.sh \
    && grep -Fq '_newapi_remove_dir_or_error "$DATA_DIR" "DATA_DIR" "$(t app.newapi.success.deleted_data "$DATA_DIR")"' impl/install_newapi.sh \
    && grep -Fq 'warn "$(t app.newapi.warn.cleanup_install_failed "$INSTALL_DIR")"' impl/install_newapi.sh \
    && grep -Fq '_newapi_remove_dir_or_error "$BACKUP_DIR" "BACKUP_DIR" "$(t app.newapi.success.deleted_backup "$BACKUP_DIR")"' impl/install_newapi.sh \
    && grep -Fq 'app.newapi.error.remove_dir' apps/newapi.sh \
    && grep -Fq 'app.newapi.warn.cleanup_install_failed' apps/newapi.sh \
    || {
      echo "NewAPI uninstall must surface directory removal failures instead of reporting unconditional success." >&2
      return 1
    }
}

check_newapi_uninstall_checks_file_removal_errors() {
  grep -Fq '_newapi_remove_file_or_error() {' impl/install_newapi.sh \
    && grep -Fq 'app_remove_file_or_error "$1" "$2" "app.newapi.error.remove_file"' impl/install_newapi.sh \
    && grep -Fq '_newapi_remove_file_or_error "/etc/systemd/system/${SERVICE_NAME}.service" "NEWAPI_SERVICE_FILE"' impl/install_newapi.sh \
    && grep -Fq '_newapi_remove_file_or_error "/etc/cron.d/new-api-backup" "NEWAPI_CRON_FILE"' impl/install_newapi.sh \
    && grep -Fq '_newapi_remove_file_or_error "/usr/local/bin/new-api-backup" "NEWAPI_BACKUP_SCRIPT"' impl/install_newapi.sh \
    && grep -Fq '_newapi_remove_file_or_error "/etc/logrotate.d/new-api" "NEWAPI_LOGROTATE_FILE"' impl/install_newapi.sh \
    && grep -Fq '_newapi_remove_file_or_error "$ENV_FILE" "ENV_FILE"' impl/install_newapi.sh \
    && grep -Fq '_newapi_remove_file_or_error "$CONF_FILE" "CONF_FILE"' impl/install_newapi.sh \
    && grep -Fq 'app.newapi.error.remove_file' apps/newapi.sh \
    || {
      echo "NewAPI uninstall must surface file removal failures instead of reporting unconditional success." >&2
      return 1
    }
}

check_newapi_uninstall_validates_binary_path_before_removal() {
  grep -Fq '_newapi_require_safe_bin_path() {' impl/install_newapi.sh \
    || {
      echo "NewAPI must centralize BIN_PATH safety validation in a reusable helper." >&2
      return 1
    }
  awk '
      /do_uninstall\(\)/ { in_uninstall=1; saw_guard=0; saw_remove=0; saw_raw_rm=0; next }
      in_uninstall && /_newapi_require_safe_bin_path/ && !saw_guard { saw_guard=1; next }
      in_uninstall && /_newapi_remove_file_or_error "\$BIN_PATH" "BIN_PATH"/ {
        if (!saw_guard) {
          printf "%s NewAPI uninstall must validate BIN_PATH before removing the binary\n", FILENAME > "/dev/stderr"
          exit 1
        }
        saw_remove=1
      }
      in_uninstall && /rm -f "\$BIN_PATH"/ { saw_raw_rm=1 }
      in_uninstall && /success "\$\(t app\.newapi\.success\.removed_binary\)"/ {
        if (!(saw_guard && saw_remove) || saw_raw_rm) {
          printf "%s NewAPI uninstall must guard binary removal and surface BIN_PATH cleanup failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_uninstall=0
      }
    ' impl/install_newapi.sh
}

check_newapi_backup_lists_preserve_paths_with_spaces() {
  if grep -R -n 'awk '\''{print \$2}'\''' impl/install_newapi.sh 2>/dev/null; then
    echo "NewAPI backup and binary retention lists must not split paths on spaces." >&2
    return 1
  fi
  awk '
      /new-api\.bak\./ { in_binary=1 }
      in_binary && /-printf '\''%T@ %p\\0'\''/ { saw_binary_print0=1 }
      in_binary && /sort -z -rn \| tail -z -n \+4/ { saw_binary_sort=1 }
      in_binary && /_old_baks\+=\("\$\{_old_bak_entry#\* \}"\)/ { saw_binary_strip=1 }
      /info "\$\(t app\.newapi\.info\.backup_list "\$BACKUP_DIR"\)"/ { in_backup_list=1 }
      in_backup_list && /-printf '\''%T@ %p\\0'\''/ { saw_backup_print0=1 }
      in_backup_list && /sort -z -rn \| head -z -n 10/ { saw_backup_sort=1 }
      in_backup_list && /_bak_list\+=\("\$\{_bak_entry#\* \}"\)/ { saw_backup_strip=1 }
      /app\.newapi\.status\.backup_info/ { in_status=1 }
      in_status && /-printf '\''%T@ %p\\0'\''/ { saw_status_print0=1 }
      in_status && /sort -z -rn \| head -z -n 3/ { saw_status_sort=1 }
      in_status && /f="\$\{_bak_entry#\* \}"/ { saw_status_strip=1 }
      END {
        if (!(saw_binary_print0 && saw_binary_sort && saw_binary_strip && saw_backup_print0 && saw_backup_sort && saw_backup_strip && saw_status_print0 && saw_status_sort && saw_status_strip)) {
          printf "%s NewAPI backup and binary retention lists must use NUL-delimited sorting without splitting paths on spaces\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_newapi.sh
}

check_newapi_dependency_failures_are_reported() {
  if grep -R -nE '^[[:space:]]*apt-get update -qq$|^[[:space:]]*apt-get install -y -qq curl ca-certificates sqlite3$' \
      impl/install_newapi.sh 2>/dev/null; then
    echo "NewAPI dependency installation must use explicit conditionals with actionable errors." >&2
    return 1
  fi
  awk '
      /app\.newapi\.error\.apt_update/ { saw_update_key=1 }
      /\/var\/log\/apt\/\*/ { saw_update_guidance=1 }
      /app\.newapi\.error\.deps_install/ { saw_install_key=1 }
      /apt-get install -y curl ca-certificates sqlite3/ { saw_install_guidance=1 }
      END {
        if (!(saw_update_key && saw_update_guidance && saw_install_key && saw_install_guidance)) {
          print "NewAPI dependency failures must tell users how to inspect apt logs and retry package installation." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/newapi.sh
  awk '
      /step "\$\(t app\.newapi\.step\.deps\)"/ { in_block=1; saw_update_if=0; saw_update_error=0; saw_install_if=0; saw_install_error=0; next }
      in_block && /if ! apt-get update -qq; then/ { saw_update_if=1 }
      in_block && /error "\$\(t app\.newapi\.error\.apt_update\)"/ { saw_update_error=1 }
      in_block && /if ! apt-get install -y -qq curl ca-certificates sqlite3; then/ { saw_install_if=1 }
      in_block && /error "\$\(t app\.newapi\.error\.deps_install\)"/ { saw_install_error=1 }
      in_block && /success "\$\(t app\.newapi\.success\.deps\)"/ {
        if (!(saw_update_if && saw_update_error && saw_install_if && saw_install_error)) {
          printf "%s NewAPI dependency installation must fail through explicit conditionals with actionable errors\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_newapi.sh
}

check_newapi_runtime_dir_failures_are_explicit() {
  awk '
      /app\.newapi\.error\.user_create/ { saw_user_key=1 }
      /app\.newapi\.error\.dir_create/ { saw_dir_key=1 }
      /Check permissions for %s and %s, then retry/ { saw_dir_guidance=1 }
      /app\.newapi\.error\.dir_owner/ { saw_owner_key=1 }
      /Check filesystem permissions and retry/ { saw_owner_guidance=1 }
      END {
        if (!(saw_user_key && saw_dir_key && saw_dir_guidance && saw_owner_key && saw_owner_guidance)) {
          print "NewAPI runtime directory failures must provide actionable user, mkdir, and chown guidance." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/newapi.sh
  awk '
      /step "\$\(t app\.newapi\.step\.user_dirs\)"/ { in_dirs=1; saw_user_if=0; saw_user_error=0; saw_mkdir_if=0; saw_mkdir_error=0; saw_install_guard=0; saw_log_guard=0; saw_backup_guard=0; saw_chown_if=0; saw_chown_error=0; next }
      in_dirs && /if ! useradd -r -s \/usr\/sbin\/nologin -d "\$INSTALL_DIR" "\$SERVICE_USER"; then/ { saw_user_if=1 }
      in_dirs && /error "\$\(t app\.newapi\.error\.user_create "\$SERVICE_USER"\)"/ { saw_user_error=1 }
      in_dirs && /if ! mkdir -p "\$INSTALL_DIR" "\$DATA_DIR" "\$LOG_DIR" "\$BACKUP_DIR"; then/ { saw_mkdir_if=1 }
      in_dirs && /error "\$\(t app\.newapi\.error\.dir_create "\$INSTALL_DIR" "\$BACKUP_DIR"\)"/ { saw_mkdir_error=1 }
      in_dirs && /require_safe_path "INSTALL_DIR" "\$INSTALL_DIR"/ { saw_install_guard=1 }
      in_dirs && /require_safe_path "LOG_DIR" "\$LOG_DIR"/ { saw_log_guard=1 }
      in_dirs && /require_safe_path "BACKUP_DIR" "\$BACKUP_DIR"/ { saw_backup_guard=1 }
      in_dirs && /if ! chown -R "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$INSTALL_DIR" "\$LOG_DIR" "\$BACKUP_DIR"; then/ { saw_chown_if=1 }
      in_dirs && /error "\$\(t app\.newapi\.error\.dir_owner "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$INSTALL_DIR"\)"/ { saw_chown_error=1 }
      in_dirs && /success "\$\(t app\.newapi\.success\.dirs "\$INSTALL_DIR" "\$DATA_DIR" "\$LOG_DIR"\)"/ {
        if (!(saw_user_if && saw_user_error && saw_mkdir_if && saw_mkdir_error && saw_install_guard && saw_log_guard && saw_backup_guard && saw_chown_if && saw_chown_error)) {
          printf "%s NewAPI install must fail explicitly when user creation, directory creation, or directory ownership setup fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_dirs=0
      }
      /if \[\[ -n "\$OLD_BIN_BAK" \]\]; then/ { in_binary=1; saw_binary_chown_if=0; saw_binary_chown_error=0; next }
      in_binary && /if ! chown -R "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$INSTALL_DIR"; then/ { saw_binary_chown_if=1 }
      in_binary && /error "\$\(t app\.newapi\.error\.dir_owner "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$INSTALL_DIR"\)"/ { saw_binary_chown_error=1 }
      in_binary && /success "\$\(t app\.newapi\.success\.binary_installed "\$BIN_PATH"\)"/ {
        if (!(saw_binary_chown_if && saw_binary_chown_error)) {
          printf "%s NewAPI binary install must fail explicitly when ownership repair fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_binary=0
      }
    ' impl/install_newapi.sh
}

check_newapi_secret_uses_private_env_file() {
  if grep -R -n 'Environment="SESSION_SECRET=' impl/install_newapi.sh 2>/dev/null; then
    echo "NewAPI must not embed SESSION_SECRET directly in a world-readable systemd unit." >&2
    return 1
  fi
  awk '
      /_write_env_file\(\)/ { in_func=1; saw_atomic=0; saw_secret=0; next }
      in_func && /atomic_write_file "\$ENV_FILE" 600 root:root/ { saw_atomic=1 }
      in_func && /SESSION_SECRET=\$\{session_secret\}/ { saw_secret=1 }
      in_func && /^}/ {
        if (!(saw_atomic && saw_secret)) {
          printf "%s NewAPI runtime secrets must be written through a private environment file\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
      /EnvironmentFile=\$\{ENV_FILE\}/ { saw_envfile=1 }
      /error "\$\(t app\.newapi\.error\.env_file "\$ENV_FILE"\)"/ { saw_error=1 }
      /success "\$\(t app\.newapi\.success\.env_file "\$ENV_FILE"\)"/ { saw_success=1 }
      /_newapi_remove_file_or_error "\$ENV_FILE" "ENV_FILE"/ { saw_remove=1 }
      END {
        if (!(saw_envfile && saw_error && saw_success && saw_remove)) {
          printf "%s NewAPI must wire the private environment file through install and uninstall\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_newapi.sh
}

check_newapi_service_start_paths_are_explicit() {
  if grep -R -nE '^[[:space:]]*systemctl (start|restart) "\$SERVICE_NAME"$' \
      impl/install_newapi.sh 2>/dev/null; then
    echo "NewAPI service start/restart paths must branch explicitly on command failure." >&2
    return 1
  fi
  awk '
      /if ! systemctl enable "\$SERVICE_NAME" --quiet; then/ { in_install=1; saw_restart_wait=0; next }
      in_install && /if systemctl restart "\$SERVICE_NAME" && wait_for_service "\$SERVICE_NAME" 20; then/ { saw_restart_wait=1 }
      in_install && /warn "\$\(t app\.newapi\.warn\.start_rollback\)"/ {
        if (!saw_restart_wait) {
          printf "%s NewAPI install must gate service success on an explicit restart-and-wait branch\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_install=0
      }
      /systemctl daemon-reload/ && !seen_reload++ { next }
      /if ! _install_binary_candidate "\$TMP_BIN"; then/ { in_update=1; saw_start_wait=0; next }
      in_update && /if systemctl start "\$SERVICE_NAME" && wait_for_service "\$SERVICE_NAME" 20; then/ { saw_start_wait=1 }
      in_update && /warn "\$\(t app\.newapi\.warn\.update_start_failed "\$LATEST" "\$CURRENT"\)"/ {
        if (!saw_start_wait) {
          printf "%s NewAPI update must gate service success on an explicit start-and-wait branch\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_update=0
      }
    ' impl/install_newapi.sh
}

check_newapi_enable_failures_are_reported() {
  awk '
      /app\.newapi\.warn\.service_enable_failed/ { saw_warn_key=1 }
      /if ! systemctl enable "\$SERVICE_NAME" --quiet; then/ { saw_enable_if=1 }
      /warn "\$\(t app\.newapi\.warn\.service_enable_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_warn=1 }
      END {
        if (!(saw_warn_key && saw_enable_if && saw_warn)) {
          print "NewAPI must warn when service enablement fails." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/newapi.sh impl/install_newapi.sh
}

check_newapi_manual_backup_wal_result_is_explicit() {
  if grep -R -n '&& success "\$\(t app\.newapi\.success\.wal\)"' \
      impl/install_newapi.sh 2>/dev/null; then
    echo "NewAPI manual backup WAL checkpoint must use explicit conditionals." >&2
    return 1
  fi
  awk '
      /step "\$\(t app\.newapi\.step\.manual_backup\)"/ { in_backup=1; saw_dir_if=0; saw_dir_error=0; saw_wal_if=0; saw_wal_success=0; saw_wal_warn=0; next }
      in_backup && /if ! mkdir -p "\$BACKUP_DIR"; then/ { saw_dir_if=1 }
      in_backup && /error "\$\(t app\.newapi\.error\.backup_dir_create "\$BACKUP_DIR"\)"/ { saw_dir_error=1 }
      in_backup && /if sqlite3 "\$DB_FILE" "PRAGMA wal_checkpoint\(TRUNCATE\);" 2>\/dev\/null; then/ { saw_wal_if=1 }
      in_backup && /success "\$\(t app\.newapi\.success\.wal\)"/ { saw_wal_success=1 }
      in_backup && /warn "\$\(t app\.newapi\.warn\.wal\)"/ { saw_wal_warn=1 }
      in_backup && /local _ic/ {
        if (!(saw_dir_if && saw_dir_error && saw_wal_if && saw_wal_success && saw_wal_warn)) {
          printf "%s NewAPI manual backup must fail explicitly when the backup directory cannot be created, and must branch on WAL checkpoint results before integrity checks\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_backup=0
      }
    ' impl/install_newapi.sh
}

check_newapi_update_rollbacks_report_restart_failures() {
  if grep -R -n 'systemctl start "\$SERVICE_NAME" 2>/dev/null || true' \
      impl/install_newapi.sh 2>/dev/null; then
    echo "NewAPI update rollback paths must not suppress service restart failures." >&2
    return 1
  fi
  awk '
      /if ! _install_binary_candidate "\$TMP_BIN"; then/ { in_install_failure=1; saw_restore=0; saw_start_if=0; saw_warn=0; next }
      in_install_failure && /if _restore_binary_backup "\$BAK_PATH"; then/ { saw_restore=1 }
      in_install_failure && /if ! systemctl start "\$SERVICE_NAME"; then/ { saw_start_if=1 }
      in_install_failure && /warn "\$\(t app\.newapi\.warn\.rollback_start_failed "\$SERVICE_NAME"\)"/ { saw_warn=1 }
      in_install_failure && /error "\$\(t app\.newapi\.error\.binary_install "\$BIN_PATH"\)"/ {
        if (!(saw_restore && saw_start_if && saw_warn)) {
          printf "%s NewAPI binary-install rollback must warn when service restart fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_install_failure=0
      }
      /warn "\$\(t app\.newapi\.warn\.update_start_failed "\$LATEST" "\$CURRENT"\)"/ { in_update_failure=1; saw_restore2=0; saw_start_if2=0; saw_wait=0; saw_warn2=0; next }
      in_update_failure && /if ! _restore_binary_backup "\$BAK_PATH"; then/ { saw_restore2=1 }
      in_update_failure && /if systemctl start "\$SERVICE_NAME"; then/ { saw_start_if2=1 }
      in_update_failure && /if wait_for_service "\$SERVICE_NAME" 15; then/ { saw_wait=1 }
      in_update_failure && /warn "\$\(t app\.newapi\.warn\.rollback_start_failed "\$SERVICE_NAME"\)"/ { saw_warn2=1 }
      in_update_failure && saw_start_if2 && /error "\$\(t app\.newapi\.error\.update_failed "\$CURRENT" "\$SERVICE_NAME" "\$BAK_PATH"\)"/ {
        if (!(saw_restore2 && saw_start_if2 && saw_wait && saw_warn2)) {
          printf "%s NewAPI update rollback must branch explicitly on restart failures before reporting rollback outcome\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_update_failure=0
      }
    ' impl/install_newapi.sh
}

check_newapi_install_cleanup_reports_systemctl_failures() {
  awk '
      /app\.newapi\.warn\.cleanup_stop_failed/ { saw_stop_key=1 }
      /app\.newapi\.warn\.cleanup_disable_failed/ { saw_disable_key=1 }
      /app\.newapi\.warn\.cleanup_reload_failed/ { saw_reload_key=1 }
      END {
        if (!(saw_stop_key && saw_disable_key && saw_reload_key)) {
          print "NewAPI must provide localized install rollback cleanup warnings." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/newapi.sh
  awk '
      /warn "\$\(t app\.newapi\.warn\.start_rollback\)"/ { in_cleanup=1; saw_stop=0; saw_disable=0; saw_reload=0; saw_suppressed=0; next }
      in_cleanup && /\|\| true/ { saw_suppressed=1 }
      in_cleanup && /warn "\$\(t app\.newapi\.warn\.cleanup_stop_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_stop=1 }
      in_cleanup && /warn "\$\(t app\.newapi\.warn\.cleanup_disable_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_disable=1 }
      in_cleanup && /warn "\$\(t app\.newapi\.warn\.cleanup_reload_failed\)"/ { saw_reload=1 }
      in_cleanup && /error "\$\(t app\.newapi\.error\.install_start_failed "\$SERVICE_NAME"\)"/ {
        if (!(saw_stop && saw_disable && saw_reload) || saw_suppressed) {
          printf "%s NewAPI install rollback cleanup must warn on stop, disable, and daemon-reload failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_cleanup=0
      }
    ' impl/install_newapi.sh
}

check_newapi_install_rollback_validates_binary_path_before_removal() {
  awk '
      /warn "\$\(t app\.newapi\.warn\.start_rollback\)"/ { in_cleanup=1; saw_restore=0; saw_guard=0; saw_remove=0; saw_raw_rm=0; next }
      in_cleanup && /_restore_binary_backup "\$OLD_BIN_BAK"/ { saw_restore=1 }
      in_cleanup && !saw_restore && /_newapi_require_safe_bin_path/ { saw_guard=1 }
      in_cleanup && !saw_restore && /_newapi_remove_file_or_error "\$BIN_PATH" "BIN_PATH"/ {
        if (!saw_guard) {
          printf "%s NewAPI install rollback must validate BIN_PATH before removing the failed binary\n", FILENAME > "/dev/stderr"
          exit 1
        }
        saw_remove=1
      }
      in_cleanup && !saw_restore && /rm -f "\$BIN_PATH"/ { saw_raw_rm=1 }
      in_cleanup && /error "\$\(t app\.newapi\.error\.install_start_failed "\$SERVICE_NAME"\)"/ {
        if (!(saw_restore || (saw_guard && saw_remove)) || saw_raw_rm) {
          printf "%s NewAPI install rollback must either restore the backup or guard BIN_PATH and surface cleanup failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_cleanup=0
      }
    ' impl/install_newapi.sh
}

check_newapi_install_rollback_surfaces_service_file_removal_failures() {
  awk '
      /warn "\$\(t app\.newapi\.warn\.start_rollback\)"/ { in_cleanup=1; saw_remove=0; saw_raw_rm=0; next }
      in_cleanup && /_newapi_remove_file_or_error "\/etc\/systemd\/system\/\$\{SERVICE_NAME\}\.service" "NEWAPI_SERVICE_FILE"/ { saw_remove=1 }
      in_cleanup && /rm -f "\/etc\/systemd\/system\/\$\{SERVICE_NAME\}\.service"/ { saw_raw_rm=1 }
      in_cleanup && /if ! systemctl daemon-reload 2>\/dev\/null; then/ {
        if (!saw_remove || saw_raw_rm) {
          printf "%s NewAPI install rollback must surface service unit removal failures before daemon-reload\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
      in_cleanup && /error "\$\(t app\.newapi\.error\.install_start_failed "\$SERVICE_NAME"\)"/ { in_cleanup=0 }
    ' impl/install_newapi.sh
}

check_newapi_update_stop_failure_aborts_before_replace() {
  awk '
      /app\.newapi\.error\.stop_service_failed/ { saw_key=1 }
      END {
        if (!saw_key) {
          print "NewAPI must provide an actionable update stop failure error." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/newapi.sh
  awk '
      /info "\$\(t app\.newapi\.info\.stop_service\)"/ { in_stop=1; saw_if=0; saw_cleanup=0; saw_error=0; saw_suppressed=0; next }
      in_stop && /systemctl stop "\$SERVICE_NAME" 2>\/dev\/null \|\| true/ { saw_suppressed=1 }
      in_stop && /if ! systemctl stop "\$SERVICE_NAME" 2>\/dev\/null; then/ { saw_if=1 }
      in_stop && /if ! rm -f "\$TMP_BIN"; then/ { saw_cleanup=1 }
      in_stop && /warn "\$\(t app\.newapi\.warn\.tmp_binary_cleanup_failed "\$TMP_BIN"\)"/ { saw_cleanup_warn=1 }
      in_stop && /error "\$\(t app\.newapi\.error\.stop_service_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_error=1 }
      in_stop && /if ! _install_binary_candidate "\$TMP_BIN"; then/ {
        if (!(saw_if && saw_cleanup && saw_cleanup_warn && saw_error) || saw_suppressed) {
          printf "%s NewAPI update must abort and surface downloaded binary cleanup failures when stopping the service fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_stop=0
      }
    ' impl/install_newapi.sh
}

check_newapi_update_rollback_stop_failure_aborts_restore() {
  awk '
      /app\.newapi\.error\.rollback_stop_failed/ { saw_key=1 }
      END {
        if (!saw_key) {
          print "NewAPI must provide an actionable rollback stop failure error." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/newapi.sh
  awk '
      /warn "\$\(t app\.newapi\.warn\.update_start_failed "\$LATEST" "\$CURRENT"\)"/ { in_rollback=1; saw_if=0; saw_error=0; saw_suppressed=0; next }
      in_rollback && /systemctl stop "\$SERVICE_NAME" 2>\/dev\/null \|\| true/ { saw_suppressed=1 }
      in_rollback && /if ! systemctl stop "\$SERVICE_NAME" 2>\/dev\/null; then/ { saw_if=1 }
      in_rollback && /error "\$\(t app\.newapi\.error\.rollback_stop_failed "\$SERVICE_NAME" "\$BAK_PATH" "\$SERVICE_NAME"\)"/ { saw_error=1 }
      in_rollback && /if ! _restore_binary_backup "\$BAK_PATH"; then/ {
        if (!(saw_if && saw_error) || saw_suppressed) {
          printf "%s NewAPI update rollback must abort before restoring files when stopping the failed new service fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_rollback=0
      }
    ' impl/install_newapi.sh
}

check_newapi_uninstall_stop_disable_failures_are_reported() {
  awk '
      /app\.newapi\.error\.uninstall_stop_failed/ { saw_stop_error=1 }
      /app\.newapi\.warn\.uninstall_stop_failed/ { saw_stop_warn=1 }
      /app\.newapi\.warn\.uninstall_disable_failed/ { saw_disable_warn=1 }
      END {
        if (!(saw_stop_error && saw_stop_warn && saw_disable_warn)) {
          print "NewAPI must provide localized uninstall stop and disable failure messages." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/newapi.sh
  awk '
      /info "\$\(t app\.newapi\.info\.stop_disable "\$SERVICE_NAME"\)"/ { in_uninstall=1; saw_stop_if=0; saw_active_if=0; saw_stop_error=0; saw_stop_warn=0; saw_disable_if=0; saw_disable_warn=0; saw_suppressed=0; next }
      in_uninstall && /systemctl (stop|disable).* \|\| true/ { saw_suppressed=1 }
      in_uninstall && /if ! systemctl stop "\$SERVICE_NAME" 2>\/dev\/null; then/ { saw_stop_if=1 }
      in_uninstall && /if systemctl is-active --quiet "\$SERVICE_NAME" 2>\/dev\/null; then/ { saw_active_if=1 }
      in_uninstall && /error "\$\(t app\.newapi\.error\.uninstall_stop_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_stop_error=1 }
      in_uninstall && /warn "\$\(t app\.newapi\.warn\.uninstall_stop_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_stop_warn=1 }
      in_uninstall && /if ! systemctl disable "\$SERVICE_NAME" 2>\/dev\/null; then/ { saw_disable_if=1 }
      in_uninstall && /warn "\$\(t app\.newapi\.warn\.uninstall_disable_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_disable_warn=1 }
      in_uninstall && /rm -f "\/etc\/systemd\/system\/\$\{SERVICE_NAME\}\.service"/ {
        if (!(saw_stop_if && saw_active_if && saw_stop_error && saw_stop_warn && saw_disable_if && saw_disable_warn) || saw_suppressed) {
          printf "%s NewAPI uninstall must abort when an active service cannot be stopped and warn on disable failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_uninstall=0
      }
    ' impl/install_newapi.sh
}

check_newapi_install_summary_matches_health_state() {
  awk '
      /app\.newapi\.summary\.title_ready/ { saw_title_ready=1 }
      /app\.newapi\.summary\.title_pending/ { saw_title_pending=1 }
      END {
        if (!(saw_title_ready && saw_title_pending)) {
          print "NewAPI install summary strings must distinguish ready and pending health states." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/newapi.sh
  awk '
      /_health_check\(\)/ { in_health=1; saw_success=0; saw_return_ok=0; saw_warn=0; saw_return_fail=0; next }
      in_health && /success "\$\(t app\.newapi\.success\.http_health "\$HTTP_CODE"\)"/ { saw_success=1 }
      in_health && /return 0/ { saw_return_ok=1 }
      in_health && /warn "\$\(t app\.newapi\.warn\.http_health "\$HTTP_CODE"\)"/ { saw_warn=1 }
      in_health && /return 1/ { saw_return_fail=1 }
      in_health && /^}/ {
        if (!(saw_success && saw_return_ok && saw_warn && saw_return_fail)) {
          printf "%s NewAPI health helper must return explicit ready/pending status\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_health=0
      }
      /_print_install_summary\(\)/ { in_summary=1; saw_state=0; saw_pending=0; saw_ready=0; next }
      in_summary && /local summary_state="\$\{2:-ready\}"/ { saw_state=1 }
      in_summary && /summary_title="\$\(t app\.newapi\.summary\.title_pending\)"/ { saw_pending=1 }
      in_summary && /summary_title="\$\(t app\.newapi\.summary\.title_ready\)"/ { saw_ready=1 }
      in_summary && /^}/ {
        if (!(saw_state && saw_pending && saw_ready)) {
          printf "%s NewAPI install summary helper must branch on health state\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_summary=0
      }
      /local _install_summary_state="ready"/ { saw_init=1 }
      /step "\$\(t app\.newapi\.step\.health\)"/ { in_install=1; saw_pending_state=0; saw_health_if=0; saw_summary_call=0; next }
      in_install && /if ! _health_check; then/ { saw_health_if=1 }
      in_install && /_install_summary_state="pending"/ { saw_pending_state=1 }
      in_install && /_print_install_summary "\$LATEST" "\$_install_summary_state"/ {
        saw_summary_call=1
        if (!(saw_init && saw_health_if && saw_pending_state)) {
          printf "%s NewAPI install flow must downgrade the summary when health checks stay pending\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_install=0
      }
    ' impl/install_newapi.sh
}

check_newapi_health_checks_are_nonfatal_outside_install() {
  awk '
      /if systemctl start "\$SERVICE_NAME" && wait_for_service "\$SERVICE_NAME" 20; then/ { in_update=1; saw_health_if=0; next }
      in_update && /if ! _health_check; then/ { saw_health_if=1 }
      in_update && /echo -e "  \$\{BOLD\}\$\{GREEN\}\$\(t app\.newapi\.success\.update_done/ {
        if (!saw_health_if) {
          printf "%s NewAPI update must treat post-restart health warnings as nonfatal\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_update=0
      }
    ' impl/install_newapi.sh
}

check_newapi_status_backup_projection() {
  local output tmp_dir
  tmp_dir="$(mktemp -d)"
  # Present a trusted config (root, mode 600) via the stat stub so the run is
  # platform-independent; the shared projection must adopt the configured
  # BACKUP_DIR only after the root/600/400 trust gate passes.
  cat > "${tmp_dir}/stat" <<'STUB'
#!/usr/bin/env bash
case "${2:-}" in
  %U) echo root ;;
  %a) echo 600 ;;
  *) /usr/bin/stat "$@" ;;
esac
STUB
  chmod +x "${tmp_dir}/stat"
  output="$(PATH="${tmp_dir}:$PATH" APP_CONF_FILE="${tmp_dir}/new-api.conf" "$BASH_BIN" -c '
    set -euo pipefail
    tmp_dir="$(mktemp -d)"
    conf_file="${APP_CONF_FILE}"
    backup_dir="${tmp_dir}/backups"
    mkdir -p "$backup_dir"
    printf "BACKUP_DIR=\\\"%s\\\"\\n" "$backup_dir" > "$conf_file"
    touch -d "2026-08-20 12:34:56 UTC" "$backup_dir/new-api_20260820123456.tar.gz"
    source lib/core.sh
    APP_ID=newapi
    APP_NAME="New API"
    app_conf_file() { printf "%s" "$APP_CONF_FILE"; }
    source impl/install_newapi.sh
    _newapi_status_backup
    rm -rf "$tmp_dir"
  ')"
  local status=$?
  rm -rf "$tmp_dir"
  [[ "$status" -eq 0 ]] || return 1
  python -c 'import json,sys; x=json.loads(sys.argv[1]); assert x["state"] == "available"; assert x["path"].endswith("new-api_20260820123456.tar.gz"); assert x["last_success_at"]' "$output"
}
