#!/usr/bin/env bash

APP_ID="newapi"
APP_NAME="New API"
i18n_register_many \
  app.newapi.description \
  "Binary deployment with systemd, backups, and operational checks." \
  "使用 systemd、备份和运维检查的二进制部署脚本。" \
  app.newapi.error.apt_only \
  "This script only supports Debian / Ubuntu because apt-get was not found." \
  "此脚本仅支持 Debian / Ubuntu（apt-get 未找到）。" \
  app.newapi.error.arch \
  "Unsupported architecture: %s. Supported: x86_64 / aarch64." \
  "不支持的架构：%s（支持 x86_64 / aarch64）。" \
  app.newapi.error.github_unreachable \
  "Cannot reach GitHub. Check network/proxy settings and retry." \
  "网络不通，无法访问 GitHub，请检查网络或代理后重试。" \
  app.newapi.warn.github_api \
  "Cannot reach GitHub API." \
  "无法访问 GitHub API。" \
  app.newapi.error.binary_empty \
  "Binary file is empty; the download likely failed." \
  "二进制文件为空，疑似下载失败。" \
  app.newapi.error.binary_too_small \
  "Binary file is too small (%s bytes); the download may be incomplete or the URL may have returned an error page such as 404 HTML." \
  "二进制文件过小（%s 字节），疑似下载不完整或 URL 返回了错误页（如 404 HTML）。" \
  app.newapi.error.binary_not_elf \
  "Binary file is not a valid ELF file (magic: %s).\n  Check the download URL or whether the network path intercepted/redirected the request." \
  "二进制文件不是有效的 ELF 格式（magic: %s）。\n  请检查下载 URL 或网络环境是否有拦截/302 跳转。" \
  app.newapi.success.binary_verified \
  "Binary verification passed (ELF, %s MB)." \
  "二进制校验通过（ELF，%s MB）。" \
  app.newapi.success.http_health \
  "HTTP health check passed (status %s)." \
  "HTTP 健康检查通过（状态码 %s）。" \
  app.newapi.warn.http_health \
  "Health check returned %s. The service may still be initializing; run status again later." \
  "健康检查返回 %s，服务可能仍在初始化（属正常现象，稍后可用 status 再次确认）。" \
  app.newapi.warn.debug_command \
  "Debug command: journalctl -u %s -n 30 --no-pager" \
  "调试命令：journalctl -u %s -n 30 --no-pager" \
  app.newapi.success.ufw_port \
  "ufw allows port %s." \
  "ufw 已放行端口 %s。" \
  app.newapi.warn.firewall_config_failed \
  "Automatic firewall configuration failed for port %s. Open it manually or retry after fixing the firewall service." \
  "端口 %s 的防火墙自动配置失败。请在修复防火墙服务后重试，或手动放行该端口。" \
  app.newapi.success.iptables_saved \
  "iptables rules persisted with netfilter-persistent." \
  "iptables 规则已持久化（netfilter-persistent）。" \
  app.newapi.info.iptables_rules_written \
  "iptables rules written to /etc/iptables/rules.v4." \
  "iptables 规则已写入 /etc/iptables/rules.v4。" \
  app.newapi.warn.iptables_write_failed \
  "Failed to write iptables rules; rules may be lost after reboot." \
  "iptables 规则写入失败，重启后规则可能丢失。" \
  app.newapi.warn.iptables_not_persisted \
  "iptables rules are not persisted and may be lost after reboot. Recommended: apt-get install -y iptables-persistent && netfilter-persistent save" \
  "iptables 规则未持久化（重启后失效）。建议：apt-get install -y iptables-persistent && netfilter-persistent save。" \
  app.newapi.success.iptables_port \
  "iptables allows port %s." \
  "iptables 已放行端口 %s。" \
  app.newapi.warn.no_firewall \
  "No active firewall detected. If you use a cloud security group, allow port %s manually." \
  "未检测到活跃防火墙，如有云安全组（如 AWS/阿里云/腾讯云）请手动放行端口 %s。" \
  app.newapi.success.logrotate \
  "Log rotation configured (daily rotation, 14 days retained, compressed automatically)." \
  "日志轮转已配置（每日轮转，保留 14 天，自动压缩）。" \
  app.newapi.error.logrotate \
  "Logrotate config write failed: /etc/logrotate.d/new-api" \
  "日志轮转配置写入失败：/etc/logrotate.d/new-api。" \
  app.newapi.backup.log.start \
  "Backup started" \
  "开始备份" \
  app.newapi.backup.log.data_missing \
  "[ERROR] Data directory does not exist (%s); backup aborted." \
  "[ERROR] 数据目录不存在（%s），备份中止。" \
  app.newapi.backup.log.wal_ok \
  "[OK] SQLite WAL checkpoint(TRUNCATE) completed." \
  "[OK] SQLite WAL checkpoint(TRUNCATE) 成功。" \
  app.newapi.backup.log.wal_warn \
  "[WARN] SQLite WAL flush failed; backup continues and some database data may not be flushed." \
  "[WARN] SQLite WAL flush 失败，备份继续（数据库可能有未落盘数据）。" \
  app.newapi.backup.log.integrity_warn \
  "[WARN] SQLite integrity_check returned %s; backup continues but the database may be corrupted." \
  "[WARN] SQLite integrity_check 返回：%s，备份继续但数据库可能已损坏。" \
  app.newapi.backup.log.ok \
  "[OK] Backup created: %s (%s)." \
  "[OK] 备份成功：%s（%s）。" \
  app.newapi.backup.log.tar_failed \
  "[ERROR] tar failed; temporary archive removed." \
  "[ERROR] tar 失败，临时文件已清理。" \
  app.newapi.backup.log.removed_old \
  "[OK] Removed %s old backups older than %s days." \
  "[OK] 已清理 %s 个超过 %s 天的旧备份。" \
  app.newapi.backup.log.done \
  "Backup finished" \
  "备份完成" \
  app.newapi.success.backup_script \
  "Backup script written: /usr/local/bin/new-api-backup" \
  "备份脚本已写入：/usr/local/bin/new-api-backup。" \
  app.newapi.error.backup_script \
  "Backup script write failed: /usr/local/bin/new-api-backup" \
  "备份脚本写入失败：/usr/local/bin/new-api-backup。" \
  app.newapi.warn.silent_data_missing \
  "_backup_silent: data directory does not exist (%s); skipping backup." \
  "_backup_silent: 数据目录不存在（%s），跳过备份。" \
  app.newapi.warn.sqlite_integrity \
  "SQLite integrity_check warning (%s); backup continues." \
  "SQLite integrity_check 警告（%s），备份继续。" \
  app.newapi.success.silent_backup \
  "Silent backup created: %s (%s)." \
  "静默备份已创建：%s（%s）。" \
  app.newapi.warn.silent_backup_failed \
  "Silent backup failed (tar error); continuing..." \
  "静默备份失败（tar 报错），继续执行..." \
  app.newapi.summary.title \
  "New API deployment complete" \
  "New API 部署完成！" \
  app.newapi.summary.public \
  "Public URL" \
  "公网访问" \
  app.newapi.summary.internal \
  "Internal URL" \
  "内网直连" \
  app.newapi.summary.default_user \
  "Default user" \
  "默认账号" \
  app.newapi.summary.default_password \
  "Default password" \
  "默认密码" \
  app.newapi.summary.change_password \
  "change it immediately after login" \
  "请登录后立即修改" \
  app.newapi.summary.api_url \
  "API URL" \
  "API 地址" \
  app.newapi.summary.version \
  "Version" \
  "版本" \
  app.newapi.summary.data_dir \
  "Data dir" \
  "数据目录" \
  app.newapi.summary.log_dir \
  "Log dir" \
  "日志目录" \
  app.newapi.summary.backup_dir \
  "Backup dir" \
  "备份目录" \
  app.newapi.summary.management \
  "Management commands:" \
  "管理命令：" \
  app.newapi.summary.status_cmd \
  "show runtime status" \
  "查看运行状态" \
  app.newapi.summary.update_cmd \
  "update to the latest version" \
  "更新到最新版" \
  app.newapi.summary.backup_cmd \
  "back up data now" \
  "立即备份数据" \
  app.newapi.summary.uninstall_cmd \
  "uninstall the service" \
  "卸载服务" \
  app.newapi.summary.systemd \
  "systemd commands:" \
  "systemd 命令：" \
  app.newapi.summary.show_status \
  "show status" \
  "查看状态" \
  app.newapi.summary.live_logs \
  "follow logs" \
  "实时日志" \
  app.newapi.summary.restart \
  "restart service" \
  "重启服务" \
  app.newapi.summary.cf_ssl \
  "[Cloudflare] Set SSL/TLS mode to Flexible." \
  "[CF 提醒] SSL/TLS 模式请设为「灵活」。" \
  app.newapi.summary.cf_sse \
  "[Cloudflare] If streaming responses (SSE) stall, disable buffering/cache for this domain in Cloudflare rules." \
  "[CF 提醒] 如遇流式响应（SSE）卡顿，在 CF 规则中关闭该域名的缓冲/缓存。" \
  app.newapi.step.latest \
  "Step 1  Get latest version" \
  "Step 1  获取最新版本" \
  app.newapi.info.query_latest \
  "Querying latest GitHub release..." \
  "查询 GitHub 最新 Release..." \
  app.newapi.error.version_failed \
  "Failed to get version. Check the network and retry." \
  "获取版本号失败，请检查网络后重试。" \
  app.newapi.success.latest \
  "Latest version: %s" \
  "最新版本：%s" \
  app.newapi.error.apt_update \
  "apt-get update failed. Check /var/log/apt/*, fix repository or network issues, and retry the installation." \
  "apt-get update 失败。请检查 /var/log/apt/*，修复软件源或网络问题后重新执行安装。" \
  app.newapi.error.deps_install \
  "Dependency installation failed. Run apt-get install -y curl ca-certificates sqlite3 after fixing the package manager state." \
  "依赖安装失败。请在修复软件包管理器状态后执行 apt-get install -y curl ca-certificates sqlite3。" \
  app.newapi.step.deps \
  "Step 2  Install system dependencies" \
  "Step 2  安装系统依赖" \
  app.newapi.success.deps \
  "Dependencies installed (curl / ca-certificates / sqlite3)." \
  "依赖安装完成（curl / ca-certificates / sqlite3）。" \
  app.newapi.step.user_dirs \
  "Step 3  Create user and directories" \
  "Step 3  创建用户与目录" \
  app.newapi.success.user_created \
  "System user %s created (low privilege, no login shell)." \
  "系统用户 %s 已创建（低权限，无登录 shell）。" \
  app.newapi.info.user_exists \
  "User %s already exists; skipping creation." \
  "用户 %s 已存在，跳过创建。" \
  app.newapi.success.dirs \
  "Directories created: %s / %s / %s." \
  "目录创建完成：%s / %s / %s。" \
  app.newapi.step.download \
  "Step 4  Download New API binary (arch: %s)" \
  "Step 4  下载 New API 二进制（架构：%s）" \
  app.newapi.info.download_url \
  "Download URL: %s" \
  "下载地址：%s" \
  app.newapi.error.download \
  "Download failed. Check the network or confirm the release exists: https://github.com/%s/releases" \
  "下载失败，请检查网络或前往 https://github.com/%s/releases 确认版本存在。" \
  app.newapi.warn.old_binary_backup \
  "Backed up old binary -> %s" \
  "已备份旧二进制 → %s。" \
  app.newapi.error.binary_install \
  "Failed to install binary: %s" \
  "二进制安装失败：%s。" \
  app.newapi.success.binary_installed \
  "Binary installed: %s" \
  "二进制安装完成：%s。" \
  app.newapi.step.secret \
  "Step 5  Generate secure configuration" \
  "Step 5  生成安全配置" \
  app.newapi.success.secret \
  "SESSION_SECRET generated (40 mixed characters)." \
  "SESSION_SECRET 已随机生成（40 位混合字符）。" \
  app.newapi.step.systemd \
  "Step 6  Configure systemd service" \
  "Step 6  配置 systemd 服务" \
  app.newapi.error.systemd_unit \
  "systemd service file write failed: /etc/systemd/system/%s.service" \
  "systemd 服务文件写入失败：/etc/systemd/system/%s.service。" \
  app.newapi.success.systemd \
  "systemd service file written: /etc/systemd/system/%s.service" \
  "systemd 服务文件已写入：/etc/systemd/system/%s.service。" \
  app.newapi.warn.service_enable_failed \
  "Could not enable %s to start automatically on boot. Run manually after fixing systemd: systemctl enable %s" \
  "无法将 %s 设置为开机自启。请在修复 systemd 问题后手动执行：systemctl enable %s。" \
  app.newapi.step.firewall \
  "Step 7  Configure firewall" \
  "Step 7  配置防火墙" \
  app.newapi.step.logrotate \
  "Step 8  Configure log rotation" \
  "Step 8  配置日志轮转" \
  app.newapi.step.cron \
  "Step 9  Configure scheduled backup (daily 03:30)" \
  "Step 9  配置定时备份（每日 03:30）" \
  app.newapi.success.cron \
  "Scheduled backup configured (daily 03:30, keep %s days)." \
  "定时备份已配置（每日 03:30，保留 %s 天）。" \
  app.newapi.error.cron \
  "Scheduled backup config write failed: /etc/cron.d/new-api-backup" \
  "定时备份配置写入失败：/etc/cron.d/new-api-backup。" \
  app.newapi.step.start \
  "Step 10  Start service" \
  "Step 10  启动服务" \
  app.newapi.status.unknown_process \
  "unknown process" \
  "未知进程" \
  app.newapi.warn.port_used \
  "Port %s is already in use (%s)." \
  "端口 %s 已被占用（%s）。" \
  app.newapi.warn.port_release \
  "If this is not the old new-api process, release the port first or the service cannot bind." \
  "若不是旧的 new-api 进程，请先释放端口，否则服务将无法绑定。" \
  app.newapi.success.service_started \
  "Service started successfully." \
  "服务启动成功。" \
  app.newapi.warn.start_rollback \
  "Service did not start within 20 seconds; rolling back installed files..." \
  "服务在 20 秒内未能正常启动，正在回滚已安装文件..." \
  app.newapi.error.install_start_failed \
  "Install failed: service could not start, binary and systemd unit rolled back.\n  Debug command: journalctl -u %s -n 30 --no-pager\n  Data and log directories were kept; fix the issue and rerun install." \
  "安装失败：服务无法启动，已回滚二进制与 systemd unit。\n  调试命令：journalctl -u %s -n 30 --no-pager\n  （数据目录、日志目录已保留，修复原因后可重新执行 install）。" \
  app.newapi.step.health \
  "Step 11  Health check" \
  "Step 11  健康检查" \
  app.newapi.error.not_installed \
  "Installed New API binary was not found (%s). Run install first." \
  "未检测到已安装的 New API 二进制（%s），请先执行 install。" \
  app.newapi.step.check_update \
  "Check for updates" \
  "检查更新" \
  app.newapi.error.latest_failed \
  "Failed to get latest version. Check the network and retry." \
  "获取最新版本失败，请检查网络后重试。" \
  app.newapi.info.current \
  "Current version (recorded): %s" \
  "当前版本（记录）：%s" \
  app.newapi.info.github_latest \
  "Latest GitHub version: %s" \
  "GitHub 最新版本：%s" \
  app.newapi.success.already_latest \
  "Already on the latest version (%s); no update needed." \
  "已是最新版本（%s），无需更新。" \
  app.newapi.warn.pre_failed_state \
  "Service was failed before update; this update will also reset the failure marker." \
  "注意：更新前服务处于 failed 状态，本次更新将同时重置故障标记。" \
  app.newapi.warn.pre_failed_debug \
  "If problems remain after update, inspect the existing errors first: journalctl -u %s -n 50 --no-pager" \
  "如更新后仍有问题，请先检查已有错误：journalctl -u %s -n 50 --no-pager。" \
  app.newapi.step.pre_backup \
  "Back up data before update" \
  "更新前备份数据" \
  app.newapi.warn.pre_backup_failed \
  "Pre-update backup failed; continuing with update. Inspect /opt/new-api-backups/backup.log or run /usr/local/bin/new-api-backup manually before proceeding further." \
  "更新前备份失败，继续执行更新。请检查 /opt/new-api-backups/backup.log，或先手动执行 /usr/local/bin/new-api-backup 再继续后续操作。" \
  app.newapi.step.download_update \
  "Download new binary (%s -> %s)" \
  "下载新版本二进制（%s → %s）" \
  app.newapi.error.update_download \
  "Download failed; update aborted and the current version was not changed." \
  "下载失败，更新中止（当前版本未受影响）。" \
  app.newapi.step.replace_restart \
  "Replace binary and restart service" \
  "替换二进制并重启服务" \
  app.newapi.info.stop_service \
  "Stopping service..." \
  "停止服务..." \
  app.newapi.info.old_binary \
  "Old binary backed up: %s" \
  "旧二进制已备份：%s。" \
  app.newapi.success.updated_started \
  "Service started successfully with the new version." \
  "服务以新版本启动成功。" \
  app.newapi.info.cleaned_old \
  "Removed %s expired old binary backups (keeping latest 3)." \
  "已清理 %s 个过期旧二进制备份（保留最近 3 个）。" \
  app.newapi.success.update_done \
  "Update complete: %s -> %s" \
  "更新完成：%s → %s" \
  app.newapi.warn.update_start_failed \
  "New version (%s) failed to start; rolling back automatically to %s..." \
  "新版本（%s）启动失败，正在自动回滚到 %s..." \
  app.newapi.success.rollback \
  "Rollback to old version (%s) succeeded; service restored." \
  "已成功回滚到旧版本（%s），服务已恢复。" \
  app.newapi.warn.rollback_start_failed \
  "Service still did not start after rollback. Inspect: journalctl -u %s -n 30 --no-pager" \
  "回滚后服务仍未正常启动，请手动检查：journalctl -u %s -n 30 --no-pager。" \
  app.newapi.error.update_failed \
  "Update failed and rolled back to %s.\n  New version diagnostics: journalctl -u %s -n 50 --no-pager\n  The new binary is kept at %s (it is the pre-rollback new binary); rename it if you want to test it manually." \
  "更新失败，已自动回滚至 %s。\n  新版本诊断：journalctl -u %s -n 50 --no-pager\n  新版二进制已保留在：%s（实为回滚前的新版）如需手动测试可重命名使用。" \
  app.newapi.error.data_missing_install \
  "Data directory does not exist (%s). Run install first." \
  "数据目录不存在（%s），请先执行安装。" \
  app.newapi.step.manual_backup \
  "Manual New API data backup" \
  "手动备份 New API 数据" \
  app.newapi.success.wal \
  "SQLite WAL checkpoint completed." \
  "SQLite WAL checkpoint 成功。" \
  app.newapi.warn.wal \
  "SQLite WAL flush failed; backup continues and a small amount of data may not be flushed." \
  "SQLite WAL flush 失败，备份继续（可能有少量未落盘数据）。" \
  app.newapi.success.sqlite_integrity \
  "SQLite integrity check passed." \
  "SQLite 完整性校验通过。" \
  app.newapi.warn.sqlite_integrity_failed \
  "SQLite integrity check failed (%s); backup continues, but the database may be corrupted." \
  "SQLite 完整性校验失败（%s），备份继续，但数据库可能已损坏。" \
  app.newapi.info.backing_up \
  "Backing up: %s -> %s" \
  "备份中：%s → %s" \
  app.newapi.success.backup_done \
  "Backup complete: %s (%s)." \
  "备份完成：%s（%s）。" \
  app.newapi.error.backup_failed \
  "Backup failed. Check disk space on the disk containing %s." \
  "备份失败，请检查磁盘空间（%s 所在磁盘）。" \
  app.newapi.info.cleaned_backups \
  "Removed %s old backups older than %s days." \
  "已清理 %s 个超过 %s 天的旧备份。" \
  app.newapi.info.backup_list \
  "Backup list (%s, latest 10):" \
  "备份列表（%s，最近 10 个）：" \
  app.newapi.info.backup_total \
  "Total backups: %s." \
  "合计 %s 个备份。" \
  app.newapi.warn.no_backups \
  "No backup files yet." \
  "暂无备份文件。" \
  app.newapi.warn.non_root_status \
  "Running without root; some status details may be incomplete. Recommended: sudo bash %s status" \
  "以非 root 运行，部分状态信息可能不完整（建议：sudo bash %s status）。" \
  app.newapi.step.status \
  "New API system status" \
  "New API 系统状态" \
  app.newapi.status.systemd \
  "systemd service status" \
  "systemd 服务状态" \
  app.newapi.status.running \
  "running" \
  "运行中" \
  app.newapi.status.not_running \
  "not running" \
  "未运行" \
  app.newapi.status.version_info \
  "Version information" \
  "版本信息" \
  app.newapi.status.recorded_version \
  "Recorded version" \
  "记录版本" \
  app.newapi.status.binary_path \
  "Binary path" \
  "二进制路径" \
  app.newapi.status.binary_time \
  "Binary time" \
  "二进制时间" \
  app.newapi.status.binary_size \
  "Binary size" \
  "二进制大小" \
  app.newapi.status.unknown \
  "unknown" \
  "未知" \
  app.newapi.status.binary_missing \
  "Binary not found: %s" \
  "未找到二进制：%s" \
  app.newapi.status.resources \
  "Process resources" \
  "进程资源" \
  app.newapi.status.pid \
  "Process PID" \
  "进程 PID" \
  app.newapi.status.memory \
  "Memory" \
  "内存占用" \
  app.newapi.status.cpu \
  "CPU" \
  "CPU 使用" \
  app.newapi.status.start_time \
  "Start time" \
  "启动时间" \
  app.newapi.status.no_process \
  "Service is not running; no process information." \
  "服务未运行，无进程信息。" \
  app.newapi.status.directories \
  "Directory information" \
  "目录信息" \
  app.newapi.status.data_dir \
  "Data dir" \
  "数据目录" \
  app.newapi.status.database \
  "Database" \
  "数据库" \
  app.newapi.status.data_missing \
  "Data directory does not exist: %s" \
  "数据目录不存在：%s" \
  app.newapi.status.log_dir \
  "Log dir" \
  "日志目录" \
  app.newapi.status.backup_info \
  "Backup information" \
  "备份信息" \
  app.newapi.status.backup_dir \
  "Backup dir" \
  "备份目录" \
  app.newapi.status.backup_count \
  "%s files" \
  "共 %s 个" \
  app.newapi.status.backup_missing \
  "Backup directory does not exist: %s" \
  "备份目录不存在：%s" \
  app.newapi.status.disk \
  "Disk space" \
  "磁盘空间" \
  app.newapi.status.disk_usage \
  "mount: %-15s  used: %s / %s (%s used)" \
  "挂载点: %-15s  已用: %s / %s（%s 已用）" \
  app.newapi.status.health \
  "HTTP health check (local 127.0.0.1:%s)" \
  "HTTP 健康检查（本地 127.0.0.1:%s）" \
  app.newapi.status.local_ok \
  "Local endpoint responded normally: HTTP %s" \
  "本地接口响应正常：HTTP %s" \
  app.newapi.status.local_warn \
  "Local endpoint returned HTTP %s (service not running, wrong port, or still initializing?)." \
  "本地接口响应：HTTP %s（服务未运行、端口错误或仍在初始化？）。" \
  app.newapi.status.firewall \
  "Firewall rules (port %s)" \
  "防火墙规则（端口 %s）" \
  app.newapi.status.ufw_allowed \
  "ufw allows port %s." \
  "ufw 端口 %s 已放行。" \
  app.newapi.status.ufw_missing \
  "ufw does not include port %s (service may not be externally reachable)." \
  "ufw 端口 %s 未在规则中（服务可能无法从外部访问）。" \
  app.newapi.status.iptables_allowed \
  "iptables allows port %s." \
  "iptables 端口 %s 已放行。" \
  app.newapi.status.iptables_missing \
  "iptables does not allow port %s." \
  "iptables 端口 %s 未放行。" \
  app.newapi.status.no_firewall \
  "No firewall detected; cloud security groups may still apply." \
  "未检测到防火墙（可能依赖云安全组）。" \
  app.newapi.error.install_dir_empty \
  "INSTALL_DIR is not set; uninstall aborted (check config file: %s)." \
  "INSTALL_DIR 未设置，卸载中止（请确认配置文件 %s 存在）。" \
  app.newapi.error.data_dir_empty \
  "DATA_DIR is not set; uninstall aborted." \
  "DATA_DIR 未设置，卸载中止。" \
  app.newapi.error.backup_dir_empty \
  "BACKUP_DIR is not set; uninstall aborted." \
  "BACKUP_DIR 未设置，卸载中止。" \
  app.newapi.error.install_dir_root \
  "INSTALL_DIR is root (/); refusing uninstall." \
  "INSTALL_DIR 为根目录（/），拒绝执行卸载。" \
  app.newapi.error.data_dir_root \
  "DATA_DIR is root (/); refusing uninstall." \
  "DATA_DIR 为根目录（/），拒绝执行卸载。" \
  app.newapi.error.backup_dir_root \
  "BACKUP_DIR is root (/); refusing uninstall." \
  "BACKUP_DIR 为根目录（/），拒绝执行卸载。" \
  app.newapi.step.uninstall \
  "Uninstall New API" \
  "卸载 New API" \
  app.newapi.uninstall.removes \
  "This will remove:" \
  "此操作将删除：" \
  app.newapi.uninstall.binary \
  "New API binary and old binary backups (%s/new-api*)" \
  "New API 二进制及旧版备份（%s/new-api*）" \
  app.newapi.uninstall.systemd \
  "systemd service unit (/etc/systemd/system/%s.service)" \
  "systemd 服务单元（/etc/systemd/system/%s.service）" \
  app.newapi.uninstall.logrotate \
  "logrotate config (/etc/logrotate.d/new-api)" \
  "日志轮转配置（/etc/logrotate.d/new-api）" \
  app.newapi.uninstall.cron \
  "scheduled backup job (/etc/cron.d/new-api-backup)" \
  "定时备份任务（/etc/cron.d/new-api-backup）" \
  app.newapi.uninstall.backup_script \
  "backup script (/usr/local/bin/new-api-backup)" \
  "备份脚本（/usr/local/bin/new-api-backup）" \
  app.newapi.uninstall.deploy_config \
  "deployment config (%s)" \
  "部署配置文件（%s）" \
  app.newapi.uninstall.keep_data \
  "Data directory (%s) is kept by default; you can choose deletion." \
  "数据目录（%s）默认保留，可选是否删除。" \
  app.newapi.uninstall.keep_backup \
  "Backup directory (%s) is kept by default; you can choose deletion." \
  "备份目录（%s）默认保留，可选是否删除。" \
  app.newapi.prompt.continue \
  "Continue uninstall? Type YES to confirm:" \
  "确认继续卸载？（输入 YES 确认）：" \
  app.newapi.info.cancelled \
  "Uninstall cancelled." \
  "已取消卸载。" \
  app.newapi.prompt.delete_data \
  "Delete data directory too (%s)? [y/N]:" \
  "是否同时删除数据目录（%s）？[y/N]：" \
  app.newapi.prompt.delete_backup \
  "Delete backup directory too (%s)? [y/N]:" \
  "是否同时删除备份目录（%s）？[y/N]：" \
  app.newapi.info.stop_disable \
  "Stopping and disabling %s service..." \
  "停止并禁用 %s 服务..." \
  app.newapi.success.removed_systemd \
  "systemd service removed." \
  "systemd 服务已移除。" \
  app.newapi.success.removed_binary \
  "Binary and related files removed." \
  "二进制及相关文件已删除。" \
  app.newapi.success.removed_scheduled \
  "Scheduled job, backup script, and logrotate config removed." \
  "定时任务、备份脚本、日志轮转配置已清除。" \
  app.newapi.success.removed_config \
  "Deployment config removed." \
  "部署配置文件已清除。" \
  app.newapi.success.deleted_log \
  "Log directory deleted: %s" \
  "日志目录已删除：%s。" \
  app.newapi.warn.log_path \
  "Log directory path is unusual (%s); skipped deletion, clean it manually if needed." \
  "日志目录路径异常（%s），已跳过删除，请手动清理。" \
  app.newapi.success.deleted_data \
  "Data directory deleted: %s" \
  "数据目录已删除：%s。" \
  app.newapi.success.cleaned_install \
  "Install directory cleaned: %s" \
  "安装目录已清理：%s。" \
  app.newapi.info.kept_data \
  "Data directory kept: %s" \
  "数据目录已保留：%s。" \
  app.newapi.success.deleted_backup \
  "Backup directory deleted: %s" \
  "备份目录已删除：%s。" \
  app.newapi.info.kept_backup \
  "Backup directory kept: %s" \
  "备份目录已保留：%s。" \
  app.newapi.success.deleted_user \
  "System user %s deleted." \
  "系统用户 %s 已删除。" \
  app.newapi.warn.delete_user \
  "Failed to delete system user %s; it may be referenced by another service." \
  "系统用户 %s 删除失败，可能被其他服务引用。" \
  app.newapi.success.uninstalled \
  "New API fully uninstalled." \
  "New API 已完全卸载。" \
  app.newapi.hint.data_kept \
  "Data kept at: %s" \
  "数据保留在：%s。" \
  app.newapi.hint.remove_data \
  "When you are sure it is no longer needed, manually run: rm -rf %s" \
  "确认不再需要时，可手动执行：rm -rf %s。" \
  app.newapi.hint.backup_kept \
  "Backups kept at: %s" \
  "备份保留在：%s。"

APP_DESCRIPTION="$(t app.newapi.description)"
APP_IMPL_SCRIPT="impl/install_newapi.sh"

load_app_impl "$APP_IMPL_SCRIPT"
