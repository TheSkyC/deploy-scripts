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
