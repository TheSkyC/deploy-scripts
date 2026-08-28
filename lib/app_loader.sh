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

# The framework logging helpers and CLI dispatch (info/success/warn/error/
# step/prompt, show_banner, usage, show_menu, dispatch_action) live in
# lib/logging.sh and lib/cli.sh, which load before the app implementation.
# Implementation scripts define only their own do_* / hook functions and
# never re-define framework functions, so no restore step is needed: keeping
# a copy here would drift from the real definitions (O12: `verify` was added
# to cli.sh but not to the old app_loader copy). This hook stays for
# backward compatibility but is intentionally a no-op.
restore_framework_functions() {
  :
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
