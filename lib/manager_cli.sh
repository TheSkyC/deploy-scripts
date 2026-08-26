#!/usr/bin/env bash

manager_usage() {
  echo "$(t manager.usage "$0")" >&2
  echo "$(t manager.usage_examples "$0" "$0" "$0")" >&2
  echo "$(t manager.available_apps "$(deploy_app_ids | tr '\n' ' ' | sed 's/[[:space:]]*$//')")" >&2
}

show_manager_banner() {
  echo -e "\n${BOLD}${CYAN}$(t manager.title)${NC}"
  echo -e "$(t manager.description)\n"
}

show_manager_menu() {
  show_manager_banner
  echo "$(t manager.choose_app)"
  echo

  local index=1 app_id app_name
  for app_id in "${DEPLOY_APP_IDS[@]}"; do
    app_name="$(deploy_app_name_for "$app_id")"
    printf '  %s) %-16s %s\n' "$index" "$app_id" "$app_name"
    index=$((index + 1))
  done
  echo "  s) $(t manager.status_all)"
  echo "  p) $(t manager.problems)"
  echo "  u) $(t manager.check_updates)"
  echo "  f) $(t manager.check_self_update)"
  echo "  q) $(t common.quit)"
  echo

  prompt "$(t manager.selection_prompt)"
  local choice app_id status
  read -r choice
  case "${choice,,}" in
    s|status-all) manager_status_main status-all; return ;;
    p|problems) manager_status_main problems; return ;;
    u|check-update) manager_update_main; return ;;
    f|self-update) self_update_main --check; return ;;
    q|quit|exit) exit 0 ;;
  esac
  set +e
  app_id="$(deploy_app_id_from_selection "$choice")"
  status=$?
  set -e
  if [[ "$status" -eq 2 ]]; then
    exit 0
  fi
  if [[ "$status" -ne 0 ]]; then
    error "$(t manager.invalid_app "$choice")"
  fi
  manager_load_app "$app_id"
  show_menu
}

manager_load_app() {
  local app_id="$1" app_file
  if [[ "${DEPLOY_BUNDLED_MANAGER:-0}" == "1" ]]; then
    BUNDLED_APP_IMPL_SCRIPT_NAME="$(deploy_app_bundled_impl_script_name_for "$app_id")"
    manager_source_bundled_app_definition "$app_id"
    return 0
  fi
  app_file="$(deploy_app_file_for "$app_id")" || error "$(t manager.invalid_app "$app_id")"
  app_file="${DEPLOY_ROOT_DIR}/${app_file}"
  [[ -f "$app_file" ]] || error "$(t manager.app_file_missing "$app_file")"
  source "$app_file"
}

manager_source_bundled_app_definition() {
  local app_id="$1" marker
  marker="__DEPLOY_APP_DEFINITION__ ${app_id}"
  if ! grep -qxF "$marker" "${BASH_SOURCE[0]}"; then
    error "$(t manager.app_definition_missing "$app_id")"
  fi
  source <(
    awk -v marker="$marker" '
      $0 == marker { found=1; next }
      found && $0 == "__DEPLOY_APP_DEFINITION_END__" { exit }
      found { print }
    ' "${BASH_SOURCE[0]}"
  )
}

manager_list_apps() {
  local app_id app_name
  for app_id in "${DEPLOY_APP_IDS[@]}"; do
    app_name="$(deploy_app_name_for "$app_id")"
    printf '%-16s %s\n' "$app_id" "$app_name"
  done
}

manager_main() {
  local command="${1:-menu}" app_id status action
  command="$(deploy_trim "$command")"
  case "${command,,}" in
    overview|status-all|problems|health-all)
      shift || true
      manager_status_main "${command,,}" "$@"
      ;;
    doctor-all)
      shift || true
      manager_doctor_main "$@"
      ;;
    backup-all)
      shift || true
      manager_backup_main "$@"
      ;;
    notify-config)
      shift || true
      notify_config_main "$@"
      ;;
    schedule|unschedule)
      shift || true
      schedule_main "$command" "$@"
      ;;
    schedule-run)
      shift || true
      schedule_run_main "$@"
      ;;
    check-update)
      shift || true
      manager_update_main "$@"
      ;;
    update-all)
      shift || true
      manager_update_all_main "$@"
      ;;
    history)
      shift || true
      manager_history_main "$@"
      ;;
    self-version)
      shift || true
      local self_version_json=0 self_version_arg
      while (($#)); do
        self_version_arg="$1"
        case "$self_version_arg" in
          --json) self_version_json=1; shift ;;
          -h|--help) printf '%s\n' "Usage: deploy.sh self-version [--json]" >&2; return 0 ;;
          *) printf 'self-version: unknown option: %s\n' "$self_version_arg" >&2; return 2 ;;
        esac
      done
      self_update_load_config || { printf 'self-version: invalid self-update configuration\n' >&2; return 1; }
      self_update_print_version "$self_version_json"
      ;;
    self-update)
      shift || true
      self_update_main "$@"
      ;;
    menu|"")
      show_manager_menu
      ;;
    list|apps)
      manager_list_apps
      ;;
    help|-h|--help)
      manager_usage
      ;;
    q|quit|exit)
      exit 0
      ;;
    *)
      set +e
      app_id="$(deploy_app_id_from_selection "$command")"
      status=$?
      set -e
      if [[ "$status" -eq 2 ]]; then
        exit 0
      fi
      if [[ "$status" -ne 0 ]]; then
        manager_usage
        error "$(t manager.invalid_app "$command")"
      fi
      shift || true
      action="${1:-menu}"
      manager_load_app "$app_id"
      dispatch_action "$action"
      ;;
  esac
}
