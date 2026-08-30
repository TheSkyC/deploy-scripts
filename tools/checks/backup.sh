# shellcheck shell=bash
# shellcheck source=../verify.sh
# Backup and update lifecycle guardrails: atomic backups, retention, rollback, download validation, and tar diagnostics.

check_optional_directory_cleanup_is_nonfatal() {
  if grep -R -nE '\[\[ (-n "\$old_go_backup"|-d "\$_wv_install_bak") \]\] && rm -rf' \
      impl/install_cyberstrikeai.sh impl/install_vaultwarden.sh 2>/dev/null; then
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
    ' impl/install_newapi.sh
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
    ' impl/install_sub2api.sh
}

check_preupdate_backup_warnings_include_followup_guidance() {
  awk '
      /binary_app\.warn\.pre_backup_failed/ { saw_framework=1 }
      /binary_app\.warn\.silent_backup_failed/ { saw_silent=1 }
      /inspect %s\/backup\.log/ { saw_framework_log=1 }
      /app\.sub2api\.warn\.pre_update_backup/ { saw_sub2api=1 }
      /\/opt\/sub2api-backups\/backup\.log/ { saw_sub2api_log=1 }
      /\/usr\/local\/bin\/sub2api-backup/ { saw_sub2api_cmd=1 }
      /app\.cyberstrikeai\.warn\.preupdate_backup/ { saw_csai=1 }
      /\/opt\/cyberstrike-ai\/logs\/backup\.log/ { saw_csai_log=1 }
      /\/usr\/local\/bin\/cyberstrike-ai-backup/ { saw_csai_cmd=1 }
      END {
        if (!(saw_framework && saw_framework_log && saw_sub2api && saw_sub2api_log && saw_sub2api_cmd && saw_csai && saw_csai_log && saw_csai_cmd)) {
          print "Pre-update backup warnings must tell users where to inspect backup logs and how to run a manual backup." > "/dev/stderr"
          exit 1
        }
      }
    ' lib/binary_app.sh apps/sub2api.sh apps/cyberstrikeai.sh
  awk '
      /step .*pre_backup/ { in_framework=1; saw_framework_if=0; next }
      in_framework && /if ! _ba_backup "pre-update"; then/ { saw_framework_if=1 }
      in_framework && /warn .*binary_app\.warn\.pre_backup_failed/ {
        if (!saw_framework_if) {
          printf "%s binary-app pre-update backup warning must come from an explicit conditional\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_framework=0
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
    ' lib/binary_app.sh impl/install_sub2api.sh impl/install_cyberstrikeai.sh
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
    ' impl/install_sub2api.sh
}

check_preupdate_backup_logs_match_guidance() {
  "$BASH_BIN" -c '
    set -euo pipefail
    # shellcheck disable=SC2043 # Fixed target; retain the shared per-file guard body.
    for file in lib/binary_app.sh; do
      block=$(sed -n "/^_ba_backup()/,/^_ba_prune_backups()/p" "$file")
      grep -Fq '\''local backup_log="${BACKUP_DIR}/backup.log"'\'' <<<"$block" || {
        echo "$file shared backup helper must declare backup.log output" >&2
        exit 1
      }
      grep -Fq "_ba_backup_log()" <<<"$block" || {
        echo "$file shared backup helper must define a backup log helper" >&2
        exit 1
      }
      grep -Fq "[[ -d \"\$BACKUP_DIR\" ]] || return 1" <<<"$block" || {
        echo "$file shared backup helper must guard log writes when the backup directory cannot be created" >&2
        exit 1
      }
      grep -Fq "if ! mkdir -p \"\$BACKUP_DIR\"; then" <<<"$block" || {
        echo "$file shared backup helper must handle backup directory creation failures explicitly" >&2
        exit 1
      }
      grep -Fq ">> \"\$backup_log\"" <<<"$block" || {
        echo "$file shared backup helper must append lines to backup.log" >&2
        exit 1
      }
      grep -Fq "_ba_backup_log \"\$(t binary_app.error.data_missing \"\$DATA_DIR\")\"" <<<"$block" || {
        echo "$file shared backup helper must log missing data directory failures" >&2
        exit 1
      }
      grep -Fq "_ba_backup_log \"\$(t binary_app.error.backup_failed)\"" <<<"$block" || {
        echo "$file shared backup helper must log tar failures" >&2
        exit 1
      }
    done
    # shellcheck disable=SC2043 # Fixed target; retain the shared per-file guard body.
    for file in impl/install_vaultwarden.sh; do
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
      /^acquire_lock\(\)/ { in_func=1; saw_mkdir=0; saw_error=0; saw_exec=0; saw_handler=0; next }
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
 ' lib/lock.sh 

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

# acquire_lock registers release_lock on the shared exit-handler stack, so an
# explicit release_lock call at the end of a do_* action is dead code — and a
# misleading one: it implies the lock would leak without it, and it releases
# early if a caller ever adds a second phase after it. Locks are released only
# by the exit handler.
check_no_explicit_release_lock_calls() {
  if grep -R -nE '^[[:space:]]*release_lock$' impl/*.sh apps/*.sh 2>/dev/null; then
    echo "Explicit release_lock calls are dead code: acquire_lock registers release via deploy_add_exit_handler. Remove them." >&2
    return 1
  fi
}

check_update_backs_up_before_stop() {
  local file
  for file in lib/binary_app.sh impl/install_sub2api.sh; do
    awk '
      /local bak_path=/ { seen_bak=1; seen_cp=0 }
      seen_bak && index($0, "app_binary_backup_current \"$bak_path\"") { seen_cp=1 }
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
      impl/install_sub2api.sh impl/install_vaultwarden.sh 2>/dev/null; then
    echo "Update binary backups must copy to a temporary file before replacing the final backup path." >&2
    return 1
  fi
  awk '
      /_backup_current_binary\(\)|backup_vaultwarden_binary\(\)/ { in_func=1; saw_tmp=0; saw_tmp_error=0; saw_cp=0; saw_mv=0; saw_cleanup=0; saw_atomic=0; saw_app_helper=0; next }
      in_func && /atomic_copy_file "\$(BIN_PATH|VW_BIN)" "\$backup_path"/ { saw_atomic=1 }
      in_func && /app_binary_backup_current "\$backup_path"/ { saw_app_helper=1 }
      in_func && /if ! backup_tmp=\$\(mktemp "\$\{backup_path\}\.XXXXXX"\); then/ { saw_tmp=1 }
      in_func && /error "\$\(t app\.(sub2api|vaultwarden)\.error\.binary_install/ { saw_tmp_error=1 }
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
    ' impl/install_sub2api.sh impl/install_vaultwarden.sh
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
  # shellcheck disable=SC2043 # Fixed target; retain the shared per-file guard body.
  for file in impl/install_cyberstrikeai.sh; do
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
  # shellcheck disable=SC2043 # Fixed target; retain the shared per-file guard body.
  for file in impl/install_sub2api.sh; do
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
  # shellcheck disable=SC2043 # Fixed target; retain the shared per-file guard body.
  for file in impl/install_vaultwarden.sh; do
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
      impl/install_sub2api.sh impl/install_vaultwarden.sh 2>/dev/null; then
    echo "Uninstall binary cleanup must report per-path removal failures instead of ignoring find -delete errors." >&2
    return 1
  fi
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
    ' impl/install_sub2api.sh
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
    ' impl/install_vaultwarden.sh
}

check_backup_temp_moves_handle_failure() {
  if grep -R -nE '^[[:space:]]*mv "\$[^"]*(TMP|tmp|ARCHIVE_TMP|archive_tmp|PG_TMP|pg_tmp|CONF_TMP|conf_tmp|DATA_TMP|data_tmp|DUMP_TMP|dump_tmp)[^"]*" "\$[^"]*(ARCHIVE|archive|FILE|file)' impl dist 2>/dev/null; then
    echo "Backup temporary files must be removed when the final move fails." >&2
    return 1
  fi
}

check_binary_replacements_handle_failure() {
  if grep -R -nE '^[[:space:]]*(mv "\$TMP_(BIN|ARCHIVE)" "\$BIN_PATH"|chmod \+x "\$BIN_PATH"|chown "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$BIN_PATH")$' \
 impl/install_sub2api.sh 2>/dev/null; then
    echo "Binary replacements must clean up candidates and restore backups on move, chmod, and chown failures." >&2
    return 1
  fi
  if grep -R -n 'mv "$backup_path" "$BIN_PATH" 2>/dev/null || true' \
 impl/install_sub2api.sh 2>/dev/null; then
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
 ' impl/install_sub2api.sh 
  awk '
      /bapp_update\(\)/ { in_update=1; saw_helper=0; next }
      in_update && /ba_install_binary "\$tmp_bin"/ { saw_helper=1 }
      in_update && /^}/ {
        if (!saw_helper) {
          printf "%s shared update lifecycle must install the candidate via ba_install_binary\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_update=0
      }
 ' lib/binary_app.sh
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
 ' impl/install_sub2api.sh 
}

check_binary_restores_validate_permissions() {
  if grep -R -nE '^[[:space:]]*(chmod \+x "\$BIN_PATH"|chown "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$BIN_PATH") 2>/dev/null \|\| true$' \
 impl/install_sub2api.sh 2>/dev/null; then
    echo "Binary rollback restores must validate executable mode and ownership changes." >&2
    return 1
  fi
  if grep -R -n '_restore_binary_backup "\$OLD_BIN_BAK" || true' \
 impl/install_sub2api.sh 2>/dev/null; then
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
 ' impl/install_sub2api.sh 
}

check_download_validation_failures_cleanup() {
  if grep -R -n 'app\.sub2api\.warn\.\(checksum_download\|checksum_missing\|sha_tool_missing\)' \
      apps/sub2api.sh impl/install_sub2api.sh 2>/dev/null; then
    echo "Sub2API checksum verification must fail closed instead of warning and continuing." >&2
    return 1
  fi
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
    ' impl/install_sub2api.sh
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
    ' impl/install_cyberstrikeai.sh
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
    ' impl/install_cyberstrikeai.sh
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
    ' impl/install_sub2api.sh
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
    ' impl/install_sub2api.sh
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
    ' impl/install_newapi.sh impl/install_sub2api.sh impl/install_cyberstrikeai.sh impl/install_vaultwarden.sh
}

check_generated_backup_headers_are_shell_quoted() {
  if grep -R -nE '^(BACKUP_DIR|DATA_DIR|CONFIG_DIR|INSTALL_DIR|PG_DSN|SERVICE_NAME)="\$\{(BACKUP_DIR|DATA_DIR|CONFIG_DIR|INSTALL_DIR|PG_DSN|SERVICE_NAME)\}"$|^KEEP_DAYS="\$\{BACKUP_KEEP_DAYS\}"$|^LOG_FILE="\$\{LOG_DIR\}/backup\.log"$' \
      impl/install_newapi.sh impl/install_sub2api.sh impl/install_cyberstrikeai.sh 2>/dev/null; then
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
    ' impl/install_newapi.sh
  awk '
      /_write_backup_script\(\)/ { in_func=1; saw_backup=0; saw_data=0; saw_config=0; saw_dsn_file=0; next }
      in_func && /printf -v backup_dir_literal '\''%q'\'' "\$BACKUP_DIR"/ { saw_backup=1 }
      in_func && /printf -v data_dir_literal '\''%q'\'' "\$DATA_DIR"/ { saw_data=1 }
      in_func && /printf -v config_dir_literal '\''%q'\'' "\$CONFIG_DIR"/ { saw_config=1 }
      in_func && /printf -v pg_dsn_file_literal '\''%q'\'' "\$pg_dsn_file"/ { saw_dsn_file=1 }
      in_func && /^BKSH_HEADER$/ {
        if (!(saw_backup && saw_data && saw_config && saw_dsn_file)) {
          printf "%s generated Sub2API backup header must shell-quote configured paths and the DSN file path\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_sub2api.sh
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
    ' impl/install_cyberstrikeai.sh
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
    ' impl/install_newapi.sh
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
    ' impl/install_sub2api.sh
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
    ' impl/install_cyberstrikeai.sh
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
    ' impl/install_vaultwarden.sh
}

check_manual_backup_retention_is_normalized() {
  awk '
      /_ba_prune_backups\(\)/ {
        in_func=1
        saw_guard=0
        saw_positive_guard=0
        saw_find=0
        next
      }
      in_func && /^}/ {
        if (!(saw_guard && saw_positive_guard && saw_find)) {
          printf "%s shared backup retention cleanup must normalize BACKUP_KEEP_DAYS and skip cleanup when it is zero\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
      in_func && /\[\[ "\$keep_days" =~ \^\[0-9\]\+\$ \]\] \|\| keep_days=0/ { saw_guard=1 }
      in_func && /\[\[ "\$keep_days" -gt 0 \]\]/ { saw_positive_guard=1 }
      in_func && /-mtime "\+\$\{keep_days\}"/ { saw_find=1 }
    ' lib/binary_app.sh
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
    ' impl/install_hugo_blog.sh
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
    ' impl/install_sub2api.sh
}

check_backup_retention_cleanup_reports_failures() {
  if grep -R -nE 'rm -f "\$f" && [^|]+ \|\| true|find "\\?\$BACKUP_DIR" -maxdepth 1 .* -delete' \
      impl/install_newapi.sh impl/install_sub2api.sh impl/install_cyberstrikeai.sh impl/install_vaultwarden.sh 2>/dev/null; then
    echo "Backup retention cleanup must report per-file removal failures instead of ignoring them." >&2
    return 1
  fi
  awk '
      /binary_app\.warn\.backup_cleanup_failed/ { saw_framework_warn=1 }
      /app\.newapi\.backup\.log\.remove_failed/ { saw_newapi_log_key=1 }
      /app\.sub2api\.backup\.log\.remove_failed/ { saw_sub2api_log_key=1 }
      /app\.sub2api\.warn\.backup_cleanup_failed/ { saw_sub2api_warn_key=1 }
      /app\.cyberstrikeai\.backup\.warn\.remove_failed/ { saw_csai_log_key=1 }
      /app\.vaultwarden\.backup\.script\.remove_failed/ { saw_vw_log_key=1 }
      END {
        if (!(saw_framework_warn && saw_newapi_log_key && saw_sub2api_log_key && saw_sub2api_warn_key && saw_csai_log_key && saw_vw_log_key)) {
          print "Backup cleanup failure messages must be localized." > "/dev/stderr"
          exit 1
        }
      }
    ' lib/binary_app.sh apps/newapi.sh apps/sub2api.sh apps/cyberstrikeai.sh apps/vaultwarden.sh
  awk '
      /MSG_REMOVE_FAILED="\$\{msg_remove_failed\}"/ { saw_msg=1 }
      /_log "\$\(printf "\$MSG_REMOVE_FAILED" "\$f"\)"/ { saw_log=1 }
      END {
        if (!(saw_msg && saw_log)) {
          printf "%s NewAPI generated backup retention cleanup must log per-file removal failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_newapi.sh
  awk '
      /MSG_REMOVE_FAILED="\$\{msg_remove_failed\}"/ { saw_msg=1 }
      /_log "\$\(printf "\$MSG_REMOVE_FAILED" "\$f"\)"/ { saw_log=1 }
      END {
        if (!(saw_msg && saw_log)) {
          printf "%s Sub2API generated backup retention cleanup must log per-file removal failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_sub2api.sh
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
    ' impl/install_sub2api.sh
  awk '
      /MSG_REMOVE_FAILED="\$\{msg_remove_failed\}"/ { saw_msg=1 }
      index($0, "_log \"[WARN] \\$(printf \"\\$MSG_REMOVE_FAILED\" \"\\$old_backup\")\"") { saw_log=1 }
      END {
        if (!(saw_msg && saw_log)) {
          printf "%s CyberStrikeAI generated backup retention cleanup must log per-file removal failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_cyberstrikeai.sh
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
    ' impl/install_vaultwarden.sh
}

check_optional_count_messages_are_nonfatal() {
  if grep -R -nE '\[\[ (\$\{?REMOVED\}?|\$_cleaned|\$_cleaned_old|\$_cleaned_wv|\$_cnt) -(gt|eq) 0 \]\] &&' \
      impl/install_newapi.sh impl/install_sub2api.sh impl/install_vaultwarden.sh 2>/dev/null; then
    echo "Optional count-based status messages must use explicit if branches so zero counts do not trip set -e." >&2
    return 1
  fi
}

check_silent_backup_tar_diagnostics_use_stderr() {
  if grep -R -n '2>&1 >&2; then' \
      impl/install_sub2api.sh impl/install_vaultwarden.sh 2>/dev/null; then
    echo "Silent backup tar diagnostics must be written directly to stderr." >&2
    return 1
  fi
  awk '
      /_ba_backup\(\)/ { in_func=1; saw_tar=0; saw_stderr=0; next }
      in_func && /if tar -czf/ { saw_tar=1 }
      in_func && / >&2; then/ { saw_stderr=1 }
      in_func && /^}/ {
        if (!(saw_tar && saw_stderr)) {
          printf "%s shared backup helper must send tar diagnostics to stderr\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' lib/binary_app.sh
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
    ' impl/install_sub2api.sh impl/install_vaultwarden.sh
}

check_tar_diagnostics_use_stderr() {
  if grep -R -nE 'tar -(czf|xzf) .*2>&1; then' \
      impl/install_sub2api.sh impl/install_vaultwarden.sh 2>/dev/null; then
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
    ' impl/install_sub2api.sh
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
    ' impl/install_sub2api.sh
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
    ' impl/install_vaultwarden.sh
}


check_backup_all_executes_serially_and_records_manager_operation() {
  local temp_root output status
  temp_root="$(mktemp -d)"
  set +e
  output="$(DEPLOY_OPERATION_ROOT="${temp_root}/state" DEPLOY_OPERATION_LOG_ROOT="${temp_root}/log" "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    manager_status_selected_ids() { printf "alpha\\nbeta\\n"; }
    manager_status_collect_app_json() { printf "{\"install_state\":\"installed\"}" > "$2"; : > "$3"; }
    manager_backup_capability() { printf supported; }
    manager_update_acquire_lock() { return 0; }
    manager_update_release_lock() { :; }
    manager_backup_execute_app() { [[ "$1" == alpha ]] && return 0 || return 7; }
    manager_backup_main --yes --json >/dev/null
  ')"
  status=$?
  set -e
  if [[ "$status" -eq 0 ]]; then
    rm -rf "$temp_root"
    return 1
  fi
  python - "${temp_root}/state/state/manager.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    record = json.load(handle)
assert record["scope"] == "manager"
assert record["action"] == "backup-all"
assert record["state"] == "failed"
assert record["exit_code"] == 1
assert record["steps"][0]["name"] == "execute"
assert record["steps"][0]["state"] == "failed"
PY
  status=$?
  rm -rf "$temp_root"
  return "$status"
}

# Behavioral round-trip for the shared integrity primitives: write a sidecar
# + manifest for a real file, verify passes; flip one archive byte and verify
# fails closed; a bare-digest sidecar is still accepted (cross-version
# compatibility); an archive without metadata reports unverified.
check_backup_finalize_archive_helper() {
  local output
  output="$($BASH_BIN -c '
    set -euo pipefail
    source lib/core.sh
    temp_dir="$(mktemp -d)"
    trap "rm -rf \"$temp_dir\"" EXIT
    archive="$temp_dir/sub2api_data_20260830_000000.tar.gz"
    printf "payload" > "$archive"
    backup_finalize_archive "$archive" sub2api 2.1.0
    backup_verify_archive "$archive"
    [[ "$(backup_manifest_field "$archive.manifest.json" app)" == sub2api ]]
    [[ "$(backup_manifest_field "$archive.manifest.json" installed_version)" == 2.1.0 ]]
    rm -f "$archive"
    ! backup_finalize_archive "$archive" sub2api 2.1.0
    echo ok
  ')"
  [[ "$output" == ok ]]
}

check_sub2api_manual_backups_finalize_integrity() {
  local file=impl/install_sub2api.sh
  local count
  count="$(grep -c 'backup_finalize_archive "\$[A-Z_]*_ARCHIVE' "$file" || true)"
  [[ "$count" -eq 3 ]] || {
    echo "$file must finalize database, config, and data archives with shared metadata" >&2
    return 1
  }
  grep -Fq 'app.sub2api.warn.backup_integrity' "$file" || {
    echo "$file must surface integrity metadata failures" >&2
    return 1
  }
}

check_backup_integrity_primitives() {
  local output
  output="$("$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    temp_dir="$(mktemp -d)"
    trap "rm -rf \"$temp_dir\"" EXIT
    archive="$temp_dir/app_manual_20260101_000000.tar.gz"
    printf "payload-bytes" > "$archive"

    digest="$(backup_write_sha256 "$archive")" || exit 3
    [[ "$digest" =~ ^[0-9a-f]{64}$ ]] || exit 3

    backup_write_manifest "$archive" "app" 1 "1.2.3" || exit 4

    backup_verify_archive "$archive" || exit 5
    [[ "$(backup_read_sha256 "$archive.sha256")" == "$digest" ]] || exit 6

    manifest_digest="$(backup_manifest_field "$archive.manifest.json" sha256)" || exit 7
    [[ "$manifest_digest" == "$digest" ]] || exit 7
    manifest_app="$(backup_manifest_field "$archive.manifest.json" app)" || exit 8
    [[ "$manifest_app" == "app" ]] || exit 8
    manifest_version="$(backup_manifest_field "$archive.manifest.json" installed_version)" || exit 9
    [[ "$manifest_version" == "1.2.3" ]] || exit 9

    # Corrupt the archive: verification must fail.
    printf "X" | dd of="$archive" bs=1 seek=0 conv=notrunc status=none
    backup_verify_archive "$archive" 2>/dev/null && exit 10

    # Bare-digest sidecar (no filename) stays compatible.
    printf "payload-bytes" > "$archive"
    printf "%s\n" "$digest" > "$archive.sha256"
    backup_verify_archive "$archive" || exit 11

    # Archive without sidecar must not verify.
    rm -f "$archive.sha256" "$archive.manifest.json"
    backup_verify_archive "$archive" 2>/dev/null && exit 12

    # Latest-selection JSON verdicts.
    verdict_json="$(backup_verify_latest_json "$temp_dir" "*_manual_*.tar.gz")"
    [[ "$verdict_json" == *"\"state\":\"unverified\""* ]] || exit 13
    backup_write_sha256 "$archive" >/dev/null || exit 14
    backup_write_manifest "$archive" "app" 1 "1.2.3" || exit 14
    verdict_json="$(backup_verify_latest_json "$temp_dir" "*_manual_*.tar.gz")"
    [[ "$verdict_json" == *"\"state\":\"verified\""* ]] || exit 15
    printf corrupted >> "$archive"
    printf "%s  %s\n" "$digest" "$(basename "$archive")" > "$archive.sha256"
    verdict_json="$(backup_verify_latest_json "$temp_dir" "*_manual_*.tar.gz")"
    [[ "$verdict_json" == *"\"state\":\"failed\""* ]] || exit 16
    echo ok
  ')"
  [[ "$output" == ok ]]
}

# Every shared binary-app implementation must expose do_verify delegating to
# bapp_verify, so `verify` reaches every app that can create backups through
# the shared lifecycle. Blog carries its own custom do_verify.
check_binary_impls_have_verify_delegate() {
  local impl
  for impl in install_alist.sh install_beszel.sh install_filebrowser.sh \
      install_frps.sh install_gitea.sh install_gotify.sh \
      install_meilisearch.sh install_navidrome.sh install_ntfy.sh \
      install_newapi.sh; do
    awk -v file="impl/$impl" '
      /^do_verify\(\) \{/ { in_fn=1; next }
      in_fn && /bapp_verify/ { saw=1 }
      in_fn && /^\}/ {
        if (!saw) { printf "%s do_verify must delegate to bapp_verify\n", file > "/dev/stderr"; exit 1 }
        in_fn=0; saw=0
      }
      END { if (in_fn) { printf "%s unterminated do_verify\n", file > "/dev/stderr"; exit 1 } }
    ' "impl/$impl" || return 1
  done
}

# Custom-backup implementations must also expose do_verify, delegating the
# verdict rendering to app_verify_latest_backup with their own archive globs.
check_custom_impls_have_verify_delegate() {
  local impl
  for impl in install_sub2api.sh install_cyberstrikeai.sh \
      install_vaultwarden.sh install_cpa_stack.sh install_tickflow.sh \
      install_hugo_blog.sh; do
    awk -v file="impl/$impl" '
      /^do_verify\(\) \{/ { in_fn=1; next }
      in_fn && /app_verify_latest_backup/ { saw=1 }
      in_fn && /^\}/ {
        if (!saw) { printf "%s do_verify must delegate to app_verify_latest_backup\n", file > "/dev/stderr"; exit 1 }
        in_fn=0; saw=0
      }
      END { if (in_fn) { printf "%s unterminated do_verify\n", file > "/dev/stderr"; exit 1 } }
    ' "impl/$impl" || return 1
  done
}

# Shared-lifecycle apps must expose restore through the shared lifecycle, and
# bapp_restore must verify the archive before touching data, refuse unsafe tar
# members, stop the service before replacing DATA_DIR, and roll back when the
# service cannot start on restored data.
check_shared_impls_have_restore_delegate() {
  local impl
  for impl in install_alist.sh install_beszel.sh install_filebrowser.sh \
      install_frps.sh install_gitea.sh install_gotify.sh \
      install_meilisearch.sh install_navidrome.sh install_ntfy.sh \
      install_newapi.sh; do
    awk -v file="impl/$impl" '
      /^do_restore\(\) \{/ { in_fn=1; next }
      in_fn && /bapp_restore/ { saw=1 }
      in_fn && /^\}/ {
        if (!saw) { printf "%s do_restore must delegate to bapp_restore\n", file > "/dev/stderr"; exit 1 }
        in_fn=0; saw=0
      }
      END { if (in_fn) { printf "%s unterminated do_restore\n", file > "/dev/stderr"; exit 1 } }
    ' "impl/$impl" || return 1
  done
  awk '
    /^bapp_restore\(\)/ { in_fn=1; saw_delegate=0; next }
    in_fn && /backup_restore_data_dir "\$DATA_DIR" "\$SERVICE_NAME"/ { saw_delegate=1 }
    in_fn && /^}$/ {
      if (!saw_delegate) {
        print "bapp_restore must delegate to backup_restore_data_dir" > "/dev/stderr"
        exit 1
      }
      in_fn=0
    }
  ' lib/binary_app.sh || return 1
  # The shared helper carries the safety-critical structure: verify before
  # touching data, unsafe-member rejection, service stop before the swap,
  # rollback when the restored service will not start.
  awk '
    /^backup_restore_data_dir\(\)/ { in_fn=1; saw_verify=0; saw_members=0; saw_stop=0; saw_rollback=0; next }
    in_fn && /backup_verify_archive "\$archive"/ { saw_verify=1 }
    in_fn && index($0, "../*") > 0 { saw_members=1 }
    in_fn && /systemctl stop "\$service_name" \|\| error/ { saw_stop=1 }
    in_fn && /backup\.restore\.rollback_done/ { saw_rollback=1 }
    in_fn && /^}$/ {
      if (!(saw_verify && saw_members && saw_stop && saw_rollback)) {
        print "backup_restore_data_dir must verify archive, reject unsafe members, stop service first, and roll back on failure" > "/dev/stderr"
        exit 1
      }
      in_fn=0
    }
  ' lib/backup.sh
}

# The blog implementation must write integrity metadata after publishing the
# archive and before reporting success, and must provide its own do_verify.
check_blog_backup_writes_integrity_metadata() {
  awk '
    /do_backup\(\)/ { in_backup=1; saw_sidecar=0; saw_manifest=0; next }
    in_backup && /backup_write_sha256 "\$archive"/ { saw_sidecar=1 }
    in_backup && /backup_write_manifest "\$archive"/ { saw_manifest=1 }
    in_backup && /^}/ {
      if (!(saw_sidecar && saw_manifest)) {
        print "blog do_backup must write sha256 sidecar and manifest" > "/dev/stderr"
        exit 1
      }
      in_backup=0
    }
  ' impl/install_hugo_blog.sh || return 1
  grep -q '^do_verify() {' impl/install_hugo_blog.sh
}

# _ba_backup must write integrity metadata after the archive lands and log a
# warning when it cannot, so silent corruption never looks like success.
check_binary_app_backup_writes_integrity_metadata() {
  awk '
    /_ba_backup\(\)/ { in_fn=1; saw_sidecar=0; saw_manifest=0; saw_warn=0; next }
    in_fn && /backup_write_sha256 "\$archive"/ { saw_sidecar=1 }
    in_fn && /backup_write_manifest "\$archive"/ { saw_manifest=1 }
    in_fn && /warn\.integrity_failed/ { saw_warn=1 }
    in_fn && /^}/ {
      if (!(saw_sidecar && saw_manifest && saw_warn)) {
        print "_ba_backup must write sha256+manifest and warn on failure" > "/dev/stderr"
        exit 1
      }
      in_fn=0
    }
  ' lib/binary_app.sh
}

# The four generated cron backup scripts must also publish a sha256 sidecar
# right after the archive lands, so scheduled and manual backups carry the
# same integrity metadata. Quoted heredocs (newapi, sub2api, vaultwarden)
# reference shell vars directly; the unquoted cyberstrikeai heredoc escapes
# them — accept both spellings.
check_generated_backup_scripts_write_sidecars() {
  for impl in install_newapi.sh install_vaultwarden.sh; do
    grep -q 'sha256sum "${ARCHIVE}"' "impl/$impl" \
      || { echo "$impl generated backup script must write a sha256 sidecar" >&2; return 1; }
    grep -q 'chmod 600 "${ARCHIVE}.sha256"' "impl/$impl" \
      || { echo "$impl sidecar must be written with mode 600" >&2; return 1; }
  done
  grep -q 'sha256sum "${PG_DUMP_FILE}"' impl/install_sub2api.sh \
    || { echo "sub2api pg_dump sidecar missing" >&2; return 1; }
  grep -q 'sha256sum "${EXTRA_CONF_ARCHIVE}"' impl/install_sub2api.sh \
    || { echo "sub2api config-archive sidecar missing" >&2; return 1; }
  grep -q 'sha256sum "${ARCHIVE}"' impl/install_sub2api.sh \
    || { echo "sub2api data-archive sidecar missing" >&2; return 1; }
  grep -q 'sha256sum "\\$archive"' impl/install_cyberstrikeai.sh \
    || { echo "cyberstrikeai generated backup script must write a sha256 sidecar" >&2; return 1; }
}

# Registry restore capability must match reality: an app declares "restore"
# only when its impl defines do_restore backed by the shared lifecycle.
check_registry_restore_capability_matches_impl() {
  # shellcheck disable=SC1091
  [[ -v DEPLOY_APP_SPECS ]] || source lib/app_registry.sh
  local app_id impl caps
  while IFS='|' read -r app_id _ _ impl caps; do
    [[ ",${caps}," == *",restore,"* ]] || continue
    [[ -f "$impl" ]] || impl="impl/$impl"
    grep -q '^do_restore() {' "$impl" \
      || { echo "$app_id declares restore capability but $impl has no do_restore" >&2; return 1; }
  done < <(printf '%s\n' "${DEPLOY_APP_SPECS[@]}")
  # Reverse direction: every app whose impl defines do_restore must declare
  # the restore capability, or batch/status planning would report it as
  # unsupported despite the implementation existing (the D3 gap: the nine
  # shared-lifecycle apps implemented bapp_restore but the registry only
  # declared backup).
  local declared_ids=()
  while IFS='|' read -r app_id _ _ _ caps; do
    [[ ",${caps}," == *",restore,"* ]] || continue
    declared_ids+=("$app_id")
  done < <(printf '%s\n' "${DEPLOY_APP_SPECS[@]}")
  local impl_file app
  for impl_file in impl/install_*.sh; do
    grep -q '^do_restore() {' "$impl_file" || continue
    app="${impl_file#impl/install_}"
    app="${app%.sh}"
    case "${app}" in
      hugo_blog) app="blog" ;;
      cpa_stack) app="cpa-stack" ;;
    esac
    case " ${declared_ids[*]} " in
      *" $app "*) : ;;
      *) echo "$impl_file implements do_restore but $app does not declare restore capability" >&2; return 1 ;;
    esac
  done
  # Custom apps restored through the shared data-dir helper, plus the two
  # bespoke multi-artifact restores (sub2api three artifacts, cpa_stack
  # root-relative five paths).
  for app_id in vaultwarden cyberstrikeai; do
    grep -q 'backup_restore_data_dir' "$(deploy_app_impl_file_for "$app_id")" \
      || { echo "$app_id do_restore must delegate to backup_restore_data_dir" >&2; return 1; }
  done
  grep -q '^do_restore() {' impl/install_tickflow.sh \
    || { echo "tickflow declares restore capability but has no do_restore" >&2; return 1; }
  awk '
    /^do_restore\(\)/ { in_fn=1; saw_members=0; saw_stop=0; saw_rollback=0; next }
    in_fn && index($0, "../*") > 0 { saw_members=1 }
    in_fn && /systemctl stop "\$TICKFLOW_SERVICE_NAME"/ { saw_stop=1 }
    in_fn && /backup\.restore\.rollback_done/ { saw_rollback=1 }
    in_fn && /^}$/ {
      if (!(saw_members && saw_stop && saw_rollback)) {
        print "tickflow do_restore must reject unsafe members, stop compose service first, and roll back on failure" > "/dev/stderr"
        exit 1
      }
      in_fn=0
    }
  ' impl/install_tickflow.sh || return 1
  awk '
    /^do_restore\(\)/ { in_fn=1; saw_members=0; saw_stop=0; saw_aside=0; next }
    in_fn && index($0, "../*") > 0 { saw_members=1 }
    in_fn && /systemctl stop "\$CPAMP_SERVICE_NAME"/ { saw_stop=1 }
    in_fn && /restore-aside/ { saw_aside=1 }
    in_fn && /^}$/ {
      if (!(saw_members && saw_stop && saw_aside)) {
        print "cpa_stack do_restore must reject unsafe members, stop CPAMP first, and aside-copy existing targets" > "/dev/stderr"
        exit 1
      }
      in_fn=0
    }
  ' impl/install_cpa_stack.sh || return 1
  awk '
    /^do_restore\(\)/ { in_fn=1; saw_data=0; saw_conf=0; saw_db=0; saw_stop=0; next }
    in_fn && /backup_restore_data_dir "\$DATA_DIR"/ { saw_data=1 }
    in_fn && /sub2api_conf_\*\.tar\.gz/ { saw_conf=1 }
    in_fn && /sub2api_db_\*\.sql\.gz/ { saw_db=1 }
    in_fn && /systemctl stop "\$SERVICE_NAME"/ { saw_stop=1 }
    in_fn && /^}$/ {
      if (!(saw_data && saw_conf && saw_db && saw_stop)) {
        print "sub2api do_restore must cover data tar, config tar, db dump, and stop the service first" > "/dev/stderr"
        exit 1
      }
      in_fn=0
    }
  ' impl/install_sub2api.sh
}

# Behavioral lifecycle test for backup_restore_data_dir, run with a stubbed
# systemctl: (1) clean restore replaces the data and the service restarts,
# (2) a corrupted archive is refused before any change, (3) an archive with
# absolute members is refused, (4) a service that cannot start on restored
# data triggers a full rollback to the previous payload.
check_backup_restore_data_dir_lifecycle() {
  local output
  output="$("$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    mkdir -p "$tmp/bin" "$tmp/backups"
    cat > "$tmp/bin/systemctl" <<'"'"'STUB'"'"'
#!/bin/bash
case "$1 $2" in
  "stop "*) exit 0 ;;
  "start "*)
    mode=$(cat "$RESTART_STATE_FILE" 2>/dev/null || echo normal)
    [[ "$mode" == "never_start" ]] && exit 1
    exit 0 ;;
  "is-active --quiet")
    mode=$(cat "$RESTART_STATE_FILE" 2>/dev/null || echo normal)
    [[ "$mode" == "normal" ]] && exit 0 || exit 3 ;;
esac
exit 0
STUB
    chmod +x "$tmp/bin/systemctl"
    export PATH="$tmp/bin:$PATH"
    export RESTART_STATE_FILE="$tmp/mode"
    DATA_DIR="$tmp/data"
    SERVICE_NAME=testsvc

    # Case 1: clean restore.
    mkdir -p "$DATA_DIR"
    printf original > "$DATA_DIR/file.txt"
    mkdir -p "$tmp/stage/data"
    printf newdata > "$tmp/stage/data/newfile.txt"
    tar -czf "$tmp/backups/app_manual_20260101_000000.tar.gz" -C "$tmp/stage" data
    backup_write_sha256 "$tmp/backups/app_manual_20260101_000000.tar.gz" >/dev/null
    echo normal > "$tmp/mode"
    backup_restore_data_dir "$DATA_DIR" testsvc \
      "$tmp/backups/app_manual_20260101_000000.tar.gz" >/dev/null 2>&1
    grep -q newdata "$DATA_DIR/newfile.txt" || exit 11

    # Case 2: corruption refused before any change.
    printf X | dd of="$tmp/backups/app_manual_20260101_000000.tar.gz" bs=1 seek=0 conv=notrunc status=none
    if (backup_restore_data_dir "$DATA_DIR" testsvc \
        "$tmp/backups/app_manual_20260101_000000.tar.gz") >/dev/null 2>&1; then exit 21; fi
    grep -q newdata "$DATA_DIR/newfile.txt" || exit 22

    # Case 3: absolute-member archive refused.
    rm -f "$tmp/backups"/*.tar.gz "$tmp/backups"/*.sha256
    mkdir -p "$tmp/absdir"; printf x > "$tmp/absdir/x.txt"
    tar -czPf "$tmp/backups/app_manual_20260101_000000.tar.gz" \
      "$tmp/absdir/x.txt" 2>/dev/null \
      || tar -czf "$tmp/backups/app_manual_20260101_000000.tar.gz" "$tmp/absdir/x.txt"
    if (backup_restore_data_dir "$DATA_DIR" testsvc \
        "$tmp/backups/app_manual_20260101_000000.tar.gz") >/dev/null 2>&1; then exit 31; fi

    # Case 4: never-starting service rolls the previous data back.
    rm -f "$tmp/backups"/*.tar.gz "$tmp/backups"/*.sha256
    mkdir -p "$tmp/badstage/data"
    printf broken-data > "$tmp/badstage/data/f.txt"
    tar -czf "$tmp/backups/app_manual_20260101_000000.tar.gz" -C "$tmp/badstage" data
    backup_write_sha256 "$tmp/backups/app_manual_20260101_000000.tar.gz" >/dev/null
    echo never_start > "$tmp/mode"
    if (backup_restore_data_dir "$DATA_DIR" testsvc \
        "$tmp/backups/app_manual_20260101_000000.tar.gz") >/dev/null 2>&1; then exit 41; fi
    grep -rq newdata "$DATA_DIR" 2>/dev/null || exit 42
    echo ok
  ')"
  [[ "$output" == ok ]]
}

# Notification integration invariants: the config file is written through
# atomic_write_file with mode 600, message bodies pass notify_redact before
# leaving, and every failure path of notify_send degrades to a warning with
# a zero exit so notifications can never block an operation. notify-config
# --test must probe the merged values (not the stale disk state) and fail
# loudly instead of claiming success when the probe cannot be delivered.
check_notification_fail_open_and_redaction() {
  awk '
    /^notify_send\(\)/ { in_send=1; saw_trust=0; saw_redact=0; saw_warn=0; next }
    in_send && /notify_load_config \|\|/ { saw_trust=1 }
    in_send && /notify_redact "\$title"/ { saw_redact=1 }
    in_send && /warn "\$\(t notify\.warn\.send_failed/ { saw_warn=1 }
    in_send && /NOTIFY_STRICT/ { saw_strict=1 }
    in_send && /^}$/ {
      if (!(saw_trust && saw_redact && saw_warn && saw_strict)) {
        print "notify_send must gate on trusted config, redact bodies, warn (not fail) on delivery errors, and honor NOTIFY_STRICT" > "/dev/stderr"
        exit 1
      }
      in_send=0
    }
    /^notify_config_main\(\)/ { in_cfg=1; saw_atomic=0; saw_mode=0; saw_probe=0; next }
    in_cfg && /atomic_write_file "\$conf_file" 600/ { saw_atomic=1; saw_mode=1 }
    in_cfg && /NOTIFY_CONF_FILE="\$probe_file"/ { saw_probe=1 }
    in_cfg && /^}$/ {
      if (!(saw_atomic && saw_probe)) {
        print "notify_config_main must persist atomically with mode 600 and probe --test against a staged merged config" > "/dev/stderr"
        exit 1
      }
      in_cfg=0
    }
  ' lib/notify.sh || return 1

  # Behavioral: send with no config is a silent no-op; disabled backend is a
  # no-op; redaction strips KEY=value secrets from delivered bodies; --test
  # with the backend disabled must fail instead of claiming success.
  "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    export NOTIFY_CONF_FILE="$tmp/notify.conf"
    # No config at all: must not fail.
    notify_send "t" "b" >/dev/null 2>&1 || { echo NO_CONFIG_FAILED; exit 51; }

    # Disabled: no-op.
    printf "NOTIFY_ENABLED=\"false\"\nNOTIFY_BACKEND=\"ntfy\"\n" > "$NOTIFY_CONF_FILE"
    chmod 600 "$NOTIFY_CONF_FILE"
    notify_send "t" "b" >/dev/null 2>&1 || { echo DISABLED_FAILED; exit 52; }

    # Strict mode with a disabled backend must fail.
    NOTIFY_STRICT=1 notify_send "t" "b" >/dev/null 2>&1 && { echo DISABLED_STRICT_OK; exit 55; }

    # Enabled ntfy against a local stub server: body must be redacted.
    # (Git Bash cannot chown root, so the trust gate is stubbed here; the
    # structural guard above already asserts it is called.)
    app_conf_trusted_value() { return 0; }
    printf "NOTIFY_ENABLED=\"true\"\nNOTIFY_BACKEND=\"ntfy\"\nNOTIFY_URL=\"%s\"\nNOTIFY_TOPIC=\"topic\"\n" "$tmp/server" > "$NOTIFY_CONF_FILE"
    mkdir -p "$tmp/bin"
    export NOTIFY_BODY_FILE="$tmp/body"
    cat > "$tmp/bin/curl" <<STUB
#!/bin/bash
while (( \$# )); do
  if [[ "\$1" == "--data-binary" ]]; then shift; printf '%s' "\$1" > "\$NOTIFY_BODY_FILE"; fi
  shift
done
echo 200
STUB
    chmod +x "$tmp/bin/curl"
    PATH="$tmp/bin:$PATH" notify_send "title with API_KEY=supersecret inside" \
      "body with DB_PASSWORD=hunter2 inside" >/dev/null 2>&1
    body="$(cat "$NOTIFY_BODY_FILE")"
    [[ "$body" == *DB_PASSWORD[=]*REDACTED* ]] || { echo BODY_NOT_REDACTED_KEY; echo "$body" >&2; exit 53; }
    if [[ "$body" == *hunter2* ]]; then echo BODY_LEAKED_PASSWORD; exit 54; fi

    # Strict delivery failure (curl stub exits non-zero) must fail the send.
    cat > "$tmp/bin/curl" <<STUB2
#!/bin/bash
exit 7
STUB2
    chmod +x "$tmp/bin/curl"
    if PATH="$tmp/bin:$PATH" NOTIFY_STRICT=1 notify_send "t" "b" >/dev/null 2>&1; then
      echo STRICT_DELIVERY_OK; exit 56
    fi
    echo ok
  ' | grep -q ok
}
  # notify-config --test end-to-end: probe the merged values (not stale disk
  # state), fail loudly when delivery fails without persisting anything, and
  # persist the tested configuration only on a successful delivery. Run in a
  # subshell so the stub error() exit cannot terminate the guard process.
  (
    set -euo pipefail
    source lib/core.sh
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    export NOTIFY_CONF_FILE="$tmp/notify.conf"
    require_root() { :; }
    app_conf_trusted_value() { return 0; }
    error() { exit 9; }
    success() { :; }
    info() { :; }
    warn() { :; }
    mkdir -p "$tmp/bin"
    cat > "$tmp/bin/curl" <<'STUB'
#!/bin/bash
c="$(cat "${NOTIFY_COUNT_FILE:-/dev/null}" 2>/dev/null || echo 0)"
c=$((c + 1))
echo "$c" > "${NOTIFY_COUNT_FILE:-/dev/null}"
(( c <= 1 )) && { echo 500; exit 0; }
echo 200
STUB
    chmod +x "$tmp/bin/curl"
    export NOTIFY_COUNT_FILE="$tmp/count"
    : > "$NOTIFY_COUNT_FILE"

    # Fresh config + failing delivery: --test must fail and not persist.
    if ( PATH="$tmp/bin:$PATH" notify_config_main --enable --backend ntfy --url http://example.invalid --topic t --test ) >/dev/null 2>&1; then
      echo TEST_DELIVERY_FAIL_OK; exit 71
    fi
    [[ -e "$NOTIFY_CONF_FILE" ]] && { echo TEST_PERSISTED_ON_FAILURE; exit 72; }

    # Succeeding delivery: --test must persist the merged config.
    PATH="$tmp/bin:$PATH" notify_config_main --enable --backend ntfy --url http://example.invalid --topic t --test >/dev/null 2>&1 \
      || { echo TEST_OK_FAILED; exit 73; }
    [[ -f "$NOTIFY_CONF_FILE" ]] || { echo TEST_OK_NO_PERSIST; exit 74; }
    grep -q '^NOTIFY_ENABLED="true"$' "$NOTIFY_CONF_FILE" || { echo TEST_OK_NOT_ENABLED; exit 75; }
    grep -q '^NOTIFY_TOPIC="t"$' "$NOTIFY_CONF_FILE" || { echo TEST_OK_NOT_MERGED; exit 76; }
  ) || return 1

# Scheduled-batch invariants: units and runner are written atomically with
# restrictive modes, cron expressions are validated before use, unschedule
# removes both systemd and cron artifacts plus the config, and the runner
# path re-enters through deploy.sh so it inherits lock + notification logic.
check_schedule_units_are_atomic_and_cleaned_up() {
  awk '
    /^schedule_load_config\(\)/ { in_load=1; saw_trust=0; next }
    in_load && /app_conf_trusted_value/ { saw_trust=1 }
    in_load && /^}$/ {
      if (!saw_trust) { print "schedule config must be trust-gated like app and notify configs" > "/dev/stderr"; exit 1 }
      in_load=0
    }
    /^schedule_write_runner\(\)/ { in_fn=1; saw_atomic=0; saw_mode=0; next }
    in_fn && /atomic_write_file "\$runner" 750/ { saw_atomic=1; saw_mode=1 }
    in_fn && /^}$/ {
      if (!saw_atomic) { print "schedule runner must be written atomically" > "/dev/stderr"; exit 1 }
      in_fn=0
    }
    /^schedule_apply\(\)/ { in_apply=1; saw_validate=0; next }
    in_apply && /schedule_validate_calendar/ { saw_validate=1 }
    in_apply && /^}$/ {
      if (!saw_validate) { print "schedule_apply must validate the calendar expression up front" > "/dev/stderr"; exit 1 }
      in_apply=0
    }
    /^schedule_validate_calendar\(\)/ { in_val=1; saw_range=0; saw_analyze=0; next }
    in_val && /hour.*-le 23/ { saw_range=1 }
    in_val && /systemd-analyze calendar/ { saw_analyze=1 }
    in_val && /^}$/ {
      if (!(saw_range && saw_analyze)) { print "calendar validation must bound HH:MM and defer to systemd-analyze" > "/dev/stderr"; exit 1 }
      in_val=0
    }
    /^schedule_remove_units\(\)/ { in_rm=1; saw_timer=0; saw_cron=0; next }
    in_rm && /disable --now/ { saw_timer=1 }
    in_rm && /DEPLOY_SCHEDULE_CRON_FILE/ { saw_cron=1 }
    in_rm && /^}$/ {
      if (!(saw_timer && saw_cron)) { print "unschedule must remove both timer and cron artifacts" > "/dev/stderr"; exit 1 }
      in_rm=0
    }
  ' lib/schedule.sh || return 1

  # Behavioral: schedule --disable writes config but installs no units;
  # unschedule removes everything. Force the cron fallback even when the
  # verification host exposes a systemctl binary (for example CI runners).
  DEPLOY_TEST_ROOT="$ROOT_DIR" "$BASH_BIN" -c '
    set -euo pipefail
    cd "$DEPLOY_TEST_ROOT"
    source lib/core.sh
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    export SCHEDULE_CONF_FILE="$tmp/schedule.conf"
    export DEPLOY_SCHEDULE_CRON_FILE="$tmp/deploy-scripts-batch"
    export DEPLOY_SCHEDULE_RUNNER="$tmp/runner"
    require_root() { :; }
    systemctl() { return 1; }
    # The root-owned mode-600 contract is asserted structurally above; this
    # isolated behavior test writes its temporary config as the CI user.
    app_conf_trusted_value() { return 0; }
    error() { echo "ERROR: $*" >&2; exit 9; }
    success() { :; }
    DEPLOY_ROOT_DIR="$tmp/root"
    mkdir -p "$tmp/root"
    printf "#!/bin/bash\n" > "$tmp/root/deploy.sh"

    # Enable: runner + cron file must exist.
    schedule_main schedule --enable --mode check-only --at "03:10"
    [[ -x "$DEPLOY_SCHEDULE_RUNNER" ]] || { echo NO_RUNNER; exit 61; }
    [[ -f "$DEPLOY_SCHEDULE_CRON_FILE" ]] || { echo NO_CRON; exit 62; }
    grep -q "^10 3 \* \* \* root " "$DEPLOY_SCHEDULE_CRON_FILE" || { echo BAD_CRON_SPEC; cat "$DEPLOY_SCHEDULE_CRON_FILE" >&2; exit 63; }

    # Default calendar (no --at) must be representable on the cron fallback:
    # the default for check-only is a plain HH:MM that converts cleanly.
    rm -f "$DEPLOY_SCHEDULE_CRON_FILE" "$DEPLOY_SCHEDULE_RUNNER" "$SCHEDULE_CONF_FILE"
    schedule_main schedule --enable --mode check-only
    [[ -f "$DEPLOY_SCHEDULE_CRON_FILE" ]] || { echo NO_DEFAULT_CRON; exit 66; }
    grep -qE "^0 9 \* \* \* root " "$DEPLOY_SCHEDULE_CRON_FILE" || { echo BAD_DEFAULT_CRON; cat "$DEPLOY_SCHEDULE_CRON_FILE" >&2; exit 67; }

    # Disable: cron file removed, config kept.
    rm -f "$DEPLOY_SCHEDULE_RUNNER"
    schedule_main schedule --disable
    if [[ -f "$DEPLOY_SCHEDULE_CRON_FILE" ]]; then echo CRON_STILL_THERE; exit 64; fi
    if [[ ! -f "$SCHEDULE_CONF_FILE" ]]; then echo CONF_LOST; exit 65; fi

    # CLI subcommand dispatch: `schedule status` must render the status line
    # (not fall through to the config branch), and `--help` must print usage
    # without touching the config file.
    status_out="$(schedule_main status 2>&1)"
    [[ "$status_out" == *enabled=* ]] || { echo STATUS_NOT_RENDERED; echo "$status_out" >&2; exit 68; }
    mtime_before="$(stat -c %Y "$SCHEDULE_CONF_FILE" 2>/dev/null || echo 0)"
    if schedule_main --help >/dev/null 2>&1; then :; fi
    mtime_after="$(stat -c %Y "$SCHEDULE_CONF_FILE" 2>/dev/null || echo 0)"
    [[ "$mtime_before" == "$mtime_after" ]] || { echo HELP_MODIFIED_CONFIG; exit 69; }
    echo ok
  ' | grep -q ok
}

# Scheduled-batch retry contract: schedule_run_main re-invokes the batch up
# to SCHEDULE_RETRIES extra times with exponential backoff, and --retries
# persists a numeric value into the schedule config.
check_schedule_retries_are_configurable() {
  awk '
    /^schedule_run_main\(\)/ { in_fn=1; saw_loop=0; saw_backoff=0; saw_warn=0; next }
    in_fn && /max_attempts=\$\(\( SCHEDULE_RETRIES \+ 1 \)\)/ { saw_loop=1 }
    in_fn && /backoff=\$\(\( backoff \* 2 \)\)/ { saw_backoff=1 }
    in_fn && /schedule\.warn\.retry/ { saw_warn=1 }
    in_fn && /^}$/ {
      if (!(saw_loop && saw_backoff && saw_warn)) {
        print "schedule_run_main must retry with exponential backoff and warn between attempts" > "/dev/stderr"
        exit 1
      }
      in_fn=0
    }
  ' lib/schedule.sh || return 1

  DEPLOY_TEST_ROOT="$ROOT_DIR" "$BASH_BIN" -c '
    set -euo pipefail
    cd "$DEPLOY_TEST_ROOT"
    source lib/core.sh
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    export SCHEDULE_CONF_FILE="$tmp/schedule.conf"
    export DEPLOY_SCHEDULE_RUNNER="$tmp/runner"
    export DEPLOY_SCHEDULE_CRON_FILE="$tmp/cron"
    require_root() { :; }
    # Force the cron path; CI runners can expose a live systemctl while this
    # fixture intentionally uses temporary, unprivileged output paths.
    systemctl() { return 1; }
    error() { exit 9; }
    success() { :; }
    # The test writes configs as the invoking user with default modes; the
    # trust gate is asserted structurally above, so stub it open here.
    app_conf_trusted_value() { return 0; }
    DEPLOY_ROOT_DIR="$tmp/root"
    mkdir -p "$tmp/root"
    # A failing deploy.sh stub that counts invocations.
    cat > "$tmp/root/deploy.sh" <<STUB
#!/bin/bash
echo x >> "\$INVOCATIONS"
exit 3
STUB
    export INVOCATIONS="$tmp/invocations"
    : > "$INVOCATIONS"
    printf "SCHEDULE_ENABLED=\"true\"\nSCHEDULE_MODE=\"update-all\"\nSCHEDULE_RETRIES=\"0\"\n" > "$SCHEDULE_CONF_FILE"
    # Backoff small so the test is fast.
    SCHEDULE_RETRY_BACKOFF=0 schedule_main schedule-run >/dev/null 2>&1 || true
    count=$(wc -l < "$INVOCATIONS")
    [[ "$count" -eq 1 ]] || { echo EXPECTED_1_GOT_$count; exit 82; }

    printf "SCHEDULE_ENABLED=\"true\"\nSCHEDULE_MODE=\"update-all\"\nSCHEDULE_RETRIES=\"2\"\n" > "$SCHEDULE_CONF_FILE"
    : > "$INVOCATIONS"
    SCHEDULE_RETRY_BACKOFF=0 schedule_main schedule-run >/dev/null 2>&1 || true
    count=$(wc -l < "$INVOCATIONS")
    [[ "$count" -eq 3 ]] || { echo EXPECTED_3_GOT_$count; exit 84; }

    # --retries persists into the config.
    schedule_main schedule --enable --mode check-only --at "03:10" --retries 4 --backoff 120 >/dev/null 2>&1
    grep -q "^SCHEDULE_RETRIES=\"4\"$" "$SCHEDULE_CONF_FILE" || { echo RETRIES_NOT_SAVED; exit 85; }
    grep -q "^SCHEDULE_RETRY_BACKOFF=\"120\"$" "$SCHEDULE_CONF_FILE" || { echo BACKOFF_NOT_SAVED; exit 86; }

    # A bad calendar is rejected before any unit file or config is written.
    # Clear the cron file first so "nothing new written" is a meaningful
    # assertion.
    rm -f "$DEPLOY_SCHEDULE_CRON_FILE"
    if schedule_main schedule --enable --mode check-only --at "25:99" >/dev/null 2>&1; then
      echo BAD_CALENDAR_ACCEPTED; exit 87
    fi
    [[ -e "$DEPLOY_SCHEDULE_CRON_FILE" ]] && { echo CRON_WRITTEN_FOR_BAD_CALENDAR; exit 88; }
    grep -q "SCHEDULE_ON_CALENDAR=\"25:99\"" "$SCHEDULE_CONF_FILE" && { echo CONF_WRITTEN_FOR_BAD_CALENDAR; exit 89; }
    echo ok
  ' | grep -q ok
}

# Per-app outcome notifications fire after install/update/backup/restore/
# uninstall actions complete, always through the fail-open notify_send, with
# success/failure derived from the action status.
check_per_app_event_notifications() {
  awk '
    /^operation_run_app_action\(\)/ { in_fn=1; saw_send=0; saw_status=0; saw_case=0; next }
    in_fn && /notify_send/ { saw_send=1 }
    in_fn && /\[\[ \$status -eq 0 \]\]/ { saw_status=1 }
    in_fn && /install\|update\|backup\|restore\|uninstall/ { saw_case=1 }
    in_fn && /^}$/ {
      if (!(saw_send && saw_status && saw_case)) {
        print "operation_run_app_action must notify per-app outcomes with status-derived verdict" > "/dev/stderr"
        exit 1
      }
      in_fn=0
    }
  ' lib/operation.sh || return 1

  # Behavioral: a stubbed action whose function name is provided must route
  # the notification through notify_send (stubbed to capture), once for a
  # success and once for a failure, without altering the exit status.
  DEPLOY_TEST_ROOT="$ROOT_DIR" "$BASH_BIN" -c '
    set -euo pipefail
    cd "$DEPLOY_TEST_ROOT"
    source lib/core.sh
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    export DEPLOY_OPERATION_ROOT="$tmp/state"
    export DEPLOY_OPERATION_LOG_ROOT="$tmp/log"
    export DEPLOY_NOTIFY_SUPPRESS=""
    APP_ID=testapp
    APP_NAME="Test App"
    notify_send() { printf "%s|%s\n" "$1" "$2" >> "$tmp/notifications"; }
    operation_start() { export OPERATION_LOG_PATH="$tmp/log"; return 0; }
    operation_step_start() { return 0; }
    operation_step_finish() { return 0; }
    operation_finish() { return 0; }
    operation_is_valid_action() { return 0; }
    operation_action_exit_trap() { :; }
    operation_restore_signal_traps() { :; }
    operation_restore_exit_trap() { :; }
    do_ok() { return 0; }
    do_bad() { return 42; }
    set +e
    operation_run_app_action backup do_ok >/dev/null 2>&1
    rc_ok=$?
    operation_run_app_action backup do_bad >/dev/null 2>&1
    rc_bad=$?
    set -e
    [[ $rc_ok -eq 0 ]] || { echo RC_OK_WRONG_$rc_ok; exit 91; }
    [[ $rc_bad -eq 42 ]] || { echo RC_BAD_WRONG_$rc_bad; exit 92; }
    [[ -f "$tmp/notifications" ]] || { echo NO_NOTIFICATIONS; exit 93; }
    grep -q "testapp backup succeeded" "$tmp/notifications" || { echo NO_SUCCESS_NOTE; cat "$tmp/notifications" >&2; exit 94; }
    grep -q "testapp backup FAILED" "$tmp/notifications" || { echo NO_FAIL_NOTE; exit 95; }
    echo ok
  ' | grep -q ok
}

# Shared compose layer invariants: both backends resolved, runtime required
# before any run, project paths validated (safe + existing) before use, and
# output streams to stderr so callers control their own formatting. TickFlow
# delegates its probes to the shared layer instead of re-implementing them.
check_compose_shared_layer_and_tickflow_delegation() {
  awk '
    /^compose_command\(\)/ { in_fn=1; saw_plugin=0; saw_legacy=0; next }
    in_fn && /docker compose version/ { saw_plugin=1 }
    in_fn && /docker-compose/ { saw_legacy=1 }
    in_fn && /^}$/ {
      if (!(saw_plugin && saw_legacy)) {
        print "compose_command must probe both docker compose and docker-compose" > "/dev/stderr"
        exit 1
      }
      in_fn=0
    }
    /^compose_validate_project\(\)/ { in_v=1; saw_safe=0; saw_exists=0; next }
    in_v && /is_safe_path/ { saw_safe=1 }
    in_v && /-f "\$project_file"/ { saw_exists=1 }
    in_v && /^}$/ {
      if (!(saw_safe && saw_exists)) {
        print "compose_validate_project must check path safety and file existence" > "/dev/stderr"
        exit 1
      }
      in_v=0
    }
    /^compose_run\(\)/ { in_r=1; saw_require=0; saw_validate=0; saw_stderr=0; next }
    in_r && /compose_require_runtime/ { saw_require=1 }
    in_r && /compose_validate_project/ { saw_validate=1 }
    in_r && />&2/ { saw_stderr=1 }
    in_r && /^}$/ {
      if (!(saw_require && saw_validate && saw_stderr)) {
        print "compose_run must require+validate first and stream to stderr" > "/dev/stderr"
        exit 1
      }
      in_r=0
    }
  ' lib/compose.sh || return 1
  awk '
    /^_compose_bin\(\)/ { in_fn=1; saw=0; next }
    in_fn && /compose_command/ { saw=1 }
    in_fn && /^}$/ { if (!saw) { print "tickflow _compose_bin must delegate to compose_command" > "/dev/stderr"; exit 1 }; in_fn=0 }
    /^_require_compose_runtime\(\)/ { in_r=1; saw_r=0; next }
    in_r && /compose_require_runtime/ { saw_r=1 }
    in_r && /^}$/ { if (!saw_r) { print "tickflow _require_compose_runtime must delegate to compose_require_runtime" > "/dev/stderr"; exit 1 }; in_r=0 }
  ' impl/install_tickflow.sh || return 1

  DEPLOY_TEST_ROOT="$ROOT_DIR" "$BASH_BIN" -c '
    set -euo pipefail
    cd "$DEPLOY_TEST_ROOT"
    source lib/core.sh
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    mkdir -p "$tmp/bin"
    cat > "$tmp/bin/docker" <<'"'"'DOCKER'"'"'
#!/bin/bash
[[ "$1 $2" == "compose version" ]] && exit 0
exit 1
DOCKER
    chmod +x "$tmp/bin/docker"
    export PATH="$tmp/bin:$PATH"
    # Missing project file: compose_try must fail (validation precedes run).
    if compose_try "$tmp" "$tmp/missing.yml" config >/dev/null 2>&1; then
      echo TRY_SHOULD_FAIL; exit 102
    fi
    # compose_command returns a usable backend or empty — never fails.
    compose_command >/dev/null 2>&1 || { echo COMMAND_FAILED; exit 103; }
    # Path validation refuses unsafe inputs.
    if compose_validate_project "$tmp" "/etc/passwd" >/dev/null 2>&1; then
      echo UNSAFE_PROJECT_ACCEPTED; exit 104
    fi
    echo ok
  ' | grep -q ok
}

# Compose lifecycle + health contract: up/down/ps delegate to the shared
# runner; compose_health reads `ps --format json` and fails closed when any
# service is exited or restarting. TickFlow's unit template uses the shared
# backend resolution instead of re-probing docker.
check_compose_lifecycle_and_health() {
  awk '
    /^compose_up\(\)/ { in_fn=1; saw=0; next }
    in_fn && /compose_run "\$1" "\$2" up -d --build/ { saw=1 }
    in_fn && /^}$/ { if (!saw) { print "compose_up must delegate to compose_run" > "/dev/stderr"; exit 1 }; in_fn=0 }
    /^compose_down\(\)/ { in_d=1; saw_d=0; next }
    in_d && /compose_run "\$1" "\$2" down/ { saw_d=1 }
    in_d && /^}$/ { if (!saw_d) { print "compose_down must delegate to compose_run" > "/dev/stderr"; exit 1 }; in_d=0 }
    /^compose_health\(\)/ { in_h=1; saw_ps=0; saw_fail=0; next }
    in_h && /ps --format json/ { saw_ps=1 }
    in_h && index($0, "Exited") > 0 { saw_fail=1 }
    in_h && /^}$/ {
      if (!(saw_ps && saw_fail)) {
        print "compose_health must parse ps json and fail on exited services" > "/dev/stderr"
        exit 1
      }
      in_h=0
    }
  ' lib/compose.sh || return 1
  awk '
    /^_write_systemd_unit\(\)/ { in_fn=1; saw=0; next }
    in_fn && /compose_cmd="\$\(compose_command\)"/ { saw=1 }
    in_fn && /^}$/ { if (!saw) { print "tickflow unit template must use shared compose_command" > "/dev/stderr"; exit 1 }; in_fn=0 }
  ' impl/install_tickflow.sh || return 1

  DEPLOY_TEST_ROOT="$ROOT_DIR" "$BASH_BIN" -c '
    set -euo pipefail
    cd "$DEPLOY_TEST_ROOT"
    source lib/core.sh
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    mkdir -p "$tmp/bin" "$tmp/project"
    printf "services: []\n" > "$tmp/project/compose.yml"
    # Stub docker so compose_command resolves; stub the compose binary
    # itself to emit controlled `ps` output (args contain the base prefix,
    # so match on the ps subcommand positionally).
    cat > "$tmp/bin/docker" <<'"'"'STUB'"'"'
#!/bin/bash
if [[ "$1 $2" == "compose version" ]]; then exit 0; fi
for a in "$@"; do
  if [[ "$a" == "ps" ]]; then
    printf "%s" "$COMPOSE_PS_OUTPUT"
    exit 0
  fi
done
exit 0
STUB
    chmod +x "$tmp/bin/docker"
    export PATH="$tmp/bin:$PATH"
    export COMPOSE_PS_OUTPUT="{\"Service\":\"app\",\"State\":\"running\"}"
    compose_health "$tmp/project" "$tmp/project/compose.yml" || { echo HEALTH_RUNNING_FAILED; exit 111; }
    export COMPOSE_PS_OUTPUT="{\"Service\":\"app\",\"State\":\"Exited\"}"
    if compose_health "$tmp/project" "$tmp/project/compose.yml"; then
      echo HEALTH_EXITED_ACCEPTED; exit 112
    fi
    echo ok
  ' | grep -q ok
}

# Fleet invariants: inventory entries are validated (aliases and targets
# restricted to safe token characters), each host runs under a timeout with
# bounded concurrency and per-host failure isolation, and the aggregated JSON
# never carries credentials — the inventory format has no password field at
# all, and targets are used only as ssh destinations.
check_fleet_host_validation_and_isolation() {
  awk '
    /^fleet_load_hosts\(\)/ { in_fn=1; saw_alias=0; saw_target=0; saw_trust=0; next }
    in_fn && /\[!A-Za-z0-9_-\]/ { saw_alias=1 }
    in_fn && /\[!A-Za-z0-9@.:\\\[\\\]_-\]/ { saw_target=1 }
    in_fn && /stat -c .%U./ { saw_trust=1 }
    in_fn && /^}$/ {
      if (!(saw_alias && saw_target && saw_trust)) {
        print "fleet host validation must restrict alias/target characters and trust-gate the inventory" > "/dev/stderr"
        exit 1
      }
      in_fn=0
    }
    /^fleet_run_host\(\)/ { in_r=1; saw_timeout=0; saw_ok_false=0; saw_record_check=0; next }
    in_r && /timeout "\$\{FLEET_TIMEOUT\}"/ { saw_timeout=1 }
    in_r && /ok.:false/ { saw_ok_false=1 }
    in_r && /grep -qE/ { saw_record_check=1 }
    in_r && /^}$/ {
      if (!(saw_timeout && saw_ok_false && saw_record_check)) {
        print "fleet_run_host must enforce a timeout, isolate failures, and validate remote JSON" > "/dev/stderr"
        exit 1
      }
      in_r=0
    }
  ' lib/fleet.sh || return 1

  DEPLOY_TEST_ROOT="$ROOT_DIR" "$BASH_BIN" -c '
    set -euo pipefail
    cd "$DEPLOY_TEST_ROOT"
    source lib/core.sh
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    # The trust gate is asserted structurally (and behaviorally below); the
    # parsing tests run against a file that stat reports as root:600.
    # (No single quotes inside: the whole body lives in an outer bash -c.)
    stat() {
      case "$2" in
        %U) printf "root\\n" ;;
        %a) printf "600\\n" ;;
        *) printf "root\\n" ;;
      esac
    }
    # Inventory parsing: valid lines load, malformed lines are skipped.
    cat > "$tmp/hosts.conf" <<'"'"'EOF'"'"'
# comment
alpha|user@host1.example.com
bad alias|user@host2.example.com
beta|deploy@10.0.0.5:2222
trailing | space|user@x
gamma|root@[2001:db8::1]
EOF
    FLEET_HOSTS_FILE="$tmp/hosts.conf" fleet_load_hosts
    [[ ${#FLEET_HOSTS[@]} -eq 3 ]] || { echo HOST_COUNT_${#FLEET_HOSTS[@]}; exit 121; }
    [[ "${FLEET_HOSTS[0]}" == "alpha|user@host1.example.com" ]] || { echo HOST0_BAD; exit 122; }
    # ssh args: a port target emits -p, a plain one does not.
    port_args="$(fleet_target_ssh_args "deploy@10.0.0.5:2222")"
    [[ "$port_args" == *" -p 2222" ]] || { echo NO_PORT_ARGS; exit 123; }
    # Concurrency default is bounded.
    [[ "$FLEET_CONCURRENCY" -ge 1 ]] || { echo BAD_CONCURRENCY; exit 124; }
    # An untrusted inventory (stat reports non-root) is ignored entirely.
    unset -f stat 2>/dev/null || true
    stat() {
      case "$2" in
        %U) printf "nobody\\n" ;;
        %a) printf "644\\n" ;;
        *) printf "nobody\\n" ;;
      esac
    }
    printf "sneaky|user@evil.example.com\\n" > "$tmp/untrusted.conf"
    FLEET_HOSTS_FILE="$tmp/untrusted.conf" fleet_load_hosts
    [[ ${#FLEET_HOSTS[@]} -eq 0 ]] || { echo UNTRUSTED_LOADED; exit 125; }
    echo ok
  ' | grep -q ok
}

# Migration invariants: export refuses an empty tree, stamps the archive
# with a sha256 sidecar, import verifies before touching /etc and installs
# configs atomically at mode 600, and the manual-steps guidance is printed
# so operators know binaries/data move via per-app restore.
check_migration_export_import_roundtrip() {
  # A bundle with a traversal member must be refused even when the sidecar
  # checks out. GNU tar strips leading ../ when creating archives, so the
  # malicious member is built here (outside the single-quoted bash -c
  # below, where nested quoting would otherwise collide) with python's
  # tarfile, and its path is handed to the behavioral half.
  local evil_bundle evil_tmp
  evil_tmp="$(mktemp -d)"
  evil_bundle="${evil_tmp}/evil.tar.gz"
  if command -v python >/dev/null 2>&1; then
    python - "$evil_bundle" <<'PY'
import sys, tarfile, io
with tarfile.open(sys.argv[1], "w:gz") as t:
    data = b'PORT="1337"\n'
    info = tarfile.TarInfo("../escape.conf")
    info.size = len(data)
    t.addfile(info, io.BytesIO(data))
PY
  fi
  awk '
    /^migrate_main\(\)/ { in_fn=1; saw_verify=0; saw_atomic=0; saw_manual=0; saw_members=0; next }
    in_fn && /backup_verify_archive "\$input"/ { saw_verify=1 }
    in_fn && /atomic_copy_file "\$f" "\$target" 600/ { saw_atomic=1 }
    in_fn && /migrate\.info\.manual_steps/ { saw_manual=1 }
    in_fn && /unsafe archive member/ { saw_members=1 }
    in_fn && /^}$/ {
      if (!(saw_verify && saw_atomic && saw_manual && saw_members)) {
        print "migrate import must verify first, scan members, install atomically at mode 600, and print manual steps" > "/dev/stderr"
        exit 1
      }
      in_fn=0
    }
  ' lib/migrate.sh || { rm -rf "$evil_tmp"; return 1; }

  EVIL_BUNDLE="$evil_bundle" DEPLOY_TEST_ROOT="$ROOT_DIR" "$BASH_BIN" -c '
    set -euo pipefail
    cd "$DEPLOY_TEST_ROOT"
    source lib/core.sh
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    export MIGRATE_EXPORT_DIR="$tmp/etc"
    export NOTIFY_CONF_FILE="$tmp/etc/deploy-notify.conf"
    export SCHEDULE_CONF_FILE="$tmp/absent-schedule.conf"
    # Test doubles: error() exits the process, which is exactly what the
    # empty-tree assertion below checks for; the subshell isolates that exit.
    require_root() { :; }
    success() { :; }
    info() { :; }
    # Empty tree must be refused. Run in a subshell: the error() helper
    # exits the process, and that is exactly what we assert on.
    if ( error() { exit 9; }
         migrate_main export --output "$tmp/out.tar.gz" ) >/dev/null 2>&1; then
      echo EMPTY_EXPORT_ALLOWED; exit 71
    fi
    error() { echo "ERROR: $*" >&2; exit 9; }

    mkdir -p "$MIGRATE_EXPORT_DIR"
    printf "PORT=\"1234\"\nAPI_TOKEN=\"sekrit\"\n" > "$MIGRATE_EXPORT_DIR/myapp-deploy.conf"
    printf "NOTIFY_ENABLED=\"false\"\nNOTIFY_BACKEND=\"ntfy\"\n" > "$NOTIFY_CONF_FILE"
    migrate_main export --output "$tmp/out.tar.gz" --redact >/dev/null 2>&1 || { echo EXPORT_FAILED; exit 72; }
    [[ -f "$tmp/out.tar.gz" && -f "$tmp/out.tar.gz.sha256" ]] || { echo NO_SIDECAR; exit 73; }
    backup_verify_archive "$tmp/out.tar.gz" || { echo BAD_SIDECAR; exit 74; }
    tar -tzf "$tmp/out.tar.gz" | grep -q "redacted-reference/myapp-deploy.conf.redacted.txt" \
      || { echo NO_REDACTED_REFERENCE; exit 75; }

    rm -f "$MIGRATE_EXPORT_DIR/myapp-deploy.conf" "$NOTIFY_CONF_FILE"
    migrate_main import --input "$tmp/out.tar.gz" >/dev/null 2>&1 || { echo IMPORT_FAILED; exit 76; }
    grep -q "^PORT=" "$MIGRATE_EXPORT_DIR/myapp-deploy.conf" || { echo CONF_NOT_RESTORED; exit 77; }
    # (The mode-600 contract is asserted structurally above against
    # atomic_copy_file; stat modes are unreliable under Windows permission
    # emulation, so the behavioral half checks content only.)

    # Traversal bundle: import must refuse it even with a valid sidecar.
    # The bundle path arrives via EVIL_BUNDLE (set by the outer function)
    # to keep the single-quoted body free of nested quoting. The import is
    # run in a subshell because migrate_main reports refusal through error()
    # (exit), which would otherwise terminate this whole test process.
    evil="${EVIL_BUNDLE:-}"
    if [[ -n "$evil" && -f "$evil" ]]; then
      rm -f "$evil.sha256"
      backup_write_sha256 "$evil" >/dev/null
      if ( migrate_main import --input "$evil" >/dev/null 2>&1 ); then
        echo TRAVERSAL_IMPORT_ACCEPTED; exit 78
      fi
      [[ -e "$MIGRATE_EXPORT_DIR/escape.conf" ]] && { echo TRAVERSAL_WROTE_FILE; exit 79; }
    fi
    echo ok
  ' | grep -q ok
  rm -rf "$evil_tmp"
}
