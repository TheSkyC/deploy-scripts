#!/usr/bin/env bash

# Deployment locking uses dedicated file descriptors with flock:
#
#   fd 7 — framework self-update lock   (lib/self_update.sh)
#   fd 8 — manager-level operation lock (lib/manager_update.sh, shared by
#          update-all and backup-all through manager_update_acquire_lock)
#   fd 9 — per-app deployment lock      (acquire_lock below; every do_* action)
#
# The three levels nest deliberately: a manager batch holds fd 8 for the whole
# run while each app action takes and releases fd 9, and self-update refuses to
# run while any of them is active. Distinct fds keep the scopes independent —
# an app lock must never release the manager lock.
#
# Release discipline: acquire_lock registers release_lock on the shared exit
# handler stack (deploy_add_exit_handler), so the lock is always freed on
# normal exit, error, or signal — do NOT call release_lock explicitly at the
# end of an action; that is dead code and releases early. manager_update.sh
# and self_update.sh hold their locks across multiple app actions, so they
# release explicitly via their own *_release_lock helpers when the batch ends.

declare -ga __DEPLOY_EXIT_HANDLERS=()

deploy_add_exit_handler() {
  local handler="$1"
  [[ -n "$handler" ]] || return 0
  __DEPLOY_EXIT_HANDLERS+=("$handler")
  trap '__deploy_run_exit_handlers' EXIT
}

__deploy_set_exit_status() {
  return "$1"
}

__deploy_run_exit_handlers() {
  local status=$? handler index
  if [[ -n "${__DEPLOY_EXIT_STATUS:-}" ]]; then
    status="$__DEPLOY_EXIT_STATUS"
  fi
  unset __DEPLOY_EXIT_STATUS
  trap - EXIT
  for (( index=${#__DEPLOY_EXIT_HANDLERS[@]} - 1; index >= 0; index-- )); do
    handler="${__DEPLOY_EXIT_HANDLERS[$index]}"
    # Protect the status-setting return from errexit while keeping it visible
    # as `$?` to the handler.
    if __deploy_set_exit_status "$status"; then
      "$handler" || true
    else
      "$handler" || true
    fi
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
