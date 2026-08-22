# shellcheck shell=bash
# shellcheck source=../verify.sh
# Verify checks for the cyberstrikeai app (apps/cyberstrikeai.sh).

check_cyberstrikeai_status_backup_projection() {
  local output
  output="$($BASH_BIN -c '
    set -euo pipefail
    tmp_dir="$(mktemp -d)"
    backup_dir="$tmp_dir/cyber backups"
    mkdir -p "$backup_dir"
    touch -d "2026-08-20 12:34:56 UTC" "$backup_dir/cyberstrike-ai_20260820123456.tar.gz"
    source lib/core.sh
    APP_ID=cyberstrikeai
    APP_NAME="CyberStrikeAI"
    BACKUP_DIR="$backup_dir"
    app_conf_file() { printf "%s" "$tmp_dir/missing.conf"; }
    source impl/install_cyberstrikeai.sh
    _csai_status_backup
    rm -rf "$tmp_dir"
  ')"
  python -c 'import json,sys; x=json.loads(sys.argv[1]); assert x["state"] == "available"; assert "cyber backups" in x["path"]; assert x["path"].endswith("cyberstrike-ai_20260820123456.tar.gz"); assert x["last_success_at"]' "$output"
  grep -Fq 'APP_STATUS_BACKUP_FN=_csai_status_backup' impl/install_cyberstrikeai.sh \
    && grep -Fq 'APP_STATUS_BACKUP_FN=_csai_status_backup' dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_uninstall_supports_noninteractive_mode() {
  awk '
      /prompt "\$\(t app\.cyberstrikeai\.prompt\.continue\)"/ { saw_continue_prompt=1 }
      /if deploy_assume_yes; then/ && !saw_continue { saw_continue=1; next }
      saw_continue && /confirm="YES"/ { saw_yes=1 }
      /if deploy_env_truthy DEPLOY_DELETE_INSTALL; then/ { saw_install_env=1 }
      /del_install="yes"/ { saw_install_yes=1 }
      /del_install="no"/ { saw_install_no=1 }
      /prompt "\$\(t app\.cyberstrikeai\.prompt\.delete_install "\$INSTALL_DIR"\)"/ { saw_install_prompt=1 }
      /if deploy_env_truthy DEPLOY_DELETE_BACKUP; then/ { saw_backup_env=1 }
      /del_backup="yes"/ { saw_backup_yes=1 }
      /del_backup="no"/ { saw_backup_no=1 }
      /prompt "\$\(t app\.cyberstrikeai\.prompt\.delete_backup "\$BACKUP_DIR"\)"/ { saw_backup_prompt=1 }
      END {
        if (!(saw_continue_prompt && saw_continue && saw_yes && saw_install_env && saw_install_yes && saw_install_no && saw_install_prompt && saw_backup_env && saw_backup_yes && saw_backup_no && saw_backup_prompt)) {
          printf "%s CyberStrikeAI uninstall must support DEPLOY_ASSUME_YES while requiring explicit env flags for install and backup deletion\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_uninstall_checks_directory_removal_errors() {
  grep -Fq '_csai_remove_dir_or_error() {' impl/install_cyberstrikeai.sh \
    && grep -Fq 'error "$(t app.cyberstrikeai.error.remove_dir "$path")"' impl/install_cyberstrikeai.sh \
    && grep -Fq '_csai_remove_dir_or_error "$INSTALL_DIR" "INSTALL_DIR" "$(t app.cyberstrikeai.success.deleted_install "$INSTALL_DIR")"' impl/install_cyberstrikeai.sh \
    && grep -Fq '_csai_remove_dir_or_error "$BACKUP_DIR" "BACKUP_DIR" "$(t app.cyberstrikeai.success.deleted_backup "$BACKUP_DIR")"' impl/install_cyberstrikeai.sh \
    && grep -Fq 'app.cyberstrikeai.error.remove_dir' apps/cyberstrikeai.sh \
    || {
      echo "CyberStrikeAI uninstall must surface directory removal failures instead of reporting unconditional success." >&2
      return 1
    }
  grep -Fq '_csai_remove_dir_or_error() {' dist/install_cyberstrikeai.sh \
    && grep -Fq 'error "$(t app.cyberstrikeai.error.remove_dir "$path")"' dist/install_cyberstrikeai.sh \
    && grep -Fq '_csai_remove_dir_or_error "$INSTALL_DIR" "INSTALL_DIR" "$(t app.cyberstrikeai.success.deleted_install "$INSTALL_DIR")"' dist/install_cyberstrikeai.sh \
    && grep -Fq '_csai_remove_dir_or_error "$BACKUP_DIR" "BACKUP_DIR" "$(t app.cyberstrikeai.success.deleted_backup "$BACKUP_DIR")"' dist/install_cyberstrikeai.sh \
    || {
      echo "Release CyberStrikeAI script must preserve uninstall directory removal failure handling." >&2
      return 1
    }
}

check_cyberstrikeai_uninstall_checks_file_removal_errors() {
  grep -Fq '_csai_remove_file_or_error() {' impl/install_cyberstrikeai.sh \
    && grep -Fq 'error "$(t app.cyberstrikeai.error.remove_file "$path")"' impl/install_cyberstrikeai.sh \
    && grep -Fq '_csai_remove_file_or_error "/etc/systemd/system/${SERVICE_NAME}.service" "CSAI_SERVICE_FILE"' impl/install_cyberstrikeai.sh \
    && grep -Fq '_csai_remove_file_or_error "$NGINX_LINK" "NGINX_LINK"' impl/install_cyberstrikeai.sh \
    && grep -Fq '_csai_remove_file_or_error "$NGINX_CONF" "NGINX_CONF"' impl/install_cyberstrikeai.sh \
    && grep -Fq '_csai_remove_file_or_error "$LOGROTATE_FILE" "LOGROTATE_FILE"' impl/install_cyberstrikeai.sh \
    && grep -Fq '_csai_remove_file_or_error "$CRON_FILE" "CRON_FILE"' impl/install_cyberstrikeai.sh \
    && grep -Fq '_csai_remove_file_or_error "$BACKUP_SCRIPT" "BACKUP_SCRIPT"' impl/install_cyberstrikeai.sh \
    && grep -Fq '_csai_remove_file_or_error "$CONF_FILE" "CONF_FILE"' impl/install_cyberstrikeai.sh \
    && grep -Fq 'app.cyberstrikeai.error.remove_file' apps/cyberstrikeai.sh \
    || {
      echo "CyberStrikeAI uninstall must surface file removal failures instead of reporting unconditional success." >&2
      return 1
    }
  grep -Fq '_csai_remove_file_or_error() {' dist/install_cyberstrikeai.sh \
    && grep -Fq 'error "$(t app.cyberstrikeai.error.remove_file "$path")"' dist/install_cyberstrikeai.sh \
    && grep -Fq '_csai_remove_file_or_error "/etc/systemd/system/${SERVICE_NAME}.service" "CSAI_SERVICE_FILE"' dist/install_cyberstrikeai.sh \
    && grep -Fq '_csai_remove_file_or_error "$NGINX_LINK" "NGINX_LINK"' dist/install_cyberstrikeai.sh \
    && grep -Fq '_csai_remove_file_or_error "$NGINX_CONF" "NGINX_CONF"' dist/install_cyberstrikeai.sh \
    && grep -Fq '_csai_remove_file_or_error "$LOGROTATE_FILE" "LOGROTATE_FILE"' dist/install_cyberstrikeai.sh \
    && grep -Fq '_csai_remove_file_or_error "$CRON_FILE" "CRON_FILE"' dist/install_cyberstrikeai.sh \
    && grep -Fq '_csai_remove_file_or_error "$BACKUP_SCRIPT" "BACKUP_SCRIPT"' dist/install_cyberstrikeai.sh \
    && grep -Fq '_csai_remove_file_or_error "$CONF_FILE" "CONF_FILE"' dist/install_cyberstrikeai.sh \
    || {
      echo "Release CyberStrikeAI script must preserve uninstall file removal failure handling." >&2
      return 1
    }
}

check_cyberstrikeai_backup_lists_preserve_paths_with_spaces() {
  if grep -R -n -- "-printf '%T@ %p\\\\n'" impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "CyberStrikeAI backup lists must not split paths on spaces." >&2
    return 1
  fi
  if grep -R -nF 'find "\$INSTALL_DIR/data" -maxdepth 1 -name "*.db" -type f 2>/dev/null | while read -r db; do' \
      impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "CyberStrikeAI generated backup script must not split database paths on spaces." >&2
    return 1
  fi
  awk '
      /find "\\\$INSTALL_DIR\/data" -maxdepth 1 -name "\*\.db" -type f -print0/ { saw_db_print0=1 }
      /while IFS= read -r -d '\'''\'' db; do/ { saw_db_read0=1 }
      /app\.cyberstrikeai\.info\.latest_backups/ { in_backup=1 }
      in_backup && /file="\$\{_backup_entry#\* \}"/ { saw_backup_strip=1 }
      in_backup && /-printf '\''%T@ %p\\0'\''/ { saw_backup_print0=1 }
      in_backup && /sort -z -rn \| head -z -n 10/ { saw_backup_sort=1; in_backup=0 }
      /app\.cyberstrikeai\.step\.backups/ { in_status=1 }
      in_status && /file="\$\{_backup_entry#\* \}"/ { saw_status_strip=1 }
      in_status && /-printf '\''%T@ %p\\0'\''/ { saw_status_print0=1 }
      in_status && /sort -z -rn \| head -z -n 5/ { saw_status_sort=1; in_status=0 }
      END {
        if (!(saw_db_print0 && saw_db_read0 && saw_backup_strip && saw_backup_print0 && saw_backup_sort && saw_status_strip && saw_status_print0 && saw_status_sort)) {
          printf "%s CyberStrikeAI backup lists must use NUL-delimited reads and sorting without splitting paths on spaces\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_display_sizes_are_nonfatal() {
  awk '
      /do_backup\(\)/ { in_backup=1; next }
      in_backup && /^}/ {
        if (!(saw_backup_file_size && saw_backup_loop)) {
          printf "%s CyberStrikeAI backup listing must tolerate disappearing backup files\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_backup=0
      }
      in_backup && /du -sh "\$file" 2>\/dev\/null \| awk '\''\{print \$1\}'\'' \|\| t status\.unknown/ { saw_backup_file_size=1 }
      in_backup && /head -z -n 10\) \|\| true/ { saw_backup_loop=1 }
      /do_status\(\)/ { in_status=1; next }
      in_status && /^}/ {
        if (!(saw_binary_size && saw_backup_dir_size && saw_status_file_size && saw_status_loop)) {
          printf "%s CyberStrikeAI status display sizes must fall back instead of failing under pipefail\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_status=0
      }
      in_status && /du -sh "\$BIN_PATH" 2>\/dev\/null \| awk '\''\{print \$1\}'\'' \|\| t status\.unknown/ { saw_binary_size=1 }
      in_status && /size=\$\(du -sh "\$BACKUP_DIR" 2>\/dev\/null \| awk '\''\{print \$1\}'\'' \|\| t status\.unknown\)/ { saw_backup_dir_size=1 }
      in_status && /du -sh "\$file" 2>\/dev\/null \| awk '\''\{print \$1\}'\'' \|\| t status\.unknown/ { saw_status_file_size=1 }
      in_status && /head -z -n 5\) \|\| true/ { saw_status_loop=1 }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_ports_are_validated() {
  awk '
      /preflight_check\(\)/ { in_preflight=1; next }
      in_preflight && /^}/ {
        if (!saw_preflight) {
          printf "%s CyberStrikeAI preflight must validate PORT and PUBLIC_PORT defaults\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_preflight=0
      }
      in_preflight && /_validate_config_values/ { saw_preflight=1 }
      /_validate_config_values\(\)/ { in_validate=1; next }
      in_validate && /app_validate_port "\$PORT"/ { saw_port=1 }
      in_validate && /app_validate_port "\$PUBLIC_PORT"/ { saw_public_port=1 }
      in_validate && /^}/ { in_validate=0 }
      END {
        if (!(saw_preflight && saw_port && saw_public_port)) {
          printf "%s CyberStrikeAI must validate PORT and PUBLIC_PORT via _validate_config_values\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_booleans_are_validated() {
  awk '
      /preflight_check\(\)/ { in_preflight=1; next }
      in_preflight && /^}/ {
        if (!saw_preflight) {
          printf "%s CyberStrikeAI preflight must validate boolean config defaults\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_preflight=0
      }
      in_preflight && /_validate_config_values/ { saw_preflight=1 }
      /_validate_config_values\(\)/ { in_validate=1; next }
      in_validate && /app_validate_bool/ { saw_bool=1 }
      in_validate && /^}/ { in_validate=0 }
      END {
        if (!(saw_preflight && saw_bool)) {
          printf "%s CyberStrikeAI must validate ENABLE_NGINX, CSAI_HTTPS, and OPEN_FIREWALL before using them\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_go_version_parse_failures_are_explicit() {
  awk '
      /version=\$\(printf .*\| grep -oE .*go\[0-9\].*\| head -1 \| sed .* \|\| true\)/ { saw_safe_parse=1 }
      /\[\[ -n "\$version" \]\] \|\| error "\$\(t app\.cyberstrikeai\.error\.go_parse\)"/ { saw_parse_error=1 }
      END {
        if (!(saw_safe_parse && saw_parse_error)) {
          printf "%s CyberStrikeAI Go version parsing must allow empty parse results to reach the explicit go_parse error under pipefail\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_go_restore_failures_are_reported() {
  if grep -R -n 'warn "\$\(t app\.cyberstrikeai\.error\.go_failed\)"' \
      impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "CyberStrikeAI Go restore failures must not reuse the generic install failure message as a warning." >&2
    return 1
  fi
  awk '
      /app\.cyberstrikeai\.warn\.go_restore_failed/ { saw_warn_key=1 }
      /if ! mv "\$extract_dir\/go" \/usr\/local\/go; then/ { in_block=1; saw_restore_if=0; saw_warn=0; next }
      in_block && /if ! restore_old_go_toolchain "\$old_go_backup"; then/ { saw_restore_if=1 }
      in_block && /warn "\$\(t app\.cyberstrikeai\.warn\.go_restore_failed\)"/ { saw_warn=1 }
      in_block && /error "\$\(t app\.cyberstrikeai\.error\.go_failed\)"/ {
        if (!(saw_warn_key && saw_restore_if && saw_warn)) {
          printf "%s CyberStrikeAI must warn explicitly when restoring the previous Go toolchain fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' apps/cyberstrikeai.sh impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_pip_upgrade_failures_are_reported() {
  if grep -R -n 'python -m pip install --index-url "\$PIP_INDEX_URL" --upgrade pip >/dev/null 2>&1 || true' \
      impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "CyberStrikeAI pip upgrade failures must not be silently ignored." >&2
    return 1
  fi
  awk '
      /app\.cyberstrikeai\.warn\.pip_upgrade/ { saw_warn_key=1 }
      /step "\$\(t app\.cyberstrikeai\.step\.python_env\)"/ { in_block=1; saw_pip_if=0; saw_warn=0; next }
      in_block && /if ! python -m pip install --index-url "\$PIP_INDEX_URL" --upgrade pip >\/dev\/null 2>&1; then/ { saw_pip_if=1 }
      in_block && /warn "\$\(t app\.cyberstrikeai\.warn\.pip_upgrade\)"/ { saw_warn=1 }
      in_block && /if \[\[ -f requirements\.txt \]\]; then/ {
        if (!(saw_warn_key && saw_pip_if && saw_warn)) {
          printf "%s CyberStrikeAI must warn explicitly when virtualenv pip upgrade fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' apps/cyberstrikeai.sh impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_python_env_failures_are_reported() {
  awk '
      /app\.cyberstrikeai\.error\.python_venv/ { saw_venv_key=1 }
      /python3-venv/ { saw_venv_guidance=1 }
      /app\.cyberstrikeai\.error\.python_activate/ { saw_activate_key=1 }
      /Recreate it and retry/ { saw_activate_guidance=1 }
      END {
        if (!(saw_venv_key && saw_venv_guidance && saw_activate_key && saw_activate_guidance)) {
          print "CyberStrikeAI Python environment failures must provide actionable setup guidance." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/cyberstrikeai.sh
  awk '
      /step "\$\(t app\.cyberstrikeai\.step\.python_env\)"/ { in_block=1; saw_venv_if=0; saw_venv_error=0; saw_activate_if=0; saw_activate_error=0; next }
      in_block && /if ! python3 -m venv "\$VENV_DIR"; then/ { saw_venv_if=1 }
      in_block && /error "\$\(t app\.cyberstrikeai\.error\.python_venv "\$VENV_DIR"\)"/ { saw_venv_error=1 }
      in_block && /if ! source "\$VENV_DIR\/bin\/activate"; then/ { saw_activate_if=1 }
      in_block && /error "\$\(t app\.cyberstrikeai\.error\.python_activate "\$VENV_DIR"\)"/ { saw_activate_error=1 }
      in_block && /if ! python -m pip install --index-url "\$PIP_INDEX_URL" --upgrade pip >\/dev\/null 2>&1; then/ {
        if (!(saw_venv_if && saw_venv_error && saw_activate_if && saw_activate_error)) {
          printf "%s CyberStrikeAI Python environment setup must fail explicitly when venv creation or activation fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_repo_go_install_failures_are_reported() {
  if grep -R -n 'apt-get install -y -qq golang-go || true' \
      impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "CyberStrikeAI repository Go installation failures must not be silently ignored." >&2
    return 1
  fi
  awk '
      /app\.cyberstrikeai\.warn\.go_repo_install_failed/ { saw_warn_key=1 }
      /step "\$\(t app\.cyberstrikeai\.step\.install_go\)"/ { in_block=1; saw_install_if=0; saw_warn=0; next }
      in_block && /if ! apt-get install -y -qq golang-go; then/ { saw_install_if=1 }
      in_block && /warn "\$\(t app\.cyberstrikeai\.warn\.go_repo_install_failed\)"/ { saw_warn=1 }
      in_block && /if command -v go >\/dev\/null 2>&1; then/ {
        if (!(saw_warn_key && saw_install_if && saw_warn)) {
          printf "%s CyberStrikeAI must warn when apt-based Go installation fails before falling back to the official toolchain\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' apps/cyberstrikeai.sh impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_dependency_failures_are_reported() {
  if grep -R -nE '^[[:space:]]*apt-get update -qq$' \
      impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "CyberStrikeAI dependency installation must use an explicit conditional for apt-get update." >&2
    return 1
  fi
  if grep -R -nE '^[[:space:]]*apt-get install -y -qq nginx$' \
      impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "CyberStrikeAI nginx installation must use an explicit conditional with an actionable error." >&2
    return 1
  fi
  awk '
      /app\.cyberstrikeai\.error\.apt_update/ { saw_update_key=1 }
      /\/var\/log\/apt\/\*/ { saw_update_guidance=1 }
      /app\.cyberstrikeai\.error\.deps_install/ { saw_install_key=1 }
      /apt-get install -y ca-certificates curl git build-essential python3 python3-venv python3-pip sqlite3 tar gzip openssl lsof/ { saw_install_guidance=1 }
      /app\.cyberstrikeai\.error\.nginx_deps_install/ { saw_nginx_key=1 }
      /apt-get install -y nginx/ { saw_nginx_guidance=1 }
      END {
        if (!(saw_update_key && saw_update_guidance && saw_install_key && saw_install_guidance && saw_nginx_key && saw_nginx_guidance)) {
          print "CyberStrikeAI dependency failures must tell users how to inspect apt logs and retry package installation." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/cyberstrikeai.sh
  awk '
      /step "\$\(t app\.cyberstrikeai\.step\.install_deps\)"/ { in_block=1; saw_update_if=0; saw_update_error=0; saw_install_if=0; saw_install_error=0; saw_nginx_if=0; saw_nginx_error=0; next }
      in_block && /if ! apt-get update -qq; then/ { saw_update_if=1 }
      in_block && /error "\$\(t app\.cyberstrikeai\.error\.apt_update\)"/ { saw_update_error=1 }
      in_block && /if ! apt-get install -y -qq \\/ { saw_install_if=1 }
      in_block && /error "\$\(t app\.cyberstrikeai\.error\.deps_install\)"/ { saw_install_error=1 }
      in_block && /if ! apt-get install -y -qq nginx; then/ { saw_nginx_if=1 }
      in_block && /error "\$\(t app\.cyberstrikeai\.error\.nginx_deps_install\)"/ { saw_nginx_error=1 }
      in_block && /success "\$\(t app\.cyberstrikeai\.success\.deps\)"/ {
        if (!(saw_update_if && saw_update_error && saw_install_if && saw_install_error && saw_nginx_if && saw_nginx_error)) {
          printf "%s CyberStrikeAI dependency installation must fail through explicit conditionals with actionable errors\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_runtime_dir_failures_are_explicit() {
  awk '
      /app\.cyberstrikeai\.error\.runtime_dirs/ { saw_error_key=1 }
      /Check permissions for %s and %s, then retry/ { saw_guidance=1 }
      END {
        if (!(saw_error_key && saw_guidance)) {
          print "CyberStrikeAI runtime directory failures must explain which paths to inspect." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/cyberstrikeai.sh
  awk '
      /install_runtime_dirs\(\)/ { in_func=1; saw_mkdir_if=0; saw_install_guard=0; saw_backup_guard=0; saw_chown_if=0; saw_mode_if=0; saw_child_mode_if=0; saw_error=0; next }
      in_func && /if ! mkdir -p "\$LOG_DIR" "\$INSTALL_DIR\/data" "\$INSTALL_DIR\/tmp" "\$BACKUP_DIR"; then/ { saw_mkdir_if=1 }
      in_func && /require_safe_path "INSTALL_DIR" "\$INSTALL_DIR"/ { saw_install_guard=1 }
      in_func && /require_safe_path "BACKUP_DIR" "\$BACKUP_DIR"/ { saw_backup_guard=1 }
      in_func && /if ! chown -R "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$INSTALL_DIR" "\$BACKUP_DIR"; then/ { saw_chown_if=1 }
      in_func && /if ! chmod 750 "\$INSTALL_DIR" "\$BACKUP_DIR"; then/ { saw_mode_if=1 }
      in_func && /if ! chmod 750 "\$LOG_DIR" "\$INSTALL_DIR\/data" "\$INSTALL_DIR\/tmp"; then/ { saw_child_mode_if=1 }
      in_func && /error "\$\(t app\.cyberstrikeai\.error\.runtime_dirs "\$INSTALL_DIR" "\$BACKUP_DIR"\)"/ { saw_error=1 }
      in_func && /success "\$\(t app\.cyberstrikeai\.success\.runtime_dirs\)"/ {
        if (!(saw_mkdir_if && saw_install_guard && saw_backup_guard && saw_chown_if && saw_mode_if && saw_child_mode_if && saw_error)) {
          printf "%s CyberStrikeAI runtime directory setup must fail explicitly on mkdir, chown, and chmod errors\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_source_and_build_prep_failures_are_explicit() {
  awk '
      /app\.cyberstrikeai\.error\.user_create/ { saw_user_key=1 }
      /app\.cyberstrikeai\.error\.source_parent_dir/ { saw_parent_key=1 }
      /app\.cyberstrikeai\.error\.repo_fetch/ { saw_fetch_key=1 }
      /git -C %s fetch --prune origin %s/ { saw_fetch_guidance=1 }
      /app\.cyberstrikeai\.error\.repo_checkout/ { saw_checkout_key=1 }
      /git -C %s checkout %s/ { saw_checkout_guidance=1 }
      /app\.cyberstrikeai\.error\.repo_pull/ { saw_pull_key=1 }
      /git -C %s pull --ff-only origin %s/ { saw_pull_guidance=1 }
      /app\.cyberstrikeai\.error\.repo_clone/ { saw_clone_key=1 }
      /git clone --depth 1 --branch %s https:\/\/github.com\/%s\.git %s/ { saw_clone_guidance=1 }
      /app\.cyberstrikeai\.error\.install_dir_missing/ { saw_dir_key=1 }
      /app\.cyberstrikeai\.error\.go_modules/ { saw_mod_key=1 }
      /go mod download/ { saw_mod_guidance=1 }
      /app\.cyberstrikeai\.error\.nginx_dirs/ { saw_nginx_key=1 }
      /app\.cyberstrikeai\.error\.install_dir_owner/ { saw_owner_key=1 }
      END {
        if (!(saw_user_key && saw_parent_key && saw_fetch_key && saw_fetch_guidance && saw_checkout_key && saw_checkout_guidance && saw_pull_key && saw_pull_guidance && saw_clone_key && saw_clone_guidance && saw_dir_key && saw_mod_key && saw_mod_guidance && saw_nginx_key && saw_owner_key)) {
          print "CyberStrikeAI source and build-prep failures must provide actionable recovery guidance." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/cyberstrikeai.sh
  awk '
      /ensure_service_user\(\)/ { in_user=1; saw_user_if=0; saw_user_error=0; next }
      in_user && /if ! useradd --system --home "\$INSTALL_DIR" --shell \/usr\/sbin\/nologin "\$SERVICE_USER"; then/ { saw_user_if=1 }
      in_user && /error "\$\(t app\.cyberstrikeai\.error\.user_create "\$SERVICE_USER"\)"/ { saw_user_error=1 }
      in_user && /success "\$\(t app\.cyberstrikeai\.success\.user_created "\$SERVICE_USER"\)"/ {
        if (!(saw_user_if && saw_user_error)) {
          printf "%s CyberStrikeAI service-user setup must fail explicitly when useradd fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_user=0
      }
      /sync_repo_branch\(\)/ { in_sync=1; saw_fetch_if=0; saw_fetch_error=0; saw_checkout_if=0; saw_checkout_error=0; saw_pull_if=0; saw_pull_error=0; next }
      in_sync && /if ! git -C "\$INSTALL_DIR" fetch --prune origin "\$GITHUB_BRANCH"; then/ { saw_fetch_if=1 }
      in_sync && /error "\$\(t app\.cyberstrikeai\.error\.repo_fetch "\$GITHUB_BRANCH" "\$INSTALL_DIR" "\$INSTALL_DIR" "\$GITHUB_BRANCH"\)"/ { saw_fetch_error=1 }
      in_sync && /if ! git -C "\$INSTALL_DIR" checkout -q "\$GITHUB_BRANCH"; then/ { saw_checkout_if=1 }
      in_sync && /error "\$\(t app\.cyberstrikeai\.error\.repo_checkout "\$INSTALL_DIR" "\$GITHUB_BRANCH" "\$INSTALL_DIR" "\$GITHUB_BRANCH"\)"/ { saw_checkout_error=1 }
      in_sync && /if ! git -C "\$INSTALL_DIR" pull --ff-only origin "\$GITHUB_BRANCH"; then/ { saw_pull_if=1 }
      in_sync && /error "\$\(t app\.cyberstrikeai\.error\.repo_pull "\$INSTALL_DIR" "\$GITHUB_BRANCH" "\$INSTALL_DIR" "\$GITHUB_BRANCH"\)"/ { saw_pull_error=1 }
      in_sync && /^}/ {
        if (!(saw_fetch_if && saw_fetch_error && saw_checkout_if && saw_checkout_error && saw_pull_if && saw_pull_error)) {
          printf "%s CyberStrikeAI git fetch, checkout, and pull steps must fail through explicit conditionals with actionable errors\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_sync=0
      }
      /clone_or_update_repo\(\)/ { in_clone=1; saw_parent_if=0; saw_parent_error=0; saw_sync_call=0; saw_clone_if=0; saw_clone_error=0; next }
      in_clone && /if ! mkdir -p "\$\(dirname "\$INSTALL_DIR"\)"; then/ { saw_parent_if=1 }
      in_clone && /error "\$\(t app\.cyberstrikeai\.error\.source_parent_dir "\$INSTALL_DIR"\)"/ { saw_parent_error=1 }
      in_clone && /sync_repo_branch/ { saw_sync_call=1 }
      in_clone && /if ! git clone --depth 1 --branch "\$GITHUB_BRANCH" "https:\/\/github.com\/\$\{GITHUB_REPO\}\.git" "\$INSTALL_DIR"; then/ { saw_clone_if=1 }
      in_clone && /error "\$\(t app\.cyberstrikeai\.error\.repo_clone "\$GITHUB_REPO" "\$INSTALL_DIR" "\$GITHUB_BRANCH" "\$GITHUB_REPO" "\$INSTALL_DIR"\)"/ { saw_clone_error=1 }
      in_clone && /success "\$\(t app\.cyberstrikeai\.success\.source_ready "\$INSTALL_DIR"\)"/ {
        if (!(saw_parent_if && saw_parent_error && saw_sync_call && saw_clone_if && saw_clone_error)) {
          printf "%s CyberStrikeAI source checkout must fail explicitly when preparing directories or cloning the repository\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_clone=0
      }
      /setup_python_env\(\)/ { in_python=1; saw_python_cd_if=0; saw_python_cd_error=0; next }
      in_python && /if ! cd "\$INSTALL_DIR"; then/ { saw_python_cd_if=1 }
      in_python && /error "\$\(t app\.cyberstrikeai\.error\.install_dir_missing "\$INSTALL_DIR"\)"/ { saw_python_cd_error=1 }
      in_python && /if ! pip_log=\$\(mktemp\); then/ { saw_pip_tmp_if=1 }
      in_python && /warn "\$\(t app\.cyberstrikeai\.warn\.python_requirements\)"/ { saw_pip_tmp_warn=1 }
      in_python && /warn "\$\(t app\.cyberstrikeai\.warn\.requirements_missing\)"/ {
        if (!(saw_python_cd_if && saw_python_cd_error && saw_pip_tmp_if && saw_pip_tmp_warn)) {
          printf "%s CyberStrikeAI Python setup must guard install-directory access and pip log creation explicitly\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_python=0
      }
      /build_binary\(\)/ { in_build=1; saw_build_cd_if=0; saw_build_cd_error=0; saw_mod_if=0; saw_mod_error=0; next }
      in_build && /if ! cd "\$INSTALL_DIR"; then/ { saw_build_cd_if=1 }
      in_build && /error "\$\(t app\.cyberstrikeai\.error\.install_dir_missing "\$INSTALL_DIR"\)"/ { saw_build_cd_error=1 }
      in_build && /if ! go mod download; then/ { saw_mod_if=1 }
      in_build && /error "\$\(t app\.cyberstrikeai\.error\.go_modules "\$INSTALL_DIR"\)"/ { saw_mod_error=1 }
      in_build && /local tmp_bin="\$\{BIN_PATH\}\.tmp\.\$\$"/ {
        if (!(saw_build_cd_if && saw_build_cd_error && saw_mod_if && saw_mod_error)) {
          printf "%s CyberStrikeAI build prep must fail explicitly when the checkout is missing or Go modules cannot be downloaded\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_build=0
      }
      /write_nginx_config\(\)/ { in_nginx=1; saw_nginx_mkdir_if=0; saw_nginx_error=0; next }
      in_nginx && /if ! mkdir -p "\$\(dirname "\$NGINX_CONF"\)" "\$\(dirname "\$NGINX_LINK"\)"; then/ { saw_nginx_mkdir_if=1 }
      in_nginx && /error "\$\(t app\.cyberstrikeai\.error\.nginx_dirs "\$NGINX_CONF"\)"/ { saw_nginx_error=1 }
      in_nginx && /local nginx_tmp/ {
        if (!(saw_nginx_mkdir_if && saw_nginx_error)) {
          printf "%s CyberStrikeAI Nginx setup must guard directory creation explicitly\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_nginx=0
      }
      /step "\$\(t app\.cyberstrikeai\.step\.update_source\)"/ { in_update=1; saw_update_sync=0; saw_owner_if=0; saw_owner_error=0; next }
      in_update && /sync_repo_branch/ { saw_update_sync=1 }
      in_update && /if ! chown -R "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$INSTALL_DIR"; then/ { saw_owner_if=1 }
      in_update && /error "\$\(t app\.cyberstrikeai\.error\.install_dir_owner "\$INSTALL_DIR" "\$SERVICE_USER"\)"/ { saw_owner_error=1 }
      in_update && /if \$service_was_active; then/ {
        if (!(saw_update_sync && saw_owner_if && saw_owner_error)) {
          printf "%s CyberStrikeAI update prep must guard repository sync and ownership repair explicitly\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_update=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_build_temp_cleanup() {
  if grep -R -n '\${BIN_PATH}\.tmp\.\$\$' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "CyberStrikeAI binary build must use mktemp instead of a pid-derived temporary binary path." >&2
    return 1
  fi
  if grep -R -nE '^[[:space:]]*(go build|chmod 0755 "\$tmp_bin"|mv "\$tmp_bin" "\$BIN_PATH")' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "CyberStrikeAI binary build must clean up the temporary binary on build, chmod, and move failures." >&2
    return 1
  fi
  awk '
      /app\.cyberstrikeai\.warn\.tmp_binary_cleanup_failed/ { saw_warn_key=1 }
      END {
        if (!saw_warn_key) {
          print "CyberStrikeAI must provide a localized temporary binary cleanup warning." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/cyberstrikeai.sh
  awk '
      /build_binary\(\)/ { in_func=1; saw_tmp=0; saw_tmp_error=0; next }
      in_func && /if ! tmp_bin=\$\(mktemp "\$\{BIN_PATH\}\.tmp\.XXXXXX"\); then/ { saw_tmp=1 }
      in_func && /error "\$\(t app\.cyberstrikeai\.error\.binary_build\)"/ { saw_tmp_error=1 }
      in_func && /if ! go build .*"\$tmp_bin"/ { in_build=1; saw_build_cleanup=0; saw_build_warn=0; next }
      in_build && /if ! rm -f "\$tmp_bin"; then/ { saw_build_cleanup=1 }
      in_build && /warn "\$\(t app\.cyberstrikeai\.warn\.tmp_binary_cleanup_failed "\$tmp_bin"\)"/ { saw_build_warn=1 }
      in_build && /error "\$\(t app\.cyberstrikeai\.error\.binary_build\)"/ {
        if (!(saw_build_cleanup && saw_build_warn)) {
          print "CyberStrikeAI build failure does not surface temporary binary cleanup failures." > "/dev/stderr"
          exit 1
        }
        in_build=0
      }
      in_func && /if \[\[ ! -s "\$tmp_bin" \]\]; then/ { in_empty=1; saw_empty_cleanup=0; saw_empty_warn=0; next }
      in_empty && /if ! rm -f "\$tmp_bin"; then/ { saw_empty_cleanup=1 }
      in_empty && /warn "\$\(t app\.cyberstrikeai\.warn\.tmp_binary_cleanup_failed "\$tmp_bin"\)"/ { saw_empty_warn=1 }
      in_empty && /error "\$\(t app\.cyberstrikeai\.error\.binary_empty\)"/ {
        if (!(saw_empty_cleanup && saw_empty_warn)) {
          print "CyberStrikeAI empty binary failure does not surface temporary binary cleanup failures." > "/dev/stderr"
          exit 1
        }
        in_empty=0
      }
      in_func && /if ! chmod 0755 "\$tmp_bin"; then/ { in_chmod=1; saw_chmod_cleanup=0; saw_chmod_warn=0; next }
      in_chmod && /if ! rm -f "\$tmp_bin"; then/ { saw_chmod_cleanup=1 }
      in_chmod && /warn "\$\(t app\.cyberstrikeai\.warn\.tmp_binary_cleanup_failed "\$tmp_bin"\)"/ { saw_chmod_warn=1 }
      in_chmod && /error "\$\(t app\.cyberstrikeai\.error\.binary_build\)"/ {
        if (!(saw_chmod_cleanup && saw_chmod_warn)) {
          print "CyberStrikeAI chmod failure does not surface temporary binary cleanup failures." > "/dev/stderr"
          exit 1
        }
        in_chmod=0
      }
      in_func && /if ! mv "\$tmp_bin" "\$BIN_PATH"; then/ { in_move=1; saw_move_cleanup=0; saw_move_warn=0; next }
      in_move && /if ! rm -f "\$tmp_bin"; then/ { saw_move_cleanup=1 }
      in_move && /warn "\$\(t app\.cyberstrikeai\.warn\.tmp_binary_cleanup_failed "\$tmp_bin"\)"/ { saw_move_warn=1 }
      in_move && /error "\$\(t app\.cyberstrikeai\.error\.binary_build\)"/ {
        if (!(saw_move_cleanup && saw_move_warn)) {
          print "CyberStrikeAI move failure does not surface temporary binary cleanup failures." > "/dev/stderr"
          exit 1
        }
        in_move=0
      }
      in_func && /^}/ {
        if (!(saw_tmp && saw_tmp_error)) {
          print "CyberStrikeAI build must report temporary binary creation failures." > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_rollback_restore_is_validated() {
  if grep -R -nE '^[[:space:]]*(\[\[ -f "\$(bin_bak|config_bak)" \]\] && cp "\$(bin_bak|config_bak)"|chown "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$BIN_PATH" "\$CONFIG_FILE" 2>/dev/null \|\| true)' \
      impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "CyberStrikeAI update rollback must validate backup restore, mode, and ownership changes." >&2
    return 1
  fi
  awk '
      /restore_update_backup\(\)/ { in_func=1; saw_bin_tmp=0; saw_bin_tmp_return=0; saw_bin_cp=0; saw_chmod=0; saw_bin_chown=0; saw_bin_mv=0; saw_config_tmp=0; saw_config_tmp_return=0; saw_config_cp=0; saw_config_chown=0; saw_config_mv=0; next }
      in_func && /if ! bin_restore_tmp=\$\(mktemp "\$\{BIN_PATH\}\.restore\.XXXXXX"\); then/ { saw_bin_tmp=1 }
      in_func && saw_bin_tmp && /return 1/ { saw_bin_tmp_return=1 }
      in_func && /cp "\$bin_backup" "\$bin_restore_tmp"/ { saw_bin_cp=1 }
      in_func && /chmod 0755 "\$bin_restore_tmp"/ { saw_chmod=1 }
      in_func && /chown "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$bin_restore_tmp"/ { saw_bin_chown=1 }
      in_func && /mv "\$bin_restore_tmp" "\$BIN_PATH"/ { saw_bin_mv=1 }
      in_func && /if ! config_restore_tmp=\$\(mktemp "\$\{CONFIG_FILE\}\.restore\.XXXXXX"\); then/ { saw_config_tmp=1 }
      in_func && saw_config_tmp && /return 1/ { saw_config_tmp_return=1 }
      in_func && /cp "\$config_backup" "\$config_restore_tmp"/ { saw_config_cp=1 }
      in_func && /chown "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$config_restore_tmp"/ { saw_config_chown=1 }
      in_func && /mv "\$config_restore_tmp" "\$CONFIG_FILE"/ { saw_config_mv=1 }
      in_func && /^}/ {
        if (!(saw_bin_tmp && saw_bin_tmp_return && saw_bin_cp && saw_chmod && saw_bin_chown && saw_bin_mv && saw_config_tmp && saw_config_tmp_return && saw_config_cp && saw_config_chown && saw_config_mv)) {
          printf "%s CyberStrikeAI rollback helper must stage and atomically restore binary and config state\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_backups_are_atomic() {
  if grep -R -nE '^[[:space:]]*(cp "\$CONFIG_FILE" "\$backup"|\[\[ -f "\$(BIN_PATH|CONFIG_FILE)" \]\] && cp "\$(BIN_PATH|CONFIG_FILE)")' \
      impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "CyberStrikeAI rollback/config backups must copy to a temporary file before replacing the final backup path." >&2
    return 1
  fi
  awk '
      /write_backup_file\(\)/ { in_func=1; saw_tmp=0; saw_tmp_return=0; saw_cp=0; saw_mv=0; saw_cleanup=0; saw_atomic=0; next }
      in_func && /atomic_copy_file "\$source_path" "\$backup_path"/ { saw_atomic=1 }
      in_func && /if ! backup_tmp=\$\(mktemp "\$\{backup_path\}\.XXXXXX"\); then/ { saw_tmp=1 }
      in_func && saw_tmp && /return 1/ { saw_tmp_return=1 }
      in_func && /cp "\$source_path" "\$backup_tmp"/ { saw_cp=1 }
      in_func && /mv "\$backup_tmp" "\$backup_path"/ { saw_mv=1 }
      in_func && /rm -f "\$backup_tmp"/ { saw_cleanup=1 }
      in_func && /^}/ {
        if (!((saw_tmp && saw_tmp_return && saw_cp && saw_mv && saw_cleanup) || saw_atomic)) {
          printf "%s CyberStrikeAI backup helper must stage, replace, and clean up temporary backups\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_config_patch_is_atomic() {
  if grep -R -n 'path.write_text(text, encoding="utf-8")' \
      impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "CyberStrikeAI config patching must write via a staged temporary file and atomic replace." >&2
    return 1
  fi
  awk '
      /patch_config_port_and_paths\(\)/ { in_func=1; saw_stat=0; saw_tmpfile=0; saw_fsync=0; saw_chmod=0; saw_chown=0; saw_replace=0; saw_cleanup=0; next }
      in_func && /file_stat = path\.stat\(\)/ { saw_stat=1 }
      in_func && /tempfile\.NamedTemporaryFile\(/ { saw_tmpfile=1 }
      in_func && /os\.fsync\(handle\.fileno\(\)\)/ { saw_fsync=1 }
      in_func && /os\.chmod\(tmp_path, file_stat\.st_mode & 0o777\)/ { saw_chmod=1 }
      in_func && /os\.chown\(tmp_path, file_stat\.st_uid, file_stat\.st_gid\)/ { saw_chown=1 }
      in_func && /os\.replace\(tmp_path, path\)/ { saw_replace=1 }
      in_func && /Path\(tmp_path\)\.unlink\(missing_ok=True\)/ { saw_cleanup=1 }
      in_func && /^}/ {
        if (!(saw_stat && saw_tmpfile && saw_fsync && saw_chmod && saw_chown && saw_replace && saw_cleanup)) {
          printf "%s CyberStrikeAI config patch helper must stage writes and atomically replace the config file\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_service_start_paths_are_explicit() {
  if grep -R -nE '^[[:space:]]*systemctl restart "\$SERVICE_NAME"$' \
      impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "CyberStrikeAI service restart paths must branch explicitly on command failure." >&2
    return 1
  fi
  awk '
      /step "\$\(t app\.cyberstrikeai\.step\.start\)"/ { in_start=1; saw_restart_wait=0; next }
      in_start && /if systemctl restart "\$SERVICE_NAME" && wait_for_service "\$SERVICE_NAME" 35; then/ { saw_restart_wait=1 }
      in_start && /journalctl -u "\$SERVICE_NAME" -n 40 --no-pager >&2 \|\| true/ {
        if (!saw_restart_wait) {
          printf "%s CyberStrikeAI startup must gate success on an explicit restart-and-wait branch\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_start=0
      }
      /step "\$\(t app\.cyberstrikeai\.step\.restart_updated\)"/ { in_update=1; saw_restart_wait2=0; next }
      in_update && /if systemctl restart "\$SERVICE_NAME" && wait_for_service "\$SERVICE_NAME" 35; then/ { saw_restart_wait2=1 }
      in_update && /warn "\$\(t app\.cyberstrikeai\.warn\.update_start_failed\)"/ {
        if (!saw_restart_wait2) {
          printf "%s CyberStrikeAI update must gate service success on an explicit restart-and-wait branch\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_update=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_enable_failures_are_reported() {
  awk '
      /app\.cyberstrikeai\.warn\.service_enable_failed/ { saw_warn_key=1 }
      /if ! systemctl enable "\$SERVICE_NAME" --quiet; then/ { saw_service_if=1 }
      /warn "\$\(t app\.cyberstrikeai\.warn\.service_enable_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_service_warn=1 }
      /if ! systemctl enable nginx --quiet; then/ { saw_nginx_if=1 }
      /warn "\$\(t app\.cyberstrikeai\.warn\.service_enable_failed "nginx" "nginx"\)"/ { saw_nginx_warn=1 }
      END {
        if (!(saw_warn_key && saw_service_if && saw_service_warn && saw_nginx_if && saw_nginx_warn)) {
          print "CyberStrikeAI must warn when service enablement fails for the app service or Nginx." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/cyberstrikeai.sh impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_update_rollbacks_report_restart_failures() {
  if grep -R -n 'systemctl start "\$SERVICE_NAME" 2>/dev/null' \
      impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "CyberStrikeAI update rollback paths must not suppress service restart diagnostics." >&2
    return 1
  fi
  awk '
      /warn "\$\(t app\.cyberstrikeai\.warn\.update_start_failed\)"/ { in_update_failure=1; saw_restore=0; saw_start_if=0; saw_wait=0; saw_ok_error=0; saw_failed_error=0; next }
      in_update_failure && /if restore_update_backup "\$bin_bak" "\$config_bak"; then/ { saw_restore=1 }
      in_update_failure && /if systemctl start "\$SERVICE_NAME"; then/ { saw_start_if=1 }
      in_update_failure && /if wait_for_service "\$SERVICE_NAME" 35; then/ { saw_wait=1 }
      in_update_failure && /error "\$\(t app\.cyberstrikeai\.error\.update_rollback_ok "\$SERVICE_NAME"\)"/ { saw_ok_error=1 }
      in_update_failure && /error "\$\(t app\.cyberstrikeai\.error\.update_rollback_failed "\$SERVICE_NAME"\)"/ { saw_failed_error=1 }
      in_update_failure && /^    fi$/ {
        if (saw_restore && !(saw_start_if && saw_wait && saw_ok_error && saw_failed_error)) {
          printf "%s CyberStrikeAI update rollback must branch explicitly on restart failures before reporting rollback outcome\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
      in_update_failure && /^  else$/ { in_update_failure=0 }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_update_rollback_stop_failure_aborts_restore() {
  awk '
      /app\.cyberstrikeai\.error\.rollback_stop_failed/ { saw_key=1 }
      END {
        if (!saw_key) {
          print "CyberStrikeAI must provide an actionable rollback stop failure error." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/cyberstrikeai.sh
  awk '
      /warn "\$\(t app\.cyberstrikeai\.warn\.update_start_failed\)"/ { in_rollback=1; saw_if=0; saw_error=0; saw_suppressed=0; next }
      in_rollback && /systemctl stop "\$SERVICE_NAME" 2>\/dev\/null \|\| true/ { saw_suppressed=1 }
      in_rollback && /if ! systemctl stop "\$SERVICE_NAME" 2>\/dev\/null; then/ { saw_if=1 }
      in_rollback && /error "\$\(t app\.cyberstrikeai\.error\.rollback_stop_failed "\$SERVICE_NAME" "\$bin_bak" "\$config_bak" "\$SERVICE_NAME"\)"/ { saw_error=1 }
      in_rollback && /if restore_update_backup "\$bin_bak" "\$config_bak"; then/ {
        if (!(saw_if && saw_error) || saw_suppressed) {
          printf "%s CyberStrikeAI update rollback must abort before restoring files when stopping the failed updated service fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_rollback=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_uninstall_stop_disable_failures_are_reported() {
  awk '
      /app\.cyberstrikeai\.info\.stop_disable/ { saw_info=1 }
      /app\.cyberstrikeai\.error\.uninstall_stop_failed/ { saw_stop_error=1 }
      /app\.cyberstrikeai\.warn\.uninstall_stop_failed/ { saw_stop_warn=1 }
      /app\.cyberstrikeai\.warn\.uninstall_disable_failed/ { saw_disable_warn=1 }
      END {
        if (!(saw_info && saw_stop_error && saw_stop_warn && saw_disable_warn)) {
          print "CyberStrikeAI must provide localized uninstall stop and disable failure messages." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/cyberstrikeai.sh
  awk '
      /info "\$\(t app\.cyberstrikeai\.info\.stop_disable "\$SERVICE_NAME"\)"/ { in_uninstall=1; saw_stop_if=0; saw_active_if=0; saw_stop_error=0; saw_stop_warn=0; saw_disable_if=0; saw_disable_warn=0; saw_suppressed=0; next }
      in_uninstall && /systemctl (stop|disable).* \|\| true/ { saw_suppressed=1 }
      in_uninstall && /if ! systemctl stop "\$SERVICE_NAME" 2>\/dev\/null; then/ { saw_stop_if=1 }
      in_uninstall && /if systemctl is-active --quiet "\$SERVICE_NAME" 2>\/dev\/null; then/ { saw_active_if=1 }
      in_uninstall && /error "\$\(t app\.cyberstrikeai\.error\.uninstall_stop_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_stop_error=1 }
      in_uninstall && /warn "\$\(t app\.cyberstrikeai\.warn\.uninstall_stop_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_stop_warn=1 }
      in_uninstall && /if ! systemctl disable "\$SERVICE_NAME" 2>\/dev\/null; then/ { saw_disable_if=1 }
      in_uninstall && /warn "\$\(t app\.cyberstrikeai\.warn\.uninstall_disable_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_disable_warn=1 }
      in_uninstall && /rm -f "\/etc\/systemd\/system\/\$\{SERVICE_NAME\}\.service"/ {
        if (!(saw_stop_if && saw_active_if && saw_stop_error && saw_stop_warn && saw_disable_if && saw_disable_warn) || saw_suppressed) {
          printf "%s CyberStrikeAI uninstall must abort when an active service cannot be stopped and warn on disable failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_uninstall=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_install_summary_matches_health_state() {
  awk '
      /app\.cyberstrikeai\.summary\.title_ready/ { saw_title_ready=1 }
      /app\.cyberstrikeai\.summary\.title_pending/ { saw_title_pending=1 }
      END {
        if (!(saw_title_ready && saw_title_pending)) {
          print "CyberStrikeAI install summary strings must distinguish ready and pending health states." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/cyberstrikeai.sh
  awk '
      /health_check\(\)/ { in_health=1; saw_pending_flag=0; saw_backend_warn=0; saw_nginx_warn=0; saw_return=0; next }
      in_health && /local health_pending=0/ { saw_pending_flag=1 }
      in_health && /warn "\$\(t app\.cyberstrikeai\.warn\.backend_health "\$code"\)"/ { saw_backend_warn=1 }
      in_health && /warn "\$\(t app\.cyberstrikeai\.warn\.nginx_health "\$code"\)"/ { saw_nginx_warn=1 }
      in_health && /\[\[ "\$health_pending" -eq 0 \]\]/ { saw_return=1 }
      in_health && /^}/ {
        if (!(saw_pending_flag && saw_backend_warn && saw_nginx_warn && saw_return)) {
          printf "%s CyberStrikeAI health check must return explicit ready/pending status\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_health=0
      }
      /print_summary\(\)/ { in_summary=1; saw_state=0; saw_pending=0; saw_ready=0; next }
      in_summary && /local summary_state="\$\{1:-ready\}"/ { saw_state=1 }
      in_summary && /app\.cyberstrikeai\.summary\.title_pending/ { saw_pending=1 }
      in_summary && /app\.cyberstrikeai\.summary\.title_ready/ { saw_ready=1 }
      in_summary && /^}/ {
        if (!(saw_state && saw_pending && saw_ready)) {
          printf "%s CyberStrikeAI summary printer must branch on health state\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_summary=0
      }
      /start_service/ { saw_start=1 }
      /local _install_summary_state="ready"/ { saw_init=1 }
      /if ! health_check; then/ { saw_health_if=1 }
      /_install_summary_state="pending"/ { saw_pending_state=1 }
      /print_summary "\$_install_summary_state"/ {
        if (!(saw_start && saw_init && saw_health_if && saw_pending_state)) {
          printf "%s CyberStrikeAI install flow must downgrade the summary when health checks stay pending\n", FILENAME > "/dev/stderr"
          exit 1
        }
        saw_summary_call=1
      }
      END {
        if (!saw_summary_call) {
          print "CyberStrikeAI install flow must pass health state into the install summary." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_nginx_health_probe_matches_server_name() {
  awk '
      /app\.cyberstrikeai\.warn\.nginx_health/ { saw_warn=1 }
      /Local Nginx probe returned HTTP %s/ { saw_probe_text=1 }
      /configured server_name/ { saw_guidance=1 }
      END {
        if (!(saw_warn && saw_probe_text && saw_guidance)) {
          print "CyberStrikeAI Nginx health warnings must describe the local probe and server_name guidance." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/cyberstrikeai.sh
  awk '
      /step "\$\(t app\.cyberstrikeai\.step\.health\)"/ { in_health=1; next }
      in_health && /public_url="http:\/\/127\.0\.0\.1:\$\{PUBLIC_PORT\}\/"/ { saw_url=1 }
      in_health && /curl -H "Host: \$\{CSAI_DOMAIN:-localhost\}"/ { saw_host_header=1 }
      in_health && /warn "\$\(t app\.cyberstrikeai\.warn\.nginx_health "\$code"\)"/ { saw_warn=1 }
      in_health && /\[\[ "\$health_pending" -eq 0 \]\]/ {
        if (!(saw_url && saw_host_header && saw_warn)) {
          printf "%s CyberStrikeAI local Nginx probe must send the configured Host header before warning on mismatches\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_health=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_health_checks_are_nonfatal_outside_install() {
  awk '
      /success "\$\(t app\.cyberstrikeai\.success\.update_complete "\$old_rev" "\$new_rev"\)"/ { in_update=1; saw_health_if=0; next }
      in_update && /if ! health_check; then/ { saw_health_if=1 }
      in_update && /warn "\$\(t app\.cyberstrikeai\.warn\.update_start_failed\)"/ {
        if (!saw_health_if) {
          printf "%s CyberStrikeAI update must treat post-restart health warnings as nonfatal\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_update=0
      }
      /step "\$\(t app\.cyberstrikeai\.step\.health\)"/ { in_status=1; saw_status_if=0; next }
      in_status && /if ! health_check; then/ { saw_status_if=1 }
      in_status && /step "\$\(t app\.cyberstrikeai\.step\.nginx\)"/ {
        if (!saw_status_if) {
          printf "%s CyberStrikeAI status must keep reporting after local health warnings\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_status=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_nginx_apply_preserves_reload_diagnostics() {
  if grep -R -n 'systemctl reload nginx 2>/dev/null || systemctl restart nginx' \
      impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "CyberStrikeAI nginx apply path must not suppress reload diagnostics." >&2
    return 1
  fi
  awk '
      /app_write_nginx_site_link "\$NGINX_CONF" "\$NGINX_LINK"/ { in_block=1; saw_test=0; saw_reload=0; saw_restart=0; next }
      in_block && /if ! nginx -t; then/ { saw_test=1 }
      in_block && /error "\$\(t app\.cyberstrikeai\.error\.nginx_test\)"/ { saw_test_error=1 }
      in_block && /if systemctl is-active --quiet nginx; then/ { saw_active_check=1 }
      in_block && /if ! systemctl reload nginx; then/ { saw_reload=1 }
      in_block && /if ! systemctl restart nginx; then/ { saw_restart=1 }
      in_block && /error "\$\(t app\.cyberstrikeai\.error\.nginx_start\)"/ { saw_start_error=1 }
      in_block && /if ! wait_for_service nginx 10; then/ { saw_wait=1 }
      in_block && /success "\$\(t app\.cyberstrikeai\.success\.nginx\)"/ {
        if (!(saw_test && saw_test_error && saw_active_check && saw_reload && saw_restart && saw_start_error && saw_wait)) {
          printf "%s CyberStrikeAI nginx apply path must validate config, preserve reload diagnostics, and report start failures explicitly\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}
