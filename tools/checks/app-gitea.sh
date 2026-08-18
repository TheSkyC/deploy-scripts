# shellcheck shell=bash
# shellcheck source=../verify.sh
# Verify checks for the Gitea app (apps/gitea.sh).

check_gitea_uses_shared_binary_lifecycle() {
  local file
  for file in impl/install_gitea.sh dist/install_gitea.sh; do
    grep -Fq 'bapp_install' "$file" \
      && grep -Fq 'bapp_update' "$file" \
      && grep -Fq 'bapp_backup' "$file" \
      && grep -Fq 'bapp_uninstall' "$file" \
      && grep -Fq 'bapp_status' "$file" \
      && grep -Fq 'bapp_preflight' "$file" \
      && grep -Fq 'bapp_validate_cfg' "$file" \
      && grep -Fq 'binary_app_bootstrap' "$file" \
      || {
        echo "${file} gitea must delegate lifecycle to lib/binary_app.sh and call binary_app_bootstrap" >&2
        return 1
      }
  done
}

check_gitea_release_asset_mapping() {
  local file
  for file in impl/install_gitea.sh dist/install_gitea.sh; do
    grep -Fq 'GITHUB_REPO="${GITHUB_REPO:-go-gitea/gitea}"' "$file" \
      && grep -Fq 'BA_BIN_NAME="gitea"' "$file" \
      && grep -Fq 'BA_ARCHIVE_TYPE="none"' "$file" \
      && grep -Fq 'BA_APT_PACKAGES="git"' "$file" \
      && grep -Fq "printf 'gitea-%s-linux-%s" "$file" \
      && grep -Fq 'BA_SERVICE_ARGS="web --config /etc/gitea/app.ini --work-path ${DATA_DIR}"' "$file" \
      || {
        echo "${file} must map the verified Gitea release binaries and apt git dependency." >&2
        return 1
      }
  done
}

check_gitea_config_is_managed_atomically() {
  local file
  for file in impl/install_gitea.sh dist/install_gitea.sh; do
    grep -Fq 'atomic_write_file "$config_file" 640 root:root' "$file" \
      && grep -Fq 'DB_TYPE = sqlite' "$file" \
      && grep -Fq 'error "$(t app.gitea.error.config_write "$config_file")"' "$file" \
      && grep -Fq 'ba_remove_file_or_error "$config_file" "GITEA_CONFIG_FILE"' "$file" \
      || {
        echo "${file} gitea config must be atomic and uninstall must report removal failures." >&2
        return 1
      }
  done
}
