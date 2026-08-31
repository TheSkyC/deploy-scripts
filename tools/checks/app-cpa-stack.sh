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

check_cpa_stack_binary_backups_are_atomic() {
  local output
  output="$($BASH_BIN <<'CPATEST'
set -euo pipefail
source lib/core.sh
export DEPLOY_IMPL_SOURCE_ONLY=1
source impl/install_cpa_stack.sh >/dev/null 2>&1

tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT
source_path="$tmp_dir/source"
target_path="$tmp_dir/target"
records="$tmp_dir/records"
cp_calls="$tmp_dir/cp-calls"
printf new > "$source_path"
printf old > "$target_path"
error() { return 1; }
atomic_copy_file() {
  local source="$1" target="$2"
  printf '%s|%s\n' "$source" "$target" >> "$records"
  if [[ "$source" == "$target_path" && "$target" == "$target_path".bak.* ]]; then
    cat "$source" > "$target"
    return 0
  fi
  [[ "$source" == "$source_path" && "$target" == "$target_path" ]] && return 1
  return 1
}
cp() { printf '%s\n' "$*" >> "$cp_calls"; return 1; }
set +e
cpa_stack_install_binary "$source_path" "$target_path" root:root
status=$?
set -e
[[ "$status" -ne 0 ]]
[[ "$(cat "$target_path")" == old ]]
compgen -G "$target_path.bak.*" >/dev/null
[[ ! -e "$cp_calls" ]]
[[ "$(sed -n '1p' "$records")" == "$target_path|$target_path".bak.* ]]
[[ "$(sed -n '2p' "$records")" == "$source_path|$target_path" ]]
printf ok
CPATEST
  )"
  [[ "$output" == ok ]]
  awk '
      /cpa_stack_install_binary\(\)/ { in_func=1; saw_backup=0; saw_publish=0; saw_backup_error=0; saw_publish_error=0; saw_direct_restore=0; next }
      in_func && /atomic_copy_file "\$target" "\$backup"/ { saw_backup=1 }
      in_func && /atomic_copy_file "\$source" "\$target" 0755 "\$owner"/ { saw_publish=1 }
      in_func && /error "\$\(t app\.cpa_stack\.error\.binary_backup "\$target"\)"/ { saw_backup_error=1 }
      in_func && /error "\$\(t app\.cpa_stack\.error\.binary_install "\$target"\)"/ { saw_publish_error=1 }
      in_func && /cp -a "\$backup" "\$target"/ { saw_direct_restore=1 }
      in_func && /^}/ {
        if (!(saw_backup && saw_publish && saw_backup_error && saw_publish_error) || saw_direct_restore) {
          print "CPA Stack binary publication must retain atomic backups and avoid non-atomic rollback copies" > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
      END {
        if (in_func) {
          print "CPA Stack binary install function was not closed" > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_cpa_stack.sh
}
