#!/usr/bin/env bash

check_connectivity_urls() {
  local url
  for url in "$@"; do
    if curl -fsSL --max-time 8 -o /dev/null "$url" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

is_valid_dns_name() {
  local name="${1:-}"
  [[ -n "$name" && ${#name} -le 253 ]] || return 1
  [[ "$name" != *..* ]] || return 1
  [[ "$name" =~ ^[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]{0,61}[A-Za-z0-9])?)*$ ]] || return 1
  [[ "$name" == *.* ]] || return 1
  return 0
}
