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

# Checks that at least one of the given endpoints is reachable; when none
# respond, fails the script through the given i18n error key.
app_check_connectivity() {
  local error_key="$1"
  shift
  if ! check_connectivity_urls "$@"; then
    error "$(t "$error_key")"
  fi
}

# Extracts the "tag_name" field from a GitHub releases/latest JSON payload.
# Pass --strip-v to drop a leading "v" (for example "v1.2.3" -> "1.2.3").
# Prints nothing when the payload has no parseable tag_name.
json_tag_name() {
  local json="$1" strip_v=false tag
  if [[ "${2:-}" == "--strip-v" ]]; then
    strip_v=true
  fi
  if echo "test" | grep -qP 'test' 2>/dev/null; then
    tag=$(printf '%s' "$json" | grep -oP '"tag_name"\s*:\s*"\K[^"]+' 2>/dev/null | head -1 || true)
  fi
  if [[ -z "${tag:-}" ]]; then
    tag=$(printf '%s' "$json" | grep '"tag_name"' | head -1 \
      | sed 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' 2>/dev/null || true)
  fi
  if $strip_v; then
    tag="${tag#v}"
  fi
  printf '%s\n' "$tag"
}

# Fetches the latest release tag for a GitHub repository (owner/repo).
# Prints the tag (with or without a leading "v") when it looks like a
# version, otherwise prints nothing and warns with the given i18n key.
github_latest_release_tag() {
  local repo="$1" warn_key="$2"
  local json tag
  json=$(curl -fsSL --max-time 15 \
    "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null) \
    || { warn "$(t "$warn_key")"; echo ""; return; }
  tag="$(json_tag_name "$json")"
  if [[ "${tag:-}" =~ ^v?[0-9] ]]; then
    echo "$tag"
  else
    echo ""
  fi
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
#
# This helper only warns: it always returns 0 so callers may invoke it as a
# bare command under `set -e` without aborting when the port is free.
app_check_port_conflict() {
  local port="$1"
  local label="${2:-Port $port}"
  if port_is_listening "$port"; then
    local owner
    owner=$(port_listening_process "$port" 2>/dev/null || echo "unknown")
    warn "$(t warn.port_in_use "$label" "$owner")"
    warn "$(t warn.port_release_hint)"
  fi
  return 0
}
