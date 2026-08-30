#!/usr/bin/env bash

# Atomically copy an executable into place with the caller's required mode and
# ownership. Unlike atomic_copy_file, an owner is mandatory when supplied: a
# rollback must never appear successful while leaving a service binary owned
# by the wrong account. Source and destination may be the same path.
# Usage: app_install_executable_file SOURCE DESTINATION OWNER MODE
app_install_executable_file() {
  local source_path="$1" destination_path="$2" owner="${3:-}" mode="${4:-0755}"
  local destination_dir restore_tmp
  [[ -f "$source_path" ]] || return 1
  destination_dir="$(dirname "$destination_path")"
  if ! mkdir -p "$destination_dir"; then
    return 1
  fi
  if ! restore_tmp="$(mktemp "${destination_path}.restore.XXXXXX")"; then
    return 1
  fi
  if ! cp "$source_path" "$restore_tmp" \
      || ! chmod "$mode" "$restore_tmp"; then
    rm -f "$restore_tmp"
    return 1
  fi
  if [[ -n "$owner" ]] && ! chown "$owner" "$restore_tmp"; then
    rm -f "$restore_tmp"
    return 1
  fi
  if ! mv "$restore_tmp" "$destination_path"; then
    rm -f "$restore_tmp"
    return 1
  fi
}

app_binary_restore_moved_backup() {
  local backup_path="$1"
  [[ -n "$backup_path" && -f "$backup_path" ]] || return 0
  [[ ! -e "$BIN_PATH" ]] || return 1
  app_install_executable_file "$backup_path" "$BIN_PATH" "${SERVICE_USER}:${SERVICE_USER}" 0755 \
    || return 1
  rm -f "$backup_path"
}

app_binary_install_candidate() {
  local tmp_bin="$1"
  local backup_path="${2:-}"
  if [[ -n "$backup_path" && -f "$BIN_PATH" ]]; then
    if ! mv "$BIN_PATH" "$backup_path"; then
      rm -f "$tmp_bin"
      return 1
    fi
  fi
  if ! mv "$tmp_bin" "$BIN_PATH"; then
    rm -f "$tmp_bin"
    app_binary_restore_moved_backup "$backup_path" || return 1
    return 1
  fi
  if ! chmod +x "$BIN_PATH" || ! chown "${SERVICE_USER}:${SERVICE_USER}" "$BIN_PATH"; then
    rm -f "$BIN_PATH"
    app_binary_restore_moved_backup "$backup_path" || return 1
    return 1
  fi
}

app_binary_restore_backup() {
  local backup_path="$1"
  app_install_executable_file "$backup_path" "$BIN_PATH" "${SERVICE_USER}:${SERVICE_USER}" 0755
}

app_binary_backup_current() {
  local backup_path="$1"
  atomic_copy_file "$BIN_PATH" "$backup_path"
}
