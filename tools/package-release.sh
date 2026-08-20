#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR=""
DOWNLOAD_BASE_URL=""
CHANNEL="stable"
ALLOW_DIRTY=0
PACKAGE_STAGE_DIR=""

usage() {
  cat >&2 <<'USAGE'
Usage: bash tools/package-release.sh [options] <vX.Y.Z>

Create a deterministic, self-contained framework release archive together
with an external manifest.json and SHA-256 sidecar. This command packages the
current Git commit, not uncommitted working-tree files.

Options:
  --output-dir DIR          Directory for archive, manifest, and checksum
                            (default: ./release-assets)
  --download-base-url URL   HTTPS release-asset base URL (required)
  --channel NAME            Release channel (default: stable)
  --allow-dirty             Permit a dirty checkout, while still packaging HEAD
  -h, --help                Show this help
USAGE
}

fail() {
  printf 'package-release: %s\n' "$*" >&2
  exit 1
}

validate_version() {
  local version="$1"
  [[ "$version" =~ ^v([0]|[1-9][0-9]*)\.([0]|[1-9][0-9]*)\.([0]|[1-9][0-9]*)(-([0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*))?$ ]] \
    || fail "invalid version '$version'; expected vX.Y.Z or a SemVer prerelease"
}

validate_channel() {
  [[ "${1:-}" =~ ^[a-z][a-z0-9_-]{0,31}$ ]] || fail "invalid release channel '${1:-}'"
}

validate_download_base_url() {
  local url="${1:-}"
  [[ "$url" =~ ^https://[A-Za-z0-9.-]+(:[0-9]+)?(/[A-Za-z0-9._~:/%+-]*)?$ ]] \
    || fail 'download base URL must be an HTTPS URL without credentials, queries, fragments, or unsafe characters'
}

release_built_at() {
  local epoch="${SOURCE_DATE_EPOCH:-}"
  if [[ -n "$epoch" ]]; then
    [[ "$epoch" =~ ^[0-9]+$ ]] || fail 'SOURCE_DATE_EPOCH must be a non-negative integer'
    date -u -d "@${epoch}" '+%Y-%m-%dT%H:%M:%SZ'
  else
    date -u '+%Y-%m-%dT%H:%M:%SZ'
  fi
}

prepare_output_dir() {
  [[ -n "$OUTPUT_DIR" ]] || OUTPUT_DIR="${ROOT_DIR}/release-assets"
  mkdir -p "$OUTPUT_DIR" || fail "cannot create output directory: $OUTPUT_DIR"
  OUTPUT_DIR="$(cd -- "$OUTPUT_DIR" && pwd)"
}

check_release_inputs() {
  git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 \
    || fail "not a Git checkout: $ROOT_DIR"
  if (( ! ALLOW_DIRTY )); then
    [[ -z "$(git -C "$ROOT_DIR" status --porcelain --untracked-files=all)" ]] \
      || fail 'working tree is dirty; commit changes or pass --allow-dirty explicitly'
  else
    printf 'package-release: warning: packaging HEAD and excluding uncommitted changes\n' >&2
  fi
  git -C "$ROOT_DIR" diff --quiet HEAD -- dist/ \
    || fail 'dist/ is out of date; rebuild and commit release scripts before packaging'
}

cleanup_stage() {
  if [[ -n "${PACKAGE_STAGE_DIR:-}" ]]; then
    rm -rf -- "$PACKAGE_STAGE_DIR"
    PACKAGE_STAGE_DIR=""
  fi
}

write_release_metadata() {
  local release_root="$1" version="$2" build_commit="$3" built_at="$4"
  cat >"${release_root}/RELEASE.json" <<EOF
{"schema_version":1,"project":"deploy-scripts","version":"${version}","build_commit":"${build_commit}","built_at":"${built_at}"}
EOF
  chmod 644 "${release_root}/RELEASE.json" || return 1
}

validate_staged_release() {
  local release_root="$1"
  [[ -f "${release_root}/deploy.sh" && -f "${release_root}/lib/core.sh" && -f "${release_root}/RELEASE.json" ]] \
    || return 1
  if find "$release_root" -type l -print -quit | grep -q .; then
    return 1
  fi
  while IFS= read -r -d '' script; do
    bash -n "$script" || return 1
  done < <(find "$release_root" -type f -name '*.sh' -print0)
}

main() {
  local version="" arg stage_dir release_root archive_name archive_tmp archive manifest_tmp checksum_tmp tar_epoch
  local build_commit built_at sha256 size_bytes archive_url
  while (($#)); do
    arg="$1"
    case "$arg" in
      --output-dir) (($# >= 2)) || fail '--output-dir requires a value'; OUTPUT_DIR="$2"; shift 2 ;;
      --download-base-url) (($# >= 2)) || fail '--download-base-url requires a value'; DOWNLOAD_BASE_URL="$2"; shift 2 ;;
      --channel) (($# >= 2)) || fail '--channel requires a value'; CHANNEL="$2"; shift 2 ;;
      --allow-dirty) ALLOW_DIRTY=1; shift ;;
      -h|--help) usage; exit 0 ;;
      --*) fail "unknown option: $arg" ;;
      *) [[ -z "$version" ]] || fail 'only one version may be supplied'; version="$arg"; shift ;;
    esac
  done
  [[ -n "$version" ]] || { usage; exit 2; }
  [[ -n "$DOWNLOAD_BASE_URL" ]] || fail '--download-base-url is required'
  validate_version "$version"
  validate_channel "$CHANNEL"
  validate_download_base_url "$DOWNLOAD_BASE_URL"
  check_release_inputs
  prepare_output_dir

  stage_dir="$(mktemp -d "${TMPDIR:-/tmp}/deploy-scripts-package.XXXXXX")" || fail 'cannot create private staging directory'
  PACKAGE_STAGE_DIR="$stage_dir"
  chmod 700 "$stage_dir" || { cleanup_stage; fail 'cannot secure staging directory'; }
  trap cleanup_stage EXIT
  release_root="${stage_dir}/deploy-scripts-${version}"
  if ! git -C "$ROOT_DIR" archive --format=tar --prefix="deploy-scripts-${version}/" HEAD | tar -xf - -C "$stage_dir"; then
    fail 'cannot stage Git archive'
  fi
  build_commit="$(git -C "$ROOT_DIR" rev-parse HEAD)"
  built_at="$(release_built_at)"
  write_release_metadata "$release_root" "$version" "$build_commit" "$built_at" \
    || fail 'cannot write internal RELEASE.json'
  validate_staged_release "$release_root" || fail 'staged release failed structural or shell validation'

  archive_name="deploy-scripts-${version}.tar.gz"
  archive="${OUTPUT_DIR}/${archive_name}"
  archive_tmp="$(mktemp "${OUTPUT_DIR}/.${archive_name}.XXXXXX")" || fail 'cannot create temporary archive'
  tar_epoch="${SOURCE_DATE_EPOCH:-0}"
  [[ "$tar_epoch" =~ ^[0-9]+$ ]] || { rm -f "$archive_tmp"; fail 'SOURCE_DATE_EPOCH must be a non-negative integer'; }
  if ! tar -C "$stage_dir" \
    --sort=name --mtime="@${tar_epoch}" --owner=0 --group=0 --numeric-owner \
    -cf - "$(basename "$release_root")" | gzip -n >"$archive_tmp"; then
    rm -f "$archive_tmp"
    fail 'cannot create release archive'
  fi
  sha256="$(sha256sum "$archive_tmp" | awk '{print $1}')"
  [[ "$sha256" =~ ^[0-9a-f]{64}$ ]] || { rm -f "$archive_tmp"; fail 'cannot calculate archive SHA-256'; }
  size_bytes="$(wc -c < "$archive_tmp" | tr -d '[:space:]')"
  [[ "$size_bytes" =~ ^[1-9][0-9]*$ ]] || { rm -f "$archive_tmp"; fail 'release archive is empty'; }
  mv -f "$archive_tmp" "$archive" || { rm -f "$archive_tmp"; fail 'cannot install release archive'; }
  chmod 644 "$archive" || fail 'cannot secure release archive permissions'

  checksum_tmp="$(mktemp "${OUTPUT_DIR}/.${archive_name}.sha256.XXXXXX")" || fail 'cannot create temporary checksum'
  printf '%s  %s\n' "$sha256" "$archive_name" > "$checksum_tmp" || { rm -f "$checksum_tmp"; fail 'cannot write checksum'; }
  mv -f "$checksum_tmp" "${archive}.sha256" || { rm -f "$checksum_tmp"; fail 'cannot install checksum'; }
  chmod 644 "${archive}.sha256" || fail 'cannot secure checksum permissions'

  archive_url="${DOWNLOAD_BASE_URL%/}/${archive_name}"
  manifest_tmp="$(mktemp "${OUTPUT_DIR}/.manifest.json.XXXXXX")" || fail 'cannot create temporary manifest'
  cat >"$manifest_tmp" <<EOF
{"schema_version":1,"project":"deploy-scripts","channel":"${CHANNEL}","version":"${version}","published_at":"${built_at}","minimum":{"bash":"4.3"},"artifacts":{"source":{"name":"${archive_name}","url":"${archive_url}","sha256":"${sha256}","size_bytes":${size_bytes}}},"notes":[]}
EOF
  mv -f "$manifest_tmp" "${OUTPUT_DIR}/manifest.json" || { rm -f "$manifest_tmp"; fail 'cannot install manifest'; }
  chmod 644 "${OUTPUT_DIR}/manifest.json" || fail 'cannot secure manifest permissions'

  printf 'Built %s\nBuilt %s\nBuilt %s\n' "$archive" "${archive}.sha256" "${OUTPUT_DIR}/manifest.json"
}

main "$@"