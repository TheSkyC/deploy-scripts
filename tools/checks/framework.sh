# shellcheck shell=bash
# shellcheck source=../verify.sh
# Verify checks for shared framework guardrails (validators, atomic writes,
# config, nginx, systemd, backups, and the runner entry checks).

check_shell_syntax() {
  local file
  while IFS= read -r file; do
    "$BASH_BIN" -n "$file"
  done < <(find apps bin impl lib tools -name '*.sh' -type f | sort; printf '%s\n' deploy.sh)
}

check_shellcheck() {
  if ! command -v shellcheck >/dev/null 2>&1; then
    echo "shellcheck not found; skipping static analysis (install shellcheck to enable)"
    return 0
  fi
  # SC2034: app/framework contract variables (APP_ID, LOCK_FILE, doctor hooks,
  # ...) are consumed by name from other scripts and are not unused.
  # SC1090: impl files source lib/*.sh through runtime-derived paths.
  # SC1017: git stores LF via .gitattributes even when the working tree is CRLF.
  local file
  local files=()
  while IFS= read -r file; do
    files+=("$file")
  done < <(find apps bin impl lib tools -name '*.sh' -type f | sort; printf '%s\n' deploy.sh)
  shellcheck --severity=warning --exclude=SC2034,SC1090,SC1017 "${files[@]}"
}

check_release_syntax() {
  local file
  while IFS= read -r file; do
    "$BASH_BIN" -n "$file"
  done < <(find dist -maxdepth 1 \( -name 'install_*.sh' -o -name 'deploy.sh' \) -type f | sort)
}

check_safe_path_guard() {
  "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh

    unsafe_paths=("" "/" "." ".." "relative/path" "/tmp" "/opt" "/var" "/var/log" "/var/lib" "/usr/local/bin" "/opt/app/../other" "/srv" "/mnt" "/data" "/media" "/backup" "/www" "/export" "/pool" "/var/www" "/usr/share" "/usr/local/lib" "/var/cache")
    for path in "${unsafe_paths[@]}"; do
      if is_safe_path "$path"; then
        echo "Expected unsafe path to be rejected: ${path:-empty}" >&2
        exit 1
      fi
    done

    safe_paths=("/opt/new-api" "/opt/new-api/data" "/var/lib/vaultwarden" "/var/log/vaultwarden" "/tmp/deploy-scripts.newapi.abc123" "/srv/myapp" "/var/www/blog" "/mnt/data/app")
    for path in "${safe_paths[@]}"; do
      if ! is_safe_path "$path"; then
        echo "Expected safe path to be accepted: ${path}" >&2
        exit 1
      fi
    done
  '
  awk '
      /restore_web_vault_backup\(\)/ { in_vw=1; saw_safe=0; next }
      in_vw && /safe_rm_dir "\$VW_WEB_DIR" "VW_WEB_DIR"/ { saw_safe=1 }
      in_vw && /mv "\$backup_dir" "\$VW_WEB_DIR"/ {
        if (!saw_safe) {
          print "Vaultwarden Web Vault restore must use safe_rm_dir before replacing the live directory." > "/dev/stderr"
          exit 1
        }
        in_vw=0
      }
      /^restore_nginx_root_backup\(\)/ { in_blog=1; saw_blog_safe=0; next }
      in_blog && /safe_rm_dir "\$NGINX_ROOT" "NGINX_ROOT"/ { saw_blog_safe=1 }
      in_blog && /mv "\$DEPLOY_BAK" "\$NGINX_ROOT"/ {
        if (!saw_blog_safe) {
          print "Blog Nginx root restore must use safe_rm_dir before replacing the live directory." > "/dev/stderr"
          exit 1
        }
        in_blog=0
      }
    ' impl/install_blog.sh impl/install_vaultwarden.sh
  awk '
      /do_uninstall\(\)/ { in_uninstall=1; saw_install_dir_guard=0; saw_vw_bin_guard=0; next }
      in_uninstall && /require_safe_path "INSTALL_DIR" "\$INSTALL_DIR"/ { saw_install_dir_guard=1 }
      in_uninstall && /_require_safe_vw_bin_path/ { saw_vw_bin_guard=1 }
      in_uninstall && /find "\$INSTALL_DIR" -maxdepth 1 -name "(new-api|sub2api)\./ {
        if (!saw_install_dir_guard) {
          printf "%s uninstall cleanup must validate INSTALL_DIR before deleting generated files\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
      in_uninstall && /find "\$\(dirname "\$VW_BIN"\)" -maxdepth 1 -name "vaultwarden\.bak\./ {
        if (!saw_vw_bin_guard) {
          printf "%s Vaultwarden uninstall must validate VW_BIN before deleting generated binary backups\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
      in_uninstall && /^}/ { in_uninstall=0 }
    ' impl/install_newapi.sh impl/install_sub2api.sh impl/install_vaultwarden.sh
}

check_managed_paths_are_validated() {
  awk '
      /_validate_config_values\(\)/ { in_func=1; next }
      in_func && /require_safe_path "INSTALL_DIR" "\$INSTALL_DIR"/ { saw_install=1 }
      in_func && /_newapi_require_safe_bin_path/ { saw_bin=1 }
      in_func && /require_safe_path "DATA_DIR" "\$DATA_DIR"/ { saw_data=1 }
      in_func && /require_safe_path "LOG_DIR" "\$LOG_DIR"/ { saw_log=1 }
      in_func && /require_safe_path "LOG_FILE" "\$LOG_FILE"/ { saw_log_file=1 }
      in_func && /require_safe_path "ENV_FILE" "\$ENV_FILE"/ { saw_env=1 }
      in_func && /require_safe_path "BACKUP_DIR" "\$BACKUP_DIR"/ { saw_backup=1 }
      in_func && /^}/ {
        if (!(saw_install && saw_bin && saw_data && saw_log && saw_log_file && saw_env && saw_backup)) {
          printf "%s NewAPI must validate managed directory and derived file paths before use\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
  awk '
      /_validate_config_values\(\)/ { in_func=1; next }
      in_func && /require_safe_path "INSTALL_DIR" "\$INSTALL_DIR"/ { saw_install=1 }
      in_func && /_sub2api_require_safe_bin_path/ { saw_bin=1 }
      in_func && /require_safe_path "DATA_DIR" "\$DATA_DIR"/ { saw_data=1 }
      in_func && /require_safe_path "LOG_DIR" "\$LOG_DIR"/ { saw_log=1 }
      in_func && /require_safe_path "CONFIG_DIR" "\$CONFIG_DIR"/ { saw_config=1 }
      in_func && /require_safe_path "BACKUP_DIR" "\$BACKUP_DIR"/ { saw_backup=1 }
      in_func && /^}/ {
        if (!(saw_install && saw_bin && saw_data && saw_log && saw_config && saw_backup)) {
          printf "%s Sub2API must validate managed directory and derived binary paths before use\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
  awk '
      /_validate_config_values\(\)/ { in_func=1; next }
      in_func && /require_safe_path "VW_DATA_DIR" "\$VW_DATA_DIR"/ { saw_data=1 }
      in_func && /require_safe_path "VW_WEB_DIR" "\$VW_WEB_DIR"/ { saw_web=1 }
      in_func && /require_safe_path "LOG_DIR" "\$\(dirname "\$VW_LOG_FILE"\)"/ { saw_log=1 }
      in_func && /require_safe_path "VW_BACKUP_DIR" "\$VW_BACKUP_DIR"/ { saw_backup=1 }
      in_func && /_require_safe_vw_bin_path/ { saw_bin=1 }
      in_func && /^}/ {
        if (!(saw_data && saw_web && saw_log && saw_backup && saw_bin)) {
          printf "%s Vaultwarden must validate managed paths and VW_BIN before use\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
  awk '
      /_validate_config_values\(\)/ { in_func=1; next }
      in_func && /require_safe_path "INSTALL_DIR" "\$INSTALL_DIR"/ { saw_install=1 }
      in_func && /require_safe_path "BIN_PATH" "\$BIN_PATH"/ { saw_bin=1 }
      in_func && /require_safe_path "CONFIG_FILE" "\$CONFIG_FILE"/ { saw_config=1 }
      in_func && /require_safe_path "VENV_DIR" "\$VENV_DIR"/ { saw_venv=1 }
      in_func && /require_safe_path "LOG_DIR" "\$LOG_DIR"/ { saw_log=1 }
      in_func && /require_safe_path "BACKUP_DIR" "\$BACKUP_DIR"/ { saw_backup=1 }
      in_func && /^}/ {
        if (!(saw_install && saw_bin && saw_config && saw_venv && saw_log && saw_backup)) {
          printf "%s CyberStrikeAI must validate managed directory and derived file paths before use\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
  awk '
      /_validate_config_values\(\)/ { in_func=1; next }
      in_func && /require_safe_path "TICKFLOW_INSTALL_DIR" "\$TICKFLOW_INSTALL_DIR"/ { saw_install=1 }
      in_func && /require_safe_path "TICKFLOW_DATA_DIR" "\$TICKFLOW_DATA_DIR"/ { saw_data=1 }
      in_func && /require_safe_path "TICKFLOW_LOG_DIR" "\$TICKFLOW_LOG_DIR"/ { saw_log=1 }
      in_func && /require_safe_path "TICKFLOW_ENV_FILE" "\$TICKFLOW_ENV_FILE"/ { saw_env=1 }
      in_func && /require_safe_path "TICKFLOW_COMPOSE_FILE" "\$TICKFLOW_COMPOSE_FILE"/ { saw_compose=1 }
      in_func && /require_safe_path "TICKFLOW_TIERS_FILE" "\$TICKFLOW_TIERS_FILE"/ { saw_tiers=1 }
      in_func && /^}/ {
        if (!(saw_install && saw_data && saw_log && saw_env && saw_compose && saw_tiers)) {
          printf "%s TickFlow must validate managed directory and file paths before use\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_tickflow.sh dist/install_tickflow.sh
  awk '
      /_validate_config_values\(\)/ { in_func=1; next }
      in_func && /require_safe_path "SITE_DIR" "\$SITE_DIR"/ { saw_site=1 }
      in_func && /require_safe_path "PUBLIC_DIR" "\$PUBLIC_DIR"/ { saw_public=1 }
      in_func && /require_safe_path "NGINX_ROOT" "\$NGINX_ROOT"/ { saw_nginx=1 }
      in_func && /require_safe_path "BLOG_BACKUP_DIR" "\$BLOG_BACKUP_DIR"/ { saw_backup=1 }
      in_func && /^}/ {
        if (!(saw_site && saw_public && saw_nginx && saw_backup)) {
          printf "%s Blog must validate managed directory paths before use\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_blog.sh dist/install_blog.sh
}

check_safe_rm_dir_is_idempotent() {
  "$BASH_BIN" -c '
    set -euo pipefail
    source lib/fs.sh
    tmp=$(mktemp -d)
    child="${tmp}/missing-dir"
    rmdir "$tmp"
    safe_rm_dir "$child" "TEST_PATH"
  '
  awk '
      /_write_publish_script\(\)/ { saw_helper=1; next }
      saw_helper && /<< BKSH$/ { in_heredoc=1; next }
      in_heredoc && /safe_rm_dir\(\)/ { in_func=1; saw_missing=0; saw_type_guard=0; next }
      in_func && /\[\[ -e "\\\$path" \|\| -L "\\\$path" \]\] \|\| return 0/ { saw_missing=1 }
      in_func && /\[\[ -d "\\\$path" \|\| -L "\\\$path" \]\] \|\| return 1/ { saw_type_guard=1 }
      in_func && /^}/ {
        if (!(saw_missing && saw_type_guard)) {
          printf "%s Blog publish helper safe_rm_dir must treat missing safe paths as already removed and reject non-directory paths\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
        in_heredoc=0
      }
    ' impl/install_blog.sh dist/install_blog.sh
}

check_atomic_helpers_are_atomic() {
  awk '
      /atomic_write_file\(\)/ { in_write=1; saw_dir=0; saw_tmp=0; saw_cat=0; saw_chmod=0; saw_chown=0; saw_mv=0; saw_cleanup=0; next }
      in_write && /mkdir -p "\$target_dir"/ { saw_dir=1 }
      in_write && /mktemp "\$\{target_dir\}\/\.\$\(basename "\$target_path"\)\.XXXXXX"/ { saw_tmp=1 }
      in_write && /cat > "\$target_tmp"/ { saw_cat=1 }
      in_write && /chmod "\$mode" "\$target_tmp"/ { saw_chmod=1 }
      in_write && /chown "\$owner" "\$target_tmp"/ { saw_chown=1 }
      in_write && /mv "\$target_tmp" "\$target_path"/ { saw_mv=1 }
      in_write && /rm -f "\$target_tmp"/ { saw_cleanup=1 }
      in_write && /^}/ {
        if (!(saw_dir && saw_tmp && saw_cat && saw_chmod && saw_chown && saw_mv && saw_cleanup)) {
          printf "%s atomic_write_file must stage, permission, replace, and clean up temporary files\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_write=0
      }
      /atomic_copy_file\(\)/ { in_copy=1; saw_dir=0; saw_tmp=0; saw_cp=0; saw_chmod=0; saw_chown=0; saw_mv=0; saw_cleanup=0; next }
      in_copy && /mkdir -p "\$target_dir"/ { saw_dir=1 }
      in_copy && /mktemp "\$\{target_path\}\.XXXXXX"/ { saw_tmp=1 }
      in_copy && /cp "\$source_path" "\$target_tmp"/ { saw_cp=1 }
      in_copy && /chmod "\$mode" "\$target_tmp"/ { saw_chmod=1 }
      in_copy && /chown "\$owner" "\$target_tmp"/ { saw_chown=1 }
      in_copy && /mv "\$target_tmp" "\$target_path"/ { saw_mv=1 }
      in_copy && /rm -f "\$target_tmp"/ { saw_cleanup=1 }
      in_copy && /^}/ {
        if (!(saw_dir && saw_tmp && saw_cp && saw_chmod && saw_chown && saw_mv && saw_cleanup)) {
          printf "%s atomic_copy_file must stage, permission, replace, and clean up temporary files\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_copy=0
      }
      /atomic_symlink\(\)/ { in_link=1; saw_dir=0; saw_tmp=0; saw_unlink=0; saw_ln=0; saw_mv=0; saw_cleanup=0; next }
      in_link && /mkdir -p "\$link_dir"/ { saw_dir=1 }
      in_link && /mktemp "\$\{link_path\}\.XXXXXX"/ { saw_tmp=1 }
      in_link && /rm -f "\$link_tmp"/ { saw_unlink=1; saw_cleanup=1 }
      in_link && /ln -s "\$target_path" "\$link_tmp"/ { saw_ln=1 }
      in_link && /mv -Tf "\$link_tmp" "\$link_path"/ { saw_mv=1 }
      in_link && /^}/ {
        if (!(saw_dir && saw_tmp && saw_unlink && saw_ln && saw_mv && saw_cleanup)) {
          printf "%s atomic_symlink must stage, replace, and clean up temporary symlinks\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_link=0
      }
    ' lib/atomic.sh dist/install_newapi.sh
}

check_binary_helpers_are_atomic() {
  awk '
      /app_binary_restore_moved_backup\(\)/ { in_moved=1; saw_tmp=0; saw_tmp_return=0; saw_cp=0; saw_chmod=0; saw_chown=0; saw_mv=0; saw_cleanup=0; next }
      in_moved && /mktemp "\$\{BIN_PATH\}\.restore\.XXXXXX"/ { saw_tmp=1 }
      in_moved && saw_tmp && /return 1/ { saw_tmp_return=1 }
      in_moved && /cp "\$backup_path" "\$restore_tmp"/ { saw_cp=1 }
      in_moved && /chmod \+x "\$restore_tmp"/ { saw_chmod=1 }
      in_moved && /chown "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$restore_tmp"/ { saw_chown=1 }
      in_moved && /mv "\$restore_tmp" "\$BIN_PATH"/ { saw_mv=1 }
      in_moved && /rm -f "\$backup_path"/ { saw_cleanup=1 }
      in_moved && /^}/ {
        if (!(saw_tmp && saw_tmp_return && saw_cp && saw_chmod && saw_chown && saw_mv && saw_cleanup)) {
          printf "%s app_binary_restore_moved_backup must stage, restore atomically, and remove moved backups\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_moved=0
      }
      /app_binary_install_candidate\(\)/ { in_install=1; saw_backup=0; saw_mv=0; saw_restore=0; saw_chmod=0; saw_chown=0; saw_cleanup=0; next }
      in_install && /mv "\$BIN_PATH" "\$backup_path"/ { saw_backup=1 }
      in_install && /mv "\$tmp_bin" "\$BIN_PATH"/ { saw_mv=1 }
      in_install && /app_binary_restore_moved_backup "\$backup_path"/ { saw_restore=1 }
      in_install && /chmod \+x "\$BIN_PATH"/ { saw_chmod=1 }
      in_install && /chown "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$BIN_PATH"/ { saw_chown=1 }
      in_install && /rm -f "\$tmp_bin"/ { saw_cleanup=1 }
      in_install && /^}/ {
        if (!(saw_backup && saw_mv && saw_restore && saw_chmod && saw_chown && saw_cleanup)) {
          printf "%s app_binary_install_candidate must back up, replace, restore on failure, and clean up candidates\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_install=0
      }
      /app_binary_restore_backup\(\)/ { in_restore=1; saw_tmp=0; saw_tmp_return=0; saw_cp=0; saw_chmod=0; saw_chown=0; saw_mv=0; next }
      in_restore && /mktemp "\$\{BIN_PATH\}\.restore\.XXXXXX"/ { saw_tmp=1 }
      in_restore && saw_tmp && /return 1/ { saw_tmp_return=1 }
      in_restore && /cp "\$backup_path" "\$restore_tmp"/ { saw_cp=1 }
      in_restore && /chmod \+x "\$restore_tmp"/ { saw_chmod=1 }
      in_restore && /chown "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$restore_tmp"/ { saw_chown=1 }
      in_restore && /mv "\$restore_tmp" "\$BIN_PATH"/ { saw_mv=1 }
      in_restore && /^}/ {
        if (!(saw_tmp && saw_tmp_return && saw_cp && saw_chmod && saw_chown && saw_mv)) {
          printf "%s app_binary_restore_backup must stage and atomically restore binary mode and ownership\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_restore=0
      }
      /app_binary_backup_current\(\)/ { in_backup=1; saw_atomic=0; next }
      in_backup && /atomic_copy_file "\$BIN_PATH" "\$backup_path"/ { saw_atomic=1 }
      in_backup && /^}/ {
        if (!saw_atomic) {
          printf "%s app_binary_backup_current must use atomic_copy_file\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_backup=0
      }
    ' lib/binary.sh dist/install_newapi.sh
}

check_systemd_helper_is_atomic() {
  awk '
      /systemd_write_unit\(\)/ { in_func=1; saw_atomic=0; next }
      in_func && /atomic_write_file "\$unit_path" 644 root:root/ { saw_atomic=1 }
      in_func && /^}/ {
        if (!saw_atomic) {
          printf "%s systemd_write_unit must use atomic_write_file with root ownership\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' lib/service.sh dist/install_newapi.sh
}

check_service_status_label() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  cat > "${tmp_dir}/systemctl" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  is-active)
    [[ "${3:-}" == "active-service" ]] && exit 0
    exit 3
    ;;
  list-unit-files)
    for arg in "$@"; do
      if [[ "$arg" == "inactive-service.service" ]]; then
        echo "inactive-service.service disabled"
        exit 0
      fi
      if [[ "$arg" == "missing-service.service" ]]; then
        exit 0
      fi
    done
    exit 0
    ;;
esac
exit 1
STUB
  chmod +x "${tmp_dir}/systemctl"

  PATH="${tmp_dir}:$PATH" DEPLOY_LANG=en "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    [[ "$(service_status_label active-service)" == "active" ]]
    [[ "$(service_status_label inactive-service)" == "inactive" ]]
    [[ "$(service_status_label missing-service)" == "unknown" ]]
  '
  rm -rf "$tmp_dir"
}

check_config_writes_are_centralized() {
  if grep -R -nE '(>|>>)[[:space:]]*"?\$\{?CONF_FILE\}?"?|tee[[:space:]]+"?\$\{?CONF_FILE\}?"?' impl dist 2>/dev/null; then
    echo "Deployment config (CONF_FILE) must be written only through app_save_config." >&2
    return 1
  fi
  if grep -R -nE '(>|>>)[[:space:]]*/etc/[A-Za-z0-9_-]+-deploy\.conf' impl dist 2>/dev/null; then
    echo "Deployment config paths must come from app_conf_file, not be hardcoded." >&2
    return 1
  fi
  awk '
      /^app_save_config$/ { saw_save=1 }
      END {
        if (!saw_save) {
          print "Every app must persist deployment config through app_save_config." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_blog.sh impl/install_cpa_stack.sh impl/install_cyberstrikeai.sh \
      impl/install_newapi.sh impl/install_sub2api.sh impl/install_tickflow.sh impl/install_vaultwarden.sh
}

check_config_crlf_handling() {
  local tmp_dir conf
  tmp_dir="$(mktemp -d)"
  conf="${tmp_dir}/deploy.conf"
  printf ' FOO = "bar"\r\n\tBAZ\t= qux \r\nQUOTED = " spaced value "\r\n' > "$conf"

  cat > "${tmp_dir}/stat" <<'STUB'
#!/usr/bin/env bash
case "${2:-}" in
  %U) echo root ;;
  %a) echo 600 ;;
  *) /usr/bin/stat "$@" ;;
esac
STUB
  chmod +x "${tmp_dir}/stat"

  PATH="${tmp_dir}:$PATH" "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    FOO=""
    BAZ=""
    QUOTED=""
    load_config_file "$1" FOO BAZ QUOTED
    [[ "$FOO" == "bar" ]] || { printf "FOO contained unexpected bytes: " >&2; printf "%s" "$FOO" | od -An -tx1 >&2; exit 1; }
    [[ "$BAZ" == "qux" ]] || { printf "BAZ contained unexpected bytes: " >&2; printf "%s" "$BAZ" | od -An -tx1 >&2; exit 1; }
    [[ "$QUOTED" == " spaced value " ]] || { printf "QUOTED contained unexpected bytes: " >&2; printf "%s" "$QUOTED" | od -An -tx1 >&2; exit 1; }
    sanitized="$(sanitize_conf_val $'"'"'one\ntwo'"'"')"
    [[ "$sanitized" == "one" ]] || { printf "sanitize_conf_val returned unexpected bytes: " >&2; printf "%s" "$sanitized" | od -An -tx1 >&2; exit 1; }
  ' _ "$conf"

  rm -rf "$tmp_dir"
}

check_config_write_failure_cleanup() {
  local tmp_dir conf
  tmp_dir="$(mktemp -d)"
  conf="${tmp_dir}/deploy.conf"

  cat > "${tmp_dir}/chmod" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  chmod +x "${tmp_dir}/chmod"

  "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    FOO="bar"
    PATH="$1:$PATH"
    set +e
    write_config_file "$2" FOO
    status=$?
    set -e
    [[ "$status" -ne 0 ]] || { echo "write_config_file unexpectedly succeeded" >&2; exit 1; }
    if find "$(dirname "$2")" -maxdepth 1 -name "$(basename "$2").tmp.*" -type f | grep -q .; then
      echo "write_config_file left a temporary config file behind" >&2
      find "$(dirname "$2")" -maxdepth 1 -name "$(basename "$2").tmp.*" -type f >&2
      exit 1
    fi
  ' _ "$tmp_dir" "$conf"

  rm -f "${tmp_dir}/chmod"
  cat > "${tmp_dir}/chown" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  chmod +x "${tmp_dir}/chown"

  "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    FOO="bar"
    PATH="$1:$PATH"
    set +e
    write_config_file "$2" FOO
    status=$?
    set -e
    [[ "$status" -ne 0 ]] || { echo "write_config_file unexpectedly ignored chown failure" >&2; exit 1; }
    if find "$(dirname "$2")" -maxdepth 1 -name "$(basename "$2").tmp.*" -type f | grep -q .; then
      echo "write_config_file left a temporary config file behind after chown failure" >&2
      find "$(dirname "$2")" -maxdepth 1 -name "$(basename "$2").tmp.*" -type f >&2
      exit 1
    fi
  ' _ "$tmp_dir" "$conf"

  rm -rf "$tmp_dir"
}

check_unsafe_config_loads_fail_closed() {
  if grep -R -n 'load_config_file "\$CONF_FILE" "\${CONFIG_KEYS\[@\]}" || return 0' impl dist 2>/dev/null; then
    echo "App config loaders must not ignore unsafe or unreadable config files." >&2
    return 1
  fi
  awk '
      /error "\$\(t error\.config_owner "\$conf_file"\)"/ { saw_owner=1 }
      /error "\$\(t error\.config_permission "\$conf_file"\)"/ { saw_permission=1 }
      /warn "\$\(t warn\.config_(owner|permission)/ { saw_warn=1 }
      END {
        if (!(saw_owner && saw_permission) || saw_warn) {
          print "Unsafe config ownership or permissions must fail closed with config errors." > "/dev/stderr"
          exit 1
        }
      }
    ' lib/config.sh
}

check_config_save_failures_are_explicit() {
  awk '
      /write_config_file\(\)/ { in_func=1; saw_tmp=0; saw_tmp_return=0; saw_chmod=0; saw_mv=0; saw_cleanup=0; next }
      in_func && /if ! tmp_file="\$\(mktemp "\$\{conf_file\}\.tmp\.XXXXXX"\)"; then/ { saw_tmp=1 }
      in_func && saw_tmp && /return 1/ { saw_tmp_return=1 }
      in_func && /chmod 600 "\$tmp_file"/ { saw_chmod=1 }
      in_func && /mv "\$tmp_file" "\$conf_file"/ { saw_mv=1 }
      in_func && /rm -f "\$tmp_file"/ { saw_cleanup=1 }
      in_func && /^}/ {
        if (!(saw_tmp && saw_tmp_return && saw_chmod && saw_mv && saw_cleanup)) {
          printf "%s write_config_file must report temp creation failures, secure, replace, and clean up temporary config files\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' lib/config.sh dist/install_newapi.sh
  awk '
      /error\.config_write/ { saw_key=1 }
      END {
        if (!saw_key) {
          print "Config save failures must have a shared error message." > "/dev/stderr"
          exit 1
        }
      }
    ' lib/i18n.sh dist/install_newapi.sh
  awk '
      /^(app_)?save_config\(\)/ { in_func=1; saw_if=0; saw_error=0; next }
      in_func && /write_config_file/ { saw_if=1 }
      in_func && /error.*config_write/ { saw_error=1 }
      in_func && /^}/ {
        if (!(saw_if && saw_error)) {
          printf "%s save_config must report config write failures explicitly\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh impl/install_cyberstrikeai.sh impl/install_vaultwarden.sh impl/install_blog.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_cyberstrikeai.sh dist/install_vaultwarden.sh dist/install_blog.sh lib/app.sh
}

check_no_unsupported_systemctl_options() {
  if grep -R -nE 'systemctl[[:space:]]+stop[[:space:]][^;&|]*--timeout' impl lib dist 2>/dev/null; then
    echo "systemctl stop does not support --timeout; use the default blocking stop behavior." >&2
    return 1
  fi
}

check_no_fixed_tmp_downloads() {
  if grep -R -n '/tmp/hugo\.deb' impl dist 2>/dev/null; then
    echo "Use mktemp for Hugo package downloads instead of a fixed /tmp path." >&2
    return 1
  fi
}

check_keyring_writes_are_atomic() {
  if grep -R -nE '(^[[:space:]]*-o /usr/share/postgresql-common/pgdg/|gpg .*--dearmor -o /usr/share/keyrings/)' impl dist 2>/dev/null; then
    echo "Write apt keyrings to a temporary file before replacing the final keyring." >&2
    return 1
  fi
  awk '
      /(postgres_keyring_dir|redis_keyring_dir)=/ { saw_dir_var=1 }
      /if ! install -d "\$(pg_keyring_dir|redis_keyring_dir)"; then/ { saw_dir_if=1 }
      /error "\$\(t app\.sub2api\.error\.(postgres|redis)_keyring_dir "\$(pg_keyring_dir|redis_keyring_dir)"\)"/ { saw_dir_error=1 }
      /if ! (pg_key_tmp|redis_key_tmp)="?\$\(mktemp/ { saw_tmp=1 }
      /error "\$\(t app\.sub2api\.error\.(postgres|redis)_key\)"/ { saw_tmp_error=1 }
      /(curl .* -o "\$pg_key_tmp"|gpg .* --dearmor -o "\$redis_key_tmp")/ { saw_write=1 }
      /mv "\$(pg_key_tmp|redis_key_tmp)" "\$(pg_keyring|redis_keyring)"/ { saw_mv=1 }
      /rm -f "\$(pg_key_tmp|redis_key_tmp)"/ { saw_cleanup=1 }
      END {
        if (!(saw_dir_var && saw_dir_if && saw_dir_error && saw_tmp && saw_tmp_error && saw_write && saw_mv && saw_cleanup)) {
          print "Apt keyring writes must prepare directories, stage, replace, and clean up temporary files." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_apt_sources_are_atomic() {
  if grep -R -nE '^[[:space:]]*(echo|printf).*>[[:space:]]*/etc/apt/sources\.list\.d/' impl dist 2>/dev/null; then
    echo "Apt source lists must be written through temporary files before replacement." >&2
    return 1
  fi
  awk '
      /apt_source_dir="\/etc\/apt\/sources\.list\.d"/ { saw_dir_var=1 }
      /if ! mkdir -p "\$apt_source_dir"; then/ { saw_dir_if=1 }
      /error "\$\(t app\.sub2api\.error\.(postgres|redis)_source_dir "\$apt_source_dir"\)"/ { saw_dir_error=1 }
      /if ! (pg_source_tmp|redis_source_tmp)=\$\(mktemp/ { saw_tmp=1 }
      /error "\$\(t app\.sub2api\.error\.(postgres|redis)_source\)"/ { saw_tmp_error=1 }
      /mv "\$(pg_source_tmp|redis_source_tmp)" "\$(pg_source_list|redis_source_list)"/ { saw_mv=1 }
      /rm -f "\$(pg_source_tmp|redis_source_tmp)"/ { saw_cleanup=1 }
      END {
        if (!(saw_dir_var && saw_dir_if && saw_dir_error && saw_tmp && saw_tmp_error && saw_mv && saw_cleanup)) {
          print "Apt source list writes must prepare directories, stage, replace, and clean up temporary files." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_iptables_rules_are_atomic() {
  if grep -R -nE '^[[:space:]]*iptables-save > /etc/iptables/rules\.v4' impl dist 2>/dev/null; then
    echo "iptables rules must be saved to a temporary file before replacing rules.v4." >&2
    return 1
  fi
  awk '
      /iptables_dir="\/etc\/iptables"/ { saw_dir=1 }
      /if mkdir -p "\$iptables_dir"; then/ { saw_dir_if=1 }
      /warn "\$\(t app\.(newapi|sub2api)\.warn\.iptables_write_failed\)"/ { saw_warn=1 }
      /if ! iptables_tmp=\$\(mktemp "\$\{iptables_rules\}\.XXXXXX"\); then/ { saw_tmp=1 }
      /iptables-save > "\$iptables_tmp"/ { saw_save=1 }
      /mv "\$iptables_tmp" "\$iptables_rules"/ { saw_mv=1 }
      /rm -f "\$iptables_tmp"/ { saw_cleanup=1 }
      END {
        if (!(saw_dir && saw_dir_if && saw_warn && saw_tmp && saw_save && saw_mv && saw_cleanup)) {
          print "iptables rules writes must prepare directories, stage, replace, and clean up temporary files." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh dist/install_newapi.sh dist/install_sub2api.sh
}

check_netfilter_persistent_save_reports_failures() {
  if grep -R -nE 'netfilter-persistent save 2>/dev/null( && success .*\\|\\| true|[[:space:]]*\\[?;?)' \
      impl/install_newapi.sh impl/install_sub2api.sh impl/install_vaultwarden.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "netfilter-persistent save failures must not be silently ignored." >&2
    return 1
  fi
  awk '
      /if command -v netfilter-persistent &>\/dev\/null; then/ {
        in_block=1; saw_save=0; saw_success=0; saw_warn=0
        block_indent=$0; sub(/[^ \t].*/, "", block_indent)
        next
      }
      in_block && /if netfilter-persistent save 2>\/dev\/null; then/ { saw_save=1; next }
      in_block && /success "\$\(t app\.(newapi|sub2api|vaultwarden)\.success\.iptables_saved\)"/ { saw_success=1; next }
      in_block && /warn "\$\(t app\.(newapi|sub2api|vaultwarden)\.warn\.iptables_not_persisted\)"/ { saw_warn=1; next }
      in_block && ($0 ~ ("^" block_indent "elif command -v iptables-save ") || $0 == (block_indent "else")) {
        if (!(saw_save && saw_success && saw_warn)) {
          printf "%s netfilter-persistent save must report both success and failure outcomes\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh impl/install_vaultwarden.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_vaultwarden.sh
}

check_random_head_pipelines_handle_sigpipe() {
  if grep -R -nE 'rand .*\\|.*head -c [0-9]+\\)$|tr -dc .*\\| head -c [0-9]+\\)$' impl dist 2>/dev/null; then
    echo "Random byte pipelines ending in head -c need an explicit successful terminator under pipefail." >&2
    return 1
  fi
}

check_summary_ip_detection_has_fallback() {
  if grep -R -n 'hostname -I .*| awk '\''{print $1}'\''' \
      impl/install_blog.sh impl/install_newapi.sh impl/install_sub2api.sh impl/install_vaultwarden.sh impl/install_cyberstrikeai.sh \
      dist/install_blog.sh dist/install_newapi.sh dist/install_sub2api.sh dist/install_vaultwarden.sh dist/install_cyberstrikeai.sh 2>/dev/null \
      | grep -v '|| true'; then
    echo "Summary IP detection must tolerate hostname -I failures and provide YOUR_SERVER_IP fallback." >&2
    return 1
  fi
  local file
  for file in impl/install_blog.sh impl/install_newapi.sh impl/install_sub2api.sh impl/install_vaultwarden.sh impl/install_cyberstrikeai.sh \
      dist/install_blog.sh dist/install_newapi.sh dist/install_sub2api.sh dist/install_vaultwarden.sh dist/install_cyberstrikeai.sh; do
    awk '
        /hostname -I 2>\/dev\/null \| awk '\''\{print \$1\}'\'' \|\| true/ { saw_safe=1 }
        /YOUR_SERVER_IP/ { saw_fallback=1 }
        END {
          if (!(saw_safe && saw_fallback)) {
            printf "%s summary IP detection must use a non-fatal hostname pipeline and fallback value\n", FILENAME > "/dev/stderr"
            exit 1
          }
        }
      ' "$file"
  done
}

check_systemctl_status_diagnostics_are_nonfatal() {
  awk '
      /systemctl status .*\| head .*\| sed/ {
        pending=1
        pending_line=FNR
        if (/&&|\|\| true/) {
          pending=0
        }
        next
      }
      pending {
        if (/\|\| (true|echo|warn|error)/) {
          pending=0
          next
        }
        printf "%s:%d systemctl status diagnostic pipelines must be non-fatal under pipefail.\n", FILENAME, pending_line > "/dev/stderr"
        exit 1
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh impl/install_vaultwarden.sh impl/install_cyberstrikeai.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_vaultwarden.sh dist/install_cyberstrikeai.sh
}

check_status_commands_allow_non_root() {
  awk '
      /app\.sub2api\.warn\.non_root_status/ { saw_sub2api=1 }
      /app\.cyberstrikeai\.warn\.non_root_status/ { saw_csai=1 }
      /app\.tickflow\.warn\.non_root_status/ { saw_tickflow=1 }
      END {
        if (!(saw_sub2api && saw_csai && saw_tickflow)) {
          print "Status commands that run without root must warn when details may be incomplete." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/sub2api.sh apps/cyberstrikeai.sh apps/tickflow.sh
  awk '
      /preflight_check\(\)/ { in_preflight=1; saw_status_exemption=0; next }
      in_preflight && /status/ && /\$EUID/ { saw_status_exemption=1 }
      in_preflight && /^}/ {
        if (!saw_status_exemption) {
          printf "%s preflight must allow the status action without root\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_preflight=0
      }
      /do_status\(\)/ { in_status=1; saw_warn=0; next }
      in_status && /warn "\$\(t app\.(newapi|sub2api|cyberstrikeai|tickflow)\.warn\.non_root_status "\$0"\)"/ { saw_warn=1 }
      in_status && /^}/ {
        if (!saw_warn) {
          printf "%s status must warn when running without root\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_status=0
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh impl/install_cyberstrikeai.sh impl/install_tickflow.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_cyberstrikeai.sh dist/install_tickflow.sh
}

check_api_status_directory_sizes_are_nonfatal() {
  awk '
      /do_status\(\)/ { in_status=1; next }
      in_status && /^}/ {
        if (!(saw_data && saw_db && saw_backup)) {
          printf "%s NewAPI status directory sizes must fall back instead of failing under pipefail\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_status=0
      }
      in_status && /data_size=\$\(du -sh "\$DATA_DIR" 2>\/dev\/null \| awk '\''\{print \$1\}'\'' \|\| t app\.newapi\.status\.unknown\)/ { saw_data=1 }
      in_status && /db_size=\$\(du -sh "\$\{DATA_DIR\}\/one-api\.db" 2>\/dev\/null \| awk '\''\{print \$1\}'\'' \|\| t app\.newapi\.status\.unknown\)/ { saw_db=1 }
      in_status && /bak_total_size=\$\(du -sh "\$BACKUP_DIR" 2>\/dev\/null \| awk '\''\{print \$1\}'\'' \|\| t app\.newapi\.status\.unknown\)/ { saw_backup=1 }
    ' impl/install_newapi.sh dist/install_newapi.sh
  awk '
      /do_status\(\)/ { in_status=1; next }
      in_status && /^}/ {
        if (!(saw_dir && saw_backup)) {
          printf "%s Sub2API status directory sizes must fall back instead of failing under pipefail\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_status=0
      }
      in_status && /_sz=\$\(du -sh "\$_d" 2>\/dev\/null \| awk '\''\{print \$1\}'\'' \|\| t app\.sub2api\.status\.unknown\)/ { saw_dir=1 }
      in_status && /bak_total_size=\$\(du -sh "\$BACKUP_DIR" 2>\/dev\/null \| awk '\''\{print \$1\}'\'' \|\| t app\.sub2api\.status\.unknown\)/ { saw_backup=1 }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_framework_validator_errors_are_actionable() {
  awk '
      /^app_validate_port\(\)/ { in_port=1; next }
      in_port && /t error\.port_invalid/ { saw_port=1 }
      in_port && /^}/ { in_port=0 }
      /^app_validate_bool\(\)/ { in_bool=1; next }
      in_bool && /t error\.bool_invalid/ { saw_bool=1 }
      in_bool && /^}/ { in_bool=0 }
      /^app_validate_domain\(\)/ { in_domain=1; next }
      in_domain && /t error\.domain_invalid/ { saw_domain=1 }
      in_domain && /^}/ { in_domain=0 }
      END {
        if (!(saw_port && saw_bool && saw_domain)) {
          print "Framework validators must route invalid port, boolean, and domain values to actionable t error.* keys." > "/dev/stderr"
          exit 1
        }
      }
    ' lib/app.sh
  awk '
      /error\.port_invalid\)/ && /between 1 and 65535/ { saw_port=1 }
      /error\.bool_invalid\)/ && /true\/false, yes\/no, on\/off, or 1\/0/ { saw_bool=1 }
      /error\.domain_invalid\)/ && /DNS name/ { saw_domain=1 }
      END {
        if (!(saw_port && saw_bool && saw_domain)) {
          print "Framework fallback messages must give actionable guidance for invalid port, boolean, and domain values." > "/dev/stderr"
          exit 1
        }
      }
    ' lib/i18n.sh
}

check_api_ports_are_validated() {
  awk '
      /preflight_check\(\)/ { in_preflight=1; next }
      in_preflight && /^}/ {
        if (!saw_preflight) {
          printf "%s NewAPI preflight must validate PORT defaults\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_preflight=0
      }
      in_preflight && /_validate_config_values/ { saw_preflight=1 }
      /_validate_config_values\(\)/ { in_validate=1; next }
      in_validate && /app_validate_port/ { saw_valport=1 }
      in_validate && /^}/ { in_validate=0 }
      END {
        if (!(saw_preflight && saw_valport)) {
          printf "%s NewAPI must validate PORT range via _validate_config_values\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
  awk '
      /preflight_check\(\)/ { in_preflight=1; next }
      in_preflight && /^}/ {
        if (!saw_preflight) {
          printf "%s Sub2API preflight must validate PORT defaults\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_preflight=0
      }
      in_preflight && /_validate_config_values/ { saw_preflight=1 }
      /_validate_config_values\(\)/ { in_validate=1; next }
      in_validate && /app_validate_port/ { saw_valport=1 }
      in_validate && /^}/ { in_validate=0 }
      END {
        if (!(saw_preflight && saw_valport)) {
          printf "%s Sub2API must validate PORT range via _validate_config_values\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_nginx_domains_are_validated() {
  awk '
      /is_valid_dns_name\(\)/ { saw_helper=1 }
      /name=.*\{1:-\}/ { saw_name=1 }
      /\[\[ "\$name" != \*\.\.\* \]\] \|\| return 1/ { saw_dots=1 }
      /\[\[ "\$name" == \*\.\* \]\] \|\| return 1/ { saw_dot_required=1 }
      END {
        if (!(saw_helper && saw_name && saw_dots && saw_dot_required)) {
          print "Shared DNS validation helper must reject empty, overlong, malformed, and single-label server names." > "/dev/stderr"
          exit 1
        }
      }
    ' lib/network.sh
  awk '
      /app\.vaultwarden\.error\.domain_invalid/ { saw_vw=1 }
      /app\.blog\.error\.keep_days_invalid/ { saw_blog_keep_days=1 }
      END {
        if (!(saw_vw && saw_blog_keep_days)) {
          print "Nginx domain and Blog retention validation errors must be localized." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/vaultwarden.sh apps/blog.sh
  awk '
      /_validate_config_values\(\)/ { in_func=1; saw_domain=0; next }
      in_func && /app_validate_domain "CSAI_DOMAIN"/ { saw_domain=1 }
      in_func && /^}/ {
        if (!saw_domain) {
          printf "%s CyberStrikeAI must validate CSAI_DOMAIN via _validate_config_values\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
  awk '
      /_validate_config_values\(\)/ { in_func=1; saw_domain=0; next }
      in_func && /app_validate_domain "SUB2API_DOMAIN"/ { saw_domain=1 }
      in_func && /^}/ {
        if (!saw_domain) {
          printf "%s Sub2API must validate SUB2API_DOMAIN via _validate_config_values\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
  awk '
      /_validate_config_values\(\)/ { in_func=1; saw_domain=0; next }
      in_func && /is_valid_dns_name "\$VW_DOMAIN"/ { saw_domain=1 }
      in_func && /^}/ {
        if (!saw_domain) {
          printf "%s Vaultwarden must validate VW_DOMAIN via _validate_config_values\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
      /prompt "\$\(t app\.vaultwarden\.prompt\.domain\)"/ { in_prompt=1; next }
      in_prompt && /if ! is_valid_dns_name "\$_input"; then/ { saw_prompt=1 }
      in_prompt && /VW_DOMAIN="\$_input"/ {
        if (!saw_prompt) {
          printf "%s Vaultwarden domain wizard must use shared DNS validation\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_prompt=0
      }
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
  awk '
      /_validate_config_values\(\)/ { in_func=1; saw_domain=0; saw_bool=0; saw_theme_url=0; saw_site_url=0; saw_repo=0; saw_ref=0; saw_keep_days=0; next }
      in_func && /app_validate_domain "BLOG_DOMAIN"/ { saw_domain=1 }
      in_func && /app_validate_bool "ENABLE_CMS"/ { saw_bool=1 }
      in_func && /app_validate_https_url "THEME_REPO"/ { saw_theme_url=1 }
      in_func && /app_validate_http_url "CMS_SITE_URL"/ { saw_site_url=1 }
      in_func && /app_validate_github_repo "CMS_REPO"/ { saw_repo=1 }
      in_func && /app_validate_git_ref "CMS_BRANCH"/ { saw_ref=1 }
      in_func && /app\.blog\.error\.keep_days_invalid/ { saw_keep_days=1 }
      in_func && /^}/ {
        if (!(saw_domain && saw_bool && saw_theme_url && saw_site_url && saw_repo && saw_ref && saw_keep_days)) {
          printf "%s Blog must validate domain, CMS settings, and backup retention config values\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_blog.sh dist/install_blog.sh
}

check_config_value_validators() {
  "$BASH_BIN" -c '
    source lib/core.sh

    app_validate_domain DOMAIN api.example.com
    app_validate_systemd_name SERVICE_NAME new-api
    app_validate_system_name SERVICE_USER newapi
    app_validate_github_repo GITHUB_REPO QuantumNous/new-api
    app_validate_git_ref GITHUB_BRANCH release/v1.2.3
    app_validate_db_identifier PG_DB sub2api_db
    app_validate_http_url CMS_SITE_URL http://localhost:1313/admin/
    app_validate_https_url THEME_REPO https://github.com/CaiJimmy/hugo-theme-stack.git
    app_validate_goproxy GOPROXY "https://goproxy.cn,direct"
    app_validate_goproxy GOPROXY "https://proxy.example.com|direct"
    app_validate_image_repo VW_IMAGE_REPO vaultwarden/server
    app_validate_image_repo VW_IMAGE_REPO ghcr.io/dani-garcia/vaultwarden
    app_validate_image_repo VW_IMAGE_REPO registry.example.com:5000/team/vaultwarden
    app_validate_image_tag VW_IMAGE_TAG 1.36.0-alpine
    app_validate_sha256 EXTRACT_TOOL_SHA256 a58f4995f568d66d9908649d4df7fc8c36f72096ca5e01f4c2c4291285125685
    app_validate_email CERTBOT_EMAIL admin@example.com
    app_validate_release_version WEB_VAULT_VER 2024.6.2

    validator_must_reject() {
      local label="$1"
      shift
      if ( "$@" ) >/dev/null 2>&1; then
        echo "Validator unexpectedly accepted invalid ${label}." >&2
        exit 1
      fi
    }

    validator_must_reject systemd-name app_validate_systemd_name SERVICE_NAME "../new-api"
    validator_must_reject domain app_validate_domain DOMAIN "api example.com"
    validator_must_reject system-name app_validate_system_name SERVICE_USER "new api"
    validator_must_reject github-repo app_validate_github_repo GITHUB_REPO "owner/repo;rm"
    validator_must_reject git-ref app_validate_git_ref GITHUB_BRANCH "feature/../main"
    validator_must_reject db-identifier app_validate_db_identifier PG_DB "sub2api-db"
    validator_must_reject http-url app_validate_http_url CMS_SITE_URL "https://example.com/a path"
    validator_must_reject https-url app_validate_https_url THEME_REPO "git://github.com/owner/repo.git"
    validator_must_reject goproxy app_validate_goproxy GOPROXY "https://proxy.example.com,;rm"
    validator_must_reject image-repo-tag app_validate_image_repo VW_IMAGE_REPO "vaultwarden/server:latest"
    validator_must_reject image-repo-digest app_validate_image_repo VW_IMAGE_REPO "vaultwarden/server@sha256:abc"
    validator_must_reject image-repo-metachar app_validate_image_repo VW_IMAGE_REPO "vaultwarden/server;rm"
    validator_must_reject image-tag app_validate_image_tag VW_IMAGE_TAG "latest/amd64"
    validator_must_reject sha256 app_validate_sha256 EXTRACT_TOOL_SHA256 abc
    validator_must_reject email app_validate_email CERTBOT_EMAIL "admin@example.com;rm"
    validator_must_reject email-domain app_validate_email CERTBOT_EMAIL "admin@example"
    validator_must_reject release-version app_validate_release_version WEB_VAULT_VER "2024.6/evil"
  '

  local checks=(
    'impl/install_newapi.sh|app_validate_systemd_name "SERVICE_NAME" "$SERVICE_NAME"'
    'impl/install_newapi.sh|app_validate_domain "DOMAIN" "$DOMAIN"'
    'impl/install_newapi.sh|app_validate_system_name "SERVICE_USER" "$SERVICE_USER"'
    'impl/install_newapi.sh|app_validate_github_repo "GITHUB_REPO" "$GITHUB_REPO"'
    'impl/install_sub2api.sh|app_validate_db_identifier "PG_USER" "$PG_USER"'
    'impl/install_sub2api.sh|app_validate_db_identifier "PG_DB" "$PG_DB"'
    'impl/install_cyberstrikeai.sh|app_validate_git_ref "GITHUB_BRANCH" "$GITHUB_BRANCH"'
    'impl/install_cyberstrikeai.sh|app_validate_http_url "PIP_INDEX_URL" "$PIP_INDEX_URL"'
    'impl/install_cyberstrikeai.sh|app_validate_goproxy "GOPROXY" "$GOPROXY"'
    'impl/install_tickflow.sh|app_validate_git_ref "TICKFLOW_BRANCH" "$TICKFLOW_BRANCH"'
    'impl/install_vaultwarden.sh|app_validate_system_name "VW_USER" "$VW_USER"'
    'impl/install_vaultwarden.sh|app_validate_email "CERTBOT_EMAIL" "$CERTBOT_EMAIL"'
    'impl/install_vaultwarden.sh|app_validate_image_repo "VW_IMAGE_REPO" "$VW_IMAGE_REPO"'
    'impl/install_vaultwarden.sh|app_validate_image_tag "VW_IMAGE_TAG" "$VW_IMAGE_TAG"'
    'impl/install_vaultwarden.sh|app_validate_git_ref "EXTRACT_TOOL_COMMIT" "$EXTRACT_TOOL_COMMIT"'
    'impl/install_vaultwarden.sh|app_validate_sha256 "EXTRACT_TOOL_SHA256" "$EXTRACT_TOOL_SHA256"'
    'impl/install_vaultwarden.sh|app_validate_release_version "WEB_VAULT_VER" "$WEB_VAULT_VER"'
    'impl/install_blog.sh|app_validate_https_url "THEME_REPO" "$THEME_REPO"'
    'impl/install_blog.sh|app_validate_http_url "CMS_SITE_URL" "$CMS_SITE_URL"'
  )
  local check file pattern
  for check in "${checks[@]}"; do
    file="${check%%|*}"
    pattern="${check#*|}"
    if ! grep -Fq "$pattern" "$file"; then
      echo "${file} must validate config value with: ${pattern}" >&2
      return 1
    fi
  done
}

check_status_port_matches_are_bounded() {
  if grep -R -nF 'grep ":${PORT}"' \
      impl/install_newapi.sh impl/install_sub2api.sh dist/install_newapi.sh dist/install_sub2api.sh 2>/dev/null; then
    echo "API port owner detection must not use substring port matches." >&2
    return 1
  fi
  if grep -R -nF 'grep "${PORT}"' \
      impl/install_newapi.sh impl/install_sub2api.sh dist/install_newapi.sh dist/install_sub2api.sh 2>/dev/null; then
    echo "API firewall status checks must not use substring port matches." >&2
    return 1
  fi
  if grep -R -nF 'grep ":${VW_PORT}"' \
      impl/install_vaultwarden.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "Vaultwarden port owner detection must not use substring port matches." >&2
    return 1
  fi
  awk '
      index($0, "ss -ltn \"( sport = :$port )\"") { saw_listen=1 }
      index($0, "ss -ltnp \"( sport = :$port )\"") { saw_owner=1 }
      /lsof -iTCP:"\$port" -sTCP:LISTEN -Pn/ { saw_lsof=1 }
      END {
        if (!(saw_listen && saw_owner && saw_lsof)) {
          printf "%s shared port conflict helpers must use bounded port matches for listeners and owners\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' lib/network.sh dist/install_newapi.sh dist/install_sub2api.sh dist/install_vaultwarden.sh
  awk '
      /app_check_port_conflict "\$PORT"/ { saw_owner++ }
      /grep -E "\(\^\|\[\[:space:\]\]\)\$\{PORT\}\/tcp\(\[\[:space:\]\]\|\$\)"/ { saw_ufw++ }
      END {
        if (!(saw_owner >= 1 && saw_ufw >= 1)) {
          printf "%s API checks must use shared bounded PORT conflict detection and bounded UFW rules\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh dist/install_newapi.sh dist/install_sub2api.sh
  awk '
      /app_check_port_conflict "\$VW_PORT"/ { saw_owner++ }
      END {
        if (saw_owner < 2) {
          printf "%s Vaultwarden checks must use shared bounded VW_PORT conflict detection\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
}

check_go_tarball_failures_cleanup() {
  if grep -R -n 'tar -C /usr/local -xzf "$tmp"$' impl dist 2>/dev/null; then
    echo "Go tarball extraction failures must remove the downloaded temporary archive." >&2
    return 1
  fi
  if grep -R -n 'rm -rf /usr/local/go' impl dist 2>/dev/null; then
    echo "Do not remove the existing Go toolchain before the replacement archive is extracted." >&2
    return 1
  fi
  if grep -R -n 'mv "$old_go_backup" /usr/local/go 2>/dev/null || true' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "CyberStrikeAI Go toolchain rollback must validate restoring the previous /usr/local/go." >&2
    return 1
  fi
  if grep -R -nE '^[[:space:]]*ln -sf /usr/local/go/bin/(go|gofmt) /usr/local/bin/(go|gofmt)$' \
      impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "CyberStrikeAI Go tool symlinks must be staged before replacement." >&2
    return 1
  fi
  awk '
      /if ! tmp=\$\(mktemp\); then/ { saw_download_tmp=1 }
      /if ! extract_dir=\$\(mktemp -d \/usr\/local\/go\.extract\.XXXXXX\); then/ { saw_extract_tmp=1 }
      /if ! old_go_backup=\$\(mktemp -d \/usr\/local\/go\.previous\.XXXXXX\); then/ { saw_backup_tmp=1 }
      /if ! rmdir "\$old_go_backup"; then/ { saw_backup_rmdir=1 }
      /error "\$\(t app\.cyberstrikeai\.error\.(go_query|go_extract|go_failed)\)"/ { saw_tmp_error=1 }
      /restore_old_go_toolchain\(\)/ { in_func=1; saw_exists=0; saw_absent=0; saw_mv=0; next }
      in_func && /\[\[ -n "\$old_go_backup" && -e "\$old_go_backup" \]\]/ { saw_exists=1 }
      in_func && /\[\[ ! -e \/usr\/local\/go \]\]/ { saw_absent=1 }
      in_func && /mv "\$old_go_backup" \/usr\/local\/go/ { saw_mv=1 }
      in_func && /^}/ {
        if (!(saw_exists && saw_absent && saw_mv)) {
          printf "%s Go toolchain rollback helper must validate backup existence, target absence, and restore move\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
      END {
        if (!(saw_download_tmp && saw_extract_tmp && saw_backup_tmp && saw_backup_rmdir && saw_tmp_error)) {
          print "CyberStrikeAI Go installation must report download, extract, and backup temp path preparation failures." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
  awk '
      /write_tool_symlink\(\)/ { in_func=1; saw_atomic=0; saw_error=0; next }
      in_func && /atomic_symlink "\$target" "\$link_path"/ { saw_atomic=1 }
      in_func && /error "\$\(t app\.cyberstrikeai\.error\.go_failed\)"/ { saw_error=1 }
      in_func && /^}/ {
        if (!(saw_atomic && saw_error)) {
          printf "%s Go tool symlink helper must use atomic_symlink and report failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_optional_directory_cleanup_is_nonfatal() {
  if grep -R -nE '\[\[ (-n "\$old_go_backup"|-d "\$_wv_install_bak") \]\] && rm -rf' \
      impl/install_cyberstrikeai.sh impl/install_vaultwarden.sh \
      dist/install_cyberstrikeai.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "Optional directory cleanup must use explicit if branches so absent paths do not trip set -e." >&2
    return 1
  fi
}

check_backup_script_dir_failures_are_explicit() {
  awk '
      /_write_backup_script\(\)/ { in_newapi=1; saw_newapi_if=0; saw_newapi_error=0; next }
      in_newapi && /if ! mkdir -p "\$BACKUP_DIR"; then/ { saw_newapi_if=1 }
      in_newapi && /error "\$\(t app\.newapi\.error\.backup_dir_create "\$BACKUP_DIR"\)"/ { saw_newapi_error=1 }
      in_newapi && /local msg_start/ {
        if (!(saw_newapi_if && saw_newapi_error)) {
          printf "%s NewAPI backup-script generator must fail explicitly when the backup directory cannot be created\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_newapi=0
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
  awk '
      /_write_backup_script\(\)/ { in_sub2api=1; saw_sub2api_if=0; saw_sub2api_error=0; next }
      in_sub2api && /if ! mkdir -p "\$BACKUP_DIR"; then/ { saw_sub2api_if=1 }
      in_sub2api && /error "\$\(t app\.sub2api\.error\.backup_dir_create "\$BACKUP_DIR"\)"/ { saw_sub2api_error=1 }
      in_sub2api && /local msg_start/ {
        if (!(saw_sub2api_if && saw_sub2api_error)) {
          printf "%s Sub2API backup-script generator must fail explicitly when the backup directory cannot be created\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_sub2api=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_preupdate_backup_warnings_include_followup_guidance() {
  awk '
      /app\.newapi\.warn\.pre_backup_failed/ { saw_newapi=1 }
      /\/opt\/new-api-backups\/backup\.log/ { saw_newapi_log=1 }
      /\/usr\/local\/bin\/new-api-backup/ { saw_newapi_cmd=1 }
      /app\.sub2api\.warn\.pre_update_backup/ { saw_sub2api=1 }
      /\/opt\/sub2api-backups\/backup\.log/ { saw_sub2api_log=1 }
      /\/usr\/local\/bin\/sub2api-backup/ { saw_sub2api_cmd=1 }
      /app\.cyberstrikeai\.warn\.preupdate_backup/ { saw_csai=1 }
      /\/opt\/cyberstrike-ai\/logs\/backup\.log/ { saw_csai_log=1 }
      /\/usr\/local\/bin\/cyberstrike-ai-backup/ { saw_csai_cmd=1 }
      END {
        if (!(saw_newapi && saw_newapi_log && saw_newapi_cmd && saw_sub2api && saw_sub2api_log && saw_sub2api_cmd && saw_csai && saw_csai_log && saw_csai_cmd)) {
          print "Pre-update backup warnings must tell users where to inspect backup logs and how to run a manual backup." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/newapi.sh apps/sub2api.sh apps/cyberstrikeai.sh
  awk '
      /step "\$\(t app\.newapi\.step\.pre_backup\)"/ { in_newapi=1; saw_newapi_if=0; next }
      in_newapi && /if ! _backup_silent "pre-update"; then/ { saw_newapi_if=1 }
      in_newapi && /warn "\$\(t app\.newapi\.warn\.pre_backup_failed\)"/ {
        if (!saw_newapi_if) {
          printf "%s NewAPI pre-update backup warning must come from an explicit conditional\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_newapi=0
      }
      /step "\$\(t app\.sub2api\.step\.pre_update_backup\)"/ { in_sub2api=1; saw_sub2api_if=0; next }
      in_sub2api && /if ! _backup_silent "pre-update"; then/ { saw_sub2api_if=1 }
      in_sub2api && /warn "\$\(t app\.sub2api\.warn\.pre_update_backup\)"/ {
        if (!saw_sub2api_if) {
          printf "%s Sub2API pre-update backup warning must come from an explicit conditional\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_sub2api=0
      }
      /step "\$\(t app\.cyberstrikeai\.step\.preupdate_backup\)"/ { in_csai=1; saw_csai_if=0; next }
      in_csai && /if ! "\$BACKUP_SCRIPT"; then/ { saw_csai_if=1 }
      in_csai && /warn "\$\(t app\.cyberstrikeai\.warn\.preupdate_backup\)"/ {
        if (!saw_csai_if) {
          printf "%s CyberStrikeAI pre-update backup warning must come from an explicit conditional\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_csai=0
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh impl/install_cyberstrikeai.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_cyberstrikeai.sh
  awk '
      /_backup_silent\(\)/ { in_helper=1; saw_failed_flag=0; saw_pg_fail=0; saw_config_fail=0; saw_return=0; next }
      in_helper && /if ! mkdir -p "\$BACKUP_DIR"; then/ { saw_mkdir_if=1 }
      in_helper && /warn "\$\(t app\.sub2api\.warn\.backup_dir_unwritable "\$BACKUP_DIR"\)"/ { saw_mkdir_warn=1 }
      in_helper && /local backup_failed=0/ { saw_failed_flag=1 }
      in_helper && /_log_backup_helper "\$\(t app\.sub2api\.backup\.log\.pg_dump_failed\)"/ { saw_pg_fail_log=1 }
      in_helper && /warn "\$\(t app\.sub2api\.warn\.pg_dump_failed\)"/ { saw_pg_fail=1 }
      in_helper && /_log_backup_helper "\$\(t app\.sub2api\.backup\.log\.config_failed\)"/ { saw_config_fail_log=1 }
      in_helper && /warn "\$\(t app\.sub2api\.warn\.config_backup_failed\)"/ { saw_config_fail=1 }
      in_helper && /\[\[ "\$backup_failed" -eq 0 \]\]/ { saw_return=1 }
      in_helper && /^}/ {
        if (!(saw_mkdir_if && saw_mkdir_warn && saw_failed_flag && saw_pg_fail_log && saw_pg_fail && saw_config_fail_log && saw_config_fail && saw_return)) {
          printf "%s Sub2API silent backup helper must handle backup-directory creation failures, log backup failures, and propagate them after warning\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_helper=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_preupdate_backup_logs_match_guidance() {
  "$BASH_BIN" -c '
    set -euo pipefail
    for file in impl/install_newapi.sh dist/install_newapi.sh; do
      block=$(sed -n "/^_backup_silent()/,/^_print_install_summary()/p" "$file")
      grep -Fq '\''local backup_log="${BACKUP_DIR}/backup.log"'\'' <<<"$block" || {
        echo "$file NewAPI silent backup helper must declare backup.log output" >&2
        exit 1
      }
      grep -Fq "_log_backup_helper()" <<<"$block" || {
        echo "$file NewAPI silent backup helper must define a backup log helper" >&2
        exit 1
      }
      grep -Fq "[[ -d \"\$BACKUP_DIR\" ]] || return 1" <<<"$block" || {
        echo "$file NewAPI silent backup helper must guard log writes when the backup directory cannot be created" >&2
        exit 1
      }
      grep -Fq "if ! mkdir -p \"\$BACKUP_DIR\"; then" <<<"$block" || {
        echo "$file NewAPI silent backup helper must handle backup directory creation failures explicitly" >&2
        exit 1
      }
      grep -Fq "warn \"\$(t app.newapi.warn.silent_backup_dir_failed \"\$BACKUP_DIR\")\"" <<<"$block" || {
        echo "$file NewAPI silent backup helper must warn explicitly when the backup directory cannot be created" >&2
        exit 1
      }
      grep -Fq ">> \"\$backup_log\"" <<<"$block" || {
        echo "$file NewAPI silent backup helper must append lines to backup.log" >&2
        exit 1
      }
      grep -Fq "_log_backup_helper \"\$(t app.newapi.backup.log.data_missing \"\$DATA_DIR\")\"" <<<"$block" || {
        echo "$file NewAPI silent backup helper must log missing data directory failures" >&2
        exit 1
      }
      grep -Fq "_log_backup_helper \"\$(t app.newapi.backup.log.tar_failed)\"" <<<"$block" || {
        echo "$file NewAPI silent backup helper must log tar failures" >&2
        exit 1
      }
    done
    for file in impl/install_vaultwarden.sh dist/install_vaultwarden.sh; do
      block=$(sed -n "/^_backup_silent()/,/^do_backup()/p" "$file")
      grep -Fq '\''local backup_log="${VW_BACKUP_DIR}/backup.log"'\'' <<<"$block" || {
        echo "$file Vaultwarden silent backup helper must declare backup.log output" >&2
        exit 1
      }
      grep -Fq "_log_backup_helper()" <<<"$block" || {
        echo "$file Vaultwarden silent backup helper must define a backup log helper" >&2
        exit 1
      }
      grep -Fq "[[ -d \"\$VW_BACKUP_DIR\" ]] || return 1" <<<"$block" || {
        echo "$file Vaultwarden silent backup helper must guard log writes when the backup directory cannot be created" >&2
        exit 1
      }
      grep -Fq "if ! mkdir -p \"\$VW_BACKUP_DIR\"; then" <<<"$block" || {
        echo "$file Vaultwarden silent backup helper must handle backup directory creation failures explicitly" >&2
        exit 1
      }
      grep -Fq "warn \"\$(t app.vaultwarden.warn.backup_dir_failed \"\$VW_BACKUP_DIR\")\"" <<<"$block" || {
        echo "$file Vaultwarden silent backup helper must warn explicitly when the backup directory cannot be created" >&2
        exit 1
      }
      grep -Fq ">> \"\$backup_log\"" <<<"$block" || {
        echo "$file Vaultwarden silent backup helper must append lines to backup.log" >&2
        exit 1
      }
      grep -Fq "_log_backup_helper \"\$(t app.vaultwarden.backup.script.data_missing \"\$VW_DATA_DIR\")\"" <<<"$block" || {
        echo "$file Vaultwarden silent backup helper must log missing data directory failures" >&2
        exit 1
      }
      grep -Fq "_log_backup_helper \"\$(t app.vaultwarden.backup.script.failed)\"" <<<"$block" || {
        echo "$file Vaultwarden silent backup helper must log archive failures" >&2
        exit 1
      }
    done
  '
}

check_mutating_actions_acquire_locks() {
  "$BASH_BIN" -c '
    set -euo pipefail
    for file in impl/install_*.sh; do
      for action in install update backup uninstall; do
        if grep -q "do_${action}()" "$file"; then
          if ! awk -v fn="do_${action}()" "
              index(\$0, fn \" {\") == 1 { in_func=1; saw_lock=0; next }
              in_func && /acquire_lock/ { saw_lock=1 }
              in_func && /^}/ {
                if (!saw_lock) {
                  printf \"%s %s does not acquire a deployment lock\\n\", FILENAME, fn > \"/dev/stderr\"
                  exit 1
                }
                in_func=0
              }
            " "$file"; then
            exit 1
          fi
        fi
      done
    done
  '
  awk '
      /deploy_add_exit_handler\(\)/ { in_add=1; saw_array_append=0; saw_trap=0; next }
      in_add && /__DEPLOY_EXIT_HANDLERS\+=\("\$handler"\)/ { saw_array_append=1 }
      in_add && /trap '\''__deploy_run_exit_handlers'\'' EXIT/ { saw_trap=1 }
      in_add && /^}/ {
        if (!(saw_array_append && saw_trap)) {
          print "Exit handlers must be appended and installed through the shared dispatcher." > "/dev/stderr"
          exit 1
        }
        in_add=0
      }
      /__deploy_run_exit_handlers\(\)/ { in_run=1; saw_status=0; saw_reverse=0; saw_handler_call=0; next }
      in_run && /local status=\$\?/ { saw_status=1 }
      in_run && /index=\$\{#__DEPLOY_EXIT_HANDLERS\[@\]\} - 1/ { saw_reverse=1 }
      in_run && /"\$handler" \|\| true/ { saw_handler_call=1 }
      in_run && /^}/ {
        if (!(saw_status && saw_reverse && saw_handler_call)) {
          print "Exit handler dispatcher must preserve exit status and run handlers best-effort in reverse order." > "/dev/stderr"
          exit 1
        }
        in_run=0
      }
      /acquire_lock\(\)/ { in_func=1; saw_mkdir=0; saw_error=0; saw_exec=0; saw_handler=0; next }
      in_func && /if ! mkdir -p "\$\(dirname "\$lock_file"\)"; then/ { saw_mkdir=1 }
      in_func && /if ! exec 9>"\$lock_file"; then/ { saw_exec=1 }
      in_func && /error "\$\(t error\.lock_failed "\$lock_file"\)"/ { saw_error=1 }
      in_func && /deploy_add_exit_handler release_lock/ { saw_handler=1 }
      in_func && /trap '\''release_lock'\'' EXIT/ {
        print "Lock acquisition must use deploy_add_exit_handler instead of replacing EXIT trap." > "/dev/stderr"
        exit 1
      }
      in_func && /^}/ {
        if (!(saw_mkdir && saw_exec && saw_error && saw_handler)) {
          print "Lock acquisition must report creation failures and register lock release with the shared exit handler stack." > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' lib/lock.sh dist/install_newapi.sh

  local handler_tmp handler_status handler_output
  handler_tmp="$(mktemp -d)"
  set +e
  HANDLER_LOG="${handler_tmp}/handlers.log" "$BASH_BIN" -c '
    source lib/core.sh
    h1() { echo h1 >> "$HANDLER_LOG"; }
    h2() { echo h2 >> "$HANDLER_LOG"; }
    deploy_add_exit_handler h1
    deploy_add_exit_handler h2
    exit 7
  '
  handler_status=$?
  set -e
  handler_output="$(cat "${handler_tmp}/handlers.log" 2>/dev/null || true)"
  rm -rf "$handler_tmp"
  [[ "$handler_status" -eq 7 ]] || {
    echo "Exit handler dispatcher must preserve the original exit status." >&2
    return 1
  }
  [[ "$handler_output" == $'h2\nh1' ]] || {
    echo "Exit handler dispatcher must run handlers in reverse registration order." >&2
    echo "$handler_output" >&2
    return 1
  }
}

check_update_backs_up_before_stop() {
  local file
  for file in impl/install_newapi.sh impl/install_sub2api.sh; do
    awk '
      /local BAK_PATH=/ { seen_bak=1; seen_cp=0 }
      seen_bak && index($0, "_backup_current_binary \"$BAK_PATH\"") { seen_cp=1 }
      seen_bak && index($0, "systemctl stop \"$SERVICE_NAME\"") {
        if (!seen_cp) {
          printf "%s stops the service before backing up the current binary\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' "$file"
  done
}

check_update_binary_backups_are_atomic() {
  if grep -R -nE '^[[:space:]]*cp "\$(BIN_PATH|VW_BIN)" "?\$\{?(BAK_PATH|VW_BIN)\}?' \
      impl/install_newapi.sh impl/install_sub2api.sh impl/install_vaultwarden.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "Update binary backups must copy to a temporary file before replacing the final backup path." >&2
    return 1
  fi
  awk '
      /_backup_current_binary\(\)|backup_vaultwarden_binary\(\)/ { in_func=1; saw_tmp=0; saw_tmp_error=0; saw_cp=0; saw_mv=0; saw_cleanup=0; saw_atomic=0; saw_app_helper=0; next }
      in_func && /atomic_copy_file "\$(BIN_PATH|VW_BIN)" "\$backup_path"/ { saw_atomic=1 }
      in_func && /app_binary_backup_current "\$backup_path"/ { saw_app_helper=1 }
      in_func && /if ! backup_tmp=\$\(mktemp "\$\{backup_path\}\.XXXXXX"\); then/ { saw_tmp=1 }
      in_func && /error "\$\(t app\.(newapi|sub2api|vaultwarden)\.error\.binary_install/ { saw_tmp_error=1 }
      in_func && /cp "\$(BIN_PATH|VW_BIN)" "\$backup_tmp"/ { saw_cp=1 }
      in_func && /mv "\$backup_tmp" "\$backup_path"/ { saw_mv=1 }
      in_func && /rm -f "\$backup_tmp"/ { saw_cleanup=1 }
      in_func && /^}/ {
        if (!((saw_tmp && saw_tmp_error && saw_cp && saw_mv && saw_cleanup) || (saw_atomic && saw_tmp_error) || (saw_app_helper && saw_tmp_error))) {
          printf "%s binary backup helper must report temp creation failures, stage, replace, and clean up temporary backups\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh impl/install_vaultwarden.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_vaultwarden.sh
}

check_old_backup_cleanup_reports_failures() {
  local file
  awk '
      /app\.cyberstrikeai\.warn\.cleanup_old_binary_failed/ { saw_warn_key=1 }
      /app\.cyberstrikeai\.info\.cleaned_old_binaries/ { saw_count_key=1 }
      END {
        if (!(saw_warn_key && saw_count_key)) {
          print "CyberStrikeAI old binary cleanup messages must be localized." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/cyberstrikeai.sh
  for file in impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh; do
    awk '
        /while IFS= read -r -d '\'''\'' _old_bak; do/ { saw_loop=1 }
        /warn "\$\(t app\.cyberstrikeai\.warn\.cleanup_old_binary_failed "\$_old_bak"\)"/ { saw_warn=1 }
        /info "\$\(t app\.cyberstrikeai\.info\.cleaned_old_binaries "\$_cleaned_old"\)"/ { saw_count=1 }
        /xargs -r rm -f/ {
          printf "%s CyberStrikeAI must not silently batch-remove old binary backups\n", FILENAME > "/dev/stderr"
          exit 1
        }
        END {
          if (!(saw_loop && saw_warn && saw_count)) {
            printf "%s CyberStrikeAI old binary backup cleanup must report per-file failures and count successful removals\n", FILENAME > "/dev/stderr"
            exit 1
          }
        }
      ' "$file"
  done
  for file in impl/install_newapi.sh dist/install_newapi.sh; do
    awk '
        /for _old_bak in "\$\{_old_baks\[@\]\}"/ { saw_loop=1 }
        /warn "\$\(t app\.newapi\.warn\.cleanup_old_failed "\$_old_bak"\)"/ { saw_warn=1 }
        /info "\$\(t app\.newapi\.info\.cleaned_old "\$_cleaned_old"\)"/ { saw_count=1 }
        /rm -f "\$\{_old_baks\[@\]\}"/ {
          printf "%s NewAPI must not silently batch-remove old binary backups\n", FILENAME > "/dev/stderr"
          exit 1
        }
        END {
          if (!(saw_loop && saw_warn && saw_count)) {
            printf "%s NewAPI old binary backup cleanup must report per-file failures and count successful removals\n", FILENAME > "/dev/stderr"
            exit 1
          }
        }
      ' "$file"
  done
  for file in impl/install_sub2api.sh dist/install_sub2api.sh; do
    awk '
        /for _old_bak in "\$\{_old_baks\[@\]\}"/ { saw_loop=1 }
        /warn "\$\(t app\.sub2api\.warn\.cleanup_old_binary_failed "\$_old_bak"\)"/ { saw_warn=1 }
        /info "\$\(t app\.sub2api\.info\.cleaned_old_binaries "\$_cleaned_old"\)"/ { saw_count=1 }
        /rm -f "\$\{_old_baks\[@\]\}"/ {
          printf "%s Sub2API must not silently batch-remove old binary backups\n", FILENAME > "/dev/stderr"
          exit 1
        }
        END {
          if (!(saw_loop && saw_warn && saw_count)) {
            printf "%s Sub2API old binary backup cleanup must report per-file failures and count successful removals\n", FILENAME > "/dev/stderr"
            exit 1
          }
        }
      ' "$file"
  done
  for file in impl/install_vaultwarden.sh dist/install_vaultwarden.sh; do
    awk '
        /for _old_bak in "\$\{_old_baks\[@\]\}"/ { saw_binary_loop=1 }
        /warn "\$\(t app\.vaultwarden\.warn\.cleanup_old_binary_failed "\$_old_bak"\)"/ { saw_binary_warn=1 }
        /info "\$\(t app\.vaultwarden\.info\.cleaned_old_binaries "\$_cleaned_old"\)"/ { saw_binary_count=1 }
        /for _old_wv_bak in "\$\{_old_wv_baks\[@\]\}"/ { saw_web_loop=1 }
        /warn "\$\(t app\.vaultwarden\.warn\.cleanup_old_webvault_failed "\$_old_wv_bak"\)"/ { saw_web_warn=1 }
        /info "\$\(t app\.vaultwarden\.info\.cleaned_webvault_backups "\$_cleaned_wv"\)"/ { saw_web_count=1 }
        /rm -f "\$\{_old_baks\[@\]\}"/ || /rm -rf "\$\{_old_wv_baks\[@\]\}"/ {
          printf "%s Vaultwarden must not silently batch-remove old backups\n", FILENAME > "/dev/stderr"
          exit 1
        }
        END {
          if (!(saw_binary_loop && saw_binary_warn && saw_binary_count && saw_web_loop && saw_web_warn && saw_web_count)) {
            printf "%s Vaultwarden old backup cleanup must report per-path failures and count successful removals\n", FILENAME > "/dev/stderr"
            exit 1
          }
        }
      ' "$file"
  done
}

check_uninstall_binary_cleanup_reports_failures() {
  if grep -R -nE 'find "\$INSTALL_DIR" -maxdepth 1 .* -delete 2>/dev/null \|\| true|find "\$\(dirname "\$VW_BIN"\)" -maxdepth 1 .* -delete 2>/dev/null \|\| true' \
      impl/install_newapi.sh impl/install_sub2api.sh impl/install_vaultwarden.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "Uninstall binary cleanup must report per-path removal failures instead of ignoring find -delete errors." >&2
    return 1
  fi
  awk '
      /do_uninstall\(\)/ { in_uninstall=1; saw_loop=0; saw_warn=0; next }
      in_uninstall && /while IFS= read -r -d '\'''\'' _cleanup_path; do/ { saw_loop=1 }
      in_uninstall && /warn "\$\(t app\.newapi\.warn\.cleanup_old_failed "\$_cleanup_path"\)"/ { saw_warn=1 }
      in_uninstall && /success "\$\(t app\.newapi\.success\.removed_binary\)"/ {
        if (!(saw_loop && saw_warn)) {
          printf "%s NewAPI uninstall binary cleanup must warn on per-path removal failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_uninstall=0
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
  awk '
      /do_uninstall\(\)/ { in_uninstall=1; saw_file_loop=0; saw_dir_loop=0; saw_warn=0; next }
      in_uninstall && /-type f -print0/ { saw_file_loop=1 }
      in_uninstall && /-type d -print0/ { saw_dir_loop=1 }
      in_uninstall && /warn "\$\(t app\.sub2api\.warn\.cleanup_old_binary_failed "\$_cleanup_path"\)"/ { saw_warn=1 }
      in_uninstall && /success "\$\(t app\.sub2api\.success\.removed_binary\)"/ {
        if (!(saw_file_loop && saw_dir_loop && saw_warn)) {
          printf "%s Sub2API uninstall binary cleanup must warn on file and directory removal failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_uninstall=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
  awk '
      /do_uninstall\(\)/ { in_uninstall=1; saw_loop=0; saw_warn=0; next }
      in_uninstall && /while IFS= read -r -d '\'''\'' _cleanup_path; do/ { saw_loop=1 }
      in_uninstall && /warn "\$\(t app\.vaultwarden\.warn\.cleanup_old_binary_failed "\$_cleanup_path"\)"/ { saw_warn=1 }
      in_uninstall && /success "\$\(t app\.vaultwarden\.success\.removed_binary\)"/ {
        if (!(saw_loop && saw_warn)) {
          printf "%s Vaultwarden uninstall binary cleanup must warn on per-path removal failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_uninstall=0
      }
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
}

check_backup_temp_moves_handle_failure() {
  if grep -R -nE '^[[:space:]]*mv "\$[^"]*(TMP|tmp|ARCHIVE_TMP|archive_tmp|PG_TMP|pg_tmp|CONF_TMP|conf_tmp|DATA_TMP|data_tmp|DUMP_TMP|dump_tmp)[^"]*" "\$[^"]*(ARCHIVE|archive|FILE|file)' impl dist 2>/dev/null; then
    echo "Backup temporary files must be removed when the final move fails." >&2
    return 1
  fi
}

check_binary_replacements_handle_failure() {
  if grep -R -nE '^[[:space:]]*(mv "\$TMP_(BIN|ARCHIVE)" "\$BIN_PATH"|chmod \+x "\$BIN_PATH"|chown "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$BIN_PATH")$' \
      impl/install_newapi.sh impl/install_sub2api.sh dist/install_newapi.sh dist/install_sub2api.sh 2>/dev/null; then
    echo "Binary replacements must clean up candidates and restore backups on move, chmod, and chown failures." >&2
    return 1
  fi
  if grep -R -n 'mv "$backup_path" "$BIN_PATH" 2>/dev/null || true' \
      impl/install_newapi.sh impl/install_sub2api.sh dist/install_newapi.sh dist/install_sub2api.sh 2>/dev/null; then
    echo "Binary candidate installs must validate moving backups back into place." >&2
    return 1
  fi
  awk '
      /_install_binary_candidate\(\)/ { in_func=1; saw_helper=0; next }
      in_func && /app_binary_install_candidate "\$@"/ { saw_helper=1 }
      in_func && /^}/ {
        if (!saw_helper) {
          printf "%s install binary wrapper must call app_binary_install_candidate\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh dist/install_newapi.sh dist/install_sub2api.sh
  awk '
      /_restore_moved_binary_backup\(\)/ { in_func=1; saw_tmp=0; saw_tmp_return=0; saw_cp=0; saw_chmod=0; saw_chown=0; saw_mv=0; saw_cleanup=0; saw_app_helper=0; next }
      in_func && /app_binary_restore_moved_backup "\$1"/ { saw_app_helper=1 }
      in_func && /if ! restore_tmp=\$\(mktemp "\$\{BIN_PATH\}\.restore\.XXXXXX"\); then/ { saw_tmp=1 }
      in_func && saw_tmp && /return 1/ { saw_tmp_return=1 }
      in_func && /cp "\$backup_path" "\$restore_tmp"/ { saw_cp=1 }
      in_func && /chmod \+x "\$restore_tmp"/ { saw_chmod=1 }
      in_func && /chown "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$restore_tmp"/ { saw_chown=1 }
      in_func && /mv "\$restore_tmp" "\$BIN_PATH"/ { saw_mv=1 }
      in_func && /rm -f "\$backup_path"/ { saw_cleanup=1 }
      in_func && /^}/ {
        if (!((saw_tmp && saw_tmp_return && saw_cp && saw_chmod && saw_chown && saw_mv && saw_cleanup) || saw_app_helper)) {
          printf "%s moved binary backup restores must stage, restore atomically, and clean up the moved backup\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh dist/install_newapi.sh dist/install_sub2api.sh
}

check_binary_restores_validate_permissions() {
  if grep -R -nE '^[[:space:]]*(chmod \+x "\$BIN_PATH"|chown "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$BIN_PATH") 2>/dev/null \|\| true$' \
      impl/install_newapi.sh impl/install_sub2api.sh dist/install_newapi.sh dist/install_sub2api.sh 2>/dev/null; then
    echo "Binary rollback restores must validate executable mode and ownership changes." >&2
    return 1
  fi
  if grep -R -n '_restore_binary_backup "\$OLD_BIN_BAK" || true' \
      impl/install_newapi.sh impl/install_sub2api.sh dist/install_newapi.sh dist/install_sub2api.sh 2>/dev/null; then
    echo "Install rollback restores must not ignore backup restore failures." >&2
    return 1
  fi
  awk '
      /_restore_binary_backup\(\)/ { in_func=1; saw_tmp=0; saw_tmp_return=0; saw_cp=0; saw_chmod=0; saw_chown=0; saw_mv=0; saw_app_helper=0; next }
      in_func && /app_binary_restore_backup "\$1"/ { saw_app_helper=1 }
      in_func && /if ! restore_tmp=\$\(mktemp "\$\{BIN_PATH\}\.restore\.XXXXXX"\); then/ { saw_tmp=1 }
      in_func && saw_tmp && /return 1/ { saw_tmp_return=1 }
      in_func && /cp "\$backup_path" "\$restore_tmp"/ { saw_cp=1 }
      in_func && /chmod \+x "\$restore_tmp"/ { saw_chmod=1 }
      in_func && /chown "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$restore_tmp"/ { saw_chown=1 }
      in_func && /mv "\$restore_tmp" "\$BIN_PATH"/ { saw_mv=1 }
      in_func && /^}/ {
        if (!((saw_tmp && saw_tmp_return && saw_cp && saw_chmod && saw_chown && saw_mv) || saw_app_helper)) {
          printf "%s restore helper must stage and atomically restore binary mode and ownership\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh dist/install_newapi.sh dist/install_sub2api.sh
}

check_download_validation_failures_cleanup() {
  if grep -R -n 'app\.sub2api\.warn\.\(checksum_download\|checksum_missing\|sha_tool_missing\)' \
      apps/sub2api.sh impl/install_sub2api.sh dist/install_sub2api.sh 2>/dev/null; then
    echo "Sub2API checksum verification must fail closed instead of warning and continuing." >&2
    return 1
  fi
  awk '
      /verify_binary\(\)/ { in_func=1; saw_rm=0; next }
      in_func && /rm -f "\$bin"/ { saw_rm=1 }
      in_func && /error "\$\(t app\.newapi\.error\.binary_/ {
        if (!saw_rm) {
          printf "%s does not remove the downloaded binary before validation failure\n", FILENAME > "/dev/stderr"
          exit 1
        }
        saw_rm=0
      }
      in_func && /^}/ { in_func=0 }
    ' impl/install_newapi.sh dist/install_newapi.sh
  awk '
      /verify_checksum\(\)/ { in_checksum=1; saw_checksum_archive_rm=0; saw_checksum_archive_warn=0; next }
      in_checksum && /if ! rm -f "\$archive"; then/ { saw_checksum_archive_rm=1 }
      in_checksum && /warn "\$\(t app\.sub2api\.warn\.tmp_archive_cleanup_failed "\$archive"\)"/ { saw_checksum_archive_warn=1 }
      in_checksum && /error "\$\(t app\.sub2api\.error\.(checksum_temp|checksum_download|checksum_missing|sha_tool_missing)/ {
        if (!(saw_checksum_archive_rm && saw_checksum_archive_warn)) {
          printf "%s does not surface downloaded archive cleanup failures before checksum verification availability failure\n", FILENAME > "/dev/stderr"
          exit 1
        }
        saw_checksum_archive_rm=0
        saw_checksum_archive_warn=0
      }
      in_checksum && /if \[\[ "\$actual_hash" != "\$expected_hash" \]\]/ { in_sha_failure=1; saw_rm=0; saw_warn=0; next }
      in_sha_failure && /if ! rm -f "\$archive"; then/ { saw_rm=1 }
      in_sha_failure && /warn "\$\(t app\.sub2api\.warn\.tmp_archive_cleanup_failed "\$archive"\)"/ { saw_warn=1 }
      in_sha_failure && /error "\$\(t app\.sub2api\.error\.sha_failed/ {
        if (!(saw_rm && saw_warn)) {
          printf "%s does not surface downloaded archive cleanup failures before checksum failure\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_sha_failure=0
      }
      in_checksum && /^}/ { in_checksum=0 }
      /extract_and_verify\(\)/ { in_extract=1; saw_archive_rm=0; next }
      in_extract && /rm -f "\$archive"/ { saw_archive_rm=1 }
      in_extract && /error "\$\(t app\.sub2api\.error\.(tar_extract|archive_missing_binary|not_elf|elf_machine)/ {
        if (!saw_archive_rm) {
          printf "%s does not remove the downloaded archive before extraction validation failure\n", FILENAME > "/dev/stderr"
          exit 1
        }
        saw_archive_rm=0
      }
      in_extract && /^}/ { in_extract=0 }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
  awk '
      /app\.cyberstrikeai\.warn\.go_archive_cleanup_failed/ { saw_warn_key=1 }
      END {
        if (!saw_warn_key) {
          print "CyberStrikeAI must provide a localized Go archive cleanup warning." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/cyberstrikeai.sh
  awk '
      /verify_go_archive_checksum\(\)/ { in_func=1; saw_archive_rm=0; saw_archive_warn=0; saw_compare=0; next }
      in_func && /if ! rm -f "\$archive"; then/ { saw_archive_rm=1 }
      in_func && /warn "\$\(t app\.cyberstrikeai\.warn\.go_archive_cleanup_failed "\$archive"\)"/ { saw_archive_warn=1 }
      in_func && /error "\$\(t app\.cyberstrikeai\.error\.(go_checksum_missing|go_sha_tool_missing|go_sha_failed)/ {
        if (!(saw_archive_rm && saw_archive_warn)) {
          printf "%s does not surface downloaded Go archive cleanup failures before checksum verification errors\n", FILENAME > "/dev/stderr"
          exit 1
        }
        saw_archive_rm=0
        saw_archive_warn=0
      }
      in_func && /if \[\[ "\$actual_sha" != "\$expected_sha" \]\]; then/ { saw_compare=1 }
      in_func && /info "\$\(t app\.cyberstrikeai\.info\.go_sha_ok "\$\{actual_sha:0:16\}"\)"/ {
        if (!saw_compare) {
          printf "%s Go checksum verification must compare the downloaded archive against release metadata\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
      END {
        if (in_func) {
          printf "%s Go checksum verifier did not reach a successful verification path\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
  awk '
      /tarball="\$\{version\}\.linux-\$\{go_arch\}\.tar\.gz"/ { saw_tarball=1 }
      /expected_sha=\$\(go_release_sha256 "\$latest_json" "\$tarball" \|\| true\)/ { saw_expected=1 }
      /verify_go_archive_checksum "\$tmp" "\$expected_sha" "\$tarball"/ { saw_verify=1 }
      END {
        if (!(saw_tarball && saw_expected && saw_verify)) {
          printf "%s CyberStrikeAI Go install must verify official release checksums before extraction\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_download_temp_creation_failures_are_explicit() {
  awk '
      /verify_checksum\(\)/ { in_func=1; saw_tmp=0; saw_rm=0; saw_error=0; next }
      in_func && index($0, "if ! tmp_sum=$(mktemp); then") { saw_tmp=1; next }
      in_func && saw_tmp && /rm -f "\$archive"/ { saw_rm=1; next }
      in_func && saw_tmp && index($0, "error \"$(t app.sub2api.error.checksum_temp)\"") { saw_error=1; next }
      in_func && index($0, "success \"$(t app.sub2api.success.sha_ok \"${actual_hash:0:16}\")\"") {
        if (!(saw_tmp && saw_rm && saw_error)) {
          printf "%s Sub2API checksum temporary file creation failures must remove the archive and fail explicitly\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
  awk '
      /step "\$\(t app\.newapi\.step\.download "\$BIN_ARCH"\)"/ { in_install=1; saw_install_tmp=0; saw_install_error=0; next }
      in_install && /if ! TMP_BIN=\$\(mktemp "\$\{INSTALL_DIR\}\/new-api\.tmp\.XXXXXX"\); then/ { saw_install_tmp=1 }
      in_install && /error "\$\(t app\.newapi\.error\.download "\$GITHUB_REPO"\)"/ { saw_install_error=1 }
      in_install && /if ! curl -fL --progress-bar -o "\$TMP_BIN" "\$DOWNLOAD_URL"; then/ { saw_install_cleanup_if=0; saw_install_cleanup_warn=0; in_install_download_fail=1; next }
      in_install_download_fail && /if ! rm -f "\$TMP_BIN"; then/ { saw_install_cleanup_if=1 }
      in_install_download_fail && /warn "\$\(t app\.newapi\.warn\.tmp_binary_cleanup_failed "\$TMP_BIN"\)"/ { saw_install_cleanup_warn=1 }
      in_install_download_fail && /error "\$\(t app\.newapi\.error\.download "\$GITHUB_REPO"\)"/ {
        if (!(saw_install_tmp && saw_install_error && saw_install_cleanup_if && saw_install_cleanup_warn)) {
          printf "%s NewAPI install must report temporary download file creation and cleanup failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_install_download_fail=0
      }
      /step "\$\(t app\.newapi\.step\.download_update "\$CURRENT" "\$LATEST"\)"/ { in_update=1; saw_update_tmp=0; saw_update_error=0; next }
      in_update && /if ! TMP_BIN=\$\(mktemp "\$\{INSTALL_DIR\}\/new-api\.tmp\.XXXXXX"\); then/ { saw_update_tmp=1 }
      in_update && /error "\$\(t app\.newapi\.error\.update_download\)"/ { saw_update_error=1 }
      in_update && /if ! curl -fL --progress-bar -o "\$TMP_BIN" "\$DOWNLOAD_URL"; then/ { saw_update_cleanup_if=0; saw_update_cleanup_warn=0; in_update_download_fail=1; next }
      in_update_download_fail && /if ! rm -f "\$TMP_BIN"; then/ { saw_update_cleanup_if=1 }
      in_update_download_fail && /warn "\$\(t app\.newapi\.warn\.tmp_binary_cleanup_failed "\$TMP_BIN"\)"/ { saw_update_cleanup_warn=1 }
      in_update_download_fail && /error "\$\(t app\.newapi\.error\.update_download\)"/ {
        if (!(saw_update_tmp && saw_update_error && saw_update_cleanup_if && saw_update_cleanup_warn)) {
          printf "%s NewAPI update must report temporary download file creation and cleanup failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_update_download_fail=0
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
  awk '
      /app\.sub2api\.warn\.tmp_archive_cleanup_failed/ { saw_warn_key=1 }
      END {
        if (!saw_warn_key) {
          print "Sub2API must provide a localized temporary archive cleanup warning." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/sub2api.sh
  awk '
      /step "\$\(t app\.sub2api\.step\.download_binary "\$BIN_ARCH"\)"/ { in_install=1; saw_install_tmp=0; saw_install_error=0; next }
      in_install && /if ! TMP_ARCHIVE=\$\(mktemp "\$\{INSTALL_DIR\}\/sub2api-release\.XXXXXX\.tar\.gz"\); then/ { saw_install_tmp=1 }
      in_install && /error "\$\(t app\.sub2api\.error\.download_failed "\$GITHUB_REPO"\)"/ { saw_install_error=1 }
      in_install && /if ! curl -fL --progress-bar -o "\$TMP_ARCHIVE" "\$DOWNLOAD_URL"; then/ { saw_install_cleanup_if=0; saw_install_cleanup_warn=0; in_install_download_fail=1; next }
      in_install_download_fail && /if ! rm -f "\$TMP_ARCHIVE"; then/ { saw_install_cleanup_if=1 }
      in_install_download_fail && /warn "\$\(t app\.sub2api\.warn\.tmp_archive_cleanup_failed "\$TMP_ARCHIVE"\)"/ { saw_install_cleanup_warn=1 }
      in_install_download_fail && /error "\$\(t app\.sub2api\.error\.download_failed "\$GITHUB_REPO"\)"/ {
        if (!(saw_install_tmp && saw_install_error && saw_install_cleanup_if && saw_install_cleanup_warn)) {
          printf "%s Sub2API install must report temporary download archive creation and cleanup failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_install_download_fail=0
      }
      /step "\$\(t app\.sub2api\.step\.download_update "\$CURRENT" "\$LATEST"\)"/ { in_update=1; saw_update_tmp=0; saw_update_error=0; next }
      in_update && /if ! TMP_ARCHIVE=\$\(mktemp "\$\{INSTALL_DIR\}\/sub2api-release\.XXXXXX\.tar\.gz"\); then/ { saw_update_tmp=1 }
      in_update && /error "\$\(t app\.sub2api\.error\.update_download\)"/ { saw_update_error=1 }
      in_update && /if ! curl -fL --progress-bar -o "\$TMP_ARCHIVE" "\$DOWNLOAD_URL"; then/ { saw_update_cleanup_if=0; saw_update_cleanup_warn=0; in_update_download_fail=1; next }
      in_update_download_fail && /if ! rm -f "\$TMP_ARCHIVE"; then/ { saw_update_cleanup_if=1 }
      in_update_download_fail && /warn "\$\(t app\.sub2api\.warn\.tmp_archive_cleanup_failed "\$TMP_ARCHIVE"\)"/ { saw_update_cleanup_warn=1 }
      in_update_download_fail && /error "\$\(t app\.sub2api\.error\.update_download\)"/ {
        if (!(saw_update_tmp && saw_update_error && saw_update_cleanup_if && saw_update_cleanup_warn)) {
          printf "%s Sub2API update must report temporary download archive creation and cleanup failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_update_download_fail=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_systemd_units_are_atomic() {
  if grep -R -nE '^[[:space:]]*cat > "?/etc/systemd/system/|^[[:space:]]*cat > "\/etc\/systemd\/system/\$\{SERVICE_NAME\}\.service"' impl dist 2>/dev/null; then
    echo "systemd unit files must be written through temporary files before replacement." >&2
    return 1
  fi
  awk '
      /systemd_write_unit "\$unit_path"/ { saw_helper=1 }
      /error "\$\(t app\.(newapi|sub2api|cyberstrikeai|vaultwarden|tickflow)\.error\.(systemd_unit|systemd|service_write)/ { saw_error=1 }
      END {
        if (!(saw_helper && saw_error)) {
          print "systemd unit writes must use systemd_write_unit and report write failures." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh impl/install_cyberstrikeai.sh impl/install_vaultwarden.sh impl/install_tickflow.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_cyberstrikeai.sh dist/install_vaultwarden.sh dist/install_tickflow.sh
}

check_systemd_daemon_reloads_are_explicit() {
  if grep -R -nE '^[[:space:]]*systemctl daemon-reload$' impl dist 2>/dev/null; then
    echo "systemd daemon reload failures must be handled explicitly or intentionally ignored in cleanup paths." >&2
    return 1
  fi
  awk '
      /app\.newapi\.error\.systemd_reload/ { saw_newapi_key=1 }
      /app\.sub2api\.error\.systemd_reload/ { saw_sub2api_key=1 }
      /app\.cyberstrikeai\.error\.systemd_reload/ { saw_cyberstrikeai_key=1 }
      /app\.vaultwarden\.error\.systemd_reload/ { saw_vaultwarden_key=1 }
      END {
        if (!(saw_newapi_key && saw_sub2api_key && saw_cyberstrikeai_key && saw_vaultwarden_key)) {
          print "All systemd apps must define actionable daemon reload failure messages." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/newapi.sh apps/sub2api.sh apps/cyberstrikeai.sh apps/vaultwarden.sh
  awk '
      /if ! systemctl daemon-reload; then/ { reloads++ }
      /error "\$\(t app\.newapi\.error\.systemd_reload "\$SERVICE_NAME"\)"/ { errors++ }
      END {
        if (!(reloads == 3 && errors == 3)) {
          printf "%s NewAPI must handle install, update, and uninstall daemon reload failures explicitly\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_newapi.sh
  awk '
      /if ! systemctl daemon-reload; then/ { reloads++ }
      /error "\$\(t app\.newapi\.error\.systemd_reload "\$SERVICE_NAME"\)"/ { errors++ }
      END {
        if (!(reloads == 3 && errors == 3)) {
          printf "%s NewAPI must handle install, update, and uninstall daemon reload failures explicitly\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' dist/install_newapi.sh
  awk '
      /if ! systemctl daemon-reload; then/ { reloads++ }
      /error "\$\(t app\.sub2api\.error\.systemd_reload "\$SERVICE_NAME"\)"/ { errors++ }
      END {
        if (!(reloads == 3 && errors == 3)) {
          printf "%s Sub2API must handle install, update, and uninstall daemon reload failures explicitly\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_sub2api.sh
  awk '
      /if ! systemctl daemon-reload; then/ { reloads++ }
      /error "\$\(t app\.sub2api\.error\.systemd_reload "\$SERVICE_NAME"\)"/ { errors++ }
      END {
        if (!(reloads == 3 && errors == 3)) {
          printf "%s Sub2API must handle install, update, and uninstall daemon reload failures explicitly\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' dist/install_sub2api.sh
  awk '
      /if ! systemctl daemon-reload; then/ { reloads++ }
      /error "\$\(t app\.cyberstrikeai\.error\.systemd_reload "\$SERVICE_NAME"\)"/ { errors++ }
      END {
        if (!(reloads == 2 && errors == 2)) {
          printf "%s CyberStrikeAI must handle install and uninstall daemon reload failures explicitly\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_cyberstrikeai.sh
  awk '
      /if ! systemctl daemon-reload; then/ { reloads++ }
      /error "\$\(t app\.cyberstrikeai\.error\.systemd_reload "\$SERVICE_NAME"\)"/ { errors++ }
      END {
        if (!(reloads == 2 && errors == 2)) {
          printf "%s CyberStrikeAI must handle install and uninstall daemon reload failures explicitly\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' dist/install_cyberstrikeai.sh
  awk '
      /if ! systemctl daemon-reload; then/ { reloads++ }
      /error "\$\(t app\.vaultwarden\.error\.systemd_reload\)"/ { errors++ }
      END {
        if (!(reloads == 2 && errors == 2)) {
          printf "%s Vaultwarden must handle install and uninstall daemon reload failures explicitly\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_vaultwarden.sh
  awk '
      /if ! systemctl daemon-reload; then/ { reloads++ }
      /error "\$\(t app\.vaultwarden\.error\.systemd_reload\)"/ { errors++ }
      END {
        if (!(reloads == 2 && errors == 2)) {
          printf "%s Vaultwarden must handle install and uninstall daemon reload failures explicitly\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' dist/install_vaultwarden.sh
}

check_backup_scripts_are_atomic() {
  if grep -R -nE '^[[:space:]]*cat (>|>>) /usr/local/bin/.*-backup|^[[:space:]]*cat > "\$BACKUP_SCRIPT"' impl dist 2>/dev/null; then
    echo "Backup scripts must be written through temporary files before replacement." >&2
    return 1
  fi
  awk '
      /if ! backup_tmp=\$\(mktemp/ { saw_tmp=1 }
      /error "\$\(t app\.(newapi|sub2api|cyberstrikeai|vaultwarden)\.error\.(backup_script|backup_write)\)"/ { saw_tmp_error=1 }
      /mv "\$backup_tmp" "(\$backup_script|\$BACKUP_SCRIPT)"/ { saw_mv=1 }
      /rm -f "\$backup_tmp"/ { saw_cleanup=1 }
      END {
        if (!(saw_tmp && saw_tmp_error && saw_mv && saw_cleanup)) {
          print "Backup script writes must report temp creation failures, stage, replace, and clean up temporary files." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh impl/install_cyberstrikeai.sh impl/install_vaultwarden.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_cyberstrikeai.sh dist/install_vaultwarden.sh
}

check_generated_backup_headers_are_shell_quoted() {
  if grep -R -nE '^(BACKUP_DIR|DATA_DIR|CONFIG_DIR|INSTALL_DIR|PG_DSN|SERVICE_NAME)="\$\{(BACKUP_DIR|DATA_DIR|CONFIG_DIR|INSTALL_DIR|PG_DSN|SERVICE_NAME)\}"$|^KEEP_DAYS="\$\{BACKUP_KEEP_DAYS\}"$|^LOG_FILE="\$\{LOG_DIR\}/backup\.log"$' \
      impl/install_newapi.sh impl/install_sub2api.sh impl/install_cyberstrikeai.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "Generated backup script headers must use shell-quoted literals instead of interpolating raw values." >&2
    return 1
  fi
  awk '
      /_write_backup_script\(\)/ { in_func=1; saw_backup=0; saw_data=0; next }
      in_func && /printf -v backup_dir_literal '\''%q'\'' "\$BACKUP_DIR"/ { saw_backup=1 }
      in_func && /printf -v data_dir_literal '\''%q'\'' "\$DATA_DIR"/ { saw_data=1 }
      in_func && /^BKSH_HEADER$/ {
        if (!(saw_backup && saw_data)) {
          printf "%s generated NewAPI backup header must shell-quote configured paths\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
  awk '
      /_write_backup_script\(\)/ { in_func=1; saw_backup=0; saw_data=0; saw_config=0; saw_dsn=0; next }
      in_func && /printf -v backup_dir_literal '\''%q'\'' "\$BACKUP_DIR"/ { saw_backup=1 }
      in_func && /printf -v data_dir_literal '\''%q'\'' "\$DATA_DIR"/ { saw_data=1 }
      in_func && /printf -v config_dir_literal '\''%q'\'' "\$CONFIG_DIR"/ { saw_config=1 }
      in_func && /printf -v pg_dsn_literal '\''%q'\'' "\$PG_DSN"/ { saw_dsn=1 }
      in_func && /^BKSH_HEADER$/ {
        if (!(saw_backup && saw_data && saw_config && saw_dsn)) {
          printf "%s generated Sub2API backup header must shell-quote configured paths and DSN\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
  awk '
      /write_backup_script\(\)/ { in_func=1; saw_install=0; saw_backup=0; saw_log=0; next }
      in_func && /printf -v install_dir_literal '\''%q'\'' "\$INSTALL_DIR"/ { saw_install=1 }
      in_func && /printf -v backup_dir_literal '\''%q'\'' "\$BACKUP_DIR"/ { saw_backup=1 }
      in_func && /printf -v log_file_literal '\''%q'\'' "\$\{LOG_DIR\}\/backup\.log"/ { saw_log=1 }
      in_func && /^BACKUP$/ {
        if (!(saw_install && saw_backup && saw_log)) {
          printf "%s generated CyberStrikeAI backup header must shell-quote configured paths\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_generated_backup_scripts_handle_missing_dirs() {
  awk '
      /KEEP_DAYS="\$\{BACKUP_KEEP_DAYS\}"/ { saw_assignment=1; next }
      saw_assignment && index($0, "KEEP_DAYS=0") && index($0, "^[0-9]+$") { saw_guard=1; saw_assignment=0 }
      END {
        if (!saw_guard) {
          printf "%s generated backup script must normalize non-numeric BACKUP_KEEP_DAYS before numeric comparisons\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh impl/install_cyberstrikeai.sh impl/install_vaultwarden.sh
  awk '
      /app\.newapi\.backup\.log\.dir_failed/ { saw_newapi=1 }
      /app\.sub2api\.backup\.log\.dir_failed/ { saw_sub2api=1 }
      /app\.cyberstrikeai\.backup\.error\.backup_dir_create/ { saw_csai=1 }
      /app\.vaultwarden\.backup\.script\.dir_failed/ { saw_vw=1 }
      END {
        if (!(saw_newapi && saw_sub2api && saw_csai && saw_vw)) {
          print "Generated backup scripts must have localized backup-directory creation failure messages." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/newapi.sh apps/sub2api.sh apps/cyberstrikeai.sh apps/vaultwarden.sh
  awk '
      /_write_backup_script\(\)/ { in_func=1; saw_msg=0; saw_mkdir=0; saw_stderr=0; next }
      in_func && /MSG_BACKUP_DIR_FAILED=/ { saw_msg=1 }
      in_func && /if ! mkdir -p "\$\{BACKUP_DIR\}"; then/ { saw_mkdir=1 }
      in_func && /MSG_BACKUP_DIR_FAILED.*>&2/ { saw_stderr=1 }
      in_func && /_log ".*MSG_START/ {
        if (!(saw_msg && saw_mkdir && saw_stderr)) {
          printf "%s generated NewAPI backup script must create the backup directory explicitly before writing backup.log\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
  awk '
      /_write_backup_script\(\)/ { in_func=1; saw_msg=0; saw_mkdir=0; saw_stderr=0; next }
      in_func && /MSG_BACKUP_DIR_FAILED=/ { saw_msg=1 }
      in_func && /if ! mkdir -p "\$\{BACKUP_DIR\}"; then/ { saw_mkdir=1 }
      in_func && /MSG_BACKUP_DIR_FAILED.*>&2/ { saw_stderr=1 }
      in_func && /_log ".*MSG_START/ {
        if (!(saw_msg && saw_mkdir && saw_stderr)) {
          printf "%s generated Sub2API backup script must create the backup directory explicitly before writing backup.log\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
  awk '
      /write_backup_script\(\)/ { in_func=1; saw_msg=0; saw_mkdir=0; saw_stderr=0; next }
      in_func && /MSG_BACKUP_DIR_FAILED=/ { saw_msg=1 }
      in_func && /if ! mkdir -p "\\\$BACKUP_DIR"; then/ { saw_mkdir=1 }
      in_func && /MSG_BACKUP_DIR_FAILED.*>&2/ { saw_stderr=1 }
      in_func && /if \[\[ ! -d "\\\$INSTALL_DIR" \]\]; then/ {
        if (!(saw_msg && saw_mkdir && saw_stderr)) {
          printf "%s generated CyberStrikeAI backup script must create the backup directory explicitly before logging backup failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
  awk '
      /_write_backup_script\(\)/ { in_func=1; saw_msg=0; saw_mkdir=0; saw_stderr=0; saw_maxdepth=0; next }
      in_func && /MSG_BACKUP_DIR_FAILED=/ { saw_msg=1 }
      in_func && index($0, "if ! mkdir -p \"${BACKUP_DIR}\"; then") { saw_mkdir=1 }
      in_func && index($0, "${MSG_BACKUP_DIR_FAILED}") && index($0, ">&2") { saw_stderr=1 }
      in_func && index($0, "find \"${BACKUP_DIR}\" -maxdepth 1 -name \"vaultwarden_*.tar.gz\"") { saw_maxdepth=1 }
      in_func && /mv "\$backup_tmp" "\$backup_script"/ {
        if (!(saw_msg && saw_mkdir && saw_stderr && saw_maxdepth)) {
          printf "%s generated Vaultwarden backup script must create the backup directory explicitly and limit retention cleanup before archiving\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
}

check_manual_backup_retention_is_normalized() {
  awk '
      /^do_backup\(\) \{/ {
        in_func=1
        saw_assignment=0
        saw_guard=0
        saw_positive_guard=0
        saw_find=0
        next
      }
      in_func && /^}/ {
        if (!(saw_assignment && saw_guard && saw_positive_guard && saw_find)) {
          printf "%s NewAPI manual backup retention cleanup must normalize BACKUP_KEEP_DAYS and skip cleanup when it is zero\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
      in_func && /local _keep_days="\$\{BACKUP_KEEP_DAYS\}"/ { saw_assignment=1 }
      in_func && /\[\[ "\$_keep_days" =~ \^\[0-9\]\+\$ \]\] \|\| _keep_days=0/ { saw_guard=1 }
      in_func && /\[\[ "\$_keep_days" -gt 0 \]\]/ { saw_positive_guard=1 }
      in_func && /-mtime "\+\$\{_keep_days\}"/ { saw_find=1 }
    ' impl/install_newapi.sh dist/install_newapi.sh
  awk '
      /^do_backup\(\) \{/ {
        in_func=1
        saw_assignment=0
        saw_guard=0
        saw_positive_guard=0
        saw_find=0
        next
      }
      in_func && /^}/ {
        if (!(saw_assignment && saw_guard && saw_positive_guard && saw_find)) {
          printf "%s Blog manual backup retention cleanup must normalize BLOG_BACKUP_KEEP_DAYS and skip cleanup when it is zero\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
      in_func && /local _keep_days="\$\{BLOG_BACKUP_KEEP_DAYS\}"/ { saw_assignment=1 }
      in_func && /\[\[ "\$_keep_days" =~ \^\[0-9\]\+\$ \]\] \|\| _keep_days=0/ { saw_guard=1 }
      in_func && /\[\[ "\$_keep_days" -gt 0 \]\]/ { saw_positive_guard=1 }
      in_func && /-mtime "\+\$\{_keep_days\}"/ { saw_find=1 }
    ' impl/install_blog.sh dist/install_blog.sh
  awk '
      /^do_backup\(\) \{/ {
        in_func=1
        saw_assignment=0
        saw_guard=0
        saw_positive_guard=0
        saw_find=0
        next
      }
      in_func && /^}/ {
        if (!(saw_assignment && saw_guard && saw_positive_guard && saw_find)) {
          printf "%s Sub2API manual backup retention cleanup must normalize BACKUP_KEEP_DAYS and skip cleanup when it is zero\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
      in_func && /local _keep_days="\$\{BACKUP_KEEP_DAYS\}"/ { saw_assignment=1 }
      in_func && /\[\[ "\$_keep_days" =~ \^\[0-9\]\+\$ \]\] \|\| _keep_days=0/ { saw_guard=1 }
      in_func && /\[\[ "\$_keep_days" -gt 0 \]\]/ { saw_positive_guard=1 }
      in_func && /-mtime "\+\$\{_keep_days\}"/ { saw_find=1 }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_backup_retention_cleanup_reports_failures() {
  if grep -R -nE 'rm -f "\$f" && [^|]+ \|\| true|find "\\?\$BACKUP_DIR" -maxdepth 1 .* -delete' \
      impl/install_newapi.sh impl/install_sub2api.sh impl/install_cyberstrikeai.sh impl/install_vaultwarden.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_cyberstrikeai.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "Backup retention cleanup must report per-file removal failures instead of ignoring them." >&2
    return 1
  fi
  awk '
      /app\.newapi\.backup\.log\.remove_failed/ { saw_newapi_log_key=1 }
      /app\.newapi\.warn\.backup_cleanup_failed/ { saw_newapi_warn_key=1 }
      /app\.sub2api\.backup\.log\.remove_failed/ { saw_sub2api_log_key=1 }
      /app\.sub2api\.warn\.backup_cleanup_failed/ { saw_sub2api_warn_key=1 }
      /app\.cyberstrikeai\.backup\.warn\.remove_failed/ { saw_csai_log_key=1 }
      /app\.vaultwarden\.backup\.script\.remove_failed/ { saw_vw_log_key=1 }
      END {
        if (!(saw_newapi_log_key && saw_newapi_warn_key && saw_sub2api_log_key && saw_sub2api_warn_key && saw_csai_log_key && saw_vw_log_key)) {
          print "Backup cleanup failure messages must be localized." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/newapi.sh apps/sub2api.sh apps/cyberstrikeai.sh apps/vaultwarden.sh
  awk '
      /MSG_REMOVE_FAILED="\$\{msg_remove_failed\}"/ { saw_msg=1 }
      /_log "\$\(printf "\$MSG_REMOVE_FAILED" "\$f"\)"/ { saw_log=1 }
      /warn "\$\(t app\.newapi\.warn\.backup_cleanup_failed "\$f"\)"/ { saw_warn=1 }
      END {
        if (!(saw_msg && saw_log && saw_warn)) {
          printf "%s NewAPI backup retention cleanup must log generated-script failures and warn for manual backup cleanup failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
  awk '
      /MSG_REMOVE_FAILED="\$\{msg_remove_failed\}"/ { saw_msg=1 }
      /_log "\$\(printf "\$MSG_REMOVE_FAILED" "\$f"\)"/ { saw_log=1 }
      END {
        if (!(saw_msg && saw_log)) {
          printf "%s Sub2API generated backup retention cleanup must log per-file removal failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
  awk '
      /^do_backup\(\) \{/ { in_backup=1; saw_warn=0; saw_info=0; saw_pattern=0; next }
      in_backup && /warn "\$\(t app\.sub2api\.warn\.backup_cleanup_failed "\$_old_backup"\)"/ { saw_warn=1 }
      in_backup && /info "\$\(t app\.sub2api\.info\.cleaned_old_backups "\$_cleaned" "\$_keep_days"\)"/ { saw_info=1 }
      in_backup && /-name "sub2api_db_\*\.sql\.gz"/ { saw_pattern=1 }
      in_backup && /success "\$\(t app\.sub2api\.success\.backup_done "\$BACKUP_DIR"\)"/ {
        if (!(saw_warn && saw_info && saw_pattern)) {
          printf "%s Sub2API manual backup retention cleanup must report per-file failures and include database backup archives\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_backup=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
  awk '
      /MSG_REMOVE_FAILED="\$\{msg_remove_failed\}"/ { saw_msg=1 }
      index($0, "_log \"[WARN] \\$(printf \"\\$MSG_REMOVE_FAILED\" \"\\$old_backup\")\"") { saw_log=1 }
      END {
        if (!(saw_msg && saw_log)) {
          printf "%s CyberStrikeAI generated backup retention cleanup must log per-file removal failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
  awk '
      /MSG_REMOVE_FAILED="\$\(t app\.vaultwarden\.backup\.script\.remove_failed\)"/ { saw_msg=1 }
      /while IFS= read -r -d '\'''\'' old_backup; do/ { saw_loop=1 }
      /printf .*"\$\{MSG_REMOVE_FAILED\}".*"\$\{old_backup\}".*>&2/ { saw_log=1 }
      /-name "vaultwarden_\*\.tar\.gz" -mtime \+"\$\{KEEP_DAYS\}" -type f -print0/ { saw_print0=1 }
      END {
        if (!(saw_msg && saw_loop && saw_log && saw_print0)) {
          printf "%s Vaultwarden generated backup retention cleanup must log per-file removal failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
}

check_optional_count_messages_are_nonfatal() {
  if grep -R -nE '\[\[ (\$\{?REMOVED\}?|\$_cleaned|\$_cleaned_old|\$_cleaned_wv|\$_cnt) -(gt|eq) 0 \]\] &&' \
      impl/install_newapi.sh impl/install_sub2api.sh impl/install_vaultwarden.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "Optional count-based status messages must use explicit if branches so zero counts do not trip set -e." >&2
    return 1
  fi
}

check_silent_backup_tar_diagnostics_use_stderr() {
  if grep -R -n '2>&1 >&2; then' \
      impl/install_newapi.sh impl/install_sub2api.sh impl/install_vaultwarden.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "Silent backup tar diagnostics must be written directly to stderr." >&2
    return 1
  fi
  awk '
      /_backup_silent\(\)/ { in_func=1; saw_tar=0; saw_stderr=0; next }
      in_func && /if tar -czf/ { saw_tar=1 }
      in_func && / >&2; then/ { saw_stderr=1 }
      in_func && /^}/ {
        if (!(saw_tar && saw_stderr)) {
          printf "%s silent backup helper must send tar diagnostics to stderr\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh impl/install_vaultwarden.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_vaultwarden.sh
}

check_tar_diagnostics_use_stderr() {
  if grep -R -nE 'tar -(czf|xzf) .*2>&1; then' \
      impl/install_newapi.sh impl/install_sub2api.sh impl/install_vaultwarden.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "Tar diagnostics in backup and extract paths must be written to stderr." >&2
    return 1
  fi
  awk '
      /extract_and_verify\(\)/ { in_extract=1; saw_stderr=0; next }
      in_extract && /tar -xzf "\$archive" -C "\$tmp_extract" >&2/ { saw_stderr=1 }
      in_extract && /^}/ {
        if (!saw_stderr) {
          printf "%s Sub2API extract helper must send tar diagnostics to stderr\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_extract=0
      }
      /do_backup\(\)/ { in_backup=1; saw_tar_stderr=0; next }
      in_backup && /if tar -czf "\$ARCHIVE_TMP"/ { saw_tar_start=1 }
      in_backup && / >&2; then/ { saw_tar_stderr=1 }
      in_backup && /while IFS= read -r f; do/ {
        if (saw_tar_start && !saw_tar_stderr) {
          printf "%s manual backup helper must send tar diagnostics to stderr\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_backup=0
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
  awk '
      /do_backup\(\)/ { in_backup=1; saw_conf_stderr=0; saw_data_stderr=0; next }
      in_backup && /if tar -czf "\$CONF_TMP"/ { in_conf=1; next }
      in_conf && / >&2; then/ { saw_conf_stderr=1; in_conf=0 }
      in_backup && /if tar -czf "\$DATA_TMP"/ { in_data=1; next }
      in_data && / >&2; then/ { saw_data_stderr=1; in_data=0 }
      in_backup && /release_lock/ {
        if (!(saw_conf_stderr && saw_data_stderr)) {
          printf "%s Sub2API manual backup tar diagnostics must go to stderr\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_backup=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
  awk '
      /ARCHIVE_TMP="\$\{ARCHIVE\}\.tmp"/ { in_script=1; saw_tar_stderr=0; next }
      in_script && /TAR_EXTRA.*>&2; then/ { saw_tar_stderr=1 }
      in_script && /printf .*\$\{MSG_SUCCESS\}/ {
        if (!saw_tar_stderr) {
          printf "%s Vaultwarden backup script must send tar diagnostics to stderr\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_script=0
      }
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
}

check_certbot_diagnostics_use_stderr() {
  if grep -R -n 'certbot certonly .*2>&1; then' \
      impl/install_vaultwarden.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "Vaultwarden certbot diagnostics must be written to stderr." >&2
    return 1
  fi
  awk '
      /step "\$\(t app\.vaultwarden\.step\.certbot\)"/ { in_block=1; saw_certbot=0; saw_stderr=0; next }
      in_block && /if certbot certonly --webroot/ { saw_certbot=1 }
      in_block && /--non-interactive >&2; then/ { saw_stderr=1 }
      in_block && /if systemctl list-timers certbot/ {
        if (!(saw_certbot && saw_stderr)) {
          printf "%s Vaultwarden certbot flow must send diagnostics to stderr\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
}

check_cron_logrotate_are_atomic() {
  if grep -R -nE '^[[:space:]]*cat > (/etc/logrotate\.d/|"\$LOGROTATE_FILE")|^[[:space:]]*> /etc/cron\.d/|^[[:space:]]*cat > "\$CRON_FILE"' impl dist 2>/dev/null; then
    echo "cron and logrotate configs must be written through temporary files before replacement." >&2
    return 1
  fi
  awk '
      /if ! (cron_tmp|_vw_cron_tmp|logrotate_tmp|_vw_logrotate_tmp)=\$\(mktemp/ { saw_tmp=1 }
      /error "\$\(t app\.(newapi|sub2api|cyberstrikeai|vaultwarden)\.error\.(cron|cron_backup|auto_backup|logrotate)\)"/ { saw_tmp_error=1 }
      /mv "\$(cron_tmp|_vw_cron_tmp|logrotate_tmp|_vw_logrotate_tmp)" "\$(cron_file|_vw_cron_file|logrotate_file|_vw_logrotate_file|CRON_FILE|LOGROTATE_FILE)"/ { saw_mv=1 }
      /rm -f "\$(cron_tmp|_vw_cron_tmp|logrotate_tmp|_vw_logrotate_tmp)"/ { saw_cleanup=1 }
      END {
        if (!(saw_tmp && saw_tmp_error && saw_mv && saw_cleanup)) {
          print "cron and logrotate config writes must stage, replace, clean up temporary files, and report temp creation failures." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh impl/install_cyberstrikeai.sh impl/install_vaultwarden.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_cyberstrikeai.sh dist/install_vaultwarden.sh
}

check_nginx_configs_are_atomic() {
  if grep -R -nE '^[[:space:]]*cat > (/etc/nginx/sites-available/|"\$NGINX_CONF")|^[[:space:]]*} >> "\$NGINX_CONF"' \
      impl dist 2>/dev/null; then
    echo "Nginx site configs must be written through temporary files before replacement." >&2
    return 1
  fi
  if grep -R -nE '^[[:space:]]*ln -s[f]? .*sites-enabled' impl dist 2>/dev/null; then
    echo "Nginx sites-enabled symlinks must be staged before replacement." >&2
    return 1
  fi
  awk '
      /^_write_nginx_(config_file|site_link)\(\)/ {
        printf "%s per-app Nginx helpers must be removed in favor of lib/app.sh shared helpers\n", FILENAME > "/dev/stderr"
        exit 1
      }
      /app_write_nginx_config_file\(\)/ { in_cfg=1; saw_cfg_atomic=0; saw_cfg_error=0; next }
      in_cfg && /atomic_write_file "\$nginx_conf" 644 root:root/ { saw_cfg_atomic=1 }
      in_cfg && /error "\$\(t "\$error_key" "\$nginx_conf"\)"/ { saw_cfg_error=1 }
      in_cfg && /^}/ {
        if (!(saw_cfg_atomic && saw_cfg_error)) {
          printf "%s shared Nginx config helper must use atomic_write_file and report failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_cfg=0
      }
      /app_write_nginx_site_link\(\)/ { in_link=1; saw_link_atomic=0; saw_link_error=0; next }
      in_link && /atomic_symlink "\$target" "\$link_path"/ { saw_link_atomic=1 }
      in_link && /error "\$\(t "\$error_key" "\$target"\)"/ { saw_link_error=1 }
      in_link && /^}/ {
        if (!(saw_link_atomic && saw_link_error)) {
          printf "%s shared Nginx site link helper must use atomic_symlink and report failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_link=0
      }
    ' lib/app.sh \
      dist/install_blog.sh dist/install_cyberstrikeai.sh dist/install_sub2api.sh dist/install_vaultwarden.sh
  awk '
      FNR == 1 {
        if (NR > 1 && !(prev_cfg && prev_link)) {
          printf "%s Nginx site config writes must use the shared app_write_nginx_config_file / app_write_nginx_site_link helpers\n", prev_file > "/dev/stderr"
          exit 1
        }
        prev_cfg=0; prev_link=0; prev_file=FILENAME
      }
      /^_write_nginx_(config_file|site_link)\(\)/ {
        printf "%s per-app Nginx helpers must be removed in favor of lib/app.sh shared helpers\n", FILENAME > "/dev/stderr"
        exit 1
      }
      /if ! mkdir -p \/etc\/nginx\/sites-available \/etc\/nginx\/sites-enabled; then/ { saw_nginx_dirs=1 }
      /app_write_nginx_config_file "\$NGINX_CONF"/ { prev_cfg=1 }
      /app_write_nginx_config_file "\$nginx_conf"/ { prev_cfg=1 }
      /app_write_nginx_site_link/ { prev_link=1 }
      END {
        if (!(prev_cfg && prev_link) || !saw_nginx_dirs) {
          printf "%s Nginx site config writes must prepare directories and use the shared app_write_nginx_config_file / app_write_nginx_site_link helpers\n", prev_file > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_sub2api.sh impl/install_cyberstrikeai.sh impl/install_vaultwarden.sh impl/install_blog.sh
}

check_nginx_main_config_edits_are_atomic() {
  if grep -R -nE '^[[:space:]]*sed -i ' impl dist 2>/dev/null; then
    echo "Nginx main config edits must be staged through a temporary file before replacement." >&2
    return 1
  fi
  awk '
      /nginx_main_tmp=\$\(mktemp "\$\{nginx_main_conf\}\.XXXXXX"\)/ { saw_tmp=1 }
      /awk .*/ { saw_render=1 }
      /mv "\$nginx_main_tmp" "\$nginx_main_conf"/ { saw_mv=1 }
      /rm -f "\$nginx_main_tmp"/ { saw_cleanup=1 }
      END {
        if (!(saw_tmp && saw_render && saw_mv && saw_cleanup)) {
          print "Nginx main config edits must stage, replace, and clean up temporary files." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_nginx_test_failures_report_diagnostics() {
  if grep -R -n 'nginx -t >&2 2>/dev/null' impl/install_sub2api.sh dist/install_sub2api.sh 2>/dev/null; then
    echo "Sub2API nginx test failures must preserve diagnostic stderr output." >&2
    return 1
  fi
  awk '
      /warn "\$\(t app\.sub2api\.warn\.nginx_test_failed\)"/ { in_block=1; saw_diag=0; next }
      in_block && /nginx -t >&2 \|\| true/ { saw_diag=1 }
      in_block && /^  fi$/ {
        if (!saw_diag) {
          printf "%s Sub2API nginx failure path must emit nginx -t diagnostics to stderr\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_firewall_success_paths_validate_command_results() {
  if grep -R -nE 'ufw allow "?\$\{?(PORT|PUBLIC_PORT)[^"]*"?[^[:cntrl:]]*\|\| true|firewall-cmd --permanent --add-port=.*\|\| true|firewall-cmd --reload.*\|\| true' \
      impl/install_newapi.sh impl/install_sub2api.sh impl/install_cyberstrikeai.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "Firewall success paths must not ignore command failures." >&2
    return 1
  fi
  if grep -R -n 'ufw allow "Nginx Full" > /dev/null 2>&1 || ufw allow 80/tcp > /dev/null' \
      impl/install_blog.sh dist/install_blog.sh 2>/dev/null; then
    echo "Blog firewall fallback must not report success unless both HTTP and HTTPS rules are applied." >&2
    return 1
  fi
  awk '
      /_configure_firewall\(\)/ { in_block=1; saw_ufw_if=0; saw_iptables_if=0; saw_failure_warn=0; next }
      in_block && /if ufw allow "\$\{PORT\}\/tcp" comment "New API" > \/dev\/null; then/ { saw_ufw_if=1 }
      in_block && /if iptables -C INPUT -p tcp --dport "\$PORT" -j ACCEPT 2>\/dev\/null/ { saw_iptables_if=1 }
      in_block && /warn "\$\(t app\.newapi\.warn\.firewall_config_failed "\$PORT"\)"/ { saw_failure_warn=1 }
      in_block && /^}/ {
        if (!(saw_ufw_if && saw_iptables_if && saw_failure_warn)) {
          printf "%s NewAPI firewall configuration must only report success after command success and warn on failure\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
  awk '
      /_configure_firewall\(\)/ { in_block=1; saw_ufw_if=0; saw_firewalld_if=0; saw_iptables_if=0; saw_failure_warn=0; next }
      in_block && /if ufw allow "\$\{PORT\}\/tcp" comment "Sub2API" > \/dev\/null; then/ { saw_ufw_if=1 }
      in_block && /if firewall-cmd --permanent --add-port="\$\{PORT\}\/tcp" >\/dev\/null 2>&1/ { saw_firewalld_if=1 }
      in_block && /if iptables -C INPUT -p tcp --dport "\$PORT" -j ACCEPT 2>\/dev\/null/ { saw_iptables_if=1 }
      in_block && /warn "\$\(t app\.sub2api\.warn\.firewall_config_failed "\$PORT"\)"/ { saw_failure_warn=1 }
      in_block && /^}/ {
        if (!(saw_ufw_if && saw_firewalld_if && saw_iptables_if && saw_failure_warn)) {
          printf "%s Sub2API firewall configuration must only report success after command success and warn on failure\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
  awk '
      /open_firewall_ports\(\)/ { in_block=1; saw_ufw_if=0; saw_iptables_if=0; saw_failure_warn=0; next }
      in_block && /if ufw allow "\$\{port_to_open\}\/tcp" >\/dev\/null 2>&1; then/ { saw_ufw_if=1 }
      in_block && /if iptables -C INPUT -p tcp --dport "\$port_to_open" -j ACCEPT 2>\/dev\/null/ { saw_iptables_if=1 }
      in_block && /warn "\$\(t app\.cyberstrikeai\.warn\.firewall_config_failed "\$port_to_open"\)"/ { saw_failure_warn=1 }
      in_block && /^}/ {
        if (!(saw_ufw_if && saw_iptables_if && saw_failure_warn)) {
          printf "%s CyberStrikeAI firewall configuration must only report success after command success and warn on failure\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
  awk '
      /step "\$\(t app\.vaultwarden\.step\.firewall\)"/ { in_block=1; saw_ufw_if=0; saw_iptables_ok=0; saw_failure_warn=0; next }
      in_block && /if ufw allow "Nginx Full" >\/dev\/null 2>&1; then/ { saw_ufw_if=1 }
      in_block && /local iptables_ok=true/ { saw_iptables_ok=1 }
      in_block && /warn "\$\(t app\.vaultwarden\.warn\.firewall_config_failed\)"/ { saw_failure_warn=1 }
      in_block && /step "\$\(t app\.vaultwarden\.step\.auto_backup\)"/ {
        if (!(saw_ufw_if && saw_iptables_ok && saw_failure_warn)) {
          printf "%s Vaultwarden firewall configuration must only report success after command success and warn on failure\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
  awk '
      /step "\$\(t app\.blog\.step_firewall\)"/ { in_block=1; saw_ufw_if=0; saw_iptables_ok=0; saw_failure_warn=0; next }
      in_block && /if ufw allow "Nginx Full" > \/dev\/null 2>&1/ { saw_ufw_if=1 }
      in_block && /iptables_ok=true/ { saw_iptables_ok=1 }
      in_block && /warn "\$\(t app\.blog\.firewall_config_failed\)"/ { saw_failure_warn=1 }
      in_block && /step "\$\(t app\.blog\.step_start_nginx\)"/ {
        if (!(saw_ufw_if && saw_iptables_ok && saw_failure_warn)) {
          printf "%s Blog firewall configuration must only report success after command success and warn on failure\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_blog.sh dist/install_blog.sh
}

check_uninstall_nginx_paths_preserve_diagnostics() {
  if grep -R -nE 'nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null \|\| true|systemctl reload nginx 2>/dev/null \|\| true$' \
      impl/install_sub2api.sh impl/install_cyberstrikeai.sh impl/install_vaultwarden.sh \
      dist/install_sub2api.sh dist/install_cyberstrikeai.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "Uninstall-time nginx cleanup must preserve nginx test/reload diagnostics." >&2
    return 1
  fi
  grep -Fq 'app.sub2api.warn.uninstall_nginx_reload_failed' apps/sub2api.sh \
    && grep -Fq 'app.sub2api.warn.uninstall_nginx_test_failed' apps/sub2api.sh \
    || {
      echo "Sub2API must localize nginx uninstall warnings." >&2
      return 1
    }
  awk '
      /rm -f \/etc\/nginx\/sites-enabled\/sub2api/ { in_block=1; saw_test=0; saw_reload=0; saw_diag=0; saw_reload_warn=0; saw_test_warn=0; saw_fallback=0; next }
      in_block && /if nginx -t >\/dev\/null 2>&1; then/ { saw_test=1 }
      in_block && /if systemctl reload nginx >\/dev\/null 2>&1; then/ { saw_reload=1 }
      in_block && /nginx -t >&2 \|\| true/ { saw_diag=1 }
      in_block && /warn "\$\(t app\.sub2api\.warn\.uninstall_nginx_reload_failed\)"/ { saw_reload_warn=1 }
      in_block && /warn "\$\(t app\.sub2api\.warn\.uninstall_nginx_test_failed\)"/ { saw_test_warn=1 }
      in_block && /success "\$\(t app\.sub2api\.success\.removed_nginx\)"/ { saw_fallback=1 }
      in_block && /rm -f \/etc\/cron\.d\/sub2api-backup/ {
        if (!(saw_test && saw_reload && saw_diag && saw_reload_warn && saw_test_warn && saw_fallback)) {
          printf "%s Sub2API uninstall nginx cleanup must validate reloads, emit diagnostics, and warn on validation or reload failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
  grep -Fq 'app.cyberstrikeai.warn.uninstall_nginx_reload_failed' apps/cyberstrikeai.sh || {
    echo "CyberStrikeAI must localize nginx reload warnings during uninstall." >&2
    return 1
  }
  awk '
      /rm -f "\$NGINX_LINK" "\$NGINX_CONF"/ { in_block=1; saw_test=0; saw_reload=0; saw_diag=0; saw_warn=0; next }
      in_block && /if nginx -t >\/dev\/null 2>&1; then/ { saw_test=1 }
      in_block && /if ! systemctl reload nginx >\/dev\/null 2>&1; then/ { saw_reload=1 }
      in_block && /^    else$/ { saw_else=1 }
      in_block && saw_else && /nginx -t >&2 \|\| true/ { saw_diag=1 }
      in_block && /warn "\$\(t app\.cyberstrikeai\.warn\.uninstall_nginx_reload_failed\)"/ { saw_warn=1 }
      in_block && /nginx -t >&2 \|\| true/ { saw_diag=1 }
      in_block && /success "\$\(t app\.cyberstrikeai\.success\.removed_nginx\)"/ {
        if (!(saw_test && saw_reload && saw_diag && saw_warn)) {
          printf "%s CyberStrikeAI uninstall nginx cleanup must emit diagnostics and an explicit warning when validation or reload fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
  grep -Fq 'app.vaultwarden.warn.uninstall_nginx_reload_failed' apps/vaultwarden.sh || {
    echo "Vaultwarden must localize nginx reload warnings during uninstall." >&2
    return 1
  }
  awk '
      /rm -f \/etc\/nginx\/sites-enabled\/vaultwarden \/etc\/nginx\/sites-available\/vaultwarden/ { in_block=1; saw_test=0; saw_reload=0; saw_diag=0; saw_warn=0; next }
      in_block && /if nginx -t >\/dev\/null 2>&1; then/ { saw_test=1 }
      in_block && /if ! systemctl reload nginx >\/dev\/null 2>&1; then/ { saw_reload=1 }
      in_block && /^    else$/ { saw_else=1 }
      in_block && saw_else && /nginx -t >&2 \|\| true/ { saw_diag=1 }
      in_block && /warn "\$\(t app\.vaultwarden\.warn\.uninstall_nginx_reload_failed\)"/ { saw_warn=1 }
      in_block && /nginx -t >&2 \|\| true/ { saw_diag=1 }
      in_block && /success "\$\(t app\.vaultwarden\.success\.removed_nginx\)"/ {
        if (!(saw_test && saw_reload && saw_diag && saw_warn)) {
          printf "%s Vaultwarden uninstall nginx cleanup must emit diagnostics and an explicit warning when validation or reload fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
  grep -Fq 'app.blog.uninstall.nginx_test_failed' apps/blog.sh || {
    echo "Blog must localize nginx uninstall validation warnings." >&2
    return 1
  }
  awk '
      /if command -v nginx >\/dev\/null 2>&1 && command -v systemctl >\/dev\/null 2>&1; then/ { in_block=1; saw_test_if=0; saw_reload_if=0; saw_diag=0; saw_reload_warn=0; saw_test_warn=0; saw_success=0; next }
      in_block && /if nginx -t >\/dev\/null 2>&1; then/ { saw_test_if=1 }
      in_block && /if systemctl reload nginx >\/dev\/null 2>&1; then/ { saw_reload_if=1 }
      in_block && /nginx -t >&2 \|\| true/ { saw_diag=1 }
      in_block && /warn "\$\(t app\.blog\.uninstall\.nginx_reload_failed\)"/ { saw_reload_warn=1 }
      in_block && /warn "\$\(t app\.blog\.uninstall\.nginx_test_failed\)"/ { saw_test_warn=1 }
      in_block && /success "\$\(t app\.blog\.uninstall\.nginx_reloaded\)"/ { saw_success=1 }
      in_block && /success "\$\(t app\.blog\.uninstall\.success\)"/ {
        if (!(saw_test_if && saw_reload_if && saw_diag && saw_reload_warn && saw_test_warn && saw_success)) {
          printf "%s Blog uninstall nginx cleanup must distinguish nginx validation failures from reload failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_blog.sh dist/install_blog.sh
}

check_fail2ban_configs_are_atomic() {
  if grep -R -nE '^[[:space:]]*cat > /etc/fail2ban/' impl dist 2>/dev/null; then
    echo "Fail2Ban configs must be written through temporary files before replacement." >&2
    return 1
  fi
  awk '
      /fail2ban_tmp=\$\(mktemp/ { saw_tmp=1 }
      /if ! fail2ban_tmp=\$\(mktemp "\$\{fail2ban_conf\}\.XXXXXX"\); then/ { saw_tmp_if=1 }
      /error "\$\(t app\.vaultwarden\.error\.fail2ban_write "\$fail2ban_conf"\)"/ { saw_tmp_error=1 }
      /mv "\$fail2ban_tmp" "\$fail2ban_conf"/ { saw_mv=1 }
      /rm -f "\$fail2ban_tmp"/ { saw_cleanup=1 }
      /_write_fail2ban_config_file \/etc\/fail2ban\// { saw_helper=1 }
      END {
        if (!(saw_tmp && saw_tmp_if && saw_tmp_error && saw_mv && saw_cleanup && saw_helper)) {
          print "Fail2Ban config writes must stage, replace, clean up temporary files, and report temp creation failures." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
}

check_user_deletion_paths_are_explicit() {
  if grep -R -nE 'userdel "\$(SERVICE_USER|VW_USER)" 2>/dev/null[[:space:]\\]*&& success .* \|\| (warn|true)' \
      impl/install_newapi.sh impl/install_sub2api.sh impl/install_cyberstrikeai.sh impl/install_vaultwarden.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_cyberstrikeai.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "User deletion paths must use explicit conditionals for userdel outcomes." >&2
    return 1
  fi
  awk '
      /if \$DELETE_DATA && id "\$SERVICE_USER" &>\/dev\/null; then/ { in_userdel=1; saw_userdel_if=0; saw_success=0; saw_warn=0; next }
      in_userdel && /if userdel "\$SERVICE_USER" 2>\/dev\/null; then/ { saw_userdel_if=1 }
      in_userdel && /success "\$\(t app\.newapi\.success\.deleted_user "\$SERVICE_USER"\)"/ { saw_success=1 }
      in_userdel && /warn "\$\(t app\.newapi\.warn\.delete_user "\$SERVICE_USER"\)"/ { saw_warn=1 }
      in_userdel && /^  fi$/ {
        if (!(saw_userdel_if && saw_success && saw_warn)) {
          printf "%s NewAPI uninstall user deletion must branch explicitly on userdel result\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_userdel=0
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
  awk '
      /if \$DELETE_DATA && \$DELETE_CONF && id "\$SERVICE_USER" &>\/dev\/null; then/ { in_userdel=1; saw_userdel_if=0; saw_success=0; saw_warn=0; next }
      in_userdel && /if userdel "\$SERVICE_USER" 2>\/dev\/null; then/ { saw_userdel_if=1 }
      in_userdel && /success "\$\(t app\.sub2api\.success\.deleted_user "\$SERVICE_USER"\)"/ { saw_success=1 }
      in_userdel && /warn "\$\(t app\.sub2api\.warn\.delete_user "\$SERVICE_USER"\)"/ { saw_warn=1 }
      in_userdel && /^  fi$/ {
        if (!(saw_userdel_if && saw_success && saw_warn)) {
          printf "%s Sub2API uninstall user deletion must branch explicitly on userdel result\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_userdel=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
  awk '
      /if \[\[ "\$\{del_install,,\}" == "y" \]\] && id "\$SERVICE_USER" >\/dev\/null 2>&1; then/ { in_userdel=1; saw_userdel_if=0; saw_success=0; saw_warn=0; next }
      in_userdel && /if userdel "\$SERVICE_USER" 2>\/dev\/null; then/ { saw_userdel_if=1 }
      in_userdel && /success "\$\(t app\.cyberstrikeai\.success\.deleted_user "\$SERVICE_USER"\)"/ { saw_success=1 }
      in_userdel && /warn "\$\(t app\.cyberstrikeai\.warn\.delete_user "\$SERVICE_USER"\)"/ { saw_warn=1 }
      in_userdel && /^  fi$/ {
        if (!(saw_userdel_if && saw_success && saw_warn)) {
          printf "%s CyberStrikeAI uninstall user deletion must branch explicitly on userdel result\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_userdel=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
  awk '
      /if \$DELETE_DATA && id "\$VW_USER" &>\/dev\/null; then/ { in_userdel=1; saw_userdel_if=0; saw_success=0; next }
      in_userdel && /if userdel "\$VW_USER" 2>\/dev\/null; then/ { saw_userdel_if=1 }
      in_userdel && /success "\$\(t app\.vaultwarden\.success\.deleted_user "\$VW_USER"\)"/ { saw_success=1 }
      in_userdel && /^  fi$/ {
        if (!(saw_userdel_if && saw_success)) {
          printf "%s Vaultwarden uninstall user deletion must branch explicitly on userdel result\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_userdel=0
      }
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
}

# A bare call to app_check_port_conflict must never abort the script under
# `set -e`, even when the checked port is free (warn-only helper).
check_port_conflict_is_warn_only() {
  "$BASH_BIN" -c '
    set -euo pipefail
    source "$1/lib/logging.sh"
    source "$1/lib/i18n.sh"
    source "$1/lib/network.sh"
    echo "before"
    app_check_port_conflict 59998 "TEST_PORT"
    echo "after"
  ' _ "$ROOT_DIR"
}

# Behavioral test for github_latest_release_tag with a stubbed curl: the
# version must be extracted from a release payload, and non-version or
# failed lookups must print nothing.
check_github_release_tag_behavior() {
  "$BASH_BIN" -c '
    set -euo pipefail
    source "$1/lib/logging.sh"
    source "$1/lib/i18n.sh"
    source "$1/lib/network.sh"
    curl() { printf "%s\n" '"'"'{"tag_name":"v1.2.3","name":"v1.2.3"}'"'"'; }
    tag=$(github_latest_release_tag "owner/repo" "test.warn" 2>/dev/null)
    [[ "$tag" == "v1.2.3" ]] || { echo "expected v1.2.3, got: ${tag}" >&2; exit 1; }
    curl() { printf "%s\n" '"'"'{"tag_name":"not-a-version"}'"'"'; }
    tag=$(github_latest_release_tag "owner/repo" "test.warn" 2>/dev/null)
    [[ -z "$tag" ]] || { echo "expected empty tag for non-version, got: ${tag}" >&2; exit 1; }
    curl() { return 1; }
    tag=$(github_latest_release_tag "owner/repo" "test.warn" 2>/dev/null)
    [[ -z "$tag" ]] || { echo "expected empty tag on failure, got: ${tag}" >&2; exit 1; }
  ' _ "$ROOT_DIR"
}

# Behavioral test for the shared validators: valid values pass and invalid
# values abort (error exits), matching how impl scripts rely on them.
check_shared_validators_accept_and_reject() {
  "$BASH_BIN" -c '
    set -euo pipefail
    source "$1/lib/logging.sh"
    source "$1/lib/i18n.sh"
    source "$1/lib/network.sh"
    source "$1/lib/app.sh"
    app_validate_port 8080 "PORT" || { echo "valid port rejected" >&2; exit 1; }
    ( app_validate_port 70000 "PORT" ) 2>/dev/null && { echo "out-of-range port accepted" >&2; exit 1; }
    ( app_validate_port "abc" "PORT" ) 2>/dev/null && { echo "non-numeric port accepted" >&2; exit 1; }
    app_validate_bool "PORT" true || { echo "valid bool rejected" >&2; exit 1; }
    app_validate_bool "PORT" 0 || { echo "valid bool 0 rejected" >&2; exit 1; }
    ( app_validate_bool "PORT" maybe ) 2>/dev/null && { echo "invalid bool accepted" >&2; exit 1; }
    app_validate_domain "DOMAIN" "app.example.com" || { echo "valid domain rejected" >&2; exit 1; }
    app_validate_domain "DOMAIN" "" || { echo "empty domain rejected" >&2; exit 1; }
    ( app_validate_domain "DOMAIN" "bad name" ) 2>/dev/null && { echo "invalid domain accepted" >&2; exit 1; }
    exit 0
  ' _ "$ROOT_DIR"
}

# Behavioral test for app_check_connectivity with a stubbed curl: at least
# one reachable endpoint passes and an unreachable set aborts (error exits).
check_connectivity_helper_behavior() {
  "$BASH_BIN" -c '
    set -euo pipefail
    source "$1/lib/logging.sh"
    source "$1/lib/i18n.sh"
    source "$1/lib/network.sh"
    curl() { return 0; }
    app_check_connectivity "test.warn" "https://example.test" \
      || { echo "reachable endpoint failed" >&2; exit 1; }
    curl() { return 1; }
    ( app_check_connectivity "test.warn" "https://example.test" ) 2>/dev/null \
      && { echo "unreachable endpoints did not abort" >&2; exit 1; }
    exit 0
  ' _ "$ROOT_DIR"
}


# A flag-driven `$flag && cmd || error` chain runs the error branch whenever
# the flag is false (&& short-circuits), even though the left side never ran.
# Require explicit `if $flag; then ...` conditionals for error handling.
check_no_flag_chained_error_handlers() {
  local file
  while IFS= read -r file; do
    if grep -nE '^[[:space:]]*\$\{?[A-Za-z_][A-Za-z0-9_]*\}?[[:space:]]*&&.*\|\|[[:space:]]*(error|return|exit)\b' "$file" >&2; then
      echo "flag-chained error handling must use an explicit if conditional (see matches above)" >&2
      return 1
    fi
  done < <(find impl apps lib bin dist -name '*.sh' -type f | sort)
}

# Behavioral test for the config sanitization helpers: embedded CR/LF are
# stripped (config injection), double quotes are removed, and plain values
# pass through unchanged.
check_config_sanitization_behavior() {
  "$BASH_BIN" -c '
    set -euo pipefail
    source "$1/lib/config.sh"
    cr=$(printf "\r")
    lf=$(printf "\n")
    value="abc${cr}${lf}def\"quoted\""
    sanitized="$(sanitize_conf_val "$value")"
    [[ "$sanitized" == "abc" ]] || { echo "embedded CR/LF or quotes not stripped: [$sanitized]" >&2; exit 1; }
    [[ "$(sanitize_conf_val "8080")" == "8080" ]] || { echo "plain value altered" >&2; exit 1; }
    [[ "$(sanitize_conf_val "hello world")" == "hello world" ]] || { echo "value with spaces altered" >&2; exit 1; }
    [[ "$(sanitize_conf_val "a\"b\"c")" == "abc" ]] || { echo "double quotes not removed" >&2; exit 1; }
    [[ "$(trim_conf_token "  foo  ")" == "foo" ]] || { echo "trim_conf_token failed" >&2; exit 1; }
    tabbed=$(printf "\tbar\n")
    [[ "$(trim_conf_token "$tabbed")" == "bar" ]] || { echo "trim_conf_token tab/newline failed" >&2; exit 1; }
    exit 0
  ' _ "$ROOT_DIR"
}

# Verifies that every check_* function is invoked by `all` and that every
# `all` check is also covered by a non-`all` target (syntax/shellcheck/release/
# dispatch/guards). Keeps parallel CI jobs from silently dropping checks.
check_target_groups_cover_all_checks() {
  awk '
    /^check_[A-Za-z0-9_]+\(\)/ { d=$0; sub(/\(.*/, "", d); defs[d]=1; next }
    /^main\(\) \{/ { in_main=1; next }
    in_main && /^main "\$@"/ { in_main=0; next }
    in_main && /^  check_[A-Za-z0-9_]+$/ { all_calls[$1]=1; next }
    in_main && /^      check_[A-Za-z0-9_]+$/ { arm_calls[$1]=1; next }
    END {
      for (d in defs) {
        if (!(d in all_calls) && !(d in arm_calls)) {
          printf "uninvoked check function: %s\n", d > "/dev/stderr"; exit 1
        }
      }
      for (c in all_calls) {
        if (!(c in arm_calls)) {
          printf "check missing from CI targets (syntax/shellcheck/release/dispatch/guards): %s\n", c > "/dev/stderr"; exit 1
        }
      }
      for (c in arm_calls) {
        if (!(c in all_calls)) {
          printf "target-only check missing from all: %s\n", c > "/dev/stderr"; exit 1
        }
      }
    }
  ' "$ROOT_DIR/tools/verify.sh" "$ROOT_DIR"/tools/checks/*.sh
}
