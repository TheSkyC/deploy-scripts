# shellcheck shell=bash
# shellcheck source=../verify.sh
# Verify checks for the Meilisearch app (apps/meilisearch.sh).

check_meilisearch_uses_shared_binary_lifecycle() {
  local file
  # shellcheck disable=SC2043 # Fixed target; retain the shared per-file guard body.
  for file in impl/install_meilisearch.sh; do
    awk -v f="$file" '
      /^do_install\(\) \{/ { wire["install"]="bapp_install" }
      /^do_update\(\) \{/ { wire["update"]="bapp_update" }
      /^do_backup\(\) \{/ { wire["backup"]="bapp_backup" }
      /^do_uninstall\(\) \{/ { wire["uninstall"]="bapp_uninstall" }
      /^do_status\(\) \{/ { wire["status"]="bapp_status" }
      /^preflight_check\(\) \{/ { wire["preflight"]="bapp_preflight" }
      /^_validate_config_values\(\) \{/ { wire["validate"]="bapp_validate_cfg" }
      /^binary_app_bootstrap$/ { saw_bootstrap=1 }
      END {
        if (wire["install"] != "bapp_install" || wire["update"] != "bapp_update" \
            || wire["backup"] != "bapp_backup" || wire["uninstall"] != "bapp_uninstall" \
            || wire["status"] != "bapp_status" || wire["preflight"] != "bapp_preflight" \
            || wire["validate"] != "bapp_validate_cfg" || !saw_bootstrap) {
          printf "%s meilisearch must delegate lifecycle to lib/binary_app.sh and call binary_app_bootstrap\n", f > "/dev/stderr"
          exit 1
        }
      }
    ' "$file"
  done
}

check_meilisearch_release_asset_mapping() {
  local file
  # shellcheck disable=SC2043 # Fixed target; retain the shared per-file guard body.
  for file in impl/install_meilisearch.sh; do
    grep -Fq 'GITHUB_REPO="${GITHUB_REPO:-meilisearch/meilisearch}"' "$file" \
      && grep -Fq 'BA_BIN_NAME="meilisearch"' "$file" \
      && grep -Fq 'BA_ARCHIVE_TYPE="none"' "$file" \
      && grep -Fq 'BA_USE_ENV_FILE=1' "$file" \
      && grep -Fq "printf 'meilisearch-linux-%s" "$file" \
      && grep -Fq '[[ "$arch" == "arm64" ]] && arch="aarch64"' "$file" \
      && grep -Fq 'BA_HEALTH_URL="http://127.0.0.1:${PORT}/health"' "$file" \
      || {
        echo "${file} must map the verified Meilisearch release binaries (aarch64 naming, env file, health URL)." >&2
        return 1
      }
  done
}

check_meilisearch_config_is_managed_atomically() {
  local file
  # shellcheck disable=SC2043 # Fixed target; retain the shared per-file guard body.
  for file in impl/install_meilisearch.sh; do
    grep -Fq 'atomic_write_file "$env_file" 600 root:root' "$file" \
      && grep -Fq 'MEILI_MASTER_KEY=' "$file" \
      && grep -Fq 'MEILI_DB_PATH=${DATA_DIR}/meili_data' "$file" \
      && grep -Fq 'error "$(t app.meilisearch.error.env_write "$env_file")"' "$file" \
      || {
        echo "${file} must write the Meilisearch env file atomically and report failures." >&2
        return 1
      }
  done
}
