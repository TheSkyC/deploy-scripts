# shellcheck shell=bash
# shellcheck source=../verify.sh
# Repo hygiene and static-analysis guardrails: syntax, shellcheck, release syntax, path safety, and atomicity of the shared lib primitives.

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
  # The gate runs at style severity so real issues such as SC2295 (unquoted
  # expansions inside ${..} patterns, which previously slipped through at
  # warning severity) are caught. Remaining exclusions are intentional:
  #   SC2034: app/framework contract variables (APP_ID, LOCK_FILE, doctor
  #           hooks, ...) are consumed by name from other scripts.
  #   SC1090/SC1091: impl files source lib/*.sh through runtime-derived paths.
  #   SC1017: git stores LF via .gitattributes even when the working tree is CRLF.
  #   SC2016: single-quoted patterns in checks deliberately assert literal text.
  #   SC2005: `echo "$(cmd)"` wrappers exist to emit formatted command output.
  #   SC2059: `printf "$text" "$@"` is the intentional i18n format mechanism.
  #   SC2329: functions invoked indirectly (restore_framework_functions / exit handlers).
  #   SC2015: `A && B || C` assertion chains in checks are deliberate: every
  #           grep in the chain must pass before the failure branch runs.
  local file normalized status temp_dir
  local files=()
  temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/deploy-scripts-shellcheck.XXXXXX")" || return 1
  while IFS= read -r file; do
    normalized="${temp_dir}/${file}"
    mkdir -p "$(dirname -- "$normalized")" || { rm -rf "$temp_dir"; return 1; }
    # Git preserves LF in the repository, but some Windows checkouts expose CRLF
    # to Unix shellcheck. Normalize only the verification copy so diagnostics
    # reflect the script instead of heredoc terminator carriage returns.
    tr -d '\r' <"$file" >"$normalized" || { rm -rf "$temp_dir"; return 1; }
    files+=("$normalized")
  done < <(find apps bin impl lib tools -name '*.sh' -type f | sort; printf '%s\n' deploy.sh)
  set +e
  shellcheck --severity=style \
    --exclude=SC2034,SC1090,SC1091,SC1017,SC2016,SC2005,SC2059,SC2329,SC2015 \
    "${files[@]}"
  status=$?
  set -e
  rm -rf "$temp_dir"
  return "$status"
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
    ' impl/install_hugo_blog.sh impl/install_vaultwarden.sh
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
    ' impl/install_newapi.sh
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
    ' impl/install_sub2api.sh
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
    ' impl/install_vaultwarden.sh
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
    ' impl/install_cyberstrikeai.sh
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
    ' impl/install_tickflow.sh
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
    ' impl/install_hugo_blog.sh
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
    ' impl/install_hugo_blog.sh
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
 ' lib/atomic.sh 
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
 ' lib/binary.sh 
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
 ' lib/service.sh 
}

check_binary_app_systemd_paths_are_validated() {
  local file
  for file in lib/binary_app.sh; do
    grep -Fq 'bapp_validate_no_whitespace' "$file" \
      && grep -Fq 'binary_app.error.path_whitespace' "$file" \
      && grep -Fq 'require_safe_path "BA_READWRITE_PATHS"' "$file" \
      && grep -Fq 'ExecStart="${BIN_PATH}"${BA_SERVICE_ARGS:+ ${BA_SERVICE_ARGS}}' "$file" \
      || {
        echo "$file must validate binary-app systemd paths (no whitespace) and quote ExecStart." >&2
        return 1
      }
  done
}

check_binary_app_pre_backup_hook_is_best_effort() {
  local file
  for file in lib/binary_app.sh; do
    grep -Fq 'declare -f ba_backup_hook' "$file" \
      && grep -Fq 'if ! ba_backup_hook; then' "$file" \
      && grep -Fq 'binary_app.warn.backup_hook_failed' "$file" \
      || {
        echo "$file must invoke ba_backup_hook() before archiving and keep it best-effort (warn, never abort the backup)." >&2
        return 1
      }
  done
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

check_random_head_pipelines_handle_sigpipe() {
  if grep -R -nE 'rand .*\\|.*head -c [0-9]+\\)$|tr -dc .*\\| head -c [0-9]+\\)$' impl dist 2>/dev/null; then
    echo "Random byte pipelines ending in head -c need an explicit successful terminator under pipefail." >&2
    return 1
  fi
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
  if grep -R -n 'mv "$old_go_backup" /usr/local/go 2>/dev/null || true' impl/install_cyberstrikeai.sh 2>/dev/null; then
    echo "CyberStrikeAI Go toolchain rollback must validate restoring the previous /usr/local/go." >&2
    return 1
  fi
  if grep -R -nE '^[[:space:]]*ln -sf /usr/local/go/bin/(go|gofmt) /usr/local/bin/(go|gofmt)$' \
      impl/install_cyberstrikeai.sh 2>/dev/null; then
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
    ' impl/install_cyberstrikeai.sh
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
    ' impl/install_cyberstrikeai.sh
}

check_no_flag_chained_error_handlers() {
  local file
  while IFS= read -r file; do
    if grep -nE '^[[:space:]]*\$\{?[A-Za-z_][A-Za-z0-9_]*\}?[[:space:]]*&&.*\|\|[[:space:]]*(error|return|exit)\b' "$file" >&2; then
      echo "flag-chained error handling must use an explicit if conditional (see matches above)" >&2
      return 1
    fi
  done < <(find impl apps lib bin dist -name '*.sh' -type f | sort)
}

