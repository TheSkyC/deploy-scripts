# shellcheck shell=bash
# shellcheck source=../verify.sh
# Verify checks for the ntfy app (apps/ntfy.sh).

check_ntfy_uses_shared_binary_lifecycle() {
  awk '
      /^do_install\(\) \{/ { in_install=1; saw_lock=0; saw_bapp=0; next }
      in_install && /acquire_lock/ { saw_lock=1 }
      in_install && /bapp_install/ { saw_bapp=1 }
      in_install && /^}/ {
        if (!(saw_lock && saw_bapp)) {
          printf "%s ntfy install must delegate to bapp_install with a deployment lock\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_install=0
      }
      /^do_update\(\) \{/ { in_update=1; saw_lock=0; saw_bapp=0; next }
      in_update && /acquire_lock/ { saw_lock=1 }
      in_update && /bapp_update/ { saw_bapp=1 }
      in_update && /^}/ {
        if (!(saw_lock && saw_bapp)) {
          printf "%s ntfy update must delegate to bapp_update with a deployment lock\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_update=0
      }
      /^do_backup\(\) \{/ { in_backup=1; saw_lock=0; saw_bapp=0; next }
      in_backup && /acquire_lock/ { saw_lock=1 }
      in_backup && /bapp_backup/ { saw_bapp=1 }
      in_backup && /^}/ {
        if (!(saw_lock && saw_bapp)) {
          printf "%s ntfy backup must delegate to bapp_backup with a deployment lock\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_backup=0
      }
      /^do_uninstall\(\) \{/ { in_uninstall=1; saw_lock=0; saw_bapp=0; next }
      in_uninstall && /acquire_lock/ { saw_lock=1 }
      in_uninstall && /bapp_uninstall/ { saw_bapp=1 }
      in_uninstall && /^}/ {
        if (!(saw_lock && saw_bapp)) {
          printf "%s ntfy uninstall must delegate to bapp_uninstall with a deployment lock\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_uninstall=0
      }
      /^do_status\(\) \{/ { in_status=1; saw_bapp=0; next }
      in_status && /bapp_status/ { saw_bapp=1 }
      in_status && /^}/ {
        if (!saw_bapp) {
          printf "%s ntfy status must delegate to bapp_status\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_status=0
      }
      /^preflight_check\(\) \{/ { in_preflight=1; saw_bapp=0; next }
      in_preflight && /bapp_preflight/ { saw_bapp=1 }
      in_preflight && /^}/ {
        if (!saw_bapp) {
          printf "%s ntfy preflight must delegate to bapp_preflight\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_preflight=0
      }
      /^_validate_config_values\(\) \{/ { in_validate=1; saw_bapp=0; next }
      in_validate && /bapp_validate_cfg/ { saw_bapp=1 }
      in_validate && /^}/ {
        if (!saw_bapp) {
          printf "%s ntfy config validation must delegate to bapp_validate_cfg\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_validate=0
      }
      /^binary_app_bootstrap$/ { saw_bootstrap=1 }
      END {
        if (!saw_bootstrap) {
          printf "%s ntfy impl must call binary_app_bootstrap\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_ntfy.sh
}

check_ntfy_release_asset_mapping() {
  local file
  for file in impl/install_ntfy.sh; do
    grep -Fq 'GITHUB_REPO="${GITHUB_REPO:-binwiederhier/ntfy}"' "$file" \
      && grep -Fq 'BA_BIN_NAME="ntfy"' "$file" \
      && grep -Fq 'BA_ARCHIVE_TYPE="tar.gz"' "$file" \
      && grep -Fq "printf 'ntfy_%s_linux_%s.tar.gz" "$file" \
      && grep -Fq 'BA_HEALTH_URL="http://127.0.0.1:${PORT}/"' "$file" \
      || {
        echo "${file} must map the verified GitHub release assets (v-less tarball names, health URL)." >&2
        return 1
      }
  done
}

check_ntfy_config_is_managed_atomically() {
  grep -Fq 'atomic_write_file "$config_file" 644 root:root' impl/install_ntfy.sh     && grep -Fq 'error "$(t app.ntfy.error.config_write "$config_file")"' impl/install_ntfy.sh     && grep -Fq 'success "$(t app.ntfy.success.config_written "$config_file")"' impl/install_ntfy.sh     && grep -Fq 'ba_remove_file_or_error "$config_file" "NTFY_CONFIG_FILE"' impl/install_ntfy.sh     && grep -Fq 'warn "$(t app.ntfy.warn.config_dir_remove "$config_dir")"' impl/install_ntfy.sh     || {
      echo "ntfy config writes must be atomic and uninstall must report removal failures." >&2
      return 1
    }
}
