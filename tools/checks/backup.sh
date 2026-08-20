# shellcheck shell=bash
# shellcheck source=../verify.sh
# Backup and update lifecycle guardrails: atomic backups, retention, rollback, download validation, and tar diagnostics.

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
    ' impl/install_hugo_blog.sh dist/install_hugo_blog.sh
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

