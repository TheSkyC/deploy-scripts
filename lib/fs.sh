#!/usr/bin/env bash

require_root() {
  local action="${1:-}"
  [[ ${EUID:-$(id -u)} -eq 0 ]] || error "$(t error.root_required "$0" "$action")"
}

require_command() {
  local command_name="$1"
  command -v "$command_name" >/dev/null 2>&1 || error "$(t error.command_required "$command_name")"
}

is_safe_path() {
  local path="${1:-}"
  [[ -n "$path" ]] || return 1
  [[ "$path" = /* ]] || return 1

  while [[ "$path" != "/" && "$path" == */ ]]; do
    path="${path%/}"
  done

  case "$path" in
    /|.|..|*'/../'*|*'/..'|*'/./'*|*'/.')
      return 1
      ;;
    /bin|/boot|/dev|/etc|/home|/lib|/lib64|/opt|/proc|/root|/run|/sbin|/sys|/tmp|/usr|/var|/usr/local)
      return 1
      ;;
  esac

  # Reject every top-level directory (for example /srv, /mnt, /data):
  # deployment and deletion targets must always live inside a named
  # subdirectory.  This keeps the guard fail-closed instead of relying on an
  # exhaustive blacklist of mount points.
  local remainder="${path#/}"
  [[ "$remainder" == */* ]] || return 1

  # Additional nested system directories that must never be targets.
  case "$path" in
    /var/lib|/var/log|/var/www|/var/cache|/var/run|/var/spool|/usr/local/bin|/usr/local/lib|/usr/share|/mnt|/media|/srv|/data|/backup|/www|/export|/pool)
      return 1
      ;;
  esac
  return 0
}

require_safe_path() {
  local name="$1"
  local path="$2"
  is_safe_path "$path" || error "$(t error.unsafe_path "$name" "${path:-empty}")"
}

safe_rm_dir() {
  local path="$1"
  local name="${2:-path}"
  while [[ "$path" != "/" && "$path" == */ ]]; do
    path="${path%/}"
  done
  require_safe_path "$name" "$path"
  [[ -e "$path" || -L "$path" ]] || return 0
  [[ -d "$path" || -L "$path" ]] || return 1
  rm -rf -- "$path"
}
