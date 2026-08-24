#!/bin/bash
set -euo pipefail
BLOG_DOMAIN="${BLOG_DOMAIN:-blog.example.com}"
BLOG_TITLE="${BLOG_TITLE:-$(t app.blog.site_title)}"
BLOG_AUTHOR="${BLOG_AUTHOR:-Abyte}"
BLOG_DESCRIPTION="${BLOG_DESCRIPTION:-$(t app.blog.site_description)}"
BLOG_LANG="${BLOG_LANG:-$(t app.blog.site_lang)}"
SITE_DIR="${SITE_DIR:-/opt/blog/site}"
PUBLIC_DIR="${PUBLIC_DIR:-/opt/blog/public}"
NGINX_ROOT="${NGINX_ROOT:-/var/www/blog}"
BLOG_BACKUP_DIR="${BLOG_BACKUP_DIR:-/opt/blog-backups}"
BLOG_BACKUP_KEEP_DAYS="${BLOG_BACKUP_KEEP_DAYS:-30}"
THEME_NAME="${THEME_NAME:-hugo-theme-stack}"
THEME_REPO="${THEME_REPO:-https://github.com/CaiJimmy/hugo-theme-stack.git}"
ENABLE_CMS="${ENABLE_CMS:-true}"
CMS_BACKEND="${CMS_BACKEND:-github}"
CMS_REPO="${CMS_REPO:-TheSkyC/my-hugo-blog}"
CMS_BRANCH="${CMS_BRANCH:-main}"
CMS_SITE_URL="${CMS_SITE_URL:-https://${BLOG_DOMAIN}}"
CONFIG_KEYS=(
  BLOG_DOMAIN BLOG_TITLE BLOG_AUTHOR BLOG_DESCRIPTION BLOG_LANG
  SITE_DIR PUBLIC_DIR NGINX_ROOT BLOG_BACKUP_DIR BLOG_BACKUP_KEEP_DAYS
  THEME_NAME THEME_REPO ENABLE_CMS CMS_BACKEND CMS_REPO CMS_BRANCH CMS_SITE_URL
)
LOCK_FILE="/var/lock/blog-deploy.lock"

_BLOG_DERIVE_PATHS() {
  if [[ -z "${CMS_SITE_URL:-}" && -n "${BLOG_DOMAIN:-}" ]]; then
    CMS_SITE_URL="https://${BLOG_DOMAIN}"
  fi
}
APP_CONFIG_DERIVE_HOOK=_BLOG_DERIVE_PATHS
_blog_status_backup() {
  app_status_backup_json "BLOG_BACKUP_DIR" "${BLOG_BACKUP_DIR:-}" \
    "backup directory is unsafe or missing" 'blog_*.tar.gz'
}
APP_STATUS_BACKUP_FN=_blog_status_backup

_validate_config_values() {
  app_validate_domain "BLOG_DOMAIN" "$BLOG_DOMAIN"
  app_validate_bool "ENABLE_CMS" "$ENABLE_CMS"
  app_validate_system_name "THEME_NAME" "$THEME_NAME"
  app_validate_https_url "THEME_REPO" "$THEME_REPO"
  app_validate_system_name "CMS_BACKEND" "$CMS_BACKEND"
  app_validate_github_repo "CMS_REPO" "$CMS_REPO"
  app_validate_git_ref "CMS_BRANCH" "$CMS_BRANCH"
  app_validate_http_url "CMS_SITE_URL" "$CMS_SITE_URL"
  [[ "$BLOG_BACKUP_KEEP_DAYS" =~ ^[0-9]+$ ]] \
    || error "$(t app.blog.error.keep_days_invalid "$BLOG_BACKUP_KEEP_DAYS")"
  require_safe_path "SITE_DIR" "$SITE_DIR"
  require_safe_path "PUBLIC_DIR" "$PUBLIC_DIR"
  require_safe_path "NGINX_ROOT" "$NGINX_ROOT"
  require_safe_path "BLOG_BACKUP_DIR" "$BLOG_BACKUP_DIR"
}

_blog_load_config_if_root() {
  if [[ ${EUID:-$(id -u)} -eq 0 ]]; then
    app_load_config _BLOG_DERIVE_PATHS
  fi
}

restore_nginx_root_backup() {
  [[ -e "$DEPLOY_BAK" || -L "$DEPLOY_BAK" ]] || return 0
  if ! safe_rm_dir "$NGINX_ROOT" "NGINX_ROOT"; then
    return 1
  fi
  if ! mv "$DEPLOY_BAK" "$NGINX_ROOT"; then
    return 1
  fi
}

_write_publish_script() {
  local publish_script="/usr/local/bin/blog-publish"
  local publish_tmp
  publish_tmp=$(mktemp "${publish_script}.XXXXXX") || error "$(t app.blog.error.publish_script)"
  # The generated publish script is standalone by design: it embeds its own
  # copies of is_safe_path() and safe_rm_dir() from lib/fs.sh. Keep those
  # helpers in sync when lib/fs.sh changes (safe_rm_dir intentionally calls
  # is_safe_path directly because the generated script has no i18n layer).
  if ! cat > "$publish_tmp" << BKSH
#!/bin/bash
set -euo pipefail
PUBLIC_DIR="${PUBLIC_DIR}"
NGINX_ROOT="${NGINX_ROOT}"
NGINX_ROOT_PARENT="\$(dirname "\$NGINX_ROOT")"
NGINX_ROOT_NAME="\$(basename "\$NGINX_ROOT")"
DEPLOY_TMP="\$(mktemp -d "\${NGINX_ROOT_PARENT}/.\${NGINX_ROOT_NAME}.new.XXXXXX")" || {
  echo "Failed to create a staging directory under \$NGINX_ROOT_PARENT" >&2
  exit 1
}
DEPLOY_BAK="\${NGINX_ROOT}.bak.\$(date +%Y%m%d%H%M%S)"
is_safe_path() {
  local path="\${1:-}"
  [[ -n "\$path" ]] || return 1
  [[ "\$path" = /* ]] || return 1
  while [[ "\$path" != "/" && "\$path" == */ ]]; do path="\${path%/}"; done
  case "\$path" in
    /|.|..|*'/../'*|*'/..'|*'/./'*|*'/.')
      return 1
      ;;
    /bin|/boot|/dev|/etc|/home|/lib|/lib64|/opt|/proc|/root|/run|/sbin|/sys|/tmp|/usr|/var|/usr/local)
      return 1
      ;;
  esac
  local remainder="\${path#/}"
  [[ "\$remainder" == */* ]] || return 1
  case "\$path" in
    /var/lib|/var/log|/var/www|/var/cache|/var/run|/var/spool|/usr/local/bin|/usr/local/lib|/usr/share|/mnt|/media|/srv|/data|/backup|/www|/export|/pool)
      return 1
      ;;
  esac
  return 0
}
safe_rm_dir() {
  local path="\$1"
  while [[ "\$path" != "/" && "\$path" == */ ]]; do path="\${path%/}"; done
  is_safe_path "\$path" || return 1
  [[ -e "\$path" || -L "\$path" ]] || return 0
  [[ -d "\$path" || -L "\$path" ]] || return 1
  rm -rf -- "\$path"
}
restore_nginx_root_backup() {
  [[ -e "\$DEPLOY_BAK" || -L "\$DEPLOY_BAK" ]] || return 0
  if ! safe_rm_dir "\$NGINX_ROOT" "NGINX_ROOT"; then
    return 1
  fi
  if ! mv "\$DEPLOY_BAK" "\$NGINX_ROOT"; then
    return 1
  fi
}
[[ -d "\$PUBLIC_DIR" ]] || { echo "PUBLIC_DIR is missing: \$PUBLIC_DIR" >&2; exit 1; }
if ! mkdir -p "\$NGINX_ROOT_PARENT"; then
  echo "Failed to create the Nginx root parent: \$NGINX_ROOT_PARENT" >&2
  exit 1
fi
if cp -a "\${PUBLIC_DIR}/." "\$DEPLOY_TMP/"; then
  if [[ -e "\$NGINX_ROOT" || -L "\$NGINX_ROOT" ]]; then
    if ! mv "\$NGINX_ROOT" "\$DEPLOY_BAK"; then
      rm -rf "\$DEPLOY_TMP"
      echo "Failed to back up the live Nginx root: \$NGINX_ROOT" >&2
      exit 1
    fi
  fi
  if mv "\$DEPLOY_TMP" "\$NGINX_ROOT"; then
    if [[ -e "\$DEPLOY_BAK" || -L "\$DEPLOY_BAK" ]]; then
      rm -rf "\$DEPLOY_BAK"
    fi
  else
    rm -rf "\$DEPLOY_TMP"
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
  atomic_copy_file "$source_path" "$backup_path"
}

_write_blog_file() {
  local target_path="$1"
  if ! atomic_write_file "$target_path" 644; then
    error "$(t app.blog.error.file_write "$target_path")"
  fi
}

_blog_build_site() {
  step "$(t app.blog.step_build)"
  if ! mkdir -p "$PUBLIC_DIR"; then
    error "$(t app.blog.error.public_dir "$PUBLIC_DIR")"
  fi
  if ! cd "$SITE_DIR"; then
    error "$(t app.blog.error.site_access "$SITE_DIR")"
  fi
  if ! git add -A; then
    error "$(t app.blog.error.git_stage "$SITE_DIR")"
  fi
  if git diff --cached --quiet; then
    :
  else
    _git_diff_status=$?
    if [[ "$_git_diff_status" -eq 1 ]]; then
      if ! git commit -q -m "init: add site content"; then
        error "$(t app.blog.error.git_commit "$SITE_DIR")"
      fi
    else
      error "$(t app.blog.error.git_diff "$SITE_DIR")"
    fi
  fi
  info "$(t app.blog.git_committed)"
  hugo --destination "$PUBLIC_DIR" --gc --minify \
    || error "$(t app.blog.error.hugo_build)"
  PAGE_COUNT=$(find "$PUBLIC_DIR" -name "*.html" | wc -l)
  success "$(t app.blog.build_complete "$PAGE_COUNT")"
}

_blog_deploy_public() {
  step "$(t app.blog.step_nginx)"
  NGINX_ROOT_PARENT="$(dirname "$NGINX_ROOT")"
  NGINX_ROOT_NAME="$(basename "$NGINX_ROOT")"
  if ! mkdir -p "$NGINX_ROOT_PARENT"; then
    error "$(t app.blog.error.nginx_root_parent "$NGINX_ROOT_PARENT")"
  fi
  if ! DEPLOY_TMP="$(mktemp -d "${NGINX_ROOT_PARENT}/.${NGINX_ROOT_NAME}.new.XXXXXX")"; then
    error "$(t app.blog.error.static_deploy "$NGINX_ROOT")"
  fi
  DEPLOY_BAK="${NGINX_ROOT}.bak.$(date +%Y%m%d%H%M%S)"
  if cp -a "${PUBLIC_DIR}/." "$DEPLOY_TMP/"; then
    if [[ -e "$NGINX_ROOT" || -L "$NGINX_ROOT" ]]; then
      if ! mv "$NGINX_ROOT" "$DEPLOY_BAK"; then
        rm -rf "$DEPLOY_TMP"
        error "$(t app.blog.error.static_deploy "$NGINX_ROOT")"
      fi
    fi
    if mv "$DEPLOY_TMP" "$NGINX_ROOT"; then
      if [[ -e "$DEPLOY_BAK" || -L "$DEPLOY_BAK" ]]; then
        rm -rf "$DEPLOY_BAK"
      fi
    else
      rm -rf "$DEPLOY_TMP"
      restore_nginx_root_backup || error "$(t app.blog.error.static_deploy "$NGINX_ROOT")"
      error "$(t app.blog.error.static_deploy "$NGINX_ROOT")"
    fi
  else
    rm -rf "$DEPLOY_TMP"
    error "$(t app.blog.error.static_deploy "$NGINX_ROOT")"
  fi
  success "$(t app.blog.static_deployed "$NGINX_ROOT")"
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
_validate_config_values
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
HUGO_JSON=$(curl -fsSL --max-time 15 \
  "https://api.github.com/repos/gohugoio/hugo/releases/latest") \
  || error "$(t app.blog.error.github_api)"
HUGO_VER="$(json_tag_name "$HUGO_JSON" --strip-v)"
[[ -z "$HUGO_VER" ]] && error "$(t app.blog.error.hugo_version)"
success "$(t app.blog.latest_version "$HUGO_VER")"
DEB_URL="https://github.com/gohugoio/hugo/releases/download/v${HUGO_VER}/hugo_extended_${HUGO_VER}_linux-${DEB_ARCH}.deb"
info "$(t app.blog.download_url "$DEB_URL")"
if ! HUGO_DEB="$(mktemp /tmp/hugo.XXXXXX.deb)"; then
  error "$(t app.blog.error.hugo_download)"
fi
if ! wget -q --show-progress -O "$HUGO_DEB" "$DEB_URL"; then
  if ! rm -f "$HUGO_DEB"; then
    warn "$(t app.blog.warn.hugo_cleanup_failed "$HUGO_DEB")"
  fi
  error "$(t app.blog.error.hugo_download)"
fi
if [[ ! -s "$HUGO_DEB" ]]; then
  if ! rm -f "$HUGO_DEB"; then
    warn "$(t app.blog.warn.hugo_cleanup_failed "$HUGO_DEB")"
  fi
  error "$(t app.blog.error.hugo_download)"
fi
if ! dpkg -i "$HUGO_DEB"; then
  if ! rm -f "$HUGO_DEB"; then
    warn "$(t app.blog.warn.hugo_cleanup_failed "$HUGO_DEB")"
  fi
  error "$(t app.blog.error.hugo_install)"
fi
if ! rm -f "$HUGO_DEB"; then
  error "$(t app.blog.error.hugo_cleanup "$HUGO_DEB")"
fi
success "$(t app.blog.hugo_installed "$(hugo version | head -1)")"
step "$(t app.blog.step_init_site)"
if ! mkdir -p "$(dirname "$SITE_DIR")"; then
  error "$(t app.blog.error.site_parent_dir "$SITE_DIR")"
fi
if [[ -d "$SITE_DIR" ]]; then
  warn "$(t app.blog.site_exists "$SITE_DIR")"
else
  if ! hugo new site "$SITE_DIR" --format toml; then
    error "$(t app.blog.error.site_create "$SITE_DIR" "$SITE_DIR")"
  fi
  success "$(t app.blog.site_created "$SITE_DIR")"
fi
if [[ ! -d "${SITE_DIR}/.git" ]]; then
  if ! git -C "$SITE_DIR" init -q; then
    error "$(t app.blog.error.git_init "$SITE_DIR" "$SITE_DIR")"
  fi
  if ! git -C "$SITE_DIR" config user.email "blog@localhost" \
      || ! git -C "$SITE_DIR" config user.name "${BLOG_AUTHOR}"; then
    error "$(t app.blog.error.git_config "$SITE_DIR")"
  fi
  success "$(t app.blog.git_initialized)"
fi
step "$(t app.blog.step_theme)"
THEME_DIR="${SITE_DIR}/themes/${THEME_NAME}"
if [[ -d "$THEME_DIR" && -f "$THEME_DIR/theme.toml" ]]; then
  info "$(t app.blog.theme_exists)"
  success "$(t app.blog.theme_current)"
else
  info "$(t app.blog.clone_theme)"
  if ! git -C "$SITE_DIR" submodule add --depth 1 "$THEME_REPO" "themes/${THEME_NAME}" 2>/dev/null; then
    if ! git clone --depth 1 "$THEME_REPO" "$THEME_DIR"; then
      error "$(t app.blog.error.theme_install "$THEME_DIR")"
    fi
    rm -rf "$THEME_DIR/.git"
  fi
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
if ! mkdir -p \
  "${SITE_DIR}/content/post/hello-world" \
  "${SITE_DIR}/content/page/about" \
  "${SITE_DIR}/content/page/archives" \
  "${SITE_DIR}/static/img"; then
  error "$(t app.blog.error.content_dirs "$SITE_DIR")"
fi
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
  if ! mkdir -p "$CMS_ADMIN_DIR"; then
    error "$(t app.blog.error.cms_admin_dir "$CMS_ADMIN_DIR")"
  fi
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
_blog_build_site
_blog_deploy_public
_write_publish_script
NGINX_CONF="/etc/nginx/sites-available/blog"
app_write_nginx_config_file "$NGINX_CONF" "app.blog.error.nginx_write" << NGINX
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
app_write_nginx_site_link "$NGINX_CONF" /etc/nginx/sites-enabled/blog "app.blog.error.nginx_write"
_blog_remove_file /etc/nginx/sites-enabled/default
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
app_save_config
step "$(t app.blog.step_health)"
local _blog_summary_state="ready"
HTTP_CODE=$(curl -H "Host: ${BLOG_DOMAIN:-localhost}" -o /dev/null -s -w "%{http_code}" --max-time 5 "http://127.0.0.1/" || echo "000")
if [[ "$HTTP_CODE" == "200" ]]; then
  success "$(t app.blog.http_ok)"
else
  warn "$(t app.blog.http_warn "$HTTP_CODE")"
  _blog_summary_state="pending"
fi
INTERNAL_IP=$(hostname -I 2>/dev/null | awk '{print $1}' || true)
INTERNAL_IP="${INTERNAL_IP:-YOUR_SERVER_IP}"
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

_blog_status_path() {
  local label="$1" path="$2"
  if [[ -e "$path" || -L "$path" ]]; then
    printf '  %s: %b%s%b (%s)\n' "$label" "$GREEN" "$(t app.blog.status.exists)" "$NC" "$path"
  else
    printf '  %s: %b%s%b (%s)\n' "$label" "$RED" "$(t app.blog.status.missing)" "$NC" "$path"
  fi
}

do_status() {
  show_banner
  [[ $EUID -ne 0 ]] && warn "$(t app.blog.warn.non_root_status "$0")"
  _blog_load_config_if_root
  step "$(t app.blog.step_status)"

  _blog_status_path "$(t app.blog.status.site)" "$SITE_DIR"
  _blog_status_path "$(t app.blog.status.public)" "$PUBLIC_DIR"
  _blog_status_path "$(t app.blog.status.nginx_root)" "$NGINX_ROOT"
  _blog_status_path "$(t app.blog.status.nginx_config)" "/etc/nginx/sites-available/blog"
  _blog_status_path "$(t app.blog.status.publish_helper)" "/usr/local/bin/blog-publish"

  if [[ -d "$PUBLIC_DIR" ]]; then
    local html_count
    html_count=$(find "$PUBLIC_DIR" -name "*.html" 2>/dev/null | wc -l | tr -d '[:space:]')
    printf '  %s\n' "$(t app.blog.status.html_count "${html_count:-0}")"
  fi

  if command -v systemctl >/dev/null 2>&1; then
    printf '  %s: %s\n' "$(t app.blog.status.nginx)" "$(service_status_label nginx)"
  fi

  if command -v hugo >/dev/null 2>&1; then
    printf '  %s: %s\n' "$(t app.blog.status.hugo)" "$(hugo version 2>/dev/null | head -1 || t status.unknown)"
  else
    printf '  %s: %b%s%b\n' "$(t app.blog.status.hugo)" "$YELLOW" "$(t app.blog.status.hugo_missing)" "$NC"
  fi

  if command -v curl >/dev/null 2>&1; then
    local http_code
    http_code=$(curl -H "Host: ${BLOG_DOMAIN:-localhost}" -o /dev/null -s -w "%{http_code}" --max-time 5 "http://127.0.0.1/" 2>/dev/null || true)
    http_code="${http_code:-000}"
    printf '  %s: %s\n' "$(t app.blog.status.local_health)" "$(t app.blog.status.local_response "$http_code" "${BLOG_DOMAIN:-localhost}")"
  else
    printf '  %s: %s\n' "$(t app.blog.status.local_health)" "$(t app.blog.status.local_skip)"
  fi
}

do_update() {
  show_banner
  require_root "update"
  _blog_load_config_if_root
  command -v systemctl >/dev/null 2>&1 || error "$(t app.blog.error.systemd_required)"
  command -v nginx >/dev/null 2>&1 || error "$(t app.blog.update.error_nginx_missing)"
  command -v hugo >/dev/null 2>&1 || error "$(t app.blog.update.error_hugo_missing)"
  acquire_lock
  require_safe_path "SITE_DIR" "$SITE_DIR"
  require_safe_path "PUBLIC_DIR" "$PUBLIC_DIR"
  require_safe_path "NGINX_ROOT" "$NGINX_ROOT"
  [[ -d "$SITE_DIR" ]] || error "$(t app.blog.update.error_not_installed "$SITE_DIR")"
  [[ -d "${SITE_DIR}/.git" ]] || error "$(t app.blog.update.error_git_missing "$SITE_DIR")"
  [[ -f /etc/nginx/sites-available/blog || -L /etc/nginx/sites-enabled/blog ]] \
    || error "$(t app.blog.update.error_nginx_site_missing)"

  _blog_build_site
  _blog_deploy_public
  _write_publish_script

  if nginx -t >/dev/null 2>&1; then
    if systemctl reload nginx; then
      success "$(t app.blog.update.nginx_reloaded)"
    else
      warn "$(t app.blog.update.nginx_reload_failed)"
    fi
  else
    nginx -t >&2 || true
    warn "$(t app.blog.update.nginx_config_failed)"
  fi

  step "$(t app.blog.step_health)"
  local http_code
  http_code=$(curl -H "Host: ${BLOG_DOMAIN:-localhost}" -o /dev/null -s -w "%{http_code}" --max-time 5 "http://127.0.0.1/" 2>/dev/null || echo "000")
  if [[ "$http_code" == "200" ]]; then
    success "$(t app.blog.http_ok)"
  else
    warn "$(t app.blog.http_warn "$http_code")"
  fi
  success "$(t app.blog.update.success "$NGINX_ROOT")"
}

do_backup() {
  show_banner
  require_root "backup"
  _blog_load_config_if_root
  acquire_lock
  step "$(t app.blog.step_backup)"
  require_safe_path "BLOG_BACKUP_DIR" "$BLOG_BACKUP_DIR"
  if ! mkdir -p "$BLOG_BACKUP_DIR"; then
    error "$(t app.blog.backup.error_dir "$BLOG_BACKUP_DIR")"
  fi

  local timestamp archive archive_tmp stage copied=false
  timestamp=$(date +%Y%m%d_%H%M%S)
  archive="${BLOG_BACKUP_DIR}/blog_${timestamp}.tar.gz"
  archive_tmp="${archive}.tmp"
  if ! stage=$(mktemp -d "${BLOG_BACKUP_DIR}/.blog-backup.XXXXXX"); then
    error "$(t app.blog.backup.error_dir "$BLOG_BACKUP_DIR")"
  fi

  _backup_dir_into_stage() {
    local source="$1" target_name="$2"
    if [[ ! -d "$source" ]]; then
      warn "$(t app.blog.backup.warn_missing "$source")"
      return 0
    fi
    if ! mkdir -p "${stage}/${target_name}" || ! cp -a "${source}/." "${stage}/${target_name}/"; then
      rm -rf "$stage" "$archive_tmp"
      error "$(t app.blog.backup.error_archive "$archive")"
    fi
    copied=true
  }

  _backup_file_into_stage() {
    local source="$1" target_name="$2"
    if [[ ! -f "$source" ]]; then
      warn "$(t app.blog.backup.warn_missing "$source")"
      return 0
    fi
    if ! cp -a "$source" "${stage}/${target_name}"; then
      rm -rf "$stage" "$archive_tmp"
      error "$(t app.blog.backup.error_archive "$archive")"
    fi
    copied=true
  }

  _backup_dir_into_stage "$SITE_DIR" site
  _backup_dir_into_stage "$PUBLIC_DIR" public
  _backup_dir_into_stage "$NGINX_ROOT" nginx-root
  _backup_file_into_stage /etc/nginx/sites-available/blog nginx-site.conf
  _backup_file_into_stage /usr/local/bin/blog-publish blog-publish

  if [[ "$copied" != "true" ]]; then
    rm -rf "$stage" "$archive_tmp"
    error "$(t app.blog.backup.error_no_sources)"
  fi
  if ! tar -czf "$archive_tmp" -C "$stage" .; then
    rm -rf "$stage" "$archive_tmp"
    error "$(t app.blog.backup.error_archive "$archive")"
  fi
  rm -rf "$stage"
  if ! chmod 600 "$archive_tmp" || ! mv "$archive_tmp" "$archive"; then
    rm -f "$archive_tmp"
    error "$(t app.blog.backup.error_archive "$archive")"
  fi
  local digest installed_version=""
  if ! digest="$(backup_write_sha256 "$archive")" \
     || ! backup_write_manifest "$archive" "blog" 1 "$installed_version"; then
    warn "$(t app.blog.backup.warn_integrity "$archive")"
  fi
  success "$(t app.blog.backup.success "$archive")"

  local _keep_days="${BLOG_BACKUP_KEEP_DAYS}"
  [[ "$_keep_days" =~ ^[0-9]+$ ]] || _keep_days=0
  if [[ "$_keep_days" -gt 0 ]]; then
    local old_backup
    while IFS= read -r -d '' old_backup; do
      if rm -f "$old_backup"; then
        info "$(t app.blog.backup.cleaned "$old_backup")"
      else
        warn "$(t app.blog.backup.clean_failed "$old_backup")"
      fi
    done < <(find "$BLOG_BACKUP_DIR" -maxdepth 1 -name 'blog_*.tar.gz' -type f -mtime "+${_keep_days}" -print0 2>/dev/null)
  fi
}

_blog_latest_backup_archive() {
  local backup_dir="$1" candidate candidate_mtime latest="" latest_mtime=0
  while IFS= read -r -d '' candidate; do
    candidate_mtime=$(stat -c %Y "$candidate" 2>/dev/null || echo 0)
    if [[ "$candidate_mtime" =~ ^[0-9]+$ && "$candidate_mtime" -gt "$latest_mtime" ]]; then
      latest="$candidate"
      latest_mtime="$candidate_mtime"
    fi
  done < <(find "$backup_dir" -maxdepth 1 -name 'blog_*.tar.gz' -type f -print0 2>/dev/null)
  printf '%s' "$latest"
}

do_verify() {
  show_banner
  require_root "verify"
  _blog_load_config_if_root
  step "$(t backup.verify.step)"
  require_safe_path "BLOG_BACKUP_DIR" "$BLOG_BACKUP_DIR"
  [[ -d "$BLOG_BACKUP_DIR" ]] || error "$(t app.blog.restore.no_backups "$BLOG_BACKUP_DIR")"
  local archive verdict
  archive="$(_blog_latest_backup_archive "$BLOG_BACKUP_DIR")"
  [[ -n "$archive" ]] || error "$(t app.blog.restore.no_backups "$BLOG_BACKUP_DIR")"
  verdict="$(backup_verify_latest_json "$BLOG_BACKUP_DIR" 'blog_*.tar.gz')"
  case "$(state_json_field "$verdict" state 2>/dev/null || true)" in
    unverified)
      warn "$(t backup.verify.unverified "$(basename "$archive")")"
      return 0
      ;;
  esac
  if backup_verify_archive "$archive"; then
    success "$(t backup.verify.verified "$(basename "$archive")" \
      "$(backup_read_sha256 "${archive}.sha256")")"
    return 0
  fi
  error "$(t backup.verify.failed "$(basename "$archive")")"
}

_blog_archive_paths_are_safe() {
  local archive="$1" member
  tar -tzf "$archive" | while IFS= read -r member; do
    case "$member" in
      ""|/*|*'/../'*|../*|*'/..'|..|*"\\"*)
        return 1
        ;;
    esac
  done
}

_blog_restore_dir_from_backup() {
  local source_dir="$1" target_name="$2" target_path="$3"
  local target_parent target_base restore_tmp restore_bak
  require_safe_path "$target_name" "$target_path"
  target_parent="$(dirname "$target_path")"
  target_base="$(basename "$target_path")"
  if ! mkdir -p "$target_parent"; then
    error "$(t app.blog.restore.error_target "$target_path")"
  fi
  if ! restore_tmp=$(mktemp -d "${target_parent}/.${target_base}.restore.XXXXXX"); then
    error "$(t app.blog.restore.error_target "$target_path")"
  fi
  restore_bak="${target_path}.restore.$(date +%Y%m%d%H%M%S)"
  if ! cp -a "${source_dir}/." "$restore_tmp/"; then
    rm -rf "$restore_tmp"
    error "$(t app.blog.restore.error_target "$target_path")"
  fi
  if [[ -e "$target_path" || -L "$target_path" ]]; then
    if ! mv "$target_path" "$restore_bak"; then
      rm -rf "$restore_tmp"
      error "$(t app.blog.restore.error_target "$target_path")"
    fi
  fi
  if mv "$restore_tmp" "$target_path"; then
    rm -rf "$restore_bak"
    success "$(t app.blog.restore.restored_dir "$target_path")"
  else
    rm -rf "$restore_tmp"
    if [[ -e "$restore_bak" || -L "$restore_bak" ]]; then
      mv "$restore_bak" "$target_path" 2>/dev/null || true
    fi
    error "$(t app.blog.restore.error_target "$target_path")"
  fi
}

_blog_restore_file_from_backup() {
  local source_file="$1" target_name="$2" target_path="$3" mode="$4"
  require_safe_path "$target_name" "$target_path"
  if ! atomic_copy_file "$source_file" "$target_path" "$mode" root:root; then
    error "$(t app.blog.restore.error_target "$target_path")"
  fi
  success "$(t app.blog.restore.restored_file "$target_path")"
}

do_restore() {
  show_banner
  require_root "restore"
  _blog_load_config_if_root
  acquire_lock
  step "$(t app.blog.step_restore)"
  require_safe_path "BLOG_BACKUP_DIR" "$BLOG_BACKUP_DIR"
  local backup_dir="${BLOG_BACKUP_DIR%/}" archive extract_dir restored=false
  [[ -d "$backup_dir" ]] || error "$(t app.blog.restore.no_backups "$backup_dir")"
  archive="${BLOG_RESTORE_ARCHIVE:-}"
  if [[ -z "$archive" ]]; then
    archive="$(_blog_latest_backup_archive "$backup_dir")"
  fi
  [[ -n "$archive" ]] || error "$(t app.blog.restore.no_backups "$backup_dir")"
  [[ "$archive" == "$backup_dir"/blog_*.tar.gz && -f "$archive" ]] \
    || error "$(t app.blog.restore.invalid_archive "$archive")"
  if ! _blog_archive_paths_are_safe "$archive"; then
    error "$(t app.blog.restore.invalid_archive "$archive")"
  fi
  info "$(t app.blog.restore.using "$archive")"
  if ! extract_dir=$(mktemp -d "${backup_dir}/.blog-restore.XXXXXX"); then
    error "$(t app.blog.restore.error_extract "$archive")"
  fi
  if ! tar -xzf "$archive" -C "$extract_dir" >&2; then
    rm -rf "$extract_dir"
    error "$(t app.blog.restore.error_extract "$archive")"
  fi

  if [[ -d "${extract_dir}/site" ]]; then
    _blog_restore_dir_from_backup "${extract_dir}/site" "SITE_DIR" "$SITE_DIR"
    restored=true
  else
    warn "$(t app.blog.restore.warn_missing site)"
  fi
  if [[ -d "${extract_dir}/public" ]]; then
    _blog_restore_dir_from_backup "${extract_dir}/public" "PUBLIC_DIR" "$PUBLIC_DIR"
    restored=true
  else
    warn "$(t app.blog.restore.warn_missing public)"
  fi
  if [[ -d "${extract_dir}/nginx-root" ]]; then
    _blog_restore_dir_from_backup "${extract_dir}/nginx-root" "NGINX_ROOT" "$NGINX_ROOT"
    restored=true
  else
    warn "$(t app.blog.restore.warn_missing nginx-root)"
  fi
  if [[ -f "${extract_dir}/nginx-site.conf" ]]; then
    _blog_restore_file_from_backup "${extract_dir}/nginx-site.conf" "NGINX_SITE" /etc/nginx/sites-available/blog 644
    app_write_nginx_site_link /etc/nginx/sites-available/blog /etc/nginx/sites-enabled/blog "app.blog.error.nginx_write"
    restored=true
  else
    warn "$(t app.blog.restore.warn_missing nginx-site.conf)"
  fi
  if [[ -f "${extract_dir}/blog-publish" ]]; then
    _blog_restore_file_from_backup "${extract_dir}/blog-publish" "BLOG_PUBLISH" /usr/local/bin/blog-publish 750
    restored=true
  else
    warn "$(t app.blog.restore.warn_missing blog-publish)"
  fi
  rm -rf "$extract_dir"
  [[ "$restored" == "true" ]] || error "$(t app.blog.restore.invalid_archive "$archive")"

  if command -v nginx >/dev/null 2>&1; then
    if nginx -t; then
      if systemctl reload nginx; then
        success "$(t app.blog.restore.nginx_reloaded)"
      else
        warn "$(t app.blog.restore.nginx_reload_failed)"
      fi
    else
      error "$(t app.blog.restore.error_nginx_config)"
    fi
  else
    warn "$(t app.blog.restore.nginx_missing)"
  fi
  success "$(t app.blog.restore.success)"
}

_blog_remove_file() {
  local path="$1"
  [[ -e "$path" || -L "$path" ]] || return 0
  if rm -f "$path"; then
    success "$(t app.blog.uninstall.removed_file "$path")"
  else
    error "$(t app.blog.uninstall.remove_failed "$path")"
  fi
}

_blog_remove_dir() {
  local name="$1" path="$2"
  [[ -e "$path" || -L "$path" ]] || return 0
  if safe_rm_dir "$path" "$name"; then
    success "$(t app.blog.uninstall.removed_dir "$path")"
  else
    error "$(t app.blog.uninstall.remove_failed "$path")"
  fi
}

do_uninstall() {
  show_banner
  require_root "uninstall"
  _blog_load_config_if_root
  acquire_lock
  require_safe_path "SITE_DIR" "$SITE_DIR"
  require_safe_path "PUBLIC_DIR" "$PUBLIC_DIR"
  require_safe_path "NGINX_ROOT" "$NGINX_ROOT"
  require_safe_path "BLOG_BACKUP_DIR" "$BLOG_BACKUP_DIR"

  warn "$(t app.blog.uninstall.warning)"
  local confirm delete_backups
  if deploy_assume_yes; then
    confirm="YES"
  else
    prompt "$(t app.blog.uninstall.continue_prompt)"
    read -r confirm
  fi
  [[ "$confirm" == "YES" ]] || { info "$(t app.blog.uninstall.cancelled)"; exit 0; }
  if deploy_assume_yes; then
    if deploy_env_truthy DEPLOY_DELETE_BACKUP; then
      delete_backups="yes"
    else
      delete_backups="no"
    fi
  else
    prompt "$(t app.blog.uninstall.delete_backups_prompt "$BLOG_BACKUP_DIR")"
    read -r delete_backups
  fi

  _blog_remove_file /etc/nginx/sites-enabled/blog
  _blog_remove_file /etc/nginx/sites-available/blog
  _blog_remove_file /usr/local/bin/blog-publish
  _blog_remove_dir "PUBLIC_DIR" "$PUBLIC_DIR"
  _blog_remove_dir "NGINX_ROOT" "$NGINX_ROOT"
  _blog_remove_dir "SITE_DIR" "$SITE_DIR"

  if [[ "${delete_backups,,}" == "y" || "${delete_backups,,}" == "yes" ]]; then
    _blog_remove_dir "BLOG_BACKUP_DIR" "$BLOG_BACKUP_DIR"
  else
    info "$(t app.blog.uninstall.kept_backups "$BLOG_BACKUP_DIR")"
  fi

  if command -v nginx >/dev/null 2>&1 && command -v systemctl >/dev/null 2>&1; then
    if nginx -t >/dev/null 2>&1; then
      if systemctl reload nginx >/dev/null 2>&1; then
        success "$(t app.blog.uninstall.nginx_reloaded)"
      else
        nginx -t >&2 || true
        warn "$(t app.blog.uninstall.nginx_reload_failed)"
      fi
    else
      nginx -t >&2 || true
      warn "$(t app.blog.uninstall.nginx_test_failed)"
    fi
  fi

  success "$(t app.blog.uninstall.success)"
}
