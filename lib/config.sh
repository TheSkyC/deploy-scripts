#!/usr/bin/env bash

sanitize_conf_val() {
  local value="${1%%$'\n'*}"
  value="${value//\"/}"
  echo "$value"
}

load_config_file() {
  local conf_file="$1"
  shift
  local -a allowed_keys=("$@")
  [[ -f "$conf_file" ]] || return 0

  if command -v stat >/dev/null 2>&1; then
    local owner mode
    owner="$(stat -c '%U' "$conf_file" 2>/dev/null || echo root)"
    mode="$(stat -c '%a' "$conf_file" 2>/dev/null || echo 600)"
    [[ "$owner" == "root" ]] || error "$(t error.config_owner "$conf_file")"
    [[ "$mode" == "600" || "$mode" == "400" ]] || error "$(t error.config_permission "$conf_file")"
  fi

  local line key value allowed
  while IFS= read -r line || [[ -n "$line" ]]; do
    [[ -z "$line" || "$line" == \#* || "$line" != *=* ]] && continue
    key="${line%%=*}"
    value="${line#*=}"
    allowed=false
    local allowed_key
    for allowed_key in "${allowed_keys[@]}"; do
      if [[ "$key" == "$allowed_key" ]]; then
        allowed=true
        break
      fi
    done
    $allowed || continue
    [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]] || continue
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
    printf '%s=%s\n' "$key" "$value" >> "$tmp_file"
  done
  chown root:root "$tmp_file" 2>/dev/null || true
  mv "$tmp_file" "$conf_file"
}
