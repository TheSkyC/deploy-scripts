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
