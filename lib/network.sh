#!/usr/bin/env bash

check_connectivity_urls() {
  local url
  for url in "$@"; do
    if curl -fsI --connect-timeout 5 --max-time 10 "$url" >/dev/null 2>&1; then
      return 0
    fi
  done
  return 1
}
