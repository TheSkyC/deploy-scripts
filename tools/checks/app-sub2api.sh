# shellcheck shell=bash
# shellcheck source=../verify.sh
# Verify checks for the sub2api app (apps/sub2api.sh, impl/install_sub2api.sh).

# Keep the Docker smoke fixture tied to real database/cache process contracts.
# The CI e2e-smoke job proves these commands execute; this guard prevents a
# future edit from silently replacing that scenario with command-only fakes.
check_sub2api_e2e_uses_real_dependency_fixture() {
  local fixture="tools/e2e-smoke.sh"
  grep -Fq "postgresql-15 redis-server redis-tools" "$fixture" \
    && grep -Fq "pg_ctlcluster --skip-systemctl-redirect 15 main start" "$fixture" \
    && grep -Fq "pg_isready -q" "$fixture" \
    && grep -Fq "redis-server --daemonize yes --bind 127.0.0.1 --port 6379" "$fixture" \
    && grep -Fq "redis-cli ping" "$fixture" \
    && grep -Fq 'psql "$PG_DSN" -v ON_ERROR_STOP=1' "$fixture" \
    && grep -Fq 'gzip -cd "$DB_ARCHIVE" | grep -Fq "fixture-row"' "$fixture" \
    && grep -Fq "SUB2API_REAL_DEPENDENCIES_SMOKE_OK" "$fixture" \
    || {
      echo "Sub2API E2E must retain its real PostgreSQL/Redis fixture and pg_dump content assertion." >&2
      return 1
    }
}

check_sub2api_status_backup_projection() {
  local output
  output="$($BASH_BIN -c '
    set -euo pipefail
    tmp_dir="$(mktemp -d)"
    backup_dir="$tmp_dir/sub2api backups"
    mkdir -p "$backup_dir"
    touch -d "2026-08-20 12:34:56 UTC" "$backup_dir/sub2api_data_20260820123456.tar.gz"
    source lib/core.sh
    APP_ID=sub2api
    APP_NAME="Sub2API"
    BACKUP_DIR="$backup_dir"
    app_conf_file() { printf "%s" "$tmp_dir/missing.conf"; }
    source impl/install_sub2api.sh
    _sub2api_status_backup
    rm -rf "$tmp_dir"
  ')"
  python -c 'import json,sys; x=json.loads(sys.argv[1]); assert x["state"] == "available"; assert "sub2api backups" in x["path"]; assert x["path"].endswith("sub2api_data_20260820123456.tar.gz"); assert x["last_success_at"]' "$output"
  grep -Fq 'APP_STATUS_BACKUP_FN=_sub2api_status_backup' impl/install_sub2api.sh
}

check_sub2api_uninstall_supports_noninteractive_mode() {
  awk '
      /prompt "\$\(t app\.sub2api\.prompt\.continue\)"/ { saw_continue_prompt=1 }
      /if deploy_assume_yes; then/ && !saw_continue { saw_continue=1; next }
      saw_continue && /_c="YES"/ { saw_yes=1 }
      /local DELETE_DATA=false/ { in_data=1; next }
      in_data && /deploy_env_truthy DEPLOY_DELETE_DATA && DELETE_DATA=true/ { saw_data_env=1 }
      in_data && /prompt "\$\(t app\.sub2api\.prompt\.delete_data "\$DATA_DIR"\)"/ { saw_data_prompt=1; in_data=0 }
      /local DELETE_CONF=false/ { in_conf=1; next }
      in_conf && /deploy_env_truthy DEPLOY_DELETE_CONFIG && DELETE_CONF=true/ { saw_conf_env=1 }
      in_conf && /prompt "\$\(t app\.sub2api\.prompt\.delete_config "\$CONFIG_DIR"\)"/ { saw_conf_prompt=1; in_conf=0 }
      /local DELETE_BACKUP=false/ { in_backup=1; next }
      in_backup && /deploy_env_truthy DEPLOY_DELETE_BACKUP && DELETE_BACKUP=true/ { saw_backup_env=1 }
      in_backup && /prompt "\$\(t app\.sub2api\.prompt\.delete_backup "\$BACKUP_DIR"\)"/ { saw_backup_prompt=1; in_backup=0 }
      END {
        if (!(saw_continue_prompt && saw_continue && saw_yes && saw_data_env && saw_data_prompt && saw_conf_env && saw_conf_prompt && saw_backup_env && saw_backup_prompt)) {
          printf "%s Sub2API uninstall must support DEPLOY_ASSUME_YES while requiring explicit env flags for data, config, and backup deletion\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_sub2api.sh
}

check_sub2api_uninstall_checks_directory_removal_errors() {
  grep -Fq '_sub2api_remove_dir_or_error() {' impl/install_sub2api.sh \
    && grep -Fq 'app_remove_dir_or_error "$1" "$2" "$3" "app.sub2api.error.remove_dir"' impl/install_sub2api.sh \
    && grep -Fq '_sub2api_remove_dir_or_error "$LOG_DIR" "LOG_DIR" "$(t app.sub2api.success.deleted_log "$LOG_DIR")"' impl/install_sub2api.sh \
    && grep -Fq '_sub2api_remove_dir_or_error "$DATA_DIR" "DATA_DIR" "$(t app.sub2api.success.deleted_data "$DATA_DIR")"' impl/install_sub2api.sh \
    && grep -Fq 'warn "$(t app.sub2api.warn.cleanup_install_failed "$INSTALL_DIR")"' impl/install_sub2api.sh \
    && grep -Fq '_sub2api_remove_dir_or_error "$CONFIG_DIR" "CONFIG_DIR" "$(t app.sub2api.success.deleted_config "$CONFIG_DIR")"' impl/install_sub2api.sh \
    && grep -Fq '_sub2api_remove_dir_or_error "$BACKUP_DIR" "BACKUP_DIR" "$(t app.sub2api.success.deleted_backup "$BACKUP_DIR")"' impl/install_sub2api.sh \
    && grep -Fq 'app.sub2api.error.remove_dir' apps/sub2api.sh \
    && grep -Fq 'app.sub2api.warn.cleanup_install_failed' apps/sub2api.sh \
    || {
      echo "Sub2API uninstall must surface directory removal failures instead of reporting unconditional success." >&2
      return 1
    }
}

check_sub2api_uninstall_checks_file_removal_errors() {
  grep -Fq '_sub2api_remove_file_or_error() {' impl/install_sub2api.sh \
    && grep -Fq 'app_remove_file_or_error "$1" "$2" "app.sub2api.error.remove_file"' impl/install_sub2api.sh \
    && grep -Fq '_sub2api_remove_file_or_error "/etc/systemd/system/${SERVICE_NAME}.service" "SUB2API_SERVICE_FILE"' impl/install_sub2api.sh \
    && grep -Fq '_sub2api_remove_file_or_error "/etc/nginx/sites-enabled/sub2api" "SUB2API_NGINX_LINK"' impl/install_sub2api.sh \
    && grep -Fq '_sub2api_remove_file_or_error "/etc/nginx/sites-available/sub2api" "SUB2API_NGINX_CONF"' impl/install_sub2api.sh \
    && grep -Fq '_sub2api_remove_file_or_error "/etc/cron.d/sub2api-backup" "SUB2API_CRON_FILE"' impl/install_sub2api.sh \
    && grep -Fq '_sub2api_remove_file_or_error "/usr/local/bin/sub2api-backup" "SUB2API_BACKUP_SCRIPT"' impl/install_sub2api.sh \
    && grep -Fq '_sub2api_remove_file_or_error "/etc/logrotate.d/sub2api" "SUB2API_LOGROTATE_FILE"' impl/install_sub2api.sh \
    && grep -Fq '_sub2api_remove_file_or_error "$CONF_FILE" "CONF_FILE"' impl/install_sub2api.sh \
    && grep -Fq 'app.sub2api.error.remove_file' apps/sub2api.sh \
    || {
      echo "Sub2API uninstall must surface file removal failures instead of reporting unconditional success." >&2
      return 1
    }
}

check_sub2api_uninstall_validates_binary_path_before_removal() {
  grep -Fq '_sub2api_require_safe_bin_path() {' impl/install_sub2api.sh \
    || {
      echo "Sub2API must centralize BIN_PATH safety validation in a reusable helper." >&2
      return 1
    }
  awk '
      /do_uninstall\(\)/ { in_uninstall=1; saw_guard=0; saw_remove=0; saw_raw_rm=0; next }
      in_uninstall && /_sub2api_require_safe_bin_path/ && !saw_guard { saw_guard=1; next }
      in_uninstall && /_sub2api_remove_file_or_error "\$BIN_PATH" "BIN_PATH"/ {
        if (!saw_guard) {
          printf "%s Sub2API uninstall must validate BIN_PATH before removing the binary\n", FILENAME > "/dev/stderr"
          exit 1
        }
        saw_remove=1
      }
      in_uninstall && /rm -f "\$BIN_PATH"/ { saw_raw_rm=1 }
      in_uninstall && /success "\$\(t app\.sub2api\.success\.removed_binary\)"/ {
        if (!(saw_guard && saw_remove) || saw_raw_rm) {
          printf "%s Sub2API uninstall must guard binary removal and surface BIN_PATH cleanup failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_uninstall=0
      }
    ' impl/install_sub2api.sh
}

check_sub2api_backup_lists_preserve_paths_with_spaces() {
  awk '
      /sub2api\.bak\./ { in_binary=1 }
      in_binary && /-printf '\''%T@ %p\\0'\''/ { saw_binary_print0=1 }
      in_binary && /sort -z -rn \| tail -z -n \+4/ { saw_binary_sort=1 }
      in_binary && /_old_baks\+=\("\$\{_old_bak_entry#\* \}"\)/ { saw_binary_strip=1 }
      /app\.sub2api\.status\.backup_info/ { in_status=1 }
      in_status && /-printf '\''%T@ %p\\0'\''/ { saw_status_print0=1 }
      in_status && /sort -z -rn \| head -z -n 5/ { saw_status_sort=1 }
      in_status && /f="\$\{_bak_entry#\* \}"/ { saw_status_strip=1 }
      END {
        if (!(saw_binary_print0 && saw_binary_sort && saw_binary_strip && saw_status_print0 && saw_status_sort && saw_status_strip)) {
          printf "%s Sub2API backup and binary retention lists must use NUL-delimited sorting without splitting paths on spaces\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_sub2api.sh
}

check_sub2api_codename_resolution() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"

  cat > "${tmp_dir}/lsb_release" <<'STUB'
#!/usr/bin/env bash
[[ "${1:-}" == "-cs" ]] || exit 1
echo jammy
STUB
  chmod +x "${tmp_dir}/lsb_release"

  PATH="${tmp_dir}:$PATH" "$BASH_BIN" -c '
    set -euo pipefail
    unset VERSION_CODENAME UBUNTU_CODENAME
    source lib/core.sh
    source apps/sub2api.sh
    [[ "$(_apt_codename)" == "jammy" ]]
  '

  rm -rf "$tmp_dir"
}

check_sub2api_apt_failures_are_reported() {
  if grep -R -nE '^[[:space:]]*apt-get update -qq$' \
      impl/install_sub2api.sh 2>/dev/null; then
    echo "Sub2API apt-get update paths must use explicit conditionals with actionable errors." >&2
    return 1
  fi
  awk '
      /app\.sub2api\.error\.apt_update/ { saw_base_update_key=1 }
      /app\.sub2api\.error\.base_deps_install/ { saw_base_install_key=1 }
      /app\.sub2api\.error\.postgres_apt_update/ { saw_pg_update_key=1 }
      /app\.sub2api\.error\.postgres_apt_install/ { saw_pg_install_key=1 }
      /app\.sub2api\.error\.redis_apt_update/ { saw_redis_update_key=1 }
      /app\.sub2api\.error\.redis_apt_install/ { saw_redis_install_key=1 }
      /\/var\/log\/apt\/\*/ { saw_apt_guidance=1 }
      /apt-get install -y curl ca-certificates gnupg lsb-release/ { saw_base_install_guidance=1 }
      /apt-get install -y postgresql-15 postgresql-client-15/ { saw_pg_install_guidance=1 }
      /apt-get install -y redis/ { saw_redis_install_guidance=1 }
      /\/etc\/apt\/sources\.list\.d\/pgdg\.list/ { saw_pg_source_guidance=1 }
      /\/etc\/apt\/sources\.list\.d\/redis\.list/ { saw_redis_source_guidance=1 }
      END {
        if (!(saw_base_update_key && saw_base_install_key && saw_pg_update_key && saw_pg_install_key && saw_redis_update_key && saw_redis_install_key && saw_apt_guidance && saw_base_install_guidance && saw_pg_install_guidance && saw_redis_install_guidance && saw_pg_source_guidance && saw_redis_source_guidance)) {
          print "Sub2API apt failures must tell users how to inspect apt logs, repair repository files, and retry package installation." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/sub2api.sh
  awk '
      /_install_base_deps\(\)/ { in_base=1; saw_update_if=0; saw_update_error=0; saw_install_if=0; saw_install_error=0; next }
      in_base && /if ! apt-get update -qq; then/ { saw_update_if=1 }
      in_base && /error "\$\(t app\.sub2api\.error\.apt_update\)"/ { saw_update_error=1 }
      in_base && /if ! DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \\/ { saw_install_if=1 }
      in_base && /error "\$\(t app\.sub2api\.error\.base_deps_install\)"/ { saw_install_error=1 }
      in_base && /success "\$\(t app\.sub2api\.success\.base_deps\)"/ {
        if (!(saw_update_if && saw_update_error && saw_install_if && saw_install_error)) {
          printf "%s Sub2API base dependency installation must fail through explicit conditionals with actionable errors\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_base=0
      }
      /_install_postgres\(\)/ { in_pg_func=1; next }
      /_install_redis\(\)/ { in_redis_func=1; next }
      in_pg_func && /if \[\[ "\$PKG_MANAGER" == "apt" \]\]; then/ { in_pg=1; in_pg_func=0; next }
      in_redis_func && /if \[\[ "\$PKG_MANAGER" == "apt" \]\]; then/ { in_redis=1; in_redis_func=0; next }
      in_pg && /if ! apt-get update -qq; then/ { saw_pg_update_if=1 }
      in_pg && /error "\$\(t app\.sub2api\.error\.postgres_apt_update\)"/ { saw_pg_update_error=1 }
      in_pg && /if ! DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-15 postgresql-client-15; then/ { saw_pg_install_if=1 }
      in_pg && /error "\$\(t app\.sub2api\.error\.postgres_apt_install\)"/ { saw_pg_install_error=1 }
      in_pg && /if ! systemctl enable postgresql 2>\/dev\/null; then/ {
        if (!(saw_pg_update_if && saw_pg_update_error && saw_pg_install_if && saw_pg_install_error)) {
          printf "%s Sub2API PostgreSQL apt installation must fail through explicit conditionals with actionable errors\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_pg=0
      }
      in_redis && /if ! apt-get update -qq; then/ { saw_redis_update_if=1 }
      in_redis && /error "\$\(t app\.sub2api\.error\.redis_apt_update\)"/ { saw_redis_update_error=1 }
      in_redis && /if ! DEBIAN_FRONTEND=noninteractive apt-get install -y redis; then/ { saw_redis_install_if=1 }
      in_redis && /error "\$\(t app\.sub2api\.error\.redis_apt_install\)"/ { saw_redis_install_error=1 }
      in_redis && /_ensure_redis_running \|\| error "\$\(t app\.sub2api\.error\.redis_start\)"/ {
        if (!(saw_redis_update_if && saw_redis_update_error && saw_redis_install_if && saw_redis_install_error)) {
          printf "%s Sub2API Redis apt installation must fail through explicit conditionals with actionable errors\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_redis=0
      }
    ' impl/install_sub2api.sh
}

check_sub2api_rpm_dependency_failures_are_reported() {
  awk '
      /app\.sub2api\.error\.base_deps_install_pkg/ { saw_base_key=1 }
      /dnf or yum/ { saw_base_guidance=1 }
      /app\.sub2api\.error\.postgres_rpm_install/ { saw_pg_key=1 }
      /dnf install -y postgresql15-server postgresql15-contrib/ { saw_pg_dnf_guidance=1 }
      /yum install -y postgresql15-server postgresql15-contrib/ { saw_pg_yum_guidance=1 }
      /app\.sub2api\.error\.redis_pkg_install/ { saw_redis_key=1 }
      /dnf install -y redis/ { saw_redis_dnf_guidance=1 }
      /yum install -y redis/ { saw_redis_yum_guidance=1 }
      END {
        if (!(saw_base_key && saw_base_guidance && saw_pg_key && saw_pg_dnf_guidance && saw_pg_yum_guidance && saw_redis_key && saw_redis_dnf_guidance && saw_redis_yum_guidance)) {
          print "Sub2API RPM/dnf/yum failures must tell users how to retry package installation." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/sub2api.sh
  awk '
      /_install_base_deps\(\)/ { in_base=1; saw_dnf_base=0; saw_yum_base=0; next }
      in_base && /dnf install -y -q curl ca-certificates \|\| error "\$\(t app\.sub2api\.error\.base_deps_install_pkg\)"/ { saw_dnf_base=1 }
      in_base && /yum install -y -q curl ca-certificates \|\| error "\$\(t app\.sub2api\.error\.base_deps_install_pkg\)"/ { saw_yum_base=1 }
      in_base && /success "\$\(t app\.sub2api\.success\.base_deps\)"/ {
        if (!(saw_dnf_base && saw_yum_base)) {
          printf "%s Sub2API RPM base dependency installation must fail explicitly with actionable errors\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_base=0
      }
      /\[\[ "\$PKG_MANAGER" == "dnf" \|\| "\$PKG_MANAGER" == "yum" \]\]/ { in_pg=1; saw_dnf_pg=0; saw_yum_pg=0; next }
      in_pg && /dnf install -y postgresql15-server postgresql15-contrib \|\| error "\$\(t app\.sub2api\.error\.postgres_rpm_install\)"/ { saw_dnf_pg=1 }
      in_pg && /yum install -y postgresql15-server postgresql15-contrib \|\| error "\$\(t app\.sub2api\.error\.postgres_rpm_install\)"/ { saw_yum_pg=1 }
      in_pg && /success "\$\(t app\.sub2api\.success\.postgres15\)"/ {
        if (!(saw_dnf_pg && saw_yum_pg)) {
          printf "%s Sub2API PostgreSQL RPM package installation must fail explicitly with actionable errors\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_pg=0
      }
      /_install_redis\(\)/ { in_redis_func=1; next }
      in_redis_func && /elif \[\[ "\$PKG_MANAGER" == "dnf" \]\]; then/ { in_redis_dnf=1; in_redis_func=0; next }
      in_redis_dnf && /dnf install -y redis \|\| error "\$\(t app\.sub2api\.error\.redis_pkg_install\)"/ { saw_dnf_redis=1 }
      /elif \[\[ "\$PKG_MANAGER" == "yum" \]\]; then/ { if (in_redis_dnf) { in_redis_yum=1; in_redis_dnf=0; next } }
      in_redis_yum && /yum install -y redis \|\| error "\$\(t app\.sub2api\.error\.redis_pkg_install\)"/ { saw_yum_redis=1 }
      in_redis_yum && /success "\$\(t app\.sub2api\.success\.redis\)"/ {
        if (!(saw_dnf_redis && saw_yum_redis)) {
          printf "%s Sub2API Redis RPM package installation must fail explicitly with actionable errors\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_redis_yum=0
      }
    ' impl/install_sub2api.sh
}

check_sub2api_runtime_dir_failures_are_explicit() {
  awk '
      /app\.sub2api\.error\.user_create/ { saw_user_key=1 }
      /app\.sub2api\.error\.dir_create/ { saw_dir_key=1 }
      /Check permissions for %s and %s, then retry/ { saw_dir_guidance=1 }
      /app\.sub2api\.error\.dir_owner/ { saw_owner_key=1 }
      /app\.sub2api\.error\.config_dir_mode/ { saw_mode_key=1 }
      /directory mode 750/ { saw_mode_guidance=1 }
      END {
        if (!(saw_user_key && saw_dir_key && saw_dir_guidance && saw_owner_key && saw_mode_key && saw_mode_guidance)) {
          print "Sub2API runtime directory failures must provide actionable user, mkdir, chown, and chmod guidance." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/sub2api.sh
  awk '
      /step "\$\(t app\.sub2api\.step\.user_dirs\)"/ { in_dirs=1; saw_user_if=0; saw_user_error=0; saw_mkdir_if=0; saw_mkdir_error=0; saw_install_guard=0; saw_log_guard=0; saw_config_guard=0; saw_chown_if=0; saw_chown_error=0; saw_chmod_if=0; saw_chmod_error=0; next }
      in_dirs && /if ! useradd -r -s \/usr\/sbin\/nologin -d "\$INSTALL_DIR" "\$SERVICE_USER"; then/ { saw_user_if=1 }
      in_dirs && /error "\$\(t app\.sub2api\.error\.user_create "\$SERVICE_USER"\)"/ { saw_user_error=1 }
      in_dirs && /if ! mkdir -p "\$INSTALL_DIR" "\$DATA_DIR" "\$LOG_DIR" "\$CONFIG_DIR" "\$BACKUP_DIR"; then/ { saw_mkdir_if=1 }
      in_dirs && /error "\$\(t app\.sub2api\.error\.dir_create "\$INSTALL_DIR" "\$BACKUP_DIR"\)"/ { saw_mkdir_error=1 }
      in_dirs && /require_safe_path "INSTALL_DIR" "\$INSTALL_DIR"/ { saw_install_guard=1 }
      in_dirs && /require_safe_path "LOG_DIR" "\$LOG_DIR"/ { saw_log_guard=1 }
      in_dirs && /require_safe_path "CONFIG_DIR" "\$CONFIG_DIR"/ { saw_config_guard=1 }
      in_dirs && /if ! chown -R "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$INSTALL_DIR" "\$LOG_DIR" "\$CONFIG_DIR"; then/ { saw_chown_if=1 }
      in_dirs && /error "\$\(t app\.sub2api\.error\.dir_owner "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$INSTALL_DIR"\)"/ { saw_chown_error=1 }
      in_dirs && /if ! chmod 750 "\$CONFIG_DIR"; then/ { saw_chmod_if=1 }
      in_dirs && /error "\$\(t app\.sub2api\.error\.config_dir_mode "\$CONFIG_DIR"\)"/ { saw_chmod_error=1 }
      in_dirs && /success "\$\(t app\.sub2api\.success\.dirs_created\)"/ {
        if (!(saw_user_if && saw_user_error && saw_mkdir_if && saw_mkdir_error && saw_install_guard && saw_log_guard && saw_config_guard && saw_chown_if && saw_chown_error && saw_chmod_if && saw_chmod_error)) {
          printf "%s Sub2API install must fail explicitly when user creation, directory creation, ownership setup, or config-dir chmod fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_dirs=0
      }
    ' impl/install_sub2api.sh
}

check_sub2api_manual_backup_warnings_are_actionable() {
  awk '
      /app\.sub2api\.warn\.config_backup_failed/ { saw_config_fail=1 }
      /partial archives may still exist in the backup directory/ { saw_partial=1 }
      /app\.sub2api\.warn\.data_missing/ { saw_data_missing=1 }
      /skipping data archive creation/ { saw_data_missing_guidance=1 }
      /app\.sub2api\.warn\.data_backup_failed/ { saw_data_fail=1 }
      END {
        if (!(saw_config_fail && saw_partial && saw_data_missing && saw_data_missing_guidance && saw_data_fail)) {
          print "Sub2API backup warnings must describe partial archive state and missing data directories." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/sub2api.sh
  awk '
      /step "\$\(t app\.sub2api\.step\.manual_backup\)"/ { in_backup=1; next }
      in_backup && /if ! mkdir -p "\$BACKUP_DIR"; then/ { saw_dir_if=1 }
      in_backup && /error "\$\(t app\.sub2api\.error\.backup_dir_create "\$BACKUP_DIR"\)"/ { saw_dir_error=1 }
      in_backup && /warn "\$\(t app\.sub2api\.warn\.config_backup_failed\)"/ { saw_config_warn=1 }
      in_backup && /warn "\$\(t app\.sub2api\.warn\.data_backup_failed\)"/ { saw_data_warn=1 }
      in_backup && /warn "\$\(t app\.sub2api\.warn\.data_missing "\$DATA_DIR"\)"/ { saw_data_missing_warn=1 }
      in_backup && /success "\$\(t app\.sub2api\.success\.backup_done "\$BACKUP_DIR"\)"/ { in_backup=0 }
      END {
        if (!(saw_dir_if && saw_dir_error && saw_config_warn && saw_data_warn && saw_data_missing_warn)) {
          print "Sub2API manual backup must fail explicitly when the backup directory cannot be created, and warn for config/data archive failures and missing data directories." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_sub2api.sh
}

check_sub2api_extract_move_failure_cleanup() {
  if grep -R -n '^[[:space:]]*mv "$bin_path" "$tmp_bin"$' impl/install_sub2api.sh 2>/dev/null; then
    echo "sub2api extraction must clean up temporary files if moving the binary fails." >&2
    return 1
  fi
  awk '
      /app\.sub2api\.warn\.tmp_archive_cleanup_failed/ { saw_archive_warn_key=1 }
      /app\.sub2api\.warn\.tmp_binary_cleanup_failed/ { saw_bin_warn_key=1 }
      END {
        if (!(saw_archive_warn_key && saw_bin_warn_key)) {
          print "Sub2API extraction must provide localized archive and binary cleanup warnings." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/sub2api.sh
  awk '
      /extract_and_verify\(\)/ { in_func=1; saw_extract_tmp=0; saw_extract_archive_rm=0; saw_extract_archive_warn=0; saw_extract_error=0; saw_bin_tmp=0; saw_bin_archive_rm=0; saw_bin_archive_warn=0; saw_bin_tmp_rm=0; saw_bin_tmp_warn=0; saw_bin_extract_rm=0; saw_bin_error=0; next }
      in_func && index($0, "if ! tmp_extract=$(mktemp -d \"${dest_dir}/sub2api-extract.XXXXXX\"); then") { saw_extract_tmp=1; next }
      in_func && saw_bin_tmp && index($0, "if ! rm -f \"$archive\"; then") { saw_bin_archive_rm=1; next }
      in_func && saw_bin_tmp && index($0, "warn \"$(t app.sub2api.warn.tmp_archive_cleanup_failed \"$archive\")\"") { saw_bin_archive_warn=1; next }
      in_func && saw_bin_tmp && index($0, "if ! rm -f \"$tmp_bin\"; then") { saw_bin_tmp_rm=1; next }
      in_func && saw_bin_tmp && index($0, "warn \"$(t app.sub2api.warn.tmp_binary_cleanup_failed \"$tmp_bin\")\"") { saw_bin_tmp_warn=1; next }
      in_func && saw_bin_tmp && index($0, "rm -rf \"$tmp_extract\"") { saw_bin_extract_rm=1; next }
      in_func && saw_bin_tmp && index($0, "error \"$(t app.sub2api.error.archive_missing_binary)\"") { saw_bin_error=1; next }
      in_func && saw_extract_tmp && index($0, "if ! rm -f \"$archive\"; then") { saw_extract_archive_rm=1; next }
      in_func && saw_extract_tmp && index($0, "warn \"$(t app.sub2api.warn.tmp_archive_cleanup_failed \"$archive\")\"") { saw_extract_archive_warn=1; next }
      in_func && saw_extract_tmp && index($0, "error \"$(t app.sub2api.error.tar_extract)\"") { saw_extract_error=1; next }
      in_func && index($0, "if ! tmp_bin=$(mktemp \"${dest_dir}/sub2api.tmp.XXXXXX\"); then") { saw_bin_tmp=1; next }
      in_func && index($0, "echo \"$tmp_bin\"") {
        if (!(saw_extract_tmp && saw_extract_archive_rm && saw_extract_archive_warn && saw_extract_error && saw_bin_tmp && saw_bin_archive_rm && saw_bin_archive_warn && saw_bin_tmp_rm && saw_bin_tmp_warn && saw_bin_extract_rm && saw_bin_error)) {
          printf "%s sub2api extraction must report and surface archive/binary cleanup failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_sub2api.sh
}

check_sub2api_pg_dump_errors_stay_out_of_backups() {
  if grep -R -nE 'pg_dump "\$\{PG_DSN\}" 2>&1 \| gzip >|pg_dump "\$PG_DSN" 2>&1 \| gzip >' \
      impl/install_sub2api.sh 2>/dev/null; then
    echo "Sub2API pg_dump backups must not mix stderr into compressed SQL archives." >&2
    return 1
  fi
  if grep -R -nE 'pg_dump "\$\{PG_DSN\}" 2>/dev/null \| gzip >|pg_dump "\$PG_DSN" 2>/dev/null \| gzip >' \
      impl/install_sub2api.sh 2>/dev/null; then
    echo "Sub2API pg_dump backups must preserve stderr diagnostics instead of discarding them." >&2
    return 1
  fi
  awk '
      /PG_DUMP_FILE="\$\{BACKUP_DIR\}\/sub2api_db_\$\{TS\}\.sql\.gz"/ { in_script=1; saw_stderr_log=0; saw_archive=0; next }
      in_script && /pg_dump "\$\{PG_DSN\}" 2> >\(/ { saw_stderr_log=1 }
      in_script && /gzip > "\$\{PG_DUMP_TMP\}"/ { saw_archive=1 }
      in_script && /# ── 2\. Configuration and local data backup/ {
        if (!(saw_stderr_log && saw_archive)) {
          printf "%s Sub2API backup script must keep pg_dump stderr separate from SQL archive data\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_script=0
      }
      /do_backup\(\)/ { in_manual=1; saw_manual_archive=0; next }
      in_manual && /pg_dump "\$\{PG_DSN\}" \| gzip > "\$PG_TMP"/ { saw_manual_archive=1 }
      in_manual && /^}/ {
        if (!saw_manual_archive) {
          printf "%s Sub2API manual backup must archive only pg_dump stdout\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_manual=0
      }
      /_backup_silent\(\)/ { in_silent=1; saw_silent_stderr=0; next }
      in_silent && /pg_dump "\$\{PG_DSN\}" 2> >\(sed .* >&2\) \| gzip > "\$pg_tmp"/ { saw_silent_stderr=1 }
      in_silent && /^}/ {
        if (!saw_silent_stderr) {
          printf "%s Sub2API silent backup must preserve pg_dump stderr while archiving only stdout\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_silent=0
      }
    ' impl/install_sub2api.sh
}

check_sub2api_summary_does_not_print_pg_password() {
  if grep -R -nE 'summary\.password.*\$\{?PG_PASS\}?' impl/install_sub2api.sh 2>/dev/null; then
    echo "Sub2API install summary must not print the generated PostgreSQL password." >&2
    return 1
  fi
  awk '
      /_print_install_summary\(\)/ { in_summary=1; saw_password_written=0; next }
      in_summary && /summary\.password_written "\$CONF_FILE"/ { saw_password_written=1 }
      in_summary && /^}/ {
        if (!saw_password_written) {
          printf "%s Sub2API install summary must tell users where the PostgreSQL password was written\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_summary=0
      }
    ' impl/install_sub2api.sh
}

check_sub2api_pg_password_is_escaped() {
  if grep -R -nF "WITH PASSWORD '\${PG_PASS}'" impl/install_sub2api.sh 2>/dev/null; then
    echo "Sub2API must not interpolate PG_PASS directly into SQL literals." >&2
    return 1
  fi
  if grep -R -nF 'postgresql://${PG_USER}:${PG_PASS}@' impl/install_sub2api.sh 2>/dev/null; then
    echo "Sub2API must URI-encode PG_PASS before building PG_DSN." >&2
    return 1
  fi
  awk '
      /_uri_encode\(\)/ { saw_encoder=1 }
      /psql -v pg_pass="\$PG_PASS" -c/ { saw_psql_var++ }
      /WITH PASSWORD :'\''pg_pass'\'';/ { saw_literal++ }
      index($0, "PG_DSN=\"postgresql://${PG_USER}:$(_uri_encode \"$PG_PASS\")@localhost:5432/${PG_DB}?sslmode=disable\"") { saw_dsn=1 }
      END {
        if (!(saw_encoder && saw_psql_var >= 2 && saw_literal >= 2 && saw_dsn)) {
          printf "%s Sub2API must escape PG_PASS for SQL and URI contexts\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_sub2api.sh
}

check_sub2api_nginx_reload_results_are_checked() {
  if grep -R -n 'nginx -t 2>/dev/null; then[[:space:]]*$' \
      impl/install_sub2api.sh 2>/dev/null | grep -v 'if nginx -t 2>/dev/null; then'; then
    echo "Sub2API nginx apply path must keep the nginx test as an explicit conditional." >&2
    return 1
  fi
  if grep -R -n '^[[:space:]]*systemctl reload nginx$' \
      impl/install_sub2api.sh 2>/dev/null; then
    echo "Sub2API nginx apply path must validate nginx reload results." >&2
    return 1
  fi
  awk '
      /if nginx -t 2>\/dev\/null; then/ { in_block=1; saw_reload_if=0; saw_domain_success=0; saw_fallback_success=0; saw_reload_warn=0; next }
      in_block && /if systemctl reload nginx; then/ { saw_reload_if=1 }
      in_block && /success "\$\(t app\.sub2api\.success\.nginx_domain "\$SUB2API_DOMAIN" "\$PORT"\)"/ { saw_domain_success=1 }
      in_block && /success "\$\(t app\.sub2api\.success\.nginx_fallback "\$PORT"\)"/ { saw_fallback_success=1 }
      in_block && /warn "\$\(t app\.sub2api\.warn\.nginx_reload_failed\)"/ { saw_reload_warn=1 }
      in_block && /warn "\$\(t app\.sub2api\.warn\.nginx_test_failed\)"/ {
        if (!(saw_reload_if && saw_domain_success && saw_fallback_success && saw_reload_warn)) {
          printf "%s Sub2API nginx apply path must branch on reload failure before reporting success\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_sub2api.sh
}

check_sub2api_postgres_rpm_setup_failures_are_explicit() {
  if grep -R -nE 'dnf install -y "\$pgdg_rpm" 2>/dev/null \|\| true|dnf -qy module disable postgresql 2>/dev/null \|\| true|yum install -y "\$pgdg_rpm" 2>/dev/null \|\| true|/usr/pgsql-15/bin/postgresql-15-setup initdb 2>/dev/null \|\| true' \
      impl/install_sub2api.sh 2>/dev/null; then
    echo "Sub2API PostgreSQL RPM setup must not suppress repository, module, or initdb failures." >&2
    return 1
  fi
  awk '
      /\[\[ "\$PKG_MANAGER" == "dnf" \|\| "\$PKG_MANAGER" == "yum" \]\]/ { in_block=1; saw_repo=0; saw_module=0; saw_initdb_guard=0; saw_initdb=0; next }
      in_block && /dnf install -y "\$pgdg_rpm" \|\| error "\$\(t app\.sub2api\.error\.postgres_repo\)"/ { saw_repo=1 }
      in_block && /dnf -qy module disable postgresql \|\| error "\$\(t app\.sub2api\.error\.postgres_module\)"/ { saw_module=1 }
      in_block && /yum install -y "\$pgdg_rpm" \|\| error "\$\(t app\.sub2api\.error\.postgres_repo\)"/ { saw_repo=1 }
      in_block && /if \[\[ ! -f "\$pg_data_version" \]\]; then/ { saw_initdb_guard=1 }
      in_block && /\/usr\/pgsql-15\/bin\/postgresql-15-setup initdb \|\| error "\$\(t app\.sub2api\.error\.postgres_initdb\)"/ { saw_initdb=1 }
      in_block && /success "\$\(t app\.sub2api\.success\.postgres15\)"/ {
        if (!(saw_repo && saw_initdb_guard && saw_initdb)) {
          printf "%s Sub2API PostgreSQL RPM setup must fail explicitly when repository install or initdb fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        if (!saw_module) {
          printf "%s Sub2API dnf path must fail explicitly when module disable fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_sub2api.sh
}

check_sub2api_dependency_services_start_before_success() {
  if grep -R -nE 'systemctl start postgresql 2>/dev/null \|\|[[:space:]\\]*systemctl start "postgresql-\$\{pg_ver\}" 2>/dev/null \|\||systemctl start postgresql 2>/dev/null \|\|[[:space:]\\]*systemctl start postgresql-15 2>/dev/null \|\|' \
      impl/install_sub2api.sh 2>/dev/null; then
    echo "Sub2API PostgreSQL startup fallbacks must use explicit conditionals." >&2
    return 1
  fi
  if grep -R -nE 'success "\$\(t app\.sub2api\.success\.(postgres_exists|redis_exists)[^"]*"\)[[:space:]]*$' \
      impl/install_sub2api.sh 2>/dev/null; then
    awk '
        /if \[\[ "\$pg_ver" -ge 15 \]\]; then/ { in_pg=1; saw_ensure=0; next }
        in_pg && /_ensure_postgres_running "\$pg_ver"/ { saw_ensure=1 }
        in_pg && /success "\$\(t app\.sub2api\.success\.postgres_exists "\$pg_ver"\)"/ {
          if (!saw_ensure) {
            printf "%s Sub2API must ensure PostgreSQL is running before reporting an existing installation as ready\n", FILENAME > "/dev/stderr"
            exit 1
          }
          in_pg=0
        }
        /if \[\[ "\$redis_ver" -ge 7 \]\]; then/ { in_redis=1; saw_redis_ensure=0; next }
      in_redis && /_ensure_redis_running \|\| error "\$\(t app\.sub2api\.error\.redis_start\)"/ { saw_redis_ensure=1 }
      in_redis && /success "\$\(t app\.sub2api\.success\.redis_exists "\$redis_ver"\)"/ {
        if (!saw_redis_ensure) {
            printf "%s Sub2API must ensure Redis is running before reporting an existing installation as ready\n", FILENAME > "/dev/stderr"
            exit 1
          }
          in_redis=0
        }
      ' impl/install_sub2api.sh
  fi
  awk '
      /_ensure_postgres_running\(\)/ { saw_pg_helper=1 }
      /if systemctl start postgresql 2>\/dev\/null; then/ { saw_pg_start_if=1 }
      /if systemctl start "postgresql-\$\{pg_ver\}" 2>\/dev\/null; then/ { saw_pg_version_start_if=1 }
      /_ensure_redis_running\(\)/ { saw_redis_helper=1 }
      /app\.sub2api\.error\.redis_start/ { saw_redis_error=1 }
      /if ! systemctl start postgresql 2>\/dev\/null/ { saw_pg_setup_if=1 }
      /! systemctl start postgresql-15 2>\/dev\/null; then/ { saw_pg_setup_fallback=1 }
      END {
        if (!(saw_pg_helper && saw_pg_start_if && saw_pg_version_start_if && saw_pg_setup_if && saw_pg_setup_fallback && saw_redis_helper && saw_redis_error)) {
          print "Sub2API must keep explicit helpers and error reporting for PostgreSQL and Redis service startup." > "/dev/stderr"
          exit 1
        }
      }
 ' impl/install_sub2api.sh apps/sub2api.sh 
}

check_sub2api_nginx_install_starts_service_explicitly() {
  if grep -R -nE 'systemctl start nginx 2>/dev/null \|\| true|systemctl start nginx 2>/dev/null \|\| error "\$\(t app\.sub2api\.error\.nginx_start\)"' \
      impl/install_sub2api.sh 2>/dev/null; then
    echo "Sub2API nginx installation must not suppress nginx start failures." >&2
    return 1
  fi
  awk '
      /app\.sub2api\.error\.nginx_install/ { saw_install_key=1 }
      /apt-get install -y nginx/ { saw_apt_guidance=1 }
      /dnf install -y nginx/ { saw_dnf_guidance=1 }
      /yum install -y nginx/ { saw_yum_guidance=1 }
      /_ensure_nginx_running\(\)/ { saw_helper=1 }
      /app\.sub2api\.error\.nginx_start/ { saw_error=1 }
      /if ! systemctl start nginx 2>\/dev\/null; then/ { saw_start_if=1 }
      /if ! systemctl is-active --quiet nginx 2>\/dev\/null; then/ { saw_active_if=1 }
      /_install_nginx\(\)/ { in_block=1; saw_ensure=0; saw_success=0; next }
      in_block && /if ! DEBIAN_FRONTEND=noninteractive apt-get install -y nginx; then/ { saw_apt_if=1 }
      in_block && /dnf install -y nginx \|\| error "\$\(t app\.sub2api\.error\.nginx_install\)"/ { saw_dnf_if=1 }
      in_block && /yum install -y nginx \|\| error "\$\(t app\.sub2api\.error\.nginx_install\)"/ { saw_yum_if=1 }
      in_block && /error "\$\(t app\.sub2api\.error\.nginx_install\)"/ { saw_install_error=1 }
      in_block && /_ensure_nginx_running/ { saw_ensure=1 }
      in_block && /success "\$\(t app\.sub2api\.success\.nginx_installed\)"/ { saw_success=1 }
      in_block && /^}/ {
        if (!(saw_install_key && saw_apt_guidance && saw_dnf_guidance && saw_yum_guidance && saw_helper && saw_error && saw_start_if && saw_active_if && saw_apt_if && saw_dnf_if && saw_yum_if && saw_install_error && saw_ensure && saw_success)) {
          printf "%s Sub2API nginx installation must fail explicitly on package install errors and ensure the service starts before reporting success\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
 ' impl/install_sub2api.sh apps/sub2api.sh 
}

check_sub2api_enable_failures_are_reported() {
  if grep -R -nE 'systemctl enable postgresql 2>/dev/null \|\| true|systemctl enable postgresql-15 2>/dev/null \|\| true|systemctl enable "postgresql-\$\{pg_ver\}" 2>/dev/null \|\| true' \
      impl/install_sub2api.sh 2>/dev/null; then
    echo "Sub2API service enable failures must not be silently ignored." >&2
    return 1
  fi
  awk '
      /app\.sub2api\.warn\.service_enable_failed/ { saw_warn_key=1 }
      /if ! systemctl enable postgresql 2>\/dev\/null &&/ { saw_existing_pg=1 }
      /warn "\$\(t app\.sub2api\.warn\.service_enable_failed "postgresql-\$\{pg_ver\}" "postgresql-\$\{pg_ver\}"\)"/ { saw_existing_pg_warn=1 }
      /if ! systemctl enable postgresql 2>\/dev\/null; then/ { saw_apt_pg=1 }
      /warn "\$\(t app\.sub2api\.warn\.service_enable_failed "postgresql" "postgresql"\)"/ { saw_apt_pg_warn=1 }
      /if ! systemctl enable postgresql-15 2>\/dev\/null; then/ { saw_rpm_pg=1 }
      /warn "\$\(t app\.sub2api\.warn\.service_enable_failed "postgresql-15" "postgresql-15"\)"/ { saw_rpm_pg_warn=1 }
      /if ! systemctl enable nginx; then/ { saw_nginx=1 }
      /warn "\$\(t app\.sub2api\.warn\.service_enable_failed "nginx" "nginx"\)"/ { saw_nginx_warn=1 }
      /if ! systemctl enable "\$SERVICE_NAME" --quiet; then/ { saw_service=1 }
      /warn "\$\(t app\.sub2api\.warn\.service_enable_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_service_warn=1 }
      END {
        if (!(saw_warn_key && saw_existing_pg && saw_existing_pg_warn && saw_apt_pg && saw_apt_pg_warn && saw_rpm_pg && saw_rpm_pg_warn && saw_nginx && saw_nginx_warn && saw_service && saw_service_warn)) {
          print "Sub2API must warn when service enablement fails for PostgreSQL, Nginx, or the app service." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/sub2api.sh impl/install_sub2api.sh
}

check_sub2api_service_start_paths_are_explicit() {
  if grep -R -nE '^[[:space:]]*systemctl (start|restart) "\$SERVICE_NAME"$' \
      impl/install_sub2api.sh 2>/dev/null; then
    echo "Sub2API service start/restart paths must branch explicitly on command failure." >&2
    return 1
  fi
  awk '
      /if ! systemctl enable "\$SERVICE_NAME" --quiet; then/ { in_install=1; saw_restart_wait=0; next }
      in_install && /if systemctl restart "\$SERVICE_NAME" && wait_for_service "\$SERVICE_NAME" 25; then/ { saw_restart_wait=1 }
      in_install && /if systemctl is-failed --quiet "\$SERVICE_NAME" 2>\/dev\/null; then/ {
        if (!saw_restart_wait) {
          printf "%s Sub2API install must gate service success on an explicit restart-and-wait branch\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_install=0
      }
      /if ! _install_binary_candidate "\$TMP_BIN"; then/ { in_update=1; saw_start_wait=0; next }
      in_update && /if systemctl start "\$SERVICE_NAME" && wait_for_service "\$SERVICE_NAME" 25; then/ { saw_start_wait=1 }
      in_update && /warn "\$\(t app\.sub2api\.warn\.new_version_failed "\$LATEST" "\$CURRENT"\)"/ {
        if (!saw_start_wait) {
          printf "%s Sub2API update must gate service success on an explicit start-and-wait branch\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_update=0
      }
    ' impl/install_sub2api.sh
}

check_sub2api_redis_service_handling_is_explicit() {
  if grep -R -n 'systemctl enable --now redis-server 2>/dev/null' \
      impl/install_sub2api.sh 2>/dev/null; then
    echo "Sub2API Redis helper must not conflate service startup with enablement." >&2
    return 1
  fi
  awk '
      /_ensure_redis_running\(\)/ { in_helper=1; saw_probe_loop=0; saw_start_loop=0; saw_enable_warn=0; next }
      in_helper && /for redis_unit in redis-server redis; do/ { saw_loop_count++; next }
      in_helper && /if systemctl is-active --quiet "\$redis_unit" 2>\/dev\/null; then/ { saw_probe_loop=1 }
      in_helper && /if systemctl start "\$redis_unit" 2>\/dev\/null; then/ { saw_start_loop=1 }
      in_helper && /warn "\$\(t app\.sub2api\.warn\.service_enable_failed "\$redis_unit" "\$redis_unit"\)"/ { saw_enable_warn=1 }
      in_helper && /^}/ {
        if (!(saw_loop_count >= 2 && saw_probe_loop && saw_start_loop && saw_enable_warn)) {
          printf "%s Sub2API Redis helper must probe units, start them explicitly, and warn on enable failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_helper=0
      }
    ' impl/install_sub2api.sh
}

check_sub2api_update_rollbacks_report_restart_failures() {
  if grep -R -n 'systemctl start "\$SERVICE_NAME" 2>/dev/null || true' \
      impl/install_sub2api.sh 2>/dev/null; then
    echo "Sub2API update rollback paths must not suppress service restart failures." >&2
    return 1
  fi
  awk '
      /if ! _install_binary_candidate "\$TMP_BIN"; then/ { in_install_failure=1; saw_restore=0; saw_start_if=0; saw_warn=0; next }
      in_install_failure && /if _restore_binary_backup "\$BAK_PATH"; then/ { saw_restore=1 }
      in_install_failure && /if ! systemctl start "\$SERVICE_NAME"; then/ { saw_start_if=1 }
      in_install_failure && /warn "\$\(t app\.sub2api\.warn\.rollback_start_failed "\$SERVICE_NAME"\)"/ { saw_warn=1 }
      in_install_failure && /error "\$\(t app\.sub2api\.error\.binary_install "\$BIN_PATH"\)"/ {
        if (!(saw_restore && saw_start_if && saw_warn)) {
          printf "%s Sub2API binary-install rollback must warn when service restart fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_install_failure=0
      }
      /warn "\$\(t app\.sub2api\.warn\.new_version_failed "\$LATEST" "\$CURRENT"\)"/ { in_update_failure=1; saw_restore2=0; saw_start_if2=0; saw_wait=0; saw_warn2=0; next }
      in_update_failure && /if ! _restore_binary_backup "\$BAK_PATH"; then/ { saw_restore2=1 }
      in_update_failure && /if systemctl start "\$SERVICE_NAME"; then/ { saw_start_if2=1 }
      in_update_failure && /if wait_for_service "\$SERVICE_NAME" 15; then/ { saw_wait=1 }
      in_update_failure && /warn "\$\(t app\.sub2api\.warn\.rollback_start_failed "\$SERVICE_NAME"\)"/ { saw_warn2=1 }
      in_update_failure && saw_start_if2 && /error "\$\(t app\.sub2api\.error\.update_failed "\$CURRENT" "\$SERVICE_NAME"\)"/ {
        if (!(saw_restore2 && saw_start_if2 && saw_wait && saw_warn2)) {
          printf "%s Sub2API update rollback must branch explicitly on restart failures before reporting rollback outcome\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_update_failure=0
      }
    ' impl/install_sub2api.sh
}

check_sub2api_install_cleanup_reports_systemctl_failures() {
  awk '
      /app\.sub2api\.warn\.cleanup_stop_failed/ { saw_stop_key=1 }
      /app\.sub2api\.warn\.cleanup_disable_failed/ { saw_disable_key=1 }
      /app\.sub2api\.warn\.cleanup_reload_failed/ { saw_reload_key=1 }
      END {
        if (!(saw_stop_key && saw_disable_key && saw_reload_key)) {
          print "Sub2API must provide localized install rollback cleanup warnings." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/sub2api.sh
  awk '
      /warn "\$\(t app\.sub2api\.warn\.service_failed_rollback\)"/ { in_cleanup=1; saw_stop=0; saw_disable=0; saw_reload=0; saw_suppressed=0; next }
      in_cleanup && /\|\| true/ { saw_suppressed=1 }
      in_cleanup && /warn "\$\(t app\.sub2api\.warn\.cleanup_stop_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_stop=1 }
      in_cleanup && /warn "\$\(t app\.sub2api\.warn\.cleanup_disable_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_disable=1 }
      in_cleanup && /warn "\$\(t app\.sub2api\.warn\.cleanup_reload_failed\)"/ { saw_reload=1 }
      in_cleanup && /error "\$\(t app\.sub2api\.error\.install_failed_rollback "\$SERVICE_NAME"\)"/ {
        if (!(saw_stop && saw_disable && saw_reload) || saw_suppressed) {
          printf "%s Sub2API install rollback cleanup must warn on stop, disable, and daemon-reload failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_cleanup=0
      }
    ' impl/install_sub2api.sh
}

check_sub2api_install_rollback_validates_binary_path_before_removal() {
  awk '
      /warn "\$\(t app\.sub2api\.warn\.service_failed_rollback\)"/ { in_cleanup=1; saw_restore=0; saw_guard=0; saw_remove=0; saw_raw_rm=0; next }
      in_cleanup && /_restore_binary_backup "\$OLD_BIN_BAK"/ { saw_restore=1 }
      in_cleanup && !saw_restore && /_sub2api_require_safe_bin_path/ { saw_guard=1 }
      in_cleanup && !saw_restore && /_sub2api_remove_file_or_error "\$BIN_PATH" "BIN_PATH"/ {
        if (!saw_guard) {
          printf "%s Sub2API install rollback must validate BIN_PATH before removing the failed binary\n", FILENAME > "/dev/stderr"
          exit 1
        }
        saw_remove=1
      }
      in_cleanup && !saw_restore && /rm -f "\$BIN_PATH"/ { saw_raw_rm=1 }
      in_cleanup && /error "\$\(t app\.sub2api\.error\.install_failed_rollback "\$SERVICE_NAME"\)"/ {
        if (!(saw_restore || (saw_guard && saw_remove)) || saw_raw_rm) {
          printf "%s Sub2API install rollback must either restore the backup or guard BIN_PATH and surface cleanup failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_cleanup=0
      }
    ' impl/install_sub2api.sh
}

check_sub2api_install_rollback_surfaces_service_file_removal_failures() {
  awk '
      /warn "\$\(t app\.sub2api\.warn\.service_failed_rollback\)"/ { in_cleanup=1; saw_remove=0; saw_raw_rm=0; next }
      in_cleanup && /_sub2api_remove_file_or_error "\/etc\/systemd\/system\/\$\{SERVICE_NAME\}\.service" "SUB2API_SERVICE_FILE"/ { saw_remove=1 }
      in_cleanup && /rm -f "\/etc\/systemd\/system\/\$\{SERVICE_NAME\}\.service"/ { saw_raw_rm=1 }
      in_cleanup && /if ! systemctl daemon-reload 2>\/dev\/null; then/ {
        if (!saw_remove || saw_raw_rm) {
          printf "%s Sub2API install rollback must surface service unit removal failures before daemon-reload\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
      in_cleanup && /error "\$\(t app\.sub2api\.error\.install_failed_rollback "\$SERVICE_NAME"\)"/ { in_cleanup=0 }
    ' impl/install_sub2api.sh
}

check_sub2api_update_stop_failure_aborts_before_replace() {
  awk '
      /app\.sub2api\.error\.stop_service_failed/ { saw_key=1 }
      /app\.sub2api\.warn\.tmp_binary_cleanup_failed/ { saw_warn_key=1 }
      END {
        if (!(saw_key && saw_warn_key)) {
          print "Sub2API must provide actionable update stop failure and cleanup warning messages." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/sub2api.sh
  awk '
      /info "\$\(t app\.sub2api\.info\.stopping_service\)"/ { in_stop=1; saw_if=0; saw_cleanup=0; saw_error=0; saw_suppressed=0; next }
      in_stop && /systemctl stop "\$SERVICE_NAME" 2>\/dev\/null \|\| true/ { saw_suppressed=1 }
      in_stop && /if ! systemctl stop "\$SERVICE_NAME" 2>\/dev\/null; then/ { saw_if=1 }
      in_stop && /if ! rm -f "\$TMP_BIN"; then/ { saw_cleanup=1 }
      in_stop && /warn "\$\(t app\.sub2api\.warn\.tmp_binary_cleanup_failed "\$TMP_BIN"\)"/ { saw_cleanup_warn=1 }
      in_stop && /error "\$\(t app\.sub2api\.error\.stop_service_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_error=1 }
      in_stop && /if ! _install_binary_candidate "\$TMP_BIN"; then/ {
        if (!(saw_if && saw_cleanup && saw_cleanup_warn && saw_error) || saw_suppressed) {
          printf "%s Sub2API update must abort and surface extracted binary cleanup failures when stopping the service fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_stop=0
      }
    ' impl/install_sub2api.sh
}

check_sub2api_update_rollback_stop_failure_aborts_restore() {
  awk '
      /app\.sub2api\.error\.rollback_stop_failed/ { saw_key=1 }
      END {
        if (!saw_key) {
          print "Sub2API must provide an actionable rollback stop failure error." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/sub2api.sh
  awk '
      /warn "\$\(t app\.sub2api\.warn\.new_version_failed "\$LATEST" "\$CURRENT"\)"/ { in_rollback=1; saw_if=0; saw_error=0; saw_suppressed=0; next }
      in_rollback && /systemctl stop "\$SERVICE_NAME" 2>\/dev\/null \|\| true/ { saw_suppressed=1 }
      in_rollback && /if ! systemctl stop "\$SERVICE_NAME" 2>\/dev\/null; then/ { saw_if=1 }
      in_rollback && /error "\$\(t app\.sub2api\.error\.rollback_stop_failed "\$SERVICE_NAME" "\$BAK_PATH" "\$SERVICE_NAME"\)"/ { saw_error=1 }
      in_rollback && /if ! _restore_binary_backup "\$BAK_PATH"; then/ {
        if (!(saw_if && saw_error) || saw_suppressed) {
          printf "%s Sub2API update rollback must abort before restoring files when stopping the failed new service fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_rollback=0
      }
    ' impl/install_sub2api.sh
}

check_sub2api_uninstall_stop_disable_failures_are_reported() {
  awk '
      /app\.sub2api\.error\.uninstall_stop_failed/ { saw_stop_error=1 }
      /app\.sub2api\.warn\.uninstall_stop_failed/ { saw_stop_warn=1 }
      /app\.sub2api\.warn\.uninstall_disable_failed/ { saw_disable_warn=1 }
      END {
        if (!(saw_stop_error && saw_stop_warn && saw_disable_warn)) {
          print "Sub2API must provide localized uninstall stop and disable failure messages." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/sub2api.sh
  awk '
      /info "\$\(t app\.sub2api\.info\.stop_disable "\$SERVICE_NAME"\)"/ { in_uninstall=1; saw_stop_if=0; saw_active_if=0; saw_stop_error=0; saw_stop_warn=0; saw_disable_if=0; saw_disable_warn=0; saw_suppressed=0; next }
      in_uninstall && /systemctl (stop|disable).* \|\| true/ { saw_suppressed=1 }
      in_uninstall && /if ! systemctl stop "\$SERVICE_NAME" 2>\/dev\/null; then/ { saw_stop_if=1 }
      in_uninstall && /if systemctl is-active --quiet "\$SERVICE_NAME" 2>\/dev\/null; then/ { saw_active_if=1 }
      in_uninstall && /error "\$\(t app\.sub2api\.error\.uninstall_stop_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_stop_error=1 }
      in_uninstall && /warn "\$\(t app\.sub2api\.warn\.uninstall_stop_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_stop_warn=1 }
      in_uninstall && /if ! systemctl disable "\$SERVICE_NAME" 2>\/dev\/null; then/ { saw_disable_if=1 }
      in_uninstall && /warn "\$\(t app\.sub2api\.warn\.uninstall_disable_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_disable_warn=1 }
      in_uninstall && /rm -f "\/etc\/systemd\/system\/\$\{SERVICE_NAME\}\.service"/ {
        if (!(saw_stop_if && saw_active_if && saw_stop_error && saw_stop_warn && saw_disable_if && saw_disable_warn) || saw_suppressed) {
          printf "%s Sub2API uninstall must abort when an active service cannot be stopped and warn on disable failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_uninstall=0
      }
    ' impl/install_sub2api.sh
}

check_sub2api_install_summary_matches_runtime_state() {
  awk '
      /app\.sub2api\.summary\.title_ready/ { saw_title_ready=1 }
      /app\.sub2api\.summary\.title_pending/ { saw_title_pending=1 }
      /app\.sub2api\.summary\.next2_ready/ { saw_next_ready=1 }
      /app\.sub2api\.summary\.next2_pending/ { saw_next_pending=1 }
      END {
        if (!(saw_title_ready && saw_title_pending && saw_next_ready && saw_next_pending)) {
          print "Sub2API install summary strings must distinguish ready and pending service states." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/sub2api.sh
  awk '
      /_health_check\(\)/ { in_health=1; saw_success=0; saw_return_ok=0; saw_warn=0; saw_return_fail=0; next }
      in_health && /success "\$\(t app\.sub2api\.success\.http_health "\$HTTP_CODE"\)"/ { saw_success=1 }
      in_health && /return 0/ { saw_return_ok=1 }
      in_health && /warn "\$\(t app\.sub2api\.warn\.http_health "\$HTTP_CODE"\)"/ { saw_warn=1 }
      in_health && /return 1/ { saw_return_fail=1 }
      in_health && /^}/ {
        if (!(saw_success && saw_return_ok && saw_warn && saw_return_fail)) {
          printf "%s Sub2API health helper must return explicit ready/pending status\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_health=0
      }
      /_print_install_summary\(\)/ { in_summary=1; saw_state=0; saw_pending=0; saw_ready=0; next }
      in_summary && /local summary_state="\$\{2:-ready\}"/ { saw_state=1 }
      in_summary && /summary_title="\$\(t app\.sub2api\.summary\.title_pending\)"/ { saw_pending=1 }
      in_summary && /summary_title="\$\(t app\.sub2api\.summary\.title_ready\)"/ { saw_ready=1 }
      in_summary && /^}/ {
        if (!(saw_state && saw_pending && saw_ready)) {
          printf "%s Sub2API install summary helper must branch on ready vs pending runtime state\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_summary=0
      }
      /step "\$\(t app\.sub2api\.step\.start_service\)"/ { in_install=1; saw_init=0; saw_pending_state=0; saw_summary_call=0; next }
      in_install && /local _install_summary_state="ready"/ { saw_init=1 }
      in_install && /_install_summary_state="pending"/ { saw_pending_state=1 }
      in_install && /_print_install_summary "\$LATEST" "\$_install_summary_state"/ {
        saw_summary_call=1
        if (!(saw_init && saw_pending_state)) {
          printf "%s Sub2API install path must downgrade the summary when the service did not become ready\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_install=0
      }
      END {
        if (!saw_summary_call) {
          print "Sub2API install path must pass runtime state into the install summary." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_sub2api.sh
}

check_sub2api_health_checks_are_nonfatal_outside_install() {
  awk '
      /if systemctl start "\$SERVICE_NAME" && wait_for_service "\$SERVICE_NAME" 25; then/ { in_update=1; saw_health_if=0; next }
      in_update && /if ! _health_check; then/ { saw_health_if=1 }
      in_update && /echo -e "  \$\{BOLD\}\$\{GREEN\}\$\(t app\.sub2api\.success\.update_done/ {
        if (!saw_health_if) {
          printf "%s Sub2API update must treat post-restart health warnings as nonfatal\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_update=0
      }
    ' impl/install_sub2api.sh
}

check_sub2api_uri_encode_ascii() {
  # _uri_encode must percent-encode non-ASCII as UTF-8 bytes and leave the
  # PostgreSQL DSN unreserved characters alone, on every locale. Case-pattern
  # classes and printf %02X are collation-dependent, so _uri_encode pins
  # LC_ALL=C internally; run the behavior under C and under each UTF-8
  # collation locale available on the host.
  local locale
  for locale in C en_US.UTF-8 zh_CN.UTF-8; do
    if [[ "$locale" == "C" ]] || LC_ALL="$locale" "$BASH_BIN" -c '[[ "é" =~ ^[A-Za-z]+$ ]]'; then
      LC_ALL="$locale" "$BASH_BIN" -c '
        set -euo pipefail
        source "$1/lib/core.sh"
        source "$1/apps/sub2api.sh"
        [[ "$(_uri_encode "päss wörld")" == "p%C3%A4ss%20w%C3%B6rld" ]] \
          || { echo "uri_encode mis-encoded non-ASCII under LC_ALL=${LC_ALL:-unset}: [$(_uri_encode "päss wörld")]" >&2; exit 1; }
        [[ "$(_uri_encode "abc-._~")" == "abc-._~" ]] \
          || { echo "uri_encode altered ASCII-safe characters" >&2; exit 1; }
        exit 0
      ' _ "$ROOT_DIR"
    fi
  done
}

check_sub2api_component_version_manifest() {
  local output
  output="$($BASH_BIN <<'SUB2APITEST'
set -euo pipefail
source lib/core.sh
export DEPLOY_IMPL_SOURCE_ONLY=1
source impl/install_sub2api.sh >/dev/null 2>&1
INSTALLED_POSTGRES_VERSION=15.4
INSTALLED_REDIS_VERSION=7.2.5
payload='{"installed":"v1.0.0","latest":"v1.1.0","checked_at":"2026-01-01T00:00:00Z","update_state":"update_available","source":"github_release","cache_state":"fresh","error":null}'
manifest="$(_sub2api_component_manifest_json "$payload")"
result="$(version_check_attach_components_json "$payload" "$manifest")"
python -c 'import json,sys; x=json.loads(sys.argv[1]); assert x["components"]["sub2api"]["repository"] == "Wei-Shaw/sub2api"; assert x["components"]["postgresql"]["installed"] == "15.4"; assert x["components"]["postgresql"]["update_state"] == "not_checked"; assert x["components"]["redis"]["installed"] == "7.2.5"; assert x["latest"] == "v1.1.0"' "$result"
printf ok
SUB2APITEST
  )"
  [[ "$output" == ok ]]
  grep -Fq 'INSTALLED_POSTGRES_VERSION INSTALLED_REDIS_VERSION' impl/install_sub2api.sh
  grep -Fq '_sub2api_record_runtime_versions' impl/install_sub2api.sh
}
