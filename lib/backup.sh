#!/usr/bin/env bash

# Shared backup-integrity primitives: SHA-256 sidecar files, manifest.json
# documents, and a verify action that checks archive integrity.
#
# Layout convention for every backup directory:
#   <backup_dir>/<app>_*.tar.gz          the archive itself
#   <backup_dir>/<archive>.sha256        64-hex digest of the archive bytes
#   <backup_dir>/<archive>.manifest.json manifest describing the backup
# The .tmp staging suffix is excluded from every listing helper so concurrent
# writers never leak into verify results.

# Print the sha256 of a file as 64 lowercase hex characters. Uses sha256sum
# with a shasum fallback; returns nonzero when neither tool can hash the file.
backup_sha256_file() {
  local file="$1" digest=""
  if command -v sha256sum >/dev/null 2>&1; then
    digest="$(sha256sum "$file" 2>/dev/null | awk '{print $1}')"
  elif command -v shasum >/dev/null 2>&1; then
    digest="$(shasum -a 256 "$file" 2>/dev/null | awk '{print $1}')"
  fi
  [[ "${digest:-}" =~ ^[0-9a-f]{64}$ ]] || return 1
  printf '%s\n' "$digest"
}

# Write "<digest>  <name>" (two spaces, basename only) next to the archive and
# return the digest on stdout. Sidecar is written through atomic_write_file
# with mode 600; backups always run as root, so no explicit chown is needed.
backup_write_sha256() {
  local archive="$1"
  local digest name sidecar
  digest="$(backup_sha256_file "$archive")" || return 1
  name="$(basename "$archive")"
  sidecar="${archive}.sha256"
  if ! printf '%s  %s\n' "$digest" "$name" | atomic_write_file "$sidecar" 600; then
    return 1
  fi
  printf '%s\n' "$digest"
}

# Read a sidecar's expected digest, accepting both "digest  name" lines and a
# bare digest. Prints the digest; returns nonzero on malformed content.
backup_read_sha256() {
  local sidecar="$1" line digest
  [[ -f "$sidecar" ]] || return 1
  IFS= read -r line < "$sidecar" || return 1
  digest="${line%%[[:space:]]*}"
  [[ "$digest" =~ ^[0-9a-fA-F]{64}$ ]] || return 1
  printf '%s\n' "$digest"
}

# Write a single-line manifest.json for an archive. Arguments:
#   $1 archive path   $2 app id   $3 schema version of the backup format
#   $4 installed version (may be empty -> null)
# The sha256 sidecar must already exist; its digest is embedded so consumers
# can cross-check manifest and sidecar for tampering. Written atomically with
# mode 600 via the shared escaper, matching status-JSON conventions.
# Finalize a completed archive with the shared integrity metadata contract.
# The archive must already have been moved to its final path. This helper keeps
# checksum/manifest orchestration identical for application-specific backups;
# callers can decide whether metadata failure is fatal for their workflow.
backup_finalize_archive() {
  local archive="$1" app_id="$2" installed_version="${3:-}" schema_version="${4:-1}"
  [[ -f "$archive" ]] || return 1
  backup_write_sha256 "$archive" >/dev/null \
    && backup_write_manifest "$archive" "$app_id" "$schema_version" "$installed_version"
}

# Create a gzip tar archive in a unique sibling temporary file and publish it
# atomically at ARCHIVE with private mode 0600. Remaining arguments are passed
# verbatim to tar after its output path, so callers retain control over
# excludes and source layout. Any failed tar, permission, or publish step
# removes the temporary file and leaves an existing final archive untouched.
backup_create_tar_archive() {
  local archive="$1" archive_tmp
  shift
  [[ -n "$archive" && "$#" -gt 0 ]] || return 1
  archive_tmp="$(mktemp "${archive}.tmp.XXXXXX")" || return 1
  if ! tar -czf "$archive_tmp" "$@" >&2; then
    rm -f "$archive_tmp"
    return 1
  fi
  if ! chmod 600 "$archive_tmp"; then
    rm -f "$archive_tmp"
    return 1
  fi
  if ! mv "$archive_tmp" "$archive"; then
    rm -f "$archive_tmp"
    return 1
  fi
}

# Run PRODUCER_ARGS, compress its stdout to a gzip archive in a unique sibling
# temporary file, and publish it atomically at ARCHIVE. The producer and gzip
# statuses are checked before publication so a failed producer cannot leave a
# partial final archive behind. The caller controls producer stderr by passing
# a command or shell function with the desired redirection.
# Any failed producer, gzip, or publish step removes the temporary file and
# leaves an existing final archive untouched.
backup_create_gzip_archive() {
  local archive="$1" archive_tmp producer_status gzip_status
  local -a pipeline_status=()
  shift
  [[ -n "$archive" && "$#" -gt 0 ]] || return 1
  archive_tmp="$(mktemp "${archive}.tmp.XXXXXX")" || return 1
  if "$@" | gzip >"$archive_tmp"; then
    pipeline_status=("${PIPESTATUS[@]}")
  else
    pipeline_status=("${PIPESTATUS[@]}")
  fi
  producer_status="${pipeline_status[0]:-1}"
  gzip_status="${pipeline_status[1]:-1}"
  if (( producer_status != 0 || gzip_status != 0 )); then
    rm -f "$archive_tmp"
    return 1
  fi
  if ! mv "$archive_tmp" "$archive"; then
    rm -f "$archive_tmp"
    return 1
  fi
}

backup_write_manifest() {
  local archive="$1" app_id="$2" schema_version="$3" installed_version="${4:-}"
  local digest name created_at
  digest="$(backup_read_sha256 "${archive}.sha256")" || return 1
  name="$(basename "$archive")"
  created_at="$(date '+%Y-%m-%dT%H:%M:%S%:z')"
  if ! atomic_write_file "${archive}.manifest.json" 600 <<MANIFEST
{"schema_version":${schema_version},"app":$(app_json_string "$app_id"),"archive":$(app_json_string "$name"),"sha256":"$digest","created_at":$(app_json_string "$created_at"),"installed_version":$(app_json_string "$installed_version")}
MANIFEST
  then
    return 1
  fi
}

# Verify one archive: recompute the digest and compare against both the
# sidecar and (when present) the manifest. Prints nothing; returns nonzero on
# any mismatch or missing artifact. A missing sidecar fails closed — archives
# without integrity metadata are reported by the caller as unverified instead.
backup_verify_archive() {
  local archive="$1" expected actual manifest_digest=""
  [[ -f "$archive" ]] || return 1
  expected="$(backup_read_sha256 "${archive}.sha256")" || return 1
  actual="$(backup_sha256_file "$archive")" || return 1
  [[ "$actual" == "$expected" ]] || return 1
  if [[ -f "${archive}.manifest.json" ]]; then
    manifest_digest="$(backup_manifest_field "${archive}.manifest.json" sha256)" || return 1
    [[ "$manifest_digest" == "$expected" ]] || return 1
  fi
  return 0
}

# Validate a gzip backup before a caller mutates any live state. Integrity
# metadata is checked when present, while pre-manifest archives remain usable;
# gzip itself is always tested so a corrupt SQL dump is rejected early.
backup_validate_gzip_archive() {
  local archive="$1"
  [[ -f "$archive" ]] || return 1
  if [[ -f "${archive}.sha256" ]] && ! backup_verify_archive "$archive"; then
    return 1
  fi
  gzip -t "$archive" >/dev/null 2>&1
}

# Print the newest archive path (by mtime) matching one or more globs in a
# backup directory, or nothing when none exist. Mirrors the find/sort idiom of
# app_backup_latest_archive_json so verify and status agree on "latest".
backup_latest_archive() {
  local backup_dir="$1" glob
  local find_args=() latest=""
  shift
  for glob in "$@"; do
    [[ ${#find_args[@]} -eq 0 ]] || find_args+=(-o)
    find_args+=(-name "$glob")
  done
  latest="$(find "$backup_dir" -maxdepth 1 -type f \( "${find_args[@]}" \) -printf '%T@|%p\n' 2>/dev/null | sort -t'|' -k1,1nr)"
  latest="${latest%%$'\n'*}"
  [[ -z "$latest" ]] && return 1
  printf '%s\n' "${latest#*|}"
}

# List expired archive paths as NUL-delimited output. The retention value is
# normalized here so every caller skips cleanup for zero/invalid values and
# applies the same max-depth, regular-file, and staging-file rules.
backup_list_expired_archives() {
  local backup_dir="$1" keep_days="$2" glob
  local find_args=()
  shift 2
  [[ -d "$backup_dir" ]] || return 0
  [[ "$keep_days" =~ ^[0-9]+$ ]] || keep_days=0
  [[ "$keep_days" -gt 0 && "$#" -gt 0 ]] || return 0
  for glob in "$@"; do
    [[ ${#find_args[@]} -eq 0 ]] || find_args+=(-o)
    find_args+=(-name "$glob")
  done
  find "$backup_dir" -maxdepth 1 -type f \( "${find_args[@]}" \) \
    ! -name '*.tmp' -mtime "+${keep_days}" -print0 2>/dev/null
}

# Remove an archive and any integrity sidecars that belong to it. Sidecars are
# removed only after the archive removal succeeds; if a cleanup step fails,
# return nonzero so callers can report the per-file failure and retry later.
backup_remove_archive_with_metadata() {
  local archive="$1" companion cleanup_status=0
  [[ -n "$archive" ]] || return 1
  if ! rm -f -- "$archive"; then
    return 1
  fi
  for companion in "${archive}.sha256" "${archive}.manifest.json"; do
    if [[ -e "$companion" || -L "$companion" ]] && ! rm -f -- "$companion"; then
      cleanup_status=1
    fi
  done
  return "$cleanup_status"
}

# List every archive (absolute paths) matching the globs, oldest first, with
# the staging suffix excluded.
backup_list_archives() {
  local backup_dir="$1" glob
  local find_args=()
  shift
  for glob in "$@"; do
    [[ ${#find_args[@]} -eq 0 ]] || find_args+=(-o)
    find_args+=(-name "$glob")
  done
  find "$backup_dir" -maxdepth 1 -type f \( "${find_args[@]}" \) ! -name '*.tmp' -print 2>/dev/null | sort
}

# Verify the newest archive in a directory and print a single-line JSON
# verdict consumable by status projections and batch summaries:
#   {"state":"verified|failed|unverified","archive":...,"message":...}
# unverified means no integrity metadata exists yet (pre-manifest backups).
backup_verify_latest_json() {
  local backup_dir="$1"
  shift
  local archive digest_state="unverified" message="no integrity metadata for this backup"
  if ! is_safe_path "$backup_dir" || [[ ! -d "$backup_dir" ]]; then
    printf '{"state":"unknown","archive":null,"message":"backup directory is missing or unsafe"}'
    return
  fi
  archive="$(backup_latest_archive "$backup_dir" "$@")" || {
    printf '{"state":"missing","archive":null,"message":"no backup archive found"}'
    return
  }
  if [[ ! -f "${archive}.sha256" ]]; then
    printf '{"state":"unverified","archive":%s,"message":%s}' \
      "$(app_json_string "$(basename "$archive")")" "$(app_json_string "$message")"
    return
  fi
  if backup_verify_archive "$archive"; then
    digest_state="verified"
    message="checksum and manifest match"
  else
    digest_state="failed"
    message="checksum or manifest mismatch; backup may be corrupted"
  fi
  printf '{"state":"%s","archive":%s,"message":%s}' \
    "$digest_state" "$(app_json_string "$(basename "$archive")")" "$(app_json_string "$message")"
}

# Validate that a gzip tar archive can be listed and has no path-traversal
# members. Prints nothing; returns nonzero for unreadable archives, absolute
# paths, parent-directory segments, or Windows-style backslashes. Callers keep
# their own user-facing error text and decide when to perform checksum checks.
backup_validate_archive_members() {
  local archive="$1" member_list member
  member_list="$(tar -tzf "$archive" 2>/dev/null)" || return 1
  while IFS= read -r member; do
    case "$member" in
      ""|/*|*'/../'*|../*|*'/..'|..|*"\\"*) return 1 ;;
    esac
  done <<< "$member_list"
}

# Restore one directory from an archive without owning the service lifecycle.
# The archive may contain either a top-level directory matching the target
# basename or a bare directory payload. Existing targets are set aside before
# extraction and restored if any staging step fails. A caller that has stopped
# a service must handle a non-zero return by restoring its service lifecycle.
backup_restore_directory() {
  local target_dir="$1" archive="$2"
  if [[ -f "${archive}.sha256" ]] && ! backup_verify_archive "$archive"; then
    return 1
  fi
  if ! backup_validate_archive_members "$archive"; then
    return 1
  fi

  local target_parent target_base aside_dir extract_dir payload restored=false had_target=false
  target_parent="$(dirname "$target_dir")"
  target_base="$(basename "$target_dir")"
  mkdir -p "$target_parent" || return 1
  aside_dir="$(mktemp -d "${target_parent}/.${target_base}.restore-aside.XXXXXX")" || return 1
  if [[ -e "$target_dir" || -L "$target_dir" ]]; then
    had_target=true
    if ! mv "$target_dir" "${aside_dir}/${target_base}"; then
      rm -rf "$aside_dir"
      return 1
    fi
  fi
  if ! extract_dir="$(mktemp -d "${target_parent}/.${target_base}.restore.XXXXXX")"; then
    if [[ "$had_target" == true ]]; then
      mv "${aside_dir}/${target_base}" "$target_dir" 2>/dev/null || true
    fi
    rm -rf "$aside_dir"
    return 1
  fi

  if tar -xzf "$archive" -C "$extract_dir"; then
    payload="$extract_dir"
    if [[ -d "${extract_dir}/${target_base}" ]]; then
      payload="${extract_dir}/${target_base}"
    fi
    if mv "$payload" "$target_dir"; then
      restored=true
      [[ "$payload" == "$extract_dir" ]] && extract_dir=""
    fi
  fi
  [[ -z "$extract_dir" ]] || rm -rf "$extract_dir"
  if [[ "$restored" != true ]]; then
    rm -rf "$target_dir"
    if [[ "$had_target" == true ]]; then
      mv "${aside_dir}/${target_base}" "$target_dir" 2>/dev/null || true
    fi
    rm -rf "$aside_dir"
    return 1
  fi
  rm -rf "$aside_dir"
}

# Restore one archive over a service's data directory, with full rollback.
# Arguments: $1 data dir  $2 optional systemd unit name  $3 archive path.
# Caller must already have: required root, taken the app lock, selected a
# path-confined archive. Verifies the checksum before touching anything and
# rejects unsafe tar members. When a service name is supplied, this helper
# manages stop/restart and rolls data back if the service cannot start. An
# empty service name is for multi-artifact restores whose caller already owns
# the service lifecycle (for example, Sub2API's data/config/database stages).
backup_restore_data_dir() {
  local data_dir="$1" service_name="$2" archive="$3"
  if [[ -f "${archive}.sha256" ]] && ! backup_verify_archive "$archive"; then
    if [[ -n "$service_name" ]]; then
      error "$(t backup.verify.failed "$(basename "$archive")")"
    fi
    return 1
  fi
  if ! backup_validate_archive_members "$archive"; then
    if [[ -n "$service_name" ]]; then
      error "$(t backup.restore.invalid_archive "$archive")"
    fi
    return 1
  fi
  info "$(t backup.restore.using "$archive")"

  if [[ -n "$service_name" ]]; then
    systemctl stop "$service_name" || error "$(t backup.restore.stop_failed "$service_name")"
  fi
  local data_parent data_base staged_aside restored=false
  data_parent="$(dirname "$data_dir")"
  data_base="$(basename "$data_dir")"
  staged_aside="${data_dir}.restore.$(date +%Y%m%d%H%M%S)"
  if ! mv "$data_dir" "$staged_aside"; then
    if [[ -n "$service_name" ]]; then
      systemctl start "$service_name" || true
    fi
    if [[ -n "$service_name" ]]; then
      error "$(t backup.restore.invalid_archive "$archive")"
    fi
    return 1
  fi
  if ! extract_dir=$(mktemp -d "${data_parent}/.${data_base}.restore.XXXXXX"); then
    mv "$staged_aside" "$data_dir"
    if [[ -n "$service_name" ]]; then
      systemctl start "$service_name" || true
    fi
    if [[ -n "$service_name" ]]; then
      error "$(t backup.restore.invalid_archive "$archive")"
    fi
    return 1
  fi
  if tar -xzf "$archive" -C "$extract_dir"; then
    # Archives store either the bare payload (tar -C stage .) or a single
    # top-level directory named after the data dir (tar -C parent).
    local payload="$extract_dir"
    if [[ -d "${extract_dir}/${data_base}" ]]; then
      payload="${extract_dir}/${data_base}"
    fi
    if mv "$payload" "$data_dir"; then
      restored=true
      [[ "$payload" == "$extract_dir" ]] && extract_dir=""
    fi
  fi
  [[ -z "$extract_dir" ]] || rm -rf "$extract_dir"
  if [[ "$restored" != "true" ]]; then
    rm -rf "$data_dir"
    mv "$staged_aside" "$data_dir"
    if [[ -n "$service_name" ]]; then
      systemctl start "$service_name" || true
    fi
    if [[ -n "$service_name" ]]; then
      error "$(t backup.restore.invalid_archive "$archive")"
    fi
    return 1
  fi
  chown -R root:root "$data_dir" 2>/dev/null || true
  if [[ -z "$service_name" ]]; then
    rm -rf "$staged_aside"
    success "$(t backup.restore.restored "$(basename "$archive")")"
    return 0
  fi
  if systemctl start "$service_name"; then
    wait_for_service "$service_name" 20 || true
  fi
  if ! systemctl is-active --quiet "$service_name"; then
    warn "$(t backup.restore.start_failed_rollback)"
    systemctl stop "$service_name" 2>/dev/null || true
    rm -rf "$data_dir"
    if mv "$staged_aside" "$data_dir"; then
      success "$(t backup.restore.rollback_done)"
    else
      warn "$(t backup.restore.rollback_failed "$staged_aside")"
    fi
    systemctl start "$service_name" \
      || error "$(t binary_app.error.install_start_failed "$service_name" "$service_name")"
    error "$(t binary_app.error.update_failed "$(systemctl is-active "$service_name" 2>/dev/null || echo unknown)")"
  fi
  rm -rf "$staged_aside"
  success "$(t backup.restore.restored "$(basename "$archive")")"
}

# Verify the newest archive in a backup directory and print the human verdict
# (success message / warning / localized error) for a per-app verify action.
# Caller must already have: shown banner, required root, loaded config, and
# validated the directory with require_safe_path. Exits via error() on a
# failed checksum; missing/unverified archives are informational only, so
# pre-manifest backups stay visible without blocking the operator.
app_verify_latest_backup() {
  local backup_dir="$1"
  shift
  local verdict state archive_name sidecar_digest
  verdict="$(backup_verify_latest_json "$backup_dir" "$@")"
  state="$(state_json_field "$verdict" state 2>/dev/null || true)"
  case "$state" in
    missing)
      info "$(t backup.verify.no_backups "$backup_dir")"
      return 0
      ;;
    unverified)
      warn "$(t backup.verify.unverified "$(state_json_field "$verdict" archive)")"
      return 0
      ;;
  esac
  archive_name="$(state_json_field "$verdict" archive)"
  if [[ "$state" == "verified" ]]; then
    sidecar_digest="$(backup_read_sha256 "${backup_dir}/${archive_name}.sha256")"
    success "$(t backup.verify.verified "$archive_name" "$sidecar_digest")"
    return 0
  fi
  error "$(t backup.verify.failed "$archive_name")"
}

# Extract one top-level string field from a manifest.json produced by
# backup_write_manifest. Prints the raw (still escaped) value; returns nonzero
# when the field is absent or the document is not the expected shape.
backup_manifest_field() {
  local manifest="$1" field="$2"
  [[ -f "$manifest" ]] || return 1
  awk -v field="\"$field\":" '
    BEGIN { found = 0 }
    {
      line = $0
      while ((idx = index(line, field)) > 0) {
        rest = substr(line, idx + length(field))
        sub(/^[[:space:]]*/, "", rest)
        if (substr(rest, 1, 1) == "\"") {
          value = substr(rest, 2)
          end = index(value, "\"")
          if (end > 1 || length(value) == 0) {
            print substr(value, 1, end - 1)
            found = 1
            exit
          }
        } else if (substr(rest, 1, 4) == "null") {
          print ""
          found = 1
          exit
        }
        line = substr(line, idx + length(field))
      }
    }
    END { exit found ? 0 : 1 }
  ' "$manifest"
}
