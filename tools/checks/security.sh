# shellcheck shell=bash
# shellcheck source=../verify.sh
# Behavior-level security baseline checks for default listeners and opt-in guards.

check_security_defaults_and_public_bind_guard() {
  local app output
  local -a binary_apps=(alist beszel filebrowser gitea gotify meilisearch navidrome ntfy newapi)

  for app in "${binary_apps[@]}"; do
    output="$($BASH_BIN -c '
      set -euo pipefail
      source lib/core.sh
      source "apps/$1.sh"
      printf "%s|%s\n" "${BA_BIND_ADDR:-}" "${BA_FIREWALL:-}"
    ' _ "$app")" || {
      echo "Could not load ${app} while checking security defaults." >&2
      return 1
    }
    [[ "$output" == "127.0.0.1|0" ]] || {
      echo "${app} must default to loopback with firewall automation disabled: ${output}" >&2
      return 1
    }
  done

  output="$($BASH_BIN -c '
    set -euo pipefail
    source lib/core.sh
    source apps/frps.sh
    printf "%s|%s\n" "${BA_BIND_ADDR:-}" "${BA_FIREWALL:-}"
  ')"
  [[ "$output" == "0.0.0.0|1" ]] || {
    echo "frps must retain its documented public TCP listener exception: ${output}" >&2
    return 1
  }

  output="$($BASH_BIN -c '
    set -euo pipefail
    source lib/core.sh
    source apps/tickflow.sh
    printf "%s\n" "${TICKFLOW_BIND_ADDR:-}"
  ')"
  [[ "$output" == "127.0.0.1" ]] || {
    echo "TickFlow must default to a loopback container mapping: ${output}" >&2
    return 1
  }

  output="$($BASH_BIN -c '
    set -euo pipefail
    source lib/core.sh
    source apps/sub2api.sh
    printf "%s\n" "${SUB2API_BIND_ADDR:-}"
  ')"
  [[ "$output" == "127.0.0.1" ]] || {
    echo "Sub2API must default to a loopback backend listener: ${output}" >&2
    return 1
  }

  if DEPLOY_FAIL_ON_INSECURE_PUBLIC_BIND=1 "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    app_enforce_secure_public_bind 0.0.0.0 0 "test-app"
  ' >/dev/null 2>&1; then
    echo "The strict public-bind guard accepted plain HTTP on 0.0.0.0." >&2
    return 1
  fi

  if ! DEPLOY_FAIL_ON_INSECURE_PUBLIC_BIND=1 "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    app_enforce_secure_public_bind 0.0.0.0 true "test-app"
    app_enforce_secure_public_bind :: 1 "test-app"
  ' >/dev/null 2>&1; then
    echo "The strict public-bind guard rejected a TLS-enabled wildcard listener." >&2
    return 1
  fi

  if DEPLOY_FAIL_ON_INSECURE_PUBLIC_BIND=1 BA_BIND_ADDR=0.0.0.0 BA_ENABLE_HTTPS=0 "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    source apps/newapi.sh
  ' >/dev/null 2>&1; then
    echo "The binary-app lifecycle did not enforce the strict public-bind guard." >&2
    return 1
  fi

  if DEPLOY_FAIL_ON_INSECURE_PUBLIC_BIND=1 TICKFLOW_BIND_ADDR=0.0.0.0 "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    source apps/tickflow.sh
    _validate_config_values
  ' >/dev/null 2>&1; then
    echo "TickFlow did not enforce the strict public-bind guard." >&2
    return 1
  fi

  local tmp_dir env_file password
  tmp_dir="$($BASH_BIN -c 'mktemp -d')"
  env_file="${tmp_dir}/tickflow.env"
  if ! TICKFLOW_INSTALL_DIR="${tmp_dir}/install" \
    TICKFLOW_DATA_DIR="${tmp_dir}/data" \
    TICKFLOW_LOG_DIR="${tmp_dir}/logs" \
    TICKFLOW_ENV_FILE="$env_file" \
    TICKFLOW_TIERS_FILE="${tmp_dir}/tiers.yaml" \
    "$BASH_BIN" -c '
      set -euo pipefail
      source lib/core.sh
      source apps/tickflow.sh
      _write_env_file
    ' >/dev/null 2>&1; then
    rm -rf "$tmp_dir"
    echo "TickFlow failed to generate its default environment." >&2
    return 1
  fi
  password="$(sed -n 's/^AUTH_PASSWORD=//p' "$env_file")"
  rm -rf "$tmp_dir"
  [[ -n "$password" && ${#password} -ge 6 ]] || {
    echo "TickFlow generated an empty or too-short panel password." >&2
    return 1
  }

  output="$(NO_COLOR=1 "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    source apps/newapi.sh
    ba_summary_extra
  ' 2>&1)"
  [[ "$output" != *"123456"* && "$output" != *"root /"* ]] || {
    echo "New API install summary contains a known credential pattern." >&2
    return 1
  }
}


check_security_audit_contract() {
  local temp_root fixture_output json_file status
  temp_root="$(mktemp -d)"
  mkdir -p "$temp_root/root" "$temp_root/tmp" "$temp_root/etc/cron.d" "$temp_root/usr/local/bin"
  printf '%s\n' 'VALUE_ONE' > "$temp_root/root/.vaultwarden-admin-token.legacy"
  printf '%s\n' 'PG_DSN=postgresql://user:VALUE_TWO@localhost:5432/db' > "$temp_root/usr/local/bin/sub2api-backup"
  printf '%s\n' 'SUB2API_BIND_ADDR=0.0.0.0' > "$temp_root/etc/sub2api-deploy.conf"
  printf '%s\n' '30 3 * * * root /usr/local/bin/sub2api-backup' > "$temp_root/etc/cron.d/legacy-job"
  printf '%s\n' '30 3 * * * /usr/local/bin/sub2api-backup' > "$temp_root/root-crontab"

  set +e
  fixture_output="$(DEPLOY_SECURITY_AUDIT_ROOT="$temp_root" \
    DEPLOY_SECURITY_AUDIT_ROOT_CRONTAB_FILE="$temp_root/root-crontab" \
    "$BASH_BIN" deploy.sh doctor security --json 2>&1)"
  status=$?
  set -e
  rm -rf "$temp_root"

  [[ "$status" -eq 0 ]] || {
    echo "Security audit fixture unexpectedly failed: ${fixture_output}" >&2
    return 1
  }
  [[ "$fixture_output" != *VALUE_ONE* && "$fixture_output" != *VALUE_TWO* ]] || {
    echo "Security audit output exposed fixture credential content." >&2
    return 1
  }
  json_file="$(mktemp)"
  printf '%s\n' "$fixture_output" > "$json_file"
  python - "$json_file" <<'PY'
import json
import sys

with open(sys.argv[1], encoding="utf-8") as handle:
    payload = json.load(handle)

assert payload["schema_version"] == 1
assert payload["summary"]["warning"] >= 3
checks = {record["check"]: record for record in payload["records"]}
assert checks["vaultwarden_legacy_token"]["state"] == "warning"
assert checks["sub2api_plaintext_dsn"]["state"] == "warning"
assert checks["public_listener"]["state"] == "warning"
assert checks["legacy_root_crontab"]["state"] == "warning"
assert checks["legacy_cron_file"]["state"] == "warning"
for record in payload["records"]:
    assert "VALUE_ONE" not in record["message"]
    assert "VALUE_TWO" not in record["message"]
PY
  status=$?
  rm -f "$json_file"
  return "$status"
}
