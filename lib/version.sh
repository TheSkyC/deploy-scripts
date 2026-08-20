#!/usr/bin/env bash

# Strict Semantic Version helpers. Callers must only use these helpers when an
# application's release policy explicitly declares its tags comparable.

deploy_version_normalize() {
  local value="${1:-}" normalized prerelease
  local LC_ALL=C

  [[ "$value" =~ ^v?([0]|[1-9][0-9]*)\.([0]|[1-9][0-9]*)\.([0]|[1-9][0-9]*)(-([0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*))?(\+([0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*))?$ ]] || return 1

  normalized="${value#v}"
  prerelease="${BASH_REMATCH[5]:-}"
  if [[ -n "$prerelease" ]]; then
    local identifier
    IFS='.' read -r -a _deploy_version_identifiers <<< "$prerelease"
    for identifier in "${_deploy_version_identifiers[@]}"; do
      [[ "$identifier" =~ ^[0-9]+$ && "$identifier" != "0" && "$identifier" == 0* ]] && return 1
    done
  fi

  # Keep valid build metadata in normalized output. SemVer comparison ignores it.
  printf '%s\n' "$normalized"
}

deploy_version_is_stable() {
  local normalized
  normalized="$(deploy_version_normalize "${1:-}")" || return 1
  [[ "$normalized" != *-* ]]
}

deploy_version_compare_decimal() {
  local left="$1" right="$2"
  local LC_ALL=C

  if (( ${#left} < ${#right} )); then
    printf '%s\n' -1
  elif (( ${#left} > ${#right} )); then
    printf '%s\n' 1
  elif [[ "$left" < "$right" ]]; then
    printf '%s\n' -1
  elif [[ "$left" > "$right" ]]; then
    printf '%s\n' 1
  else
    printf '%s\n' 0
  fi
}

deploy_version_compare_identifier() {
  local left="$1" right="$2"
  local LC_ALL=C

  if [[ "$left" =~ ^[0-9]+$ && "$right" =~ ^[0-9]+$ ]]; then
    deploy_version_compare_decimal "$left" "$right"
  elif [[ "$left" =~ ^[0-9]+$ ]]; then
    printf '%s\n' -1
  elif [[ "$right" =~ ^[0-9]+$ ]]; then
    printf '%s\n' 1
  elif [[ "$left" < "$right" ]]; then
    printf '%s\n' -1
  elif [[ "$left" > "$right" ]]; then
    printf '%s\n' 1
  else
    printf '%s\n' 0
  fi
}

# Prints -1 when the first version is older, 0 when equal, and 1 when newer.
# Invalid versions return status 2 and never silently fall back to lexical order.
deploy_version_compare() {
  local left right left_core right_core left_pre right_pre result
  local -a left_parts right_parts left_identifiers right_identifiers
  local index max_identifiers

  left="$(deploy_version_normalize "${1:-}")" || return 2
  right="$(deploy_version_normalize "${2:-}")" || return 2
  left_core="${left%%[-+]*}"
  right_core="${right%%[-+]*}"
  left_pre=""
  right_pre=""
  [[ "$left" == *-* ]] && left_pre="${left#*-}" && left_pre="${left_pre%%+*}"
  [[ "$right" == *-* ]] && right_pre="${right#*-}" && right_pre="${right_pre%%+*}"

  IFS='.' read -r -a left_parts <<< "$left_core"
  IFS='.' read -r -a right_parts <<< "$right_core"
  for index in 0 1 2; do
    result="$(deploy_version_compare_decimal "${left_parts[$index]}" "${right_parts[$index]}")"
    [[ "$result" == 0 ]] || { printf '%s\n' "$result"; return 0; }
  done

  if [[ -z "$left_pre" && -z "$right_pre" ]]; then
    printf '%s\n' 0
    return 0
  fi
  [[ -z "$left_pre" ]] && { printf '%s\n' 1; return 0; }
  [[ -z "$right_pre" ]] && { printf '%s\n' -1; return 0; }

  IFS='.' read -r -a left_identifiers <<< "$left_pre"
  IFS='.' read -r -a right_identifiers <<< "$right_pre"
  max_identifiers=${#left_identifiers[@]}
  (( ${#right_identifiers[@]} > max_identifiers )) && max_identifiers=${#right_identifiers[@]}
  for ((index = 0; index < max_identifiers; index++)); do
    if (( index >= ${#left_identifiers[@]} )); then
      printf '%s\n' -1
      return 0
    fi
    if (( index >= ${#right_identifiers[@]} )); then
      printf '%s\n' 1
      return 0
    fi
    result="$(deploy_version_compare_identifier "${left_identifiers[$index]}" "${right_identifiers[$index]}")"
    [[ "$result" == 0 ]] || { printf '%s\n' "$result"; return 0; }
  done

  printf '%s\n' 0
}

deploy_version_is_newer() {
  [[ "$(deploy_version_compare "$1" "$2")" == 1 ]]
}

deploy_version_is_older() {
  [[ "$(deploy_version_compare "$1" "$2")" == -1 ]]
}