#!/bin/bash
set -euo pipefail
BLOG_DOMAIN="blog.tarxf.com"
BLOG_TITLE="${BLOG_TITLE:-$(t app.blog.site_title)}"
BLOG_AUTHOR="Abyte"
BLOG_DESCRIPTION="${BLOG_DESCRIPTION:-$(t app.blog.site_description)}"
BLOG_LANG="${BLOG_LANG:-$(t app.blog.site_lang)}"
SITE_DIR="/opt/blog/site"
PUBLIC_DIR="/opt/blog/public"
NGINX_ROOT="/var/www/blog"
THEME_NAME="hugo-theme-stack"
THEME_REPO="https://github.com/CaiJimmy/hugo-theme-stack.git"
ENABLE_CMS=true
CMS_BACKEND="github"
CMS_REPO="TheSkyC/my-hugo-blog"
CMS_BRANCH="main"
CMS_SITE_URL="https://${BLOG_DOMAIN}"
LOCK_FILE="/var/lock/blog-deploy.lock"

restore_nginx_root_backup() {
  [[ -e "$DEPLOY_BAK" || -L "$DEPLOY_BAK" ]] || return 0
  rm -rf "$NGINX_ROOT" || return 1
  mv "$DEPLOY_BAK" "$NGINX_ROOT" || return 1
}

_write_publish_script() {
  local publish_script="/usr/local/bin/blog-publish"
  local publish_tmp
  publish_tmp=$(mktemp "${publish_script}.XXXXXX") || error "$(t app.blog.error.publish_script)"
  if ! cat > "$publish_tmp" << BKSH
#!/bin/bash
set -euo pipefail
PUBLIC_DIR="${PUBLIC_DIR}"
NGINX_ROOT="${NGINX_ROOT}"
NGINX_ROOT_PARENT="\$(dirname "\$NGINX_ROOT")"
NGINX_ROOT_NAME="\$(basename "\$NGINX_ROOT")"
DEPLOY_TMP="\$(mktemp -d "\${NGINX_ROOT_PARENT}/.\${NGINX_ROOT_NAME}.new.XXXXXX")"
DEPLOY_BAK="\${NGINX_ROOT}.bak.\$(date +%Y%m%d%H%M%S)"
restore_nginx_root_backup() {
  [[ -e "\$DEPLOY_BAK" || -L "\$DEPLOY_BAK" ]] || return 0
  rm -rf "\$NGINX_ROOT" || return 1
  mv "\$DEPLOY_BAK" "\$NGINX_ROOT" || return 1
}
[[ -d "\$PUBLIC_DIR" ]] || { echo "PUBLIC_DIR is missing: \$PUBLIC_DIR" >&2; exit 1; }
mkdir -p "\$NGINX_ROOT_PARENT"
if cp -a "\${PUBLIC_DIR}/." "\$DEPLOY_TMP/"; then
  if [[ -e "\$NGINX_ROOT" || -L "\$NGINX_ROOT" ]]; then
    if ! mv "\$NGINX_ROOT" "\$DEPLOY_BAK"; then
      rm -rf "\$DEPLOY_TMP"
      echo "Failed to back up the live Nginx root: \$NGINX_ROOT" >&2
      exit 1
    fi
  fi
  if mv "\$DEPLOY_TMP" "\$NGINX_ROOT"; then
    [[ -e "\$DEPLOY_BAK" || -L "\$DEPLOY_BAK" ]] && rm -rf "\$DEPLOY_BAK"
  else
    restore_nginx_root_backup || {
      echo "Failed to restore the previous Nginx root: \$NGINX_ROOT" >&2
      exit 1
    }
    echo "Failed to replace the live Nginx root: \$NGINX_ROOT" >&2
    exit 1
  fi
else
  rm -rf "\$DEPLOY_TMP"
  echo "Failed to stage static output from \$PUBLIC_DIR" >&2
  exit 1
fi
BKSH
  then
    rm -f "$publish_tmp"
    error "$(t app.blog.error.publish_script)"
  fi
  if ! chmod 750 "$publish_tmp" \
      || ! chown root:root "$publish_tmp" \
      || ! mv "$publish_tmp" "$publish_script"; then
    rm -f "$publish_tmp"
    error "$(t app.blog.error.publish_script)"
  fi
  success "$(t app.blog.success.publish_script)"
}

backup_blog_file() {
  local source_path="$1" backup_path="$2"
  local backup_tmp
  backup_tmp=$(mktemp "${backup_path}.XXXXXX") || return 1
  if ! cp "$source_path" "$backup_tmp" || ! mv "$backup_tmp" "$backup_path"; then
    rm -f "$backup_tmp"
    return 1
  fi
}

_write_nginx_site_link() {
  local target="$1" link_path="$2"
  local link_tmp
  mkdir -p "$(dirname "$link_path")" || return 1
  link_tmp=$(mktemp "${link_path}.XXXXXX") || return 1
  rm -f "$link_tmp"
  if ! ln -s "$target" "$link_tmp" || ! mv -Tf "$link_tmp" "$link_path"; then
    rm -f "$link_tmp"
    return 1
  fi
}

_write_blog_file() {
  local target_path="$1"
  local target_dir target_tmp
  target_dir="$(dirname "$target_path")"
  mkdir -p "$target_dir"
  target_tmp=$(mktemp "${target_dir}/.$(basename "$target_path").XXXXXX")
  if ! cat > "$target_tmp"; then
    rm -f "$target_tmp"
    error "$(t app.blog.error.file_write "$target_path")"
  fi
  if ! chmod 644 "$target_tmp" \
      || ! mv "$target_tmp" "$target_path"; then
    rm -f "$target_tmp"
    error "$(t app.blog.error.file_write "$target_path")"
  fi
}

wait_for_service() {
  local service="$1"
  local timeout="${2:-10}"
  local elapsed=0
  while (( elapsed < timeout )); do
    if systemctl is-active --quiet "$service"; then
      return 0
    fi
    sleep 1
    elapsed=$(( elapsed + 1 ))
  done
  systemctl is-active --quiet "$service"
}

do_install() {
echo -e "\n${BOLD}${CYAN}"
cat << 'EOF'
  ██╗  ██╗██╗   ██╗ ██████╗  ██████╗     ██████╗ ██╗      ██████╗  ██████╗
  ██║  ██║██║   ██║██╔════╝ ██╔═══██╗    ██╔══██╗██║     ██╔═══██╗██╔════╝
  ███████║██║   ██║██║  ███╗██║   ██║    ██████╔╝██║     ██║   ██║██║  ███╗
  ██╔══██║██║   ██║██║   ██║██║   ██║    ██╔══██╗██║     ██║   ██║██║   ██║
  ██║  ██║╚██████╔╝╚██████╔╝╚██████╔╝    ██████╔╝███████╗╚██████╔╝╚██████╔╝
  ╚═╝  ╚═╝ ╚═════╝  ╚═════╝  ╚═════╝    ╚═════╝ ╚══════╝ ╚═════╝  ╚═════╝
EOF
echo -e "${NC}"
echo -e "  ${BOLD}$(t app.blog.banner_theme "${CYAN}hugo-theme-stack${NC}${BOLD}")${NC}"
echo -e "  ${BOLD}$(t app.blog.banner_stack)${NC}\n"
[[ $EUID -ne 0 ]] && error "$(t error.root_required "$0" "${1:-}")"
command -v apt-get >/dev/null 2>&1 || error "$(t app.blog.error.apt_only)"
command -v systemctl >/dev/null 2>&1 || error "$(t app.blog.error.systemd_required)"
ARCH=$(uname -m)
case $ARCH in
  x86_64)  DEB_ARCH="amd64" ;;
  aarch64) DEB_ARCH="arm64" ;;
  *)       error "$(t app.blog.error.arch "$ARCH")" ;;
esac
acquire_lock
step "$(t app.blog.step_install_deps)"
if ! apt-get update -qq; then
  error "$(t app.blog.error.apt_update)"
fi
if ! apt-get install -y -qq curl wget git nginx ca-certificates; then
  error "$(t app.blog.error.deps_install)"
fi
success "$(t app.blog.deps_installed)"
step "$(t app.blog.step_install_hugo)"
info "$(t app.blog.query_hugo)"
HUGO_VER=$(curl -fsSL --max-time 15 \
  "https://api.github.com/repos/gohugoio/hugo/releases/latest" \
  | grep '"tag_name"' | head -1 \
  | sed 's/.*"v\([^"]*\)".*/\1/') \
  || error "$(t app.blog.error.github_api)"
[[ -z "$HUGO_VER" ]] && error "$(t app.blog.error.hugo_version)"
success "$(t app.blog.latest_version "$HUGO_VER")"
DEB_URL="https://github.com/gohugoio/hugo/releases/download/v${HUGO_VER}/hugo_extended_${HUGO_VER}_linux-${DEB_ARCH}.deb"
info "$(t app.blog.download_url "$DEB_URL")"
HUGO_DEB="$(mktemp /tmp/hugo.XXXXXX.deb)"
if ! wget -q --show-progress -O "$HUGO_DEB" "$DEB_URL"; then
  rm -f "$HUGO_DEB"
  error "$(t app.blog.error.hugo_download)"
fi
if ! dpkg -i "$HUGO_DEB"; then
  rm -f "$HUGO_DEB"
  error "$(t app.blog.error.hugo_install)"
fi
rm -f "$HUGO_DEB"
success "$(t app.blog.hugo_installed "$(hugo version | head -1)")"
step "$(t app.blog.step_init_site)"
mkdir -p "$(dirname "$SITE_DIR")"
if [[ -d "$SITE_DIR" ]]; then
  warn "$(t app.blog.site_exists "$SITE_DIR")"
else
  hugo new site "$SITE_DIR" --format toml
  success "$(t app.blog.site_created "$SITE_DIR")"
fi
if [[ ! -d "${SITE_DIR}/.git" ]]; then
  git -C "$SITE_DIR" init -q
  git -C "$SITE_DIR" config user.email "blog@localhost"
  git -C "$SITE_DIR" config user.name "${BLOG_AUTHOR}"
  success "$(t app.blog.git_initialized)"
fi
step "$(t app.blog.step_theme)"
THEME_DIR="${SITE_DIR}/themes/${THEME_NAME}"
if [[ -d "$THEME_DIR" && -f "$THEME_DIR/theme.toml" ]]; then
  info "$(t app.blog.theme_exists)"
  success "$(t app.blog.theme_current)"
else
  info "$(t app.blog.clone_theme)"
  git -C "$SITE_DIR" submodule add --depth 1 "$THEME_REPO" "themes/${THEME_NAME}" 2>/dev/null \
    || { git clone --depth 1 "$THEME_REPO" "$THEME_DIR" && rm -rf "$THEME_DIR/.git"; }
  success "$(t app.blog.theme_installed)"
fi
step "$(t app.blog.step_config)"
CONFIG_FILE="${SITE_DIR}/hugo.toml"
if [[ -f "$CONFIG_FILE" && $(wc -l < "$CONFIG_FILE") -gt 3 ]]; then
  backup_blog_file "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)" \
    || error "$(t app.blog.error.file_write "$CONFIG_FILE")"
  warn "$(t app.blog.config_backed_up)"
fi
if [[ -n "$BLOG_DOMAIN" ]]; then
  BASE_URL="https://${BLOG_DOMAIN}"
else
  BASE_URL="http://localhost"
fi
_write_blog_file "$CONFIG_FILE" << TOML
baseURL = "${BASE_URL}"
locale = "${BLOG_LANG}"
defaultContentLanguage = "${BLOG_LANG}"
title = "${BLOG_TITLE}"
theme = "${THEME_NAME}"

# Pagination.
paginate = 10

# Enable Git metadata for last-modified timestamps.
enableGitInfo = true

[params]
  mainSections = ["post"]
  description = "${BLOG_DESCRIPTION}"

  [params.sidebar]
    emoji = "✍️"
    subtitle = "${BLOG_DESCRIPTION}"

    # Uncomment this block after placing an avatar at assets/img/avatar.png.
    # [params.sidebar.avatar]
    #   enabled = true
    #   local   = true
    #   src     = "img/avatar.png"

  [params.footer]
    since = $(date +%Y)
    customText = ""

  [params.article]
    math = false
    toc = true
    readingTime = true
    license.enabled = false

  [params.comments]
    enabled = false

[author]
  name = "${BLOG_AUTHOR}"

[menu]
  [[menu.main]]
    name = "$(t app.blog.menu_home)"
    url = "/"
    weight = 1
  [[menu.main]]
    name = "$(t app.blog.menu_archives)"
    url = "/archives"
    weight = 2
  [[menu.main]]
    name = "$(t app.blog.menu_categories)"
    url = "/categories"
    weight = 3
  [[menu.main]]
    name = "$(t app.blog.menu_tags)"
    url = "/tags"
    weight = 4
  [[menu.main]]
    name = "$(t app.blog.menu_about)"
    url = "/about"
    weight = 5

[taxonomies]
  category = "categories"
  tag = "tags"
  series = "series"
TOML
success "$(t app.blog.config_written "$CONFIG_FILE")"
step "$(t app.blog.step_content)"
mkdir -p "${SITE_DIR}/content/post/hello-world"
mkdir -p "${SITE_DIR}/content/page/about"
mkdir -p "${SITE_DIR}/content/page/archives"
mkdir -p "${SITE_DIR}/static/img"
if [[ ! -f "${SITE_DIR}/content/post/hello-world/index.md" ]]; then
_write_blog_file "${SITE_DIR}/content/post/hello-world/index.md" << MD
+++
title = "$(t app.blog.post_title)"
date = "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
description = "$(t app.blog.post_description)"
draft = false
categories = ["$(t app.blog.post_category)"]
tags = ["Hugo", "$(t app.blog.post_tag_blog)"]
+++

## $(t app.blog.post_heading)

$(t app.blog.post_intro)

### $(t app.blog.post_why_heading)

- $(t app.blog.post_fast_build)
- $(t app.blog.post_markdown)
- $(t app.blog.post_theme)
- $(t app.blog.post_open_source)

### $(t app.blog.post_start_heading)

$(t app.blog.post_start_body)

\`\`\`bash
# Create a new post quickly.
hugo new content post/my-new-post/index.md
\`\`\`

$(t app.blog.post_closing)
MD
success "$(t app.blog.sample_post_created)"
fi
if [[ ! -f "${SITE_DIR}/content/page/about/index.md" ]]; then
_write_blog_file "${SITE_DIR}/content/page/about/index.md" << MD
+++
title = "$(t app.blog.about_title)"
date = "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
menu = "main"
+++

## $(t app.blog.about_heading)

$(t app.blog.about_intro "$BLOG_AUTHOR")

$(t app.blog.about_body)

---

*$(t app.blog.about_footer)*
MD
success "$(t app.blog.about_created)"
fi
if [[ ! -f "${SITE_DIR}/content/page/archives/index.md" ]]; then
_write_blog_file "${SITE_DIR}/content/page/archives/index.md" << MD
+++
title = "$(t app.blog.archives_title)"
date = "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
layout = "archives"
+++
MD
success "$(t app.blog.archives_created)"
fi
step "$(t app.blog.step_cms)"
if [[ "$ENABLE_CMS" != "true" ]]; then
  warn "$(t app.blog.cms_skipped)"
else
  CMS_ADMIN_DIR="${SITE_DIR}/static/admin"
  mkdir -p "$CMS_ADMIN_DIR"
  _write_blog_file "${CMS_ADMIN_DIR}/index.html" << HTML
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <meta name="robots" content="noindex" />
    <title>$(t app.blog.cms_title)</title>
  </head>
  <body>
    <script src="https://unpkg.com/decap-cms@^3.0.0/dist/decap-cms.js"></script>
  </body>
</html>
HTML
  _write_blog_file "${CMS_ADMIN_DIR}/config.yml" << YAML
# ─────────────────────────────────────────────
#  Decap CMS configuration for hugo-theme-stack.
#  Docs: https://decapcms.org/docs/configuration-options/
# ─────────────────────────────────────────────

backend:
  name: ${CMS_BACKEND}
  repo: ${CMS_REPO}
  branch: ${CMS_BRANCH}
  # Uncomment and fill this when using a self-hosted OAuth proxy.
  # base_url: https://your-oauth-server.com

site_url: ${CMS_SITE_URL}

# Media paths are relative to the Hugo project root.
media_folder: "static/img/uploads"
public_folder: "/img/uploads"

collections:

  # ── Blog posts (content/post/) ──────────────────────────────
  - name: "post"
    label: "$(t app.blog.cms_posts)"
    label_singular: "$(t app.blog.cms_post)"
    folder: "content/post"
    path: "{{slug}}/index"
    media_folder: ""
    public_folder: ""
    create: true
    slug: "{{slug}}"
    preview_path: "post/{{slug}}/"
    format: toml-frontmatter
    fields:
      - { label: "$(t app.blog.cms_title_field)", name: "title", widget: "string" }
      - { label: "$(t app.blog.cms_date_field)", name: "date", widget: "datetime", date_format: "YYYY-MM-DD", time_format: "HH:mm:ss", format: "YYYY-MM-DDTHH:mm:ssZ" }
      - { label: "$(t app.blog.cms_description_field)", name: "description", widget: "string", required: false }
      - { label: "$(t app.blog.cms_draft_field)", name: "draft", widget: "boolean", default: false }
      - label: "$(t app.blog.cms_categories_field)"
        name: "categories"
        widget: "list"
        allow_add: true
        default: []
        field: { label: "$(t app.blog.cms_category_field)", name: "category", widget: "string" }
      - label: "$(t app.blog.cms_tags_field)"
        name: "tags"
        widget: "list"
        allow_add: true
        default: []
        field: { label: "$(t app.blog.cms_tag_field)", name: "tag", widget: "string" }
      - label: "$(t app.blog.cms_series_field)"
        name: "series"
        widget: "list"
        allow_add: true
        required: false
        field: { label: "$(t app.blog.cms_series_item_field)", name: "series", widget: "string" }
      - label: "$(t app.blog.cms_image_field)"
        name: "image"
        widget: "image"
        required: false
        choose_url: false
        hint: "$(t app.blog.cms_image_hint)"
      - { label: "$(t app.blog.cms_weight_field)", name: "weight", widget: "number", required: false, value_type: "int" }
      - { label: "$(t app.blog.cms_body_field)", name: "body", widget: "markdown" }

  # ── Standalone pages (content/page/) ────────────────────────
  - name: "page"
    label: "$(t app.blog.cms_pages)"
    label_singular: "$(t app.blog.cms_page)"
    folder: "content/page"
    path: "{{slug}}/index"
    create: true
    format: toml-frontmatter
    fields:
      - { label: "$(t app.blog.cms_title_field)", name: "title", widget: "string" }
      - { label: "$(t app.blog.cms_date_field)", name: "date", widget: "datetime", format: "YYYY-MM-DDTHH:mm:ssZ" }
      - { label: "$(t app.blog.cms_draft_field)", name: "draft", widget: "boolean", default: false }
      - label: "$(t app.blog.cms_menu_field)"
        name: "menu"
        widget: "select"
        required: false
        options: ["main"]
        hint: "$(t app.blog.cms_menu_hint)"
      - { label: "$(t app.blog.cms_layout_field)", name: "layout", widget: "string", required: false, hint: "$(t app.blog.cms_layout_hint)" }
      - { label: "$(t app.blog.cms_body_field)", name: "body", widget: "markdown" }
YAML
  success "$(t app.blog.cms_config_created "${CMS_ADMIN_DIR}/")"
  info "$(t app.blog.cms_admin_url "$CMS_SITE_URL")"
fi
step "$(t app.blog.step_build)"
mkdir -p "$PUBLIC_DIR"
cd "$SITE_DIR"
git add -A
git diff --cached --quiet || git commit -q -m "init: add site content"
info "$(t app.blog.git_committed)"
hugo --destination "$PUBLIC_DIR" --gc --minify \
  || error "$(t app.blog.error.hugo_build)"
PAGE_COUNT=$(find "$PUBLIC_DIR" -name "*.html" | wc -l)
success "$(t app.blog.build_complete "$PAGE_COUNT")"
step "$(t app.blog.step_nginx)"
NGINX_ROOT_PARENT="$(dirname "$NGINX_ROOT")"
NGINX_ROOT_NAME="$(basename "$NGINX_ROOT")"
mkdir -p "$NGINX_ROOT_PARENT"
DEPLOY_TMP="$(mktemp -d "${NGINX_ROOT_PARENT}/.${NGINX_ROOT_NAME}.new.XXXXXX")"
DEPLOY_BAK="${NGINX_ROOT}.bak.$(date +%Y%m%d%H%M%S)"
if cp -a "${PUBLIC_DIR}/." "$DEPLOY_TMP/"; then
  if [[ -e "$NGINX_ROOT" || -L "$NGINX_ROOT" ]]; then
    if ! mv "$NGINX_ROOT" "$DEPLOY_BAK"; then
      rm -rf "$DEPLOY_TMP"
      error "$(t app.blog.error.static_deploy "$NGINX_ROOT")"
    fi
  fi
  if mv "$DEPLOY_TMP" "$NGINX_ROOT"; then
    [[ -e "$DEPLOY_BAK" || -L "$DEPLOY_BAK" ]] && rm -rf "$DEPLOY_BAK"
  else
    restore_nginx_root_backup || error "$(t app.blog.error.static_deploy "$NGINX_ROOT")"
    error "$(t app.blog.error.static_deploy "$NGINX_ROOT")"
  fi
else
  rm -rf "$DEPLOY_TMP"
  error "$(t app.blog.error.static_deploy "$NGINX_ROOT")"
fi
success "$(t app.blog.static_deployed "$NGINX_ROOT")"
_write_publish_script
NGINX_CONF="/etc/nginx/sites-available/blog"
NGINX_TMP=$(mktemp "${NGINX_CONF}.XXXXXX")
if ! cat > "$NGINX_TMP" << NGINX
server {
    listen 80;
    listen [::]:80;

    server_name ${BLOG_DOMAIN:-_};   # Match all hosts when no domain is configured.
    root ${NGINX_ROOT};
    index index.html;

    # Character encoding.
    charset utf-8;

    # Static asset caching.
    location ~* \.(css|js|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 30d;
        add_header Cache-Control "public, no-transform";
    }

    # Hugo-generated RSS.
    location /index.xml {
        add_header Content-Type "application/rss+xml; charset=utf-8";
    }

    # Decap CMS admin SPA entrypoint; disable caching and indexing.
    location /admin/ {
        try_files \$uri \$uri/ /admin/index.html;
        add_header Cache-Control "no-store, no-cache, must-revalidate";
        add_header X-Robots-Tag "noindex, nofollow";
    }

    # Keep Decap CMS config.yml uncached for live configuration updates.
    location = /admin/config.yml {
        add_header Cache-Control "no-store";
    }

    # 404 handling.
    error_page 404 /404.html;
    location = /404.html {
        internal;
    }

    # Gzip compression.
    gzip on;
    gzip_types text/plain text/css application/json application/javascript
               text/xml application/xml application/xml+rss text/javascript
               application/x-yaml;
    gzip_min_length 1024;

    # Security headers.
    add_header X-Frame-Options "SAMEORIGIN";
    add_header X-Content-Type-Options "nosniff";
    add_header Referrer-Policy "strict-origin-when-cross-origin";

    # Logs.
    access_log /var/log/nginx/blog_access.log;
    error_log  /var/log/nginx/blog_error.log;
}
NGINX
then
  rm -f "$NGINX_TMP"
  error "$(t app.blog.error.nginx_write "$NGINX_CONF")"
fi
if ! chmod 644 "$NGINX_TMP" \
    || ! chown root:root "$NGINX_TMP" \
    || ! mv "$NGINX_TMP" "$NGINX_CONF"; then
  rm -f "$NGINX_TMP"
  error "$(t app.blog.error.nginx_write "$NGINX_CONF")"
fi
_write_nginx_site_link "$NGINX_CONF" /etc/nginx/sites-enabled/blog \
  || error "$(t app.blog.error.nginx_write "$NGINX_CONF")"
rm -f /etc/nginx/sites-enabled/default
nginx -t || error "$(t app.blog.error.nginx_config)"
success "$(t app.blog.nginx_configured)"
step "$(t app.blog.step_firewall)"
FW_DONE=false
FW_ERROR=false
if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
  if ufw allow "Nginx Full" > /dev/null 2>&1 \
      || { ufw allow 80/tcp > /dev/null 2>&1 && ufw allow 443/tcp > /dev/null 2>&1; }; then
    success "$(t app.blog.ufw_opened)"
    FW_DONE=true
  else
    FW_ERROR=true
  fi
fi
if ! $FW_DONE && command -v iptables &>/dev/null; then
  iptables_ok=true
  for PORT in 80 443; do
    if ! iptables -C INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null; then
      if ! iptables -A INPUT -p tcp --dport "$PORT" -j ACCEPT; then
        iptables_ok=false
        break
      fi
    fi
  done
  if $iptables_ok; then
    success "$(t app.blog.iptables_opened)"
    FW_DONE=true
  else
    FW_ERROR=true
  fi
fi
if ! $FW_DONE; then
  if $FW_ERROR; then
    warn "$(t app.blog.firewall_config_failed)"
  else
    warn "$(t app.blog.firewall_missing)"
  fi
fi
step "$(t app.blog.step_start_nginx)"
if ! systemctl enable nginx --quiet; then
  warn "$(t app.blog.warn.service_enable_failed "nginx" "nginx")"
fi
if systemctl restart nginx && wait_for_service nginx 10; then
  success "$(t app.blog.nginx_started)"
else
  error "$(t app.blog.error.nginx_start)"
fi
step "$(t app.blog.step_health)"
local _blog_summary_state="ready"
HTTP_CODE=$(curl -H "Host: ${BLOG_DOMAIN:-localhost}" -o /dev/null -s -w "%{http_code}" --max-time 5 "http://127.0.0.1/" || echo "000")
if [[ "$HTTP_CODE" == "200" ]]; then
  success "$(t app.blog.http_ok)"
else
  warn "$(t app.blog.http_warn "$HTTP_CODE")"
  _blog_summary_state="pending"
fi
INTERNAL_IP=$(hostname -I | awk '{print $1}')
echo ""
echo -e "${BOLD}${GREEN}"
echo "  ╔══════════════════════════════════════════════════════╗"
if [[ "$_blog_summary_state" == "pending" ]]; then
  printf "  ║               %s                     ║\n" "$(t app.blog.summary_title_pending)"
else
  printf "  ║               %s                     ║\n" "$(t app.blog.summary_title_ready)"
fi
echo "  ╠══════════════════════════════════════════════════════╣"
if [[ -n "$BLOG_DOMAIN" ]]; then
echo -e "  ║  $(t app.blog.public_url)  ${CYAN}http://${BLOG_DOMAIN}${GREEN}"
fi
echo -e "  ║  $(t app.blog.internal_url)  ${CYAN}http://${INTERNAL_IP}${GREEN}"
if [[ "$ENABLE_CMS" == "true" ]]; then
echo -e "  ║  $(t app.blog.cms_admin)  ${CYAN}http://${INTERNAL_IP}/admin/${GREEN}  ($(t app.blog.oauth_required))"
fi
echo "  ╠══════════════════════════════════════════════════════╣"
echo -e "  ║  $(t app.blog.site_dir)  ${YELLOW}${SITE_DIR}${GREEN}"
echo -e "  ║  $(t app.blog.posts_dir)  ${YELLOW}${SITE_DIR}/content/post/${GREEN}"
echo -e "  ║  $(t app.blog.public_dir)  ${YELLOW}${NGINX_ROOT}${GREEN}"
if [[ "$ENABLE_CMS" == "true" ]]; then
echo -e "  ║  $(t app.blog.cms_config)  ${YELLOW}${SITE_DIR}/static/admin/config.yml${GREEN}"
fi
echo "  ╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  ${BOLD}$(t app.blog.workflow_title)${NC}"
echo ""
echo -e "  ${CYAN}# $(t app.blog.workflow_new_post)${NC}"
echo -e "  cd ${SITE_DIR}"
echo -e "  hugo new content post/my-post/index.md"
echo ""
echo -e "  ${CYAN}# $(t app.blog.workflow_preview)${NC}"
echo -e "  hugo server -D --bind 0.0.0.0 --port 1313"
echo -e "  # $(t app.blog.workflow_visit "$INTERNAL_IP")"
echo ""
echo -e "  ${CYAN}# $(t app.blog.workflow_publish)${NC}"
echo -e "  hugo --destination ${PUBLIC_DIR} --gc --minify"
echo -e "  /usr/local/bin/blog-publish"
echo ""
if [[ "$ENABLE_CMS" == "true" ]]; then
echo -e "  ${BOLD}$(t app.blog.cms_usage)${NC}"
echo ""
echo -e "  ${CYAN}# $(t app.blog.cms_github_backend)${NC}"
echo -e "  $(t app.blog.cms_oauth_step1)"
echo -e "$(t app.blog.cms_oauth_homepage "$CMS_SITE_URL")"
echo -e "$(t app.blog.cms_oauth_callback)"
echo -e "$(t app.blog.cms_oauth_proxy)"
echo -e "  $(t app.blog.cms_push_repo "$SITE_DIR" "$CMS_REPO")"
echo -e "  $(t app.blog.cms_login "$CMS_SITE_URL")"
echo ""
echo -e "  ${CYAN}# $(t app.blog.cms_local_debug)${NC}"
echo -e "  # $(t app.blog.cms_test_repo "$SITE_DIR")"
echo -e "  # $(t app.blog.cms_run_server)"
echo ""
fi
echo -e "  ${BOLD}$(t app.blog.https_title)${NC}"
echo -e "  apt install certbot python3-certbot-nginx -y"
echo -e "  certbot --nginx -d ${BLOG_DOMAIN:-your-domain.com}"
echo ""
echo -e "  ${BOLD}$(t app.blog.theme_docs)${NC}  https://stack.jimmycai.com"
echo -e "  ${BOLD}📖  Decap CMS：${NC} https://decapcms.org/docs/"
echo ""
echo -e "  ${YELLOW}${BOLD}[i]${NC} $(t app.blog.rebuild_hint "$PUBLIC_DIR")"
echo ""
}
