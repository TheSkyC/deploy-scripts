#!/usr/bin/env bash
# End-to-end smoke install matrix inside a Docker container.
#
# PLAN.md section 9 notes that real installs are never run on the dev
# machine. This script runs the actual install flow inside a disposable
# Debian container so the filesystem side of the lifecycle (download,
# extraction, user/dir setup, config writing, binary placement, backup
# creation) is exercised for real. systemd is stubbed (the container has
# no init); GitHub API and release downloads are served from a local HTTP
# server via a curl shim, so no external network is needed.
#
# Coverage:
#   - binary_app lifecycle path (ntfy): install -> backup -> verify
#   - compose path (tickflow): install files + config generation
#
# Usage: bash tools/e2e-smoke.sh        (requires docker; Linux recommended)
# The script fails with a nonzero exit on any step so CI can gate on it.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR" || exit 1

if ! command -v docker >/dev/null 2>&1; then
  echo "e2e-smoke: docker is required" >&2
  exit 1
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Docker Desktop on Windows needs Windows-style bind-mount paths; convert
# the repo and temp dirs when cygpath is available.
ROOT_MOUNT="$ROOT_DIR"
WORK_MOUNT="$WORK"
if command -v cygpath >/dev/null 2>&1; then
  ROOT_MOUNT="$(cygpath -w "$ROOT_DIR")"
  WORK_MOUNT="$(cygpath -w "$WORK")"
fi

echo "=== e2e-smoke: staging stub release assets ==="
PYTHON=""
if command -v python3 >/dev/null 2>&1 && python3 -c 'import sys' >/dev/null 2>&1; then
  PYTHON=python3
elif command -v python >/dev/null 2>&1; then
  PYTHON=python
fi
[[ -n "$PYTHON" ]] || { echo "e2e-smoke: python3 or python is required" >&2; exit 1; }
"$PYTHON" - "$WORK" <<'PY'
import os, sys
work = sys.argv[1]
payload = b"\x7fELF" + b"\0" * (2 * 1024 * 1024)
with open(os.path.join(work, "ntfy.bin"), "wb") as fh:
    fh.write(payload)
with open(os.path.join(work, "tickflow.bin"), "wb") as fh:
    fh.write(payload)
PY

# Fake ntfy release tarball: ntfy_<ver>_linux_<arch>.tar.gz with a binary.
mkdir -p "$WORK/www/binwiederhier/ntfy/releases/download/v2.27.0"
mkdir -p "$WORK/www/ntfy-stage"
cp "$WORK/ntfy.bin" "$WORK/www/ntfy-stage/ntfy"
tar -czf "$WORK/www/binwiederhier/ntfy/releases/download/v2.27.0/ntfy_2.27.0_linux_amd64.tar.gz" \
  -C "$WORK/www/ntfy-stage" ntfy

# Fake GitHub API responses per repo path.
mkdir -p "$WORK/www/api"
printf '{"tag_name":"v2.27.0"}\n' > "$WORK/www/api/binwiederhier-ntfy_latest.json"

# A stub systemctl + a curl shim that serves GitHub requests from the
# mounted /www tree (no network needed, works on every Docker host):
#   api.github.com/repos/<o>/<r>/releases/latest -> /www/api/<o>-<r>_latest.json
#   github.com/<o>/<r>/releases/download/<t>/<a>  -> /www/<o>/<r>/releases/download/<t>/<a>
STUB_DIR="$WORK/stub"
mkdir -p "$STUB_DIR"
cat > "$STUB_DIR/systemctl" <<'SYS'
#!/bin/bash
# Container has no init; every systemctl call reports success and the
# enable/daemon-reload paths are no-ops. --quiet is accepted by bash.
exit 0
SYS
cat > "$STUB_DIR/curl" <<'CURL'
#!/bin/bash
# Serve API/asset requests from the mounted /www tree. Supports the flag
# shapes the deploy scripts use: -o FILE, -fsSL URL, -w FORMAT.
output=""
for arg in "$@"; do
  if [[ "$arg" == "-o" ]]; then
    # next arg is the output file
    :
  fi
done
# Find -o target and the URL argument.
prev=""
url=""
for arg in "$@"; do
  if [[ "$prev" == "-o" ]]; then
    output="$arg"
  fi
  case "$arg" in
    https://api.github.com/repos/*/releases/latest)
      repo="${arg#*repos/}"
      repo="${repo%%/releases*}"
      # owner/repo -> owner-repo to match the stub file name.
      repo="${repo//\//-}"
      url="/www/api/${repo}_latest.json"
      ;;
    https://github.com/*/releases/download/*)
      path="${arg#https://github.com/}"
      url="/www/${path}"
      ;;
  esac
  prev="$arg"
done
if [[ -z "$url" ]]; then
  # Connectivity probes: report success with a minimal body.
  printf 'ok\n'
  exit 0
fi
if [[ -n "$output" && "$output" != "-" ]]; then
  cp "$url" "$output" 2>/dev/null || { printf 'not found: %s\n' "$url" >&2; exit 22; }
  exit 0
fi
cat "$url" 2>/dev/null || { printf 'not found: %s\n' "$url" >&2; exit 22; }
CURL
chmod +x "$STUB_DIR/systemctl" "$STUB_DIR/curl"

WWW_MOUNT="$WORK/www"
if command -v cygpath >/dev/null 2>&1; then
  WWW_MOUNT="$(cygpath -w "$WORK/www")"
fi

STUB_MOUNT="$STUB_DIR"
WWW_MOUNT="$WORK/www"
if command -v cygpath >/dev/null 2>&1; then
  STUB_MOUNT="$(cygpath -w "$STUB_DIR")"
  WWW_MOUNT="$(cygpath -w "$WORK/www")"
fi

echo "=== e2e-smoke: building disposable container ==="
docker build -t deploy-e2e-smoke - <<'DOCKERFILE'
FROM debian:bookworm-slim
RUN apt-get update -qq && apt-get install -y -qq ca-certificates curl tar gzip python3
DOCKERFILE

echo "=== e2e-smoke: binary_app lifecycle (ntfy install/backup/verify) ==="
docker run --rm \
  -v "$ROOT_MOUNT:/repo:ro" \
  -v "$STUB_MOUNT:/stub:ro" \
  -v "$WWW_MOUNT:/www:ro" \
  deploy-e2e-smoke bash -c '
set -euo pipefail
export PATH="/stub:$PATH"
LOG=/tmp/e2e.log
# The install flow calls apt-get; a slim container has none. The stub
# apt-get reports success so the flow proceeds to download/config.
cat > /usr/local/bin/apt-get <<APT
#!/bin/bash
exit 0
APT
chmod +x /usr/local/bin/apt-get
# useradd exists in the image; id/userdel come from passwd/usrbin. The
# install also calls hostname; the container has it via coreutils.
# Run the real dist script. bapp_install downloads the stub tarball from
# the local server, verifies the ELF payload, creates the user/dirs, writes
# the systemd unit (systemctl stubbed), and starts nothing real.
DOMAIN="" PORT=2586 INSTALL_DIR=/opt/ntfy DATA_DIR=/var/lib/ntfy \
LOG_DIR=/var/log/ntfy SERVICE_NAME=ntfy SERVICE_USER=ntfy \
GITHUB_REPO=binwiederhier/ntfy BACKUP_DIR=/opt/ntfy-backups \
BACKUP_KEEP_DAYS=30 BA_BIN_NAME=ntfy BA_ARCHIVE_TYPE=tar.gz \
BA_USE_ENV_FILE=0 BA_FIREWALL=0 \
bash /repo/dist/install_ntfy.sh install >"$LOG" 2>&1 || {
  cat "$LOG"
  echo "NTFY_INSTALL_FAILED"
  exit 1
}
# The summary may show the ready or pending title depending on the health
# probe (stubbed systemd means the service never actually listens).
grep -qE "Deployment Ready|verify service health before use" "$LOG" || { echo "NO_SUMMARY"; cat "$LOG"; exit 1; }
test -x /opt/ntfy/ntfy || { echo "BINARY_MISSING"; exit 1; }
test -f /etc/systemd/system/ntfy.service || { echo "UNIT_MISSING"; exit 1; }
grep -q "ExecStart=\"/opt/ntfy/ntfy\"" /etc/systemd/system/ntfy.service || { echo "UNIT_BAD"; exit 1; }
# Manual backup must produce an archive with integrity metadata.
bash /repo/dist/install_ntfy.sh backup >"$LOG" 2>&1 || { echo "BACKUP_FAILED"; exit 1; }
test -n "$(ls /opt/ntfy-backups/ntfy_*.tar.gz 2>/dev/null)" || { echo "NO_ARCHIVE"; exit 1; }
test -n "$(ls /opt/ntfy-backups/ntfy_*.tar.gz.sha256 2>/dev/null)" || { echo "NO_SIDECAR"; exit 1; }
echo "BINARY_APP_SMOKE_OK"
' || exit 1

echo "=== e2e-smoke: compose path (tickflow config + compose delegation) ==="
docker run --rm \
  -v "$ROOT_MOUNT:/repo:ro" \
  -v "$STUB_MOUNT:/stub:ro" \
  -v "$WWW_MOUNT:/www:ro" \
  deploy-e2e-smoke bash -c '
set -euo pipefail
export PATH="/stub:$PATH"
LOG=/tmp/e2e.log
# Stub git: a tickflow install clones a repo; provide a fake checkout that
# contains the docker-compose.yml so _write_compose_file and the unit write
# can proceed. docker compose is stubbed as present. Stubs are written under
# /usr/local/bin (the /stub mount is read-only).
cat > /usr/local/bin/git <<GIT
#!/bin/bash
if [[ "\$1" == "clone" ]]; then
  mkdir -p "\${@: -1}/.git"
  printf "services: []\\n" > "\${@: -1}/docker-compose.yml"
  exit 0
fi
exit 0
GIT
cat > /usr/local/bin/docker <<DOCKER
#!/bin/bash
exit 0
DOCKER
cat > /usr/local/bin/docker-compose <<DC
#!/bin/bash
exit 0
DC
chmod +x /usr/local/bin/git /usr/local/bin/docker /usr/local/bin/docker-compose
cat > /usr/local/bin/apt-get <<APT
#!/bin/bash
exit 0
APT
chmod +x /usr/local/bin/apt-get
# Install tickflow with compose stubbed: the shared compose_command must
# resolve, the env/compose files must be written, and the systemd unit must
# embed the resolved compose command.
TICKFLOW_INSTALL_DIR=/opt/tickflow \
TICKFLOW_PORT=3018 \
TICKFLOW_REPO=shy3130/tickflow-stock-panel \
TICKFLOW_BRANCH=main \
TICKFLOW_AUTH_PASSWORD=testpass \
bash /repo/dist/install_tickflow.sh install >"$LOG" 2>&1 || {
  cat "$LOG"
  echo "TICKFLOW_INSTALL_FAILED"
  exit 1
}
test -f /opt/tickflow/.env || { echo "ENV_MISSING"; exit 1; }
test -f /opt/tickflow/docker-compose.yml || { echo "COMPOSE_MISSING"; exit 1; }
test -f /etc/systemd/system/tickflow-stock-panel.service || { echo "UNIT_MISSING"; exit 1; }
grep -q "compose" /etc/systemd/system/tickflow-stock-panel.service || { echo "UNIT_NO_COMPOSE"; exit 1; }
echo "COMPOSE_PATH_SMOKE_OK"
' || exit 1

echo "=== e2e-smoke: done (binary_app + compose paths passed) ==="
