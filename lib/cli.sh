#!/usr/bin/env bash

show_banner() {
  echo -e "\n${BOLD}${CYAN}${APP_NAME:-Deployment Manager}${NC}"
  [[ -n "${APP_DESCRIPTION:-}" ]] && echo -e "${APP_DESCRIPTION}\n"
}

usage() {
  t common.usage "$0" >&2
  echo "      $(t common.no_argument_menu)" >&2
  if [[ "${1:-}" == "--help" ]] && declare -p CONFIG_KEYS >/dev/null 2>&1; then
    local key
    echo "" >&2
    t common.help_config_keys >&2
    for key in "${CONFIG_KEYS[@]}"; do
      printf '  %-24s %s\n' "$key" "$(app_print_config_value "$key")" >&2
    done
    echo "" >&2
    t common.help_env_hint >&2
  fi
}

# Display a config value without exposing credential-like configuration in
# help or dry-run output.  The key name is retained so operators can see which
# variable is configured without learning its value.
app_print_config_value() {
  local key="$1"
  if [[ "$key" == *PASS* || "$key" == *TOKEN* || "$key" == *SECRET* || "$key" == *KEY* || "$key" == *DSN* ]]; then
    printf '%s\n' '***'
  else
    printf '%s\n' "${!key:-}"
  fi
}

# Application-level dry-run: prints the actions that install/update/backup/
# uninstall would take and exits without modifying the system. Each do_* and
# bapp_* entry point honors DEPLOY_DRY_RUN=1.
app_dry_run_guard() {
  local action="$1"
  [[ "${DEPLOY_DRY_RUN:-0}" == "1" ]] || return 0
  case "$action" in
    install)
      info "$(t common.dry_run_install "$APP_NAME")"
      app_dry_run_list_config
      ;;
    update)
      info "$(t common.dry_run_update "$APP_NAME")"
      ;;
    backup)
      info "$(t common.dry_run_backup "$APP_NAME")"
      ;;
    uninstall)
      info "$(t common.dry_run_uninstall "$APP_NAME")"
      ;;
    *)
      info "$(t common.dry_run_action "$APP_NAME" "$action")"
      ;;
  esac
  exit 0
}

app_dry_run_list_config() {
  [[ "${DEPLOY_DRY_RUN_SHOW_CONFIG:-0}" == "1" ]] || return 0
  local key
  if declare -p CONFIG_KEYS >/dev/null 2>&1; then
    t common.dry_run_config >&2
    for key in "${CONFIG_KEYS[@]}"; do
      printf '  %-24s %s\n' "$key" "$(app_print_config_value "$key")" >&2
    done
  fi
}

show_menu() {
  show_banner
  t common.choose_action
  echo
  echo "  1) install    - $(t menu.install_desc)"
  echo "  2) update     - $(t menu.update_desc)"
  echo "  3) backup     - $(t menu.backup_desc)"
  echo "  4) restore    - $(t menu.restore_desc)"
  echo "  5) status     - $(t menu.status_desc)"
  echo "  6) doctor     - $(t menu.doctor_desc)"
  echo "  7) uninstall  - $(t menu.uninstall_desc)"
  local menu_no=8
  if declare -f do_verify >/dev/null 2>&1; then
    echo "  ${menu_no}) verify       - $(t menu.verify_desc)"
    menu_no=$((menu_no + 1))
  fi
  if declare -f do_token >/dev/null 2>&1; then
    echo "  ${menu_no}) token        - $(t menu.token_desc)"
    menu_no=$((menu_no + 1))
  fi
  if declare -f do_signups >/dev/null 2>&1; then
    echo "  ${menu_no}) signups      - $(t menu.signups_desc)"
    menu_no=$((menu_no + 1))
  fi
  echo "  q) $(t common.quit)"
  echo
  prompt "$(t common.selection_prompt)"
  local choice
  if ! read -r choice; then
    # stdin reached EOF (non-TTY/scripted invocation): there is no selection
    # to dispatch, so show the usage text instead of failing on the read.
    usage
    return 1
  fi
  dispatch_action "$choice"
}

# Export the app's deployment config before uninstall so the user can restore
# it later. Writes <BACKUP_DIR or /opt>/<app>-deploy-config-<ts>.conf (mode
# 600) and prints a hint about re-importing. Best-effort: failures are
# warnings, never block the uninstall.
app_export_config_before_uninstall() {
  local conf_file dir export_path
  conf_file="$(app_conf_file 2>/dev/null || true)"
  [[ -n "$conf_file" && -f "$conf_file" ]] || return 0
  dir="$(dirname "$conf_file")"
  export_path="${dir}/${APP_ID:-app}-deploy-config-export.conf"
  if [[ -d "${BACKUP_DIR:-}" ]] && [[ -w "${BACKUP_DIR}" ]]; then
    export_path="${BACKUP_DIR}/${APP_ID:-app}-deploy-config-export.conf"
  fi
  if ! atomic_copy_file "$conf_file" "$export_path" 600 2>/dev/null; then
    warn "$(t common.config_export_failed "$conf_file")"
    return 0
  fi
  chmod 600 "$export_path" 2>/dev/null || true
  info "$(t common.config_exported "$export_path")"
  info "$(t common.config_export_restore_hint "$export_path")"
}

dispatch_action() {
  local action="${1:-menu}"
  shift || true
  if declare -f deploy_trim >/dev/null 2>&1; then
    action="$(deploy_trim "$action")"
  fi
  case "${action,,}" in
      install|1) app_dry_run_guard install; operation_run_app_action install do_install "$@" ;;
      update|2) app_dry_run_guard update; operation_run_app_action update do_update "$@" ;;
      backup|3) app_dry_run_guard backup; operation_run_app_action backup do_backup "$@" ;;
      restore|4)
        if declare -f do_restore >/dev/null 2>&1; then
          operation_run_app_action restore do_restore "$@"
        else
          error "$(t error.unsupported_action "${APP_NAME:-app}" restore)"
        fi
        ;;
      cert|https)
        if declare -f do_cert >/dev/null 2>&1; then
          operation_run_app_action cert do_cert "$@"
        else
          error "$(t error.unsupported_action "${APP_NAME:-app}" cert)"
        fi
        ;;
      verify)
        if declare -f do_verify >/dev/null 2>&1; then
          operation_run_app_action verify do_verify "$@"
        else
          error "$(t error.unsupported_action "${APP_NAME:-app}" verify)"
        fi
        ;;
      token)
        if declare -f do_token >/dev/null 2>&1; then
          operation_run_app_action token do_token "$@"
        else
          error "$(t error.unsupported_action "${APP_NAME:-app}" token)"
        fi
        ;;
      signups)
        if declare -f do_signups >/dev/null 2>&1; then
          operation_run_app_action signups do_signups "$@"
        else
          error "$(t error.unsupported_action "${APP_NAME:-app}" signups)"
        fi
        ;;
      --dry-run|--dryrun)
        DEPLOY_DRY_RUN=1
        DEPLOY_DRY_RUN_SHOW_CONFIG=1
        export DEPLOY_DRY_RUN DEPLOY_DRY_RUN_SHOW_CONFIG
        if (($#)); then
          dispatch_action "$@"
        else
          error "$(t common.dry_run_requires_action "$APP_NAME")"
        fi
        ;;
      status|5) do_status "$@" ;;
      status-json|json-status) do_status_json "$@" ;;
      doctor|6) do_doctor "$@" ;;
      uninstall|7)
        app_dry_run_guard uninstall
        app_export_config_before_uninstall
        operation_run_app_action uninstall do_uninstall "$@" ;;
    menu|"") show_menu ;;
    help|-h|--help) usage --help ;;
    q|quit|exit) exit 0 ;;
    *) error "$(t common.invalid_choice "$action")" ;;
  esac
}

