# shellcheck shell=bash
# shellcheck source=../verify.sh
# Verify checks for the Filebrowser app (apps/filebrowser.sh).

check_filebrowser_uses_shared_binary_lifecycle() {
  local file
  # shellcheck disable=SC2043 # Fixed target; retain the shared per-file guard body.
  for file in impl/install_filebrowser.sh; do
    grep -Fq 'bapp_install' "$file" \
      && grep -Fq 'bapp_update' "$file" \
      && grep -Fq 'bapp_backup' "$file" \
      && grep -Fq 'bapp_uninstall' "$file" \
      && grep -Fq 'bapp_status' "$file" \
      && grep -Fq 'bapp_preflight' "$file" \
      && grep -Fq 'bapp_validate_cfg' "$file" \
      && grep -Fq 'binary_app_bootstrap' "$file" \
      || {
        echo "${file} filebrowser must delegate lifecycle to lib/binary_app.sh and call binary_app_bootstrap" >&2
        return 1
      }
  done
}

check_filebrowser_release_asset_mapping() {
  local file
  # shellcheck disable=SC2043 # Fixed target; retain the shared per-file guard body.
  for file in impl/install_filebrowser.sh; do
    grep -Fq 'GITHUB_REPO="${GITHUB_REPO:-filebrowser/filebrowser}"' "$file" \
      && grep -Fq 'BA_BIN_NAME="filebrowser"' "$file" \
      && grep -Fq 'BA_ARCHIVE_TYPE="tar.gz"' "$file" \
      && grep -Fq "printf 'linux-%s-filebrowser.tar.gz" "$file" \
      && grep -Fq 'BA_READWRITE_PATHS="${FB_ROOT}"' "$file" \
      && grep -Fq 'BA_HEALTH_URL="http://127.0.0.1:${PORT}/"' "$file" \
      || {
        echo "${file} must map the verified Filebrowser release tarball and serve FB_ROOT." >&2
        return 1
      }
  done
}

check_filebrowser_root_directory_is_prepared() {
  local file
  # shellcheck disable=SC2043 # Fixed target; retain the shared per-file guard body.
  for file in impl/install_filebrowser.sh; do
    grep -Fq 'ba_pre_start()' "$file" \
      && grep -Fq 'mkdir -p "$FB_ROOT"' "$file" \
      && grep -Fq 'chown "${SERVICE_USER}:${SERVICE_USER}" "$FB_ROOT"' "$file" \
      || {
        echo "${file} filebrowser must create and own the served FB_ROOT before start." >&2
        return 1
      }
  done
}
