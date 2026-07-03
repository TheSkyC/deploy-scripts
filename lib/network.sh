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

# ── Unified port detection ────────────────────────────────────────

# Returns 0 when a process is listening on the given TCP port.
port_is_listening() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -ltn "( sport = :$port )" 2>/dev/null | tail -n +2 | grep -q .
  elif command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"$port" -sTCP:LISTEN -Pn >/dev/null 2>&1
  else
    return 1
  fi
}

# Prints the process name (or pid/name from ss) bound to the port.
# Returns 0 when a process was identified, 1 otherwise.
port_listening_process() {
  local port="$1"
  if command -v ss >/dev/null 2>&1; then
    ss -ltnp "( sport = :$port )" 2>/dev/null | awk 'NR>1{
      n=$NF; gsub(/^.*"/, "", n); gsub(/"$/,"", n); print n; exit
    }'
    return 0
  elif command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"$port" -sTCP:LISTEN -Pn 2>/dev/null | awk 'NR>1{print $1; exit}'
    return 0
  fi
  return 1
}

# Warns when a port is already in use.  Does NOT abort — the caller
# decides whether to proceed.  Pass an optional label for the port
# (e.g. "Backend port").
app_check_port_conflict() {
  local port="$1"
  local label="${2:-Port $port}"
  if port_is_listening "$port"; then
    local owner
    owner=$(port_listening_process "$port" 2>/dev/null || echo "unknown")
    warn "$(t warn.port_in_use "$label" "$owner")"
    warn "$(t warn.port_release_hint)"
    return 0
  fi
  return 1
}
