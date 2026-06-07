#!/usr/bin/env bash

sanitize_conf_val() {
  local value="${1%%$'\n'*}"
  value="${value//\"/}"
  echo "$value"
}

config_file_is_safe() {
  local conf_file="$1"
  [[ -f "$conf_file" ]] || return 0

  if command -v stat >/dev/null 2>&1; then
    local owner mode
    owner="$(stat -c '%U' "$conf_file" 2>/dev/null || echo unknown)"
    mode="$(stat -c '%a' "$conf_file" 2>/dev/null || echo 777)"
    [[ "$owner" == "root" ]] || { warn "$(t warn.config_owner "$conf_file" "$owner")"; return 1; }
    [[ "$mode" == "600" || "$mode" == "400" ]] || { warn "$(t warn.config_permission "$conf_file" "$mode")"; return 1; }
  fi
  return 0
}

load_config_file() {
  local conf_file="$1"
  shift
  local -a allowed_keys=("$@")
  [[ -f "$conf_file" ]] || return 0
  config_file_is_safe "$conf_file" || return 1

  local line key value allowed
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ "$line" =~ ^[[:space:]]*(#|$) || "$line" != *=* ]] && continue
    key="${line%%=*}"
    key="${key// /}"
    if [[ ! "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
      warn "$(t warn.config_invalid_key "$key")"
      continue
    fi
    value="${line#*=}"
    if [[ "$value" =~ ^\"(.*)\"$ ]]; then
      value="${BASH_REMATCH[1]}"
    fi
    allowed=false
    local allowed_key
    for allowed_key in "${allowed_keys[@]}"; do
      if [[ "$key" == "$allowed_key" ]]; then
        allowed=true
        break
      fi
    done
    $allowed || { warn "$(t warn.config_unknown_key "$key")"; continue; }
    printf -v "$key" '%s' "$value"
  done < "$conf_file"
}

write_config_file() {
  local conf_file="$1"
  shift
  local tmp_file
  tmp_file="$(mktemp "${conf_file}.tmp.XXXXXX")"
  chmod 600 "$tmp_file"
  local key value
  for key in "$@"; do
    value="$(sanitize_conf_val "${!key:-}")"
    printf '%s="%s"\n' "$key" "$value" >> "$tmp_file"
  done
  chown root:root "$tmp_file" 2>/dev/null || true
  mv "$tmp_file" "$conf_file"
}
