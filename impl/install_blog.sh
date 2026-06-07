#!/bin/bash
set -euo pipefail
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'
info()    { echo -e "${BLUE}[·]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✗]${NC} $*"; exit 1; }
step()    { echo -e "\n${CYAN}${BOLD}── $* ──────────────────────────────${NC}"; }
BLOG_DOMAIN="blog.tarxf.com"
BLOG_TITLE="Abyte 的个人博客"
BLOG_AUTHOR="Abyte"
BLOG_DESCRIPTION="记录技术与生活"
BLOG_LANG="zh-cn"
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
echo -e "  ${BOLD}主题：${CYAN}hugo-theme-stack${NC}"
echo -e "  ${BOLD}服务：${CYAN}Hugo + Nginx + Decap CMS${NC}\n"
[[ $EUID -ne 0 ]] && error "$(t error.root_required "$0" "${1:-}")"
command -v apt-get >/dev/null 2>&1 || error "$(t app.blog.error.apt_only)"
command -v systemctl >/dev/null 2>&1 || error "$(t app.blog.error.systemd_required)"
ARCH=$(uname -m)
case $ARCH in
  x86_64)  DEB_ARCH="amd64" ;;
  aarch64) DEB_ARCH="arm64" ;;
  *)       error "$(t app.blog.error.arch "$ARCH")" ;;
esac
step "Step 1  安装系统依赖"
apt-get update -qq
apt-get install -y -qq curl wget git nginx ca-certificates
success "依赖安装完成（curl / wget / git / nginx）"
step "Step 2  安装 Hugo Extended"
info "查询 Hugo 最新版本..."
HUGO_VER=$(curl -fsSL --max-time 15 \
  "https://api.github.com/repos/gohugoio/hugo/releases/latest" \
  | grep '"tag_name"' | head -1 \
  | sed 's/.*"v\([^"]*\)".*/\1/') \
  || error "无法访问 GitHub API，请检查网络连接"
[[ -z "$HUGO_VER" ]] && error "获取 Hugo 版本失败"
success "最新版本：v${HUGO_VER}"
DEB_URL="https://github.com/gohugoio/hugo/releases/download/v${HUGO_VER}/hugo_extended_${HUGO_VER}_linux-${DEB_ARCH}.deb"
info "下载：${DEB_URL}"
wget -q --show-progress -O /tmp/hugo.deb "$DEB_URL" \
  || error "Hugo 下载失败，请检查网络或手动下载"
dpkg -i /tmp/hugo.deb
rm -f /tmp/hugo.deb
success "Hugo $(hugo version | head -1) 安装完成"
step "Step 3  初始化 Hugo 博客项目"
mkdir -p "$(dirname "$SITE_DIR")"
if [[ -d "$SITE_DIR" ]]; then
  warn "目录 ${SITE_DIR} 已存在，跳过初始化（保留现有内容）"
else
  hugo new site "$SITE_DIR" --format toml
  success "Hugo 项目创建于：${SITE_DIR}"
fi
if [[ ! -d "${SITE_DIR}/.git" ]]; then
  git -C "$SITE_DIR" init -q
  git -C "$SITE_DIR" config user.email "blog@localhost"
  git -C "$SITE_DIR" config user.name "${BLOG_AUTHOR}"
  success "Git 仓库已初始化"
fi
step "Step 4  安装 hugo-theme-stack 主题"
THEME_DIR="${SITE_DIR}/themes/${THEME_NAME}"
if [[ -d "$THEME_DIR" && -f "$THEME_DIR/theme.toml" ]]; then
  info "主题已存在，跳过克隆"
  success "主题已是最新"
else
  info "克隆主题仓库（首次可能需要一点时间）..."
  git -C "$SITE_DIR" submodule add --depth 1 "$THEME_REPO" "themes/${THEME_NAME}" 2>/dev/null \
    || { git clone --depth 1 "$THEME_REPO" "$THEME_DIR" && rm -rf "$THEME_DIR/.git"; }
  success "主题安装完成"
fi
step "Step 5  生成站点配置"
CONFIG_FILE="${SITE_DIR}/hugo.toml"
if [[ -f "$CONFIG_FILE" && $(wc -l < "$CONFIG_FILE") -gt 3 ]]; then
  cp "$CONFIG_FILE" "${CONFIG_FILE}.bak.$(date +%Y%m%d%H%M%S)"
  warn "已备份旧配置"
fi
if [[ -n "$BLOG_DOMAIN" ]]; then
  BASE_URL="https://${BLOG_DOMAIN}"
else
  BASE_URL="http://localhost"
fi
cat > "$CONFIG_FILE" << TOML
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
    name = "首页"
    url = "/"
    weight = 1
  [[menu.main]]
    name = "归档"
    url = "/archives"
    weight = 2
  [[menu.main]]
    name = "分类"
    url = "/categories"
    weight = 3
  [[menu.main]]
    name = "标签"
    url = "/tags"
    weight = 4
  [[menu.main]]
    name = "关于"
    url = "/about"
    weight = 5

[taxonomies]
  category = "categories"
  tag = "tags"
  series = "series"
TOML
success "配置文件已写入：${CONFIG_FILE}"
step "Step 6  创建示例文章与页面"
mkdir -p "${SITE_DIR}/content/post/hello-world"
mkdir -p "${SITE_DIR}/content/page/about"
mkdir -p "${SITE_DIR}/content/page/archives"
mkdir -p "${SITE_DIR}/static/img"
if [[ ! -f "${SITE_DIR}/content/post/hello-world/index.md" ]]; then
cat > "${SITE_DIR}/content/post/hello-world/index.md" << MD
+++
title = "你好，世界！"
date = "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
description = "我的第一篇博客文章"
draft = false
categories = ["随笔"]
tags = ["Hugo", "博客"]
+++

## 欢迎来到我的博客

这是用 **Hugo** + **Stack 主题** 搭建的个人博客，已经成功运行！

### 为什么选择 Hugo？

- ⚡ 极速构建，数千篇文章几秒完成
- 📝 Markdown 写作，专注内容
- 🎨 丰富主题，Stack 主题对中文友好
- 🆓 完全免费开源

### 开始写作

在 \`content/post/\` 目录下创建文件夹和 \`index.md\` 即可发布新文章。

\`\`\`bash
# Create a new post quickly.
hugo new content post/my-new-post/index.md
\`\`\`

祝写作愉快！✨
MD
success "示例文章已创建"
fi
if [[ ! -f "${SITE_DIR}/content/page/about/index.md" ]]; then
cat > "${SITE_DIR}/content/page/about/index.md" << MD
+++
title = "关于"
date = "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
menu = "main"
+++

## 关于我

你好！我是 **${BLOG_AUTHOR}**，欢迎来到我的博客。

这里记录我的技术学习、生活感悟和各种折腾经历。

---

*本站使用 [Hugo](https://gohugo.io) 构建，主题为 [Stack](https://github.com/CaiJimmy/hugo-theme-stack)。*
MD
success "关于页面已创建"
fi
if [[ ! -f "${SITE_DIR}/content/page/archives/index.md" ]]; then
cat > "${SITE_DIR}/content/page/archives/index.md" << MD
+++
title = "归档"
date = "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
layout = "archives"
+++
MD
success "归档页面已创建"
fi
step "Step 7  集成 Decap CMS（可视化内容管理）"
if [[ "$ENABLE_CMS" != "true" ]]; then
  warn "ENABLE_CMS=false，跳过 Decap CMS 安装"
else
  CMS_ADMIN_DIR="${SITE_DIR}/static/admin"
  mkdir -p "$CMS_ADMIN_DIR"
  cat > "${CMS_ADMIN_DIR}/index.html" << 'HTML'
<!doctype html>
<html>
  <head>
    <meta charset="utf-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <meta name="robots" content="noindex" />
    <title>内容管理</title>
  </head>
  <body>
    <script src="https://unpkg.com/decap-cms@^3.0.0/dist/decap-cms.js"></script>
  </body>
</html>
HTML
  cat > "${CMS_ADMIN_DIR}/config.yml" << YAML
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
    label: "博客文章"
    label_singular: "文章"
    folder: "content/post"
    path: "{{slug}}/index"
    media_folder: ""
    public_folder: ""
    create: true
    slug: "{{slug}}"
    preview_path: "post/{{slug}}/"
    format: toml-frontmatter
    fields:
      - { label: "标题", name: "title", widget: "string" }
      - { label: "发布时间", name: "date", widget: "datetime", date_format: "YYYY-MM-DD", time_format: "HH:mm:ss", format: "YYYY-MM-DDTHH:mm:ssZ" }
      - { label: "摘要 / 描述", name: "description", widget: "string", required: false }
      - { label: "草稿", name: "draft", widget: "boolean", default: false }
      - label: "分类"
        name: "categories"
        widget: "list"
        allow_add: true
        default: []
        field: { label: "分类名", name: "category", widget: "string" }
      - label: "标签"
        name: "tags"
        widget: "list"
        allow_add: true
        default: []
        field: { label: "标签名", name: "tag", widget: "string" }
      - label: "系列"
        name: "series"
        widget: "list"
        allow_add: true
        required: false
        field: { label: "系列名", name: "series", widget: "string" }
      - label: "封面图片"
        name: "image"
        widget: "image"
        required: false
        choose_url: false
        hint: "文章封面，推荐 1200x630px"
      - { label: "权重（排序）", name: "weight", widget: "number", required: false, value_type: "int" }
      - { label: "正文内容", name: "body", widget: "markdown" }

  # ── Standalone pages (content/page/) ────────────────────────
  - name: "page"
    label: "独立页面"
    label_singular: "页面"
    folder: "content/page"
    path: "{{slug}}/index"
    create: true
    format: toml-frontmatter
    fields:
      - { label: "标题", name: "title", widget: "string" }
      - { label: "发布时间", name: "date", widget: "datetime", format: "YYYY-MM-DDTHH:mm:ssZ" }
      - { label: "草稿", name: "draft", widget: "boolean", default: false }
      - label: "在导航菜单显示"
        name: "menu"
        widget: "select"
        required: false
        options: ["main"]
        hint: "选择 main 后该页面出现在顶部导航"
      - { label: "布局模板", name: "layout", widget: "string", required: false, hint: "特殊布局如 archives，留空使用默认" }
      - { label: "正文内容", name: "body", widget: "markdown" }
YAML
  success "Decap CMS 配置文件已创建：${CMS_ADMIN_DIR}/"
  info "Admin 入口将位于：${CMS_SITE_URL}/admin/"
fi
step "Step 8  构建静态网站（含 CMS admin 文件）"
mkdir -p "$PUBLIC_DIR"
cd "$SITE_DIR"
git add -A
git diff --cached --quiet || git commit -q -m "init: add site content"
info "Git 提交完成，Hugo 可读取文件修改时间"
hugo --destination "$PUBLIC_DIR" --gc --minify \
  || error "Hugo 构建失败，请检查配置"
PAGE_COUNT=$(find "$PUBLIC_DIR" -name "*.html" | wc -l)
success "构建完成，共生成 ${PAGE_COUNT} 个 HTML 页面"
step "Step 9  配置 Nginx"
mkdir -p "$NGINX_ROOT"
cp -a "${PUBLIC_DIR}/." "$NGINX_ROOT/"
success "静态文件已部署到：${NGINX_ROOT}"
NGINX_CONF="/etc/nginx/sites-available/blog"
cat > "$NGINX_CONF" << NGINX
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
ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/blog
rm -f /etc/nginx/sites-enabled/default
nginx -t || error "Nginx 配置验证失败，请检查上方错误"
success "Nginx 配置完成"
step "Step 10  配置防火墙"
FW_DONE=false
if command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "Status: active"; then
  ufw allow "Nginx Full" > /dev/null 2>&1 || ufw allow 80/tcp > /dev/null
  success "ufw 已放行 HTTP/HTTPS"
  FW_DONE=true
fi
if ! $FW_DONE && command -v iptables &>/dev/null; then
  for PORT in 80 443; do
    if ! iptables -C INPUT -p tcp --dport "$PORT" -j ACCEPT 2>/dev/null; then
      iptables -A INPUT -p tcp --dport "$PORT" -j ACCEPT
    fi
  done
  success "iptables 已放行 80/443"
  FW_DONE=true
fi
$FW_DONE || warn "未检测到防火墙，如有云安全组请手动放行 80 和 443 端口"
step "Step 11  启动 Nginx"
systemctl enable nginx --quiet
systemctl restart nginx
sleep 1
if systemctl is-active --quiet nginx; then
  success "Nginx 已启动"
else
  error "Nginx 启动失败，请运行：journalctl -u nginx -n 30"
fi
step "Step 12  健康检查"
HTTP_CODE=$(curl -o /dev/null -s -w "%{http_code}" --max-time 5 "http://127.0.0.1/" || echo "000")
if [[ "$HTTP_CODE" == "200" ]]; then
  success "HTTP 响应正常（200 OK）"
else
  warn "HTTP 返回 ${HTTP_CODE}，如无域名指向请用内网 IP 访问"
fi
INTERNAL_IP=$(hostname -I | awk '{print $1}')
echo ""
echo -e "${BOLD}${GREEN}"
echo "  ╔══════════════════════════════════════════════════════╗"
echo "  ║               🎉  博客部署完成！                     ║"
echo "  ╠══════════════════════════════════════════════════════╣"
if [[ -n "$BLOG_DOMAIN" ]]; then
echo -e "  ║  公网访问  ${CYAN}http://${BLOG_DOMAIN}${GREEN}"
fi
echo -e "  ║  内网访问  ${CYAN}http://${INTERNAL_IP}${GREEN}"
if [[ "$ENABLE_CMS" == "true" ]]; then
echo -e "  ║  CMS 管理  ${CYAN}http://${INTERNAL_IP}/admin/${GREEN}  (需配置 OAuth)"
fi
echo "  ╠══════════════════════════════════════════════════════╣"
echo -e "  ║  博客目录  ${YELLOW}${SITE_DIR}${GREEN}"
echo -e "  ║  文章目录  ${YELLOW}${SITE_DIR}/content/post/${GREEN}"
echo -e "  ║  静态输出  ${YELLOW}${NGINX_ROOT}${GREEN}"
if [[ "$ENABLE_CMS" == "true" ]]; then
echo -e "  ║  CMS 配置  ${YELLOW}${SITE_DIR}/static/admin/config.yml${GREEN}"
fi
echo "  ╚══════════════════════════════════════════════════════╝"
echo -e "${NC}"
echo -e "  ${BOLD}📝  写作与发布工作流：${NC}"
echo ""
echo -e "  ${CYAN}# 1. 创建新文章${NC}"
echo -e "  cd ${SITE_DIR}"
echo -e "  hugo new content post/my-post/index.md"
echo ""
echo -e "  ${CYAN}# 2. 本地预览${NC}"
echo -e "  hugo server -D --bind 0.0.0.0 --port 1313"
echo -e "  # 访问：http://${INTERNAL_IP}:1313"
echo ""
echo -e "  ${CYAN}# 3. 构建并发布到 Nginx${NC}"
echo -e "  hugo --destination ${NGINX_ROOT} --gc --minify"
echo ""
if [[ "$ENABLE_CMS" == "true" ]]; then
echo -e "  ${BOLD}🖊️   Decap CMS 使用：${NC}"
echo ""
echo -e "  ${CYAN}# 使用 GitHub 后端${NC}"
echo -e "  1. 前往 GitHub → Settings → Developer settings → OAuth Apps"
echo -e "     新建 App，Homepage URL 填：${CMS_SITE_URL}"
echo -e "     Callback URL 填：https://api.netlify.com/auth/done"
echo -e "     （自建 OAuth 代理则填自己的回调地址）"
echo -e "  2. 将博客 ${SITE_DIR} 推送到 GitHub 仓库：${CMS_REPO}"
echo -e "  3. 访问 ${CMS_SITE_URL}/admin/ 并用 GitHub 账号登录即可"
echo ""
echo -e "  ${CYAN}# 本地开发调试（无需 OAuth）${NC}"
echo -e "  # 将 ${SITE_DIR}/static/admin/config.yml 中 backend.name 改为 test-repo"
echo -e "  # 然后运行：hugo server -D --port 1313"
echo ""
fi
echo -e "  ${BOLD}🔒  HTTPS 配置（推荐）：${NC}"
echo -e "  apt install certbot python3-certbot-nginx -y"
echo -e "  certbot --nginx -d ${BLOG_DOMAIN:-your-domain.com}"
echo ""
echo -e "  ${BOLD}🎨  主题文档：${NC}  https://stack.jimmycai.com"
echo -e "  ${BOLD}📖  Decap CMS：${NC} https://decapcms.org/docs/"
echo ""
echo -e "  ${YELLOW}${BOLD}[提示]${NC} 修改配置后需重新构建：hugo --destination ${NGINX_ROOT} --gc --minify"
echo ""
}
