#!/usr/bin/env bash

atomic_write_file() {
  local target_path="$1"
  local mode="${2:-}"
  local owner="${3:-}"
  local target_dir target_tmp
  target_dir="$(dirname "$target_path")"
  if ! mkdir -p "$target_dir"; then
    return 1
  fi
  if ! target_tmp="$(mktemp "${target_dir}/.$(basename "$target_path").XXXXXX")"; then
    return 1
  fi
  if ! cat > "$target_tmp"; then
    rm -f "$target_tmp"
    return 1
  fi
  if [[ -n "$mode" ]] && ! chmod "$mode" "$target_tmp"; then
    rm -f "$target_tmp"
    return 1
  fi
  if [[ -n "$owner" ]] && ! chown "$owner" "$target_tmp" 2>/dev/null; then
    rm -f "$target_tmp"
    return 1
  fi
  if ! mv "$target_tmp" "$target_path"; then
    rm -f "$target_tmp"
    return 1
  fi
}

atomic_copy_file() {
  local source_path="$1"
  local target_path="$2"
  local mode="${3:-}"
  local owner="${4:-}"
  local target_dir target_tmp
  [[ -f "$source_path" ]] || return 1
  target_dir="$(dirname "$target_path")"
  if ! mkdir -p "$target_dir"; then
    return 1
  fi
  if ! target_tmp="$(mktemp "${target_path}.XXXXXX")"; then
    return 1
  fi
  if ! cp "$source_path" "$target_tmp"; then
    rm -f "$target_tmp"
    return 1
  fi
  if [[ -n "$mode" ]] && ! chmod "$mode" "$target_tmp"; then
    rm -f "$target_tmp"
    return 1
  fi
  if [[ -n "$owner" ]] && ! chown "$owner" "$target_tmp" 2>/dev/null; then
    # Owner normalization is best-effort: on hosts where the caller is not
    # root (or the filesystem does not support chown) the copy itself is
    # still valid, so keep going instead of failing the write.
    :
  fi
  if ! mv "$target_tmp" "$target_path"; then
    rm -f "$target_tmp"
    return 1
  fi
}

atomic_symlink() {
  local target_path="$1"
  local link_path="$2"
  local link_dir link_tmp
  link_dir="$(dirname "$link_path")"
  if ! mkdir -p "$link_dir"; then
    return 1
  fi
  if ! link_tmp="$(mktemp "${link_path}.XXXXXX")"; then
    return 1
  fi
  rm -f "$link_tmp"
  if ! ln -s "$target_path" "$link_tmp" || ! mv -Tf "$link_tmp" "$link_path"; then
    rm -f "$link_tmp"
    return 1
  fi
}
