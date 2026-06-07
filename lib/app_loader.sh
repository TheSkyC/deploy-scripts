#!/usr/bin/env bash

app_impl_script_path() {
  local script="${APP_IMPL_SCRIPT:-}"
  if [[ "${DEPLOY_BUNDLED:-0}" == "1" ]]; then
    local bundle_dir
    bundle_dir="${DEPLOY_BUNDLED_IMPL_DIR:-${TMPDIR:-/tmp}/deploy-scripts/${APP_ID:-app}}"
    mkdir -p "$bundle_dir"
    chmod 700 "$bundle_dir" 2>/dev/null || true
    echo "${bundle_dir}/${BUNDLED_APP_IMPL_SCRIPT_NAME}"
    return 0
  fi
  [[ -n "$script" ]] || error "APP_IMPL_SCRIPT is not configured for ${APP_ID:-unknown}"
  if [[ "$script" = /* ]]; then
    echo "$script"
  else
    echo "${DEPLOY_ROOT_DIR}/${script}"
  fi
}

ensure_bundled_app_impl_script() {
  [[ "${DEPLOY_BUNDLED:-0}" == "1" ]] || return 0
  local script_path tmp_path
  script_path="$(app_impl_script_path)"
  tmp_path="${script_path}.$$"
  awk "/^__DEPLOY_APP_IMPL_SCRIPT__$/ { found=1; next } found { print }" "${BASH_SOURCE[0]}" > "$tmp_path"
  [[ -s "$tmp_path" ]] || error "Bundled app implementation payload is empty"
  chmod 700 "$tmp_path"
  mv "$tmp_path" "$script_path"
}

restore_framework_functions() {
  info() { echo -e "${BLUE}[i]${NC} $*" >&2; }
  success() { echo -e "${GREEN}[+]${NC} $*" >&2; }
  warn() { echo -e "${YELLOW}[!]${NC} $*" >&2; }
  error() { echo -e "${RED}[x]${NC} $*" >&2; exit 1; }
  step() { echo -e "\n${CYAN}${BOLD}== $* ==${NC}" >&2; }
  prompt() { echo -ne "${YELLOW}[?]${NC} $* " >&2; }

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
}

load_app_impl() {
  APP_IMPL_SCRIPT="$1"
  ensure_bundled_app_impl_script
  local script_path
  script_path="$(app_impl_script_path)"
  [[ -f "$script_path" ]] || error "App implementation script not found: $script_path"
  DEPLOY_IMPL_SOURCE_ONLY=1 source "$script_path"
  unset DEPLOY_IMPL_SOURCE_ONLY
  restore_framework_functions
}
