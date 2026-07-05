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
  echo "  4) status     - $(t menu.status_desc)"
  echo "  5) uninstall  - $(t menu.uninstall_desc)"
  echo "  q) $(t common.quit)"
  echo
  prompt "$(t common.selection_prompt)"
  local choice
  read -r choice
  dispatch_action "$choice"
}

dispatch_action() {
  local action="${1:-menu}"
  if declare -f deploy_trim >/dev/null 2>&1; then
    action="$(deploy_trim "$action")"
  fi
  case "${action,,}" in
    install|1) do_install ;;
    update|2) do_update ;;
    backup|3) do_backup ;;
    status|4) do_status ;;
    uninstall|5) do_uninstall ;;
    menu|"") show_menu ;;
    q|quit|exit) exit 0 ;;
    *) error "$(t common.invalid_choice "$action")" ;;
  esac
}
