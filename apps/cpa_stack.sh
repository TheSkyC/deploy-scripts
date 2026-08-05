#!/usr/bin/env bash

APP_ID="cpa-stack"
APP_NAME="CLIProxyAPI + CPA Manager Plus"
i18n_register_many \
  app.cpa_stack.description \
  "Native CLIProxyAPI (CPA) and CPA Manager Plus deployment with systemd, Nginx, HTTPS, backups, and diagnostics." \
  "使用 systemd、Nginx、HTTPS、备份和诊断部署原生 CLIProxyAPI（CPA）与 CPA Manager Plus。" \
  app.cpa_stack.error.apt_only \
  "This script supports Debian / Ubuntu only because apt-get was not found." \
  "此脚本仅支持 Debian / Ubuntu（未找到 apt-get）。" \
  app.cpa_stack.error.systemd_required \
  "systemd is required by this script." \
  "此脚本需要 systemd。" \
  app.cpa_stack.error.arch \
  "Unsupported architecture: %s. Supported: x86_64 / aarch64 / arm64." \
  "不支持的架构：%s。支持：x86_64 / aarch64 / arm64。" \
  app.cpa_stack.error.domain_required \
  "%s is required. Set it to a valid DNS name such as api.example.com." \
  "%s 为必填项。请设置为类似 api.example.com 的有效域名。" \
  app.cpa_stack.error.domains_same \
  "CPA_DOMAIN and CPAMP_DOMAIN must be different DNS names." \
  "CPA_DOMAIN 和 CPAMP_DOMAIN 必须是不同的域名。" \
  app.cpa_stack.error.domain_invalid \
  "%s is invalid: %s." \
  "%s 无效：%s。" \
  app.cpa_stack.error.email_required \
  "CERTBOT_EMAIL is required when ENABLE_HTTPS=true." \
  "ENABLE_HTTPS=true 时必须设置 CERTBOT_EMAIL。" \
  app.cpa_stack.error.component \
  "CPA_STACK_COMPONENT must be one of: all, cpa, cpamp. Got: %s." \
  "CPA_STACK_COMPONENT 只能是 all、cpa 或 cpamp，当前为：%s。" \
  app.cpa_stack.error.github \
  "Cannot query the GitHub release API for %s." \
  "无法查询 %s 的 GitHub Release API。" \
  app.cpa_stack.error.release_asset \
  "Release %s for %s does not contain asset %s." \
  "%s 的 Release %s 未包含资源文件 %s。" \
  app.cpa_stack.error.download \
  "Failed to download %s." \
  "下载 %s 失败。" \
  app.cpa_stack.error.checksum \
  "Checksum verification failed for %s." \
  "%s 的校验和验证失败。" \
  app.cpa_stack.error.extract \
  "Failed to extract %s." \
  "解压 %s 失败。" \
  app.cpa_stack.error.binary_missing \
  "Expected binary %s was not found in %s." \
  "未在 %s 中找到预期二进制文件 %s。" \
  app.cpa_stack.error.deps \
  "Failed to install required packages: curl ca-certificates nginx certbot python3-certbot-nginx openssl." \
  "安装必需软件包失败：curl ca-certificates nginx certbot python3-certbot-nginx openssl。" \
  app.cpa_stack.error.user \
  "Failed to create or validate system user %s." \
  "创建或验证系统用户 %s 失败。" \
  app.cpa_stack.error.directory \
  "Failed to prepare directory %s." \
  "创建目录 %s 失败。" \
  app.cpa_stack.error.config_exists \
  "CPA configuration already exists at %s. To avoid overwriting credentials, provide CPA_MANAGEMENT_KEY and manage the file manually, or move it before a fresh install." \
  "CPA 配置已存在：%s。为避免覆盖凭据，请提供 CPA_MANAGEMENT_KEY 并手动管理该文件，或在全新安装前移走它。" \
  app.cpa_stack.error.service \
  "Failed to configure or start systemd service %s." \
  "配置或启动 systemd 服务 %s 失败。" \
  app.cpa_stack.error.nginx \
  "Nginx configuration failed: %s." \
  "Nginx 配置失败：%s。" \
  app.cpa_stack.error.backup \
  "Backup failed: %s." \
  "备份失败：%s。" \
  app.cpa_stack.error.uninstall_cancelled \
  "Uninstall cancelled." \
  "已取消卸载。" \
  app.cpa_stack.warn.config_preserved \
  "Preserving existing CPA configuration: %s. Confirm it binds to 127.0.0.1 and enables usage-statistics-enabled." \
  "将保留现有 CPA 配置：%s。请确认其绑定到 127.0.0.1 并启用了 usage-statistics-enabled。" \
  app.cpa_stack.warn.certbot \
  "Certificate issuance failed. HTTP remains active; fix DNS / inbound port 80 and rerun install." \
  "证书签发失败。HTTP 将继续可用；请修复 DNS/入站 80 端口后重新执行 install。" \
  app.cpa_stack.warn.http_health \
  "%s health check returned HTTP %s." \
  "%s 健康检查返回 HTTP %s。" \
  app.cpa_stack.warn.config_missing \
  "Configuration file is missing: %s." \
  "配置文件缺失：%s。" \
  app.cpa_stack.step.dependencies \
  "Installing system dependencies" \
  "安装系统依赖" \
  app.cpa_stack.step.download \
  "Downloading %s release %s" \
  "下载 %s Release %s" \
  app.cpa_stack.step.users \
  "Preparing system users and directories" \
  "创建系统用户和目录" \
  app.cpa_stack.step.config \
  "Writing CPA and CPAMP configuration" \
  "写入 CPA 和 CPAMP 配置" \
  app.cpa_stack.step.services \
  "Writing and starting systemd services" \
  "写入并启动 systemd 服务" \
  app.cpa_stack.step.nginx \
  "Writing Nginx reverse-proxy configuration" \
  "写入 Nginx 反向代理配置" \
  app.cpa_stack.step.https \
  "Requesting Let's Encrypt certificate" \
  "申请 Let's Encrypt 证书" \
  app.cpa_stack.step.backup \
  "Creating consistent CPA Stack backup" \
  "创建一致性的 CPA Stack 备份" \
  app.cpa_stack.success.installed \
  "CPA Stack installed. API: %s/v1 ; management: %s/management.html" \
  "CPA Stack 已安装。API：%s/v1；管理面板：%s/management.html" \
  app.cpa_stack.success.updated \
  "CPA Stack update completed." \
  "CPA Stack 更新完成。" \
  app.cpa_stack.success.backup \
  "Backup created: %s" \
  "备份已创建：%s" \
  app.cpa_stack.success.health \
  "%s health check passed (HTTP %s)." \
  "%s 健康检查通过（HTTP %s）。" \
  app.cpa_stack.success.removed \
  "CPA Stack service and proxy configuration removed. Persistent data was kept unless explicitly selected for deletion." \
  "CPA Stack 服务和反向代理配置已移除。除非明确选择删除，否则持久数据会被保留。" \
  app.cpa_stack.info.oauth \
  "OAuth is intentionally not automated. Run login commands as the cli-proxy-api user; some providers use localhost callbacks or device-code flows." \
  "OAuth 不会自动执行。请以 cli-proxy-api 用户运行登录命令；部分提供商使用 localhost 回调或设备码流程。" \
  app.cpa_stack.info.login_command \
  "Example: sudo -u %s %s -config %s --codex-login --no-browser" \
  "示例：sudo -u %s %s -config %s --codex-login --no-browser" \
  app.cpa_stack.info.kept_data \
  "Keeping persistent data: %s" \
  "保留持久数据：%s" \
  app.cpa_stack.prompt.cpa_domain \
  "CPA public API domain:" \
  "CPA 公网 API 域名：" \
  app.cpa_stack.prompt.cpamp_domain \
  "CPAMP management domain:" \
  "CPAMP 管理域名：" \
  app.cpa_stack.prompt.continue \
  "Type YES to remove CPA Stack services and Nginx configuration:" \
  "输入 YES 以移除 CPA Stack 服务和 Nginx 配置：" \
  app.cpa_stack.prompt.delete_data \
  "Delete persistent data and credentials under %s? [y/N]:" \
  "删除 %s 下的持久数据和凭据？[y/N]："

APP_DESCRIPTION="$(t app.cpa_stack.description)"
APP_IMPL_SCRIPT="impl/install_cpa_stack.sh"
load_app_impl "$APP_IMPL_SCRIPT"
