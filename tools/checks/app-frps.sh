# shellcheck shell=bash
# shellcheck source=../verify.sh
# Verify checks for the frps app (apps/frps.sh).

check_frps_uses_shared_binary_lifecycle() {
  local file
  for file in impl/install_frps.sh dist/install_frps.sh; do
    grep -Fq 'bapp_install' "$file" \
      && grep -Fq 'bapp_update' "$file" \
      && grep -Fq 'bapp_backup' "$file" \
      && grep -Fq 'bapp_uninstall' "$file" \
      && grep -Fq 'bapp_status' "$file" \
      && grep -Fq 'bapp_preflight' "$file" \
      && grep -Fq 'bapp_validate_cfg' "$file" \
      && grep -Fq 'binary_app_bootstrap' "$file" \
      || {
        echo "${file} frps must delegate lifecycle to lib/binary_app.sh and call binary_app_bootstrap" >&2
        return 1
      }
  done
}

check_frps_release_asset_mapping() {
  local file
  for file in impl/install_frps.sh dist/install_frps.sh; do
    grep -Fq 'GITHUB_REPO="${GITHUB_REPO:-fatedier/frp}"' "$file" \
      && grep -Fq 'BA_BIN_NAME="frps"' "$file" \
      && grep -Fq 'BA_ARCHIVE_TYPE="tar.gz"' "$file" \
      && grep -Fq "printf 'frp_%s_linux_%s.tar.gz" "$file" \
      && grep -Fq 'BA_SERVICE_ARGS="-c /etc/frps/frps.toml"' "$file" \
      && grep -Fq 'bindPort = ${PORT}' "$file" \
      || {
        echo "${file} must map the verified frp release tarball and run frps with the managed config." >&2
        return 1
      }
  done
}

check_frps_config_is_managed_atomically() {
  local file
  for file in impl/install_frps.sh dist/install_frps.sh; do
    grep -Fq 'atomic_write_file "$config_file" 600 root:root' "$file" \
      && grep -Fq 'auth.token' "$file" \
      && grep -Fq 'error "$(t app.frps.error.config_write "$config_file")"' "$file" \
      && grep -Fq 'ba_remove_file_or_error "$config_file" "FRPS_CONFIG_FILE"' "$file" \
      && grep -Fq 'systemctl is-active --quiet "$SERVICE_NAME"' "$file" \
      || {
        echo "${file} frps config must be atomic, uninstall must report failures, and health must check the unit." >&2
        return 1
      }
  done
}
