# shellcheck shell=bash
# shellcheck source=../verify.sh
# Verify checks for the cpa-stack app (apps/cpa_stack.sh).

check_cpa_stack_status_backup_projection() {
  local output
  output="$($BASH_BIN -c '
    set -euo pipefail
    tmp_dir="$(mktemp -d)"
    backup_dir="$tmp_dir/cpa backups"
    mkdir -p "$backup_dir"
    touch -d "2026-08-20 12:34:56 UTC" "$backup_dir/cpa-stack-20260820123456.tar.gz"
    source lib/core.sh
    APP_ID=cpa_stack
    APP_NAME="CPA Stack"
    CPA_STACK_BACKUP_DIR="$backup_dir"
    app_conf_file() { printf "%s" "$tmp_dir/missing.conf"; }
    source impl/install_cpa_stack.sh
    _cpa_stack_status_backup
    rm -rf "$tmp_dir"
  ')"
  python -c 'import json,sys; x=json.loads(sys.argv[1]); assert x["state"] == "available"; assert "cpa backups" in x["path"]; assert x["path"].endswith("cpa-stack-20260820123456.tar.gz"); assert x["last_success_at"]' "$output"
  grep -Fq 'APP_STATUS_BACKUP_FN=_cpa_stack_status_backup' impl/install_cpa_stack.sh
}

check_cpa_stack_layout() {
  local file
  # shellcheck disable=SC2043 # Fixed target; retain the shared per-file guard body.
  for file in impl/install_cpa_stack.sh; do
    grep -Fq 'host: "127.0.0.1"' "$file" \
      && grep -Fq 'usage-statistics-enabled: true' "$file" \
      && grep -Fq 'Environment=HTTP_ADDR=127.0.0.1:18317' "$file" \
      && grep -Fq 'CPA_UPSTREAM_URL="${prior_upstream:-http://127.0.0.1:8317}"' "$file" \
      && grep -Fq 'cpa_stack_download_verified_archive' "$file" \
      && grep -Fq 'checksums.txt' "$file" \
      && grep -Fq 'data.key' "$file" \
      && grep -Fq 'CPAMP_ENV_FILE' "$file" \
      && grep -Fq 'location /.well-known/acme-challenge/' "$file" \
      && grep -Fq 'proxy_pass http://127.0.0.1:8317;' "$file" \
      && grep -Fq 'proxy_pass http://127.0.0.1:18317;' "$file" \
      && grep -Fq 'certbot certonly --webroot' "$file" \
      && grep -Fq 'CPA_STACK_COMPONENT' "$file" \
      && grep -Fq 'do_cert()' "$file" \
      && grep -Fq 'app.cpa_stack.success.https' "$file" \
      && grep -Fq 'cpa_stack_nginx_http2_directives' "$file" \
      && grep -Fq 'http2 on;' "$file" \
      && grep -Fq 'listen 443 ssl http2;' "$file" \
      || {
        echo "CPA Stack must retain local-only backends, verified releases, HTTPS reverse proxy, and component update controls: ${file}" >&2
        return 1
      }
  done
}

check_cpa_stack_component_version_manifest() {
  local output
  output="$($BASH_BIN <<'CPATEST'
set -euo pipefail
source lib/core.sh
export DEPLOY_IMPL_SOURCE_ONLY=1
source impl/install_cpa_stack.sh >/dev/null 2>&1
fresh='{"installed":"v1","latest":"v9","checked_at":"2026-01-01T00:00:00Z","update_state":"up_to_date","source":"github_release","cache_state":"fresh","error":null}'
available='{"installed":"v2","latest":"v8","checked_at":null,"update_state":"update_available","source":"github_release","cache_state":"refreshed","error":null}'
merged="$(_cpa_stack_merge_version_json "$fresh" "$available")"
python -c 'import json,sys; x=json.loads(sys.argv[1]); assert x["components"]["cpa"]["id"] == "cpa"; assert x["components"]["cpa"]["repository"] == "router-for-me/CLIProxyAPI"; assert x["components"]["cpamp"]["latest"] == "v8"; assert x["update_state"] == "update_available"' "$merged"
printf ok
CPATEST
  )"
  [[ "$output" == ok ]]
  grep -Fq 'version_check_component_json cpa' impl/install_cpa_stack.sh
  grep -Fq 'version_check_component_json cpamp' impl/install_cpa_stack.sh
}
