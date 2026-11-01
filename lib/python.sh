#!/usr/bin/env bash

# Shared Python interpreter resolution for framework helpers that parse JSON
# payloads (for example the self-update smoke check). Linux distributions ship
# python3 while some development environments only provide the unversioned
# `python` command, so callers must never assume one exact name.
deploy_python_cmd() {
  local candidate
  if [[ -n "${DEPLOY_PYTHON:-}" ]] && command -v "$DEPLOY_PYTHON" >/dev/null 2>&1; then
    printf '%s\n' "$DEPLOY_PYTHON"
    return 0
  fi
  for candidate in python3 python; do
    if command -v "$candidate" >/dev/null 2>&1; then
      printf '%s\n' "$candidate"
      return 0
    fi
  done
  return 1
}
