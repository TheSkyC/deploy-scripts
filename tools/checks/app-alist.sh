# shellcheck shell=bash
# shellcheck source=../verify.sh
# Verify checks for the Alist app (apps/alist.sh).

check_alist_uses_shared_binary_lifecycle() {
  local file
  # shellcheck disable=SC2043 # Fixed target; retain the shared per-file guard body.
  for file in impl/install_alist.sh; do
    grep -Fq 'bapp_install' "$file" \
      && grep -Fq 'bapp_update' "$file" \
      && grep -Fq 'bapp_backup' "$file" \
      && grep -Fq 'bapp_uninstall' "$file" \
      && grep -Fq 'bapp_status' "$file" \
      && grep -Fq 'bapp_preflight' "$file" \
      && grep -Fq 'bapp_validate_cfg' "$file" \
      && grep -Fq 'binary_app_bootstrap' "$file" \
      || {
        echo "${file} alist must delegate lifecycle to lib/binary_app.sh and call binary_app_bootstrap" >&2
        return 1
      }
  done
}

check_alist_release_asset_mapping() {
  local file
  # shellcheck disable=SC2043 # Fixed target; retain the shared per-file guard body.
  for file in impl/install_alist.sh; do
    grep -Fq 'GITHUB_REPO="${GITHUB_REPO:-AlistGo/alist}"' "$file" \
      && grep -Fq 'BA_BIN_NAME="alist"' "$file" \
      && grep -Fq 'BA_ARCHIVE_TYPE="tar.gz"' "$file" \
      && grep -Fq "printf 'alist-linux-%s.tar.gz" "$file" \
      && grep -Fq 'BA_SERVICE_ARGS="server --data ${DATA_DIR}"' "$file" \
      && grep -Fq 'BA_HEALTH_URL="http://127.0.0.1:${PORT}/"' "$file" \
      || {
        echo "${file} must map the verified Alist release tarball and run the server from DATA_DIR." >&2
        return 1
      }
  done
}


check_alist_config_rewrites_use_shared_atomic_write() {
  local file=impl/install_alist.sh
  grep -Fq '"$config_file" | atomic_write_file "$config_file" 600 "root:${SERVICE_USER}"' "$file"     || {
      echo "${file} Alist config rewrites must publish through atomic_write_file." >&2
      return 1
    }
  if grep -nE '^[[:space:]]*(local (tmp|tmp2)|if ! (tmp|tmp2)=\$\(mktemp "\$\{config_file\})|chown "root:\$\{SERVICE_USER\}" "\$tmp|mv -f "\$tmp' "$file"; then
    echo "${file} must not stage config rewrites with a private mktemp/chown/mv sequence." >&2
    return 1
  fi
}
