#!/usr/bin/env bash

APP_ID="vaultwarden"
APP_NAME="Vaultwarden"
i18n_register_many \
  app.vaultwarden.description \
  "Vaultwarden deployment with Web Vault, Nginx, TLS, and backups." \
  "包含 Web Vault、Nginx、TLS 和备份的 Vaultwarden 部署脚本。" \
  app.vaultwarden.error.apt_only \
  "This script only supports Debian / Ubuntu because apt-get was not found." \
  "此脚本仅支持 Debian / Ubuntu（apt-get 未找到）。" \
  app.vaultwarden.error.arch \
  "Unsupported architecture: %s. Supported: x86_64 / aarch64 / armv7l." \
  "不支持的架构：%s（支持 x86_64 / aarch64 / armv7l）。" \
  app.vaultwarden.error.registry_unreachable \
  "Cannot reach Docker Registry or GitHub. Check network/proxy settings and retry." \
  "网络不通，无法访问 Docker Registry / GitHub，请检查网络或代理后重试。" \
  app.vaultwarden.status.not_installed \
  "not installed" \
  "未安装" \
  app.vaultwarden.info.download_extract_tool \
  "Downloading docker-image-extract..." \
  "下载 docker-image-extract 工具..." \
  app.vaultwarden.error.extract_tool_download \
  "Cannot download docker-image-extract. Check network connectivity." \
  "无法下载 docker-image-extract，请检查网络连接。" \
  app.vaultwarden.error.extract_tool_empty \
  "docker-image-extract was downloaded as an empty file." \
  "docker-image-extract 下载后为空文件。" \
  app.vaultwarden.error.extract_tool_shebang \
  "docker-image-extract is not a valid shell script (missing shebang); the download may be corrupted." \
  "docker-image-extract 不是合法的 shell 脚本（shebang 缺失），可能下载损坏。" \
  app.vaultwarden.error.extract_tool_small \
  "docker-image-extract is too small (%s bytes); the download may be incomplete or tampered with." \
  "docker-image-extract 文件过小（%s 字节），疑似下载不完整或被篡改。" \
  app.vaultwarden.error.extract_tool_content \
  "docker-image-extract content is unexpected (missing registry keyword); aborting because it may be tampered with." \
  "docker-image-extract 内容异常（缺少 registry 关键字），疑似被篡改，已中止。" \
  app.vaultwarden.error.extract_tool_sha \
  "docker-image-extract SHA256 verification failed!\n  expected: %s\n  actual: %s\n  Update EXTRACT_TOOL_SHA256 in the script or check network security." \
  "docker-image-extract SHA256 校验失败！\n  期望：%s\n  实际：%s\n  请更新脚本中的 EXTRACT_TOOL_SHA256 或检查网络安全性。" \
  app.vaultwarden.success.extract_tool_sha \
  "docker-image-extract SHA256 verification passed." \
  "docker-image-extract SHA256 校验通过。" \
  app.vaultwarden.warn.extract_tool_sha_missing \
  "EXTRACT_TOOL_SHA256 is not configured; skipping checksum verification. Configure it for production." \
  "未配置 EXTRACT_TOOL_SHA256，跳过 checksum 校验（建议为生产环境配置此项）。" \
  app.vaultwarden.info.extract_image \
  "Extracting %s:%s from the image registry (platform: %s)..." \
  "从镜像仓库提取 %s:%s（平台：%s）..." \
  app.vaultwarden.info.first_download_wait \
  "The first download can take a few minutes. Please wait..." \
  "首次下载需要几分钟，请耐心等待..." \
  app.vaultwarden.error.image_extract \
  "Image extraction failed. Check the network and retry later." \
  "镜像提取失败，请检查网络或稍后重试。" \
  app.vaultwarden.error.binary_missing_image \
  "vaultwarden binary was not found in the image." \
  "未在镜像中找到 vaultwarden 二进制。" \
  app.vaultwarden.error.binary_too_small \
  "Extracted vaultwarden binary is too small (%s bytes); it may be incomplete or tampered with." \
  "提取的 vaultwarden 二进制过小（%s 字节），疑似不完整或被篡改。" \
  app.vaultwarden.error.binary_not_elf \
  "Extracted file is not a valid ELF binary (magic bytes mismatch); the download may be corrupted." \
  "提取的文件不是合法的 ELF 二进制（magic bytes 不匹配），疑似下载损坏。" \
  app.vaultwarden.error.binary_install \
  "Failed to install Vaultwarden binary: %s" \
  "安装 Vaultwarden 二进制失败：%s。" \
  app.vaultwarden.error.elf_machine \
  "ELF e_machine mismatch. Expected %s (%s), actual %s.\n  The image platform argument may be wrong, or the image manifest parsing failed. Retry." \
  "ELF e_machine 不匹配！期望 %s（%s），实际 %s。\n  镜像平台参数可能有误，或镜像 manifest 解析异常，请重试。" \
  app.vaultwarden.warn.installed \
  "Vaultwarden is already installed (%s), version: %s" \
  "检测到 Vaultwarden 已安装（%s），版本：%s。" \
  app.vaultwarden.warn.reinstall \
  "Reinstalling will overwrite the existing binary and config; the data directory will be kept." \
  "重新安装会覆盖现有二进制和配置（数据目录保留）。" \
  app.vaultwarden.prompt.force_reinstall \
  "Force reinstall? (y/N):" \
  "是否强制重新安装？（y/N）：" \
  app.vaultwarden.info.install_cancelled_update \
  "Cancelled. Use the update command if you want to update." \
  "已取消，如需更新请使用 update 命令。" \
  app.vaultwarden.step.wizard \
  "Configuration wizard" \
  "配置向导" \
  app.vaultwarden.prompt.domain \
  "Enter your domain (for example vault.yourdomain.com):" \
  "请输入你的域名（如 vault.yourdomain.com）：" \
  app.vaultwarden.warn.domain_empty \
  "Domain cannot be empty. Try again." \
  "域名不能为空，请重新输入。" \
  app.vaultwarden.warn.domain_invalid \
  "Domain is invalid (%s). Try again." \
  "域名格式无效（%s），请重新输入。" \
  app.vaultwarden.prompt.email \
  "Enter the Let's Encrypt notification email:" \
  "请输入 Let's Encrypt 通知邮箱：" \
  app.vaultwarden.warn.email_empty \
  "Email cannot be empty. Try again." \
  "邮箱不能为空，请重新输入。" \
  app.vaultwarden.warn.email_invalid \
  "Email is invalid (%s). Try again." \
  "邮箱格式无效（%s），请重新输入。" \
  app.vaultwarden.error.port_invalid \
  "VW_PORT is invalid: '%s'. Set a port between 1 and 65535 at the top of the script." \
  "VW_PORT 无效：'%s'，请在脚本顶部设置 1-65535 之间的端口号。" \
  app.vaultwarden.info.domain \
  "Domain     : %s" \
  "域名     : %s" \
  app.vaultwarden.info.listen_port \
  "Listen port: %s (local only, behind Nginx reverse proxy)" \
  "监听端口 : %s（仅本机，经 Nginx 反代）" \
  app.vaultwarden.info.binary \
  "Binary     : %s" \
  "二进制   : %s" \
  app.vaultwarden.info.data_dir \
  "Data dir   : %s" \
  "数据目录 : %s" \
  app.vaultwarden.info.run_user \
  "Run user   : %s" \
  "运行用户 : %s" \
  app.vaultwarden.prompt.confirm_config \
  "Is this configuration correct? (y/N):" \
  "配置是否正确？（y/N）：" \
  app.vaultwarden.info.config_cancelled \
  "Cancelled. Update the configuration at the top of the script and retry." \
  "已取消，请修改脚本顶部配置项后重试。" \
  app.vaultwarden.step.deps \
  "Step 1  Install system dependencies" \
  "Step 1  安装系统依赖" \
  app.vaultwarden.warn.apt_update \
  "apt-get update partially failed. Continuing install, but package versions may be affected. Inspect /var/log/apt/* or rerun apt-get update after fixing repository/network issues." \
  "apt-get update 部分仓库失败，将尝试继续安装（可能影响包版本）。请检查 /var/log/apt/*，或在修复仓库/网络问题后重新执行 apt-get update。" \
  app.vaultwarden.error.deps_install \
  "Dependency installation failed. Run apt-get install -y curl wget ca-certificates nginx certbot python3-certbot-nginx sqlite3 argon2 openssl fail2ban logrotate after fixing the package manager state." \
  "依赖安装失败。请在修复软件包管理器状态后执行 apt-get install -y curl wget ca-certificates nginx certbot python3-certbot-nginx sqlite3 argon2 openssl fail2ban logrotate。" \
  app.vaultwarden.success.deps \
  "System dependencies installed." \
  "系统依赖安装完成。" \
  app.vaultwarden.step.user_dirs \
  "Step 2  Create system user and directories" \
  "Step 2  创建系统用户与目录" \
  app.vaultwarden.success.user_created \
  "System user %s created." \
  "系统用户 %s 已创建。" \
  app.vaultwarden.warn.user_exists \
  "User %s already exists; skipping." \
  "用户 %s 已存在，跳过。" \
  app.vaultwarden.success.dirs \
  "Directories created and permissions set." \
  "目录已创建并设置权限。" \
  app.vaultwarden.step.extract_binary \
  "Step 3  Extract Vaultwarden static binary" \
  "Step 3  提取 Vaultwarden 静态二进制" \
  app.vaultwarden.success.binary_extracted \
  "Binary extracted successfully: %s" \
  "二进制提取成功：%s。" \
  app.vaultwarden.success.binary_installed \
  "Binary installed: %s" \
  "二进制已安装：%s。" \
  app.vaultwarden.info.version \
  "Vaultwarden version: %s" \
  "Vaultwarden 版本：%s" \
  app.vaultwarden.step.web_vault \
  "Step 4  Install Web Vault" \
  "Step 4  安装 Web Vault" \
  app.vaultwarden.info.web_vault_image \
  "Using Web Vault extracted from the image (matching the binary version)..." \
  "使用镜像中提取的 Web Vault（与二进制版本一致）..." \
  app.vaultwarden.success.web_vault_image \
  "Web Vault installed from the Alpine image." \
  "Web Vault 已安装（来自 Alpine 镜像）。" \
  app.vaultwarden.info.web_vault_github \
  "Downloading the latest Web Vault from GitHub..." \
  "从 GitHub 下载最新 Web Vault..." \
  app.vaultwarden.error.web_vault_version \
  "Cannot get Web Vault version. Check the network." \
  "无法获取 Web Vault 版本，请检查网络。" \
  app.vaultwarden.info.web_vault_version \
  "Web Vault version: v%s" \
  "Web Vault 版本：v%s" \
  app.vaultwarden.info.download \
  "Download: %s" \
  "下载：%s" \
  app.vaultwarden.error.web_vault_download \
  "Web Vault download failed." \
  "Web Vault 下载失败。" \
  app.vaultwarden.error.web_vault_install \
  "Web Vault installation failed." \
  "Web Vault 安装失败。" \
  app.vaultwarden.success.web_vault_version \
  "Web Vault v%s installed." \
  "Web Vault v%s 已安装。" \
  app.vaultwarden.info.web_vault_path \
  "Web Vault path: %s" \
  "Web Vault 位置：%s" \
  app.vaultwarden.step.admin_token \
  "Step 5  Generate Admin Token (Argon2id hash)" \
  "Step 5  生成 Admin Token（Argon2id 哈希）" \
  app.vaultwarden.info.hash_token \
  "Generating hash with vaultwarden hash --preset owasp..." \
  "使用 vaultwarden hash --preset owasp 生成哈希..." \
  app.vaultwarden.warn.hash_parse \
  "Failed to parse vaultwarden hash output; falling back to argon2 CLI (OWASP preset)..." \
  "vaultwarden hash 输出解析失败，回退至 argon2 CLI（OWASP preset）..." \
  app.vaultwarden.error.admin_token_hash \
  "argon2 CLI also failed, so a secure Admin Token cannot be generated.\n  Confirm argon2 is installed: apt-get install -y argon2\n  Fix the issue and rerun install. Plaintext tokens are deprecated and unsafe in newer Vaultwarden versions, so installation is refused." \
  "argon2 CLI 也失败，无法生成安全的 Admin Token。\n  请确认已安装 argon2：apt-get install -y argon2\n  修复后重新运行 install。（使用明文 Token 在新版 Vaultwarden 中已废弃且不安全，拒绝继续）。" \
  app.vaultwarden.success.admin_token \
  "Admin Token generated." \
  "Admin Token 生成完成。" \
  app.vaultwarden.step.env_file \
  "Step 6  Write %s" \
  "Step 6  写入 %s" \
  app.vaultwarden.error.env_file \
  "Environment config file write failed: %s" \
  "环境配置文件写入失败：%s" \
  app.vaultwarden.success.env_file \
  "Environment config file written: %s (mode 600)." \
  "环境配置文件已写入：%s（权限 600）。" \
  app.vaultwarden.step.systemd \
  "Step 7  Create systemd service" \
  "Step 7  创建 systemd 服务" \
  app.vaultwarden.error.systemd \
  "systemd service file write failed: /etc/systemd/system/vaultwarden.service" \
  "systemd 服务文件写入失败：/etc/systemd/system/vaultwarden.service" \
  app.vaultwarden.success.systemd \
  "systemd service created." \
  "systemd 服务已创建。" \
  app.vaultwarden.warn.service_enable_failed \
  "Could not enable %s to start automatically on boot. Run manually after fixing systemd: systemctl enable %s" \
  "无法将 %s 设置为开机自启。请在修复 systemd 问题后手动执行：systemctl enable %s。" \
  app.vaultwarden.step.start_service \
  "Step 8  Start Vaultwarden service" \
  "Step 8  启动 Vaultwarden 服务" \
  app.vaultwarden.status.unknown_process \
  "unknown process" \
  "未知进程" \
  app.vaultwarden.warn.port_used \
  "Port %s is already in use (%s)." \
  "端口 %s 已被占用（%s）。" \
  app.vaultwarden.warn.port_hint \
  "If this is not an old vaultwarden process, release the port before installing or the service cannot start." \
  "若不是旧的 vaultwarden 进程，请先释放端口再安装，否则服务将无法启动。" \
  app.vaultwarden.success.service_started \
  "Vaultwarden service started successfully." \
  "Vaultwarden 服务启动成功。" \
  app.vaultwarden.warn.service_cleanup \
  "The service did not start within 20 seconds. Cleaning installed files..." \
  "服务在 20 秒内未能正常启动，正在清理已安装文件..." \
  app.vaultwarden.error.install_failed_start \
  "Installation failed because the service could not start. The binary and systemd unit were rolled back.\n  Debug: journalctl -u vaultwarden -n 30 --no-pager\n  Data directory, env file, and Nginx config were kept. Fix the cause and rerun install." \
  "安装失败：服务无法启动，已回滚二进制与 systemd 单元。\n  调试命令：journalctl -u vaultwarden -n 30 --no-pager\n  数据目录、env 文件、Nginx 配置已保留，修复原因后重新 install。" \
  app.vaultwarden.step.nginx_http \
  "Step 9  Configure Nginx reverse proxy (HTTP-only; Step 10 certbot completes HTTPS)" \
  "Step 9  配置 Nginx 反向代理（HTTP-only，HTTPS 由 Step 10 certbot 补全）" \
  app.vaultwarden.warn.default_site_removed \
  "Removed the default Nginx site (/etc/nginx/sites-enabled/default). Restore it manually if another site depends on it." \
  "已移除 Nginx 默认站点（/etc/nginx/sites-enabled/default）。如有其他站点依赖它，请手动恢复。" \
  app.vaultwarden.error.nginx_write \
  "Nginx config write failed: %s" \
  "Nginx 配置写入失败：%s" \
  app.vaultwarden.error.nginx_http_test \
  "Nginx config validation failed (HTTP phase)." \
  "Nginx 配置验证失败（HTTP 阶段）。" \
  app.vaultwarden.success.nginx_http \
  "Nginx HTTP config complete." \
  "Nginx HTTP 配置完成。" \
  app.vaultwarden.step.certbot \
  "Step 10  Request HTTPS certificate" \
  "Step 10  申请 HTTPS 证书" \
  app.vaultwarden.error.nginx_start \
  "Nginx did not start within 10 seconds. Check config: nginx -t\n  journalctl -u nginx -n 20 --no-pager" \
  "Nginx 未能在 10 秒内成功启动，请检查配置：nginx -t\n  journalctl -u nginx -n 20 --no-pager" \
  app.vaultwarden.success.nginx_ready \
  "Nginx is ready; continuing certificate request." \
  "Nginx 已就绪，继续申请证书。" \
  app.vaultwarden.info.request_cert \
  "Requesting certificate (%s / %s)..." \
  "申请证书（%s / %s）..." \
  app.vaultwarden.success.certbot \
  "Let's Encrypt certificate issued successfully." \
  "Let's Encrypt 证书申请成功。" \
  app.vaultwarden.warn.certbot_failed \
  "Certbot certificate request failed (see output above)." \
  "Certbot 证书申请失败（见上方输出）。" \
  app.vaultwarden.warn.certbot_manual \
  "After fixing DNS/firewall issues, run manually: certbot certonly --webroot -w /var/www/certbot -d %s --email %s --agree-tos --non-interactive" \
  "请解决 DNS/防火墙问题后手动运行：certbot certonly --webroot -w /var/www/certbot -d %s --email %s --agree-tos --non-interactive" \
  app.vaultwarden.success.certbot_timer \
  "Certbot auto-renew timer is ready." \
  "Certbot 自动续签定时器已就绪。" \
  app.vaultwarden.success.certbot_cron_exists \
  "Certbot auto-renew cron entry already exists; skipping." \
  "Certbot 自动续签 cron 条目已存在，跳过。" \
  app.vaultwarden.success.certbot_cron \
  "Certbot auto-renew cron entry added (daily 02:30)." \
  "Certbot 自动续签（每天 02:30）已加入 crontab。" \
  app.vaultwarden.error.certbot_cron \
  "Failed to write the Certbot auto-renew crontab entry. Add it manually after fixing crontab access: 30 2 * * * certbot renew --quiet --post-hook 'systemctl reload nginx'" \
  "写入 Certbot 自动续签 crontab 条目失败。请在修复 crontab 访问问题后手动添加：30 2 * * * certbot renew --quiet --post-hook 'systemctl reload nginx'" \
  app.vaultwarden.warn.nginx_version \
  "Cannot detect Nginx version; using legacy http2 syntax (attached to listen lines)." \
  "无法检测 Nginx 版本，默认使用旧版 http2 语法（listen 行附加）。" \
  app.vaultwarden.success.nginx_https \
  "Nginx HTTPS config is active." \
  "Nginx HTTPS 完整配置已生效。" \
  app.vaultwarden.warn.nginx_https_test \
  "Nginx HTTPS config test failed. Check: nginx -t" \
  "Nginx HTTPS 配置测试失败，请检查：nginx -t。" \
  app.vaultwarden.warn.cert_missing \
  "Certificate files were not found. Skipping HTTPS config; current mode is still HTTP." \
  "证书文件未找到，跳过 HTTPS 配置写入，当前仍使用 HTTP 模式。" \
  app.vaultwarden.warn.https_skipped \
  "Skipping HTTPS config. Vaultwarden Web Crypto API requires HTTPS!" \
  "跳过 HTTPS 配置（Vaultwarden Web Crypto API 需要 HTTPS！）。" \
  app.vaultwarden.step.fail2ban \
  "Step 11  Configure Fail2Ban brute-force protection" \
  "Step 11  配置 Fail2Ban 防暴力破解" \
  app.vaultwarden.error.fail2ban_write \
  "Fail2Ban config write failed: %s" \
  "Fail2Ban 配置写入失败：%s" \
  app.vaultwarden.error.fail2ban_start \
  "Cannot start Fail2Ban service. Inspect: journalctl -u fail2ban -n 30" \
  "无法启动 Fail2Ban 服务，请检查：journalctl -u fail2ban -n 30" \
  app.vaultwarden.success.fail2ban \
  "Fail2Ban configured (login: 5 failures/hour -> 1h ban, admin: 3 failures/day -> 24h ban)." \
  "Fail2Ban 已配置（登录失败 5 次/小时封禁 1h，Admin 3 次/天封禁 24h）。" \
  app.vaultwarden.warn.fail2ban_restart \
  "Fail2Ban rules were removed, but the service could not be restarted. Inspect: journalctl -u fail2ban -n 30" \
  "Fail2Ban 规则已移除，但服务重启失败。请检查：journalctl -u fail2ban -n 30" \
  app.vaultwarden.step.logrotate \
  "Step 12  Configure log rotation" \
  "Step 12  配置日志轮转" \
  app.vaultwarden.success.logrotate \
  "Log rotation configured (daily rotation, 14 days retained, compressed automatically)." \
  "日志轮转已配置（每日轮转，保留 14 天，自动压缩）。" \
  app.vaultwarden.error.logrotate \
  "Logrotate config write failed: /etc/logrotate.d/vaultwarden" \
  "日志轮转配置写入失败：/etc/logrotate.d/vaultwarden" \
  app.vaultwarden.step.firewall \
  "Step 13  Configure firewall" \
  "Step 13  配置防火墙" \
  app.vaultwarden.success.ufw \
  "ufw allows HTTP/HTTPS." \
  "ufw 已放行 HTTP/HTTPS。" \
  app.vaultwarden.success.iptables \
  "iptables allows 80/443." \
  "iptables 已放行 80/443。" \
  app.vaultwarden.success.iptables_saved \
  "iptables rules persisted with netfilter-persistent." \
  "iptables 规则已持久化（netfilter-persistent）。" \
  app.vaultwarden.warn.firewall_config_failed \
  "Automatic firewall configuration failed for ports 80/443. Open them manually or retry after fixing the firewall service." \
  "80/443 端口的防火墙自动配置失败。请在修复防火墙服务后重试，或手动放行这些端口。" \
  app.vaultwarden.warn.iptables_not_persisted \
  "iptables rules are not persisted and may be lost after reboot. Recommended: apt-get install -y iptables-persistent && netfilter-persistent save" \
  "iptables 规则未持久化（重启后失效）。建议：apt-get install -y iptables-persistent && netfilter-persistent save。" \
  app.vaultwarden.warn.no_firewall \
  "No active firewall detected. Allow ports 80/443 manually." \
  "未检测到活跃防火墙，请手动放行 80/443 端口。" \
  app.vaultwarden.step.auto_backup \
  "Step 14  Configure automatic backup (daily 03:30)" \
  "Step 14  配置自动备份（每日 03:30）" \
  app.vaultwarden.success.auto_backup \
  "Automatic backup configured (daily 03:30, retaining %s days)." \
  "自动备份已配置（每日 03:30，保留 %s 天）。" \
  app.vaultwarden.error.auto_backup \
  "Automatic backup config write failed: /etc/cron.d/vaultwarden-backup" \
  "自动备份配置写入失败：/etc/cron.d/vaultwarden-backup" \
  app.vaultwarden.step.health \
  "Step 15  Health check" \
  "Step 15  健康检查" \
  app.vaultwarden.success.local_health \
  "Vaultwarden local endpoint responded normally (HTTP %s)." \
  "Vaultwarden 本地接口响应正常（HTTP %s）。" \
  app.vaultwarden.warn.local_health \
  "Local health check returned %s. The service may still be initializing; try again later." \
  "本地健康检查返回 %s，服务可能仍在初始化，稍后再试。" \
  app.vaultwarden.warn.debug \
  "Debug command: journalctl -u vaultwarden -n 30 --no-pager" \
  "调试命令：journalctl -u vaultwarden -n 30 --no-pager" \
  app.vaultwarden.summary.title_ready \
  "Vaultwarden deployment complete! (binary edition)" \
  "Vaultwarden 部署完成！（二进制版）" \
  app.vaultwarden.summary.title_pending \
  "Vaultwarden files installed; verify service health before first use" \
  "Vaultwarden 文件已安装；首次使用前请先确认服务健康" \
  app.vaultwarden.summary.url \
  "Access URL" \
  "访问地址" \
  app.vaultwarden.summary.admin \
  "Admin panel" \
  "Admin 面板" \
  app.vaultwarden.summary.lan \
  "LAN test" \
  "内网测试" \
  app.vaultwarden.summary.version \
  "Version" \
  "版本" \
  app.vaultwarden.summary.binary \
  "Binary" \
  "二进制" \
  app.vaultwarden.summary.data \
  "Data dir" \
  "数据目录" \
  app.vaultwarden.summary.env \
  "Env file" \
  "环境配置" \
  app.vaultwarden.summary.mode600 \
  "mode 600" \
  "600 权限" \
  app.vaultwarden.summary.log \
  "Log" \
  "日志" \
  app.vaultwarden.summary.backup \
  "Backup dir" \
  "备份目录" \
  app.vaultwarden.summary.token_warning \
  "Admin plaintext token was written to a temporary file (root-readable only)" \
  "Admin 明文 Token 已写入临时文件（仅 root 可读）" \
  app.vaultwarden.summary.view_command \
  "View command:" \
  "查看命令：" \
  app.vaultwarden.summary.remove_command \
  "Remove it immediately after viewing:" \
  "查看后请立即运行：" \
  app.vaultwarden.summary.first_steps \
  "First-use steps:" \
  "首次使用步骤：" \
  app.vaultwarden.summary.step0 \
  "0. View and save the Admin Token (delete the temporary file immediately after viewing!)" \
  "0. 查看并保存 Admin Token（查看后立即删除临时文件！）" \
  app.vaultwarden.summary.step1 \
  "1. Open in a browser and create your account" \
  "1. 用浏览器访问，创建你的账号" \
  app.vaultwarden.summary.create_account \
  "%s  ->  click Create account" \
  "%s  →  点击「创建账号」" \
  app.vaultwarden.summary.step2 \
  "2. After setup, disable public registration (choose one method)" \
  "2. 完成后关闭公开注册（两种方式二选一）" \
  app.vaultwarden.summary.method_admin \
  "Method A - Admin panel: %s/admin -> General settings" \
  "方式 A - Admin 面板：%s/admin → General settings" \
  app.vaultwarden.summary.method_config \
  "Method B - Edit config file: sed -i 's/SIGNUPS_ALLOWED=true/SIGNUPS_ALLOWED=false/' %s" \
  "方式 B - 编辑配置文件：sed -i 's/SIGNUPS_ALLOWED=true/SIGNUPS_ALLOWED=false/' %s" \
  app.vaultwarden.summary.then_restart \
  "Then: systemctl restart vaultwarden" \
  "然后：systemctl restart vaultwarden" \
  app.vaultwarden.summary.step3 \
  "3. Configure Bitwarden clients (browser extension / app) for self-hosting" \
  "3. 配置 Bitwarden 客户端（浏览器扩展 / App）连接自托管" \
  app.vaultwarden.summary.self_hosted \
  "Login page -> choose Self-hosted -> server URL: %s" \
  "登录页 → 选择「自托管」→ 服务器地址填：%s" \
  app.vaultwarden.summary.step4 \
  "4. Common management commands" \
  "4. 常用管理命令" \
  app.vaultwarden.summary.cmd_status \
  "show service status" \
  "查看服务状态" \
  app.vaultwarden.summary.cmd_logs \
  "follow logs" \
  "实时日志" \
  app.vaultwarden.summary.cmd_restart \
  "restart service" \
  "重启服务" \
  app.vaultwarden.summary.cmd_backup \
  "create a backup now" \
  "立即备份" \
  app.vaultwarden.summary.important \
  "[important]" \
  "[重要]" \
  app.vaultwarden.summary.token_cleanup \
  "Delete the Admin Token temporary file immediately after viewing it to avoid leaving it on disk!" \
  "Admin Token 临时文件查看后请立即删除，避免遗留在磁盘！" \
  app.vaultwarden.step.update \
  "Update Vaultwarden binary and Web Vault" \
  "更新 Vaultwarden 二进制与 Web Vault" \
  app.vaultwarden.error.not_installed_update \
  "Vaultwarden is not installed. Run install first." \
  "未检测到已安装的 Vaultwarden，请先执行 install。" \
  app.vaultwarden.info.current_version \
  "Current version: %s" \
  "当前版本：%s" \
  app.vaultwarden.info.pre_update_backup \
  "Creating automatic backup before update..." \
  "更新前自动备份数据..." \
  app.vaultwarden.warn.pre_update_failed_state \
  "vaultwarden service was already failed before update; this update will also reset that failed state." \
  "注意：更新前 vaultwarden 服务处于 failed 状态，本次更新将同时重置该故障状态。" \
  app.vaultwarden.warn.pre_update_existing_error \
  "If the service still has issues after update, inspect the pre-existing error: journalctl -u vaultwarden -n 50 --no-pager" \
  "如果更新后仍有问题，请检查更新前已存在的错误：journalctl -u vaultwarden -n 50 --no-pager。" \
  app.vaultwarden.info.stop_service \
  "Stopping Vaultwarden service..." \
  "停止 Vaultwarden 服务..." \
  app.vaultwarden.step.extract_update_binary \
  "Extract new version binary" \
  "提取新版本二进制" \
  app.vaultwarden.success.binary_updated \
  "Binary updated." \
  "二进制已更新。" \
  app.vaultwarden.step.update_web_vault \
  "Update Web Vault" \
  "更新 Web Vault" \
  app.vaultwarden.success.web_vault_updated_image \
  "Web Vault updated from the Alpine image." \
  "Web Vault 已更新（来自 Alpine 镜像）。" \
  app.vaultwarden.success.web_vault_updated_version \
  "Web Vault v%s updated." \
  "Web Vault v%s 已更新。" \
  app.vaultwarden.warn.web_vault_extract \
  "Web Vault extraction failed; trying to restore the old version..." \
  "Web Vault 解压失败，尝试恢复旧版本..." \
  app.vaultwarden.warn.web_vault_update_extract \
  "Web Vault update failed. The existing Web Vault was kept or a backup restore was attempted. Inspect %s and retry after fixing the archive or filesystem issue." \
  "Web Vault 更新失败。现有 Web Vault 已保留或已尝试从备份恢复。请检查 %s，并在修复压缩包或文件系统问题后重试。" \
  app.vaultwarden.warn.web_vault_update_download \
  "Web Vault download failed, so the existing Web Vault was left unchanged. Retry the update later or download the release manually from GitHub." \
  "Web Vault 下载失败，现有 Web Vault 未变更。请稍后重试更新，或手动从 GitHub 下载发布包。" \
  app.vaultwarden.warn.web_vault_update_version \
  "Cannot get the Web Vault version, so the existing Web Vault was left unchanged. Retry the update later after fixing network access to GitHub." \
  "无法获取 Web Vault 版本，现有 Web Vault 未变更。请先修复到 GitHub 的网络访问，再稍后重试更新。" \
  app.vaultwarden.warn.update_port_used \
  "Port %s is still in use (%s); the service may not be able to bind to it." \
  "端口 %s 仍被占用（%s），服务可能无法绑定端口。" \
  app.vaultwarden.success.restart \
  "Vaultwarden service restarted successfully." \
  "Vaultwarden 服务重启成功。" \
  app.vaultwarden.success.version_updated \
  "Version updated: %s -> %s" \
  "版本已更新：%s  →  %s" \
  app.vaultwarden.success.already_latest \
  "Already on the latest version (%s); no update needed." \
  "已是最新版本（%s），无需更新。" \
  app.vaultwarden.warn.restart_failed_rollback \
  "Service restart failed. Rolling back binary..." \
  "服务重启失败！正在回滚二进制..." \
  app.vaultwarden.warn.web_vault_rolled_back \
  "Web Vault rolled back." \
  "Web Vault 已回滚。" \
  app.vaultwarden.success.rollback \
  "Rollback complete; service restored to previous version (%s)." \
  "回滚完成，服务已恢复至旧版本（%s）。" \
  app.vaultwarden.error.update_rolled_back \
  "Update failed and was rolled back to previous version %s.\n  To inspect the new-version issue: journalctl -u vaultwarden -n 50 --no-pager\n  New binary backup kept at: %s" \
  "更新失败，已回滚至旧版本 %s。\n  如需排查新版本问题：journalctl -u vaultwarden -n 50 --no-pager\n  新版本二进制备份保留在：%s" \
  app.vaultwarden.error.rollback_start_failed \
  "Service still cannot start after rollback. Inspect manually: journalctl -u vaultwarden -n 30 --no-pager" \
  "回滚后服务仍无法启动，请手动检查：journalctl -u vaultwarden -n 30 --no-pager。" \
  app.vaultwarden.error.no_backup_binary \
  "Backup binary was not found, so rollback failed. Inspect manually: journalctl -u vaultwarden -n 30 --no-pager" \
  "未找到备份二进制，回滚失败！请手动检查：journalctl -u vaultwarden -n 30 --no-pager。" \
  app.vaultwarden.info.cleaned_webvault_backups \
  "Removed %s old web-vault backup directories (keeping the latest 3)." \
  "已清理 %s 个过期 web-vault 备份目录（保留最近 3 个）。" \
  app.vaultwarden.backup.script.data_missing \
  "[ERROR] Data directory does not exist (%s); backup aborted." \
  "[ERROR] 数据目录不存在（%s），备份已中止。" \
  app.vaultwarden.backup.script.sqlite_warning \
  "[WARN] SQLite integrity check failed (%s). Backup will continue, but the database may be corrupted." \
  "[WARN] SQLite 完整性校验失败（%s），备份仍将继续但数据库可能已损坏。" \
  app.vaultwarden.backup.script.success \
  "[OK] Backup succeeded: %s (%s)" \
  "[OK] 备份成功：%s（%s）" \
  app.vaultwarden.backup.script.failed \
  "[ERROR] Backup failed; temporary file removed." \
  "[ERROR] 备份失败，临时文件已清理。" \
  app.vaultwarden.backup.script.cleaned \
  "[OK] Removed %s expired backups (>%s days)." \
  "[OK] 已清理 %s 个过期备份（>%s 天）。" \
  app.vaultwarden.warn.backup_data_missing \
  "Backup skipped: data directory does not exist (%s)." \
  "备份跳过：数据目录不存在（%s）。" \
  app.vaultwarden.warn.sqlite_integrity \
  "SQLite integrity check warning (%s). Backup continues, but the database may be corrupted." \
  "SQLite 完整性校验警告（%s），备份继续但数据库可能已损坏。" \
  app.vaultwarden.success.backup_created \
  "Backup created: %s" \
  "备份已创建：%s" \
  app.vaultwarden.warn.backup_failed_continue \
  "Backup failed; temporary file removed. Continuing. Inspect /opt/vaultwarden-backups/backup.log or run /usr/local/bin/vaultwarden-backup manually before proceeding further." \
  "备份失败，临时文件已清理，继续执行。请检查 /opt/vaultwarden-backups/backup.log，或先手动执行 /usr/local/bin/vaultwarden-backup 再继续后续操作。" \
  app.vaultwarden.error.manual_backup_failed \
  "Manual backup did not complete successfully. Inspect /opt/vaultwarden-backups/backup.log, review the existing backups above, and retry after fixing the archive or filesystem issue." \
  "手动备份未成功完成。请检查 /opt/vaultwarden-backups/backup.log，核对上方已有备份，并在修复压缩包或文件系统问题后重试。" \
  app.vaultwarden.error.backup_script \
  "Backup script write failed: /usr/local/bin/vaultwarden-backup" \
  "备份脚本写入失败：/usr/local/bin/vaultwarden-backup" \
  app.vaultwarden.step.manual_backup \
  "Manual Vaultwarden backup" \
  "手动备份 Vaultwarden" \
  app.vaultwarden.error.data_missing_install \
  "Data directory does not exist: %s. Run install first." \
  "数据目录不存在：%s，请先执行安装。" \
  app.vaultwarden.info.backup_list \
  "All current backups (latest 10):" \
  "当前所有备份（最近 10 个）：" \
  app.vaultwarden.warn.no_backups \
  "No backup files yet." \
  "暂无备份文件。" \
  app.vaultwarden.info.backup_total \
  "%s backups total, %s combined." \
  "共 %s 个备份，合计 %s。" \
  app.vaultwarden.warn.non_root_status \
  "Running as non-root; some status details (fail2ban, systemd details, etc.) may be incomplete." \
  "当前以非 root 用户运行，部分状态信息（fail2ban、systemd 详情等）可能不完整。" \
  app.vaultwarden.warn.root_status \
  "For complete status, run: sudo bash %s status" \
  "如需完整状态，请：sudo bash %s status" \
  app.vaultwarden.step.status \
  "Vaultwarden system status" \
  "Vaultwarden 系统状态" \
  app.vaultwarden.status.systemd \
  "systemd service status" \
  "systemd 服务状态" \
  app.vaultwarden.status.service_missing \
  "vaultwarden service is not installed or not running" \
  "vaultwarden 服务未安装或未运行" \
  app.vaultwarden.status.version_info \
  "Version info" \
  "版本信息" \
  app.vaultwarden.status.binary_version \
  "Binary version: %s" \
  "二进制版本：%s" \
  app.vaultwarden.status.binary_path \
  "Binary path: %s (%s)" \
  "二进制路径：%s（%s）" \
  app.vaultwarden.status.binary_time \
  "Binary time: %s" \
  "二进制时间：%s" \
  app.vaultwarden.status.binary_missing \
  "Vaultwarden binary was not found: %s" \
  "未找到 Vaultwarden 二进制：%s" \
  app.vaultwarden.status.data_dir \
  "Data directory (%s)" \
  "数据目录（%s）" \
  app.vaultwarden.status.total \
  "Total: %s" \
  "合计：%s" \
  app.vaultwarden.status.database \
  "Database: db.sqlite3 (%s)" \
  "数据库：db.sqlite3（%s）" \
  app.vaultwarden.status.data_missing \
  "Data directory does not exist" \
  "数据目录不存在" \
  app.vaultwarden.status.backup_files \
  "Backup files (latest 5)" \
  "备份文件（最近 5 个）" \
  app.vaultwarden.status.backup_count \
  "%s backups total" \
  "共 %s 个备份" \
  app.vaultwarden.status.nginx \
  "Nginx status" \
  "Nginx 状态" \
  app.vaultwarden.status.nginx_running \
  "nginx is running" \
  "nginx 运行中" \
  app.vaultwarden.status.nginx_stopped \
  "nginx is not running" \
  "nginx 未运行" \
  app.vaultwarden.status.fail2ban \
  "Fail2Ban status" \
  "Fail2Ban 状态" \
  app.vaultwarden.status.fail2ban_jail_missing \
  "fail2ban is running, but the vaultwarden jail is not loaded" \
  "fail2ban 运行中，但 vaultwarden jail 未加载" \
  app.vaultwarden.status.fail2ban_stopped \
  "fail2ban is not running" \
  "fail2ban 未运行" \
  app.vaultwarden.status.http_health \
  "HTTP health check" \
  "HTTP 健康检查" \
  app.vaultwarden.status.local_response \
  "Local endpoint response: HTTP %s" \
  "本地接口响应：HTTP %s" \
  app.vaultwarden.status.local_response_warn \
  "Local endpoint response: HTTP %s (service not running, wrong port, or still initializing?)" \
  "本地接口响应：HTTP %s（服务未运行、端口错误或仍在初始化？）" \
  app.vaultwarden.status.tls \
  "TLS certificate" \
  "TLS 证书" \
  app.vaultwarden.status.cert_valid \
  "Certificate is valid, %s days remaining (%s)" \
  "证书有效，剩余 %s 天（%s）" \
  app.vaultwarden.status.cert_expiring \
  "Certificate is expiring soon (%s days remaining). Run certbot renew soon." \
  "证书即将到期（剩余 %s 天），请尽快执行：certbot renew。" \
  app.vaultwarden.status.cert_expired \
  "Certificate expired (%s days ago). Run certbot renew immediately." \
  "证书已过期（%s 天前），请立即执行：certbot renew。" \
  app.vaultwarden.status.cert_missing \
  "Certificate was not found (HTTPS is not configured or certificate path is wrong)." \
  "未找到证书（未配置 HTTPS 或证书路径有误）。" \
  app.vaultwarden.error.bin_empty \
  "VW_BIN is not set. Run install first or confirm the config file exists." \
  "VW_BIN 未设置，请先执行 install 或确认配置文件存在。" \
  app.vaultwarden.error.data_dir_empty \
  "VW_DATA_DIR is not set; uninstall aborted." \
  "VW_DATA_DIR 未设置，卸载已中止。" \
  app.vaultwarden.error.backup_dir_empty \
  "VW_BACKUP_DIR is not set; uninstall aborted." \
  "VW_BACKUP_DIR 未设置，卸载已中止。" \
  app.vaultwarden.error.data_dir_root \
  "VW_DATA_DIR is root (/); refusing uninstall." \
  "VW_DATA_DIR 为根目录（/），拒绝卸载。" \
  app.vaultwarden.error.backup_dir_root \
  "VW_BACKUP_DIR is root (/); refusing uninstall." \
  "VW_BACKUP_DIR 为根目录（/），拒绝卸载。" \
  app.vaultwarden.step.uninstall \
  "Uninstall Vaultwarden" \
  "卸载 Vaultwarden" \
  app.vaultwarden.uninstall.removes \
  "This will remove:" \
  "此操作将删除：" \
  app.vaultwarden.uninstall.binary \
  "Vaultwarden binary (%s)" \
  "Vaultwarden 二进制（%s）" \
  app.vaultwarden.uninstall.systemd \
  "systemd service unit" \
  "systemd 服务单元" \
  app.vaultwarden.uninstall.nginx \
  "Nginx config" \
  "Nginx 配置" \
  app.vaultwarden.uninstall.fail2ban \
  "Fail2Ban rules" \
  "Fail2Ban 规则" \
  app.vaultwarden.uninstall.env \
  "environment file (%s)" \
  "环境变量文件（%s）" \
  app.vaultwarden.uninstall.cron \
  "scheduled backup job" \
  "定时备份任务" \
  app.vaultwarden.uninstall.keep_data \
  "Data directory (%s) is kept by default; you can choose deletion." \
  "数据目录（%s）默认保留，可选是否删除。" \
  app.vaultwarden.prompt.continue \
  "Continue uninstall? Type YES to confirm:" \
  "确认继续卸载？（输入 YES 确认）：" \
  app.vaultwarden.info.cancelled \
  "Cancelled." \
  "已取消。" \
  app.vaultwarden.prompt.delete_data \
  "Delete data directory too (%s)? (y/N):" \
  "是否同时删除数据目录（%s）？（y/N）：" \
  app.vaultwarden.prompt.delete_backup \
  "Delete backup directory too (%s)? (y/N):" \
  "是否同时删除备份目录（%s）？（y/N）：" \
  app.vaultwarden.success.removed_systemd \
  "systemd service removed." \
  "systemd 服务已移除。" \
  app.vaultwarden.success.removed_binary \
  "Binary removed." \
  "二进制已删除。" \
  app.vaultwarden.success.removed_nginx \
  "Nginx config removed." \
  "Nginx 配置已清除。" \
  app.vaultwarden.success.removed_fail2ban \
  "Fail2Ban rules removed." \
  "Fail2Ban 规则已清除。" \
  app.vaultwarden.success.removed_scheduled \
  "Scheduled job, backup script, and logrotate config removed." \
  "定时任务、备份脚本、日志轮转已清除。" \
  app.vaultwarden.success.removed_config \
  "Config files removed." \
  "配置文件已清除。" \
  app.vaultwarden.success.deleted_log \
  "Log directory deleted: %s" \
  "日志目录已删除：%s。" \
  app.vaultwarden.warn.log_path \
  "Log directory path is unusual (%s); skipped deletion." \
  "日志目录路径异常（%s），已跳过删除。" \
  app.vaultwarden.success.deleted_data \
  "Data directory deleted: %s" \
  "数据目录已删除：%s。" \
  app.vaultwarden.info.kept_data \
  "Data directory kept: %s" \
  "数据目录已保留：%s。" \
  app.vaultwarden.success.deleted_backup \
  "Backup directory deleted: %s" \
  "备份目录已删除：%s。" \
  app.vaultwarden.info.kept_backup \
  "Backup directory kept: %s" \
  "备份目录已保留：%s。" \
  app.vaultwarden.success.deleted_user \
  "System user %s deleted." \
  "系统用户 %s 已删除。" \
  app.vaultwarden.success.uninstalled \
  "Vaultwarden fully uninstalled" \
  "Vaultwarden 已完全卸载" \
  app.vaultwarden.hint.data_kept \
  "Data kept at: %s" \
  "数据保留在：%s" \
  app.vaultwarden.hint.remove_data \
  "When you are sure it is no longer needed, manually run: rm -rf %s" \
  "如确认不再需要，可手动执行：rm -rf %s"

APP_DESCRIPTION="$(t app.vaultwarden.description)"
APP_IMPL_SCRIPT="impl/install_vaultwarden.sh"

load_app_impl "$APP_IMPL_SCRIPT"
