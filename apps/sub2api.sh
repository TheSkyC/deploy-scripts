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
  app.sub2api.error.os_codename \
  "Cannot determine the Debian / Ubuntu codename from lsb_release or /etc/os-release." \
  "无法从 lsb_release 或 /etc/os-release 获取 Debian / Ubuntu 发行版代号。" \
  app.sub2api.error.arch \
  "Unsupported architecture: %s. Supported: x86_64 / aarch64." \
  "不支持的架构：%s（支持 x86_64 / aarch64）。" \
  app.sub2api.error.github_unreachable \
  "Cannot reach GitHub. Check network/proxy settings and retry." \
  "网络不通，无法访问 GitHub，请检查网络或代理后重试。" \
  app.sub2api.warn.github_api \
  "Cannot reach GitHub API." \
  "无法访问 GitHub API。" \
  app.sub2api.error.checksum_temp \
  "Cannot create a temporary checksum file; refusing to install an unverified archive." \
  "无法创建临时校验文件，拒绝安装未经校验的归档文件。" \
  app.sub2api.error.checksum_download \
  "Cannot download checksums.txt; refusing to install an unverified archive." \
  "无法下载 checksums.txt，拒绝安装未经校验的归档文件。" \
  app.sub2api.error.checksum_missing \
  "checksums.txt does not contain a checksum for %s; refusing to install an unverified archive." \
  "checksums.txt 中未找到 %s 的校验值，拒绝安装未经校验的归档文件。" \
  app.sub2api.error.sha_tool_missing \
  "sha256sum / shasum was not found; refusing to install an unverified archive." \
  "未找到 sha256sum / shasum，拒绝安装未经校验的归档文件。" \
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
  app.sub2api.error.apt_update \
  "apt-get update failed. Check /var/log/apt/*, fix repository or network issues, and retry." \
  "apt-get update 失败。请检查 /var/log/apt/*，修复软件源或网络问题后重试。" \
  app.sub2api.error.base_deps_install \
  "Base dependency installation failed. Run apt-get install -y curl ca-certificates gnupg lsb-release after fixing the package manager state." \
  "基础依赖安装失败。请在修复软件包管理器状态后执行 apt-get install -y curl ca-certificates gnupg lsb-release。" \
  app.sub2api.error.base_deps_install_pkg \
  "Base dependency installation failed. Install curl and ca-certificates with dnf or yum after fixing the package manager state." \
  "基础依赖安装失败。请在修复软件包管理器状态后使用 dnf 或 yum 安装 curl 和 ca-certificates。" \
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
  app.sub2api.error.postgres_keyring_dir \
  "Cannot prepare the PostgreSQL keyring directory: %s. Check filesystem permissions and retry." \
  "无法准备 PostgreSQL keyring 目录：%s。请检查文件系统权限后重试。" \
  app.sub2api.error.postgres_key \
  "Cannot download the PostgreSQL signing key. Check the network and retry." \
  "无法下载 PostgreSQL 签名密钥，请检查网络后重试。" \
  app.sub2api.error.postgres_source_dir \
  "Cannot prepare the PostgreSQL apt source directory: %s. Check filesystem permissions and retry." \
  "无法准备 PostgreSQL apt 源目录：%s。请检查文件系统权限后重试。" \
  app.sub2api.error.postgres_source \
  "PostgreSQL apt source write failed: /etc/apt/sources.list.d/pgdg.list" \
  "PostgreSQL apt 源写入失败：/etc/apt/sources.list.d/pgdg.list。" \
  app.sub2api.error.postgres_apt_update \
  "apt-get update failed after adding the PostgreSQL PGDG repository. Check /var/log/apt/* and /etc/apt/sources.list.d/pgdg.list, then retry." \
  "添加 PostgreSQL PGDG 源后 apt-get update 失败。请检查 /var/log/apt/* 和 /etc/apt/sources.list.d/pgdg.list，然后重试。" \
  app.sub2api.error.postgres_apt_install \
  "PostgreSQL 15 installation failed. Run apt-get install -y postgresql-15 postgresql-client-15 after fixing the package manager state." \
  "PostgreSQL 15 安装失败。请在修复软件包管理器状态后执行 apt-get install -y postgresql-15 postgresql-client-15。" \
  app.sub2api.success.postgres15 \
  "PostgreSQL 15 installed." \
  "PostgreSQL 15 安装完成。" \
  app.sub2api.info.postgres_rpm_source \
  "Adding the PostgreSQL PGDG RPM repository..." \
  "添加 PostgreSQL PGDG RPM 源..." \
  app.sub2api.error.postgres_repo \
  "Cannot install the PostgreSQL PGDG RPM repository. Check the network and package manager output." \
  "无法安装 PostgreSQL PGDG RPM 仓库。请检查网络和包管理器输出。" \
  app.sub2api.error.postgres_module \
  "Cannot disable the built-in PostgreSQL module. Resolve the package manager error and retry." \
  "无法禁用内置 PostgreSQL 模块。请先解决包管理器错误后重试。" \
  app.sub2api.error.postgres_initdb \
  "PostgreSQL 15 database initialization failed. Inspect: journalctl -u postgresql-15 -n 30" \
  "PostgreSQL 15 数据目录初始化失败，请检查：journalctl -u postgresql-15 -n 30" \
  app.sub2api.error.postgres_rpm_install \
  "PostgreSQL 15 package installation failed. Repair the package manager state, then run dnf install -y postgresql15-server postgresql15-contrib or yum install -y postgresql15-server postgresql15-contrib." \
  "PostgreSQL 15 软件包安装失败。请先修复包管理器状态，再执行 dnf install -y postgresql15-server postgresql15-contrib 或 yum install -y postgresql15-server postgresql15-contrib。" \
  app.sub2api.success.redis_exists \
  "Redis %s is already installed; skipping installation." \
  "Redis %s 已安装，跳过安装。" \
  app.sub2api.warn.redis_old \
  "Detected Redis %s (< 7); installing Redis 7 from the official repository." \
  "检测到 Redis %s（< 7），将从官方源安装 Redis 7。" \
  app.sub2api.info.redis_apt_source \
  "Adding the official Redis apt repository..." \
  "添加 Redis 官方 apt 源..." \
  app.sub2api.error.redis_keyring_dir \
  "Cannot prepare the Redis keyring directory: %s. Check filesystem permissions and retry." \
  "无法准备 Redis keyring 目录：%s。请检查文件系统权限后重试。" \
  app.sub2api.error.redis_key \
  "Cannot download or convert the Redis signing key. Check the network and retry." \
  "无法下载或转换 Redis 签名密钥，请检查网络后重试。" \
  app.sub2api.error.redis_source_dir \
  "Cannot prepare the Redis apt source directory: %s. Check filesystem permissions and retry." \
  "无法准备 Redis apt 源目录：%s。请检查文件系统权限后重试。" \
  app.sub2api.error.redis_source \
  "Redis apt source write failed: /etc/apt/sources.list.d/redis.list" \
  "Redis apt 源写入失败：/etc/apt/sources.list.d/redis.list。" \
  app.sub2api.error.redis_apt_update \
  "apt-get update failed after adding the Redis repository. Check /var/log/apt/* and /etc/apt/sources.list.d/redis.list, then retry." \
  "添加 Redis 源后 apt-get update 失败。请检查 /var/log/apt/* 和 /etc/apt/sources.list.d/redis.list，然后重试。" \
  app.sub2api.error.redis_apt_install \
  "Redis installation failed. Run apt-get install -y redis after fixing the package manager state." \
  "Redis 安装失败。请在修复软件包管理器状态后执行 apt-get install -y redis。" \
  app.sub2api.error.redis_pkg_install \
  "Redis installation failed. Repair the package manager state, then run dnf install -y redis or yum install -y redis." \
  "Redis 安装失败。请先修复包管理器状态，再执行 dnf install -y redis 或 yum install -y redis。" \
  app.sub2api.success.redis7 \
  "Redis 7 installed." \
  "Redis 7 安装完成。" \
  app.sub2api.success.redis \
  "Redis installed." \
  "Redis 安装完成。" \
  app.sub2api.error.redis_start \
  "Cannot start Redis service. Inspect: journalctl -u redis -n 30" \
  "无法启动 Redis 服务，请检查：journalctl -u redis -n 30" \
  app.sub2api.warn.postgres_not_running \
  "PostgreSQL service is not running; trying to start it..." \
  "PostgreSQL 服务未运行，尝试启动..." \
  app.sub2api.warn.service_enable_failed \
  "Could not enable %s to start automatically on boot. Run manually after fixing systemd: systemctl enable %s" \
  "无法将 %s 设置为开机自启。请在修复 systemd 问题后手动执行：systemctl enable %s。" \
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
  app.sub2api.error.nginx_install \
  "Nginx installation failed. Repair the package manager state, then run apt-get install -y nginx, dnf install -y nginx, or yum install -y nginx as appropriate." \
  "Nginx 安装失败。请先修复包管理器状态，再按当前系统执行 apt-get install -y nginx、dnf install -y nginx 或 yum install -y nginx。" \
  app.sub2api.success.nginx_installed \
  "Nginx installed." \
  "Nginx 安装完成。" \
  app.sub2api.error.nginx_start \
  "Cannot start Nginx service. Inspect: journalctl -u nginx -n 30" \
  "无法启动 Nginx 服务，请检查：journalctl -u nginx -n 30" \
  app.sub2api.error.nginx_config_write \
  "Nginx config write failed: %s" \
  "Nginx 配置写入失败：%s。" \
  app.sub2api.warn.nginx_include \
  "Cannot update /etc/nginx/nginx.conf automatically. Add this inside http {} manually: include /etc/nginx/sites-enabled/*;" \
  "无法自动修改 /etc/nginx/nginx.conf，请手动在 http {} 块中添加：include /etc/nginx/sites-enabled/*;" \
  app.sub2api.success.nginx_domain \
  "Nginx reverse proxy is active (domain: %s -> :%s)." \
  "Nginx 反代配置已生效（域名：%s → :%s）。" \
  app.sub2api.success.nginx_fallback \
  "Nginx reverse proxy is active (fallback server_name _ -> :%s)." \
  "Nginx 反代配置已生效（兜底 server_name _ → :%s）。" \
  app.sub2api.warn.nginx_reload_failed \
  "Nginx config test passed, but reload failed. Inspect the error output and rerun manually: systemctl reload nginx" \
  "Nginx 配置校验已通过，但 reload 失败。请检查错误输出后手动重试：systemctl reload nginx。" \
  app.sub2api.warn.nginx_test_failed \
  "Nginx config test failed (nginx -t). Check the config file and run manually: nginx -t && systemctl reload nginx" \
  "Nginx 配置校验失败（nginx -t），请检查配置文件后手动执行：nginx -t && systemctl reload nginx。" \
  app.sub2api.success.ufw_port \
  "ufw allows port %s." \
  "ufw 已放行端口 %s。" \
  app.sub2api.success.firewalld_port \
  "firewalld allows port %s." \
  "firewalld 已放行端口 %s。" \
  app.sub2api.warn.firewall_config_failed \
  "Automatic firewall configuration failed for port %s. Open it manually or retry after fixing the firewall service." \
  "端口 %s 的防火墙自动配置失败。请在修复防火墙服务后重试，或手动放行该端口。" \
  app.sub2api.success.iptables_saved \
  "iptables rules persisted with netfilter-persistent." \
  "iptables 规则已持久化（netfilter-persistent）。" \
  app.sub2api.info.iptables_rules_written \
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
  app.sub2api.error.logrotate \
  "Logrotate config write failed: /etc/logrotate.d/sub2api" \
  "日志轮转配置写入失败：/etc/logrotate.d/sub2api。" \
  app.sub2api.backup.log.start \
  "Backup started" \
  "开始备份" \
  app.sub2api.backup.log.dir_failed \
  "[ERROR] Cannot create backup directory: %s" \
  "[ERROR] 无法创建备份目录：%s" \
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
  app.sub2api.backup.log.remove_failed \
  "[WARN] Could not remove old backup: %s" \
  "[WARN] 旧备份删除失败：%s" \
  app.sub2api.backup.log.done \
  "Backup finished" \
  "备份完成" \
  app.sub2api.success.backup_script \
  "Backup script written: /usr/local/bin/sub2api-backup" \
  "备份脚本已写入：/usr/local/bin/sub2api-backup。" \
  app.sub2api.error.backup_script \
  "Backup script write failed: /usr/local/bin/sub2api-backup" \
  "备份脚本写入失败：/usr/local/bin/sub2api-backup。" \
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
  "Config directory backup failed. Inspect the tar output above; partial archives may still exist in the backup directory." \
  "配置目录备份失败。请检查上方 tar 输出；备份目录中可能仍保留了部分归档。" \
  app.sub2api.warn.backup_integrity \
  "Backup created but integrity metadata could not be written: %s" \
  "备份已创建，但完整性元数据写入失败：%s" \
  app.sub2api.summary.title_ready \
  "Sub2API deployment complete!" \
  "Sub2API 部署完成！" \
  app.sub2api.summary.title_pending \
  "Sub2API files installed; complete the Setup Wizard" \
  "Sub2API 文件已安装；请继续完成 Setup Wizard" \
  app.sub2api.summary.version \
  "Version" \
  "版本" \
  app.sub2api.summary.postgres_title \
  "PostgreSQL account (Setup Wizard -> Database)" \
  "PostgreSQL 账号（Setup Wizard → 数据库配置）" \
  app.sub2api.summary.redis_title \
  "Redis config (Setup Wizard -> Redis)" \
  "Redis 配置（Setup Wizard → Redis）" \
  app.sub2api.summary.host \
  "Host" \
  "主机" \
  app.sub2api.summary.port \
  "Port" \
  "端口" \
  app.sub2api.summary.username \
  "Username" \
  "用户名" \
  app.sub2api.summary.password \
  "Password" \
  "密码" \
  app.sub2api.summary.password_written \
  "written to %s (not printed)" \
  "已写入 %s（不在终端显示）" \
  app.sub2api.summary.database \
  "Database" \
  "数据库名" \
  app.sub2api.summary.ssl_mode \
  "SSL mode" \
  "SSL 模式" \
  app.sub2api.summary.ssl_disable \
  "disable" \
  "禁用" \
  app.sub2api.summary.empty \
  "(empty)" \
  "（留空）" \
  app.sub2api.summary.install_dir \
  "Install dir" \
  "安装目录" \
  app.sub2api.summary.data_dir \
  "Data dir" \
  "数据目录" \
  app.sub2api.summary.config_dir \
  "Config dir" \
  "配置目录" \
  app.sub2api.summary.log_dir \
  "Log dir" \
  "日志目录" \
  app.sub2api.summary.backup_dir \
  "Backup dir" \
  "备份目录" \
  app.sub2api.summary.next_steps \
  "Next steps:" \
  "后续步骤：" \
  app.sub2api.summary.next1 \
  "Open the Setup Wizard and fill database / Redis settings from the table above." \
  "打开 Setup Wizard，按上表填写数据库 / Redis 配置。" \
  app.sub2api.summary.next2_ready \
  "After the wizard is complete, the service will be ready and can be reached through Nginx." \
  "完成向导后服务自动就绪，可通过 Nginx 域名访问。" \
  app.sub2api.summary.next2_pending \
  "After the wizard is complete, run the status command again to confirm the service and Nginx are healthy." \
  "完成向导后，请再次运行 status 命令，确认服务和 Nginx 都已恢复健康。" \
  app.sub2api.summary.next3 \
  "The PostgreSQL password is saved to %s (chmod 600)." \
  "PostgreSQL 密码已保存至 %s（chmod 600）。" \
  app.sub2api.summary.management \
  "Management commands:" \
  "管理命令：" \
  app.sub2api.summary.cmd_status \
  "show runtime status" \
  "查看运行状态" \
  app.sub2api.summary.cmd_update \
  "update to the latest version" \
  "更新到最新版" \
  app.sub2api.summary.cmd_backup \
  "create a backup now" \
  "立即备份数据" \
  app.sub2api.summary.cmd_uninstall \
  "uninstall the service" \
  "卸载服务" \
  app.sub2api.summary.systemd \
  "systemd commands:" \
  "systemd 命令：" \
  app.sub2api.summary.systemd_status \
  "show status" \
  "查看状态" \
  app.sub2api.summary.systemd_logs \
  "follow logs" \
  "实时日志" \
  app.sub2api.summary.systemd_restart \
  "restart service" \
  "重启服务" \
  app.sub2api.step.latest \
  "Step 1  Get latest version" \
  "Step 1  获取最新版本" \
  app.sub2api.info.query_release \
  "Querying the latest GitHub release..." \
  "查询 GitHub 最新 Release..." \
  app.sub2api.error.version_lookup \
  "Failed to get the version. Check network connectivity and retry." \
  "获取版本号失败，请检查网络后重试。" \
  app.sub2api.success.latest_version \
  "Latest version: %s" \
  "最新版本：%s" \
  app.sub2api.info.download_url \
  "Download URL: %s" \
  "下载地址：%s" \
  app.sub2api.step.base_deps \
  "Step 2  Install base dependencies (curl / gnupg / lsb-release)" \
  "Step 2  安装基础依赖（curl / gnupg / lsb-release）" \
  app.sub2api.step.postgres \
  "Step 3  Install PostgreSQL 15+" \
  "Step 3  安装 PostgreSQL 15+" \
  app.sub2api.step.redis \
  "Step 4  Install Redis 7+" \
  "Step 4  安装 Redis 7+" \
  app.sub2api.step.pg_account \
  "Step 6  Configure PostgreSQL account" \
  "Step 6  配置 PostgreSQL 账号" \
  app.sub2api.step.user_dirs \
  "Step 7  Create user and directories" \
  "Step 7  创建用户与目录" \
  app.sub2api.success.user_created \
  "System user %s created (low privilege, no login shell)." \
  "系统用户 %s 已创建（低权限，无登录 shell）。" \
  app.sub2api.info.user_exists \
  "User %s already exists; skipping creation." \
  "用户 %s 已存在，跳过创建。" \
  app.sub2api.error.user_create \
  "Failed to create system user %s. Check useradd output and retry." \
  "创建系统用户 %s 失败。请检查 useradd 输出后重试。" \
  app.sub2api.error.dir_create \
  "Failed to create one or more runtime directories. Check permissions for %s and %s, then retry." \
  "创建运行目录失败。请检查 %s 和 %s 的权限后重试。" \
  app.sub2api.error.dir_owner \
  "Failed to apply ownership %s to %s. Check filesystem permissions and retry." \
  "无法将 %s 的所有权设置到 %s。请检查文件系统权限后重试。" \
  app.sub2api.error.config_dir_mode \
  "Failed to set directory mode 750 on %s. Check filesystem permissions and retry." \
  "无法将 %s 的目录权限设置为 750。请检查文件系统权限后重试。" \
  app.sub2api.success.dirs_created \
  "Directories created." \
  "目录创建完成。" \
  app.sub2api.step.download_binary \
  "Step 8  Download and verify Sub2API binary (arch: %s)" \
  "Step 8  下载并校验 Sub2API 二进制（架构：%s）" \
  app.sub2api.error.download_failed \
  "Download failed. Check the network or confirm the release exists: https://github.com/%s/releases" \
  "下载失败，请检查网络或前往 https://github.com/%s/releases 确认版本存在。" \
  app.sub2api.warn.tmp_archive_cleanup_failed \
  "Failed to remove temporary archive %s. Remove it manually after this command finishes." \
  "删除临时归档 %s 失败。请在本次命令结束后手动清理。" \
  app.sub2api.warn.old_binary_backup \
  "Old binary backed up -> %s" \
  "已备份旧二进制 → %s" \
  app.sub2api.error.binary_install \
  "Failed to install binary: %s" \
  "二进制安装失败：%s" \
  app.sub2api.success.binary_installed \
  "Binary installed: %s" \
  "二进制安装完成：%s" \
  app.sub2api.step.systemd \
  "Step 9  Configure systemd service" \
  "Step 9  配置 systemd 服务" \
  app.sub2api.error.systemd_unit \
  "systemd service file write failed: /etc/systemd/system/%s.service" \
  "systemd 服务文件写入失败：/etc/systemd/system/%s.service" \
  app.sub2api.success.systemd_unit \
  "systemd service file written: /etc/systemd/system/%s.service" \
  "systemd 服务文件已写入：/etc/systemd/system/%s.service" \
  app.sub2api.error.systemd_reload \
  "systemd daemon reload failed for %s. Run manually after fixing systemd: systemctl daemon-reload" \
  "无法为 %s 重新加载 systemd daemon。请在修复 systemd 问题后手动执行：systemctl daemon-reload。" \
  app.sub2api.step.nginx \
  "Step 10  Install and configure Nginx reverse proxy" \
  "Step 10  安装并配置 Nginx 反向代理" \
  app.sub2api.step.firewall \
  "Step 11  Configure firewall" \
  "Step 11  配置防火墙" \
  app.sub2api.step.logrotate \
  "Step 12  Configure log rotation" \
  "Step 12  配置日志轮转" \
  app.sub2api.step.cron_backup \
  "Step 13  Configure scheduled backup (daily 03:30)" \
  "Step 13  配置定时备份（每日 03:30）" \
  app.sub2api.success.cron_backup \
  "Scheduled backup configured (daily 03:30, retaining %s days)." \
  "定时备份已配置（每日 03:30，保留 %s 天）。" \
  app.sub2api.error.cron_backup \
  "Scheduled backup config write failed: /etc/cron.d/sub2api-backup" \
  "定时备份配置写入失败：/etc/cron.d/sub2api-backup。" \
  app.sub2api.step.start_service \
  "Step 14  Start service" \
  "Step 14  启动服务" \
  app.sub2api.success.service_started \
  "Service started successfully." \
  "服务启动成功。" \
  app.sub2api.warn.service_failed_rollback \
  "Service failed; rolling back installed files..." \
  "服务已 failed，正在回滚已安装文件..." \
  app.sub2api.warn.cleanup_stop_failed \
  "Could not stop %s during install rollback. It may already be stopped; otherwise inspect systemctl status %s." \
  "安装回滚时无法停止 %s。它可能已经停止；否则请检查：systemctl status %s。" \
  app.sub2api.warn.cleanup_disable_failed \
  "Could not disable %s during install rollback. Run manually after fixing systemd: systemctl disable %s" \
  "安装回滚时无法禁用 %s。请在修复 systemd 问题后手动执行：systemctl disable %s。" \
  app.sub2api.warn.cleanup_reload_failed \
  "Could not reload systemd during install rollback. Run manually: systemctl daemon-reload" \
  "安装回滚时无法重新加载 systemd。请手动执行：systemctl daemon-reload。" \
  app.sub2api.error.install_failed_rollback \
  "Installation failed because the service entered failed state. The binary and systemd unit were rolled back.\n  Debug: journalctl -u %s -n 30 --no-pager" \
  "安装失败：服务进入 failed 状态，已回滚二进制与 systemd unit。\n  调试：journalctl -u %s -n 30 --no-pager" \
  app.sub2api.warn.waiting_deps \
  "The service may be waiting for database/Redis connectivity; continuing the install flow." \
  "服务可能正在等待数据库/Redis 连接（属正常情况），继续安装流程。" \
  app.sub2api.warn.setup_status_later \
  "Verify service status again after completing the Setup Wizard." \
  "请在 Setup Wizard 完成配置后再验证服务状态。" \
  app.sub2api.step.health_save \
  "Step 15  Health check and save config" \
  "Step 15  健康检查 & 保存配置" \
  app.sub2api.error.binary_missing_install \
  "Sub2API binary is not installed (%s). Run install first." \
  "未检测到已安装的 Sub2API 二进制（%s），请先执行 install。" \
  app.sub2api.step.check_update \
  "Check for updates" \
  "检查更新" \
  app.sub2api.error.latest_lookup \
  "Failed to get the latest version. Check network connectivity and retry." \
  "获取最新版本失败，请检查网络后重试。" \
  app.sub2api.info.current_version \
  "Current version (recorded): %s" \
  "当前版本（记录）：%s" \
  app.sub2api.info.github_latest \
  "Latest GitHub version: %s" \
  "GitHub 最新版本：%s" \
  app.sub2api.success.already_latest \
  "Already on the latest version (%s); no update needed." \
  "已是最新版本（%s），无需更新。" \
  app.sub2api.warn.update_failed_state \
  "The service was already failed before update; this update will also reset the failed marker." \
  "更新前服务处于 failed 状态，本次更新将同时重置故障标记。" \
  app.sub2api.step.pre_update_backup \
  "Back up data before update" \
  "更新前备份数据" \
  app.sub2api.warn.pre_update_backup \
  "Pre-update backup failed; continuing the update. Inspect /opt/sub2api-backups/backup.log or run /usr/local/bin/sub2api-backup manually before proceeding further." \
  "更新前备份失败，继续执行更新。请检查 /opt/sub2api-backups/backup.log，或先手动执行 /usr/local/bin/sub2api-backup 再继续后续操作。" \
  app.sub2api.warn.backup_dir_unwritable \
  "Backup directory could not be created (%s); backup outputs were skipped." \
  "无法创建备份目录（%s），已跳过备份输出。" \
  app.sub2api.step.download_update \
  "Download new version (%s -> %s)" \
  "下载新版本（%s → %s）" \
  app.sub2api.error.update_download \
  "Download failed; update aborted and the current version is unchanged." \
  "下载失败，更新中止（当前版本未受影响）。" \
  app.sub2api.warn.tmp_binary_cleanup_failed \
  "Failed to remove temporary binary %s. Remove it manually after this command finishes." \
  "删除临时二进制 %s 失败。请在本次命令结束后手动清理。" \
  app.sub2api.step.replace_restart \
  "Replace binary and restart service" \
  "替换二进制并重启服务" \
  app.sub2api.info.stopping_service \
  "Stopping service..." \
  "停止服务..." \
  app.sub2api.error.stop_service_failed \
  "Could not stop %s before replacing the binary. Update aborted and the current binary was left unchanged. Inspect: systemctl status %s" \
  "替换二进制前无法停止 %s。更新已中止，当前二进制未变更。请检查：systemctl status %s。" \
  app.sub2api.info.old_binary_backup \
  "Old binary backed up: %s" \
  "旧二进制已备份：%s" \
  app.sub2api.success.new_version_started \
  "Service started successfully with the new version." \
  "服务以新版本启动成功。" \
  app.sub2api.info.cleaned_old_binaries \
  "Removed %s old binary backups (keeping the latest 3)." \
  "已清理 %s 个过期旧二进制备份（保留最近 3 个）。" \
  app.sub2api.warn.cleanup_old_binary_failed \
  "Could not remove old binary backup: %s" \
  "旧二进制备份删除失败：%s" \
  app.sub2api.success.update_done \
  "Update complete: %s -> %s" \
  "更新完成：%s → %s" \
  app.sub2api.warn.new_version_failed \
  "New version (%s) failed to start; automatically rolling back to %s..." \
  "新版本（%s）启动失败，正在自动回滚到 %s..." \
  app.sub2api.error.rollback_stop_failed \
  "New version failed to start, but %s could not be stopped. Rollback was aborted before restoring files; old binary backup is kept at %s. Inspect: systemctl status %s" \
  "新版本启动失败，但无法停止 %s。回滚已在恢复文件前中止；旧二进制备份保留在 %s。请检查：systemctl status %s。" \
  app.sub2api.success.rollback \
  "Rolled back to the previous version (%s); service recovered." \
  "已成功回滚到旧版本（%s），服务已恢复。" \
  app.sub2api.warn.rollback_start_failed \
  "Service still did not start after rollback. Inspect: journalctl -u %s -n 30 --no-pager" \
  "回滚后服务仍未正常启动，请手动检查：journalctl -u %s -n 30 --no-pager" \
  app.sub2api.error.update_failed \
  "Update failed and was rolled back to %s.\n  Diagnostics: journalctl -u %s -n 50 --no-pager" \
  "更新失败，已自动回滚至 %s。\n  诊断：journalctl -u %s -n 50 --no-pager" \
  app.sub2api.step.manual_backup \
  "Manual Sub2API data backup" \
  "手动备份 Sub2API 数据" \
  app.sub2api.info.pg_dump \
  "Running pg_dump..." \
  "执行 pg_dump..." \
  app.sub2api.success.db_backup \
  "Database backup: %s (%s)." \
  "数据库备份：%s（%s）。" \
  app.sub2api.warn.pg_dump_check_dsn \
  "pg_dump failed. Check PG_DSN and continuing with config files." \
  "pg_dump 失败（请检查 PG_DSN 是否正确），继续备份配置文件。" \
  app.sub2api.warn.pg_dump_missing \
  "pg_dump command is missing; skipping database backup." \
  "pg_dump 命令不存在，跳过数据库备份。" \
  app.sub2api.warn.pg_dsn_missing \
  "PG_DSN is not configured; skipping database backup." \
  "PG_DSN 未配置，跳过数据库备份。" \
  app.sub2api.warn.config_missing \
  "Config directory does not exist (%s); skipping." \
  "配置目录不存在（%s），跳过。" \
  app.sub2api.warn.data_missing \
  "Data directory does not exist (%s); skipping data archive creation." \
  "数据目录不存在（%s），跳过数据归档创建。" \
  app.sub2api.success.data_backup \
  "Data directory backup: %s (%s)." \
  "数据目录备份：%s（%s）。" \
  app.sub2api.warn.data_backup_failed \
  "Data directory backup failed. Inspect the tar output above; partial archives may still exist in the backup directory." \
  "数据目录备份失败。请检查上方 tar 输出；备份目录中可能仍保留了部分归档。" \
  app.sub2api.info.cleaned_old_backups \
  "Removed %s old backup archives older than %s days." \
  "已清理 %s 个超过 %s 天的旧备份归档。" \
  app.sub2api.warn.backup_cleanup_failed \
  "Could not remove old backup archive: %s" \
  "旧备份归档删除失败：%s" \
  app.sub2api.success.backup_done \
  "Backup flow complete. Archive directory: %s" \
  "备份流程完成，归档目录：%s。" \
  app.sub2api.error.backup_dir_create \
  "Backup directory could not be created: %s. Check permissions or disk state before retrying." \
  "无法创建备份目录：%s。请检查权限或磁盘状态后重试。" \
  app.sub2api.warn.non_root_status \
  "Running without root; some status details may be incomplete. Recommended: sudo bash %s status" \
  "以非 root 运行，部分状态信息可能不完整（建议：sudo bash %s status）。" \
  app.sub2api.step.status \
  "Sub2API runtime status" \
  "Sub2API 运行状态" \
  app.sub2api.status.systemd \
  "systemd service" \
  "systemd 服务" \
  app.sub2api.status.service_running \
  "Service status: running" \
  "服务状态：running" \
  app.sub2api.status.service_failed \
  "Service status: failed" \
  "服务状态：failed" \
  app.sub2api.status.service_inactive \
  "Service status: inactive / unknown" \
  "服务状态：inactive / unknown" \
  app.sub2api.status.pid \
  "PID" \
  "PID" \
  app.sub2api.status.memory \
  "Memory (RSS)" \
  "内存（RSS）" \
  app.sub2api.status.cpu \
  "CPU usage" \
  "CPU 占用" \
  app.sub2api.status.uptime \
  "Uptime" \
  "运行时长" \
  app.sub2api.status.version_info \
  "Version info" \
  "版本信息" \
  app.sub2api.status.installed_version \
  "Installed version (recorded)" \
  "已安装版本（记录）" \
  app.sub2api.status.unknown \
  "unknown" \
  "未知" \
  app.sub2api.status.binary_no_version \
  "(binary does not support --version)" \
  "（二进制不支持 --version）" \
  app.sub2api.status.binary_version \
  "Binary version output" \
  "二进制版本输出" \
  app.sub2api.status.nginx \
  "Nginx status" \
  "Nginx 状态" \
  app.sub2api.status.nginx_running \
  "nginx service is running" \
  "nginx 服务运行中" \
  app.sub2api.status.nginx_stopped \
  "nginx service is not running (systemctl start nginx)" \
  "nginx 服务未运行（systemctl start nginx）" \
  app.sub2api.status.nginx_config_exists \
  "Reverse proxy config exists: %s" \
  "反代配置存在：%s" \
  app.sub2api.status.proxy_target \
  "Proxy target: %s" \
  "代理目标：%s" \
  app.sub2api.status.server_name \
  "server_name: %s" \
  "server_name：%s" \
  app.sub2api.status.nginx_config_missing \
  "Reverse proxy config was not found (%s)." \
  "未找到反代配置（%s）。" \
  app.sub2api.status.nginx_link_active \
  "sites-enabled symlink is active" \
  "sites-enabled 软链接已激活" \
  app.sub2api.status.nginx_link_missing \
  "sites-enabled symlink is missing (ln -s %s %s)" \
  "sites-enabled 软链接不存在（ln -s %s %s）" \
  app.sub2api.status.nginx_test_ok \
  "nginx -t syntax check passed" \
  "nginx -t 语法校验通过" \
  app.sub2api.status.nginx_test_failed \
  "nginx -t syntax check failed; check the config." \
  "nginx -t 语法校验失败（请检查配置）。" \
  app.sub2api.status.nginx_missing \
  "nginx is not installed" \
  "nginx 未安装" \
  app.sub2api.status.dependencies \
  "Dependency connectivity" \
  "依赖服务连通性" \
  app.sub2api.status.port_reachable \
  "%s (:%s) is reachable" \
  "%s（:%s）可达" \
  app.sub2api.status.port_unreachable \
  "%s (:%s) is unreachable" \
  "%s（:%s）不可达" \
  app.sub2api.status.pg_dsn_masked \
  "PG_DSN (masked): %s" \
  "PG_DSN（脱敏）：%s" \
  app.sub2api.status.pg_dsn_missing \
  "PG_DSN is not configured; pg_dump backup is unavailable." \
  "PG_DSN 未配置，pg_dump 备份不可用。" \
  app.sub2api.status.directories \
  "Directory info" \
  "目录信息" \
  app.sub2api.status.dir_missing \
  "%s (missing)" \
  "%s（不存在）" \
  app.sub2api.status.backup_info \
  "Backup info" \
  "备份信息" \
  app.sub2api.status.backup_dir \
  "Backup directory: %s (%s, %s files)" \
  "备份目录：%s（%s，共 %s 个文件）" \
  app.sub2api.status.no_backup_files \
  "No backup files yet" \
  "暂无备份文件" \
  app.sub2api.status.backup_missing \
  "Backup directory does not exist: %s" \
  "备份目录不存在：%s" \
  app.sub2api.status.disk \
  "Disk space" \
  "磁盘空间" \
  app.sub2api.status.disk_usage \
  "Mount: %-15s  Used: %s / %s (%s used)" \
  "挂载点: %-15s  已用: %s / %s（%s 已用）" \
  app.sub2api.status.http_health \
  "HTTP health check (local 127.0.0.1:%s)" \
  "HTTP 健康检查（本地 127.0.0.1:%s）" \
  app.sub2api.status.local_ok \
  "Local endpoint responded normally: HTTP %s" \
  "本地接口响应正常：HTTP %s" \
  app.sub2api.status.local_warn \
  "Local endpoint response: HTTP %s (service not running / waiting for DB?)" \
  "本地接口响应：HTTP %s（服务未运行 / 等待 DB 连接？）" \
  app.sub2api.status.firewall \
  "Firewall rules (port %s)" \
  "防火墙规则（端口 %s）" \
  app.sub2api.status.ufw_allowed \
  "ufw allows port %s" \
  "ufw 端口 %s 已放行" \
  app.sub2api.status.ufw_missing \
  "ufw port %s is not in the rules" \
  "ufw 端口 %s 未在规则中" \
  app.sub2api.status.iptables_allowed \
  "iptables allows port %s" \
  "iptables 端口 %s 已放行" \
  app.sub2api.status.iptables_missing \
  "iptables port %s is not allowed" \
  "iptables 端口 %s 未放行" \
  app.sub2api.status.no_firewall \
  "No firewall detected; this may rely on a cloud security group." \
  "未检测到防火墙（可能依赖云安全组）。" \
  app.sub2api.error.install_dir_empty \
  "INSTALL_DIR is not set; uninstall aborted (config file: %s)." \
  "INSTALL_DIR 未设置，卸载中止（配置文件：%s）。" \
  app.sub2api.error.data_dir_empty \
  "DATA_DIR is not set; uninstall aborted." \
  "DATA_DIR 未设置，卸载中止。" \
  app.sub2api.error.backup_dir_empty \
  "BACKUP_DIR is not set; uninstall aborted." \
  "BACKUP_DIR 未设置，卸载中止。" \
  app.sub2api.error.install_dir_root \
  "INSTALL_DIR is root (/); refusing uninstall." \
  "INSTALL_DIR 为根目录（/），拒绝执行卸载。" \
  app.sub2api.error.data_dir_root \
  "DATA_DIR is root (/); refusing uninstall." \
  "DATA_DIR 为根目录（/），拒绝执行卸载。" \
  app.sub2api.error.backup_dir_root \
  "BACKUP_DIR is root (/); refusing uninstall." \
  "BACKUP_DIR 为根目录（/），拒绝执行卸载。" \
  app.sub2api.step.uninstall \
  "Uninstall Sub2API" \
  "卸载 Sub2API" \
  app.sub2api.uninstall.removes \
  "This will remove:" \
  "此操作将删除：" \
  app.sub2api.uninstall.binary \
  "Sub2API binary and old backups (%s/sub2api*)" \
  "Sub2API 二进制及旧版备份（%s/sub2api*）" \
  app.sub2api.uninstall.systemd \
  "systemd service unit (/etc/systemd/system/%s.service)" \
  "systemd 服务单元（/etc/systemd/system/%s.service）" \
  app.sub2api.uninstall.nginx_config \
  "Nginx reverse proxy config (/etc/nginx/sites-available/sub2api)" \
  "Nginx 反代配置（/etc/nginx/sites-available/sub2api）" \
  app.sub2api.uninstall.nginx_link \
  "Nginx sites-enabled symlink (/etc/nginx/sites-enabled/sub2api)" \
  "Nginx sites-enabled 软链接（/etc/nginx/sites-enabled/sub2api）" \
  app.sub2api.uninstall.logrotate \
  "logrotate config (/etc/logrotate.d/sub2api)" \
  "日志轮转配置（/etc/logrotate.d/sub2api）" \
  app.sub2api.uninstall.cron \
  "scheduled backup job (/etc/cron.d/sub2api-backup)" \
  "定时备份任务（/etc/cron.d/sub2api-backup）" \
  app.sub2api.uninstall.backup_script \
  "backup script (/usr/local/bin/sub2api-backup)" \
  "备份脚本（/usr/local/bin/sub2api-backup）" \
  app.sub2api.uninstall.deploy_config \
  "deployment config (%s)" \
  "部署配置文件（%s）" \
  app.sub2api.uninstall.keep_database \
  "The PostgreSQL database will not be deleted; clean it manually if needed." \
  "PostgreSQL 数据库不会被删除（需手动清理）。" \
  app.sub2api.uninstall.keep_dirs \
  "Data directory (%s) and config directory (%s) are kept by default; you can choose deletion." \
  "数据目录（%s）和配置目录（%s）默认保留，可选是否删除。" \
  app.sub2api.prompt.continue \
  "Continue uninstall? Type YES to confirm:" \
  "确认继续卸载？（输入 YES 确认）：" \
  app.sub2api.info.cancelled \
  "Uninstall cancelled." \
  "已取消卸载。" \
  app.sub2api.prompt.delete_data \
  "Delete local data directory too (%s)? [y/N]:" \
  "是否同时删除本地数据目录（%s）？[y/N]：" \
  app.sub2api.prompt.delete_config \
  "Delete config directory too (%s)? [y/N]:" \
  "是否同时删除配置目录（%s）？[y/N]：" \
  app.sub2api.prompt.delete_backup \
  "Delete backup directory too (%s)? [y/N]:" \
  "是否同时删除备份目录（%s）？[y/N]：" \
  app.sub2api.info.stop_disable \
  "Stopping and disabling %s service..." \
  "停止并禁用 %s 服务..." \
  app.sub2api.error.uninstall_stop_failed \
  "Could not stop %s during uninstall, and it still appears active. Uninstall aborted before deleting files. Inspect: systemctl status %s" \
  "卸载时无法停止 %s，且该服务仍处于 active 状态。已在删除文件前中止卸载。请检查：systemctl status %s。" \
  app.sub2api.warn.uninstall_stop_failed \
  "Could not stop %s during uninstall, but it is not active; continuing cleanup. Inspect systemd if this is unexpected: systemctl status %s" \
  "卸载时无法停止 %s，但该服务当前不是 active，继续清理。如不符合预期，请检查：systemctl status %s。" \
  app.sub2api.warn.uninstall_disable_failed \
  "Could not disable %s during uninstall. Remove the enablement manually after fixing systemd: systemctl disable %s" \
  "卸载时无法禁用 %s。请在修复 systemd 后手动移除开机自启：systemctl disable %s。" \
  app.sub2api.error.remove_dir \
  "Directory removal failed: %s" \
  "目录删除失败：%s。" \
  app.sub2api.error.remove_file \
  "File removal failed: %s" \
  "文件删除失败：%s。" \
  app.sub2api.success.removed_systemd \
  "systemd service removed." \
  "systemd 服务已移除。" \
  app.sub2api.success.removed_binary \
  "Binary and related files removed." \
  "二进制及相关文件已删除。" \
  app.sub2api.warn.uninstall_nginx_reload_failed \
  "Nginx config files were removed and validation passed, but reload failed. Inspect the error output and rerun manually: systemctl reload nginx" \
  "Nginx 配置文件已删除且校验已通过，但 reload 失败。请检查错误输出后手动重试：systemctl reload nginx。" \
  app.sub2api.warn.uninstall_nginx_test_failed \
  "Nginx config files were removed, but nginx -t failed. Check the config file and rerun manually: nginx -t && systemctl reload nginx" \
  "Nginx 配置文件已删除，但 nginx -t 失败。请检查配置文件后手动执行：nginx -t && systemctl reload nginx。" \
  app.sub2api.success.removed_nginx_reload \
  "Nginx reverse proxy config removed and service reloaded." \
  "Nginx 反代配置已清除，服务已重载。" \
  app.sub2api.success.removed_nginx \
  "Nginx reverse proxy config removed." \
  "Nginx 反代配置已清除。" \
  app.sub2api.success.removed_scheduled \
  "Scheduled job, backup script, and logrotate config removed." \
  "定时任务、备份脚本、日志轮转配置已清除。" \
  app.sub2api.success.removed_config \
  "Deployment config removed." \
  "部署配置文件已清除。" \
  app.sub2api.success.deleted_log \
  "Log directory deleted: %s" \
  "日志目录已删除：%s。" \
  app.sub2api.warn.log_path \
  "Log directory path is unusual (%s); skipped deletion." \
  "日志目录路径异常（%s），已跳过。" \
  app.sub2api.status.unset \
  "unset" \
  "未设置" \
  app.sub2api.success.deleted_data \
  "Local data directory deleted: %s" \
  "本地数据目录已删除：%s。" \
  app.sub2api.success.cleaned_install \
  "Install directory cleaned: %s" \
  "安装目录已清理：%s。" \
  app.sub2api.warn.cleanup_install_failed \
  "Install directory cleanup skipped because removal failed: %s" \
  "安装目录清理失败，已跳过：%s。" \
  app.sub2api.info.kept_data \
  "Local data directory kept: %s" \
  "本地数据目录已保留：%s。" \
  app.sub2api.success.deleted_config \
  "Config directory deleted: %s" \
  "配置目录已删除：%s。" \
  app.sub2api.info.kept_config \
  "Config directory kept: %s" \
  "配置目录已保留：%s。" \
  app.sub2api.success.deleted_backup \
  "Backup directory deleted: %s" \
  "备份目录已删除：%s。" \
  app.sub2api.info.kept_backup \
  "Backup directory kept: %s" \
  "备份目录已保留：%s。" \
  app.sub2api.success.deleted_user \
  "System user %s deleted." \
  "系统用户 %s 已删除。" \
  app.sub2api.warn.delete_user \
  "Failed to delete system user %s; it may be referenced by another service." \
  "系统用户 %s 删除失败，可能被其他服务引用。" \
  app.sub2api.success.uninstalled \
  "Sub2API fully uninstalled" \
  "Sub2API 已完全卸载" \
  app.sub2api.hint.database_kept \
  "PostgreSQL database data was not deleted." \
  "PostgreSQL 数据库数据未被删除。" \
  app.sub2api.hint.clean_database \
  "Manual database cleanup:" \
  "手动清理数据库："

APP_DESCRIPTION="$(t app.sub2api.description)"
APP_IMPL_SCRIPT="impl/install_sub2api.sh"

load_app_impl "$APP_IMPL_SCRIPT"
