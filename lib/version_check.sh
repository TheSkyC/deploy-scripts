#!/usr/bin/env bash

# Shared, read-only GitHub-release version checking with a small on-disk cache.
# Status collection consumes this cache but never calls the network; only the
# central check-update command refreshes expired entries (or all entries with
# --refresh).
DEPLOY_VERSION_CACHE_ROOT="${DEPLOY_VERSION_CACHE_ROOT:-/var/lib/deploy-scripts/version-cache}"
DEPLOY_VERSION_CACHE_TTL_SECONDS="${DEPLOY_VERSION_CACHE_TTL_SECONDS:-21600}"
DEPLOY_VERSION_CACHE_SCHEMA_VERSION=1

version_check_now_epoch() {
  local now="${DEPLOY_VERSION_NOW_EPOCH:-}"
  if [[ "$now" =~ ^[0-9]+$ ]]; then
    printf '%s\n' "$now"
  else
    date +%s
  fi
}

version_check_timestamp_for_epoch() {
  local epoch="$1"
  if date -u -d "@${epoch}" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null; then
    return 0
  fi
  state_now
}

version_cache_file_for() {
  local app_id="$1"
  [[ "$app_id" =~ ^[a-z][a-z0-9_-]{0,63}$ ]] || return 2
  printf '%s/%s.json\n' "${DEPLOY_VERSION_CACHE_ROOT%/}" "$app_id"
}

version_cache_ensure_directory() {
  [[ -n "${DEPLOY_VERSION_CACHE_ROOT:-}" && "${DEPLOY_VERSION_CACHE_ROOT}" = /* ]] || return 1
  [[ ! -L "$DEPLOY_VERSION_CACHE_ROOT" ]] || return 1
  mkdir -p "$DEPLOY_VERSION_CACHE_ROOT" || return 1
  chmod 700 "$DEPLOY_VERSION_CACHE_ROOT" || return 1
}

version_cache_file_is_safe() {
  local file="$1" mode
  [[ -f "$file" && ! -L "$file" ]] || return 1
  if command -v stat >/dev/null 2>&1; then
    # Git Bash translates Windows ACLs to synthetic POSIX modes, so a file
    # successfully chmodded to 0600 can still be reported as 0644. Linux
    # deployments retain the strict group/other-write rejection below.
    case "$(uname -s 2>/dev/null || true)" in MINGW*|MSYS*) return 0 ;; esac
    mode="$(stat -c '%a' "$file" 2>/dev/null || true)"
    [[ "$mode" =~ ^[0-7]{3,4}$ ]] || return 1
    mode="${mode: -3}"
    [[ "${mode:1:1}" == 0 && "${mode:2:1}" == 0 ]] || return 1
  fi
}

version_cache_reset_loaded() {
  VERSION_CACHE_APP_ID=""
  VERSION_CACHE_LATEST=""
  VERSION_CACHE_CHECKED_AT=""
  VERSION_CACHE_SOURCE=""
  VERSION_CACHE_RESULT=""
  VERSION_CACHE_EXPIRES_AT=""
  VERSION_CACHE_EXPIRES_AT_EPOCH=""
  VERSION_CACHE_FRESH=0
}

# Load and validate a successful cache entry. A malformed or unsafe entry is
# treated as a cache miss instead of being trusted as state.
version_cache_load() {
  local app_id="$1" file payload schema cached_app latest checked_at source result expires_at expires_at_epoch now
  version_cache_reset_loaded
  file="$(version_cache_file_for "$app_id")" || return 2
  version_cache_file_is_safe "$file" || return 1
  payload="$(cat "$file")" || return 1
  [[ "$(printf '%s\n' "$payload" | wc -l)" -eq 1 && "$payload" == \{*\} ]] || return 1
  schema="$(state_json_field "$payload" schema_version 2>/dev/null || true)"
  cached_app="$(state_json_field "$payload" app_id 2>/dev/null || true)"
  latest="$(state_json_field "$payload" latest 2>/dev/null || true)"
  checked_at="$(state_json_field "$payload" checked_at 2>/dev/null || true)"
  source="$(state_json_field "$payload" source 2>/dev/null || true)"
  result="$(state_json_field "$payload" result 2>/dev/null || true)"
  expires_at="$(state_json_field "$payload" expires_at 2>/dev/null || true)"
  expires_at_epoch="$(state_json_field "$payload" expires_at_epoch 2>/dev/null || true)"
  [[ "$schema" == "$DEPLOY_VERSION_CACHE_SCHEMA_VERSION" && "$cached_app" == "$app_id" && -n "$latest" && -n "$checked_at" && -n "$expires_at" && "$source" == github_release ]] || return 1
  case "$result" in up_to_date|update_available|unknown) ;; *) return 1 ;; esac
  [[ "$expires_at_epoch" =~ ^[0-9]+$ ]] || return 1
  now="$(version_check_now_epoch)"
  VERSION_CACHE_APP_ID="$cached_app"
  VERSION_CACHE_LATEST="$latest"
  VERSION_CACHE_CHECKED_AT="$checked_at"
  VERSION_CACHE_SOURCE="$source"
  VERSION_CACHE_RESULT="$result"
  VERSION_CACHE_EXPIRES_AT="$expires_at"
  VERSION_CACHE_EXPIRES_AT_EPOCH="$expires_at_epoch"
  (( now <= expires_at_epoch )) && VERSION_CACHE_FRESH=1
  return 0
}

version_check_result_for_versions() {
  local installed="$1" latest="$2" compared
  [[ -n "$installed" && -n "$latest" ]] || { printf 'unknown\n'; return 0; }
  deploy_version_is_stable "$installed" && deploy_version_is_stable "$latest" || { printf 'unknown\n'; return 0; }
  compared="$(deploy_version_compare "$latest" "$installed" 2>/dev/null)" || { printf 'unknown\n'; return 0; }
  case "$compared" in
    1) printf 'update_available\n' ;;
    0) printf 'up_to_date\n' ;;
    *) printf 'unknown\n' ;;
  esac
}

version_check_emit_json() {
  local installed="$1" latest="$2" checked_at="$3" update_state="$4" source="$5" cache_state="$6" error_summary="${7:-}"
  printf '{"installed":%s,"latest":%s,"checked_at":%s,"update_state":%s,"source":%s,"cache_state":%s,"error":%s}' \
    "$(state_json_nullable "$installed")" "$(state_json_nullable "$latest")" "$(state_json_nullable "$checked_at")" \
    "$(app_json_string "$update_state")" "$(app_json_string "$source")" "$(app_json_string "$cache_state")" \
    "$(state_json_nullable "$(operation_safe_summary "$error_summary")")"
}

version_cache_write() {
  local app_id="$1" latest="$2" checked_at="$3" result="$4" source="$5" now expires_at_epoch expires_at file
  now="$(version_check_now_epoch)"
  [[ "$now" =~ ^[0-9]+$ ]] || return 1
  [[ "$DEPLOY_VERSION_CACHE_TTL_SECONDS" =~ ^[0-9]+$ && "$DEPLOY_VERSION_CACHE_TTL_SECONDS" -gt 0 ]] || return 1
  expires_at_epoch=$((now + DEPLOY_VERSION_CACHE_TTL_SECONDS))
  expires_at="$(version_check_timestamp_for_epoch "$expires_at_epoch")" || return 1
  file="$(version_cache_file_for "$app_id")" || return 2
  version_cache_ensure_directory || return 1
  atomic_write_file "$file" 600 <<EOF
{"schema_version":${DEPLOY_VERSION_CACHE_SCHEMA_VERSION},"app_id":$(app_json_string "$app_id"),"checked_at":$(app_json_string "$checked_at"),"latest":$(app_json_string "$latest"),"source":$(app_json_string "$source"),"result":$(app_json_string "$result"),"expires_at":$(app_json_string "$expires_at"),"expires_at_epoch":${expires_at_epoch}}
EOF
}

# Return the last network check without making a network request. Expired
# cache data remains visible but is explicitly marked stale.
version_check_cached_binary_release_json() {
  local app_id="$1" installed="$2" cache_state=miss result
  if version_cache_load "$app_id"; then
    result="$(version_check_result_for_versions "$installed" "$VERSION_CACHE_LATEST")"
    if (( VERSION_CACHE_FRESH )); then
      cache_state=fresh
    else
      result=stale
      cache_state=stale
    fi
    version_check_emit_json "$installed" "$VERSION_CACHE_LATEST" "$VERSION_CACHE_CHECKED_AT" "$result" "$VERSION_CACHE_SOURCE" "$cache_state"
    return 0
  fi
  version_check_emit_json "$installed" "" "" unknown github_release "$cache_state"
}

# Check one binary application. refresh=1 always requests GitHub; without it,
# only cache misses or expired entries are refreshed. no_network=1 never calls
# curl and reports an expired cache as stale.
version_check_binary_release_json() {
  local app_id="$1" repo="$2" installed="$3" refresh="${4:-0}" no_network="${5:-0}"
  local latest checked_at result cache_state=miss
  [[ "$app_id" =~ ^[a-z][a-z0-9_-]{0,63}$ ]] || return 2
  [[ "$repo" =~ ^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$ ]] || {
    version_check_emit_json "$installed" "" "" unsupported github_release unsupported "binary release repository is not configured"
    return 0
  }
  if version_cache_load "$app_id"; then
    if (( ! refresh && VERSION_CACHE_FRESH )); then
      result="$(version_check_result_for_versions "$installed" "$VERSION_CACHE_LATEST")"
      version_check_emit_json "$installed" "$VERSION_CACHE_LATEST" "$VERSION_CACHE_CHECKED_AT" "$result" "$VERSION_CACHE_SOURCE" fresh
      return 0
    fi
    cache_state=stale
  fi
  if [[ "$no_network" == 1 ]]; then
    if [[ -n "$VERSION_CACHE_LATEST" ]]; then
      version_check_emit_json "$installed" "$VERSION_CACHE_LATEST" "$VERSION_CACHE_CHECKED_AT" stale "$VERSION_CACHE_SOURCE" stale
    else
      version_check_emit_json "$installed" "" "" unknown github_release no_network
    fi
    return 0
  fi
  if latest="$(github_latest_release_tag_checked "$repo")"; then
    checked_at="$(state_now)"
    result="$(version_check_result_for_versions "$installed" "$latest")"
    if version_cache_write "$app_id" "$latest" "$checked_at" "$result" github_release; then
      cache_state=refreshed
    else
      cache_state=not_persisted
    fi
    version_check_emit_json "$installed" "$latest" "$checked_at" "$result" github_release "$cache_state"
    return 0
  fi
  if [[ -n "$VERSION_CACHE_LATEST" ]]; then
    version_check_emit_json "$installed" "$VERSION_CACHE_LATEST" "$VERSION_CACHE_CHECKED_AT" stale "$VERSION_CACHE_SOURCE" stale "release check failed; using stale cache"
  else
    version_check_emit_json "$installed" "" "" check_failed github_release miss "release check failed"
  fi
}

# Check one git-branch application. The comparison is the local checkout HEAD
# against the remote branch head after a fetch; refs are not semver, so this
# never touches the version cache and always performs the network round trip
# unless no_network=1, which reports unknown without any fetch.
version_check_git_branch_json() {
  local repo_dir="$1" branch="$2" no_network="${3:-0}"
  local local_rev="" remote_rev result
  if [[ -n "$repo_dir" && -d "$repo_dir/.git" ]]; then
    local_rev="$(git -C "$repo_dir" rev-parse --short HEAD 2>/dev/null || true)"
  fi
  if [[ "$no_network" == 1 ]]; then
    version_check_emit_json "$local_rev" "" "" unknown git_branch miss
    return 0
  fi
  if [[ -z "$repo_dir" || ! -d "$repo_dir/.git" ]]; then
    version_check_emit_json "" "" "" check_failed git_branch miss "installation is not a git checkout"
    return 0
  fi
  if ! git -C "$repo_dir" fetch --quiet --prune origin "$branch" 2>/dev/null; then
    version_check_emit_json "$local_rev" "" "" check_failed git_branch miss "branch fetch failed"
    return 0
  fi
  remote_rev="$(git -C "$repo_dir" rev-parse --short "origin/${branch}" 2>/dev/null || true)"
  if [[ -z "$remote_rev" ]]; then
    version_check_emit_json "$local_rev" "" "" check_failed git_branch miss "cannot resolve remote branch head"
    return 0
  fi
  result=up_to_date
  [[ "$local_rev" != "$remote_rev" ]] && result=update_available
  version_check_emit_json "$local_rev" "$remote_rev" "$(state_now)" "$result" git_branch not_persisted
}