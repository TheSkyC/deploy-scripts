#!/usr/bin/env bash

APP_ID="sub2api"
APP_NAME="Sub2API"
i18n_register_many \
  app.sub2api.description \
  "API gateway deployment with database, cache, systemd, and backups." \
  "包含数据库、缓存、systemd 和备份的 API 网关部署脚本。" \
  app.sub2api.error.package_manager \
  "No supported package manager was found. Install dependencies manually or use apt, dnf, or yum." \
  "未找到支持的包管理器（apt / dnf / yum），请手动安装依赖。" \
  app.sub2api.error.arch \
  "Unsupported architecture: %s. Supported: x86_64 / aarch64." \
  "不支持的架构：%s（支持 x86_64 / aarch64）。" \
  app.sub2api.error.github_unreachable \
  "Cannot reach GitHub. Check network/proxy settings and retry." \
  "网络不通，无法访问 GitHub，请检查网络或代理后重试。" \
  app.sub2api.warn.github_api \
  "Cannot reach GitHub API." \
  "无法访问 GitHub API。" \
  app.sub2api.warn.checksum_download \
  "Cannot download checksums.txt; skipping SHA256 verification. Manual verification is recommended." \
  "无法下载 checksums.txt，跳过 SHA256 校验（建议手动核验）。" \
  app.sub2api.warn.checksum_missing \
  "checksums.txt does not contain a checksum for %s; skipping verification." \
  "checksums.txt 中未找到 %s 的校验值，跳过校验。" \
  app.sub2api.warn.sha_tool_missing \
  "sha256sum / shasum was not found; skipping SHA256 verification." \
  "未找到 sha256sum / shasum，跳过 SHA256 校验。" \
  app.sub2api.error.sha_failed \
  "SHA256 verification failed!\n  expected: %s\n  actual: %s" \
  "SHA256 校验失败！\n  期望：%s\n  实际：%s" \
  app.sub2api.success.sha_ok \
  "SHA256 verification passed (%s...)." \
  "SHA256 校验通过（%s...）。" \
  app.sub2api.error.tar_extract \
  "tar extraction failed; the archive may be corrupted." \
  "tar 解压失败，归档文件可能已损坏。" \
  app.sub2api.error.archive_missing_binary \
  "sub2api binary was not found in the tar.gz archive. Confirm the download URL." \
  "tar.gz 中未找到 sub2api 二进制文件，请确认下载 URL 是否正确。" \
  app.sub2api.error.not_elf \
  "Binary is not a valid ELF file (magic: %s)." \
  "二进制不是有效的 ELF 格式（magic: %s）。" \
  app.sub2api.error.elf_machine \
  "ELF architecture mismatch (e_machine=%s, expected=%s, current platform=%s)." \
  "ELF 架构不匹配（e_machine=%s，期望=%s，当前平台=%s）。" \
  app.sub2api.success.elf_ok \
  "ELF verification passed (arch %s, %s MB)." \
  "ELF 校验通过（架构 %s，%s MB）。" \
  app.sub2api.success.http_health \
  "HTTP health check passed (status %s)." \
  "HTTP 健康检查通过（状态码 %s）。" \
  app.sub2api.warn.http_health \
  "Health check returned %s. The service may still be initializing." \
  "健康检查返回 %s，服务可能仍在初始化。" \
  app.sub2api.warn.debug_command \
  "Debug command: journalctl -u %s -n 30 --no-pager" \
  "调试命令：journalctl -u %s -n 30 --no-pager" \
  app.sub2api.warn.setup_wizard \
  "After database/Redis setup is complete, visit the Setup Wizard in a browser: http://<IP>:%s/" \
  "完成数据库/Redis 配置后，请在浏览器访问 Setup Wizard：http://<IP>:%s/" \
  app.sub2api.info.install_base_deps \
  "Installing base dependencies..." \
  "安装基础依赖..." \
  app.sub2api.success.base_deps \
  "Base dependencies installed." \
  "基础依赖安装完成。" \
  app.sub2api.success.postgres_exists \
  "PostgreSQL %s is already installed; skipping installation." \
  "PostgreSQL %s 已安装，跳过安装。" \
  app.sub2api.warn.postgres_old \
  "Detected PostgreSQL %s (< 15); installing PostgreSQL 15 from the official PGDG repository." \
  "检测到 PostgreSQL %s（< 15），将从 PGDG 官方源安装 PostgreSQL 15。" \
  app.sub2api.info.postgres_apt_source \
  "Adding the official PostgreSQL PGDG apt repository..." \
  "添加 PostgreSQL PGDG 官方 apt 源..." \
  app.sub2api.error.postgres_key \
  "Cannot download the PostgreSQL signing key. Check the network and retry." \
  "无法下载 PostgreSQL 签名密钥，请检查网络后重试。" \
  app.sub2api.success.postgres15 \
  "PostgreSQL 15 installed." \
  "PostgreSQL 15 安装完成。" \
  app.sub2api.info.postgres_rpm_source \
  "Adding the PostgreSQL PGDG RPM repository..." \
  "添加 PostgreSQL PGDG RPM 源..." \
  app.sub2api.success.redis_exists \
  "Redis %s is already installed; skipping installation." \
  "Redis %s 已安装，跳过安装。" \
  app.sub2api.warn.redis_old \
  "Detected Redis %s (< 7); installing Redis 7 from the official repository." \
  "检测到 Redis %s（< 7），将从官方源安装 Redis 7。" \
  app.sub2api.info.redis_apt_source \
  "Adding the official Redis apt repository..." \
  "添加 Redis 官方 apt 源..." \
  app.sub2api.success.redis7 \
  "Redis 7 installed." \
  "Redis 7 安装完成。" \
  app.sub2api.success.redis \
  "Redis installed." \
  "Redis 安装完成。" \
  app.sub2api.warn.postgres_not_running \
  "PostgreSQL service is not running; trying to start it..." \
  "PostgreSQL 服务未运行，尝试启动..." \
  app.sub2api.error.postgres_start \
  "Cannot start PostgreSQL service. Inspect: journalctl -u postgresql -n 30" \
  "无法启动 PostgreSQL 服务，请检查：journalctl -u postgresql -n 30" \
  app.sub2api.info.pg_password_generated \
  "Generated a random PostgreSQL password (24 characters)." \
  "已生成随机 PostgreSQL 密码（24 位）。" \
  app.sub2api.info.pg_password_reused \
  "Reusing the existing PostgreSQL password." \
  "复用已有 PostgreSQL 密码。" \
  app.sub2api.info.pg_setup \
  "Configuring PostgreSQL user and database..." \
  "配置 PostgreSQL 用户和数据库..." \
  app.sub2api.info.pg_user_exists \
  "PostgreSQL user '%s' already exists; synchronizing password..." \
  "PostgreSQL 用户 '%s' 已存在，同步密码..." \
  app.sub2api.success.pg_user_created \
  "PostgreSQL user '%s' created." \
  "PostgreSQL 用户 '%s' 已创建。" \
  app.sub2api.info.pg_db_exists \
  "PostgreSQL database '%s' already exists; skipping creation." \
  "PostgreSQL 数据库 '%s' 已存在，跳过创建。" \
  app.sub2api.success.pg_db_created \
  "PostgreSQL database '%s' created with owner %s." \
  "PostgreSQL 数据库 '%s' 已创建，属主：%s。" \
  app.sub2api.success.pg_dsn \
  "PostgreSQL DSN generated." \
  "PostgreSQL DSN 已生成。" \
  app.sub2api.info.nginx_exists \
  "Nginx is already installed; skipping installation." \
  "Nginx 已安装，跳过安装。" \
  app.sub2api.info.install_nginx \
  "Installing Nginx..." \
  "安装 Nginx..." \
  app.sub2api.success.nginx_installed \
  "Nginx installed." \
  "Nginx 安装完成。" \
  app.sub2api.warn.nginx_include \
  "Cannot update /etc/nginx/nginx.conf automatically. Add this inside http {} manually: include /etc/nginx/sites-enabled/*;" \
  "无法自动修改 /etc/nginx/nginx.conf，请手动在 http {} 块中添加：include /etc/nginx/sites-enabled/*;" \
  app.sub2api.success.nginx_domain \
  "Nginx reverse proxy is active (domain: %s -> :%s)." \
  "Nginx 反代配置已生效（域名：%s → :%s）。" \
  app.sub2api.success.nginx_fallback \
  "Nginx reverse proxy is active (fallback server_name _ -> :%s)." \
  "Nginx 反代配置已生效（兜底 server_name _ → :%s）。" \
  app.sub2api.warn.nginx_test_failed \
  "Nginx config test failed (nginx -t). Check the config file and run manually: nginx -t && systemctl reload nginx" \
  "Nginx 配置校验失败（nginx -t），请检查配置文件后手动执行：nginx -t && systemctl reload nginx。" \
  app.sub2api.success.ufw_port \
  "ufw allows port %s." \
  "ufw 已放行端口 %s。" \
  app.sub2api.success.firewalld_port \
  "firewalld allows port %s." \
  "firewalld 已放行端口 %s。" \
  app.sub2api.success.iptables_saved \
  "iptables rules persisted with netfilter-persistent." \
  "iptables 规则已持久化（netfilter-persistent）。" \
  app.sub2api.info.iptables_written \
  "iptables rules written to /etc/iptables/rules.v4." \
  "iptables 规则已写入 /etc/iptables/rules.v4。" \
  app.sub2api.warn.iptables_write_failed \
  "Failed to write iptables rules; rules may be lost after reboot." \
  "iptables 规则写入失败，重启后规则可能丢失。" \
  app.sub2api.warn.iptables_not_persisted \
  "iptables rules are not persisted and may be lost after reboot. Recommended: install iptables-persistent." \
  "iptables 规则未持久化，重启后失效。建议安装 iptables-persistent。" \
  app.sub2api.success.iptables_port \
  "iptables allows port %s." \
  "iptables 已放行端口 %s。" \
  app.sub2api.warn.no_firewall \
  "No active firewall detected. If you use a cloud security group, allow port %s manually." \
  "未检测到活跃防火墙，如有云安全组（AWS/阿里云/腾讯云）请手动放行端口 %s。" \
  app.sub2api.success.logrotate \
  "Log rotation configured (daily rotation, 14 days retained, compressed automatically)." \
  "日志轮转已配置（每日轮转，保留 14 天，自动压缩）。" \
  app.sub2api.backup.log.start \
  "Backup started" \
  "开始备份" \
  app.sub2api.backup.log.pg_dump_start \
  "[DB] Starting pg_dump..." \
  "[DB] 开始 pg_dump..." \
  app.sub2api.backup.log.pg_dump_ok \
  "[DB] pg_dump succeeded: %s (%s)" \
  "[DB] pg_dump 成功：%s（%s）" \
  app.sub2api.backup.log.pg_dump_failed \
  "[WARN] pg_dump failed; skipping database backup and continuing with config files." \
  "[WARN] pg_dump 失败，跳过数据库备份（继续备份配置文件）。" \
  app.sub2api.backup.log.pg_dsn_missing \
  "[WARN] PG_DSN is not configured; skipping database backup." \
  "[WARN] PG_DSN 未配置，跳过数据库备份。" \
  app.sub2api.backup.log.pg_dump_missing \
  "[WARN] pg_dump command is missing; skipping database backup." \
  "[WARN] pg_dump 命令不存在，跳过数据库备份。" \
  app.sub2api.backup.log.config_ok \
  "[OK] Config directory backup: %s" \
  "[OK] 配置目录备份：%s" \
  app.sub2api.backup.log.config_failed \
  "[WARN] Config directory backup failed." \
  "[WARN] 配置目录备份失败。" \
  app.sub2api.backup.log.data_ok \
  "[OK] Data directory backup: %s (%s)" \
  "[OK] 数据目录备份：%s（%s）" \
  app.sub2api.backup.log.data_failed \
  "[ERROR] Data directory tar failed; temporary archive removed." \
  "[ERROR] 数据目录 tar 失败，临时文件已清理。" \
  app.sub2api.backup.log.removed_old \
  "[OK] Removed %s old backups older than %s days." \
  "[OK] 已清理 %s 个超过 %s 天的旧备份。" \
  app.sub2api.backup.log.done \
  "Backup finished" \
  "备份完成" \
  app.sub2api.success.backup_script \
  "Backup script written: /usr/local/bin/sub2api-backup" \
  "备份脚本已写入：/usr/local/bin/sub2api-backup。" \
  app.sub2api.success.silent_pg_dump \
  "Silent pg_dump backup: %s (%s)." \
  "静默 pg_dump 备份：%s（%s）。" \
  app.sub2api.warn.pg_dump_failed \
  "pg_dump failed; continuing. This may affect data recovery capability." \
  "pg_dump 失败，继续执行（可能影响数据恢复能力）。" \
  app.sub2api.warn.pg_snapshot_skip \
  "PG_DSN is not configured or pg_dump is missing; skipping database snapshot." \
  "PG_DSN 未配置或 pg_dump 不存在，跳过数据库快照。" \
  app.sub2api.success.config_backup \
  "Config directory backup: %s (%s)." \
  "配置目录备份：%s（%s）。" \
  app.sub2api.warn.config_backup_failed \
  "Config directory backup failed (tar error)." \
  "配置目录备份失败（tar 报错）。"

APP_DESCRIPTION="$(t app.sub2api.description)"
APP_IMPL_SCRIPT="impl/install_sub2api.sh"

load_app_impl "$APP_IMPL_SCRIPT"
