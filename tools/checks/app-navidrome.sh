# shellcheck shell=bash
# shellcheck source=../verify.sh
# Verify checks for the Navidrome app (apps/navidrome.sh).

check_navidrome_uses_shared_binary_lifecycle() {
  local file
  # shellcheck disable=SC2043 # Fixed target; retain the shared per-file guard body.
  for file in impl/install_navidrome.sh; do
    grep -Fq 'bapp_install' "$file" \
      && grep -Fq 'bapp_update' "$file" \
      && grep -Fq 'bapp_backup' "$file" \
      && grep -Fq 'bapp_uninstall' "$file" \
      && grep -Fq 'bapp_status' "$file" \
      && grep -Fq 'bapp_preflight' "$file" \
      && grep -Fq 'bapp_validate_cfg' "$file" \
      && grep -Fq 'binary_app_bootstrap' "$file" \
      || {
        echo "${file} navidrome must delegate lifecycle to lib/binary_app.sh and call binary_app_bootstrap" >&2
        return 1
      }
  done
}

check_navidrome_release_asset_mapping() {
  local file
  # shellcheck disable=SC2043 # Fixed target; retain the shared per-file guard body.
  for file in impl/install_navidrome.sh; do
    grep -Fq 'GITHUB_REPO="${GITHUB_REPO:-navidrome/navidrome}"' "$file" \
      && grep -Fq 'BA_BIN_NAME="navidrome"' "$file" \
      && grep -Fq 'BA_ARCHIVE_TYPE="tar.gz"' "$file" \
      && grep -Fq "printf 'navidrome_%s_linux_%s.tar.gz" "$file" \
      && grep -Fq 'BA_USE_ENV_FILE=1' "$file" \
      && grep -Fq 'ND_MUSICFOLDER=${MUSIC_DIR}' "$file" \
      && grep -Fq 'BA_HEALTH_URL="http://127.0.0.1:${PORT}/ping"' "$file" \
      || {
        echo "${file} must map the verified Navidrome release tarball and ND_* env configuration." >&2
        return 1
      }
  done
}

check_navidrome_music_folder_is_prepared() {
  local file
  # shellcheck disable=SC2043 # Fixed target; retain the shared per-file guard body.
  for file in impl/install_navidrome.sh; do
    grep -Fq 'ba_pre_start()' "$file" \
      && grep -Fq 'mkdir -p "$MUSIC_DIR"' "$file" \
      && grep -Fq 'chown "${SERVICE_USER}:${SERVICE_USER}" "$MUSIC_DIR"' "$file" \
      && grep -Fq 'BA_READWRITE_PATHS="${MUSIC_DIR}"' "$file" \
      || {
        echo "${file} navidrome must create and own the music folder before start." >&2
        return 1
      }
  done
}
