#!/usr/bin/env bash

app_binary_restore_moved_backup() {
  local backup_path="$1"
  local restore_tmp
  [[ -n "$backup_path" && -f "$backup_path" ]] || return 0
  [[ ! -e "$BIN_PATH" ]] || return 1
  if ! restore_tmp="$(mktemp "${BIN_PATH}.restore.XXXXXX")"; then
    return 1
  fi
  if ! cp "$backup_path" "$restore_tmp"; then
    rm -f "$restore_tmp"
    return 1
  fi
  if ! chmod +x "$restore_tmp" \
      || ! chown "${SERVICE_USER}:${SERVICE_USER}" "$restore_tmp" \
      || ! mv "$restore_tmp" "$BIN_PATH"; then
    rm -f "$restore_tmp"
    return 1
  fi
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
  local restore_tmp
  [[ -f "$backup_path" ]] || return 1
  if ! restore_tmp="$(mktemp "${BIN_PATH}.restore.XXXXXX")"; then
    return 1
  fi
  if ! cp "$backup_path" "$restore_tmp"; then
    rm -f "$restore_tmp"
    return 1
  fi
  if ! chmod +x "$restore_tmp" \
      || ! chown "${SERVICE_USER}:${SERVICE_USER}" "$restore_tmp" \
      || ! mv "$restore_tmp" "$BIN_PATH"; then
    rm -f "$restore_tmp"
    return 1
  fi
}

app_binary_backup_current() {
  local backup_path="$1"
  atomic_copy_file "$BIN_PATH" "$backup_path"
}
