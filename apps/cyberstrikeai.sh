#!/usr/bin/env bash

APP_ID="cyberstrikeai"
APP_NAME="CyberStrikeAI"
i18n_register_many \
  app.cyberstrikeai.description \
  "Source build deployment with Go, Python, systemd, Nginx, and backups." \
  "包含 Go、Python、systemd、Nginx 和备份的源码构建部署脚本。" \
  app.cyberstrikeai.error.apt_only \
  "Only Debian / Ubuntu is supported by this script." \
  "此脚本仅支持 Debian / Ubuntu。" \
  app.cyberstrikeai.error.systemd_required \
  "systemd is required by this script." \
  "此脚本需要 systemd。" \
  app.cyberstrikeai.error.arch \
  "Unsupported architecture: %s." \
  "不支持的架构：%s。" \
  app.cyberstrikeai.error.github_unreachable \
  "Cannot reach GitHub. Check network/proxy settings and retry." \
  "无法访问 GitHub，请检查网络或代理后重试。" \
  app.cyberstrikeai.step.install_deps \
  "Install system dependencies" \
  "安装系统依赖" \
  app.cyberstrikeai.success.deps \
  "Base dependencies installed" \
  "基础依赖安装完成" \
  app.cyberstrikeai.warn.go_old \
  "Go version is too old: %s" \
  "Go 版本过旧：%s" \
  app.cyberstrikeai.success.go_ready \
  "Go is ready: %s" \
  "Go 已就绪：%s" \
  app.cyberstrikeai.step.install_go \
  "Install Go" \
  "安装 Go" \
  app.cyberstrikeai.warn.go_repo_old \
  "Repository Go is still too old: %s. Installing official Go toolchain." \
  "软件源中的 Go 版本仍然过旧：%s。将安装官方 Go 工具链。" \
  app.cyberstrikeai.error.go_arch \
  "Unsupported architecture for Go install: %s" \
  "不支持为该架构安装 Go：%s" \
  app.cyberstrikeai.error.go_query \
  "Failed to query official Go releases" \
  "查询官方 Go 版本失败" \
  app.cyberstrikeai.error.go_parse \
  "Failed to parse latest Go version" \
  "解析最新 Go 版本失败" \
  app.cyberstrikeai.info.download \
  "Downloading %s" \
  "正在下载 %s" \
  app.cyberstrikeai.error.go_empty \
  "Downloaded Go archive is empty" \
  "下载的 Go 压缩包为空" \
  app.cyberstrikeai.error.go_extract \
  "Failed to extract the official Go archive." \
  "解压官方 Go 压缩包失败。" \
  app.cyberstrikeai.error.go_failed \
  "Go installation failed. Please install Go 1.21+ manually." \
  "Go 安装失败，请手动安装 Go 1.21 或更高版本。" \
  app.cyberstrikeai.warn.go_restore_failed \
  "Go installation failed and the previous Go toolchain could not be restored automatically. Please repair /usr/local/go manually." \
  "Go 安装失败，且旧 Go 工具链未能自动恢复。请手动修复 /usr/local/go。" \
  app.cyberstrikeai.success.go_installed \
  "Go installed: %s" \
  "Go 已安装：%s" \
  app.cyberstrikeai.success.user_created \
  "Created service user: %s" \
  "服务用户已创建：%s" \
  app.cyberstrikeai.step.fetch_source \
  "Fetch CyberStrikeAI source" \
  "获取 CyberStrikeAI 源码" \
  app.cyberstrikeai.info.repo_fetch \
  "Repository exists, fetching latest branch: %s" \
  "仓库已存在，正在获取最新分支：%s" \
  app.cyberstrikeai.error.nonempty_dir \
  "%s exists and is not an empty git checkout" \
  "%s 已存在且不是空的 Git 检出目录" \
  app.cyberstrikeai.success.source_ready \
  "Source ready: %s" \
  "源码已就绪：%s" \
  app.cyberstrikeai.error.config_missing \
  "Missing config.yaml at %s" \
  "缺少 config.yaml：%s" \
  app.cyberstrikeai.error.backup_write \
  "Failed to write backup file: %s" \
  "备份文件写入失败：%s" \
  app.cyberstrikeai.success.config_adjusted \
  "Adjusted config.yaml: local host, port %s, log file" \
  "已调整 config.yaml：本地监听、端口 %s、日志文件" \
  app.cyberstrikeai.step.python_env \
  "Prepare Python environment" \
  "准备 Python 环境" \
  app.cyberstrikeai.success.python_requirements \
  "Python requirements installed" \
  "Python 依赖安装完成" \
  app.cyberstrikeai.warn.pip_upgrade \
  "Failed to upgrade pip inside the virtual environment; continuing with the existing pip version" \
  "虚拟环境中的 pip 升级失败；将继续使用当前 pip 版本" \
  app.cyberstrikeai.warn.python_requirements \
  "Some Python requirements failed to install; continuing because several tools are optional" \
  "部分 Python 依赖安装失败；由于若干工具为可选项，将继续执行" \
  app.cyberstrikeai.warn.requirements_missing \
  "requirements.txt not found; skipping Python dependency install" \
  "未找到 requirements.txt，跳过 Python 依赖安装" \
  app.cyberstrikeai.step.build \
  "Build Go binary" \
  "构建 Go 二进制" \
  app.cyberstrikeai.error.binary_empty \
  "Built binary is empty" \
  "构建出的二进制为空" \
  app.cyberstrikeai.error.binary_build \
  "Binary build failed" \
  "二进制构建失败" \
  app.cyberstrikeai.success.binary_built \
  "Built binary: %s" \
  "二进制已构建：%s" \
  app.cyberstrikeai.step.runtime_dirs \
  "Prepare runtime directories" \
  "准备运行目录" \
  app.cyberstrikeai.success.runtime_dirs \
  "Runtime directories prepared" \
  "运行目录已准备完成" \
  app.cyberstrikeai.step.systemd \
  "Install systemd service" \
  "安装 systemd 服务" \
  app.cyberstrikeai.error.systemd \
  "systemd unit write failed: %s" \
  "systemd 单元写入失败：%s" \
  app.cyberstrikeai.success.systemd \
  "systemd unit installed: %s" \
  "systemd 单元已安装：%s" \
  app.cyberstrikeai.warn.service_enable_failed \
  "Could not enable %s to start automatically on boot. Run manually after fixing systemd: systemctl enable %s" \
  "无法将 %s 设置为开机自启。请在修复 systemd 问题后手动执行：systemctl enable %s。" \
  app.cyberstrikeai.step.nginx \
  "Configure Nginx reverse proxy" \
  "配置 Nginx 反向代理" \
  app.cyberstrikeai.error.nginx \
  "Nginx config write failed: %s" \
  "Nginx 配置写入失败：%s" \
  app.cyberstrikeai.error.nginx_test \
  "Nginx configuration validation failed. Run: nginx -t" \
  "Nginx 配置校验失败。请执行：nginx -t" \
  app.cyberstrikeai.error.nginx_start \
  "Cannot start Nginx service. Inspect: journalctl -u nginx -n 30" \
  "无法启动 Nginx 服务，请检查：journalctl -u nginx -n 30" \
  app.cyberstrikeai.success.nginx \
  "Nginx reverse proxy installed" \
  "Nginx 反向代理已安装" \
  app.cyberstrikeai.step.firewall \
  "Configure firewall" \
  "配置防火墙" \
  app.cyberstrikeai.success.ufw \
  "ufw allows public port: %s/tcp" \
  "ufw 已放行公网端口：%s/tcp" \
  app.cyberstrikeai.success.ufw_backend \
  "ufw allows backend port: %s/tcp" \
  "ufw 已放行后端端口：%s/tcp" \
  app.cyberstrikeai.success.iptables \
  "iptables allows port: %s/tcp" \
  "iptables 已放行端口：%s/tcp" \
  app.cyberstrikeai.warn.firewall_config_failed \
  "Automatic firewall configuration failed for port %s/tcp. Open it manually or retry after fixing the firewall service." \
  "端口 %s/tcp 的防火墙自动配置失败。请在修复防火墙服务后重试，或手动放行该端口。" \
  app.cyberstrikeai.warn.no_firewall \
  "No active ufw/iptables detected. Cloud security groups may still need manual rules." \
  "未检测到活跃的 ufw/iptables。云安全组可能仍需手动配置规则。" \
  app.cyberstrikeai.error.logrotate \
  "Logrotate config write failed: %s" \
  "日志轮转配置写入失败：%s" \
  app.cyberstrikeai.error.cron \
  "Scheduled backup config write failed: %s" \
  "定时备份配置写入失败：%s" \
  app.cyberstrikeai.step.start \
  "Start CyberStrikeAI" \
  "启动 CyberStrikeAI" \
  app.cyberstrikeai.warn.port_in_use \
  "Port %s appears to be in use:" \
  "端口 %s 似乎已被占用：" \
  app.cyberstrikeai.success.running \
  "%s is running" \
  "%s 正在运行" \
  app.cyberstrikeai.error.start_failed \
  "%s failed to start" \
  "%s 启动失败" \
  app.cyberstrikeai.step.health \
  "Health check" \
  "健康检查" \
  app.cyberstrikeai.success.backend_health \
  "Backend health OK: %s HTTP %s" \
  "后端健康检查正常：%s HTTP %s" \
  app.cyberstrikeai.warn.backend_health \
  "Backend health returned HTTP %s" \
  "后端健康检查返回 HTTP %s" \
  app.cyberstrikeai.success.nginx_health \
  "Nginx health OK: %s HTTP %s" \
  "Nginx 健康检查正常：%s HTTP %s" \
  app.cyberstrikeai.warn.nginx_health \
  "Nginx health returned HTTP %s" \
  "Nginx 健康检查返回 HTTP %s" \
  app.cyberstrikeai.summary.title \
  "CyberStrikeAI deployment complete" \
  "CyberStrikeAI 部署完成" \
  app.cyberstrikeai.summary.service \
  "service" \
  "服务" \
  app.cyberstrikeai.summary.install_dir \
  "install dir" \
  "安装目录" \
  app.cyberstrikeai.summary.config \
  "config" \
  "配置" \
  app.cyberstrikeai.summary.logs \
  "logs" \
  "日志" \
  app.cyberstrikeai.summary.backups \
  "backups" \
  "备份" \
  app.cyberstrikeai.summary.backend \
  "backend" \
  "后端" \
  app.cyberstrikeai.summary.public \
  "public" \
  "公网访问" \
  app.cyberstrikeai.summary.commands \
  "Useful commands:" \
  "常用命令：" \
  app.cyberstrikeai.warn.configure_model \
  "Set your model API key/base_url/model in the Web Settings page or edit %s." \
  "请在 Web 设置页配置模型 API key/base_url/model，或编辑 %s。" \
  app.cyberstrikeai.warn.authorized_only \
  "Use this platform only for authorized security testing." \
  "请仅将此平台用于已授权的安全测试。" \
  app.cyberstrikeai.step.manual_backup \
  "Manual backup" \
  "手动备份" \
  app.cyberstrikeai.info.latest_backups \
  "Latest backups:" \
  "最近的备份：" \
  app.cyberstrikeai.backup.error.install_missing \
  "install dir missing: %s" \
  "安装目录不存在：%s" \
  app.cyberstrikeai.backup.warn.sqlite_integrity \
  "SQLite integrity warning for %s: %s" \
  "SQLite 完整性警告：%s：%s" \
  app.cyberstrikeai.backup.ok.created \
  "backup created: %s" \
  "备份已创建：%s" \
  app.cyberstrikeai.error.backup_script \
  "Backup script write failed: %s" \
  "备份脚本写入失败：%s" \
  app.cyberstrikeai.error.not_git \
  "%s is not a git checkout. Run install first." \
  "%s 不是 Git 检出目录。请先执行 install。" \
  app.cyberstrikeai.step.preupdate_backup \
  "Pre-update backup" \
  "更新前备份" \
  app.cyberstrikeai.warn.preupdate_backup \
  "Pre-update backup failed; continuing cautiously. Inspect /opt/cyberstrike-ai/logs/backup.log or run /usr/local/bin/cyberstrike-ai-backup manually before proceeding further." \
  "更新前备份失败；将谨慎继续。请检查 /opt/cyberstrike-ai/logs/backup.log，或先手动执行 /usr/local/bin/cyberstrike-ai-backup 再继续后续操作。" \
  app.cyberstrikeai.step.update_source \
  "Update source" \
  "更新源码" \
  app.cyberstrikeai.step.restart_updated \
  "Restart updated service" \
  "重启更新后的服务" \
  app.cyberstrikeai.success.update_complete \
  "Update complete: %s -> %s" \
  "更新完成：%s -> %s" \
  app.cyberstrikeai.warn.update_start_failed \
  "Updated version failed to start. Rolling back binary and config." \
  "更新后的版本启动失败。正在回滚二进制与配置。" \
  app.cyberstrikeai.error.update_rollback_ok \
  "Update failed and rollback succeeded. Inspect: journalctl -u %s -n 80 --no-pager" \
  "更新失败且已成功回滚。请检查：journalctl -u %s -n 80 --no-pager" \
  app.cyberstrikeai.error.update_rollback_failed \
  "Update failed and rollback also failed. Inspect: journalctl -u %s -n 120 --no-pager" \
  "更新失败且回滚也失败。请检查：journalctl -u %s -n 120 --no-pager" \
  app.cyberstrikeai.success.update_inactive \
  "Update complete while service was inactive: %s -> %s" \
  "服务未运行时更新完成：%s -> %s" \
  app.cyberstrikeai.step.service_status \
  "Service status" \
  "服务状态" \
  app.cyberstrikeai.step.version_paths \
  "Version and paths" \
  "版本与路径" \
  app.cyberstrikeai.step.resources \
  "Process resources" \
  "进程资源" \
  app.cyberstrikeai.status.git_revision \
  "git revision" \
  "Git 修订" \
  app.cyberstrikeai.status.git_branch \
  "git branch" \
  "Git 分支" \
  app.cyberstrikeai.status.binary \
  "binary" \
  "二进制" \
  app.cyberstrikeai.status.process \
  "process" \
  "进程" \
  app.cyberstrikeai.status.memory_rss \
  "memory RSS" \
  "内存 RSS" \
  app.cyberstrikeai.status.cpu \
  "CPU" \
  "CPU" \
  app.cyberstrikeai.status.uptime \
  "uptime" \
  "运行时长" \
  app.cyberstrikeai.status.nginx \
  "nginx" \
  "nginx" \
  app.cyberstrikeai.status.syntax \
  "syntax" \
  "语法" \
  app.cyberstrikeai.status.backup_dir \
  "backup dir" \
  "备份目录" \
  app.cyberstrikeai.status.files \
  "%s files" \
  "%s 个文件" \
  app.cyberstrikeai.status.not_installed \
  "not installed" \
  "未安装" \
  app.cyberstrikeai.step.backups \
  "Backups" \
  "备份" \
  app.cyberstrikeai.status.running \
  "running" \
  "运行中" \
  app.cyberstrikeai.status.failed \
  "failed" \
  "失败" \
  app.cyberstrikeai.status.inactive \
  "inactive / unknown" \
  "未运行 / 未知" \
  app.cyberstrikeai.status.not_running \
  "not running" \
  "未运行" \
  app.cyberstrikeai.status.missing \
  "missing" \
  "缺失" \
  app.cyberstrikeai.status.ok \
  "OK" \
  "正常" \
  app.cyberstrikeai.status.disabled \
  "disabled by config" \
  "已通过配置禁用" \
  app.cyberstrikeai.step.uninstall \
  "Uninstall CyberStrikeAI" \
  "卸载 CyberStrikeAI" \
  app.cyberstrikeai.uninstall.removes \
  "This will remove:" \
  "此操作将删除：" \
  app.cyberstrikeai.uninstall.systemd \
  "systemd service: %s" \
  "systemd 服务：%s" \
  app.cyberstrikeai.uninstall.nginx \
  "Nginx config: %s" \
  "Nginx 配置：%s" \
  app.cyberstrikeai.uninstall.logrotate_cron \
  "logrotate and cron backup config" \
  "logrotate 与 cron 备份配置" \
  app.cyberstrikeai.uninstall.deploy_config \
  "deploy config: %s" \
  "部署配置：%s" \
  app.cyberstrikeai.uninstall.keep_default \
  "Install dir and backup dir are kept by default unless you choose deletion." \
  "默认保留安装目录和备份目录，除非你选择删除。" \
  app.cyberstrikeai.prompt.continue \
  "Type YES to continue:" \
  "输入 YES 继续：" \
  app.cyberstrikeai.prompt.delete_install \
  "Delete install directory %s? [y/N]:" \
  "是否删除安装目录 %s？[y/N]：" \
  app.cyberstrikeai.prompt.delete_backup \
  "Delete backup directory %s? [y/N]:" \
  "是否删除备份目录 %s？[y/N]：" \
  app.cyberstrikeai.info.cancelled \
  "Cancelled" \
  "已取消" \
  app.cyberstrikeai.success.removed_systemd \
  "Removed systemd service" \
  "systemd 服务已移除" \
  app.cyberstrikeai.success.removed_nginx \
  "Removed Nginx config" \
  "Nginx 配置已移除" \
  app.cyberstrikeai.success.removed_configs \
  "Removed deploy configs" \
  "部署配置已移除" \
  app.cyberstrikeai.success.deleted_install \
  "Deleted install dir: %s" \
  "安装目录已删除：%s" \
  app.cyberstrikeai.info.kept_install \
  "Kept install dir: %s" \
  "已保留安装目录：%s" \
  app.cyberstrikeai.success.deleted_backup \
  "Deleted backup dir: %s" \
  "备份目录已删除：%s" \
  app.cyberstrikeai.info.kept_backup \
  "Kept backup dir: %s" \
  "已保留备份目录：%s" \
  app.cyberstrikeai.success.deleted_user \
  "Deleted user: %s" \
  "系统用户已删除：%s" \
  app.cyberstrikeai.warn.delete_user \
  "Could not delete user: %s" \
  "无法删除系统用户：%s" \
  app.cyberstrikeai.success.uninstalled \
  "CyberStrikeAI uninstalled" \
  "CyberStrikeAI 已卸载"

APP_DESCRIPTION="$(t app.cyberstrikeai.description)"
APP_IMPL_SCRIPT="impl/install_cyberstrikeai.sh"

load_app_impl "$APP_IMPL_SCRIPT"
