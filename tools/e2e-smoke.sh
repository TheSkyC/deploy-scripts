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
#   - newapi migrated lifecycle (env file + cron backup script): install -> backup
#   - Sub2API: real PostgreSQL/Redis processes, database bootstrap, and pg_dump backup
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
with open(os.path.join(work, "newapi.bin"), "wb") as fh:
    fh.write(payload)
# Sub2API verifies both the ELF magic and the x86_64 e_machine field.
# It never executes this fixture binary because systemd is intentionally stubbed.
sub2api = bytearray(2 * 1024 * 1024)
sub2api[:4] = b"\x7fELF"
sub2api[4:7] = b"\x02\x01\x01"  # ELF64, little-endian, current version
sub2api[16:18] = (2).to_bytes(2, "little")  # ET_EXEC
sub2api[18:20] = (62).to_bytes(2, "little")  # EM_X86_64
with open(os.path.join(work, "sub2api.bin"), "wb") as fh:
    fh.write(sub2api)
PY

# Fake ntfy release tarball: ntfy_<ver>_linux_<arch>.tar.gz with a binary.
mkdir -p "$WORK/www/binwiederhier/ntfy/releases/download/v2.27.0"
mkdir -p "$WORK/www/ntfy-stage"
cp "$WORK/ntfy.bin" "$WORK/www/ntfy-stage/ntfy"
tar -czf "$WORK/www/binwiederhier/ntfy/releases/download/v2.27.0/ntfy_2.27.0_linux_amd64.tar.gz" \
  -C "$WORK/www/ntfy-stage" ntfy

# Fake new-api bare binary asset: new-api-<ver> (amd64).
mkdir -p "$WORK/www/QuantumNous/new-api/releases/download/v0.6.1"
cp "$WORK/newapi.bin" "$WORK/www/QuantumNous/new-api/releases/download/v0.6.1/new-api-0.6.1"

# Fake Sub2API tarball plus the checksum file required by its install flow.
mkdir -p "$WORK/www/Wei-Shaw/sub2api/releases/download/v0.1.0"
mkdir -p "$WORK/www/sub2api-stage"
cp "$WORK/sub2api.bin" "$WORK/www/sub2api-stage/sub2api"
tar -czf "$WORK/www/Wei-Shaw/sub2api/releases/download/v0.1.0/sub2api_0.1.0_linux_amd64.tar.gz" \
  -C "$WORK/www/sub2api-stage" sub2api
(
  cd "$WORK/www/Wei-Shaw/sub2api/releases/download/v0.1.0"
  sha256sum sub2api_0.1.0_linux_amd64.tar.gz > checksums.txt
)

# Fake GitHub API responses per repo path.
mkdir -p "$WORK/www/api"
printf '{"tag_name":"v2.27.0"}\n' > "$WORK/www/api/binwiederhier-ntfy_latest.json"
printf '{"tag_name":"v0.6.1"}\n' > "$WORK/www/api/QuantumNous-new-api_latest.json"
printf '{"tag_name":"v0.1.0"}\n' > "$WORK/www/api/Wei-Shaw-sub2api_latest.json"

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
RUN apt-get update -qq \
  && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    ca-certificates curl tar gzip python3 openssl sudo \
    postgresql-15 redis-server redis-tools
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

echo "=== e2e-smoke: newapi migrated lifecycle (env file + cron backup) ==="
docker run --rm \
  -v "$ROOT_MOUNT:/repo:ro" \
  -v "$STUB_MOUNT:/stub:ro" \
  -v "$WWW_MOUNT:/www:ro" \
  deploy-e2e-smoke bash -c '
set -euo pipefail
export PATH="/stub:$PATH"
LOG=/tmp/e2e.log
# newapi uses BA_APT_PACKAGES="sqlite3"; stub apt-get to report success.
cat > /usr/local/bin/apt-get <<APT
#!/bin/bash
exit 0
APT
chmod +x /usr/local/bin/apt-get
# sqlite3 is used by the backup hook; stub it as present so the WAL branch
# is exercised without a real database.
cat > /usr/local/bin/sqlite3 <<SQLITE
#!/bin/bash
if [[ "\$1" == "PRAGMA" ]]; then
  # First arg is the db file, second the pragma; wal_checkpoint is
  # non-fatal (|| true) and integrity_check reports ok.
  echo ok
fi
exit 0
SQLITE
chmod +x /usr/local/bin/sqlite3
# Install the migrated newapi: bare GitHub-release binary, private env file,
# cron backup script, and systemd unit via the shared lifecycle.
DOMAIN=api.example.com PORT=2587 INSTALL_DIR=/opt/new-api DATA_DIR=/opt/new-api/data \
LOG_DIR=/opt/new-api/logs SERVICE_NAME=new-api SERVICE_USER=newapi \
GITHUB_REPO=QuantumNous/new-api BACKUP_DIR=/opt/new-api-backups \
BACKUP_KEEP_DAYS=30 BACKUP_CRON="30 3 * * *" \
bash /repo/dist/install_newapi.sh install >"$LOG" 2>&1 || {
  cat "$LOG"
  echo "NEWAPI_INSTALL_FAILED"
  exit 1
}
grep -qE "Deployment Ready|verify service health before use" "$LOG" || { echo "NO_SUMMARY"; cat "$LOG"; exit 1; }
test -x /opt/new-api/new-api || { echo "BINARY_MISSING"; exit 1; }
test -f /etc/systemd/system/new-api.service || { echo "UNIT_MISSING"; exit 1; }
grep -q "EnvironmentFile=/etc/new-api.env" /etc/systemd/system/new-api.service || { echo "ENVFILE_NOT_WIRED"; cat /etc/systemd/system/new-api.service; exit 1; }
grep -q "LimitNOFILE=65536" /etc/systemd/system/new-api.service || { echo "LIMITS_MISSING"; exit 1; }
test -f /etc/new-api.env || { echo "ENV_FILE_MISSING"; exit 1; }
grep -q "^SESSION_SECRET=" /etc/new-api.env || { echo "NO_SESSION_SECRET"; exit 1; }
test -f /usr/local/bin/new-api-backup || { echo "BACKUP_SCRIPT_MISSING"; exit 1; }
test -f /etc/cron.d/new-api-backup || { echo "CRON_MISSING"; exit 1; }
grep -q "30 3 \* \* \* root /bin/bash /usr/local/bin/new-api-backup" /etc/cron.d/new-api-backup || { echo "CRON_BAD"; cat /etc/cron.d/new-api-backup; exit 1; }
# Manual backup must produce a new-api_ archive through the shared lifecycle
# (BA_ARCHIVE_PREFIX keeps the historical prefix).
bash /repo/dist/install_newapi.sh backup >"$LOG" 2>&1 || { echo "BACKUP_FAILED"; cat "$LOG"; exit 1; }
test -n "$(ls /opt/new-api-backups/new-api_*.tar.gz 2>/dev/null)" || { echo "NO_ARCHIVE"; exit 1; }
test -n "$(ls /opt/new-api-backups/new-api_*.tar.gz.sha256 2>/dev/null)" || { echo "NO_SIDECAR"; exit 1; }
echo "NEWAPI_SMOKE_OK"
' || exit 1

echo "=== e2e-smoke: Sub2API real PostgreSQL/Redis fixture ==="
docker run --rm \
  -v "$ROOT_MOUNT:/repo:ro" \
  -v "$STUB_MOUNT:/stub:ro" \
  -v "$WWW_MOUNT:/www:ro" \
  deploy-e2e-smoke bash -c '
set -euo pipefail
export PATH="/stub:$PATH"
LOG=/tmp/e2e.log
# The container has actual PostgreSQL 15 and Redis 7 packages. Start both
# daemons directly because systemd is deliberately stubbed for app lifecycle
# calls. --skip-systemctl-redirect keeps pg_ctlcluster from delegating back to
# the systemctl shim.
pg_ctlcluster --skip-systemctl-redirect 15 main start
for attempt in $(seq 1 30); do
  pg_isready -q && break
  sleep 1
done
pg_isready -q || { echo "POSTGRES_NOT_READY"; exit 1; }
redis-server --daemonize yes --bind 127.0.0.1 --port 6379
for attempt in $(seq 1 30); do
  redis-cli ping 2>/dev/null | grep -qx PONG && break
  sleep 1
done
redis-cli ping | grep -qx PONG || { echo "REDIS_NOT_READY"; exit 1; }
# The real dependency packages are already present, so bypass only the install
# action. Nginx remains a harmless command stub: this scenario focuses on the
# actual PostgreSQL/Redis bootstrap and backup contracts.
cat > /usr/local/bin/apt-get <<APT
#!/bin/bash
exit 0
APT
cat > /usr/local/bin/nginx <<NGINX
#!/bin/bash
exit 0
NGINX
chmod +x /usr/local/bin/apt-get /usr/local/bin/nginx
DOMAIN="" PORT=18082 INSTALL_DIR=/opt/sub2api DATA_DIR=/opt/sub2api/data \
LOG_DIR=/opt/sub2api/logs CONFIG_DIR=/etc/sub2api SERVICE_NAME=sub2api \
SERVICE_USER=sub2api GITHUB_REPO=Wei-Shaw/sub2api BACKUP_DIR=/opt/sub2api-backups \
BACKUP_KEEP_DAYS=30 bash /repo/dist/install_sub2api.sh install >"$LOG" 2>&1 || {
  cat "$LOG"
  echo "SUB2API_INSTALL_FAILED"
  exit 1
}
grep -qE "Sub2API deployment complete|Sub2API files installed" "$LOG" || { echo "NO_SUMMARY"; cat "$LOG"; exit 1; }
test -x /opt/sub2api/sub2api || { echo "BINARY_MISSING"; exit 1; }
test -f /etc/systemd/system/sub2api.service || { echo "UNIT_MISSING"; exit 1; }
test -f /etc/sub2api/.pg_dsn || { echo "PG_DSN_MISSING"; exit 1; }
test "$(stat -c %a /etc/sub2api/.pg_dsn)" = 600 || { echo "PG_DSN_MODE_BAD"; exit 1; }
# Exercise the deployed DSN with a real client and leave data that must appear
# in the real pg_dump artifact produced by the manual backup flow.
PG_DSN="$(cat /etc/sub2api/.pg_dsn)"
psql "$PG_DSN" -v ON_ERROR_STOP=1 -c "CREATE TABLE e2e_fixture (value text NOT NULL); INSERT INTO e2e_fixture VALUES ('fixture-row');" >"$LOG" 2>&1 || {
  cat "$LOG"
  echo "POSTGRES_DSN_FAILED"
  exit 1
}
redis-cli set sub2api-e2e fixture-value | grep -qx OK || { echo "REDIS_WRITE_FAILED"; exit 1; }
test "$(redis-cli get sub2api-e2e)" = fixture-value || { echo "REDIS_READ_FAILED"; exit 1; }
# The runtime dependency versions must have been persisted by the real tools.
source /etc/sub2api-deploy.conf
[[ "${INSTALLED_POSTGRES_VERSION}" =~ ^15\. ]] || { echo "POSTGRES_VERSION_NOT_SAVED"; exit 1; }
[[ "${INSTALLED_REDIS_VERSION}" =~ ^7\. ]] || { echo "REDIS_VERSION_NOT_SAVED"; exit 1; }
bash /repo/dist/install_sub2api.sh backup >"$LOG" 2>&1 || { cat "$LOG"; echo "BACKUP_FAILED"; exit 1; }
DB_ARCHIVE="$(ls -1t /opt/sub2api-backups/sub2api_db_*.sql.gz | head -1)"
test -n "$DB_ARCHIVE" || { echo "DB_ARCHIVE_MISSING"; exit 1; }
gzip -cd "$DB_ARCHIVE" | grep -Fq "fixture-row" || { echo "DB_DUMP_CONTENT_MISSING"; exit 1; }
test -n "$(ls /opt/sub2api-backups/sub2api_conf_*.tar.gz 2>/dev/null)" || { echo "CONF_ARCHIVE_MISSING"; exit 1; }
test -n "$(ls /opt/sub2api-backups/sub2api_data_*.tar.gz 2>/dev/null)" || { echo "DATA_ARCHIVE_MISSING"; exit 1; }
# Verify the persisted runtime versions reach the public component manifest.
bash /repo/dist/install_sub2api.sh status-json | python3 -c '\''
import json, sys
payload = json.load(sys.stdin)
components = payload["version_info"]["components"]
assert components["sub2api"]["repository"] == "Wei-Shaw/sub2api"
assert components["postgresql"]["installed"].startswith("15.")
assert components["postgresql"]["source"] == "system_runtime"
assert components["redis"]["installed"].startswith("7.")
assert components["redis"]["update_state"] == "not_checked"
'\'' || { echo "COMPONENT_MANIFEST_BAD"; exit 1; }
echo "SUB2API_REAL_DEPENDENCIES_SMOKE_OK"
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
if [[ " \$* " == *" rev-parse --verify HEAD "* ]]; then
  printf "0123456789abcdef0123456789abcdef01234567\\n"
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

echo "=== e2e-smoke: done (binary_app + real dependencies + compose paths passed) ==="
