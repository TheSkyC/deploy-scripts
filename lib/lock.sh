#!/usr/bin/env bash

declare -ga __DEPLOY_EXIT_HANDLERS=()

deploy_add_exit_handler() {
  local handler="$1"
  [[ -n "$handler" ]] || return 0
  __DEPLOY_EXIT_HANDLERS+=("$handler")
  trap '__deploy_run_exit_handlers' EXIT
}

__deploy_run_exit_handlers() {
  local status=$? handler index
  trap - EXIT
  for (( index=${#__DEPLOY_EXIT_HANDLERS[@]} - 1; index >= 0; index-- )); do
    handler="${__DEPLOY_EXIT_HANDLERS[$index]}"
    "$handler" || true
  done
  exit "$status"
}

acquire_lock() {
  local lock_file="${1:-${LOCK_FILE:-}}"
  [[ -n "$lock_file" ]] || return 0
  if ! mkdir -p "$(dirname "$lock_file")"; then
    error "$(t error.lock_failed "$lock_file")"
  fi
  if ! exec 9>"$lock_file"; then
    error "$(t error.lock_failed "$lock_file")"
  fi
  flock -n 9 || error "$(t error.lock_failed "$lock_file")"
  if [[ "${__DEPLOY_LOCK_EXIT_REGISTERED:-0}" != "1" ]]; then
    deploy_add_exit_handler release_lock
    __DEPLOY_LOCK_EXIT_REGISTERED=1
  fi
}

release_lock() {
  flock -u 9 2>/dev/null || true
  exec 9>&- 2>/dev/null || true
}
