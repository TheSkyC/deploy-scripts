#!/usr/bin/env bash

sanitize_conf_val() {
  local newline=$'\n'
  local carriage_return=$'\r'
  local value="${1%%"${newline}"*}"
  value="${value%%"${carriage_return}"*}"
  value="${value//\"/}"
  echo "$value"
}

trim_conf_token() {
  local value="$1"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

config_file_is_safe() {
  local conf_file="$1"
  [[ -f "$conf_file" ]] || return 0

  if command -v stat >/dev/null 2>&1; then
    local owner mode
    owner="$(stat -c '%U' "$conf_file" 2>/dev/null || echo unknown)"
    mode="$(stat -c '%a' "$conf_file" 2>/dev/null || echo 777)"
    [[ "$owner" == "root" ]] || error "$(t error.config_owner "$conf_file")"
    [[ "$mode" == "600" || "$mode" == "400" ]] || error "$(t error.config_permission "$conf_file")"
  fi
  return 0
}

load_config_file() {
  local conf_file="$1"
  # Character ranges in regexes are collation-dependent: under en_US.UTF-8 /
  # zh_CN.UTF-8, [A-Z0-9] also matches lowercase. Pin the C locale so config
  # keys must be uppercase on every server locale.
  local LC_ALL=C
  shift
  local -a allowed_keys=("$@")
  [[ -f "$conf_file" ]] || return 0
  config_file_is_safe "$conf_file" || return 1

  local line key value allowed
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    [[ "$line" =~ ^[[:space:]]*(#|$) || "$line" != *=* ]] && continue
    key="$(trim_conf_token "${line%%=*}")"
    if [[ ! "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
      warn "$(t warn.config_invalid_key "$key")"
      continue
    fi
    value="$(trim_conf_token "${line#*=}")"
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
    # printf -v would clobber the deployment shell's own state for reserved
    # names; the allow-list normally gates keys, but keep a defense-in-depth
    # guard so future CONFIG_KEYS cannot expose IFS/PATH and similar.
    case "$key" in
      IFS|PATH|BASH_ENV|ENV|SHELLOPTS|BASHOPTS|PS4|CDPATH|GLOBIGNORE)
        warn "$(t warn.config_reserved_key "$key")"
        continue
        ;;
    esac
    # A blank value means "not configured": keep the script default instead of
    # clobbering it. Older configs can store empty placeholders for keys that
    # later gained pinned defaults (e.g. EXTRACT_TOOL_SHA256); applying them
    # would make validation fail.
    [[ -z "$value" ]] && continue
    printf -v "$key" '%s' "$value"
  done < "$conf_file"
}

_write_config_file_content() {
  local key value
  for key in "$@"; do
    value="$(sanitize_conf_val "${!key:-}")"
    printf '%s="%s"\n' "$key" "$value"
  done
}

write_config_file() {
  local conf_file="$1"
  shift
  atomic_write_command_file "$conf_file" 600 root:root _write_config_file_content "$@"
}
