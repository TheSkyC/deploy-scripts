# shellcheck shell=bash
# shellcheck source=../verify.sh
# Verify checks for the Gotify app (apps/gotify.sh).

check_gotify_uses_shared_binary_lifecycle() {
  local file
  # shellcheck disable=SC2043 # Fixed target; retain the shared per-file guard body.
  for file in impl/install_gotify.sh; do
    grep -Fq 'bapp_install' "$file" \
      && grep -Fq 'bapp_update' "$file" \
      && grep -Fq 'bapp_backup' "$file" \
      && grep -Fq 'bapp_uninstall' "$file" \
      && grep -Fq 'bapp_status' "$file" \
      && grep -Fq 'bapp_preflight' "$file" \
      && grep -Fq 'bapp_validate_cfg' "$file" \
      && grep -Fq 'binary_app_bootstrap' "$file" \
      || {
        echo "${file} gotify must delegate lifecycle to lib/binary_app.sh and call binary_app_bootstrap" >&2
        return 1
      }
  done
}

check_gotify_release_asset_mapping() {
  local file
  # shellcheck disable=SC2043 # Fixed target; retain the shared per-file guard body.
  for file in impl/install_gotify.sh; do
    grep -Fq 'GITHUB_REPO="${GITHUB_REPO:-gotify/server}"' "$file" \
      && grep -Fq 'BA_BIN_NAME="gotify"' "$file" \
      && grep -Fq 'BA_ARCHIVE_TYPE="zip"' "$file" \
      && grep -Fq 'BA_APT_PACKAGES="unzip"' "$file" \
      && grep -Fq "printf 'gotify-linux-%s.zip" "$file" \
      && grep -Fq 'BA_USE_ENV_FILE=1' "$file" \
      && grep -Fq 'BA_HEALTH_URL="http://127.0.0.1:${PORT}/"' "$file" \
      || {
        echo "${file} must map the verified Gotify release zip and GOTIFY_* env configuration." >&2
        return 1
      }
  done
}

check_gotify_env_is_managed_atomically() {
  local file
  # shellcheck disable=SC2043 # Fixed target; retain the shared per-file guard body.
  for file in impl/install_gotify.sh; do
    grep -Fq 'atomic_write_file "$env_file" 600 root:root' "$file" \
      && grep -Fq "grep -E '^GOTIFY_DEFAULTUSER_PASS='" "$file" \
      && grep -Fq "tr -dc 'A-Za-z0-9' </dev/urandom | head -c 40" "$file" \
      && grep -Fq 'GOTIFY_DEFAULTUSER_NAME=admin' "$file" \
      && grep -Fq 'GOTIFY_DEFAULTUSER_PASS=${admin_password}' "$file" \
      && grep -Fq 'GOTIFY_SERVER_PORT=${PORT}' "$file" \
      && grep -Fq 'error "$(t app.gotify.error.env_write "$env_file")"' "$file" \
      && grep -Fq 'success "$(t app.gotify.success.env_written "$env_file")"' "$file" \
      || {
        echo "${file} gotify env must be written atomically and report failures." >&2
        return 1
      }
  done
}
