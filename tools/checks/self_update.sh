#!/usr/bin/env bash

check_release_package_artifacts() {
  local first_dir second_dir first_sha second_sha
  first_dir="$(mktemp -d)"
  second_dir="$(mktemp -d)"
  if ! SOURCE_DATE_EPOCH=0 "$BASH_BIN" tools/package-release.sh --allow-dirty \
    --output-dir "$first_dir" --download-base-url 'https://example.invalid/releases/v9.9.9' v9.9.9 >/dev/null; then
    rm -rf "$first_dir" "$second_dir"
    return 1
  fi
  if ! SOURCE_DATE_EPOCH=0 "$BASH_BIN" tools/package-release.sh --allow-dirty \
    --output-dir "$second_dir" --download-base-url 'https://example.invalid/releases/v9.9.9' v9.9.9 >/dev/null; then
    rm -rf "$first_dir" "$second_dir"
    return 1
  fi
  first_sha="$(sha256sum "${first_dir}/deploy-scripts-v9.9.9.tar.gz" | awk '{print $1}')"
  second_sha="$(sha256sum "${second_dir}/deploy-scripts-v9.9.9.tar.gz" | awk '{print $1}')"
  [[ "$first_sha" == "$second_sha" ]] || { rm -rf "$first_dir" "$second_dir"; return 1; }
  if ! python - "$first_dir" "$first_sha" <<'PY'
import hashlib
import json
import os
import sys
import tarfile

output_dir, archive_sha = sys.argv[1:]
archive_name = "deploy-scripts-v9.9.9.tar.gz"
archive_path = os.path.join(output_dir, archive_name)
with open(os.path.join(output_dir, "manifest.json"), encoding="utf-8") as handle:
    manifest = json.load(handle)
assert manifest == {
    "schema_version": 1,
    "project": "deploy-scripts",
    "channel": "stable",
    "version": "v9.9.9",
    "published_at": "1970-01-01T00:00:00Z",
    "minimum": {"bash": "4.3"},
    "artifacts": {
        "source": {
            "name": archive_name,
            "url": "https://example.invalid/releases/v9.9.9/" + archive_name,
            "sha256": archive_sha,
            "size_bytes": os.path.getsize(archive_path),
        }
    },
    "notes": [],
}
with open(archive_path, "rb") as handle:
    assert hashlib.sha256(handle.read()).hexdigest() == archive_sha
with open(archive_path + ".sha256", encoding="utf-8") as handle:
    assert handle.read() == f"{archive_sha}  {archive_name}\n"
with tarfile.open(archive_path, "r:gz") as archive:
    names = archive.getnames()
    prefix = "deploy-scripts-v9.9.9/"
    assert prefix + "deploy.sh" in names
    assert prefix + "lib/core.sh" in names
    assert prefix + "RELEASE.json" in names
    assert not any(name == ".git" or name.startswith(".git/") or "/.git/" in name for name in names)
    assert not any(member.issym() or member.islnk() for member in archive.getmembers())
    release = json.load(archive.extractfile(prefix + "RELEASE.json"))
assert release["schema_version"] == 1
assert release["project"] == "deploy-scripts"
assert release["version"] == "v9.9.9"
assert release["built_at"] == "1970-01-01T00:00:00Z"
assert len(release["build_commit"]) == 40
PY
  then
    rm -rf "$first_dir" "$second_dir"
    return 1
  fi
  if SOURCE_DATE_EPOCH=0 "$BASH_BIN" tools/package-release.sh --allow-dirty \
    --output-dir "$first_dir" --download-base-url 'http://example.invalid/releases' v9.9.9 >/dev/null 2>&1; then
    rm -rf "$first_dir" "$second_dir"
    return 1
  fi
  if SOURCE_DATE_EPOCH=0 "$BASH_BIN" tools/package-release.sh --allow-dirty \
    --output-dir "$first_dir" --download-base-url 'https://token@example.invalid/releases' v9.9.9 >/dev/null 2>&1; then
    rm -rf "$first_dir" "$second_dir"
    return 1
  fi
  rm -rf "$first_dir" "$second_dir"
}

check_self_version_and_manifest_checks() {
  local managed_root fake_bin fixture output
  managed_root="$(mktemp -d)"
  fake_bin="$(mktemp -d)"
  fixture="$(mktemp)"
  mkdir -p "${managed_root}/releases/v1.2.3" "${managed_root}/releases/v1.1.0"
  mkdir -p "${managed_root}/current" "${managed_root}/previous"
  cat >"${managed_root}/releases/v1.2.3/RELEASE.json" <<'JSON'
{"schema_version":1,"project":"deploy-scripts","version":"v1.2.3","build_commit":"0123456789012345678901234567890123456789","built_at":"1970-01-01T00:00:00Z"}
JSON
  cp "${managed_root}/releases/v1.2.3/RELEASE.json" "${managed_root}/current/RELEASE.json"
  cat >"${managed_root}/releases/v1.1.0/RELEASE.json" <<'JSON'
{"schema_version":1,"project":"deploy-scripts","version":"v1.1.0","build_commit":"0123456789012345678901234567890123456789","built_at":"1970-01-01T00:00:00Z"}
JSON
  cp "${managed_root}/releases/v1.1.0/RELEASE.json" "${managed_root}/previous/RELEASE.json"
  cat >"$fixture" <<'JSON'
{"schema_version":1,"project":"deploy-scripts","channel":"stable","version":"v1.3.0","published_at":"1970-01-01T00:00:00Z","minimum":{"bash":"4.3"},"artifacts":{"source":{"name":"deploy-scripts-v1.3.0.tar.gz","url":"https://updates.invalid/v1.3.0/deploy-scripts-v1.3.0.tar.gz","sha256":"0123456789012345678901234567890123456789012345678901234567890123","size_bytes":1234}},"notes":[]}
JSON
  cat >"${fake_bin}/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
output=""
while (($#)); do
  if [[ "$1" == -o ]]; then output="$2"; shift 2
  else shift
  fi
done
[[ -n "$output" ]]
cat "${SELF_UPDATE_FIXTURE}" > "$output"
SH
  chmod 700 "${fake_bin}/curl"
  if ! output="$(env DEPLOY_ROOT_DIR="${managed_root}/releases/v1.2.3" DEPLOY_SELF_UPDATE_ROOT="$managed_root" \
    "$BASH_BIN" -c '
      set -euo pipefail
      source lib/core.sh
      self_update_load_config
      self_update_version_json
    ')"; then
    rm -rf "$managed_root" "$fake_bin" "$fixture"
    return 1
  fi
  if ! python - "$output" <<'PY'
import json
import sys
payload = json.loads(sys.argv[1])
assert payload["mode"] == "managed_release"
assert payload["version"] == "v1.2.3"
assert payload["previous_version"] == "v1.1.0"
assert payload["can_update"] is True
PY
  then
    rm -rf "$managed_root" "$fake_bin" "$fixture"
    return 1
  fi
  if ! output="$(env PATH="${fake_bin}:$PATH" SELF_UPDATE_FIXTURE="$fixture" \
    DEPLOY_ROOT_DIR="${managed_root}/releases/v1.2.3" DEPLOY_SELF_UPDATE_ROOT="$managed_root" \
    DEPLOY_SELF_UPDATE_URL='https://updates.invalid/v1.3.0' "$BASH_BIN" -c '
      set -euo pipefail
      source lib/core.sh
      self_update_check_main 1
    ')"; then
    rm -rf "$managed_root" "$fake_bin" "$fixture"
    return 1
  fi
  if ! python - "$output" <<'PY'
import json
import sys
payload = json.loads(sys.argv[1])
assert payload["state"] == "update_available"
assert payload["current_version"] == "v1.2.3"
assert payload["latest_version"] == "v1.3.0"
assert payload["artifact"]["name"] == "deploy-scripts-v1.3.0.tar.gz"
PY
  then
    rm -rf "$managed_root" "$fake_bin" "$fixture"
    return 1
  fi
  output="$(env DEPLOY_ROOT_DIR="${managed_root}/releases/v1.2.3" DEPLOY_SELF_UPDATE_ROOT="$managed_root" \
    DEPLOY_SELF_UPDATE_URL='https://token@example.invalid/v1.3.0' "$BASH_BIN" -c '
      set +e
      source lib/core.sh
      self_update_check_main 1
    ' 2>/dev/null || true)"
  [[ "$output" != *token* ]] || { rm -rf "$managed_root" "$fake_bin" "$fixture"; return 1; }
  rm -rf "$managed_root" "$fake_bin" "$fixture"
}


check_self_update_dry_run_validation() {
  local managed_root fake_bin fixture_dir stage_dir archive_path fixture_snapshot output
  managed_root="$(mktemp -d)"
  fake_bin="$(mktemp -d)"
  fixture_dir="$(mktemp -d)"
  stage_dir="$(mktemp -d)"
  mkdir -p "${managed_root}/releases/v1.2.3" "${managed_root}/current" "${managed_root}/previous"
  printf '%s
' '{"schema_version":1,"project":"deploy-scripts","version":"v1.2.3","build_commit":"0123456789012345678901234567890123456789","built_at":"1970-01-01T00:00:00Z"}' >"${managed_root}/releases/v1.2.3/RELEASE.json"
  cp "${managed_root}/releases/v1.2.3/RELEASE.json" "${managed_root}/current/RELEASE.json"
  cp "${managed_root}/releases/v1.2.3/RELEASE.json" "${managed_root}/previous/RELEASE.json"
  mkdir -p "${stage_dir}/deploy-scripts-v1.3.0/lib"
  printf '#!/usr/bin/env bash
' >"${stage_dir}/deploy-scripts-v1.3.0/deploy.sh"
  printf '#!/usr/bin/env bash
' >"${stage_dir}/deploy-scripts-v1.3.0/lib/core.sh"
  printf '%s
' '{"schema_version":1,"project":"deploy-scripts","version":"v1.3.0","build_commit":"0123456789012345678901234567890123456789","built_at":"1970-01-01T00:00:00Z"}' >"${stage_dir}/deploy-scripts-v1.3.0/RELEASE.json"
  archive_path="${fixture_dir}/deploy-scripts-v1.3.0.tar.gz"
  tar -C "$stage_dir" -czf "$archive_path" deploy-scripts-v1.3.0
  local sha256 size_bytes
  sha256="$(sha256sum "$archive_path" | awk '{print $1}')"
  size_bytes="$(wc -c <"$archive_path" | tr -d '[:space:]')"
  cat >"${fixture_dir}/manifest.json" <<JSON
{"schema_version":1,"project":"deploy-scripts","channel":"stable","version":"v1.3.0","artifacts":{"source":{"name":"deploy-scripts-v1.3.0.tar.gz","url":"https://updates.invalid/v1.3.0/deploy-scripts-v1.3.0.tar.gz","sha256":"${sha256}","size_bytes":${size_bytes}}}}
JSON
  cat >"${fake_bin}/curl" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
output=""
while (($#)); do
  if [[ "$1" == -o ]]; then output="$2"; shift 2
  else shift
  fi
done
case "$(basename "$output")" in
  manifest.json) cp "${SELF_UPDATE_FIXTURE}/manifest.json" "$output" ;;
  *) cp "${SELF_UPDATE_FIXTURE}/deploy-scripts-v1.3.0.tar.gz" "$output" ;;
esac
SH
  chmod 700 "${fake_bin}/curl"
  fixture_snapshot="$(find "$managed_root" -type f -printf '%P
' | sort)"
  if ! output="$(env PATH="${fake_bin}:$PATH" SELF_UPDATE_FIXTURE="$fixture_dir" \
    DEPLOY_ROOT_DIR="${managed_root}/releases/v1.2.3" DEPLOY_SELF_UPDATE_ROOT="$managed_root" \
    DEPLOY_SELF_UPDATE_URL='https://updates.invalid/v1.3.0' "$BASH_BIN" -c '
      set -euo pipefail
      source lib/core.sh
      self_update_main --dry-run --json
    ')"; then
    rm -rf "$managed_root" "$fake_bin" "$fixture_dir" "$stage_dir"
    return 1
  fi
  if ! python - "$output" <<'PY'
import json
import sys
payload = json.loads(sys.argv[1])
assert payload["state"] == "validated"
assert payload["latest_version"] == "v1.3.0"
assert payload["artifact_size_bytes"] > 0
PY
  then
    rm -rf "$managed_root" "$fake_bin" "$fixture_dir" "$stage_dir"
    return 1
  fi
  [[ "$(find "$managed_root" -type f -printf '%P
' | sort)" == "$fixture_snapshot" ]] || {
    rm -rf "$managed_root" "$fake_bin" "$fixture_dir" "$stage_dir"
    return 1
  }
  rm -rf "$managed_root" "$fake_bin" "$fixture_dir" "$stage_dir"
}



check_self_update_managed_rehearsal() {
  if ! "$BASH_BIN" -c '
    set -euo pipefail
    managed_root="$(mktemp -d)"
    fixture_root="$(mktemp -d)"
    trap "rm -rf \"$managed_root\" \"$fixture_root\"" EXIT
    mkdir -p "${managed_root}/releases/v1.2.3" "${managed_root}/releases/v1.1.0"
    printf "%s\n" "{\"schema_version\":1,\"project\":\"deploy-scripts\",\"version\":\"v1.2.3\",\"build_commit\":\"0123456789012345678901234567890123456789\",\"built_at\":\"1970-01-01T00:00:00Z\"}" >"${managed_root}/releases/v1.2.3/RELEASE.json"
    printf "%s\n" "{\"schema_version\":1,\"project\":\"deploy-scripts\",\"version\":\"v1.1.0\",\"build_commit\":\"0123456789012345678901234567890123456789\",\"built_at\":\"1970-01-01T00:00:00Z\"}" >"${managed_root}/releases/v1.1.0/RELEASE.json"
    printf "%s\n" "${managed_root}/releases/v1.2.3" >"${managed_root}/current"
    printf "%s\n" "${managed_root}/releases/v1.1.0" >"${managed_root}/previous"

    make_release() {
      local version="$1" smoke_status="$2" stage archive sha256 size_bytes
      stage="${fixture_root}/stage-${version}"
      mkdir -p "${stage}/deploy-scripts-${version}/lib"
      cat >"${stage}/deploy-scripts-${version}/deploy.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
case "\${1:-}" in
  list) printf "%s\\n" "fixture release" ;;
  self-version) printf "%s\\n" "{\"schema_version\":1,\"mode\":\"managed_release\",\"version\":\"${version}\"}" ;;
  status-all) [[ "${smoke_status}" -eq 0 ]] && printf "%s\n" "{\"schema_version\":1,\"apps\":[],\"errors\":[]}" || exit "${smoke_status}" ;;
  *) exit 2 ;;
esac
SCRIPT
      printf "%s\n" "#!/usr/bin/env bash" "set -euo pipefail" >"${stage}/deploy-scripts-${version}/lib/core.sh"
      printf "%s\n" "{\"schema_version\":1,\"project\":\"deploy-scripts\",\"version\":\"${version}\",\"build_commit\":\"0123456789012345678901234567890123456789\",\"built_at\":\"1970-01-01T00:00:00Z\"}" >"${stage}/deploy-scripts-${version}/RELEASE.json"
      archive="${fixture_root}/deploy-scripts-${version}.tar.gz"
      tar -C "$stage" -czf "$archive" "deploy-scripts-${version}"
      sha256="$(sha256sum "$archive" | awk "{print \$1}")"
      size_bytes="$(wc -c <"$archive" | tr -d '[:space:]')"
      printf "%s\n" "{\"schema_version\":1,\"project\":\"deploy-scripts\",\"channel\":\"stable\",\"version\":\"${version}\",\"artifacts\":{\"source\":{\"name\":\"deploy-scripts-${version}.tar.gz\",\"url\":\"https://updates.invalid/${version}/deploy-scripts-${version}.tar.gz\",\"sha256\":\"${sha256}\",\"size_bytes\":${size_bytes}}}}" >"${fixture_root}/manifest-${version}.json"
    }
    make_release v1.3.0 0
    make_release v1.4.0 1

    fake_bin="${fixture_root}/bin"
    mkdir -p "$fake_bin"
    cat >"${fake_bin}/curl" <<\SCRIPT
#!/usr/bin/env bash
set -euo pipefail
output=""
url=""
while (($#)); do
  case "$1" in
    -o) output="$2"; shift 2 ;;
    *) url="$1"; shift ;;
  esac
done
version="$(basename "$(dirname "$url")")"
if [[ "$(basename "$url")" == manifest.json ]]; then
  cp "${SELF_UPDATE_FIXTURE}/manifest-${version}.json" "$output"
else
  cp "${SELF_UPDATE_FIXTURE}/deploy-scripts-${version}.tar.gz" "$output"
fi
SCRIPT
    printf "%s\n" "#!/usr/bin/env bash" "exit 0" >"${fake_bin}/flock"
    chmod 700 "${fake_bin}/curl" "${fake_bin}/flock"

    export PATH="${fake_bin}:$PATH"
    export SELF_UPDATE_FIXTURE="$fixture_root"
    export DEPLOY_ROOT_DIR="${managed_root}/releases/v1.2.3"
    export DEPLOY_SELF_UPDATE_ROOT="$managed_root"
    export DEPLOY_SELF_UPDATE_ALLOW_NONROOT_TEST=1
    export DEPLOY_OPERATION_ROOT="${managed_root}/operation"
    export DEPLOY_OPERATION_LOG_ROOT="${managed_root}/logs"
    export DEPLOY_SELF_UPDATE_LOCK_FILE="${managed_root}/self-update.lock"
    export DEPLOY_SELF_UPDATE_URL="https://updates.invalid/v1.3.0"

    source lib/core.sh
    atomic_symlink() {
      local target="$1" link="$2"
      rm -f -- "$link"
      printf "%s\n" "$target" >"$link"
    }
    self_update_current_target_for() {
      local managed_root="$1" target
      target="$(cat "${managed_root}/current")"
      [[ -d "$target" ]] || return 1
      printf "%s\n" "$target"
    }
    self_update_previous_target_for() {
      local managed_root="$1" target
      target="$(cat "${managed_root}/previous")"
      [[ -d "$target" ]] || return 1
      printf "%s\n" "$target"
    }

    self_update_detect_mode() {
      SELF_UPDATE_MODE=managed_release
      SELF_UPDATE_MANAGED_ROOT="$managed_root"
      SELF_UPDATE_VERSION="v1.2.3"
      SELF_UPDATE_ROOT="$managed_root"
      SELF_UPDATE_CURRENT_PATH="${managed_root}/current"
      SELF_UPDATE_PREVIOUS_PATH="${managed_root}/previous"
    }
    output="$(self_update_apply_main 1 1)"
    python - "$output" <<\PY
import json
import sys
payload = json.loads(sys.argv[1])
assert payload["state"] == "succeeded"
assert payload["latest_version"] == "v1.3.0"
PY
    [[ "$(cat "${managed_root}/current")" == "${managed_root}/releases/v1.3.0" ]]
    [[ "$(cat "${managed_root}/previous")" == "${managed_root}/releases/v1.2.3" ]]

    export DEPLOY_SELF_UPDATE_URL="https://updates.invalid/v1.4.0"
    set +e
    output="$(self_update_apply_main 1 1)"
    status=$?
    set -e
    [[ "$status" -eq 1 ]]
    python - "$output" <<\PY
import json
import sys
payload = json.loads(sys.argv[1])
assert payload["state"] == "rolled_back"
assert payload["latest_version"] == "v1.4.0"
PY
    [[ "$(cat "${managed_root}/current")" == "${managed_root}/releases/v1.3.0" ]]
    [[ "$(cat "${managed_root}/previous")" == "${managed_root}/releases/v1.2.3" ]]
    [[ ! -e "${managed_root}/releases/v1.4.0" ]]
  '; then
    return 1
  fi
}

check_self_update_activation_and_rollback() {
  if ! "$BASH_BIN" -c '
    set -euo pipefail
    managed_root="$(mktemp -d)"
    trap "rm -rf \"$managed_root\"" EXIT
    mkdir -p "${managed_root}/releases/v1.2.3"
    printf "%s\n" "{\"schema_version\":1,\"project\":\"deploy-scripts\",\"version\":\"v1.2.3\",\"build_commit\":\"0123456789012345678901234567890123456789\",\"built_at\":\"1970-01-01T00:00:00Z\"}" >"${managed_root}/releases/v1.2.3/RELEASE.json"
    export DEPLOY_ROOT_DIR="${managed_root}/releases/v1.2.3"
    export DEPLOY_SELF_UPDATE_ROOT="$managed_root"
    export DEPLOY_SELF_UPDATE_URL="https://updates.invalid/v1.3.0"
    export DEPLOY_SELF_UPDATE_ALLOW_NONROOT_TEST=1
    export DEPLOY_OPERATION_ROOT="${managed_root}/operation"
    export DEPLOY_OPERATION_LOG_ROOT="${managed_root}/logs"
    export DEPLOY_SELF_UPDATE_LOCK_FILE="${managed_root}/self-update.lock"
    fake_bin="${managed_root}/bin"
    mkdir -p "$fake_bin"
    printf "%s\\n" "#!/usr/bin/env bash" "exit 0" >"${fake_bin}/flock"
    chmod +x "${fake_bin}/flock"
    export PATH="${fake_bin}:$PATH"
    source lib/core.sh
    atomic_symlink() {
      rm -rf -- "$2"
      printf "%s\n" "$1" >"$2"
    }
    self_update_current_target_for() {
      if [[ -f "${managed_root}/current" ]]; then cat "${managed_root}/current"; else printf "%s\n" "${managed_root}/releases/v1.2.3"; fi
    }
    self_update_previous_target_for() {
      [[ -f "${managed_root}/previous" ]] || return 1
      cat "${managed_root}/previous"
    }
    self_update_confirm() { return 0; }
    self_update_cleanup_releases() { return 0; }
    self_update_smoke_check() { return "${SMOKE_STATUS:-0}"; }
    self_update_prepare_candidate() {
      local temp_dir="$1" version candidate
      version="${NEXT_VERSION:-v1.3.0}"
      candidate="${temp_dir}/extracted/deploy-scripts-${version}"
      mkdir -p "${candidate}/lib"
      printf "#!/usr/bin/env bash\n" >"${candidate}/deploy.sh"
      printf "#!/usr/bin/env bash\n" >"${candidate}/lib/core.sh"
      printf "%s\n" "{\"schema_version\":1,\"project\":\"deploy-scripts\",\"version\":\"${version}\",\"build_commit\":\"0123456789012345678901234567890123456789\",\"built_at\":\"1970-01-01T00:00:00Z\"}" >"${candidate}/RELEASE.json"
      SELF_UPDATE_MANIFEST_VERSION="$version"
      SELF_UPDATE_MANIFEST_NAME="deploy-scripts-${version}.tar.gz"
      SELF_UPDATE_MANIFEST_SHA256="0123456789012345678901234567890123456789012345678901234567890123"
      SELF_UPDATE_MANIFEST_SIZE_BYTES=1
      SELF_UPDATE_CANDIDATE_ROOT="$candidate"
      SELF_UPDATE_CANDIDATE_ARCHIVE="${temp_dir}/archive"
    }
    output="$(self_update_apply_main 1 1)"
    python - "$output" <<"PY"
import json
import sys
payload = json.loads(sys.argv[1])
assert payload["state"] == "succeeded"
assert payload["latest_version"] == "v1.3.0"
PY
    [[ "$(cat "${managed_root}/current")" == "${managed_root}/releases/v1.3.0" ]]
    [[ "$(cat "${managed_root}/previous")" == "${managed_root}/releases/v1.2.3" ]]
    export NEXT_VERSION=v1.4.0
    export SMOKE_STATUS=1
    output="$(self_update_apply_main 1 1)" || status=$?
    [[ "${status:-0}" -eq 1 ]]
    python - "$output" <<"PY"
import json
import sys
payload = json.loads(sys.argv[1])
assert payload["state"] == "rolled_back"
PY
    [[ "$(cat "${managed_root}/current")" == "${managed_root}/releases/v1.3.0" ]]
    [[ "$(cat "${managed_root}/previous")" == "${managed_root}/releases/v1.2.3" ]]
    export SMOKE_STATUS=0
    output="$(self_update_rollback_main 1 1)"
    python - "$output" <<"PY"
import json
import sys
payload = json.loads(sys.argv[1])
assert payload["state"] == "succeeded"
assert payload["target_version"] == "v1.2.3"
PY
    [[ "$(cat "${managed_root}/current")" == "${managed_root}/releases/v1.2.3" ]]
    [[ "$(cat "${managed_root}/previous")" == "${managed_root}/releases/v1.3.0" ]]
    output="$(self_update_list_main 1)"
    python - "$output" <<"PY"
import json
import sys
payload = json.loads(sys.argv[1])
assert payload["mode"] == "managed_release"
assert len(payload["releases"]) == 2
PY
    if self_update_main --check --list >/dev/null 2>&1; then
      exit 1
    fi
  '; then
    return 1
  fi
}

check_self_update_rejects_archive_listing_failure() {
  local temp_root fake_bin archive extraction_root
  temp_root="$(mktemp -d)"
  fake_bin="${temp_root}/bin"
  archive="${temp_root}/archive.tar.gz"
  extraction_root="${temp_root}/extracted"
  mkdir -p "$fake_bin"
  : > "$archive"
  cat >"${fake_bin}/tar" <<'SCRIPT'
#!/usr/bin/env bash
set -euo pipefail
if [[ "${1:-}" == --extract ]]; then
  extraction_root=""
  for ((index = 1; index <= $#; index++)); do
    if [[ "${!index:-}" == --directory ]]; then
      next=$((index + 1))
      extraction_root="${!next}"
      break
    fi
  done
  root="${extraction_root}/deploy-scripts-v1.3.0"
  mkdir -p "${root}/lib"
  printf '#!/usr/bin/env bash\n' >"${root}/deploy.sh"
  printf '#!/usr/bin/env bash\n' >"${root}/lib/core.sh"
  printf '%s\n' '{"schema_version":1,"project":"deploy-scripts","version":"v1.3.0"}' >"${root}/RELEASE.json"
  exit 0
fi
exit 1
SCRIPT
  chmod +x "${fake_bin}/tar"
  if PATH="${fake_bin}:$PATH" "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    self_update_validate_archive_layout "$1" "$2" v1.3.0
  ' _ "$archive" "$extraction_root"; then
    rm -rf "$temp_root"
    return 1
  fi
  rm -rf "$temp_root"
}

check_self_update_interruption_restores_activation() {
  local temp_root status
  temp_root="$(mktemp -d)"
  mkdir -p "$temp_root/releases/v1.2.3" "$temp_root/releases/v1.3.0"
  set +e
  DEPLOY_OPERATION_ROOT="${temp_root}/state" DEPLOY_OPERATION_LOG_ROOT="${temp_root}/log" "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    managed_root="$1"
    old_target="${managed_root}/releases/v1.2.3"
    old_previous="${managed_root}/releases/v1.1.0"
    release_path="${managed_root}/releases/v1.3.0"
    mkdir -p "$old_previous"
    printf "%s\n" "$old_target" > "${managed_root}/current"
    printf "%s\n" "$old_previous" > "${managed_root}/previous"
    atomic_symlink() {
      local target="$1" link="$2"
      printf "%s\n" "$target" > "$link"
    }
    self_update_operation_begin
    SELF_UPDATE_MANAGED_ROOT="$managed_root"
    SELF_UPDATE_OLD_TARGET="$old_target"
    SELF_UPDATE_OLD_PREVIOUS_TARGET="$old_previous"
    SELF_UPDATE_RELEASE_PATH="$release_path"
    SELF_UPDATE_ACTIVATION_STARTED=1
    SELF_UPDATE_CURRENT_CHANGED=1
    atomic_symlink "$release_path" "${managed_root}/current"
    kill -TERM "$$"
  ' _ "$temp_root"
  status=$?
  set -e
  if [[ "$status" -ne 143 ]]; then
    rm -rf "$temp_root"
    return 1
  fi
  [[ "$(cat "$temp_root/current")" == "$temp_root/releases/v1.2.3" ]] \
    || { rm -rf "$temp_root"; return 1; }
  [[ "$(cat "$temp_root/previous")" == "$temp_root/releases/v1.1.0" ]] \
    || { rm -rf "$temp_root"; return 1; }
  [[ ! -e "$temp_root/releases/v1.3.0" && ! -L "$temp_root/releases/v1.3.0" ]] \
    || { rm -rf "$temp_root"; return 1; }
  python - "${temp_root}/state/self-update.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    record = json.load(handle)
assert record["state"] == "interrupted"
assert "current was restored" in record["error"]
PY
  status=$?
  rm -rf "$temp_root"
  return "$status"
}

check_self_update_signal_interruption() {
  local temp_root status
  temp_root="$(mktemp -d)"
  set +e
  DEPLOY_OPERATION_ROOT="${temp_root}/state" DEPLOY_OPERATION_LOG_ROOT="${temp_root}/log" "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    self_update_operation_begin
    kill -TERM "$$"
  '
  status=$?
  set -e
  if [[ "$status" -ne 143 ]]; then
    rm -rf "$temp_root"
    return 1
  fi
  python - "${temp_root}/state/self-update.json" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    record = json.load(handle)
assert record["scope"] == "self_update"
assert record["state"] == "interrupted"
assert record["exit_code"] == 143
assert "SIGTERM" in record["error"]
PY
  status=$?
  rm -rf "$temp_root"
  return "$status"
}
