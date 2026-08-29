# shellcheck shell=bash
# shellcheck source=../verify.sh
# Verify checks for the newapi app (apps/newapi.sh, impl/install_newapi.sh).
#
# New API is migrated onto the shared binary-app lifecycle (lib/binary_app.sh);
# the framework-level guarantees (install rollback, update rollback, stop
# failure handling, health gating, backup integrity) are verified by the
# binary-app checks.  These checks cover what remains New API-specific:
# the private env file with the generated SESSION_SECRET, the SQLite WAL
# backup hook, the credential warning in the install summary, and the
# historical backup archive prefix.

check_newapi_secret_uses_private_env_file() {
  if grep -R -n 'Environment="SESSION_SECRET=' impl/install_newapi.sh 2>/dev/null; then
    echo "NewAPI must not embed SESSION_SECRET directly in a world-readable systemd unit." >&2
    return 1
  fi
  awk '
      /ba_write_config\(\)/ { in_func=1; saw_atomic=0; saw_secret=0; next }
      in_func && /atomic_write_file "\$env_file" 600 root:root/ { saw_atomic=1 }
      in_func && /SESSION_SECRET=\$\{session_secret\}/ { saw_secret=1 }
      in_func && /^}/ {
        if (!(saw_atomic && saw_secret)) {
          printf "%s NewAPI runtime secrets must be written through a private environment file\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
      /EnvironmentFile=\$\{ENV_FILE\}/ { saw_envfile=1 }
      /error "\$\(t app\.newapi\.error\.env_file "\$env_file"\)"/ { saw_error=1 }
      /success "\$\(t app\.newapi\.success\.env_file "\$env_file"\)"/ { saw_success=1 }
      END {
        if (!(saw_envfile && saw_error && saw_success)) {
          printf "%s NewAPI must wire the private environment file through the systemd unit\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_newapi.sh
}

check_newapi_backup_wal_hook_is_best_effort() {
  awk '
      /ba_backup_hook\(\)/ { in_hook=1; saw_wal=0; saw_integrity=0; saw_warn=0; next }
      in_hook && /PRAGMA wal_checkpoint\(TRUNCATE\);/ { saw_wal=1 }
      in_hook && /PRAGMA integrity_check;/ { saw_integrity=1 }
      in_hook && /warn "\$\(t app\.newapi\.backup\.log\.integrity_warn/ { saw_warn=1 }
      in_hook && /return 0/ { saw_return=1; in_hook=0 }
      END {
        if (!(saw_wal && saw_integrity && saw_warn && saw_return)) {
          printf "%s NewAPI backup hook must quiesce SQLite WAL, warn on integrity failures, and stay best-effort\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_newapi.sh
}

check_newapi_summary_warns_about_default_credentials() {
  if grep -R -nE 'root[[:space:]]*/[[:space:]]*123456' \
      apps/newapi.sh impl/install_newapi.sh 2>/dev/null; then
    echo "NewAPI must not print the publicly known default credentials in the install summary." >&2
    return 1
  fi
  grep -Fq 'app.newapi.summary.credential_warning' apps/newapi.sh \
    && grep -Fq 'app.newapi.summary.credential_hint' apps/newapi.sh \
    && grep -Fq 'ba_summary_extra' impl/install_newapi.sh \
    || {
      echo "NewAPI install summary must warn that the default admin credentials are publicly known." >&2
      return 1
    }
}

check_newapi_status_backup_projection() {
  local output tmp_dir
  tmp_dir="$(mktemp -d)"
  # Present a trusted config (root, mode 600) via the stat stub so the run is
  # platform-independent; the shared projection must adopt the configured
  # BACKUP_DIR only after the root/600/400 trust gate passes.
  cat > "${tmp_dir}/stat" <<'STUB'
#!/usr/bin/env bash
case "${2:-}" in
  %U) echo root ;;
  %a) echo 600 ;;
  *) /usr/bin/stat "$@" ;;
esac
STUB
  chmod +x "${tmp_dir}/stat"
  output="$(PATH="${tmp_dir}:$PATH" APP_CONF_FILE="${tmp_dir}/new-api.conf" "$BASH_BIN" -c '
    set -euo pipefail
    tmp_dir="$(mktemp -d)"
    conf_file="${APP_CONF_FILE}"
    backup_dir="${tmp_dir}/backups"
    mkdir -p "$backup_dir"
    printf "BACKUP_DIR=\\\"%s\\\"\\n" "$backup_dir" > "$conf_file"
    touch -d "2026-08-20 12:34:56 UTC" "$backup_dir/new-api_20260820123456.tar.gz"
    source lib/core.sh
    APP_ID=newapi
    APP_NAME="New API"
    app_conf_file() { printf "%s" "$APP_CONF_FILE"; }
    source impl/install_newapi.sh
    bapp_status_backup_json
    rm -rf "$tmp_dir"
  ')"
  local status=$?
  rm -rf "$tmp_dir"
  [[ "$status" -eq 0 ]] || return 1
  python -c 'import json,sys; x=json.loads(sys.argv[1]); assert x["state"] == "available"; assert x["path"].endswith("new-api_20260820123456.tar.gz"); assert x["last_success_at"]' "$output"
}
