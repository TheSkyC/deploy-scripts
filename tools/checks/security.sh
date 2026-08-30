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
