#!/usr/bin/env bash

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
  trap 'release_lock' EXIT
}

release_lock() {
  flock -u 9 2>/dev/null || true
  exec 9>&- 2>/dev/null || true
}
