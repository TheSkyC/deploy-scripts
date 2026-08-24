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
