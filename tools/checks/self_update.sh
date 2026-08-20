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