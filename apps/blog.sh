#!/usr/bin/env bash

APP_ID="blog"
APP_NAME="Hugo Blog"
i18n_register app.blog.description \
  "Hugo and Nginx blog deployment." \
  "Hugo 与 Nginx 博客部署脚本。"
i18n_register app.blog.error.apt_only \
  "Only Debian / Ubuntu is supported by this script." \
  "此脚本仅支持 Debian / Ubuntu。"
i18n_register app.blog.error.systemd_required \
  "systemd is required by this script." \
  "此脚本需要 systemd。"
i18n_register app.blog.error.arch \
  "Unsupported architecture: %s. Supported: x86_64 / aarch64." \
  "不支持的架构：%s（支持 x86_64 / aarch64）。"
i18n_register app.blog.site_title \
  "Abyte's Blog" \
  "Abyte 的个人博客"
i18n_register app.blog.site_description \
  "Notes on technology and life." \
  "记录技术与生活。"
i18n_register app.blog.site_lang \
  "en-us" \
  "zh-cn"
i18n_register app.blog.banner_theme \
  "Theme: %s" \
  "主题：%s"
i18n_register app.blog.banner_stack \
  "Stack: Hugo + Nginx + Decap CMS" \
  "服务：Hugo + Nginx + Decap CMS"
i18n_register app.blog.menu_home \
  "Home" \
  "首页"
i18n_register app.blog.menu_archives \
  "Archives" \
  "归档"
i18n_register app.blog.menu_categories \
  "Categories" \
  "分类"
i18n_register app.blog.menu_tags \
  "Tags" \
  "标签"
i18n_register app.blog.menu_about \
  "About" \
  "关于"
i18n_register app.blog.post_title \
  "Hello, World!" \
  "你好，世界！"
i18n_register app.blog.post_description \
  "My first blog post." \
  "我的第一篇博客文章"
i18n_register app.blog.post_category \
  "Notes" \
  "随笔"
i18n_register app.blog.post_tag_blog \
  "Blog" \
  "博客"
i18n_register app.blog.post_heading \
  "Welcome to my blog" \
  "欢迎来到我的博客"
i18n_register app.blog.post_intro \
  "This personal blog is powered by **Hugo** and the **Stack theme**. It is ready to publish." \
  "这是用 **Hugo** + **Stack 主题** 搭建的个人博客，已经成功运行！"
i18n_register app.blog.post_why_heading \
  "Why Hugo?" \
  "为什么选择 Hugo？"
i18n_register app.blog.post_fast_build \
  "Fast builds, even with thousands of posts." \
  "极速构建，数千篇文章几秒完成"
i18n_register app.blog.post_markdown \
  "Markdown writing keeps the focus on content." \
  "Markdown 写作，专注内容"
i18n_register app.blog.post_theme \
  "Rich themes, including Stack." \
  "丰富主题，Stack 主题对中文友好"
i18n_register app.blog.post_open_source \
  "Free and open source." \
  "完全免费开源"
i18n_register app.blog.post_start_heading \
  "Start writing" \
  "开始写作"
i18n_register app.blog.post_start_body \
  "Create a folder under \`content/post/\` with an \`index.md\` file to publish a new post." \
  "在 \`content/post/\` 目录下创建文件夹和 \`index.md\` 即可发布新文章。"
i18n_register app.blog.post_closing \
  "Happy writing!" \
  "祝写作愉快！"
i18n_register app.blog.about_title \
  "About" \
  "关于"
i18n_register app.blog.about_heading \
  "About me" \
  "关于我"
i18n_register app.blog.about_intro \
  "Hi, I am **%s**. Welcome to my blog." \
  "你好！我是 **%s**，欢迎来到我的博客。"
i18n_register app.blog.about_body \
  "I write about technology, learning notes, and everyday experiments." \
  "这里记录我的技术学习、生活感悟和各种折腾经历。"
i18n_register app.blog.about_footer \
  "This site is built with [Hugo](https://gohugo.io) and the [Stack theme](https://github.com/CaiJimmy/hugo-theme-stack)." \
  "本站使用 [Hugo](https://gohugo.io) 构建，主题为 [Stack](https://github.com/CaiJimmy/hugo-theme-stack)。"
i18n_register app.blog.archives_title \
  "Archives" \
  "归档"
i18n_register app.blog.cms_title \
  "Content Manager" \
  "内容管理"
i18n_register app.blog.cms_posts \
  "Blog posts" \
  "博客文章"
i18n_register app.blog.cms_post \
  "Post" \
  "文章"
i18n_register app.blog.cms_page \
  "Page" \
  "页面"
i18n_register app.blog.cms_pages \
  "Standalone pages" \
  "独立页面"
i18n_register app.blog.cms_title_field \
  "Title" \
  "标题"
i18n_register app.blog.cms_date_field \
  "Publish time" \
  "发布时间"
i18n_register app.blog.cms_description_field \
  "Summary / description" \
  "摘要 / 描述"
i18n_register app.blog.cms_draft_field \
  "Draft" \
  "草稿"
i18n_register app.blog.cms_categories_field \
  "Categories" \
  "分类"
i18n_register app.blog.cms_category_field \
  "Category" \
  "分类名"
i18n_register app.blog.cms_tags_field \
  "Tags" \
  "标签"
i18n_register app.blog.cms_tag_field \
  "Tag" \
  "标签名"
i18n_register app.blog.cms_series_field \
  "Series" \
  "系列"
i18n_register app.blog.cms_series_item_field \
  "Series name" \
  "系列名"
i18n_register app.blog.cms_image_field \
  "Cover image" \
  "封面图片"
i18n_register app.blog.cms_image_hint \
  "Recommended cover size: 1200x630px." \
  "文章封面，推荐 1200x630px"
i18n_register app.blog.cms_weight_field \
  "Weight" \
  "权重（排序）"
i18n_register app.blog.cms_body_field \
  "Body" \
  "正文内容"
i18n_register app.blog.cms_menu_field \
  "Show in navigation menu" \
  "在导航菜单显示"
i18n_register app.blog.cms_menu_hint \
  "Choose main to show this page in the top navigation." \
  "选择 main 后该页面出现在顶部导航"
i18n_register app.blog.cms_layout_field \
  "Layout template" \
  "布局模板"
i18n_register app.blog.cms_layout_hint \
  "Use a special layout such as archives, or leave blank for default." \
  "特殊布局如 archives，留空使用默认"
i18n_register app.blog.step_install_deps \
  "Step 1  Install system dependencies" \
  "Step 1  安装系统依赖"
i18n_register app.blog.deps_installed \
  "Dependencies installed: curl / wget / git / nginx" \
  "依赖安装完成（curl / wget / git / nginx）"
i18n_register app.blog.error.apt_update \
  "apt-get update failed. Check /var/log/apt/*, fix repository or network issues, and retry the installation." \
  "apt-get update 失败。请检查 /var/log/apt/*，修复软件源或网络问题后重新执行安装。"
i18n_register app.blog.error.deps_install \
  "Dependency installation failed. Run apt-get install -y curl wget git nginx ca-certificates after fixing the package manager state." \
  "依赖安装失败。请在修复软件包管理器状态后执行 apt-get install -y curl wget git nginx ca-certificates。"
i18n_register app.blog.step_install_hugo \
  "Step 2  Install Hugo Extended" \
  "Step 2  安装 Hugo Extended"
i18n_register app.blog.query_hugo \
  "Querying the latest Hugo release..." \
  "查询 Hugo 最新版本..."
i18n_register app.blog.error.github_api \
  "Cannot reach GitHub API. Check network connectivity." \
  "无法访问 GitHub API，请检查网络连接。"
i18n_register app.blog.error.hugo_version \
  "Failed to resolve the Hugo version." \
  "获取 Hugo 版本失败。"
i18n_register app.blog.latest_version \
  "Latest version: v%s" \
  "最新版本：v%s"
i18n_register app.blog.download_url \
  "Download: %s" \
  "下载：%s"
i18n_register app.blog.error.hugo_download \
  "Hugo download failed. Check the network or download it manually." \
  "Hugo 下载失败，请检查网络或手动下载。"
i18n_register app.blog.error.hugo_install \
  "Hugo package installation failed. Run apt-get install -f and then dpkg -i <downloaded-hugo.deb> after fixing dependency issues." \
  "Hugo 软件包安装失败。请先执行 apt-get install -f 修复依赖问题，再重新运行 dpkg -i <下载的-hugo.deb>。"
i18n_register app.blog.hugo_installed \
  "Hugo installed: %s" \
  "Hugo %s 安装完成"
i18n_register app.blog.step_init_site \
  "Step 3  Initialize Hugo blog project" \
  "Step 3  初始化 Hugo 博客项目"
i18n_register app.blog.site_exists \
  "Site directory already exists, keeping current content: %s" \
  "目录 %s 已存在，跳过初始化（保留现有内容）"
i18n_register app.blog.site_created \
  "Hugo project created at: %s" \
  "Hugo 项目创建于：%s"
i18n_register app.blog.git_initialized \
  "Git repository initialized." \
  "Git 仓库已初始化"
i18n_register app.blog.step_theme \
  "Step 4  Install hugo-theme-stack" \
  "Step 4  安装 hugo-theme-stack 主题"
i18n_register app.blog.theme_exists \
  "Theme already exists; skipping clone." \
  "主题已存在，跳过克隆"
i18n_register app.blog.theme_current \
  "Theme is ready." \
  "主题已是最新"
i18n_register app.blog.clone_theme \
  "Cloning theme repository. This may take a moment..." \
  "克隆主题仓库（首次可能需要一点时间）..."
i18n_register app.blog.theme_installed \
  "Theme installed." \
  "主题安装完成"
i18n_register app.blog.step_config \
  "Step 5  Generate site configuration" \
  "Step 5  生成站点配置"
i18n_register app.blog.config_backed_up \
  "Existing config was backed up." \
  "已备份旧配置"
i18n_register app.blog.config_written \
  "Config file written: %s" \
  "配置文件已写入：%s"
i18n_register app.blog.error.file_write \
  "Blog file write failed: %s" \
  "博客文件写入失败：%s"
i18n_register app.blog.step_content \
  "Step 6  Create sample post and pages" \
  "Step 6  创建示例文章与页面"
i18n_register app.blog.sample_post_created \
  "Sample post created." \
  "示例文章已创建"
i18n_register app.blog.about_created \
  "About page created." \
  "关于页面已创建"
i18n_register app.blog.archives_created \
  "Archives page created." \
  "归档页面已创建"
i18n_register app.blog.step_cms \
  "Step 7  Integrate Decap CMS" \
  "Step 7  集成 Decap CMS（可视化内容管理）"
i18n_register app.blog.cms_skipped \
  "ENABLE_CMS=false; skipping Decap CMS installation." \
  "ENABLE_CMS=false，跳过 Decap CMS 安装"
i18n_register app.blog.cms_config_created \
  "Decap CMS config created: %s" \
  "Decap CMS 配置文件已创建：%s"
i18n_register app.blog.cms_admin_url \
  "Admin entrypoint: %s/admin/" \
  "Admin 入口将位于：%s/admin/"
i18n_register app.blog.step_build \
  "Step 8  Build static site with CMS admin files" \
  "Step 8  构建静态网站（含 CMS admin 文件）"
i18n_register app.blog.git_committed \
  "Git commit complete; Hugo can read file modification times." \
  "Git 提交完成，Hugo 可读取文件修改时间"
i18n_register app.blog.error.hugo_build \
  "Hugo build failed. Check the configuration." \
  "Hugo 构建失败，请检查配置。"
i18n_register app.blog.build_complete \
  "Build complete: %s HTML pages generated." \
  "构建完成，共生成 %s 个 HTML 页面"
i18n_register app.blog.step_nginx \
  "Step 9  Configure Nginx" \
  "Step 9  配置 Nginx"
i18n_register app.blog.static_deployed \
  "Static files deployed to: %s" \
  "静态文件已部署到：%s"
i18n_register app.blog.error.static_deploy \
  "Static file deployment failed." \
  "静态文件部署失败。"
i18n_register app.blog.error.nginx_config \
  "Nginx configuration validation failed. Check the errors above." \
  "Nginx 配置验证失败，请检查上方错误。"
i18n_register app.blog.error.nginx_write \
  "Nginx config write failed: %s" \
  "Nginx 配置写入失败：%s"
i18n_register app.blog.nginx_configured \
  "Nginx configured." \
  "Nginx 配置完成"
i18n_register app.blog.step_firewall \
  "Step 10  Configure firewall" \
  "Step 10  配置防火墙"
i18n_register app.blog.ufw_opened \
  "ufw allows HTTP/HTTPS." \
  "ufw 已放行 HTTP/HTTPS"
i18n_register app.blog.iptables_opened \
  "iptables allows ports 80/443." \
  "iptables 已放行 80/443"
i18n_register app.blog.firewall_config_failed \
  "Automatic firewall configuration failed for ports 80 and 443. Open them manually or retry after fixing the firewall service." \
  "80 和 443 端口的防火墙自动配置失败。请在修复防火墙服务后重试，或手动放行这些端口"
i18n_register app.blog.firewall_missing \
  "No firewall was detected. If you use cloud security groups, allow ports 80 and 443 manually." \
  "未检测到防火墙，如有云安全组请手动放行 80 和 443 端口"
i18n_register app.blog.step_start_nginx \
  "Step 11  Start Nginx" \
  "Step 11  启动 Nginx"
i18n_register app.blog.warn.service_enable_failed \
  "Could not enable %s to start automatically on boot. Run manually after fixing systemd: systemctl enable %s" \
  "无法将 %s 设置为开机自启。请在修复 systemd 问题后手动执行：systemctl enable %s。"
i18n_register app.blog.nginx_started \
  "Nginx started." \
  "Nginx 已启动"
i18n_register app.blog.error.nginx_start \
  "Nginx failed to start. Run: journalctl -u nginx -n 30" \
  "Nginx 启动失败，请运行：journalctl -u nginx -n 30"
i18n_register app.blog.step_health \
  "Step 12  Health check" \
  "Step 12  健康检查"
i18n_register app.blog.http_ok \
  "HTTP response is healthy: 200 OK" \
  "HTTP 响应正常（200 OK）"
i18n_register app.blog.http_warn \
  "HTTP returned %s. If the domain is not pointed here yet, use the internal IP." \
  "HTTP 返回 %s，如无域名指向请用内网 IP 访问"
i18n_register app.blog.summary_title \
  "Blog deployment complete!" \
  "博客部署完成！"
i18n_register app.blog.public_url \
  "Public URL" \
  "公网访问"
i18n_register app.blog.internal_url \
  "Internal URL" \
  "内网访问"
i18n_register app.blog.cms_admin \
  "CMS admin" \
  "CMS 管理"
i18n_register app.blog.oauth_required \
  "OAuth required" \
  "需配置 OAuth"
i18n_register app.blog.site_dir \
  "Site dir" \
  "博客目录"
i18n_register app.blog.posts_dir \
  "Posts dir" \
  "文章目录"
i18n_register app.blog.public_dir \
  "Static output" \
  "静态输出"
i18n_register app.blog.cms_config \
  "CMS config" \
  "CMS 配置"
i18n_register app.blog.workflow_title \
  "Writing and publishing workflow:" \
  "写作与发布工作流："
i18n_register app.blog.workflow_new_post \
  "1. Create a new post" \
  "1. 创建新文章"
i18n_register app.blog.workflow_preview \
  "2. Local preview" \
  "2. 本地预览"
i18n_register app.blog.workflow_visit \
  "Visit: http://%s:1313" \
  "访问：http://%s:1313"
i18n_register app.blog.workflow_publish \
  "3. Build and publish to Nginx" \
  "3. 构建并发布到 Nginx"
i18n_register app.blog.cms_usage \
  "Decap CMS usage:" \
  "Decap CMS 使用："
i18n_register app.blog.cms_github_backend \
  "Use the GitHub backend" \
  "使用 GitHub 后端"
i18n_register app.blog.cms_oauth_step1 \
  "1. Go to GitHub -> Settings -> Developer settings -> OAuth Apps" \
  "1. 前往 GitHub -> Settings -> Developer settings -> OAuth Apps"
i18n_register app.blog.cms_oauth_homepage \
  "   Create an app. Homepage URL: %s" \
  "   新建 App，Homepage URL 填：%s"
i18n_register app.blog.cms_oauth_callback \
  "   Callback URL: https://api.netlify.com/auth/done" \
  "   Callback URL 填：https://api.netlify.com/auth/done"
i18n_register app.blog.cms_oauth_proxy \
  "   Use your own callback URL when self-hosting an OAuth proxy." \
  "   自建 OAuth 代理则填自己的回调地址。"
i18n_register app.blog.cms_push_repo \
  "2. Push %s to the GitHub repo: %s" \
  "2. 将博客 %s 推送到 GitHub 仓库：%s"
i18n_register app.blog.cms_login \
  "3. Visit %s/admin/ and sign in with GitHub." \
  "3. 访问 %s/admin/ 并用 GitHub 账号登录即可"
i18n_register app.blog.cms_local_debug \
  "Local development without OAuth" \
  "本地开发调试（无需 OAuth）"
i18n_register app.blog.cms_test_repo \
  "Change backend.name in %s/static/admin/config.yml to test-repo." \
  "将 %s/static/admin/config.yml 中 backend.name 改为 test-repo"
i18n_register app.blog.cms_run_server \
  "Then run: hugo server -D --port 1313" \
  "然后运行：hugo server -D --port 1313"
i18n_register app.blog.https_title \
  "HTTPS setup recommended:" \
  "HTTPS 配置（推荐）："
i18n_register app.blog.theme_docs \
  "Theme docs:" \
  "主题文档："
i18n_register app.blog.rebuild_hint \
  "Rebuild after changing config: hugo --destination %s --gc --minify" \
  "修改配置后需重新构建：hugo --destination %s --gc --minify"

APP_DESCRIPTION="$(t app.blog.description)"
APP_IMPL_SCRIPT="impl/install_blog.sh"

load_app_impl "$APP_IMPL_SCRIPT"

do_update() { error "$(t error.unsupported_action "$APP_NAME" update)"; }
do_backup() { error "$(t error.unsupported_action "$APP_NAME" backup)"; }
do_status() { error "$(t error.unsupported_action "$APP_NAME" status)"; }
do_uninstall() { error "$(t error.unsupported_action "$APP_NAME" uninstall)"; }
