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
  [[ -n "$path" && "$path" != "/" && "$path" != "." ]]
}

require_safe_path() {
  local name="$1"
  local path="$2"
  is_safe_path "$path" || error "$(t error.unsafe_path "$name" "${path:-empty}")"
}

safe_rm_dir() {
  local path="$1"
  local name="${2:-path}"
  require_safe_path "$name" "$path"
  [[ -d "$path" ]] && rm -rf "$path"
}
