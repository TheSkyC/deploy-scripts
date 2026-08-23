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
# The checked variant is intentionally silent so JSON-producing callers can
# handle failures without contaminating stdout. GITHUB_TOKEN, when present,
# is passed to curl only and is never logged or returned.
github_latest_release_tag_checked() {
  local repo="$1" json tag timeout_seconds
  local -a curl_args
  [[ "$repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || return 2
  timeout_seconds="${DEPLOY_GITHUB_API_TIMEOUT_SECONDS:-15}"
  [[ "$timeout_seconds" =~ ^[0-9]+$ && "$timeout_seconds" -gt 0 ]] || timeout_seconds=15
  curl_args=(-fsSL --max-time "$timeout_seconds" -H 'Accept: application/vnd.github+json')
  [[ -n "${GITHUB_TOKEN:-}" ]] && curl_args+=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  json="$(curl "${curl_args[@]}" "https://api.github.com/repos/${repo}/releases/latest" 2>/dev/null)" || return 1
  tag="$(json_tag_name "$json")"
  [[ "${tag:-}" =~ ^v?[0-9] ]] || return 2
  printf '%s\n' "$tag"
}

# Compatibility wrapper for existing lifecycle paths. It retains the prior
# warning-and-empty-output contract while delegating request handling to the
# silent helper used by the central version checker.
github_latest_release_tag() {
  local repo="$1" warn_key="$2" tag
  if ! tag="$(github_latest_release_tag_checked "$repo")"; then
    warn "$(t "$warn_key")"
    printf '\n'
    return 0
  fi
  printf '%s\n' "$tag"
}

is_valid_dns_name() {
  local name="${1:-}"
  # Character classes are collation-dependent: under UTF-8 locales
  # [A-Za-z0-9-] also matches accented characters. Pin C so DNS names stay ASCII.
  local LC_ALL=C
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
# Returns 0 when a process was identified, 1 otherwise (the caller reports
# the owner as unknown).
port_listening_process() {
  local port="$1" owner=""
  if command -v ss >/dev/null 2>&1; then
    owner="$(ss -ltnp "( sport = :$port )" 2>/dev/null | awk 'NR>1{
      n=$NF
      start=index(n, "\"")
      if (start > 0) {
        rest=substr(n, start + 1)
        stop=index(rest, "\"")
        if (stop > 0) print substr(rest, 1, stop - 1)
      }
      exit
    }')" || true
  elif command -v lsof >/dev/null 2>&1; then
    owner="$(lsof -iTCP:"$port" -sTCP:LISTEN -Pn 2>/dev/null | awk 'NR>1{print $1; exit}')" || true
  fi
  [[ -n "$owner" ]] || return 1
  printf '%s\n' "$owner"
  return 0
}

# Warns when a port is already in use; optionally fails the check so callers
# can abort before heavyweight install work instead of at systemctl start.
#
# Usage: app_check_port_conflict PORT [LABEL] [STRICT]
# - Default (STRICT empty/0): warn only, always return 0, so callers may invoke
#   it as a bare command under `set -e` when the port is free.
# - STRICT=1 or DEPLOY_FAIL_ON_PORT_CONFLICT=1: return 1 while the port stays
#   occupied. The warning is emitted in both modes; strict mode adds an abort
#   hint naming the opt-in variable.
app_check_port_conflict() {
  local port="$1"
  local label="${2:-Port $port}"
  local strict="${3:-}"
  if ! port_is_listening "$port"; then
    return 0
  fi
  local owner
  owner=$(port_listening_process "$port" 2>/dev/null || echo "unknown")
  warn "$(t warn.port_in_use "$label" "$owner")"
  warn "$(t warn.port_release_hint)"
  if [[ "$strict" == 1 || "${DEPLOY_FAIL_ON_PORT_CONFLICT:-0}" == 1 ]]; then
    warn "$(t warn.port_conflict_abort)"
    return 1
  fi
  return 0
}
