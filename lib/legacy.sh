#!/usr/bin/env bash

legacy_script_path() {
  local script="${LEGACY_SCRIPT:-}"
  [[ -n "$script" ]] || error "LEGACY_SCRIPT is not configured for ${APP_ID:-unknown}"
  if [[ "$script" = /* ]]; then
    echo "$script"
  else
    echo "${DEPLOY_ROOT_DIR}/${script}"
  fi
}

legacy_dispatch() {
  local action="$1"
  local script_path
  script_path="$(legacy_script_path)"
  [[ -f "$script_path" ]] || error "Legacy script not found: $script_path"
  exec bash "$script_path" "$action"
}
