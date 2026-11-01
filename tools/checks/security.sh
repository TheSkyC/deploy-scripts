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


check_security_bind_keys_follow_registry() {
  local key registry_keys found
  registry_keys="$("$BASH_BIN" -c 'source lib/core.sh; printf "%s\n" "${DEPLOY_APP_BIND_CONFIG_KEYS[@]}"')"
  while IFS= read -r key; do
    [[ -n "$key" ]] || continue
    found=0
    while IFS= read -r registry_key; do
      [[ "$registry_key" == "$key" ]] && found=1
    done <<<"$registry_keys"
    if (( found == 0 )); then
      printf 'Implementation bind key %s must be added to DEPLOY_APP_BIND_CONFIG_KEYS.\n' "$key" >&2
      return 1
    fi
  done < <(grep -hE '^[[:space:]]*[A-Z0-9_]+_BIND_ADDR=' impl/*.sh 2>/dev/null \
    | sed -E 's/^[[:space:]]*([A-Z0-9_]+)_BIND_ADDR=.*/\1_BIND_ADDR/' \
    | LC_ALL=C sort -u)
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

# A valid certificate is only safe if something renews it. The security audit
# must report TLS sites whose certificate is covered by neither the certbot
# timer, the legacy shared entry, nor a per-app /etc/cron.d entry.
check_security_doctor_tls_renewal_audit() {
  "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    DEPLOY_SECURITY_AUDIT_ROOT="$tmp"
    sites="$tmp/etc/nginx/sites-available"
    cron_dir="$tmp/etc/cron.d"
    mkdir -p "$sites" "$cron_dir"
    printf "%s\n" "server { ssl_certificate /etc/letsencrypt/live/api.example.com/fullchain.pem; }" >"$sites/cpa-stack"
    printf "%s\n" "server { listen 80; }" >"$sites/plain"
    security_doctor_certbot_timer_active() { return 1; }

    # No schedule at all: the uncovered certificate must be reported.
    security_doctor_reset
    security_doctor_check_tls_renewal
    [[ "${SECURITY_DOCTOR_STATES[0]}" == warning ]] || { echo "uncovered TLS certificate was not reported" >&2; exit 1; }
    [[ "${SECURITY_DOCTOR_MESSAGES[0]}" == *api.example.com* ]] || { echo "uncovered record must name the certificate" >&2; exit 2; }
    [[ "${SECURITY_DOCTOR_PATHS[0]}" == *cpa-stack ]] || { echo "uncovered record must point at the site file" >&2; exit 3; }

    # A per-app entry naming the certificate covers it.
    printf "%s\n" "30 2 * * * root certbot renew --quiet --cert-name \"api.example.com\"" >"$cron_dir/certbot-renew-cpa-stack"
    security_doctor_reset
    security_doctor_check_tls_renewal
    [[ "${SECURITY_DOCTOR_STATES[0]}" == ok ]] || { echo "scoped per-app renewal was not accepted" >&2; exit 4; }

    # A per-app entry for another certificate does not cover this one.
    printf "%s\n" "30 2 * * * root certbot renew --quiet --cert-name \"other.example.com\"" >"$cron_dir/certbot-renew-cpa-stack"
    security_doctor_reset
    security_doctor_check_tls_renewal
    [[ "${SECURITY_DOCTOR_STATES[0]}" == warning ]] || { echo "renewal for a different certificate was accepted" >&2; exit 5; }

    # Single quotes and the --cert-name=NAME form name the certificate too.
    printf "%s\n" "30 2 * * * root certbot renew --quiet --cert-name '\''api.example.com'\''" >"$cron_dir/certbot-renew-cpa-stack"
    security_doctor_reset
    security_doctor_check_tls_renewal
    [[ "${SECURITY_DOCTOR_STATES[0]}" == ok ]] || { echo "single-quoted --cert-name was not parsed" >&2; exit 8; }

    printf "%s\n" "30 2 * * * root certbot renew --quiet --cert-name=api.example.com" >"$cron_dir/certbot-renew-cpa-stack"
    security_doctor_reset
    security_doctor_check_tls_renewal
    [[ "${SECURITY_DOCTOR_STATES[0]}" == ok ]] || { echo "--cert-name=VALUE was not parsed" >&2; exit 9; }

    # The legacy shared entry renews everything.
    rm -f "$cron_dir/certbot-renew-cpa-stack"
    printf "%s\n" "30 2 * * * root certbot renew --quiet" >"$cron_dir/certbot-renew"
    security_doctor_reset
    security_doctor_check_tls_renewal
    [[ "${SECURITY_DOCTOR_STATES[0]}" == ok ]] || { echo "shared renewal entry was not accepted" >&2; exit 6; }

    # The system timer on its own is enough.
    rm -f "$cron_dir/certbot-renew"
    security_doctor_certbot_timer_active() { return 0; }
    security_doctor_reset
    security_doctor_check_tls_renewal
    [[ "${SECURITY_DOCTOR_STATES[0]}" == ok ]] || { echo "certbot timer was not accepted as a renewal schedule" >&2; exit 7; }
    echo ok
  ' | grep -q ok
}

# Coverage alone is not enough: a certificate that lapses on Friday is an outage
# even when a renewal job is scheduled. Expiry therefore gets its own record,
# and an unreadable certificate must never look either healthy or expired.
check_security_doctor_tls_expiry_audit() {
  "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    tmp="$(mktemp -d)"
    trap "rm -rf \"$tmp\"" EXIT
    DEPLOY_SECURITY_AUDIT_ROOT="$tmp"
    sites="$tmp/etc/nginx/sites-available"
    live="$tmp/etc/letsencrypt/live"
    mkdir -p "$sites"
    printf "%s\n" \
      "server {" \
      "  ssl_certificate /etc/letsencrypt/live/healthy.example.com/fullchain.pem;" \
      "  ssl_certificate /etc/letsencrypt/live/soon.example.com/fullchain.pem;" \
      "  ssl_certificate /etc/letsencrypt/live/critical.example.com/fullchain.pem;" \
      "  ssl_certificate /etc/letsencrypt/live/missing.example.com/fullchain.pem;" \
      "}" >"$sites/all"

    state_of() {
      local needle="$1" index
      for index in "${!SECURITY_DOCTOR_CHECKS[@]}"; do
        [[ "${SECURITY_DOCTOR_CHECKS[$index]}" == tls_expiry ]] || continue
        case "${SECURITY_DOCTOR_MESSAGES[$index]}" in
          *"$needle"*) printf "%s" "${SECURITY_DOCTOR_STATES[$index]}" ; return 0 ;;
        esac
      done
      return 1
    }

    if ! command -v openssl >/dev/null 2>&1; then
      # Without openssl the audit must say so instead of reporting healthy.
      security_doctor_reset
      security_doctor_check_tls_expiry
      [[ "${SECURITY_DOCTOR_STATES[0]}" == not_checked ]] || { echo "missing openssl must be not_checked" >&2; exit 1; }
      echo ok
      exit 0
    fi

    make_cert() {
      local name="$1" days="$2"
      mkdir -p "$live/$name"
      openssl req -x509 -newkey rsa:2048 -nodes -sha256 \
        -keyout "$live/$name/privkey.pem" -out "$live/$name/cert.pem" \
        -days "$days" -subj "/CN=$name" >/dev/null 2>&1
    }
    make_cert healthy.example.com 60
    make_cert soon.example.com 10
    make_cert critical.example.com 2

    security_doctor_reset
    security_doctor_check_tls_expiry
    [[ "$(state_of healthy.example.com)" == ok ]] || { echo "healthy certificate must be ok" >&2; exit 2; }
    [[ "$(state_of soon.example.com)" == warning ]] || { echo "certificate inside the warning window must warn" >&2; exit 3; }
    [[ "$(state_of critical.example.com)" == error ]] || { echo "certificate inside the error window must fail" >&2; exit 4; }
    [[ "$(state_of missing.example.com)" == not_checked ]] || { echo "unreadable certificate must be not_checked" >&2; exit 5; }

    # The thresholds are operator-tunable.
    security_doctor_reset
    DEPLOY_SECURITY_TLS_WARN_DAYS=5 security_doctor_check_tls_expiry
    [[ "$(state_of soon.example.com)" == ok ]] || { echo "warning window override was ignored" >&2; exit 6; }

    # An expired certificate is an error even though the file parses.
    app_certificate_days_remaining() { printf "%s\n" "-1" ; }
    security_doctor_reset
    security_doctor_check_tls_expiry
    [[ "$(state_of healthy.example.com)" == error ]] || { echo "expired certificate must be an error" >&2; exit 7; }
    echo ok
  ' | grep -q ok
}
