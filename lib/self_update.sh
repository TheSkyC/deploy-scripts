#!/usr/bin/env bash

# Framework identity, release-manifest validation, and managed-release activation.
# Checkout and standalone executions remain strictly read-only.

DEPLOY_SELF_UPDATE_URL="${DEPLOY_SELF_UPDATE_URL:-}"
DEPLOY_SELF_UPDATE_CHANNEL="${DEPLOY_SELF_UPDATE_CHANNEL:-stable}"
DEPLOY_SELF_UPDATE_CONFIG_FILE="${DEPLOY_SELF_UPDATE_CONFIG_FILE:-/etc/deploy-scripts/self-update.conf}"
DEPLOY_SELF_UPDATE_ROOT="${DEPLOY_SELF_UPDATE_ROOT:-/opt/deploy-scripts}"
DEPLOY_SELF_UPDATE_TIMEOUT_SECONDS="${DEPLOY_SELF_UPDATE_TIMEOUT_SECONDS:-30}"
DEPLOY_SELF_UPDATE_MAX_MANIFEST_BYTES="${DEPLOY_SELF_UPDATE_MAX_MANIFEST_BYTES:-1048576}"
DEPLOY_SELF_UPDATE_MAX_ARTIFACT_BYTES="${DEPLOY_SELF_UPDATE_MAX_ARTIFACT_BYTES:-536870912}"
DEPLOY_SELF_UPDATE_KEEP_RELEASES="${DEPLOY_SELF_UPDATE_KEEP_RELEASES:-3}"

SELF_UPDATE_MODE="unknown"
SELF_UPDATE_ROOT=""
SELF_UPDATE_VERSION=""
SELF_UPDATE_PREVIOUS_VERSION=""
SELF_UPDATE_CURRENT_PATH=""
SELF_UPDATE_PREVIOUS_PATH=""
SELF_UPDATE_MANAGED_ROOT=""
SELF_UPDATE_MANIFEST_VERSION=""
SELF_UPDATE_MANIFEST_URL=""
SELF_UPDATE_MANIFEST_SHA256=""
SELF_UPDATE_MANIFEST_SIZE_BYTES=""
SELF_UPDATE_MANIFEST_NAME=""
SELF_UPDATE_MANIFEST_ERROR=""
SELF_UPDATE_MANIFEST_VALID=1
SELF_UPDATE_MANAGER_LOCK_ACQUIRED=0

self_update_validate_channel() {
  [[ "${1:-}" =~ ^[a-z][a-z0-9_-]{0,31}$ ]]
}

self_update_validate_https_url() {
  local url="${1:-}"
  [[ "$url" =~ ^https://[A-Za-z0-9.-]+(:[0-9]+)?(/[A-Za-z0-9._~:/%+-]*)?$ ]]
}

self_update_realpath() {
  local path="$1" resolved
  if command -v readlink >/dev/null 2>&1 && resolved="$(readlink -f -- "$path" 2>/dev/null)" && [[ -n "$resolved" ]]; then
    printf '%s\n' "$resolved"
    return 0
  fi
  (cd -- "$(dirname -- "$path")" && printf '%s/%s\n' "$PWD" "$(basename -- "$path")")
}

self_update_release_version_from_root() {
  local root="$1" metadata project version schema
  metadata="${root}/RELEASE.json"
  [[ -f "$metadata" ]] || return 1
  [[ "$(stat -c '%s' "$metadata" 2>/dev/null || printf 0)" -gt 0 ]] || return 1
  project="$(state_json_field "$(cat "$metadata")" project 2>/dev/null || true)"
  version="$(state_json_field "$(cat "$metadata")" version 2>/dev/null || true)"
  schema="$(state_json_field "$(cat "$metadata")" schema_version 2>/dev/null || true)"
  [[ "$schema" == 1 && "$project" == deploy-scripts ]] || return 1
  [[ "$version" =~ ^v([0]|[1-9][0-9]*)\.([0]|[1-9][0-9]*)\.([0]|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$ ]] || return 1
  printf '%s\n' "$version"
}

self_update_managed_root_for() {
  local root="$1" parent grandparent
  parent="$(dirname -- "$root")"
  grandparent="$(dirname -- "$parent")"
  if [[ "$(basename -- "$root")" == current ]]; then
    printf '%s\n' "$parent"
  elif [[ "$(basename -- "$parent")" == releases ]]; then
    printf '%s\n' "$grandparent"
  else
    printf '%s\n' "$root"
  fi
}

self_update_previous_version_for() {
  local managed_root="$1" previous_root version
  previous_root="${managed_root}/previous"
  [[ -e "$previous_root" || -L "$previous_root" ]] || return 0
  version="$(self_update_release_version_from_root "$previous_root" 2>/dev/null || true)"
  [[ -n "$version" ]] && printf '%s\n' "$version"
}

self_update_load_config() {
  local configured_url="${DEPLOY_SELF_UPDATE_URL:-}"
  local configured_channel="${DEPLOY_SELF_UPDATE_CHANNEL:-stable}"
  local configured_timeout="${DEPLOY_SELF_UPDATE_TIMEOUT_SECONDS:-30}"
  local configured_max_manifest="${DEPLOY_SELF_UPDATE_MAX_MANIFEST_BYTES:-1048576}"
  local configured_max_artifact="${DEPLOY_SELF_UPDATE_MAX_ARTIFACT_BYTES:-536870912}"
  local configured_keep_releases="${DEPLOY_SELF_UPDATE_KEEP_RELEASES:-3}"
  local config_file="${DEPLOY_SELF_UPDATE_CONFIG_FILE:-/etc/deploy-scripts/self-update.conf}"

  DEPLOY_SELF_UPDATE_URL=""
  DEPLOY_SELF_UPDATE_CHANNEL="stable"
  DEPLOY_SELF_UPDATE_TIMEOUT_SECONDS="30"
  DEPLOY_SELF_UPDATE_MAX_MANIFEST_BYTES="1048576"
  DEPLOY_SELF_UPDATE_MAX_ARTIFACT_BYTES="536870912"
  DEPLOY_SELF_UPDATE_KEEP_RELEASES="3"
  if [[ -f "$config_file" ]]; then
    load_config_file "$config_file" \
      DEPLOY_SELF_UPDATE_URL DEPLOY_SELF_UPDATE_CHANNEL \
      DEPLOY_SELF_UPDATE_TIMEOUT_SECONDS DEPLOY_SELF_UPDATE_MAX_MANIFEST_BYTES \
      DEPLOY_SELF_UPDATE_MAX_ARTIFACT_BYTES DEPLOY_SELF_UPDATE_KEEP_RELEASES \
      DEPLOY_SELF_UPDATE_REQUIRE_SIGNATURE DEPLOY_SELF_UPDATE_PUBLIC_KEY || return 1
  fi
  [[ -z "$configured_url" ]] || DEPLOY_SELF_UPDATE_URL="$configured_url"
  [[ -z "$configured_channel" ]] || DEPLOY_SELF_UPDATE_CHANNEL="$configured_channel"
  [[ -z "$configured_timeout" ]] || DEPLOY_SELF_UPDATE_TIMEOUT_SECONDS="$configured_timeout"
  [[ -z "$configured_max_manifest" ]] || DEPLOY_SELF_UPDATE_MAX_MANIFEST_BYTES="$configured_max_manifest"
  [[ -z "$configured_max_artifact" ]] || DEPLOY_SELF_UPDATE_MAX_ARTIFACT_BYTES="$configured_max_artifact"
  [[ -z "$configured_keep_releases" ]] || DEPLOY_SELF_UPDATE_KEEP_RELEASES="$configured_keep_releases"
  self_update_validate_channel "$DEPLOY_SELF_UPDATE_CHANNEL" || return 1
  [[ "$DEPLOY_SELF_UPDATE_TIMEOUT_SECONDS" =~ ^[0-9]+$ && "$DEPLOY_SELF_UPDATE_TIMEOUT_SECONDS" -gt 0 ]] || return 1
  [[ "$DEPLOY_SELF_UPDATE_MAX_MANIFEST_BYTES" =~ ^[1-9][0-9]*$ ]] || return 1
  [[ "$DEPLOY_SELF_UPDATE_MAX_ARTIFACT_BYTES" =~ ^[1-9][0-9]*$ ]] || return 1
  [[ "$DEPLOY_SELF_UPDATE_KEEP_RELEASES" =~ ^[3-9][0-9]*$ ]] || return 1
}

self_update_detect_mode() {
  local root="${DEPLOY_ROOT_DIR:-}" metadata_version managed_root
  SELF_UPDATE_MODE=unknown
  SELF_UPDATE_ROOT="$root"
  SELF_UPDATE_VERSION=""
  SELF_UPDATE_PREVIOUS_VERSION=""
  SELF_UPDATE_CURRENT_PATH=""
  SELF_UPDATE_PREVIOUS_PATH=""
  SELF_UPDATE_MANAGED_ROOT=""
  [[ -n "$root" ]] || return 0

  # A checkout takes precedence over metadata so a developer worktree can
  # never be mistaken for a writable managed installation.
  if [[ -e "${root}/.git" ]]; then
    SELF_UPDATE_MODE=checkout
    return 0
  fi
  if metadata_version="$(self_update_release_version_from_root "$root" 2>/dev/null)"; then
    local configured_root root_real configured_real current_real
    configured_root="${DEPLOY_SELF_UPDATE_ROOT:-/opt/deploy-scripts}"
    root_real="$(self_update_realpath "$root")"
    configured_real="$(self_update_realpath "$configured_root")"
    current_real="$(self_update_realpath "${configured_root}/current")"
    if [[ "$root_real" == "$current_real" || "$root_real" == "$configured_real/releases/"* ]]; then
      SELF_UPDATE_MODE=managed_release
      SELF_UPDATE_VERSION="$metadata_version"
      managed_root="$configured_root"
      SELF_UPDATE_MANAGED_ROOT="$managed_root"
      SELF_UPDATE_CURRENT_PATH="${managed_root}/current"
      SELF_UPDATE_PREVIOUS_PATH="${managed_root}/previous"
      SELF_UPDATE_PREVIOUS_VERSION="$(self_update_previous_version_for "$managed_root" || true)"
      return 0
    fi
  fi
  if [[ "${DEPLOY_BUNDLED:-0}" == 1 ]]; then
    SELF_UPDATE_MODE=standalone_dist
    return 0
  fi
}

self_update_nullable_json() {
  if [[ -n "${1:-}" ]]; then app_json_string "$1"; else printf 'null'; fi
}

self_update_version_json() {
  local can_update=false
  self_update_detect_mode
  [[ "$SELF_UPDATE_MODE" == managed_release ]] && can_update=true
  printf '{"schema_version":1,"mode":%s,"version":%s,"previous_version":%s,"channel":%s,"root":%s,"current_path":%s,"previous_path":%s,"can_update":%s}\n' \
    "$(app_json_string "$SELF_UPDATE_MODE")" \
    "$(self_update_nullable_json "$SELF_UPDATE_VERSION")" \
    "$(self_update_nullable_json "$SELF_UPDATE_PREVIOUS_VERSION")" \
    "$(app_json_string "${DEPLOY_SELF_UPDATE_CHANNEL:-stable}")" \
    "$(self_update_nullable_json "$SELF_UPDATE_ROOT")" \
    "$(self_update_nullable_json "$SELF_UPDATE_CURRENT_PATH")" \
    "$(self_update_nullable_json "$SELF_UPDATE_PREVIOUS_PATH")" \
    "$can_update"
}

self_update_print_version() {
  local json="$1"
  if [[ "$json" == 1 ]]; then
    self_update_version_json
    return 0
  fi
  self_update_detect_mode
  printf 'mode: %s\n' "$SELF_UPDATE_MODE"
  printf 'version: %s\n' "${SELF_UPDATE_VERSION:-unknown}"
  printf 'previous_version: %s\n' "${SELF_UPDATE_PREVIOUS_VERSION:-unknown}"
  printf 'channel: %s\n' "${DEPLOY_SELF_UPDATE_CHANNEL:-stable}"
  [[ -n "$SELF_UPDATE_ROOT" ]] && printf 'root: %s\n' "$SELF_UPDATE_ROOT"
}

self_update_manifest_url() {
  local base="${DEPLOY_SELF_UPDATE_URL:-}"
  [[ -n "$base" ]] || return 1
  if [[ "$base" == */manifest.json ]]; then
    printf '%s\n' "$base"
  else
    printf '%s/manifest.json\n' "${base%/}"
  fi
}

self_update_manifest_set_error() {
  [[ -n "${SELF_UPDATE_MANIFEST_ERROR:-}" ]] || SELF_UPDATE_MANIFEST_ERROR="$1"
  SELF_UPDATE_MANIFEST_VALID=0
}

self_update_validate_manifest_file() {
  local manifest_file="$1" object schema project channel version artifact_name artifact_url sha256 size_bytes
  SELF_UPDATE_MANIFEST_ERROR=""
  SELF_UPDATE_MANIFEST_VALID=1
SELF_UPDATE_MANAGER_LOCK_ACQUIRED=0
  [[ -s "$manifest_file" ]] || self_update_manifest_set_error 'manifest is empty'
  object="$(cat "$manifest_file" 2>/dev/null)" || self_update_manifest_set_error 'manifest cannot be read'
  schema="$(state_json_field "$object" schema_version 2>/dev/null || true)"
  project="$(state_json_field "$object" project 2>/dev/null || true)"
  channel="$(state_json_field "$object" channel 2>/dev/null || true)"
  version="$(state_json_field "$object" version 2>/dev/null || true)"
  artifact_name="$(state_json_field "$object" artifacts.source.name 2>/dev/null || true)"
  artifact_url="$(state_json_field "$object" artifacts.source.url 2>/dev/null || true)"
  sha256="$(state_json_field "$object" artifacts.source.sha256 2>/dev/null || true)"
  size_bytes="$(state_json_field "$object" artifacts.source.size_bytes 2>/dev/null || true)"
  [[ "$schema" == 1 ]] || self_update_manifest_set_error 'unsupported manifest schema'
  [[ "$project" == deploy-scripts ]] || self_update_manifest_set_error 'manifest project mismatch'
  [[ "$channel" == "${DEPLOY_SELF_UPDATE_CHANNEL:-stable}" ]] || self_update_manifest_set_error 'manifest channel mismatch'
  [[ "$version" =~ ^v([0]|[1-9][0-9]*)\.([0]|[1-9][0-9]*)\.([0]|[1-9][0-9]*)(-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*)?$ ]] || self_update_manifest_set_error 'manifest version is invalid'
  [[ "$artifact_name" == "deploy-scripts-${version}.tar.gz" ]] || self_update_manifest_set_error 'manifest artifact name is invalid'
  self_update_validate_https_url "$artifact_url" || self_update_manifest_set_error 'manifest artifact URL is not HTTPS'
  [[ "${artifact_url%/}" == */"$artifact_name" ]] || self_update_manifest_set_error 'manifest artifact URL does not match artifact name'
  [[ "$sha256" =~ ^[0-9a-f]{64}$ ]] || self_update_manifest_set_error 'manifest artifact hash is invalid'
  [[ "$size_bytes" =~ ^[1-9][0-9]*$ ]] || self_update_manifest_set_error 'manifest artifact size is invalid'
  (( SELF_UPDATE_MANIFEST_VALID == 1 )) || return 1
  SELF_UPDATE_MANIFEST_VERSION="$version"
  SELF_UPDATE_MANIFEST_NAME="$artifact_name"
  SELF_UPDATE_MANIFEST_URL="$artifact_url"
  SELF_UPDATE_MANIFEST_SHA256="$sha256"
  SELF_UPDATE_MANIFEST_SIZE_BYTES="$size_bytes"
  return 0
}

self_update_check_json() {
  local state="$1" error_message="${2:-}" current_version="${SELF_UPDATE_VERSION:-}"
  printf '{"schema_version":1,"mode":%s,"channel":%s,"state":%s,"current_version":%s,"latest_version":%s,"manifest_url":%s,"artifact":{"name":%s,"url":%s,"sha256":%s,"size_bytes":%s},"error":%s}\n' \
    "$(app_json_string "${SELF_UPDATE_MODE:-unknown}")" \
    "$(app_json_string "${DEPLOY_SELF_UPDATE_CHANNEL:-stable}")" \
    "$(app_json_string "$state")" \
    "$(self_update_nullable_json "$current_version")" \
    "$(self_update_nullable_json "${SELF_UPDATE_MANIFEST_VERSION:-}")" \
    "$(self_update_nullable_json "${SELF_UPDATE_CHECK_MANIFEST_URL:-}")" \
    "$(self_update_nullable_json "${SELF_UPDATE_MANIFEST_NAME:-}")" \
    "$(self_update_nullable_json "${SELF_UPDATE_MANIFEST_URL:-}")" \
    "$(self_update_nullable_json "${SELF_UPDATE_MANIFEST_SHA256:-}")" \
    "${SELF_UPDATE_MANIFEST_SIZE_BYTES:-null}" \
    "$(self_update_nullable_json "$error_message")"
}

self_update_fetch_file() {
  local url="$1" output="$2" max_bytes="$3"
  self_update_validate_https_url "$url" || return 1
  curl -fsSL --proto '=https' --proto-redir '=https' \
    --max-time "$DEPLOY_SELF_UPDATE_TIMEOUT_SECONDS" \
    --max-filesize "$max_bytes" -o "$output" "$url" 2>/dev/null
  [[ -s "$output" ]] || return 1
}

self_update_validate_archive_layout() {
  local archive_path="$1" extraction_root="$2" expected_version="$3"
  local member member_type top_prefix
  top_prefix="deploy-scripts-${expected_version}/"
  while IFS= read -r member; do
    [[ -n "$member" ]] || continue
    case "$member" in
      /*|../*|*/../*|*/..|*/./*|./*) return 1 ;;
    esac
    [[ "$member" == "$top_prefix"* ]] || return 1
  done < <(tar -tzf "$archive_path")
  while IFS= read -r member_type; do
    case "${member_type:0:1}" in
      -|d) ;;
      *) return 1 ;;
    esac
  done < <(tar -tvzf "$archive_path" | awk '{ print $1 }')
  mkdir -p "$extraction_root" || return 1
  tar --extract --gzip --file "$archive_path" --directory "$extraction_root" \
    --no-same-owner --no-same-permissions || return 1
  find "$extraction_root" -type l -o -type b -o -type c -o -type p | grep -q . && return 1 || true
  [[ -f "${extraction_root}/${top_prefix}deploy.sh" ]] || return 1
  [[ -f "${extraction_root}/${top_prefix}lib/core.sh" ]] || return 1
  [[ -f "${extraction_root}/${top_prefix}RELEASE.json" ]] || return 1
  local metadata project version schema
  metadata="$(cat "${extraction_root}/${top_prefix}RELEASE.json")" || return 1
  schema="$(state_json_field "$metadata" schema_version 2>/dev/null || true)"
  project="$(state_json_field "$metadata" project 2>/dev/null || true)"
  version="$(state_json_field "$metadata" version 2>/dev/null || true)"
  [[ "$schema" == 1 && "$project" == deploy-scripts && "$version" == "$expected_version" ]] || return 1
  while IFS= read -r -d '' member; do
    bash -n "$member" || return 1
  done < <(find "$extraction_root/${top_prefix%/}" -type f -name '*.sh' -print0)
}

self_update_prepare_candidate() {
  local temp_dir="$1" manifest_file archive_file extraction_root actual_size actual_sha
  manifest_file="${temp_dir}/manifest.json"
  extraction_root="${temp_dir}/extracted"
  self_update_fetch_file "$SELF_UPDATE_CHECK_MANIFEST_URL" "$manifest_file" "$DEPLOY_SELF_UPDATE_MAX_MANIFEST_BYTES" || {
    SELF_UPDATE_MANIFEST_ERROR='manifest download failed'
    return 1
  }
  self_update_validate_manifest_file "$manifest_file" || return 1
  if [[ -n "${SELF_UPDATE_VERSION:-}" ]]; then
    local comparison
    comparison="$(deploy_version_compare "$SELF_UPDATE_MANIFEST_VERSION" "$SELF_UPDATE_VERSION" 2>/dev/null || printf invalid)"
    case "$comparison" in
      1) ;;
      0) SELF_UPDATE_MANIFEST_ERROR='release is already current'; return 1 ;;
      -1) SELF_UPDATE_MANIFEST_ERROR='downgrade is not allowed'; return 1 ;;
      *) SELF_UPDATE_MANIFEST_ERROR='release version comparison failed'; return 1 ;;
    esac
  fi
  archive_file="${temp_dir}/${SELF_UPDATE_MANIFEST_NAME}"
  self_update_fetch_file "$SELF_UPDATE_MANIFEST_URL" "$archive_file" "$DEPLOY_SELF_UPDATE_MAX_ARTIFACT_BYTES" || {
    SELF_UPDATE_MANIFEST_ERROR='artifact download failed'
    return 1
  }
  actual_size="$(wc -c < "$archive_file" | tr -d '[:space:]')"
  [[ "$actual_size" == "$SELF_UPDATE_MANIFEST_SIZE_BYTES" ]] || {
    SELF_UPDATE_MANIFEST_ERROR='artifact size does not match manifest'
    return 1
  }
  actual_sha="$(sha256sum "$archive_file" | awk '{print $1}')"
  [[ "$actual_sha" == "$SELF_UPDATE_MANIFEST_SHA256" ]] || {
    SELF_UPDATE_MANIFEST_ERROR='artifact SHA-256 does not match manifest'
    return 1
  }
  self_update_validate_archive_layout "$archive_file" "$extraction_root" "$SELF_UPDATE_MANIFEST_VERSION" || {
    SELF_UPDATE_MANIFEST_ERROR='artifact failed archive or release validation'
    return 1
  }
  SELF_UPDATE_CANDIDATE_ROOT="${extraction_root}/deploy-scripts-${SELF_UPDATE_MANIFEST_VERSION}"
  SELF_UPDATE_CANDIDATE_ARCHIVE="$archive_file"
  return 0
}

self_update_dry_run_json() {
  local state="$1" error_message="${2:-}"
  printf '{"schema_version":1,"mode":%s,"channel":%s,"state":%s,"current_version":%s,"latest_version":%s,"artifact_name":%s,"artifact_sha256":%s,"artifact_size_bytes":%s,"error":%s}\n' \
    "$(app_json_string "${SELF_UPDATE_MODE:-unknown}")" \
    "$(app_json_string "${DEPLOY_SELF_UPDATE_CHANNEL:-stable}")" \
    "$(app_json_string "$state")" \
    "$(self_update_nullable_json "${SELF_UPDATE_VERSION:-}")" \
    "$(self_update_nullable_json "${SELF_UPDATE_MANIFEST_VERSION:-}")" \
    "$(self_update_nullable_json "${SELF_UPDATE_MANIFEST_NAME:-}")" \
    "$(self_update_nullable_json "${SELF_UPDATE_MANIFEST_SHA256:-}")" \
    "${SELF_UPDATE_MANIFEST_SIZE_BYTES:-null}" \
    "$(self_update_nullable_json "$error_message")"
}

self_update_dry_run_main() {
  local json="$1" temp_dir candidate_error
  self_update_detect_mode
  if [[ "$SELF_UPDATE_MODE" != managed_release ]]; then
    if [[ "$json" == 1 ]]; then self_update_dry_run_json blocked_mode 'dry-run requires managed_release mode'; else printf '%s\n' 'self-update dry-run requires managed_release mode' >&2; fi
    return 2
  fi
  if ! self_update_load_config; then
    if [[ "$json" == 1 ]]; then self_update_dry_run_json check_failed 'self-update configuration is invalid'; else printf '%s\n' 'self-update configuration is invalid' >&2; fi
    return 1
  fi
  SELF_UPDATE_CHECK_MANIFEST_URL="$(self_update_manifest_url 2>/dev/null || true)"
  if ! self_update_validate_https_url "$SELF_UPDATE_CHECK_MANIFEST_URL"; then
    if [[ "$json" == 1 ]]; then self_update_dry_run_json check_failed 'self-update URL must be HTTPS without credentials, queries, or fragments'; else printf '%s\n' 'self-update URL must be HTTPS without credentials, queries, or fragments' >&2; fi
    return 1
  fi
  temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/deploy-scripts-self-dry-run.XXXXXX")" || return 1
  chmod 700 "$temp_dir" || { rm -rf "$temp_dir"; return 1; }
  if ! self_update_prepare_candidate "$temp_dir"; then
    candidate_error="$SELF_UPDATE_MANIFEST_ERROR"
    rm -rf "$temp_dir"
    if [[ "$json" == 1 ]]; then self_update_dry_run_json check_failed "$candidate_error"; else printf 'self-update dry-run failed: %s\n' "$candidate_error" >&2; fi
    return 1
  fi
  rm -rf "$temp_dir"
  if [[ "$json" == 1 ]]; then self_update_dry_run_json validated; else printf 'validated release %s (no files changed)\n' "$SELF_UPDATE_MANIFEST_VERSION"; fi
  return 0
}

self_update_check_main() {
  local json="$1" manifest_url temp_dir manifest_file comparison
  SELF_UPDATE_CHECK_MANIFEST_URL=""
  SELF_UPDATE_CANDIDATE_ROOT=""
  SELF_UPDATE_CANDIDATE_ARCHIVE=""
  SELF_UPDATE_MANIFEST_VERSION=""
  SELF_UPDATE_MANIFEST_URL=""
  SELF_UPDATE_MANIFEST_SHA256=""
  SELF_UPDATE_MANIFEST_SIZE_BYTES=""
  SELF_UPDATE_MANIFEST_NAME=""
  SELF_UPDATE_MANIFEST_ERROR=""
  self_update_detect_mode
  if ! self_update_load_config; then
    if [[ "$json" == 1 ]]; then self_update_check_json check_failed 'self-update configuration is invalid'; else printf '%s\n' 'self-update configuration is invalid' >&2; fi
    return 1
  fi
  if [[ -z "${DEPLOY_SELF_UPDATE_URL:-}" ]]; then
    if [[ "$json" == 1 ]]; then self_update_check_json not_configured; else printf 'self-update URL is not configured\n' >&2; fi
    return 2
  fi
  manifest_url="$(self_update_manifest_url)" || return 1
  self_update_validate_https_url "$manifest_url" || {
    if [[ "$json" == 1 ]]; then self_update_check_json check_failed 'self-update URL must be HTTPS without credentials, queries, or fragments'; else printf '%s\n' 'self-update URL must be HTTPS without credentials, queries, or fragments' >&2; fi
    return 1
  }
  SELF_UPDATE_CHECK_MANIFEST_URL="$manifest_url"
  temp_dir="$(mktemp -d "${TMPDIR:-/tmp}/deploy-scripts-self-check.XXXXXX")" || return 1
  chmod 700 "$temp_dir" || { rm -rf "$temp_dir"; return 1; }
  manifest_file="${temp_dir}/manifest.json"
  if ! curl -fsSL --proto '=https' --proto-redir '=https' --max-time "$DEPLOY_SELF_UPDATE_TIMEOUT_SECONDS" --max-filesize "$DEPLOY_SELF_UPDATE_MAX_MANIFEST_BYTES" -o "$manifest_file" "$manifest_url" 2>/dev/null; then
    rm -rf "$temp_dir"
    if [[ "$json" == 1 ]]; then self_update_check_json check_failed 'manifest download failed'; else printf 'manifest download failed\n' >&2; fi
    return 1
  fi
  if ! self_update_validate_manifest_file "$manifest_file"; then
    local manifest_error="$SELF_UPDATE_MANIFEST_ERROR"
    rm -rf "$temp_dir"
    if [[ "$json" == 1 ]]; then self_update_check_json check_failed "$manifest_error"; else printf 'manifest validation failed: %s\n' "$manifest_error" >&2; fi
    return 1
  fi
  rm -rf "$temp_dir"
  if [[ -n "$SELF_UPDATE_VERSION" ]]; then
    comparison="$(deploy_version_compare "$SELF_UPDATE_MANIFEST_VERSION" "$SELF_UPDATE_VERSION" 2>/dev/null || printf invalid)"
    case "$comparison" in
      -1|0) self_update_check_json up_to_date; return 0 ;;
      1) self_update_check_json update_available; return 0 ;;
    esac
  fi
  self_update_check_json unknown_current; return 0
}


self_update_acquire_lock() {
  local lock_file="${DEPLOY_SELF_UPDATE_LOCK_FILE:-${DEPLOY_OPERATION_ROOT}/locks/self-update.lock}" lock_dir
  lock_dir="$(dirname -- "$lock_file")"
  [[ ! -L "$lock_dir" ]] || return 1
  mkdir -p "$lock_dir" || return 1
  operation_set_owner_and_mode "$lock_dir" 750 || return 1
  command -v flock >/dev/null 2>&1 || return 1
  exec 7>"$lock_file" || return 1
  operation_set_owner_and_mode "$lock_file" 600 || { exec 7>&-; return 1; }
  flock -n 7 || { exec 7>&-; return 9; }
}

self_update_release_lock() {
  flock -u 7 2>/dev/null || true
  exec 7>&- 2>/dev/null || true
}

self_update_acquire_coordination_locks() {
  local status
  SELF_UPDATE_MANAGER_LOCK_ACQUIRED=0
  self_update_acquire_lock
  status=$?
  (( status == 0 )) || return "$status"
  if declare -F manager_update_acquire_lock >/dev/null 2>&1; then
    manager_update_acquire_lock
    status=$?
    if (( status != 0 )); then
      self_update_release_lock
      return "$status"
    fi
    SELF_UPDATE_MANAGER_LOCK_ACQUIRED=1
  fi
}

self_update_release_coordination_locks() {
  if (( SELF_UPDATE_MANAGER_LOCK_ACQUIRED == 1 )); then
    manager_update_release_lock
    SELF_UPDATE_MANAGER_LOCK_ACQUIRED=0
  fi
  self_update_release_lock
}

self_update_current_target_for() {
  local managed_root="$1" current_path resolved release_root
  current_path="${managed_root}/current"
  [[ -L "$current_path" ]] || return 1
  resolved="$(self_update_realpath "$current_path")" || return 1
  release_root="$(self_update_realpath "${managed_root}/releases")" || return 1
  [[ "$resolved" == "$release_root/"* ]] || return 1
  [[ -d "$resolved" ]] || return 1
  self_update_release_version_from_root "$resolved" >/dev/null || return 1
  printf '%s\n' "$resolved"
}

self_update_release_path_is_safe() {
  local managed_root="$1" release_path="$2" releases_root resolved
  releases_root="$(self_update_realpath "${managed_root}/releases")" || return 1
  resolved="$(self_update_realpath "$release_path")" || true
  [[ "$release_path" == "$managed_root/releases/"* ]] || return 1
  [[ ! -L "$release_path" ]] || return 1
  [[ ! -e "$release_path" ]] || return 1
  [[ "$release_path" != "$managed_root/releases" ]] || return 1
  [[ "$release_path" == "$releases_root/"* ]] || return 1
}

self_update_prepare_activation_root() {
  local managed_root="$1" releases_root temp_dir
  [[ -d "$managed_root" && ! -L "$managed_root" ]] || return 1
  releases_root="${managed_root}/releases"
  [[ ! -L "$releases_root" ]] || return 1
  mkdir -p "$releases_root" || return 1
  temp_dir="$(mktemp -d "${managed_root}/.self-update.XXXXXX")" || return 1
  chmod 700 "$temp_dir" || { rm -rf "$temp_dir"; return 1; }
  printf '%s\n' "$temp_dir"
}

self_update_atomic_restore_current() {
  local managed_root="$1" old_target="$2"
  [[ -n "$old_target" ]] || return 1
  atomic_symlink "$old_target" "${managed_root}/current"
}

self_update_restore_previous_target() {
  local managed_root="$1" old_target="${2:-}" previous_path="${managed_root}/previous"
  if [[ -n "$old_target" ]]; then
    atomic_symlink "$old_target" "$previous_path"
    return $?
  fi
  [[ ! -e "$previous_path" && ! -L "$previous_path" ]] && return 0
  [[ ! -d "$previous_path" ]] || return 1
  rm -f -- "$previous_path"
}

self_update_discard_failed_release() {
  local managed_root="$1" release_path="${2:-}" releases_root resolved
  [[ -n "$release_path" && -e "$release_path" ]] || return 0
  releases_root="$(self_update_realpath "${managed_root}/releases")" || return 1
  resolved="$(self_update_realpath "$release_path")" || return 1
  [[ "$release_path" == "$managed_root/releases/"* ]] || return 1
  [[ "$resolved" == "$releases_root/"* ]] || return 1
  [[ -d "$release_path" && ! -L "$release_path" ]] || return 1
  rm -rf -- "$release_path"
}

self_update_activate_candidate() {
  local managed_root="$1" candidate_root="$2" version="$3"
  local releases_root release_path old_target old_previous_target=""
  releases_root="${managed_root}/releases"
  [[ -d "$releases_root" && ! -L "$releases_root" ]] || return 1
  release_path="${releases_root}/${version}"
  self_update_release_path_is_safe "$managed_root" "$release_path" || return 1
  old_target="$(self_update_current_target_for "$managed_root")" || return 1
  if [[ -e "${managed_root}/previous" || -L "${managed_root}/previous" ]]; then
    old_previous_target="$(self_update_previous_target_for "$managed_root")" || return 1
  fi
  [[ -d "$candidate_root" && ! -L "$candidate_root" ]] || return 1
  mv -- "$candidate_root" "$release_path" || return 1
  if ! atomic_symlink "$old_target" "${managed_root}/previous"; then
    rm -rf -- "$release_path"
    return 1
  fi
  if ! atomic_symlink "$release_path" "${managed_root}/current"; then
    self_update_atomic_restore_current "$managed_root" "$old_target" || true
    self_update_restore_previous_target "$managed_root" "$old_previous_target" || true
    rm -rf -- "$release_path"
    return 1
  fi
  SELF_UPDATE_OLD_TARGET="$old_target"
  SELF_UPDATE_OLD_PREVIOUS_TARGET="$old_previous_target"
  SELF_UPDATE_RELEASE_PATH="$release_path"
  SELF_UPDATE_CURRENT_CHANGED=1
  printf '%s\n' "$release_path"
}

self_update_smoke_check() {
  local release_root="$1" output_dir status command_output
  output_dir="$(mktemp -d "${TMPDIR:-/tmp}/deploy-scripts-smoke.XXXXXX")" || return 1
  chmod 700 "$output_dir" || { rm -rf "$output_dir"; return 1; }
  command_output="${output_dir}/list.out"
  if ! DEPLOY_SELF_UPDATE_ROOT="$SELF_UPDATE_MANAGED_ROOT" bash "${release_root}/deploy.sh" list >"$command_output" 2>"${output_dir}/list.err"; then
    rm -rf "$output_dir"
    return 1
  fi
  if ! DEPLOY_SELF_UPDATE_ROOT="$SELF_UPDATE_MANAGED_ROOT" bash "${release_root}/deploy.sh" self-version --json >"${output_dir}/version.out" 2>"${output_dir}/version.err"; then
    rm -rf "$output_dir"
    return 1
  fi
  if ! python - "${output_dir}/version.out" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)
assert payload.get("schema_version") == 1
assert payload.get("mode") == "managed_release"
PY
  then
    rm -rf "$output_dir"
    return 1
  fi
  if ! DEPLOY_SELF_UPDATE_ROOT="$SELF_UPDATE_MANAGED_ROOT" bash "${release_root}/deploy.sh" status-all --json --no-network >"${output_dir}/status.out" 2>"${output_dir}/status.err"; then
    rm -rf "$output_dir"
    return 1
  fi
  python - "${output_dir}/status.out" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)
assert payload.get("schema_version") == 1
PY
  status=$?
  rm -rf "$output_dir"
  return "$status"
}

self_update_operation_begin() {
  operation_start self_update "" self-update || return 1
  operation_step_start prepare || { operation_reset; return 1; }
}

self_update_operation_finish() {
  local exit_code="$1" state="$2" summary="${3:-}"
  operation_finish "$exit_code" "$state" "$summary" || true
}

self_update_confirm() {
  local yes="$1" version="$2" answer
  [[ "$yes" == 1 || "${DEPLOY_ASSUME_YES:-0}" == 1 ]] && return 0
  if [[ ! -t 0 ]]; then
    printf 'self-update requires --yes or DEPLOY_ASSUME_YES=1 when standard input is not interactive.\n' >&2
    return 2
  fi
  printf 'Activate framework %s? [y/N] ' "$version" >&2
  read -r answer
  [[ "${answer,,}" == y || "${answer,,}" == yes ]]
}

self_update_apply_json() {
  local state="$1" error_message="${2:-}"
  printf '{"schema_version":1,"mode":%s,"state":%s,"current_version":%s,"latest_version":%s,"release_path":%s,"error":%s}\n' \
    "$(app_json_string "${SELF_UPDATE_MODE:-unknown}")" \
    "$(app_json_string "$state")" \
    "$(self_update_nullable_json "${SELF_UPDATE_VERSION:-}")" \
    "$(self_update_nullable_json "${SELF_UPDATE_MANIFEST_VERSION:-}")" \
    "$(self_update_nullable_json "${SELF_UPDATE_RELEASE_PATH:-}")" \
    "$(self_update_nullable_json "$error_message")"
}

self_update_apply_main() {
  local json="$1" yes="$2" temp_dir candidate_error candidate_root
  local current_step="prepare" smoke_status lock_status had_errexit=0
  SELF_UPDATE_MANIFEST_VERSION=""
  SELF_UPDATE_MANIFEST_URL=""
  SELF_UPDATE_MANIFEST_SHA256=""
  SELF_UPDATE_MANIFEST_SIZE_BYTES=""
  SELF_UPDATE_MANIFEST_NAME=""
  SELF_UPDATE_MANIFEST_ERROR=""
  SELF_UPDATE_RELEASE_PATH=""
  SELF_UPDATE_OLD_TARGET=""
  SELF_UPDATE_OLD_PREVIOUS_TARGET=""
  self_update_detect_mode
  if [[ "$SELF_UPDATE_MODE" != managed_release ]]; then
    if (( json )); then self_update_apply_json blocked_mode 'self-update requires managed_release mode'; else printf '%s\n' 'self-update requires managed_release mode; use --check in checkout or standalone mode' >&2; fi
    return 2
  fi
  if [[ "${EUID:-$(id -u)}" -ne 0 && "${DEPLOY_SELF_UPDATE_ALLOW_NONROOT_TEST:-0}" != 1 ]]; then
    if (( json )); then self_update_apply_json permission_denied 'self-update requires root'; else printf '%s\n' 'self-update requires root' >&2; fi
    return 1
  fi
  self_update_load_config || {
    if (( json )); then self_update_apply_json check_failed 'self-update configuration is invalid'; else printf '%s\n' 'self-update configuration is invalid' >&2; fi
    return 1
  }
  if self_update_acquire_coordination_locks; then
    :
  else
    lock_status=$?
    if (( lock_status == 9 )); then
      if (( json )); then self_update_apply_json locked 'another managed write is running'; else printf '%s\n' 'another managed write is running' >&2; fi
      return 9
    fi
    if (( json )); then self_update_apply_json failed 'unable to acquire self-update coordination locks'; else printf '%s\n' 'unable to acquire self-update coordination locks' >&2; fi
    return 1
  fi
  if ! self_update_operation_begin; then
    self_update_release_coordination_locks
    if (( json )); then self_update_apply_json failed 'unable to create self-update operation record'; else printf '%s\n' 'unable to create self-update operation record' >&2; fi
    return 1
  fi
  operation_started=1
  temp_dir="$(self_update_prepare_activation_root "$SELF_UPDATE_MANAGED_ROOT")" || {
    self_update_operation_finish 1 failed 'unable to create private activation staging directory'
    self_update_release_coordination_locks
    if (( json )); then self_update_apply_json failed 'unable to create private activation staging directory'; else printf '%s\n' 'unable to create private activation staging directory' >&2; fi
    return 1
  }
  if ! self_update_load_config || ! self_update_manifest_url >/dev/null; then
    candidate_error='self-update configuration is invalid'
    rm -rf "$temp_dir"
    operation_step_finish "$current_step" failed || true
    self_update_operation_finish 1 failed "$candidate_error"
    self_update_release_coordination_locks
    if (( json )); then self_update_apply_json check_failed "$candidate_error"; else printf '%s\n' "$candidate_error" >&2; fi
    return 1
  fi
  SELF_UPDATE_CHECK_MANIFEST_URL="$(self_update_manifest_url)"
  if ! self_update_validate_https_url "$SELF_UPDATE_CHECK_MANIFEST_URL"; then
    candidate_error='self-update URL must be HTTPS without credentials, queries, or fragments'
    rm -rf "$temp_dir"
    operation_step_finish "$current_step" failed || true
    self_update_operation_finish 1 failed "$candidate_error"
    self_update_release_coordination_locks
    if (( json )); then self_update_apply_json check_failed "$candidate_error"; else printf '%s\n' "$candidate_error" >&2; fi
    return 1
  fi
  if ! self_update_prepare_candidate "$temp_dir"; then
    candidate_error="${SELF_UPDATE_MANIFEST_ERROR:-release validation failed}"
    rm -rf "$temp_dir"
    operation_step_finish "$current_step" failed || true
    self_update_operation_finish 1 failed "$candidate_error"
    self_update_release_coordination_locks
    if (( json )); then self_update_apply_json check_failed "$candidate_error"; else printf 'self-update failed: %s\n' "$candidate_error" >&2; fi
    return 1
  fi
  candidate_root="$SELF_UPDATE_CANDIDATE_ROOT"
  operation_step_finish prepare succeeded || true
  current_step=activate
  operation_step_start activate || true
  self_update_confirm "$yes" "$SELF_UPDATE_MANIFEST_VERSION" || {
    candidate_error='self-update was not confirmed'
    rm -rf "$temp_dir"
    operation_step_finish activate skipped || true
    self_update_operation_finish 2 cancelled "$candidate_error"
    self_update_release_coordination_locks
    if (( json )); then self_update_apply_json cancelled "$candidate_error"; else printf '%s\n' "$candidate_error" >&2; fi
    return 2
  }
  if ! self_update_activate_candidate "$SELF_UPDATE_MANAGED_ROOT" "$candidate_root" "$SELF_UPDATE_MANIFEST_VERSION" >/dev/null; then
    candidate_error='atomic release activation failed'
    rm -rf "$temp_dir"
    operation_step_finish activate failed || true
    self_update_operation_finish 1 failed "$candidate_error"
    self_update_release_coordination_locks
    if (( json )); then self_update_apply_json failed "$candidate_error"; else printf '%s\n' "$candidate_error" >&2; fi
    return 1
  fi
  rm -rf "$temp_dir"
  operation_step_finish activate succeeded || true
  current_step=smoke_check
  operation_step_start smoke_check || true
  case "$-" in *e*) had_errexit=1;; esac
  set +e
  self_update_smoke_check "$SELF_UPDATE_RELEASE_PATH"
  smoke_status=$?
  (( had_errexit == 1 )) && set -e || set +e
  if [[ "$smoke_status" -eq 0 ]]; then
    SELF_UPDATE_VERSION="$SELF_UPDATE_MANIFEST_VERSION"
    operation_step_finish smoke_check succeeded || true
    self_update_cleanup_releases "$SELF_UPDATE_MANAGED_ROOT" || printf '%s\n' 'self-update: warning: release retention cleanup failed' >&2
    self_update_operation_finish 0 succeeded
    self_update_release_coordination_locks
    if (( json )); then self_update_apply_json succeeded; else printf 'self-update activated %s\n' "$SELF_UPDATE_MANIFEST_VERSION"; fi
    return 0
  fi
  operation_step_finish smoke_check failed || true
  operation_step_start rollback || true
  if self_update_atomic_restore_current "$SELF_UPDATE_MANAGED_ROOT" "$SELF_UPDATE_OLD_TARGET" \
      && self_update_restore_previous_target "$SELF_UPDATE_MANAGED_ROOT" "${SELF_UPDATE_OLD_PREVIOUS_TARGET:-}"; then
    self_update_discard_failed_release "$SELF_UPDATE_MANAGED_ROOT" "$SELF_UPDATE_RELEASE_PATH" \
      || printf '%s\n' 'self-update: warning: could not remove failed release candidate' >&2
    operation_step_finish rollback succeeded || true
    self_update_operation_finish 1 rolled_back 'new release smoke check failed; current was restored'
    self_update_release_coordination_locks
    if (( json )); then self_update_apply_json rolled_back 'new release smoke check failed; current was restored'; else printf '%s\n' 'new release smoke check failed; current was restored' >&2; fi
    return 1
  fi
  operation_step_finish rollback failed || true
  self_update_operation_finish 1 rollback_failed 'new release smoke check failed and current could not be restored'
  self_update_release_coordination_locks
  if (( json )); then self_update_apply_json rollback_failed 'new release smoke check failed and current could not be restored'; else printf '%s\n' 'new release smoke check failed and current could not be restored' >&2; fi
  return 1
}


self_update_previous_target_for() {
  local managed_root="$1" previous_path resolved release_root
  previous_path="${managed_root}/previous"
  [[ -L "$previous_path" ]] || return 1
  resolved="$(self_update_realpath "$previous_path")" || return 1
  release_root="$(self_update_realpath "${managed_root}/releases")" || return 1
  [[ "$resolved" == "$release_root/"* && -d "$resolved" ]] || return 1
  self_update_release_version_from_root "$resolved" >/dev/null || return 1
  printf '%s\n' "$resolved"
}

self_update_sorted_release_paths() {
  local managed_root="$1" release_root path version
  release_root="${managed_root}/releases"
  [[ -d "$release_root" && ! -L "$release_root" ]] || return 1
  while IFS= read -r -d '' path; do
    [[ -d "$path" && ! -L "$path" ]] || continue
    version="$(self_update_release_version_from_root "$path" 2>/dev/null || true)"
    [[ -n "$version" ]] || continue
    printf '%s\t%s\n' "$version" "$path"
  done < <(find "$release_root" -mindepth 1 -maxdepth 1 -type d -print0)
}

self_update_release_is_protected() {
  local path="$1" current_target="${SELF_UPDATE_CURRENT_TARGET:-}" previous_target="${SELF_UPDATE_PREVIOUS_TARGET:-}"
  [[ -n "$current_target" && "$path" == "$current_target" ]] && return 0
  [[ -n "$previous_target" && "$path" == "$previous_target" ]] && return 0
  return 1
}

self_update_cleanup_releases() {
  local managed_root="$1" keep_count="${DEPLOY_SELF_UPDATE_KEEP_RELEASES:-3}" current_target previous_target
  local line version path count=0
  local -a entries=()
  [[ "$keep_count" =~ ^[3-9][0-9]*$ ]] || keep_count=3
  current_target="$(self_update_current_target_for "$managed_root" 2>/dev/null || true)"
  previous_target="$(self_update_previous_target_for "$managed_root" 2>/dev/null || true)"
  SELF_UPDATE_CURRENT_TARGET="$current_target"
  SELF_UPDATE_PREVIOUS_TARGET="$previous_target"
  while IFS= read -r line; do [[ -n "$line" ]] && entries+=("$line"); done < <(self_update_sorted_release_paths "$managed_root" | sort -t $'\t' -k1,1Vr)
  for line in "${entries[@]}"; do
    version="${line%%$'\t'*}"
    path="${line#*$'\t'}"
    if self_update_release_is_protected "$path"; then
      continue
    fi
    if (( count < keep_count )); then
      count=$((count + 1))
      continue
    fi
    [[ "$path" == "$managed_root/releases/"* && ! -L "$path" ]] || continue
    rm -rf -- "$path" || printf 'self-update: warning: could not remove old release %s\n' "$version" >&2
  done
  return 0
}

self_update_list_json() {
  local managed_root="$1" first=1 line version path
  printf '{"schema_version":1,"mode":%s,"releases":[' "$(app_json_string "$SELF_UPDATE_MODE")"
  while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    version="${line%%$'\t'*}"
    path="${line#*$'\t'}"
    (( first )) || printf ','
    first=0
    printf '{"version":%s,"path":%s,"current":%s,"previous":%s}' \
      "$(app_json_string "$version")" "$(app_json_string "$path")" \
      "$(app_json_bool "$(self_update_release_is_protected "$path" && [[ "$path" == "${SELF_UPDATE_CURRENT_TARGET:-}" ]] && printf true || printf false)")" \
      "$(app_json_bool "$(self_update_release_is_protected "$path" && [[ "$path" == "${SELF_UPDATE_PREVIOUS_TARGET:-}" ]] && printf true || printf false)")"
  done < <(self_update_sorted_release_paths "$managed_root" | sort -t $'\t' -k1,1Vr)
  printf ']}\n'
}

self_update_list_main() {
  local json="$1"
  self_update_detect_mode
  if [[ "$SELF_UPDATE_MODE" != managed_release ]]; then
    if (( json )); then printf '{"schema_version":1,"mode":%s,"releases":[],"error":"managed release mode required"}\n' "$(app_json_string "$SELF_UPDATE_MODE")"; else printf '%s\n' 'self-update --list requires managed_release mode' >&2; fi
    return 2
  fi
  self_update_current_target_for "$SELF_UPDATE_MANAGED_ROOT" >/dev/null || true
  SELF_UPDATE_CURRENT_TARGET="$(self_update_current_target_for "$SELF_UPDATE_MANAGED_ROOT" 2>/dev/null || true)"
  SELF_UPDATE_PREVIOUS_TARGET="$(self_update_previous_target_for "$SELF_UPDATE_MANAGED_ROOT" 2>/dev/null || true)"
  if (( json )); then
    self_update_list_json "$SELF_UPDATE_MANAGED_ROOT"
  else
    self_update_sorted_release_paths "$SELF_UPDATE_MANAGED_ROOT" | sort -t $'\t' -k1,1Vr | awk -F '\t' '{ print $1 "\t" $2 }'
  fi
}

self_update_rollback_json() {
  local state="$1" error_message="${2:-}"
  printf '{"schema_version":1,"mode":%s,"state":%s,"current_version":%s,"target_version":%s,"error":%s}\n' \
    "$(app_json_string "${SELF_UPDATE_MODE:-unknown}")" \
    "$(app_json_string "$state")" \
    "$(self_update_nullable_json "${SELF_UPDATE_VERSION:-}")" \
    "$(self_update_nullable_json "${SELF_UPDATE_ROLLBACK_TARGET_VERSION:-}")" \
    "$(self_update_nullable_json "$error_message")"
}

self_update_rollback_main() {
  local json="$1" yes="$2" old_target previous_target old_version target_version
  local lock_status candidate_error smoke_status had_errexit=0
  self_update_detect_mode
  if [[ "$SELF_UPDATE_MODE" != managed_release ]]; then
    if (( json )); then self_update_rollback_json blocked_mode 'rollback requires managed_release mode'; else printf '%s\n' 'self-update rollback requires managed_release mode' >&2; fi
    return 2
  fi
  if [[ "${EUID:-$(id -u)}" -ne 0 && "${DEPLOY_SELF_UPDATE_ALLOW_NONROOT_TEST:-0}" != 1 ]]; then
    if (( json )); then self_update_rollback_json permission_denied 'rollback requires root'; else printf '%s\n' 'self-update rollback requires root' >&2; fi
    return 1
  fi
  self_update_load_config || {
    if (( json )); then self_update_rollback_json failed 'self-update configuration is invalid'; else printf '%s\n' 'self-update configuration is invalid' >&2; fi
    return 1
  }
  if self_update_acquire_coordination_locks; then
    :
  else
    lock_status=$?
    if (( lock_status == 9 )); then
      if (( json )); then self_update_rollback_json locked 'another managed write is running'; else printf '%s\n' 'another managed write is running' >&2; fi
      return 9
    fi
    if (( json )); then self_update_rollback_json failed 'unable to acquire self-update coordination locks'; else printf '%s\n' 'unable to acquire self-update coordination locks' >&2; fi
    return 1
  fi
  if ! self_update_operation_begin; then
    self_update_release_coordination_locks
    if (( json )); then self_update_rollback_json failed 'unable to create self-update operation record'; else printf '%s\n' 'unable to create self-update operation record' >&2; fi
    return 1
  fi
  old_target="$(self_update_current_target_for "$SELF_UPDATE_MANAGED_ROOT" 2>/dev/null || true)"
  previous_target="$(self_update_previous_target_for "$SELF_UPDATE_MANAGED_ROOT" 2>/dev/null || true)"
  old_version="$(self_update_release_version_from_root "$old_target" 2>/dev/null || true)"
  target_version="$(self_update_release_version_from_root "$previous_target" 2>/dev/null || true)"
  SELF_UPDATE_ROLLBACK_TARGET_VERSION="$target_version"
  if [[ -z "$old_target" || -z "$previous_target" || -z "$old_version" || -z "$target_version" || "$old_target" == "$previous_target" ]]; then
    self_update_operation_finish 1 failed 'previous release is missing or invalid'
    self_update_release_coordination_locks
    if (( json )); then self_update_rollback_json failed 'previous release is missing or invalid'; else printf '%s\n' 'previous release is missing or invalid' >&2; fi
    return 1
  fi
  operation_step_finish prepare succeeded || true
  operation_step_start activate || true
  if ! self_update_confirm "$yes" "$target_version"; then
    operation_step_finish activate skipped || true
    self_update_operation_finish 2 cancelled 'rollback was not confirmed'
    self_update_release_coordination_locks
    if (( json )); then self_update_rollback_json cancelled 'rollback was not confirmed'; else printf '%s\n' 'rollback was not confirmed' >&2; fi
    return 2
  fi
  if ! atomic_symlink "$previous_target" "${SELF_UPDATE_MANAGED_ROOT}/current"; then
    operation_step_finish activate failed || true
    self_update_operation_finish 1 failed 'atomic rollback switch failed'
    self_update_release_coordination_locks
    if (( json )); then self_update_rollback_json failed 'atomic rollback switch failed'; else printf '%s\n' 'atomic rollback switch failed' >&2; fi
    return 1
  fi
  if ! atomic_symlink "$old_target" "${SELF_UPDATE_MANAGED_ROOT}/previous"; then
    if self_update_atomic_restore_current "$SELF_UPDATE_MANAGED_ROOT" "$old_target"; then
      operation_step_finish activate failed || true
      self_update_operation_finish 1 failed 'atomic rollback switch failed'
      self_update_release_coordination_locks
      if (( json )); then self_update_rollback_json failed 'atomic rollback switch failed'; else printf '%s\n' 'atomic rollback switch failed' >&2; fi
      return 1
    fi
    operation_step_finish activate failed || true
    self_update_operation_finish 1 rollback_failed 'rollback changed current but could not restore it after the pointer swap failed'
    self_update_release_coordination_locks
    if (( json )); then self_update_rollback_json rollback_failed 'rollback changed current but could not restore it'; else printf '%s\n' 'rollback changed current but could not restore it' >&2; fi
    return 1
  fi
  operation_step_finish activate succeeded || true
  operation_step_start smoke_check || true
  case "$-" in *e*) had_errexit=1;; esac
  set +e
  self_update_smoke_check "$previous_target"
  smoke_status=$?
  (( had_errexit == 1 )) && set -e || set +e
  if [[ "$smoke_status" -eq 0 ]]; then
    SELF_UPDATE_VERSION="$target_version"
    operation_step_finish smoke_check succeeded || true
    self_update_operation_finish 0 succeeded
    self_update_release_coordination_locks
    if (( json )); then self_update_rollback_json succeeded; else printf 'self-update rolled back to %s\n' "$target_version"; fi
    return 0
  fi
  operation_step_finish smoke_check failed || true
  operation_step_start rollback || true
  if self_update_atomic_restore_current "$SELF_UPDATE_MANAGED_ROOT" "$old_target" \
      && atomic_symlink "$previous_target" "${SELF_UPDATE_MANAGED_ROOT}/previous"; then
    SELF_UPDATE_VERSION="$old_version"
    operation_step_finish rollback succeeded || true
    self_update_operation_finish 1 rolled_back 'rollback target smoke check failed; current was restored'
    self_update_release_coordination_locks
    if (( json )); then self_update_rollback_json rolled_back 'rollback target smoke check failed; current was restored'; else printf '%s\n' 'rollback target smoke check failed; current was restored' >&2; fi
    return 1
  fi
  operation_step_finish rollback failed || true
  self_update_operation_finish 1 rollback_failed 'rollback target smoke check failed and current could not be restored'
  self_update_release_coordination_locks
  if (( json )); then self_update_rollback_json rollback_failed 'rollback target smoke check failed and current could not be restored'; else printf '%s\n' 'rollback target smoke check failed and current could not be restored' >&2; fi
  return 1
}

self_update_main() {
  local json=0 check=0 dry_run=0 rollback=0 list=0 yes=0 channel_override="" arg
  while (($#)); do
    arg="$1"
    case "$arg" in
      --json) json=1; shift ;;
      --check) check=1; shift ;;
      --dry-run) dry_run=1; shift ;;
      --rollback) rollback=1; shift ;;
      --list) list=1; shift ;;
      --yes) yes=1; shift ;;
      --channel) (($# >= 2)) || { printf 'self-update: --channel requires a value\n' >&2; return 2; }; channel_override="$2"; shift 2 ;;
      -h|--help) printf '%s\n' 'Usage: deploy.sh self-update [--check|--dry-run|--rollback|--list] [--json] [--yes] [--channel NAME]' >&2; return 0 ;;
      *) printf 'self-update: unknown option: %s\n' "$arg" >&2; return 2 ;;
    esac
  done
  (( check + dry_run + rollback + list <= 1 )) || {
    printf '%s\n' 'self-update: choose only one of --check, --dry-run, --rollback, or --list' >&2
    return 2
  }
  [[ -z "$channel_override" ]] || DEPLOY_SELF_UPDATE_CHANNEL="$channel_override"
  if (( check )); then
    self_update_check_main "$json"
    return $?
  fi
  if (( dry_run )); then
    self_update_dry_run_main "$json"
    return $?
  fi
  if (( rollback )); then
    self_update_rollback_main "$json" "$yes"
    return $?
  fi
  if (( list )); then
    self_update_list_main "$json"
    return $?
  fi
  self_update_apply_main "$json" "$yes"
}
