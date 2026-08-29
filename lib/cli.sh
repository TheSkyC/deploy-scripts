#!/usr/bin/env bash

show_banner() {
  echo -e "\n${BOLD}${CYAN}${APP_NAME:-Deployment Manager}${NC}"
  [[ -n "${APP_DESCRIPTION:-}" ]] && echo -e "${APP_DESCRIPTION}\n"
}

usage() {
  echo "$(t common.usage "$0")" >&2
  echo "      $(t common.no_argument_menu)" >&2
}

show_menu() {
  show_banner
  echo "$(t common.choose_action)"
  echo
  echo "  1) install    - $(t menu.install_desc)"
  echo "  2) update     - $(t menu.update_desc)"
  echo "  3) backup     - $(t menu.backup_desc)"
  echo "  4) restore    - $(t menu.restore_desc)"
  echo "  5) status     - $(t menu.status_desc)"
  echo "  6) doctor     - $(t menu.doctor_desc)"
  echo "  7) uninstall  - $(t menu.uninstall_desc)"
  echo "  q) $(t common.quit)"
  echo
  prompt "$(t common.selection_prompt)"
  local choice
  read -r choice
  dispatch_action "$choice"
}

dispatch_action() {
  local action="${1:-menu}"
  shift || true
  if declare -f deploy_trim >/dev/null 2>&1; then
    action="$(deploy_trim "$action")"
  fi
  case "${action,,}" in
      install|1) operation_run_app_action install do_install "$@" ;;
      update|2) operation_run_app_action update do_update "$@" ;;
      backup|3) operation_run_app_action backup do_backup "$@" ;;
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
      status|5) do_status "$@" ;;
      status-json|json-status) do_status_json "$@" ;;
      doctor|6) do_doctor "$@" ;;
      uninstall|7) operation_run_app_action uninstall do_uninstall "$@" ;;
    menu|"") show_menu ;;
    help|-h|--help) usage ;;
    q|quit|exit) exit 0 ;;
    *) error "$(t common.invalid_choice "$action")" ;;
  esac
}
