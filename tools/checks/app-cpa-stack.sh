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

check_cpa_stack_status_reports_component_versions() {
  awk '
      /^do_status\(\)/ { current="status"; next }
      /^}/ { current="" }
      current == "status" && /if \[\[ \$\{EUID:-\$\(id -u\)\} -eq 0 \]\]/ { saw_root_gate=1 }
      current == "status" && /app\.cpa_stack\.status\.versions/ { saw_versions=1 }
      current == "status" && /app\.cpa_stack\.status\.cpa_component/ { saw_cpa=1 }
      current == "status" && /app\.cpa_stack\.status\.cpamp_component/ { saw_cpamp=1 }
      current == "status" && /app\.cpa_stack\.status\.components_follow_latest/ { saw_follow=1 }
      END {
        if (!(saw_root_gate && saw_versions && saw_cpa && saw_cpamp && saw_follow)) {
          printf "%s root cpa-stack status must report recorded component versions and the moving-latest semantics\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_cpa_stack.sh
  grep -Fq 'app.cpa_stack.status.versions' apps/cpa_stack.sh
  grep -Fq 'app.cpa_stack.status.cpa_component' apps/cpa_stack.sh
  grep -Fq 'app.cpa_stack.status.cpamp_component' apps/cpa_stack.sh
  grep -Fq 'app.cpa_stack.status.components_follow_latest' apps/cpa_stack.sh
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

# Pinned CPA/CPAMP releases (CPA_VERSION / CPAMP_VERSION persisted in the
# trusted deployment config) are immutable targets: install resolves the exact
# GitHub tags/<tag> endpoint, an already-matching pinned binary is not
# re-downloaded, and the central check-update/status adapters compare the
# installed versions against the pins locally (cache_state=pinned) without
# querying the moving latest. Without pins the adapters keep the
# floating-latest behavior.
check_cpa_stack_pinned_versions_contract() {
  local output
  output="$($BASH_BIN <<'CPATEST'
set -euo pipefail
temp_root="$(mktemp -d)"
trap 'rm -rf "$temp_root"' EXIT
export DEPLOY_VERSION_CACHE_ROOT="${temp_root}/version-cache"
source lib/core.sh
export DEPLOY_IMPL_SOURCE_ONLY=1
APP_ID=cpa_stack
APP_NAME="CPA Stack"
app_conf_file() { printf '%s' '/nonexistent/cpa-stack-deploy.conf'; }
github_latest_release_tag_checked() { printf 'pinned projection must not query the moving latest\n' >&2; return 97; }
source apps/cpa_stack.sh >/dev/null 2>&1

CPA_VERSION=v1.0.0
CPAMP_VERSION=v2.0.0
INSTALLED_CPA_VERSION=v0.9.0
INSTALLED_CPAMP_VERSION=v2.0.0
source impl/install_cpa_stack.sh >/dev/null 2>&1

pinned="$(_cpa_stack_check_update_json 1 1)"
[[ "$(state_json_field "$pinned" installed)" == "v0.9.0/v2.0.0" ]]
[[ "$(state_json_field "$pinned" latest)" == "v1.0.0/v2.0.0" ]]
[[ "$(state_json_field "$pinned" update_state)" == update_available ]]
[[ "$(state_json_field "$pinned" source)" == github_release ]]
[[ "$(state_json_field "$pinned" cache_state)" == pinned ]]
[[ "$(state_json_field "$pinned" components.cpa.cache_state)" == pinned ]]
[[ "$(state_json_field "$pinned" components.cpamp.update_state)" == up_to_date ]]

status_pinned="$(_cpa_stack_status_version_json)"
[[ "$(state_json_field "$status_pinned" cache_state)" == pinned ]]

# An installed binary that already matches the pin must short-circuit without
# touching GitHub; a curl stub fails the run if the tagged endpoint is hit.
cpa_stack_arch() { printf 'amd64\n'; }
curl() { printf 'already-pinned install must not download\n' >&2; return 97; }
INSTALLED_CPA_VERSION=v1.0.0
CPA_BIN="${temp_root}/cpa-bin"
printf '#!/bin/sh\n' > "$CPA_BIN"
chmod 0755 "$CPA_BIN"
result="$(cpa_stack_install_release cpa 2>&1)"
[[ "$result" == *"v1.0.0"* ]]

CPA_VERSION=""
CPAMP_VERSION=""
INSTALLED_CPA_VERSION=v0.9.0
github_latest_release_tag_checked() { case "$1" in "$CPAMP_REPOSITORY") printf 'v2.1.0\n' ;; *) printf 'v1.1.0\n' ;; esac; }
floating="$(_cpa_stack_check_update_json 1 0)"
[[ "$(state_json_field "$floating" installed)" == "v0.9.0/v2.0.0" ]]
[[ "$(state_json_field "$floating" latest)" == "v1.1.0/v2.1.0" ]]
[[ "$(state_json_field "$floating" update_state)" == update_available ]]
[[ "$(state_json_field "$floating" source)" == github_release ]]
printf ok
CPATEST
  )"
  [[ "$output" == ok ]] || return 1
  grep -Fq 'CPA_VERSION="${CPA_VERSION:-}"' impl/install_cpa_stack.sh
  grep -Fq 'CPAMP_VERSION="${CPAMP_VERSION:-}"' impl/install_cpa_stack.sh
  grep -Fq 'CPA_VERSION CPAMP_VERSION' impl/install_cpa_stack.sh
  grep -Fq 'endpoint="releases/tags/${tag}"' impl/install_cpa_stack.sh
  grep -Fq 'success "$(t app.cpa_stack.success.already_pinned "$component" "$pin")"' impl/install_cpa_stack.sh
  grep -Fq 'success "$(t app.cpa_stack.success.pinned_version "$component" "$tag")"' impl/install_cpa_stack.sh
  grep -Fq 'info "$(t app.cpa_stack.info.unpinned_version "$component" "$tag")"' impl/install_cpa_stack.sh
  grep -Fq 'error "$(t app.cpa_stack.error.pinned_version_invalid "$pinned_key" "$pinned_value")"' impl/install_cpa_stack.sh
  grep -Fq 't app.cpa_stack.status.pin_ok "$pin_component" "$pin_value"' impl/install_cpa_stack.sh
  grep -Fq 't app.cpa_stack.status.pin_mismatch "$pin_component" "$pin_value" "$pin_installed"' impl/install_cpa_stack.sh
  grep -Fq 't app.cpa_stack.status.pin_set "$pin_component" "$pin_value"' impl/install_cpa_stack.sh
  grep -Fq 'app.cpa_stack.success.pinned_version' apps/cpa_stack.sh
  grep -Fq 'app.cpa_stack.success.already_pinned' apps/cpa_stack.sh
  grep -Fq 'app.cpa_stack.info.unpinned_version' apps/cpa_stack.sh
  grep -Fq 'app.cpa_stack.error.pinned_version_invalid' apps/cpa_stack.sh
  grep -Fq 'app.cpa_stack.status.pin_ok' apps/cpa_stack.sh
  grep -Fq 'app.cpa_stack.status.pin_mismatch' apps/cpa_stack.sh
  grep -Fq 'app.cpa_stack.status.pin_set' apps/cpa_stack.sh
}
