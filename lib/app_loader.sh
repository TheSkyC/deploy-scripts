#!/usr/bin/env bash

ensure_bundled_impl_dir() {
  [[ "${DEPLOY_BUNDLED:-0}" == "1" ]] || return 0
  [[ -n "${DEPLOY_BUNDLED_IMPL_DIR:-}" ]] && return 0

  local tmp_root
  tmp_root="${TMPDIR:-/tmp}"
  tmp_root="${tmp_root%/}"
  DEPLOY_BUNDLED_IMPL_DIR="$(mktemp -d "${tmp_root}/deploy-scripts.${APP_ID:-app}.XXXXXX")" \
    || error "Failed to create bundled implementation directory"
  if ! chmod 700 "$DEPLOY_BUNDLED_IMPL_DIR"; then
    safe_rm_dir "$DEPLOY_BUNDLED_IMPL_DIR" "bundled implementation directory"
    unset DEPLOY_BUNDLED_IMPL_DIR
    error "Failed to secure bundled implementation directory"
  fi
}

app_impl_script_path() {
  local script="${APP_IMPL_SCRIPT:-}"
  if [[ "${DEPLOY_BUNDLED:-0}" == "1" ]]; then
    ensure_bundled_impl_dir
    echo "${DEPLOY_BUNDLED_IMPL_DIR}/${BUNDLED_APP_IMPL_SCRIPT_NAME}"
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
  ensure_bundled_impl_dir
  script_path="$(app_impl_script_path)"
  tmp_path="$(mktemp "${script_path}.XXXXXX")" \
    || error "Failed to create bundled app implementation payload"
  local marker
  marker="__DEPLOY_APP_IMPL_SCRIPT__ ${BUNDLED_APP_IMPL_SCRIPT_NAME:-}"
  if grep -qxF "$marker" "${BASH_SOURCE[0]}"; then
    if ! awk -v marker="$marker" '
        $0 == marker { found=1; next }
        found && $0 == "__DEPLOY_APP_IMPL_SCRIPT_END__" { exit }
        found { print }
      ' "${BASH_SOURCE[0]}" > "$tmp_path"; then
      rm -f "$tmp_path"
      cleanup_bundled_app_impl_script
      error "Failed to extract bundled implementation payload"
    fi
  elif ! awk "/^__DEPLOY_APP_IMPL_SCRIPT__$/ { found=1; next } found { print }" "${BASH_SOURCE[0]}" > "$tmp_path"; then
    rm -f "$tmp_path"
    cleanup_bundled_app_impl_script
    error "Failed to extract bundled app implementation payload"
  fi
  if [[ ! -s "$tmp_path" ]]; then
    rm -f "$tmp_path"
    cleanup_bundled_app_impl_script
    error "Bundled app implementation payload is empty"
  fi
  if ! chmod 700 "$tmp_path"; then
    rm -f "$tmp_path"
    cleanup_bundled_app_impl_script
    error "Failed to secure bundled app implementation payload"
  fi
  if ! mv "$tmp_path" "$script_path"; then
    rm -f "$tmp_path"
    cleanup_bundled_app_impl_script
    error "Failed to install bundled app implementation payload"
  fi
}

cleanup_bundled_app_impl_script() {
  [[ "${DEPLOY_BUNDLED:-0}" == "1" ]] || return 0
  [[ -n "${DEPLOY_BUNDLED_IMPL_DIR:-}" ]] || return 0
  safe_rm_dir "$DEPLOY_BUNDLED_IMPL_DIR" "bundled implementation directory"
  unset DEPLOY_BUNDLED_IMPL_DIR
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
    if declare -f deploy_trim >/dev/null 2>&1; then
      action="$(deploy_trim "$action")"
    fi
    case "${action,,}" in
      install|1) do_install ;;
      update|2) do_update ;;
      backup|3) do_backup ;;
      restore|4)
        if declare -f do_restore >/dev/null 2>&1; then
          do_restore
        else
          error "$(t error.unsupported_action "${APP_NAME:-app}" restore)"
        fi
        ;;
      status|5) do_status ;;
      doctor|6) do_doctor ;;
      uninstall|7) do_uninstall ;;
      menu|"") show_menu ;;
      q|quit|exit) exit 0 ;;
      *) error "$(t common.invalid_choice "$action")" ;;
    esac
  }
}

load_app_impl() {
  APP_IMPL_SCRIPT="$1"
  ensure_bundled_impl_dir
  ensure_bundled_app_impl_script
  local script_path
  script_path="$(app_impl_script_path)"
  [[ -f "$script_path" ]] || error "App implementation script not found: $script_path"
  if DEPLOY_IMPL_SOURCE_ONLY=1 source "$script_path"; then
    unset DEPLOY_IMPL_SOURCE_ONLY
    cleanup_bundled_app_impl_script
  else
    local source_status=$?
    unset DEPLOY_IMPL_SOURCE_ONLY
    cleanup_bundled_app_impl_script
    return "$source_status"
  fi
  restore_framework_functions
}
