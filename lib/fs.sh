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
    /bin|/boot|/dev|/etc|/home|/lib|/lib64|/opt|/proc|/root|/run|/sbin|/sys|/tmp|/usr|/var|/var/lib|/var/log|/usr/local|/usr/local/bin)
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
