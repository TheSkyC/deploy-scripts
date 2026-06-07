#!/usr/bin/env bash

wait_for_service() {
  local service_name="$1"
  local timeout="${2:-20}"
  local elapsed=0
  while (( elapsed < timeout )); do
    if systemctl is-active --quiet "$service_name"; then
      return 0
    fi
    if systemctl is-failed --quiet "$service_name"; then
      return 1
    fi
    sleep 1
    elapsed=$((elapsed + 1))
  done
  return 1
}

service_status_label() {
  local service_name="$1"
  if systemctl is-active --quiet "$service_name" 2>/dev/null; then
    t status.active
  elif systemctl list-unit-files "$service_name.service" >/dev/null 2>&1; then
    t status.inactive
  else
    t status.unknown
  fi
}
