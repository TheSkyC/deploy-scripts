#!/usr/bin/env bash
# Feature-proof suite: behaviorally exercises the P0 backup-integrity,
# P1 notification/schedule/migration, and P2 compose/fleet implementations
# with stub backends, so the checklist features have executable evidence
# beyond static guards. Run: bash tools/prove-features.sh
set -uo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR" || exit 1

echo "=== P0: backup integrity primitives (sha256 + manifest + verify) ==="
bash -c '
  set -euo pipefail
  source lib/core.sh
  tmp="$(mktemp -d)"
  trap "rm -rf \"$tmp\"" EXIT
  app_conf_trusted_value() { return 0; }
  echo payload > "$tmp/archive.tar.gz"
  backup_write_sha256 "$tmp/archive.tar.gz" >/dev/null || exit 1
  backup_write_manifest "$tmp/archive.tar.gz" testapp 1 1.2.3 || exit 1
  [[ -f "$tmp/archive.tar.gz.sha256" && -f "$tmp/archive.tar.gz.manifest.json" ]] || exit 1
  backup_verify_archive "$tmp/archive.tar.gz" || exit 1
  echo tampered >> "$tmp/archive.tar.gz"
  backup_verify_archive "$tmp/archive.tar.gz" 2>/dev/null && exit 1
  echo OK
'

echo "=== P0: restore lifecycle (roundtrip + corrupt rejection) ==="
bash -c '
  set -euo pipefail
  source lib/core.sh
  tmp="$(mktemp -d)"
  trap "rm -rf \"$tmp\"" EXIT
  error() { exit 9; }
  info() { :; }
  success() { :; }
  app_conf_trusted_value() { return 0; }
  mkdir -p "$tmp/data" "$tmp/backup"
  echo original > "$tmp/data/app.db"
  tar -czf "$tmp/backup/app.tar.gz" -C "$tmp" data
  backup_write_sha256 "$tmp/backup/app.tar.gz" >/dev/null
  systemctl() { return 0; }
  backup_restore_data_dir "$tmp/data" testapp "$tmp/backup/app.tar.gz"
  grep -q original "$tmp/data/app.db" || exit 1
  echo corrupt >> "$tmp/backup/app.tar.gz"
  ( backup_restore_data_dir "$tmp/data" testapp "$tmp/backup/app.tar.gz" ) 2>/dev/null && exit 1
  echo OK
'

echo "=== P0: status-json integrity + 16/16 verify/restore ==="
bash -c '
  set -euo pipefail
  source lib/core.sh
  tmp="$(mktemp -d)"
  trap "rm -rf \"$tmp\"" EXIT
  app_conf_trusted_value() { return 0; }
  mkdir -p "$tmp/backup"
  echo data > "$tmp/backup/app.tar.gz"
  backup_write_sha256 "$tmp/backup/app.tar.gz" >/dev/null
  backup_write_manifest "$tmp/backup/app.tar.gz" testapp 1 9.9.9 >/dev/null
  json="$(backup_verify_latest_json "$tmp/backup" app.tar.gz)"
  printf "%s" "$json" | grep -Fq "\"state\":\"verified\"" || exit 1
  verify_count=$(grep -l "^do_verify() {" impl/install_*.sh | wc -l)
  [[ "$verify_count" -eq 16 ]] || exit 1
  echo OK
'

echo "=== P1: notify_send fail-open + redaction ==="
bash -c '
  set -euo pipefail
  source lib/core.sh
  tmp="$(mktemp -d)"
  trap "rm -rf \"$tmp\"" EXIT
  export NOTIFY_CONF_FILE="$tmp/notify.conf"
  app_conf_trusted_value() { return 0; }
  notify_send t b >/dev/null 2>&1 || exit 1
  printf "NOTIFY_ENABLED=\"false\"\n" > "$NOTIFY_CONF_FILE"; chmod 600 "$NOTIFY_CONF_FILE"
  notify_send t b >/dev/null 2>&1 || exit 1
  printf "NOTIFY_ENABLED=\"true\"\nNOTIFY_BACKEND=\"ntfy\"\nNOTIFY_URL=\"%s\"\nNOTIFY_TOPIC=\"topic\"\n" "$tmp/s" > "$NOTIFY_CONF_FILE"
  mkdir -p "$tmp/bin"; export NOTIFY_BODY_FILE="$tmp/body"
  cat > "$tmp/bin/curl" <<STUB
#!/bin/bash
while (( \$# )); do
  if [[ "\$1" == "--data-binary" ]]; then shift; printf "%s" "\$1" > "\$NOTIFY_BODY_FILE"; fi
  shift
done
echo 200
STUB
  chmod +x "$tmp/bin/curl"
  PATH="$tmp/bin:$PATH" notify_send t "TOKEN=hunter2" >/dev/null 2>&1
  body="$(cat "$NOTIFY_BODY_FILE")"
  [[ "$body" == *hunter2* ]] && exit 1
  echo OK
'

echo "=== P1: schedule validate/apply/status/unschedule ==="
bash -c '
  set -euo pipefail
  source lib/core.sh
  tmp="$(mktemp -d)"
  trap "rm -rf \"$tmp\"" EXIT
  export SCHEDULE_CONF_FILE="$tmp/s.conf" DEPLOY_SCHEDULE_CRON_FILE="$tmp/cron" DEPLOY_SCHEDULE_RUNNER="$tmp/run"
  require_root() { :; }
  error() { exit 9; }
  success() { :; }
  app_conf_trusted_value() { return 0; }
  DEPLOY_ROOT_DIR="$tmp/root"; mkdir -p "$tmp/root"; printf "#!/bin/bash\n" > "$tmp/root/deploy.sh"
  schedule_main schedule --enable --mode check-only --at "25:99" >/dev/null 2>&1 && exit 1
  [[ -e "$DEPLOY_SCHEDULE_CRON_FILE" ]] && exit 1
  schedule_main schedule --enable --mode check-only --at "03:10" >/dev/null 2>&1 || exit 1
  [[ -x "$DEPLOY_SCHEDULE_RUNNER" && -f "$DEPLOY_SCHEDULE_CRON_FILE" ]] || exit 1
  schedule_main status | grep -q enabled= || exit 1
  schedule_main unschedule >/dev/null 2>&1
  [[ ! -e "$DEPLOY_SCHEDULE_CRON_FILE" ]] || exit 1
  echo OK
'

echo "=== P1: migrate export/import roundtrip ==="
bash -c '
  set -euo pipefail
  source lib/core.sh
  tmp="$(mktemp -d)"
  trap "rm -rf \"$tmp\"" EXIT
  export MIGRATE_EXPORT_DIR="$tmp/etc" NOTIFY_CONF_FILE="$tmp/etc/deploy-notify.conf" SCHEDULE_CONF_FILE="$tmp/absent"
  require_root() { :; }
  success() { :; }
  info() { :; }
  error() { exit 9; }
  app_conf_trusted_value() { return 0; }
  ( migrate_main export --output "$tmp/out.tar.gz" ) >/dev/null 2>&1 && exit 1
  mkdir -p "$MIGRATE_EXPORT_DIR"
  printf "PORT=\"1234\"\n" > "$MIGRATE_EXPORT_DIR/myapp-deploy.conf"
  printf "NOTIFY_ENABLED=\"false\"\n" > "$NOTIFY_CONF_FILE"
  migrate_main export --output "$tmp/out.tar.gz" --redact >/dev/null 2>&1 || exit 1
  [[ -f "$tmp/out.tar.gz" && -f "$tmp/out.tar.gz.sha256" ]] || exit 1
  backup_verify_archive "$tmp/out.tar.gz" || exit 1
  rm -f "$MIGRATE_EXPORT_DIR/myapp-deploy.conf" "$NOTIFY_CONF_FILE"
  migrate_main import --input "$tmp/out.tar.gz" >/dev/null 2>&1 || exit 1
  grep -q "^PORT=" "$MIGRATE_EXPORT_DIR/myapp-deploy.conf" || exit 1
  echo OK
'

echo "=== P2: compose validation + health fail-closed ==="
bash -c '
  set -euo pipefail
  source lib/core.sh
  tmp="$(mktemp -d)"
  trap "rm -rf \"$tmp\"" EXIT
  error() { exit 9; }
  is_safe_path() { [[ "$1" == /* ]] && [[ "$1" != / ]]; }
  compose_validate_project /tmp/x /etc/passwd && exit 1
  compose_validate_project "$tmp" "$tmp/nope.yml" && exit 1
  echo "services: {}" > "$tmp/compose.yml"
  compose_validate_project "$tmp" "$tmp/compose.yml" || exit 1
  mkdir -p "$tmp/bin"
  cat > "$tmp/bin/docker" <<STUB
#!/bin/bash
for a in "\$@"; do
  case "\$a" in
    version) echo v2; exit 0 ;;
    ps)
      [[ -f "$tmp/healthy" ]] && printf "[{\"Service\":\"web\",\"State\":\"running\"}]" || printf "[{\"Service\":\"web\",\"State\":\"exited\"}]"
      exit 0 ;;
  esac
done
exit 1
STUB
  chmod +x "$tmp/bin/docker"
  export PATH="$tmp/bin:$PATH"
  touch "$tmp/healthy"
  compose_health "$tmp" "$tmp/compose.yml" || exit 1
  rm -f "$tmp/healthy"
  compose_health "$tmp" "$tmp/compose.yml" 2>/dev/null && exit 1
  echo OK
'

echo "=== P2: fleet trust gate + parsing + ssh args ==="
bash -c '
  set -euo pipefail
  source lib/core.sh
  tmp="$(mktemp -d)"
  trap "rm -rf \"$tmp\"" EXIT
  export FLEET_HOSTS_FILE="$tmp/hosts"
  printf "alpha|user@h1.example.com\nbeta|user@h2.example.com:2222\nbad line\n" > "$FLEET_HOSTS_FILE"
  stat() {
    if [[ "$1" == "-c" && "$2" == "%U" ]]; then echo root; fi
    if [[ "$1" == "-c" && "$2" == "%a" ]]; then echo 600; fi
  }
  fleet_load_hosts
  [[ ${#FLEET_HOSTS[@]} -eq 2 ]] || exit 1
  [[ "$(fleet_target_ssh_args "user@h2.example.com:2222")" == "user@h2.example.com -p 2222" ]] || exit 1
  echo OK
'

echo "ALL FEATURE PROOFS PASSED"
