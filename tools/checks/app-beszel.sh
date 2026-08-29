# shellcheck shell=bash
# shellcheck source=../verify.sh
# Verify checks for the Beszel app (apps/beszel.sh).

check_beszel_uses_shared_binary_lifecycle() {
  local file
  for file in impl/install_beszel.sh; do
    grep -Fq 'bapp_install' "$file" \
      && grep -Fq 'bapp_update' "$file" \
      && grep -Fq 'bapp_backup' "$file" \
      && grep -Fq 'bapp_uninstall' "$file" \
      && grep -Fq 'bapp_status' "$file" \
      && grep -Fq 'bapp_preflight' "$file" \
      && grep -Fq 'bapp_validate_cfg' "$file" \
      && grep -Fq 'binary_app_bootstrap' "$file" \
      || {
        echo "${file} beszel must delegate lifecycle to lib/binary_app.sh and call binary_app_bootstrap" >&2
        return 1
      }
  done
}

check_beszel_release_asset_mapping() {
  local file
  for file in impl/install_beszel.sh; do
    grep -Fq 'GITHUB_REPO="${GITHUB_REPO:-henrygd/beszel}"' "$file" \
      && grep -Fq 'BA_BIN_NAME="beszel"' "$file" \
      && grep -Fq 'BA_ARCHIVE_TYPE="tar.gz"' "$file" \
      && grep -Fq "printf 'beszel_linux_%s.tar.gz" "$file" \
      && grep -Fq 'BA_SERVICE_ARGS="serve --http ${BA_BIND_ADDR}:${PORT} --dir ${DATA_DIR}"' "$file" \
      && grep -Fq 'BA_HEALTH_URL="http://127.0.0.1:${PORT}/api/health"' "$file" \
      || {
        echo "${file} must map the verified Beszel hub release archive, data directory, and health endpoint." >&2
        return 1
      }
  done
}

check_beszel_env_is_managed_atomically() {
  local file
  for file in impl/install_beszel.sh; do
    grep -Fq 'atomic_write_file "$env_file" 600 root:root' "$file" \
      && grep -Fq 'APP_URL=${app_url}' "$file" \
      && grep -Fq 'error "$(t app.beszel.error.env_write "$env_file")"' "$file" \
      && grep -Fq 'success "$(t app.beszel.success.env_written "$env_file")"' "$file" \
      || {
        echo "${file} beszel env must be written atomically and report failures." >&2
        return 1
      }
  done
}
