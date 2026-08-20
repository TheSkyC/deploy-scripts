#!/usr/bin/env bash

# Read-only framework identity and release-manifest checks. Write activation is
# deliberately kept out of this slice so checkout and standalone executions
# cannot mutate themselves accidentally.

DEPLOY_SELF_UPDATE_URL="${DEPLOY_SELF_UPDATE_URL:-}"
DEPLOY_SELF_UPDATE_CHANNEL="${DEPLOY_SELF_UPDATE_CHANNEL:-stable}"
DEPLOY_SELF_UPDATE_CONFIG_FILE="${DEPLOY_SELF_UPDATE_CONFIG_FILE:-/etc/deploy-scripts/self-update.conf}"
DEPLOY_SELF_UPDATE_ROOT="${DEPLOY_SELF_UPDATE_ROOT:-/opt/deploy-scripts}"
DEPLOY_SELF_UPDATE_TIMEOUT_SECONDS="${DEPLOY_SELF_UPDATE_TIMEOUT_SECONDS:-30}"
DEPLOY_SELF_UPDATE_MAX_MANIFEST_BYTES="${DEPLOY_SELF_UPDATE_MAX_MANIFEST_BYTES:-1048576}"
DEPLOY_SELF_UPDATE_MAX_ARTIFACT_BYTES="${DEPLOY_SELF_UPDATE_MAX_ARTIFACT_BYTES:-536870912}"

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
  local config_file="${DEPLOY_SELF_UPDATE_CONFIG_FILE:-/etc/deploy-scripts/self-update.conf}"

  DEPLOY_SELF_UPDATE_URL=""
  DEPLOY_SELF_UPDATE_CHANNEL="stable"
  DEPLOY_SELF_UPDATE_TIMEOUT_SECONDS="30"
  DEPLOY_SELF_UPDATE_MAX_MANIFEST_BYTES="1048576"
  DEPLOY_SELF_UPDATE_MAX_ARTIFACT_BYTES="536870912"
  if [[ -f "$config_file" ]]; then
    load_config_file "$config_file" \
      DEPLOY_SELF_UPDATE_URL DEPLOY_SELF_UPDATE_CHANNEL \
      DEPLOY_SELF_UPDATE_TIMEOUT_SECONDS DEPLOY_SELF_UPDATE_MAX_MANIFEST_BYTES \
      DEPLOY_SELF_UPDATE_MAX_ARTIFACT_BYTES DEPLOY_SELF_UPDATE_REQUIRE_SIGNATURE DEPLOY_SELF_UPDATE_PUBLIC_KEY \
      DEPLOY_SELF_UPDATE_KEEP_RELEASES || return 1
  fi
  [[ -z "$configured_url" ]] || DEPLOY_SELF_UPDATE_URL="$configured_url"
  [[ -z "$configured_channel" ]] || DEPLOY_SELF_UPDATE_CHANNEL="$configured_channel"
  [[ -z "$configured_timeout" ]] || DEPLOY_SELF_UPDATE_TIMEOUT_SECONDS="$configured_timeout"
  [[ -z "$configured_max_manifest" ]] || DEPLOY_SELF_UPDATE_MAX_MANIFEST_BYTES="$configured_max_manifest"
  [[ -z "$configured_max_artifact" ]] || DEPLOY_SELF_UPDATE_MAX_ARTIFACT_BYTES="$configured_max_artifact"
  self_update_validate_channel "$DEPLOY_SELF_UPDATE_CHANNEL" || return 1
  [[ "$DEPLOY_SELF_UPDATE_TIMEOUT_SECONDS" =~ ^[0-9]+$ && "$DEPLOY_SELF_UPDATE_TIMEOUT_SECONDS" -gt 0 ]] || return 1
  [[ "$DEPLOY_SELF_UPDATE_MAX_MANIFEST_BYTES" =~ ^[1-9][0-9]*$ ]] || return 1
  [[ "$DEPLOY_SELF_UPDATE_MAX_ARTIFACT_BYTES" =~ ^[1-9][0-9]*$ ]] || return 1
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

self_update_main() {
  local json=0 check=0 dry_run=0 channel_override="" arg
  while (($#)); do
    arg="$1"
    case "$arg" in
      --json) json=1; shift ;;
      --check) check=1; shift ;;
      --dry-run) dry_run=1; shift ;;
      --channel) (($# >= 2)) || { printf 'self-update: --channel requires a value\n' >&2; return 2; }; channel_override="$2"; shift 2 ;;
      --rollback|--list) printf 'self-update: %s is not implemented yet\n' "$arg" >&2; return 2 ;;
      -h|--help) printf '%s\n' 'Usage: deploy.sh self-update [--check|--dry-run] [--json] [--channel NAME]' >&2; return 0 ;;
      *) printf 'self-update: unknown option: %s\n' "$arg" >&2; return 2 ;;
    esac
  done
  [[ -z "$channel_override" ]] || DEPLOY_SELF_UPDATE_CHANNEL="$channel_override"
  if (( check )); then
    self_update_check_main "$json"
    return $?
  fi
  if (( dry_run )); then
    self_update_dry_run_main "$json"
    return $?
  fi
  printf 'self-update activation is not available in this release; use --check\n' >&2
  return 2
}
