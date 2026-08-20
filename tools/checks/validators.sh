# shellcheck shell=bash
# shellcheck source=../verify.sh
# Shared validator and helper behavior guardrails: accept/reject tests for lib/app.sh validators plus connectivity and GitHub tag helpers.

check_framework_validator_errors_are_actionable() {
  awk '
      /^app_validate_port\(\)/ { in_port=1; next }
      in_port && /t error\.port_invalid/ { saw_port=1 }
      in_port && /^}/ { in_port=0 }
      /^app_validate_bool\(\)/ { in_bool=1; next }
      in_bool && /t error\.bool_invalid/ { saw_bool=1 }
      in_bool && /^}/ { in_bool=0 }
      /^app_validate_domain\(\)/ { in_domain=1; next }
      in_domain && /t error\.domain_invalid/ { saw_domain=1 }
      in_domain && /^}/ { in_domain=0 }
      END {
        if (!(saw_port && saw_bool && saw_domain)) {
          print "Framework validators must route invalid port, boolean, and domain values to actionable t error.* keys." > "/dev/stderr"
          exit 1
        }
      }
    ' lib/app.sh
  awk '
      /error\.port_invalid\)/ && /between 1 and 65535/ { saw_port=1 }
      /error\.bool_invalid\)/ && /true\/false, yes\/no, on\/off, or 1\/0/ { saw_bool=1 }
      /error\.domain_invalid\)/ && /DNS name/ { saw_domain=1 }
      END {
        if (!(saw_port && saw_bool && saw_domain)) {
          print "Framework fallback messages must give actionable guidance for invalid port, boolean, and domain values." > "/dev/stderr"
          exit 1
        }
      }
    ' lib/i18n.sh
}

check_api_ports_are_validated() {
  awk '
      /preflight_check\(\)/ { in_preflight=1; next }
      in_preflight && /^}/ {
        if (!saw_preflight) {
          printf "%s NewAPI preflight must validate PORT defaults\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_preflight=0
      }
      in_preflight && /_validate_config_values/ { saw_preflight=1 }
      /_validate_config_values\(\)/ { in_validate=1; next }
      in_validate && /app_validate_port/ { saw_valport=1 }
      in_validate && /^}/ { in_validate=0 }
      END {
        if (!(saw_preflight && saw_valport)) {
          printf "%s NewAPI must validate PORT range via _validate_config_values\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
  awk '
      /preflight_check\(\)/ { in_preflight=1; next }
      in_preflight && /^}/ {
        if (!saw_preflight) {
          printf "%s Sub2API preflight must validate PORT defaults\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_preflight=0
      }
      in_preflight && /_validate_config_values/ { saw_preflight=1 }
      /_validate_config_values\(\)/ { in_validate=1; next }
      in_validate && /app_validate_port/ { saw_valport=1 }
      in_validate && /^}/ { in_validate=0 }
      END {
        if (!(saw_preflight && saw_valport)) {
          printf "%s Sub2API must validate PORT range via _validate_config_values\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_nginx_domains_are_validated() {
  awk '
      /is_valid_dns_name\(\)/ { saw_helper=1 }
      /name=.*\{1:-\}/ { saw_name=1 }
      /\[\[ "\$name" != \*\.\.\* \]\] \|\| return 1/ { saw_dots=1 }
      /\[\[ "\$name" == \*\.\* \]\] \|\| return 1/ { saw_dot_required=1 }
      END {
        if (!(saw_helper && saw_name && saw_dots && saw_dot_required)) {
          print "Shared DNS validation helper must reject empty, overlong, malformed, and single-label server names." > "/dev/stderr"
          exit 1
        }
      }
    ' lib/network.sh
  awk '
      /app\.vaultwarden\.error\.domain_invalid/ { saw_vw=1 }
      /app\.blog\.error\.keep_days_invalid/ { saw_blog_keep_days=1 }
      END {
        if (!(saw_vw && saw_blog_keep_days)) {
          print "Nginx domain and Blog retention validation errors must be localized." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/vaultwarden.sh apps/blog.sh
  awk '
      /_validate_config_values\(\)/ { in_func=1; saw_domain=0; next }
      in_func && /app_validate_domain "CSAI_DOMAIN"/ { saw_domain=1 }
      in_func && /^}/ {
        if (!saw_domain) {
          printf "%s CyberStrikeAI must validate CSAI_DOMAIN via _validate_config_values\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
  awk '
      /_validate_config_values\(\)/ { in_func=1; saw_domain=0; next }
      in_func && /app_validate_domain "SUB2API_DOMAIN"/ { saw_domain=1 }
      in_func && /^}/ {
        if (!saw_domain) {
          printf "%s Sub2API must validate SUB2API_DOMAIN via _validate_config_values\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
  awk '
      /_validate_config_values\(\)/ { in_func=1; saw_domain=0; next }
      in_func && /is_valid_dns_name "\$VW_DOMAIN"/ { saw_domain=1 }
      in_func && /^}/ {
        if (!saw_domain) {
          printf "%s Vaultwarden must validate VW_DOMAIN via _validate_config_values\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
      /prompt "\$\(t app\.vaultwarden\.prompt\.domain\)"/ { in_prompt=1; next }
      in_prompt && /if ! is_valid_dns_name "\$_input"; then/ { saw_prompt=1 }
      in_prompt && /VW_DOMAIN="\$_input"/ {
        if (!saw_prompt) {
          printf "%s Vaultwarden domain wizard must use shared DNS validation\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_prompt=0
      }
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
  awk '
      /_validate_config_values\(\)/ { in_func=1; saw_domain=0; saw_bool=0; saw_theme_url=0; saw_site_url=0; saw_repo=0; saw_ref=0; saw_keep_days=0; next }
      in_func && /app_validate_domain "BLOG_DOMAIN"/ { saw_domain=1 }
      in_func && /app_validate_bool "ENABLE_CMS"/ { saw_bool=1 }
      in_func && /app_validate_https_url "THEME_REPO"/ { saw_theme_url=1 }
      in_func && /app_validate_http_url "CMS_SITE_URL"/ { saw_site_url=1 }
      in_func && /app_validate_github_repo "CMS_REPO"/ { saw_repo=1 }
      in_func && /app_validate_git_ref "CMS_BRANCH"/ { saw_ref=1 }
      in_func && /app\.blog\.error\.keep_days_invalid/ { saw_keep_days=1 }
      in_func && /^}/ {
        if (!(saw_domain && saw_bool && saw_theme_url && saw_site_url && saw_repo && saw_ref && saw_keep_days)) {
          printf "%s Blog must validate domain, CMS settings, and backup retention config values\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_hugo_blog.sh dist/install_hugo_blog.sh
}

check_config_value_validators() {
  "$BASH_BIN" -c '
    source lib/core.sh

    app_validate_domain DOMAIN api.example.com
    app_validate_systemd_name SERVICE_NAME new-api
    app_validate_system_name SERVICE_USER newapi
    app_validate_github_repo GITHUB_REPO QuantumNous/new-api
    app_validate_git_ref GITHUB_BRANCH release/v1.2.3
    app_validate_db_identifier PG_DB sub2api_db
    app_validate_http_url CMS_SITE_URL http://localhost:1313/admin/
    app_validate_https_url THEME_REPO https://github.com/CaiJimmy/hugo-theme-stack.git
    app_validate_goproxy GOPROXY "https://goproxy.cn,direct"
    app_validate_goproxy GOPROXY "https://proxy.example.com|direct"
    app_validate_image_repo VW_IMAGE_REPO vaultwarden/server
    app_validate_image_repo VW_IMAGE_REPO ghcr.io/dani-garcia/vaultwarden
    app_validate_image_repo VW_IMAGE_REPO registry.example.com:5000/team/vaultwarden
    app_validate_image_tag VW_IMAGE_TAG 1.36.0-alpine
    app_validate_sha256 EXTRACT_TOOL_SHA256 a58f4995f568d66d9908649d4df7fc8c36f72096ca5e01f4c2c4291285125685
    app_validate_email CERTBOT_EMAIL admin@example.com
    app_validate_release_version WEB_VAULT_VER 2024.6.2

    validator_must_reject() {
      local label="$1"
      shift
      if ( "$@" ) >/dev/null 2>&1; then
        echo "Validator unexpectedly accepted invalid ${label}." >&2
        exit 1
      fi
    }

    validator_must_reject systemd-name app_validate_systemd_name SERVICE_NAME "../new-api"
    validator_must_reject domain app_validate_domain DOMAIN "api example.com"
    validator_must_reject system-name app_validate_system_name SERVICE_USER "new api"
    validator_must_reject github-repo app_validate_github_repo GITHUB_REPO "owner/repo;rm"
    validator_must_reject git-ref app_validate_git_ref GITHUB_BRANCH "feature/../main"
    validator_must_reject db-identifier app_validate_db_identifier PG_DB "sub2api-db"
    validator_must_reject http-url app_validate_http_url CMS_SITE_URL "https://example.com/a path"
    validator_must_reject https-url app_validate_https_url THEME_REPO "git://github.com/owner/repo.git"
    validator_must_reject goproxy app_validate_goproxy GOPROXY "https://proxy.example.com,;rm"
    validator_must_reject image-repo-tag app_validate_image_repo VW_IMAGE_REPO "vaultwarden/server:latest"
    validator_must_reject image-repo-digest app_validate_image_repo VW_IMAGE_REPO "vaultwarden/server@sha256:abc"
    validator_must_reject image-repo-metachar app_validate_image_repo VW_IMAGE_REPO "vaultwarden/server;rm"
    validator_must_reject image-tag app_validate_image_tag VW_IMAGE_TAG "latest/amd64"
    validator_must_reject sha256 app_validate_sha256 EXTRACT_TOOL_SHA256 abc
    validator_must_reject email app_validate_email CERTBOT_EMAIL "admin@example.com;rm"
    validator_must_reject email-domain app_validate_email CERTBOT_EMAIL "admin@example"
    validator_must_reject release-version app_validate_release_version WEB_VAULT_VER "2024.6/evil"
  '

  local checks=(
    'impl/install_newapi.sh|app_validate_systemd_name "SERVICE_NAME" "$SERVICE_NAME"'
    'impl/install_newapi.sh|app_validate_domain "DOMAIN" "$DOMAIN"'
    'impl/install_newapi.sh|app_validate_system_name "SERVICE_USER" "$SERVICE_USER"'
    'impl/install_newapi.sh|app_validate_github_repo "GITHUB_REPO" "$GITHUB_REPO"'
    'impl/install_sub2api.sh|app_validate_db_identifier "PG_USER" "$PG_USER"'
    'impl/install_sub2api.sh|app_validate_db_identifier "PG_DB" "$PG_DB"'
    'impl/install_cyberstrikeai.sh|app_validate_git_ref "GITHUB_BRANCH" "$GITHUB_BRANCH"'
    'impl/install_cyberstrikeai.sh|app_validate_http_url "PIP_INDEX_URL" "$PIP_INDEX_URL"'
    'impl/install_cyberstrikeai.sh|app_validate_goproxy "GOPROXY" "$GOPROXY"'
    'impl/install_tickflow.sh|app_validate_git_ref "TICKFLOW_BRANCH" "$TICKFLOW_BRANCH"'
    'impl/install_vaultwarden.sh|app_validate_system_name "VW_USER" "$VW_USER"'
    'impl/install_vaultwarden.sh|app_validate_email "CERTBOT_EMAIL" "$CERTBOT_EMAIL"'
    'impl/install_vaultwarden.sh|app_validate_image_repo "VW_IMAGE_REPO" "$VW_IMAGE_REPO"'
    'impl/install_vaultwarden.sh|app_validate_image_tag "VW_IMAGE_TAG" "$VW_IMAGE_TAG"'
    'impl/install_vaultwarden.sh|app_validate_git_ref "EXTRACT_TOOL_COMMIT" "$EXTRACT_TOOL_COMMIT"'
    'impl/install_vaultwarden.sh|app_validate_sha256 "EXTRACT_TOOL_SHA256" "$EXTRACT_TOOL_SHA256"'
    'impl/install_vaultwarden.sh|app_validate_release_version "WEB_VAULT_VER" "$WEB_VAULT_VER"'
    'impl/install_hugo_blog.sh|app_validate_https_url "THEME_REPO" "$THEME_REPO"'
    'impl/install_hugo_blog.sh|app_validate_http_url "CMS_SITE_URL" "$CMS_SITE_URL"'
  )
  local check file pattern
  for check in "${checks[@]}"; do
    file="${check%%|*}"
    pattern="${check#*|}"
    if ! grep -Fq "$pattern" "$file"; then
      echo "${file} must validate config value with: ${pattern}" >&2
      return 1
    fi
  done
}

check_github_release_tag_behavior() {
  "$BASH_BIN" -c '
    set -euo pipefail
    source "$1/lib/logging.sh"
    source "$1/lib/i18n.sh"
    source "$1/lib/network.sh"
    tag=$(json_tag_name '"'"'{"tag_name":"v1.2.3","name":"v1.2.3"}'"'"')
    [[ "$tag" == "v1.2.3" ]] || { echo "json_tag_name expected v1.2.3, got: ${tag}" >&2; exit 1; }
    tag=$(json_tag_name '"'"'{"tag_name":"v1.2.3"}'"'"' --strip-v)
    [[ "$tag" == "1.2.3" ]] || { echo "json_tag_name --strip-v expected 1.2.3, got: ${tag}" >&2; exit 1; }
    tag=$(json_tag_name '"'"'{"id":1}'"'"')
    [[ -z "$tag" ]] || { echo "json_tag_name expected empty, got: ${tag}" >&2; exit 1; }
    curl() { printf "%s\n" '"'"'{"tag_name":"v1.2.3","name":"v1.2.3"}'"'"'; }
    tag=$(github_latest_release_tag "owner/repo" "test.warn" 2>/dev/null)
    [[ "$tag" == "v1.2.3" ]] || { echo "expected v1.2.3, got: ${tag}" >&2; exit 1; }
    curl() { printf "%s\n" '"'"'{"tag_name":"not-a-version"}'"'"'; }
    tag=$(github_latest_release_tag "owner/repo" "test.warn" 2>/dev/null)
    [[ -z "$tag" ]] || { echo "expected empty tag for non-version, got: ${tag}" >&2; exit 1; }
    curl() { return 1; }
    tag=$(github_latest_release_tag "owner/repo" "test.warn" 2>/dev/null)
    [[ -z "$tag" ]] || { echo "expected empty tag on failure, got: ${tag}" >&2; exit 1; }
  ' _ "$ROOT_DIR"
}

check_shared_validators_accept_and_reject() {
  # Every shared validator in lib/app.sh must accept valid values and reject
  # invalid ones. Validators pin LC_ALL=C internally, so results must be
  # identical under C and under UTF-8 collation locales; run the behavior
  # matrix under each locale whose collation actually differs from C so the
  # pins cannot regress silently.
  "$BASH_BIN" -c '
    set -euo pipefail
    source "$1/lib/logging.sh"
    source "$1/lib/i18n.sh"
    source "$1/lib/network.sh"
    source "$1/lib/app.sh"
    assert_all() {
    # Port
    app_validate_port 8080 "PORT" || { echo "valid port rejected" >&2; exit 1; }
    ( app_validate_port 70000 "PORT" ) 2>/dev/null && { echo "out-of-range port accepted" >&2; exit 1; }
    ( app_validate_port abc "PORT" ) 2>/dev/null && { echo "non-numeric port accepted" >&2; exit 1; }
    # Bool
    app_validate_bool "FLAG" true || { echo "valid bool rejected" >&2; exit 1; }
    app_validate_bool "FLAG" 0 || { echo "valid bool 0 rejected" >&2; exit 1; }
    ( app_validate_bool "FLAG" maybe ) 2>/dev/null && { echo "invalid bool accepted" >&2; exit 1; }
    # Domain (empty is allowed)
    app_validate_domain "DOMAIN" "app.example.com" || { echo "valid domain rejected" >&2; exit 1; }
    app_validate_domain "DOMAIN" "" || { echo "empty domain rejected" >&2; exit 1; }
    ( app_validate_domain "DOMAIN" "bad name" ) 2>/dev/null && { echo "invalid domain accepted" >&2; exit 1; }
    # http(s) URLs
    app_validate_http_url "URL" "http://example.com/path" || { echo "valid http url rejected" >&2; exit 1; }
    app_validate_http_url "URL" "https://api.github.com/v3" || { echo "valid https url rejected" >&2; exit 1; }
    app_validate_http_url "URL" "http://localhost:8080/x" || { echo "localhost url rejected" >&2; exit 1; }
    ( app_validate_http_url "URL" "ftp://example.com" ) 2>/dev/null && { echo "non-http scheme accepted" >&2; exit 1; }
    ( app_validate_http_url "URL" "http://" ) 2>/dev/null && { echo "empty host accepted" >&2; exit 1; }
    ( app_validate_http_url "URL" "http://bad name.com" ) 2>/dev/null && { echo "url with space accepted" >&2; exit 1; }
    app_validate_https_url "URL" "https://example.com" || { echo "valid https-only url rejected" >&2; exit 1; }
    ( app_validate_https_url "URL" "http://example.com" ) 2>/dev/null && { echo "http url accepted by https validator" >&2; exit 1; }
    # Go proxy
    app_validate_goproxy "GOPROXY" "direct" || { echo "goproxy direct rejected" >&2; exit 1; }
    app_validate_goproxy "GOPROXY" "off" || { echo "goproxy off rejected" >&2; exit 1; }
    app_validate_goproxy "GOPROXY" "direct,https://proxy.example.com" || { echo "goproxy list rejected" >&2; exit 1; }
    app_validate_goproxy "GOPROXY" "direct|https://proxy.example.com" || { echo "goproxy pipe list rejected" >&2; exit 1; }
    ( app_validate_goproxy "GOPROXY" "" ) 2>/dev/null && { echo "empty goproxy accepted" >&2; exit 1; }
    ( app_validate_goproxy "GOPROXY" "foo" ) 2>/dev/null && { echo "invalid goproxy token accepted" >&2; exit 1; }
    # Image repo (uppercase must be rejected under LC_ALL=C)
    app_validate_image_repo "REPO" "nginx" || { echo "bare repo rejected" >&2; exit 1; }
    app_validate_image_repo "REPO" "vaultwarden/server" || { echo "org/name repo rejected" >&2; exit 1; }
    app_validate_image_repo "REPO" "docker.io/library/nginx" || { echo "registry repo rejected" >&2; exit 1; }
    app_validate_image_repo "REPO" "localhost:5000/foo" || { echo "localhost repo rejected" >&2; exit 1; }
    ( app_validate_image_repo "REPO" "" ) 2>/dev/null && { echo "empty repo accepted" >&2; exit 1; }
    ( app_validate_image_repo "REPO" "/foo" ) 2>/dev/null && { echo "leading-slash repo accepted" >&2; exit 1; }
    ( app_validate_image_repo "REPO" "foo//bar" ) 2>/dev/null && { echo "double-slash repo accepted" >&2; exit 1; }
    ( app_validate_image_repo "REPO" "foo/.." ) 2>/dev/null && { echo "dotdot repo accepted" >&2; exit 1; }
    ( app_validate_image_repo "REPO" "example.com:70000/foo" ) 2>/dev/null && { echo "out-of-range repo port accepted" >&2; exit 1; }
    ( app_validate_image_repo "REPO" "Foo/bar" ) 2>/dev/null && { echo "uppercase repo accepted" >&2; exit 1; }
    # Image tag
    app_validate_image_tag "TAG" "latest" || { echo "valid tag rejected" >&2; exit 1; }
    app_validate_image_tag "TAG" "1.36.0-alpine" || { echo "version tag rejected" >&2; exit 1; }
    ( app_validate_image_tag "TAG" "" ) 2>/dev/null && { echo "empty tag accepted" >&2; exit 1; }
    ( app_validate_image_tag "TAG" "-bad" ) 2>/dev/null && { echo "leading-dash tag accepted" >&2; exit 1; }
    # SHA-256
    app_validate_sha256 "SHA" "a58f4995f568d66d9908649d4df7fc8c36f72096ca5e01f4c2c4291285125685" || { echo "valid sha256 rejected" >&2; exit 1; }
    ( app_validate_sha256 "SHA" "short" ) 2>/dev/null && { echo "short sha256 accepted" >&2; exit 1; }
    ( app_validate_sha256 "SHA" "zzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz" ) 2>/dev/null && { echo "non-hex sha256 accepted" >&2; exit 1; }
    # Email
    app_validate_email "EMAIL" "admin@example.com" || { echo "valid email rejected" >&2; exit 1; }
    app_validate_email "EMAIL" "user.name+tag@sub.example.com" || { echo "plus-address email rejected" >&2; exit 1; }
    ( app_validate_email "EMAIL" "a b@example.com" ) 2>/dev/null && { echo "email with space accepted" >&2; exit 1; }
    ( app_validate_email "EMAIL" "a@b@example.com" ) 2>/dev/null && { echo "double-at email accepted" >&2; exit 1; }
    ( app_validate_email "EMAIL" "@example.com" ) 2>/dev/null && { echo "empty-local email accepted" >&2; exit 1; }
    ( app_validate_email "EMAIL" "a..b@example.com" ) 2>/dev/null && { echo "dotdot email accepted" >&2; exit 1; }
    # Release version
    app_validate_release_version "VER" "1.2" || { echo "x.y version rejected" >&2; exit 1; }
    app_validate_release_version "VER" "1.2.3" || { echo "x.y.z version rejected" >&2; exit 1; }
    app_validate_release_version "VER" "1.2.3-rc.1" || { echo "prerelease version rejected" >&2; exit 1; }
    ( app_validate_release_version "VER" "" ) 2>/dev/null && { echo "empty version accepted" >&2; exit 1; }
    ( app_validate_release_version "VER" "1" ) 2>/dev/null && { echo "x-only version accepted" >&2; exit 1; }
    ( app_validate_release_version "VER" "v1.2" ) 2>/dev/null && { echo "v-prefixed version accepted" >&2; exit 1; }
    # System and systemd names
    app_validate_system_name "USER" "newapi" || { echo "valid system name rejected" >&2; exit 1; }
    app_validate_system_name "USER" "my_app-2" || { echo "mixed system name rejected" >&2; exit 1; }
    ( app_validate_system_name "USER" "1abc" ) 2>/dev/null && { echo "digit-leading system name accepted" >&2; exit 1; }
    ( app_validate_system_name "USER" "a b" ) 2>/dev/null && { echo "space system name accepted" >&2; exit 1; }
    app_validate_systemd_name "UNIT" "new-api" || { echo "valid unit name rejected" >&2; exit 1; }
    app_validate_systemd_name "UNIT" "foo@bar" || { echo "at unit name rejected" >&2; exit 1; }
    ( app_validate_systemd_name "UNIT" "foo..bar" ) 2>/dev/null && { echo "dotdot unit accepted" >&2; exit 1; }
    ( app_validate_systemd_name "UNIT" "foo/bar" ) 2>/dev/null && { echo "slash unit accepted" >&2; exit 1; }
    # GitHub repo
    app_validate_github_repo "REPO" "owner/repo" || { echo "valid github repo rejected" >&2; exit 1; }
    app_validate_github_repo "REPO" "QuantumNous/new-api" || { echo "real github repo rejected" >&2; exit 1; }
    ( app_validate_github_repo "REPO" "owner" ) 2>/dev/null && { echo "slashless github repo accepted" >&2; exit 1; }
    ( app_validate_github_repo "REPO" "owner/repo/extra" ) 2>/dev/null && { echo "multi-segment github repo accepted" >&2; exit 1; }
    ( app_validate_github_repo "REPO" "owner/.hidden" ) 2>/dev/null && { echo "hidden-segment github repo accepted" >&2; exit 1; }
    # Git ref
    app_validate_git_ref "REF" "main" || { echo "valid git ref rejected" >&2; exit 1; }
    app_validate_git_ref "REF" "feature/foo" || { echo "slash git ref rejected" >&2; exit 1; }
    ( app_validate_git_ref "REF" "-bad" ) 2>/dev/null && { echo "leading-dash git ref accepted" >&2; exit 1; }
    ( app_validate_git_ref "REF" "foo@{1}" ) 2>/dev/null && { echo "at-brace git ref accepted" >&2; exit 1; }
    ( app_validate_git_ref "REF" "foo..bar" ) 2>/dev/null && { echo "dotdot git ref accepted" >&2; exit 1; }
    ( app_validate_git_ref "REF" "a b" ) 2>/dev/null && { echo "space git ref accepted" >&2; exit 1; }
    # DB identifier
    app_validate_db_identifier "DB" "my_db" || { echo "valid db identifier rejected" >&2; exit 1; }
    app_validate_db_identifier "DB" "_private" || { echo "underscore db identifier rejected" >&2; exit 1; }
    ( app_validate_db_identifier "DB" "1abc" ) 2>/dev/null && { echo "digit-leading db identifier accepted" >&2; exit 1; }
    ( app_validate_db_identifier "DB" "a-b" ) 2>/dev/null && { echo "dash db identifier accepted" >&2; exit 1; }
    # Strict-ASCII rejections: character-range regexes must not match accented
    # Latin characters on any locale (validators pin LC_ALL=C internally).
    ( app_validate_domain "DOMAIN" "éxample.com" ) 2>/dev/null && { echo "accented domain accepted" >&2; exit 1; }
    ( app_validate_http_url "URL" "http://éxample.com" ) 2>/dev/null && { echo "accented url host accepted" >&2; exit 1; }
    ( app_validate_image_tag "TAG" "v1.2-é" ) 2>/dev/null && { echo "accented image tag accepted" >&2; exit 1; }
    ( app_validate_email "EMAIL" "é@example.com" ) 2>/dev/null && { echo "accented email local part accepted" >&2; exit 1; }
    ( app_validate_release_version "VER" "1.2-é" ) 2>/dev/null && { echo "accented release version accepted" >&2; exit 1; }
    ( app_validate_system_name "USER" "néwapi" ) 2>/dev/null && { echo "accented system name accepted" >&2; exit 1; }
    ( app_validate_systemd_name "UNIT" "néw-api" ) 2>/dev/null && { echo "accented systemd name accepted" >&2; exit 1; }
    ( app_validate_github_repo "REPO" "owner/répo" ) 2>/dev/null && { echo "accented github repo accepted" >&2; exit 1; }
    ( app_validate_git_ref "REF" "feature/é" ) 2>/dev/null && { echo "accented git ref accepted" >&2; exit 1; }
    ( app_validate_db_identifier "DB" "néw_db" ) 2>/dev/null && { echo "accented db identifier accepted" >&2; exit 1; }
    return 0
  }
  for locale in C en_US.UTF-8 zh_CN.UTF-8; do
    export LC_ALL="$locale"
    if [[ "$locale" == "C" ]] || [[ "é" =~ ^[A-Za-z]+$ ]]; then
      assert_all
    fi
  done
  exit 0
  ' _ "$ROOT_DIR"
}

check_connectivity_helper_behavior() {
  "$BASH_BIN" -c '
    set -euo pipefail
    source "$1/lib/logging.sh"
    source "$1/lib/i18n.sh"
    source "$1/lib/network.sh"
    curl() { return 0; }
    app_check_connectivity "test.warn" "https://example.test" \
      || { echo "reachable endpoint failed" >&2; exit 1; }
    curl() { return 1; }
    ( app_check_connectivity "test.warn" "https://example.test" ) 2>/dev/null \
      && { echo "unreachable endpoints did not abort" >&2; exit 1; }
    exit 0
  ' _ "$ROOT_DIR"
}

check_port_listening_process_behavior() {
  "$BASH_BIN" -c '
    set -euo pipefail
    source "$1/lib/network.sh"
    # Empty ss output must not report an owner (returns 1).
    ss() { return 0; }
    lsof() { return 0; }
    ( port_listening_process 8080 ) 2>/dev/null \
      && { echo "empty ss output must not report an owner" >&2; exit 1; }
    # A realistic ss users column must yield the process name.
    ss() { printf "State Recv-Q Send-Q Local Address:Port Peer Address:Port Process\nLISTEN 0 511 0.0.0.0:8080 0.0.0.0:* users:((\"nginx\",pid=123,fd=10))\n"; }
    [[ "$(port_listening_process 8080)" == "nginx" ]] \
      || { echo "ss process name extraction failed" >&2; exit 1; }
    # lsof branch (only reachable when ss is absent).
    if ! command -v ss >/dev/null 2>&1; then
      lsof() { printf "COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME\nnginx 123 root 9u IPv4 12345 0t0 TCP *:8080 (LISTEN)\n"; }
      [[ "$(port_listening_process 8080)" == "nginx" ]] \
        || { echo "lsof process name extraction failed" >&2; exit 1; }
      lsof() { return 0; }
      ( port_listening_process 8080 ) 2>/dev/null \
        && { echo "empty lsof output must not report an owner" >&2; exit 1; }
    fi
    exit 0
  ' _ "$ROOT_DIR"
}

check_app_json_string_escapes_controls() {
  "$BASH_BIN" -c '
    set -euo pipefail
    source "$1/lib/app.sh"
    out="$(app_json_string "$(printf "a\tb\nc\rd\x08e\x0cf")")"
    [[ "$out" == "\"a\\tb\\nc\\rd\\be\\ff\"" ]] \
      || { echo "control escapes wrong: $out" >&2; exit 1; }
    out="$(app_json_string "quote\"back\\slash")"
    [[ "$out" == "\"quote\\\"back\\\\slash\"" ]] \
      || { echo "quote/backslash escapes wrong: $out" >&2; exit 1; }
    out="$(app_json_string "$(printf "x\x1fy")")"
    [[ "$out" == "\"x\\u001fy\"" ]] \
      || { echo "remaining C0 escape wrong: $out" >&2; exit 1; }
    exit 0
  ' _ "$ROOT_DIR"
}
