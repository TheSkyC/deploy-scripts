#!/usr/bin/env bash

CPA_DOMAIN="${CPA_DOMAIN:-}"
CPAMP_DOMAIN="${CPAMP_DOMAIN:-}"
ENABLE_HTTPS="${ENABLE_HTTPS:-true}"
CPA_ALLOW_REMOTE="${CPA_ALLOW_REMOTE:-true}"
CERTBOT_EMAIL="${CERTBOT_EMAIL:-}"
CPA_STACK_COMPONENT="${CPA_STACK_COMPONENT:-all}"
CPA_MANAGEMENT_KEY="${CPA_MANAGEMENT_KEY:-}"
CPA_API_KEY="${CPA_API_KEY:-}"
CPAMP_ADMIN_KEY="${CPAMP_ADMIN_KEY:-}"
CPA_STACK_BACKUP_DIR="${CPA_STACK_BACKUP_DIR:-/opt/cpa-stack-backups}"
BACKUP_KEEP_DAYS="${BACKUP_KEEP_DAYS:-30}"

CPA_REPOSITORY="router-for-me/CLIProxyAPI"
CPAMP_REPOSITORY="seakee/CPA-Manager-Plus"
CPA_SERVICE_NAME="cli-proxy-api"
CPAMP_SERVICE_NAME="cpa-manager-plus"
CPA_SERVICE_USER="cli-proxy-api"
CPAMP_SERVICE_USER="cpa-manager-plus"
CPA_INSTALL_DIR="/opt/cli-proxy-api"
CPAMP_INSTALL_DIR="/opt/cpa-manager-plus"
CPA_CONFIG_DIR="/etc/cli-proxy-api"
CPA_CONFIG_FILE="${CPA_CONFIG_DIR}/config.yaml"
CPA_DATA_DIR="/var/lib/cli-proxy-api"
CPA_AUTH_DIR="${CPA_DATA_DIR}/auths"
CPAMP_DATA_DIR="/var/lib/cpa-manager-plus"
CPAMP_ENV_DIR="/etc/cpa-stack"
CPAMP_ENV_FILE="${CPAMP_ENV_DIR}/cpamp.env"
CPA_BIN="${CPA_INSTALL_DIR}/cli-proxy-api"
CPAMP_BIN="${CPAMP_INSTALL_DIR}/cpa-manager-plus"
NGINX_SITE="/etc/nginx/sites-available/cpa-stack"
NGINX_SITE_LINK="/etc/nginx/sites-enabled/cpa-stack"
NGINX_MAP_FILE="/etc/nginx/conf.d/cpa-stack-connection-upgrade.conf"
ACME_WEBROOT="/var/www/certbot"

CONFIG_KEYS=(
  CPA_DOMAIN
  CPAMP_DOMAIN
  ENABLE_HTTPS
  CPA_ALLOW_REMOTE
  CERTBOT_EMAIL
  CPA_STACK_BACKUP_DIR
  BACKUP_KEEP_DAYS
)

CONF_FILE="$(app_conf_file)"
LOCK_FILE="$(app_lock_file)"

_cpa_stack_doctor_primary_service() {
  printf '%s\n' "$CPA_SERVICE_NAME"
}
_cpa_stack_doctor_services() {
  printf '%s\n' "$CPA_SERVICE_NAME" "$CPAMP_SERVICE_NAME" nginx
}
APP_DOCTOR_SERVICE_FN=_cpa_stack_doctor_primary_service
APP_DOCTOR_SERVICES_FN=_cpa_stack_doctor_services

cpa_stack_show_banner() {
  echo -e "${BOLD}$(t app.cpa_stack.banner)${NC}"
}

cpa_stack_truthy() {
  case "${1,,}" in
    1|true|yes|y|on) return 0 ;;
    *) return 1 ;;
  esac
}

cpa_stack_component_includes() {
  local component="$1"
  [[ "$CPA_STACK_COMPONENT" == "all" || "$CPA_STACK_COMPONENT" == "$component" ]]
}

cpa_stack_validate_component() {
  case "$CPA_STACK_COMPONENT" in
    all|cpa|cpamp) ;;
    *) error "$(t app.cpa_stack.error.component "$CPA_STACK_COMPONENT")" ;;
  esac
}

_validate_config_values() {
  app_validate_domain "CPA_DOMAIN" "$CPA_DOMAIN"
  app_validate_domain "CPAMP_DOMAIN" "$CPAMP_DOMAIN"
  app_validate_bool "ENABLE_HTTPS" "$ENABLE_HTTPS"
  app_validate_bool "CPA_ALLOW_REMOTE" "$CPA_ALLOW_REMOTE"
  if [[ -n "${CERTBOT_EMAIL:-}" ]]; then
    app_validate_email "CERTBOT_EMAIL" "$CERTBOT_EMAIL"
  fi
  [[ "$BACKUP_KEEP_DAYS" =~ ^[0-9]+$ ]] || error "$(t app.cpa_stack.error.keep_days)"
  require_safe_path "CPA_STACK_BACKUP_DIR" "$CPA_STACK_BACKUP_DIR"
  if [[ -n "$CPA_DOMAIN" && "$CPA_DOMAIN" == "$CPAMP_DOMAIN" ]]; then
    error "$(t app.cpa_stack.error.domains_same)"
  fi
}

cpa_stack_require_domains() {
  while [[ -z "$CPA_DOMAIN" ]]; do
    prompt "$(t app.cpa_stack.prompt.cpa_domain)"
    read -r CPA_DOMAIN
    if ! is_valid_dns_name "$CPA_DOMAIN"; then
      warn "$(t app.cpa_stack.error.domain_invalid "CPA_DOMAIN" "$CPA_DOMAIN")"
      CPA_DOMAIN=""
    fi
  done
  while [[ -z "$CPAMP_DOMAIN" ]]; do
    prompt "$(t app.cpa_stack.prompt.cpamp_domain)"
    read -r CPAMP_DOMAIN
    if ! is_valid_dns_name "$CPAMP_DOMAIN"; then
      warn "$(t app.cpa_stack.error.domain_invalid "CPAMP_DOMAIN" "$CPAMP_DOMAIN")"
      CPAMP_DOMAIN=""
    fi
  done
  _validate_config_values
  if cpa_stack_truthy "$ENABLE_HTTPS" && [[ -z "$CERTBOT_EMAIL" ]]; then
    if deploy_assume_yes; then
      error "$(t app.cpa_stack.error.noninteractive_email)"
    else
      while true; do
        prompt "$(t app.cpa_stack.prompt.email)"
        local _email; read -r _email
        [[ -z "$_email" ]] && { warn "$(t app.cpa_stack.warn.email_empty)"; continue; }
        if ! app_is_valid_email "$_email"; then
          warn "$(t app.cpa_stack.warn.email_invalid "$_email")"
          continue
        fi
        CERTBOT_EMAIL="$_email"
        break
      done
    fi
  fi
}

cpa_stack_preflight() {
  local action="${1:-}"
  if [[ "$action" != "status" && "$action" != "doctor" ]]; then
    require_root "$action"
  fi
  if [[ "$action" != "status" && "$action" != "doctor" ]] && ! command -v apt-get >/dev/null 2>&1; then
    error "$(t app.cpa_stack.error.apt_only)"
  fi
  if [[ "$action" != "status" && "$action" != "doctor" ]] && ! command -v systemctl >/dev/null 2>&1; then
    error "$(t app.cpa_stack.error.systemd_required)"
  fi
  cpa_stack_validate_component
  app_load_config
}

cpa_stack_arch() {
  case "$(uname -m)" in
    x86_64|amd64) printf '%s\n' amd64 ;;
    aarch64|arm64) printf '%s\n' arm64 ;;
    *) error "$(t app.cpa_stack.error.arch "$(uname -m)")" ;;
  esac
}

cpa_stack_cpa_asset_name() {
  local tag="$1" arch="$2"
  case "$arch" in
    amd64) printf 'CLIProxyAPI_%s_linux_amd64.tar.gz\n' "${tag#v}" ;;
    arm64) printf 'CLIProxyAPI_%s_linux_aarch64.tar.gz\n' "${tag#v}" ;;
  esac
}

cpa_stack_cpamp_asset_name() {
  local tag="$1" arch="$2"
  case "$arch" in
    amd64) printf 'cpa-manager-plus_%s_linux_amd64.tar.gz\n' "$tag" ;;
    arm64) printf 'cpa-manager-plus_%s_linux_arm64.tar.gz\n' "$tag" ;;
  esac
}

cpa_stack_release_json() {
  local repository="$1"
  curl -fsSL --retry 2 --connect-timeout 10 --max-time 30 \
    -H 'Accept: application/vnd.github+json' \
    -H 'User-Agent: deploy-scripts-cpa-stack' \
    "https://api.github.com/repos/${repository}/releases/latest"
}

cpa_stack_release_tag() {
  json_tag_name "$1"
}

cpa_stack_release_asset_url() {
  local json="$1" asset="$2" compact remainder after_asset
  compact="$(printf '%s' "$json" | tr -d '\r\n\t ' )"
  after_asset="${compact#*\"name\":\""${asset}"\"}"
  [[ "$after_asset" != "$compact" ]] || return 0
  remainder="${after_asset#*\"browser_download_url\":\"}"
  [[ "$remainder" != "$after_asset" ]] || return 0
  printf '%s\n' "${remainder%%\"*}"
}
cpa_stack_download_verified_archive() {
  local repository="$1" tag="$2" asset="$3" destination="$4"
  local checksum_url archive_url checksum_file expected actual
  checksum_url="https://github.com/${repository}/releases/download/${tag}/checksums.txt"
  archive_url="https://github.com/${repository}/releases/download/${tag}/${asset}"
  checksum_file="${destination}.checksums"

  if ! curl -fL --retry 2 --connect-timeout 10 --max-time 180 -H 'User-Agent: deploy-scripts-cpa-stack' -o "$destination" "$archive_url"; then
    rm -f "$destination" "$checksum_file"
    error "$(t app.cpa_stack.error.download "$asset")"
  fi
  if ! curl -fsSL --retry 2 --connect-timeout 10 --max-time 30 -H 'User-Agent: deploy-scripts-cpa-stack' -o "$checksum_file" "$checksum_url"; then
    rm -f "$destination" "$checksum_file"
    error "$(t app.cpa_stack.error.download "checksums.txt")"
  fi
  expected="$(awk -v asset="$asset" '$NF == asset || $NF == "./" asset { print $1; exit }' "$checksum_file")"
  actual="$(sha256sum "$destination" | awk '{print $1}')"
  rm -f "$checksum_file"
  if [[ -z "$expected" || "$expected" != "$actual" ]]; then
    rm -f "$destination"
    error "$(t app.cpa_stack.error.checksum "$asset")"
  fi
}

cpa_stack_install_binary() {
  local source="$1" target="$2" owner="$3" backup
  [[ -s "$source" ]] || error "$(t app.cpa_stack.error.binary_missing "$(basename "$target")" "$(dirname "$source")")"
  backup="${target}.bak.$(date +%Y%m%d_%H%M%S)"
  if [[ -f "$target" ]] && ! cp -a "$target" "$backup"; then
    error "$(t app.cpa_stack.error.binary_backup "$target")"
  fi
  if ! atomic_copy_file "$source" "$target" 0755 "$owner"; then
    [[ -f "$backup" ]] && cp -a "$backup" "$target" || true
    error "$(t app.cpa_stack.error.binary_install "$target")"
  fi
}

cpa_stack_install_release() {
  local component="$1" repository tag arch asset json archive extract_dir binary
  case "$component" in
    cpa)
      repository="$CPA_REPOSITORY"
      ;;
    cpamp)
      repository="$CPAMP_REPOSITORY"
      ;;
    *) return 1 ;;
  esac
  json="$(cpa_stack_release_json "$repository" 2>/dev/null)" || error "$(t app.cpa_stack.error.github "$repository")"
  tag="$(cpa_stack_release_tag "$json")"
  [[ -n "$tag" ]] || error "$(t app.cpa_stack.error.github "$repository")"
  arch="$(cpa_stack_arch)"
  if [[ "$component" == "cpa" ]]; then
    asset="$(cpa_stack_cpa_asset_name "$tag" "$arch")"
  else
    asset="$(cpa_stack_cpamp_asset_name "$tag" "$arch")"
  fi
  [[ -n "$(cpa_stack_release_asset_url "$json" "$asset")" ]] || error "$(t app.cpa_stack.error.release_asset "$tag" "$repository" "$asset")"
  step "$(t app.cpa_stack.step.download "$component" "$tag")"
  archive="$(mktemp "/tmp/${component}.XXXXXX")" || error "$(t app.cpa_stack.error.download "$asset")"
  extract_dir="$(mktemp -d "/tmp/${component}.XXXXXX")" || { rm -f "$archive"; error "$(t app.cpa_stack.error.extract "$asset")"; }
  if ! cpa_stack_download_verified_archive "$repository" "$tag" "$asset" "$archive"; then
    rm -f "$archive"; rm -rf "$extract_dir"; return 1
  fi
  if ! tar -xzf "$archive" -C "$extract_dir"; then
    rm -f "$archive"; rm -rf "$extract_dir"; error "$(t app.cpa_stack.error.extract "$asset")"
  fi
  if [[ "$component" == "cpa" ]]; then
    binary="$(find "$extract_dir" -type f -name cli-proxy-api -print -quit)"
    [[ -n "$binary" ]] || { rm -f "$archive"; rm -rf "$extract_dir"; error "$(t app.cpa_stack.error.binary_missing "cli-proxy-api" "$asset")"; }
    cpa_stack_install_binary "$binary" "$CPA_BIN" "${CPA_SERVICE_USER}:${CPA_SERVICE_USER}"
  else
    binary="$(find "$extract_dir" -type f -name cpa-manager-plus -print -quit)"
    [[ -n "$binary" ]] || { rm -f "$archive"; rm -rf "$extract_dir"; error "$(t app.cpa_stack.error.binary_missing "cpa-manager-plus" "$asset")"; }
    cpa_stack_install_binary "$binary" "$CPAMP_BIN" "${CPAMP_SERVICE_USER}:${CPAMP_SERVICE_USER}"
  fi
  rm -f "$archive"
  rm -rf "$extract_dir"
}

cpa_stack_ensure_user() {
  local user="$1"
  if ! id "$user" >/dev/null 2>&1; then
    useradd --system --no-create-home --shell /usr/sbin/nologin "$user" \
      || error "$(t app.cpa_stack.error.user "$user")"
  fi
}

cpa_stack_prepare_runtime() {
  step "$(t app.cpa_stack.step.users)"
  cpa_stack_ensure_user "$CPA_SERVICE_USER"
  cpa_stack_ensure_user "$CPAMP_SERVICE_USER"
  local path owner
  while IFS='|' read -r path owner; do
    if ! mkdir -p "$path" || ! chown "$owner" "$path"; then
      error "$(t app.cpa_stack.error.directory "$path")"
    fi
  done <<EOF
$CPA_INSTALL_DIR|$CPA_SERVICE_USER:$CPA_SERVICE_USER
$CPA_CONFIG_DIR|root:$CPA_SERVICE_USER
$CPA_DATA_DIR|$CPA_SERVICE_USER:$CPA_SERVICE_USER
$CPA_AUTH_DIR|$CPA_SERVICE_USER:$CPA_SERVICE_USER
$CPAMP_INSTALL_DIR|$CPAMP_SERVICE_USER:$CPAMP_SERVICE_USER
$CPAMP_DATA_DIR|$CPAMP_SERVICE_USER:$CPAMP_SERVICE_USER
$CPAMP_ENV_DIR|root:root
$CPA_STACK_BACKUP_DIR|root:root
$ACME_WEBROOT|www-data:www-data
EOF
  chmod 0770 "$CPA_CONFIG_DIR" || true
  chmod 0750 "$CPA_DATA_DIR" "$CPA_AUTH_DIR" "$CPAMP_DATA_DIR" || true
  chmod 0700 "$CPAMP_ENV_DIR" "$CPA_STACK_BACKUP_DIR" || true
  [[ -f "$CPA_CONFIG_FILE" ]] && chmod 0660 "$CPA_CONFIG_FILE" 2>/dev/null || true
}

cpa_stack_random_key() {
  local prefix="$1"
  printf '%s%s\n' "$prefix" "$(openssl rand -hex 32)"
}

cpa_stack_write_cpa_config() {
  if [[ -f "$CPA_CONFIG_FILE" ]]; then
    warn "$(t app.cpa_stack.warn.config_preserved "$CPA_CONFIG_FILE")"
    if [[ -z "$CPA_MANAGEMENT_KEY" ]]; then
      local prior
      prior="$(sed -nE 's/^[[:space:]]*secret-key:[[:space:]]*"([^"]+)".*/\1/p' "$CPA_CONFIG_FILE" | tail -n 1)"
      [[ -n "$prior" ]] && CPA_MANAGEMENT_KEY="$prior"
    fi
    [[ -n "$CPA_MANAGEMENT_KEY" ]] || error "$(t app.cpa_stack.error.config_exists "$CPA_CONFIG_FILE")"
    return 0
  fi
  [[ -n "$CPA_MANAGEMENT_KEY" ]] || CPA_MANAGEMENT_KEY="$(cpa_stack_random_key 'cpa_')"
  [[ -n "$CPA_API_KEY" ]] || CPA_API_KEY="$(cpa_stack_random_key 'sk-')"
  if ! cat <<EOF | atomic_write_file "$CPA_CONFIG_FILE" 0660 "root:${CPA_SERVICE_USER}"
host: "127.0.0.1"
port: 8317

auth-dir: "${CPA_AUTH_DIR}"

api-keys:
  - "${CPA_API_KEY}"

usage-statistics-enabled: true

remote-management:
  # CPAMP's web panel calls the CPA management API from the browser over the
  # public domain; CPA rejects non-loopback clients unless allow-remote is
  # true. Keep false only when the panel is never used from a browser.
  allow-remote: ${CPA_ALLOW_REMOTE}
  secret-key: "${CPA_MANAGEMENT_KEY}"
EOF
  then
    error "$(t app.cpa_stack.error.config_write "$CPA_CONFIG_FILE")"
  fi
  if ! cpa_stack_truthy "$CPA_ALLOW_REMOTE"; then
    warn "$(t app.cpa_stack.warn.remote_disabled)"
  fi
}

cpa_stack_load_cpamp_env() {
  local prior_admin="" prior_management="" prior_upstream=""
  if [[ -f "$CPAMP_ENV_FILE" ]]; then
    load_config_file "$CPAMP_ENV_FILE" CPA_MANAGER_ADMIN_KEY CPA_MANAGEMENT_KEY CPA_UPSTREAM_URL || true
    prior_admin="${CPA_MANAGER_ADMIN_KEY:-}"
    prior_management="${CPA_MANAGEMENT_KEY:-}"
    prior_upstream="${CPA_UPSTREAM_URL:-}"
  fi
  [[ -n "$CPAMP_ADMIN_KEY" ]] || CPAMP_ADMIN_KEY="$prior_admin"
  [[ -n "$CPA_MANAGEMENT_KEY" ]] || CPA_MANAGEMENT_KEY="$prior_management"
  [[ -n "$CPA_MANAGEMENT_KEY" ]] || error "$(t app.cpa_stack.error.management_key_required)"
  [[ -n "$CPAMP_ADMIN_KEY" ]] || CPAMP_ADMIN_KEY="$(cpa_stack_random_key 'cpamp_')"
  CPA_UPSTREAM_URL="${prior_upstream:-http://127.0.0.1:8317}"
}

cpa_stack_write_cpamp_env() {
  cpa_stack_load_cpamp_env
  CPA_MANAGER_ADMIN_KEY="$CPAMP_ADMIN_KEY"
  if ! write_config_file "$CPAMP_ENV_FILE" \
    CPA_MANAGER_ADMIN_KEY CPA_UPSTREAM_URL CPA_MANAGEMENT_KEY; then
    error "$(t app.cpa_stack.error.cpamp_env_write "$CPAMP_ENV_FILE")"
  fi
}

cpa_stack_write_services() {
  step "$(t app.cpa_stack.step.services)"
  if ! cat <<EOF | systemd_write_unit "/etc/systemd/system/${CPA_SERVICE_NAME}.service"
[Unit]
Description=CLIProxyAPI
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${CPA_SERVICE_USER}
Group=${CPA_SERVICE_USER}
WorkingDirectory=${CPA_INSTALL_DIR}
ExecStart=${CPA_BIN} -config ${CPA_CONFIG_FILE}
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF
  then
    error "$(t app.cpa_stack.error.service "$CPA_SERVICE_NAME")"
  fi
  if ! cat <<EOF | systemd_write_unit "/etc/systemd/system/${CPAMP_SERVICE_NAME}.service"
[Unit]
Description=CPA Manager Plus Manager Server
After=network-online.target ${CPA_SERVICE_NAME}.service
Wants=network-online.target

[Service]
Type=simple
User=${CPAMP_SERVICE_USER}
Group=${CPAMP_SERVICE_USER}
WorkingDirectory=${CPAMP_INSTALL_DIR}
Environment=HTTP_ADDR=127.0.0.1:18317
Environment=USAGE_DATA_DIR=${CPAMP_DATA_DIR}
EnvironmentFile=${CPAMP_ENV_FILE}
ExecStart=${CPAMP_BIN}
Restart=on-failure
RestartSec=3
NoNewPrivileges=true
PrivateTmp=true
ProtectHome=true

[Install]
WantedBy=multi-user.target
EOF
  then
    error "$(t app.cpa_stack.error.service "$CPAMP_SERVICE_NAME")"
  fi
  systemctl daemon-reload || error "$(t app.cpa_stack.error.service "$CPA_SERVICE_NAME")"
  systemctl enable "$CPA_SERVICE_NAME" "$CPAMP_SERVICE_NAME" >/dev/null \
    || error "$(t app.cpa_stack.error.service "$CPA_SERVICE_NAME")"
  systemctl restart "$CPA_SERVICE_NAME" || error "$(t app.cpa_stack.error.service "$CPA_SERVICE_NAME")"
  wait_for_service "$CPA_SERVICE_NAME" 20 || error "$(t app.cpa_stack.error.service "$CPA_SERVICE_NAME")"
  systemctl restart "$CPAMP_SERVICE_NAME" || error "$(t app.cpa_stack.error.service "$CPAMP_SERVICE_NAME")"
  wait_for_service "$CPAMP_SERVICE_NAME" 20 || error "$(t app.cpa_stack.error.service "$CPAMP_SERVICE_NAME")"
}

cpa_stack_nginx_common_headers() {
  cat <<'EOF'
    client_max_body_size 64m;
    proxy_http_version 1.1;
    proxy_read_timeout 3600s;
    proxy_send_timeout 3600s;
    proxy_buffering off;

    proxy_set_header Host              $host;
    proxy_set_header X-Real-IP         $remote_addr;
    proxy_set_header X-Forwarded-For   $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header Upgrade           $http_upgrade;
    proxy_set_header Connection        $cpa_stack_connection_upgrade;
EOF
}

cpa_stack_write_nginx_http() {
  step "$(t app.cpa_stack.step.nginx)"
  mkdir -p /etc/nginx/conf.d /etc/nginx/sites-available /etc/nginx/sites-enabled "$ACME_WEBROOT" \
    || error "$(t app.cpa_stack.error.nginx "$NGINX_SITE")"
  if ! cat <<'EOF' | atomic_write_file "$NGINX_MAP_FILE" 0644 root:root
map $http_upgrade $cpa_stack_connection_upgrade {
    default upgrade;
    ''      close;
}
EOF
  then
    error "$(t app.cpa_stack.error.nginx "$NGINX_MAP_FILE")"
  fi
  if ! cat <<EOF | atomic_write_file "$NGINX_SITE" 0644 root:root
server {
    listen 80;
    listen [::]:80;
    server_name ${CPA_DOMAIN};

    location /.well-known/acme-challenge/ {
        root ${ACME_WEBROOT};
    }

$(cpa_stack_nginx_common_headers)
    location / {
        proxy_pass http://127.0.0.1:8317;
    }
}

server {
    listen 80;
    listen [::]:80;
    server_name ${CPAMP_DOMAIN};

    location /.well-known/acme-challenge/ {
        root ${ACME_WEBROOT};
    }

$(cpa_stack_nginx_common_headers)
    location = / {
        return 302 /management.html;
    }

    location / {
        proxy_pass http://127.0.0.1:18317;
    }
}
EOF
  then
    error "$(t app.cpa_stack.error.nginx "$NGINX_SITE")"
  fi
  atomic_symlink "$NGINX_SITE" "$NGINX_SITE_LINK" \
    || error "$(t app.cpa_stack.error.nginx "$NGINX_SITE_LINK")"
  nginx -t || error "$(t app.cpa_stack.error.nginx "$NGINX_SITE")"
  systemctl enable nginx >/dev/null || true
  systemctl restart nginx || error "$(t app.cpa_stack.error.nginx "$NGINX_SITE")"
}

cpa_stack_nginx_http2_directives() {
  local version
  version="$(nginx -v 2>&1 | sed -nE 's/.*nginx\/([0-9]+\.[0-9]+\.[0-9]+).*/\1/p')"
  if [[ -n "$version" ]] && awk -v v="$version" 'BEGIN { split(v, a, "."); exit !(a[1]*10000 + a[2]*100 + a[3] >= 12501) }'; then
    cat <<'EOF'
    listen 443 ssl;
    listen [::]:443 ssl;
    http2 on;
EOF
  else
    cat <<'EOF'
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
EOF
  fi
}

cpa_stack_write_nginx_https() {
  local cert_dir="/etc/letsencrypt/live/${CPA_DOMAIN}"
  [[ -f "${cert_dir}/fullchain.pem" && -f "${cert_dir}/privkey.pem" ]] || return 1
  if ! cat <<EOF | atomic_write_file "$NGINX_SITE" 0644 root:root
server {
    listen 80;
    listen [::]:80;
    server_name ${CPA_DOMAIN};

    location /.well-known/acme-challenge/ {
        root ${ACME_WEBROOT};
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
$(cpa_stack_nginx_http2_directives)
    server_name ${CPA_DOMAIN};

    ssl_certificate ${cert_dir}/fullchain.pem;
    ssl_certificate_key ${cert_dir}/privkey.pem;

$(cpa_stack_nginx_common_headers)
    location / {
        proxy_pass http://127.0.0.1:8317;
    }
}

server {
    listen 80;
    listen [::]:80;
    server_name ${CPAMP_DOMAIN};

    location /.well-known/acme-challenge/ {
        root ${ACME_WEBROOT};
    }

    location / {
        return 301 https://\$host\$request_uri;
    }
}

server {
$(cpa_stack_nginx_http2_directives)
    server_name ${CPAMP_DOMAIN};

    ssl_certificate ${cert_dir}/fullchain.pem;
    ssl_certificate_key ${cert_dir}/privkey.pem;

$(cpa_stack_nginx_common_headers)
    location = / {
        return 302 /management.html;
    }

    location / {
        proxy_pass http://127.0.0.1:18317;
    }
}
EOF
  then
    return 1
  fi
  nginx -t && systemctl reload nginx
}

cpa_stack_configure_https() {
  cpa_stack_truthy "$ENABLE_HTTPS" || return 0
  step "$(t app.cpa_stack.step.https)"
  if ! certbot certonly --webroot -w "$ACME_WEBROOT" \
      --email "$CERTBOT_EMAIL" --agree-tos --non-interactive \
      -d "$CPA_DOMAIN" -d "$CPAMP_DOMAIN"; then
    warn "$(t app.cpa_stack.warn.certbot "$CPA_DOMAIN" "$CPAMP_DOMAIN")"
    return 0
  fi
  cpa_stack_write_nginx_https || error "$(t app.cpa_stack.error.nginx "$NGINX_SITE")"
}

cpa_stack_install_dependencies() {
  step "$(t app.cpa_stack.step.dependencies)"
  apt-get update -qq || warn "apt-get update failed; package installation may fail."
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \
    curl ca-certificates nginx certbot python3-certbot-nginx openssl \
    || error "$(t app.cpa_stack.error.deps)"
}

cpa_stack_stop_components() {
  if cpa_stack_component_includes cpamp; then
    systemctl stop "$CPAMP_SERVICE_NAME" >/dev/null 2>&1 || true
  fi
  if cpa_stack_component_includes cpa; then
    systemctl stop "$CPA_SERVICE_NAME" >/dev/null 2>&1 || true
  fi
}

cpa_stack_verify_health() {
  local name="$1" url="$2" code
  command -v curl >/dev/null 2>&1 || return 0
  code="$(curl -sS -o /dev/null -w '%{http_code}' --max-time 8 "$url" 2>/dev/null || echo 000)"
  if [[ "$code" =~ ^2 ]]; then
    success "$(t app.cpa_stack.success.health "$name" "$code")"
  else
    warn "$(t app.cpa_stack.warn.http_health "$name" "$code")"
  fi
}

cpa_stack_prune_backups() {
  find "$CPA_STACK_BACKUP_DIR" -maxdepth 1 -type f -name 'cpa-stack-*.tar.gz' -mtime "+${BACKUP_KEEP_DAYS}" -delete 2>/dev/null || true
}

do_install() {
  cpa_stack_show_banner
  cpa_stack_preflight install
  acquire_lock
  cpa_stack_require_domains
  app_save_config
  cpa_stack_install_dependencies
  cpa_stack_prepare_runtime
  step "$(t app.cpa_stack.step.config)"
  cpa_stack_write_cpa_config
  cpa_stack_write_cpamp_env
  cpa_stack_stop_components
  cpa_stack_install_release cpa
  cpa_stack_install_release cpamp
  cpa_stack_write_services
  cpa_stack_write_nginx_http
  cpa_stack_configure_https
  cpa_stack_verify_health CPA http://127.0.0.1:8317/healthz
  cpa_stack_verify_health CPAMP http://127.0.0.1:18317/health
  local scheme="http"
  cpa_stack_truthy "$ENABLE_HTTPS" && [[ -f "/etc/letsencrypt/live/${CPA_DOMAIN}/fullchain.pem" ]] && scheme="https"
  success "$(t app.cpa_stack.success.installed "${scheme}://${CPA_DOMAIN}" "${scheme}://${CPAMP_DOMAIN}")"
  info "$(t app.cpa_stack.info.oauth)"
  info "$(t app.cpa_stack.info.login_command "$CPA_SERVICE_USER" "$CPA_BIN" "$CPA_CONFIG_FILE")"
}

do_update() {
  cpa_stack_show_banner
  cpa_stack_preflight update
  acquire_lock
  [[ -f "$CPA_CONFIG_FILE" ]] || error "$(t app.cpa_stack.warn.config_missing "$CPA_CONFIG_FILE")"
  cpa_stack_install_dependencies
  cpa_stack_prepare_runtime
  cpa_stack_stop_components
  if cpa_stack_component_includes cpa; then
    cpa_stack_install_release cpa
  fi
  if cpa_stack_component_includes cpamp; then
    cpa_stack_install_release cpamp
  fi
  cpa_stack_write_services
  cpa_stack_write_nginx_http
  cpa_stack_configure_https
  cpa_stack_verify_health CPA http://127.0.0.1:8317/healthz
  cpa_stack_verify_health CPAMP http://127.0.0.1:18317/health
  success "$(t app.cpa_stack.success.updated)"
}

do_cert() {
  cpa_stack_show_banner
  cpa_stack_preflight cert
  acquire_lock
  if ! cpa_stack_truthy "$ENABLE_HTTPS"; then
    error "$(t app.cpa_stack.error.https_disabled)"
  fi
  [[ -n "$CERTBOT_EMAIL" ]] || error "$(t app.cpa_stack.error.email_required)"
  cpa_stack_install_dependencies
  cpa_stack_write_nginx_http
  cpa_stack_configure_https
  cpa_stack_verify_health CPA http://127.0.0.1:8317/healthz
  cpa_stack_verify_health CPAMP http://127.0.0.1:18317/health
  local scheme="http"
  cpa_stack_truthy "$ENABLE_HTTPS" && [[ -f "/etc/letsencrypt/live/${CPA_DOMAIN}/fullchain.pem" ]] && scheme="https"
  if [[ "$scheme" == "https" ]]; then
    success "$(t app.cpa_stack.success.https "${scheme}://${CPA_DOMAIN}" "${scheme}://${CPAMP_DOMAIN}")"
  else
    warn "$(t app.cpa_stack.warn.certbot "$CPA_DOMAIN" "$CPAMP_DOMAIN")"
  fi
}

do_backup() {
  cpa_stack_show_banner
  cpa_stack_preflight backup
  acquire_lock
  require_safe_path "CPA_STACK_BACKUP_DIR" "$CPA_STACK_BACKUP_DIR"
  step "$(t app.cpa_stack.step.backup)"
  mkdir -p "$CPA_STACK_BACKUP_DIR" || error "$(t app.cpa_stack.error.backup "$CPA_STACK_BACKUP_DIR")"
  local timestamp archive tmp cpamp_was_active=false
  timestamp="$(date +%Y%m%d_%H%M%S)"
  archive="${CPA_STACK_BACKUP_DIR}/cpa-stack-${timestamp}.tar.gz"
  tmp="${archive}.tmp"
  systemctl is-active --quiet "$CPAMP_SERVICE_NAME" && cpamp_was_active=true
  if $cpamp_was_active; then
    systemctl stop "$CPAMP_SERVICE_NAME" || error "$(t app.cpa_stack.error.service "$CPAMP_SERVICE_NAME")"
  fi
  # CPAMP data directory includes usage.sqlite, its WAL/SHM files, and data.key.
  local -a backup_paths=()
  for candidate in \
      etc/cpa-stack \
      etc/cli-proxy-api \
      opt/cpa-manager-plus/config.json \
      var/lib/cpa-manager-plus \
      var/lib/cli-proxy-api; do
    [[ -e "/${candidate}" ]] && backup_paths+=("$candidate")
  done
  if ! tar -C / -czf "$tmp" "${backup_paths[@]}" 2>/dev/null; then
    rm -f "$tmp"
    if $cpamp_was_active; then
      systemctl start "$CPAMP_SERVICE_NAME" || true
    fi
    error "$(t app.cpa_stack.error.backup "$archive")"
  fi
  if ! mv "$tmp" "$archive"; then
    rm -f "$tmp"
    if $cpamp_was_active; then
      systemctl start "$CPAMP_SERVICE_NAME" || true
    fi
    error "$(t app.cpa_stack.error.backup "$archive")"
  fi
  if $cpamp_was_active; then
    systemctl start "$CPAMP_SERVICE_NAME" || error "$(t app.cpa_stack.error.service "$CPAMP_SERVICE_NAME")"
  fi
  cpa_stack_prune_backups
  success "$(t app.cpa_stack.success.backup "$archive")"
}

do_status() {
  cpa_stack_show_banner
  app_load_config
  printf '\n[%s]\n' "$(t app.cpa_stack.status.services)"
  printf '  %s: %s\n' "$CPA_SERVICE_NAME" "$(service_status_label "$CPA_SERVICE_NAME")"
  printf '  %s: %s\n' "$CPAMP_SERVICE_NAME" "$(service_status_label "$CPAMP_SERVICE_NAME")"
  printf '  nginx: %s\n' "$(service_status_label nginx)"
  printf '\n[%s]\n' "$(t app.cpa_stack.status.local_health)"
  cpa_stack_verify_health CPA http://127.0.0.1:8317/healthz
  cpa_stack_verify_health CPAMP http://127.0.0.1:18317/health
  printf '\n[%s]\n' "$(t app.cpa_stack.status.paths)"
  for path in "$CPA_CONFIG_FILE" "$CPA_AUTH_DIR" "$CPAMP_ENV_FILE" "$CPAMP_DATA_DIR" "$NGINX_SITE" "$CPA_STACK_BACKUP_DIR"; do
    [[ -e "$path" ]] && printf '  [ok] %s\n' "$path" || printf '  [--] %s\n' "$path"
  done
}

do_doctor() {
  cpa_stack_show_banner
  app_load_config
  local failures=0 warnings=0
  printf '\n%s\n' "$(t doctor.title)"
  if [[ -n "$CPA_DOMAIN" && -n "$CPAMP_DOMAIN" ]]; then
    success "$(t app.cpa_stack.doctor.domains "$CPA_DOMAIN" "$CPAMP_DOMAIN")"
  else
    warn "$(t app.cpa_stack.error.domain_required "CPA_DOMAIN / CPAMP_DOMAIN")"; warnings=$((warnings + 1))
  fi
  for requirement in curl nginx systemctl; do
    if command -v "$requirement" >/dev/null 2>&1; then
      success "$(t app.cpa_stack.doctor.command_ok "$requirement")"
    else
      warn "$(t app.cpa_stack.doctor.command_missing "$requirement")"; failures=$((failures + 1))
    fi
  done
  for service in "$CPA_SERVICE_NAME" "$CPAMP_SERVICE_NAME" nginx; do
    if systemctl is-active --quiet "$service" 2>/dev/null; then
      success "$(t app.cpa_stack.doctor.service_active "$service")"
    else
      warn "$(t app.cpa_stack.doctor.service_inactive "$service")"; warnings=$((warnings + 1))
    fi
  done
  if [[ -f "$CPA_CONFIG_FILE" ]]; then
    if grep -Eq '^host:[[:space:]]*"?127\.0\.0\.1' "$CPA_CONFIG_FILE" \
        && grep -Eq '^usage-statistics-enabled:[[:space:]]*true' "$CPA_CONFIG_FILE"; then
      success "$(t app.cpa_stack.doctor.cpa_loopback_ok)"
    else
      warn "$(t app.cpa_stack.doctor.cpa_loopback_bad)"; warnings=$((warnings + 1))
    fi
  else
    warn "$(t app.cpa_stack.warn.config_missing "$CPA_CONFIG_FILE")"; failures=$((failures + 1))
  fi
  if [[ -f "$CPAMP_ENV_FILE" ]]; then
    success "$(t app.cpa_stack.doctor.env_ok)"
  else
    warn "$(t app.cpa_stack.warn.config_missing "$CPAMP_ENV_FILE")"; failures=$((failures + 1))
  fi
  if command -v ss >/dev/null 2>&1; then
    if ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq '(^|:)8317$|(^|:)18317$'; then
      if ss -ltnH 2>/dev/null | awk '{print $4}' | grep -Eq '(^|:)0\.0\.0\.0:8317$|(^|:)\[::\]:8317$|(^|:)0\.0\.0\.0:18317$|(^|:)\[::\]:18317$'; then
        warn "$(t app.cpa_stack.doctor.public_listener_bad)"; failures=$((failures + 1))
      else
        success "$(t app.cpa_stack.doctor.loopback_ok)"
      fi
    fi
  fi
  cpa_stack_verify_health CPA http://127.0.0.1:8317/healthz
  cpa_stack_verify_health CPAMP http://127.0.0.1:18317/health
  if (( failures > 0 )); then
    warn "$(t app.cpa_stack.doctor.done_blocking "$failures" "$warnings")"
    return 1
  fi
  if (( warnings > 0 )); then
    warn "$(t app.cpa_stack.doctor.done_warnings "$warnings")"
  else
    success "$(t app.cpa_stack.doctor.done_ok)"
  fi
}

do_uninstall() {
  cpa_stack_show_banner
  cpa_stack_preflight uninstall
  acquire_lock
  local confirm delete_data=false
  if deploy_assume_yes; then
    confirm="YES"
  else
    prompt "$(t app.cpa_stack.prompt.continue)"
    read -r confirm
  fi
  [[ "$confirm" == "YES" ]] || error "$(t app.cpa_stack.error.uninstall_cancelled)"
  if deploy_assume_yes; then
    deploy_env_truthy DEPLOY_DELETE_DATA && delete_data=true
  else
    prompt "$(t app.cpa_stack.prompt.delete_data "/var/lib/cli-proxy-api and /var/lib/cpa-manager-plus")"
    local answer
    read -r answer
    [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]] && delete_data=true
  fi
  systemctl disable --now "$CPAMP_SERVICE_NAME" "$CPA_SERVICE_NAME" >/dev/null 2>&1 || true
  rm -f "/etc/systemd/system/${CPA_SERVICE_NAME}.service" "/etc/systemd/system/${CPAMP_SERVICE_NAME}.service"
  systemctl daemon-reload || true
  rm -f "$NGINX_SITE_LINK" "$NGINX_SITE" "$NGINX_MAP_FILE"
  rm -f "$CONF_FILE"
  if command -v nginx >/dev/null 2>&1 && nginx -t >/dev/null 2>&1; then
    systemctl reload nginx || true
  fi
  if $delete_data; then
    safe_rm_dir "$CPA_DATA_DIR" "CPA_DATA_DIR"
    safe_rm_dir "$CPAMP_DATA_DIR" "CPAMP_DATA_DIR"
    safe_rm_dir "$CPA_CONFIG_DIR" "CPA_CONFIG_DIR"
    safe_rm_dir "$CPAMP_ENV_DIR" "CPAMP_ENV_DIR"
    safe_rm_dir "$CPA_STACK_BACKUP_DIR" "CPA_STACK_BACKUP_DIR"
  else
    info "$(t app.cpa_stack.info.kept_data "$CPA_DATA_DIR")"
    info "$(t app.cpa_stack.info.kept_data "$CPAMP_DATA_DIR")"
  fi
  success "$(t app.cpa_stack.success.removed)"
}
