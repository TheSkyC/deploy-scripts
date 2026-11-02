#!/usr/bin/env bash
# Container-side half of tools/e2e-systemd.sh.
#
# Runs inside the booted systemd container as root. Everything it asserts is a
# real interaction with systemd, nginx, or the shipped release script; only the
# release download and package installation are stubbed so the run stays
# hermetic and offline.
set -euo pipefail

fail() {
  echo "$1" >&2
  exit 1
}

# --- hermetic release fixture ------------------------------------------------
# GitHub traffic is answered by a curl shim reading a local tree; local health
# probes still reach the real curl so the install sees a genuine failure to
# connect and reports it rather than pretending the app is healthy.
# The fixture lives on the container root filesystem: /tmp is a tmpfs mount and
# Docker mounts those noexec, so an executable shim placed there would not run.
#
# Meilisearch ships a bare binary and, unlike the other shared-binary apps, does
# not hardcode BA_SERVICE_ARGS, so this rehearsal can hand the unit
# "-f /dev/null" and point it at a real system binary that stays in the
# foreground. That is what makes "the unit is really running" assertable.
mkdir -p /e2e/www/api \
  /e2e/www/meilisearch/meilisearch/releases/download/v1.9.0 \
  /e2e/stage /e2e/bin
cp /opt/fixtures/service-bin /e2e/stage/meilisearch
# The installer rejects assets under 1 MiB. Trailing bytes past the end of an
# ELF image are ignored by the loader, so pad rather than ship a fake header.
head -c 1048576 /dev/zero >> /e2e/stage/meilisearch
cp /e2e/stage/meilisearch \
  /e2e/www/meilisearch/meilisearch/releases/download/v1.9.0/meilisearch-linux-amd64
printf '{"tag_name":"v1.9.0"}\n' > /e2e/www/api/meilisearch-meilisearch_latest.json

cat > /e2e/bin/curl <<'CURL'
#!/bin/bash
output=""
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
      repo="${repo//\//-}"
      url="/e2e/www/api/${repo}_latest.json"
      ;;
    https://api.github.com/repos/*/releases/tags/*)
      rest="${arg#*repos/}"
      repo="${rest%%/releases/*}"
      tag="${rest##*/releases/tags/}"
      repo="${repo//\//-}"
      url="/e2e/www/api/${repo}_tags_${tag}.json"
      ;;
    https://github.com/*/releases/download/*)
      path="${arg#https://github.com/}"
      url="/e2e/www/${path}"
      ;;
  esac
  prev="$arg"
done
if [[ -z "$url" ]]; then
  for arg in "$@"; do
    case "$arg" in
      http://127.0.0.1:*|http://localhost:*|http://\[::1\]:*)
        exec /usr/bin/curl "$@"
        ;;
    esac
  done
  printf 'ok\n'
  exit 0
fi
if [[ -n "$output" && "$output" != "-" ]]; then
  cp "$url" "$output" 2>/dev/null || { printf 'not found: %s\n' "$url" >&2; exit 22; }
  exit 0
fi
cat "$url" 2>/dev/null || { printf 'not found: %s\n' "$url" >&2; exit 22; }
CURL
chmod +x /e2e/bin/curl

# Package installation is out of scope here; the image already carries every
# dependency the lifecycle needs, so keep the rehearsal hermetic.
cat > /e2e/bin/apt-get <<'APT'
#!/bin/bash
exit 0
APT
chmod +x /e2e/bin/apt-get
export PATH="/e2e/bin:$PATH"

# --- install against real systemd -------------------------------------------
echo "--- install ---"
DOMAIN="meili.example.test" PORT=7700 INSTALL_DIR=/opt/meilisearch DATA_DIR=/var/lib/meilisearch \
LOG_DIR=/var/log/meilisearch SERVICE_NAME=meilisearch SERVICE_USER=meilisearch \
GITHUB_REPO=meilisearch/meilisearch BACKUP_DIR=/opt/meilisearch-backups \
BACKUP_KEEP_DAYS=30 BA_ENABLE_HTTPS=0 BA_SERVICE_ARGS="-f /dev/null" \
bash /repo/dist/install_meilisearch.sh install >/tmp/install.log 2>&1 || {
  cat /tmp/install.log
  fail MEILISEARCH_INSTALL_FAILED
}

for _ in $(seq 1 30); do
  [[ "$(systemctl is-active meilisearch 2>/dev/null || true)" == "active" ]] && break
  sleep 1
done
if [[ "$(systemctl is-active meilisearch 2>/dev/null || true)" != "active" ]]; then
  systemctl status meilisearch --no-pager || true
  journalctl -u meilisearch --no-pager | tail -20 || true
  cat /tmp/install.log
  fail MEILISEARCH_SERVICE_NOT_ACTIVE
fi
systemctl is-enabled meilisearch >/dev/null 2>&1 || fail MEILISEARCH_SERVICE_NOT_ENABLED
systemd-analyze verify /etc/systemd/system/meilisearch.service >/tmp/verify.log 2>&1 || {
  cat /tmp/verify.log
  fail MEILISEARCH_UNIT_INVALID
}
nginx -t >/tmp/nginx-t.log 2>&1 || { cat /tmp/nginx-t.log; fail NGINX_CONFIG_INVALID; }
bash /repo/dist/deploy.sh meilisearch status >/tmp/status.log 2>&1 || {
  cat /tmp/status.log
  fail MEILISEARCH_STATUS_FAILED
}

# --- backup / restore with the service actually running ---------------------
echo "--- backup / restore ---"
printf 'data-old\n' > /var/lib/meilisearch/restore-marker.txt
bash /repo/dist/install_meilisearch.sh backup >/tmp/backup.log 2>&1 || {
  cat /tmp/backup.log
  fail BACKUP_FAILED
}
archive="$(find /opt/meilisearch-backups -maxdepth 1 -type f -name 'meilisearch_*.tar.gz' \
  -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2-)"
[[ -n "$archive" ]] || fail BACKUP_ARCHIVE_MISSING
[[ -f "${archive}.sha256" ]] || fail BACKUP_SIDECAR_MISSING
printf 'data-mutated\n' > /var/lib/meilisearch/restore-marker.txt
MEILISEARCH_RESTORE_ARCHIVE="$archive" bash /repo/dist/install_meilisearch.sh restore >/tmp/restore.log 2>&1 || {
  cat /tmp/restore.log
  fail RESTORE_FAILED
}
[[ "$(cat /var/lib/meilisearch/restore-marker.txt)" == "data-old" ]] || fail RESTORE_DID_NOT_RESTORE_DATA
for _ in $(seq 1 30); do
  [[ "$(systemctl is-active meilisearch 2>/dev/null || true)" == "active" ]] && break
  sleep 1
done
[[ "$(systemctl is-active meilisearch 2>/dev/null || true)" == "active" ]] || fail SERVICE_DOWN_AFTER_RESTORE

# --- scheduled batch has to become a real systemd timer ---------------------
echo "--- schedule ---"
bash /repo/dist/deploy.sh schedule --enable --mode check-only --at 03:30 >/tmp/schedule.log 2>&1 || {
  cat /tmp/schedule.log
  fail SCHEDULE_ENABLE_FAILED
}
[[ -f /etc/systemd/system/deploy-scripts-batch.timer ]] || {
  cat /tmp/schedule.log
  fail SCHEDULE_TIMER_MISSING
}
systemctl is-enabled deploy-scripts-batch.timer >/dev/null 2>&1 || fail SCHEDULE_TIMER_NOT_ENABLED
systemctl is-active deploy-scripts-batch.timer >/dev/null 2>&1 || fail SCHEDULE_TIMER_NOT_ACTIVE
systemd-analyze verify /etc/systemd/system/deploy-scripts-batch.timer >/tmp/verify-timer.log 2>&1 || {
  cat /tmp/verify-timer.log
  fail SCHEDULE_TIMER_INVALID
}
bash /repo/dist/deploy.sh unschedule >/tmp/unschedule.log 2>&1 || {
  cat /tmp/unschedule.log
  fail UNSCHEDULE_FAILED
}
[[ ! -e /etc/systemd/system/deploy-scripts-batch.timer ]] || fail SCHEDULE_TIMER_LEFT_BEHIND

# --- the security audit sees the real host state ----------------------------
echo "--- doctor security ---"
bash /repo/dist/deploy.sh doctor security --json >/tmp/doctor.json 2>/tmp/doctor.err || {
  cat /tmp/doctor.err
  cat /tmp/doctor.json 2>/dev/null || true
  fail DOCTOR_SECURITY_FAILED
}
if command -v python3 >/dev/null 2>&1; then
  python3 - /tmp/doctor.json <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)

assert payload["schema_version"] == 1
checks = {record["check"]: record for record in payload["records"]}
assert "tls_renewal" in checks, "TLS renewal audit missing"
assert "tls_expiry" in checks, "TLS expiry audit missing"
assert checks["tls_expiry"]["state"] in {"ok", "not_checked"}, checks["tls_expiry"]
PY
else
  grep -Fq '"schema_version":1' /tmp/doctor.json || fail DOCTOR_JSON_INVALID
  grep -Fq '"check":"tls_renewal"' /tmp/doctor.json || fail DOCTOR_JSON_MISSING_TLS_RENEWAL
  grep -Fq '"check":"tls_expiry"' /tmp/doctor.json || fail DOCTOR_JSON_MISSING_TLS_EXPIRY
fi

# --- uninstall removes every managed artifact -------------------------------
echo "--- uninstall ---"
DEPLOY_ASSUME_YES=1 DEPLOY_DELETE_DATA=1 bash /repo/dist/deploy.sh meilisearch uninstall >/tmp/uninstall.log 2>&1 || {
  cat /tmp/uninstall.log
  fail UNINSTALL_FAILED
}
if systemctl is-active --quiet meilisearch; then
  systemctl status meilisearch --no-pager || true
  fail SERVICE_STILL_ACTIVE_AFTER_UNINSTALL
fi
[[ ! -e /etc/systemd/system/meilisearch.service ]] || fail UNIT_LEFT_BEHIND
[[ ! -e /opt/meilisearch ]] || fail INSTALL_DIR_LEFT_BEHIND
nginx -t >/tmp/nginx-t2.log 2>&1 || { cat /tmp/nginx-t2.log; fail NGINX_BROKEN_AFTER_UNINSTALL; }

# --- hand-written lifecycle: CPA Stack under real systemd -------------------
# The hand-written apps keep their own install flow, so they get their own
# rehearsal. Their binaries are shell-script fixtures that never exit, which is
# enough to prove systemd starts and stops the generated units.
echo "--- cpa-stack (hand-written lifecycle) ---"
mkdir -p /e2e/cpa-stage /e2e/cpamp-stage \
  /e2e/www/router-for-me/CLIProxyAPI/releases/download/v1.2.3 \
  /e2e/www/seakee/CPA-Manager-Plus/releases/download/v0.4.1
printf '#!/bin/sh\nexec sleep 2147483647\n' >/e2e/cpa-stage/cli-proxy-api
printf '#!/bin/sh\nexec sleep 2147483647\n' >/e2e/cpamp-stage/cpa-manager-plus
tar -czf /e2e/www/router-for-me/CLIProxyAPI/releases/download/v1.2.3/CLIProxyAPI_1.2.3_linux_amd64.tar.gz \
  -C /e2e/cpa-stage cli-proxy-api
tar -czf /e2e/www/seakee/CPA-Manager-Plus/releases/download/v0.4.1/cpa-manager-plus_v0.4.1_linux_amd64.tar.gz \
  -C /e2e/cpamp-stage cpa-manager-plus
(
  cd /e2e/www/router-for-me/CLIProxyAPI/releases/download/v1.2.3
  sha256sum CLIProxyAPI_1.2.3_linux_amd64.tar.gz >checksums.txt
)
(
  cd /e2e/www/seakee/CPA-Manager-Plus/releases/download/v0.4.1
  sha256sum cpa-manager-plus_v0.4.1_linux_amd64.tar.gz >checksums.txt
)
printf '{"tag_name":"v1.2.3","assets":[{"name":"CLIProxyAPI_1.2.3_linux_amd64.tar.gz","browser_download_url":"https://github.com/router-for-me/CLIProxyAPI/releases/download/v1.2.3/CLIProxyAPI_1.2.3_linux_amd64.tar.gz"}]}\n' \
  >/e2e/www/api/router-for-me-CLIProxyAPI_tags_v1.2.3.json
printf '{"tag_name":"v0.4.1","assets":[{"name":"cpa-manager-plus_v0.4.1_linux_amd64.tar.gz","browser_download_url":"https://github.com/seakee/CPA-Manager-Plus/releases/download/v0.4.1/cpa-manager-plus_v0.4.1_linux_amd64.tar.gz"}]}\n' \
  >/e2e/www/api/seakee-CPA-Manager-Plus_tags_v0.4.1.json

CPA_DOMAIN="api.cpa-e2e.test" CPAMP_DOMAIN="panel.cpa-e2e.test" ENABLE_HTTPS=false \
CPA_VERSION=v1.2.3 CPAMP_VERSION=v0.4.1 \
bash /repo/dist/install_cpa_stack.sh install >/tmp/cpa-install.log 2>&1 || {
  cat /tmp/cpa-install.log
  fail CPA_STACK_INSTALL_FAILED
}
for unit_name in cli-proxy-api cpa-manager-plus; do
  for _ in $(seq 1 30); do
    [[ "$(systemctl is-active "$unit_name" 2>/dev/null || true)" == "active" ]] && break
    sleep 1
  done
  [[ "$(systemctl is-active "$unit_name" 2>/dev/null || true)" == "active" ]] || {
    systemctl status "$unit_name" --no-pager || true
    journalctl -u "$unit_name" --no-pager | tail -20 || true
    cat /tmp/cpa-install.log
    fail "CPA_UNIT_NOT_ACTIVE_${unit_name}"
  }
  systemctl is-enabled "$unit_name" >/dev/null 2>&1 || fail "CPA_UNIT_NOT_ENABLED_${unit_name}"
  systemd-analyze verify "/etc/systemd/system/${unit_name}.service" >/tmp/verify-"$unit_name".log 2>&1 || {
    cat /tmp/verify-"$unit_name".log
    fail "CPA_UNIT_INVALID_${unit_name}"
  }
done
nginx -t >/tmp/nginx-cpa.log 2>&1 || { cat /tmp/nginx-cpa.log; fail CPA_NGINX_CONFIG_INVALID; }

printf 'marker-old\n' >/etc/cli-proxy-api/restore-marker.txt
bash /repo/dist/install_cpa_stack.sh backup >/tmp/cpa-backup.log 2>&1 || {
  cat /tmp/cpa-backup.log
  fail CPA_BACKUP_FAILED
}
cpa_archive="$(find /opt/cpa-stack-backups -maxdepth 1 -type f -name 'cpa-stack-*.tar.gz' \
  -printf '%T@ %p\n' 2>/dev/null | sort -nr | head -n 1 | cut -d' ' -f2-)"
[[ -n "$cpa_archive" ]] || fail CPA_BACKUP_ARCHIVE_MISSING
printf 'marker-mutated\n' >/etc/cli-proxy-api/restore-marker.txt
CPA_STACK_RESTORE_ARCHIVE="$cpa_archive" bash /repo/dist/install_cpa_stack.sh restore >/tmp/cpa-restore.log 2>&1 || {
  cat /tmp/cpa-restore.log
  fail CPA_RESTORE_FAILED
}
[[ "$(cat /etc/cli-proxy-api/restore-marker.txt)" == "marker-old" ]] || fail CPA_RESTORE_DID_NOT_RESTORE_DATA
[[ "$(systemctl is-active cli-proxy-api 2>/dev/null || true)" == "active" ]] || fail CPA_SERVICE_DOWN_AFTER_RESTORE

DEPLOY_ASSUME_YES=1 DEPLOY_DELETE_DATA=1 bash /repo/dist/install_cpa_stack.sh uninstall >/tmp/cpa-uninstall.log 2>&1 || {
  cat /tmp/cpa-uninstall.log
  fail CPA_UNINSTALL_FAILED
}
for unit_name in cli-proxy-api cpa-manager-plus; do
  if systemctl is-active --quiet "$unit_name"; then
    fail "CPA_SERVICE_STILL_ACTIVE_${unit_name}"
  fi
  [[ ! -e "/etc/systemd/system/${unit_name}.service" ]] || fail "CPA_UNIT_LEFT_BEHIND_${unit_name}"
done
[[ ! -e /opt/cli-proxy-api && ! -e /opt/cpa-manager-plus ]] || fail CPA_INSTALL_DIR_LEFT_BEHIND
nginx -t >/tmp/nginx-cpa2.log 2>&1 || { cat /tmp/nginx-cpa2.log; fail CPA_NGINX_BROKEN_AFTER_UNINSTALL; }

echo SYSTEMD_E2E_OK
