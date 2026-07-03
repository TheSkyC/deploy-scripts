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

systemd_write_unit() {
  local unit_path="$1"
  atomic_write_file "$unit_path" 644 root:root
}

service_status_label() {
  local service_name="$1"
  if systemctl is-active --quiet "$service_name" 2>/dev/null; then
    t status.active
  elif systemctl list-unit-files --no-legend --no-pager "$service_name.service" 2>/dev/null \
      | awk '{print $1}' \
      | grep -Fxq "$service_name.service"; then
    t status.inactive
  else
    t status.unknown
  fi
}
