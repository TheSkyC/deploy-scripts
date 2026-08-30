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
  app.cyberstrikeai.error.apt_update \
  "apt-get update failed. Check /var/log/apt/*, fix repository or network issues, and retry the installation." \
  "apt-get update 失败。请检查 /var/log/apt/*，修复软件源或网络问题后重新执行安装。" \
  app.cyberstrikeai.error.deps_install \
  "Base dependency installation failed. Run apt-get install -y ca-certificates curl git build-essential python3 python3-venv python3-pip sqlite3 tar gzip openssl lsof after fixing the package manager state." \
  "基础依赖安装失败。请在修复软件包管理器状态后执行 apt-get install -y ca-certificates curl git build-essential python3 python3-venv python3-pip sqlite3 tar gzip openssl lsof。" \
  app.cyberstrikeai.error.nginx_deps_install \
  "Nginx installation failed. Run apt-get install -y nginx after fixing the package manager state." \
  "Nginx 安装失败。请在修复软件包管理器状态后执行 apt-get install -y nginx。" \
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
  app.cyberstrikeai.warn.go_repo_install_failed \
  "Failed to install Go from the system repository. Falling back to the official Go toolchain." \
  "从系统软件源安装 Go 失败。将回退到官方 Go 工具链。" \
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
  app.cyberstrikeai.error.go_checksum_missing \
  "Official Go release metadata does not include a SHA-256 checksum for %s; refusing to install an unverified archive." \
  "官方 Go 发布元数据中没有 %s 的 SHA-256 校验值，拒绝安装未经校验的归档文件。" \
  app.cyberstrikeai.error.go_sha_tool_missing \
  "sha256sum / shasum was not found; refusing to install an unverified Go archive." \
  "未找到 sha256sum / shasum，拒绝安装未经校验的 Go 归档文件。" \
  app.cyberstrikeai.error.go_sha_failed \
  "Go archive checksum verification failed. Expected %s, got %s." \
  "Go 归档文件校验失败。期望 %s，实际 %s。" \
  app.cyberstrikeai.warn.go_archive_cleanup_failed \
  "Failed to remove temporary Go archive %s. Remove it manually after this command finishes." \
  "删除临时 Go 归档 %s 失败。请在本次命令结束后手动清理。" \
  app.cyberstrikeai.info.go_sha_ok \
  "Go archive checksum verified: %s..." \
  "Go 归档文件校验通过：%s..." \
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
  app.cyberstrikeai.error.user_create \
  "Failed to create service user %s. Check useradd output and retry." \
  "创建服务用户 %s 失败。请检查 useradd 输出后重试。" \
  app.cyberstrikeai.success.user_created \
  "Created service user: %s" \
  "服务用户已创建：%s" \
  app.cyberstrikeai.step.fetch_source \
  "Fetch CyberStrikeAI source" \
  "获取 CyberStrikeAI 源码" \
  app.cyberstrikeai.error.source_parent_dir \
  "Failed to prepare the source parent directory for %s. Check filesystem permissions and retry." \
  "无法为 %s 准备源码父目录。请检查文件系统权限后重试。" \
  app.cyberstrikeai.info.repo_fetch \
  "Repository exists, fetching latest branch: %s" \
  "仓库已存在，正在获取最新分支：%s" \
  app.cyberstrikeai.error.repo_fetch \
  "Failed to fetch branch %s in %s. Run git -C %s fetch --prune origin %s after fixing network or repository access." \
  "无法在 %s 中获取分支 %s。请在修复网络或仓库访问问题后执行 git -C %s fetch --prune origin %s。" \
  app.cyberstrikeai.error.repo_checkout \
  "Failed to switch %s to branch %s. Inspect local changes and branch state, then run git -C %s checkout %s." \
  "无法将 %s 切换到分支 %s。请检查本地改动和分支状态，然后执行 git -C %s checkout %s。" \
  app.cyberstrikeai.error.repo_pull \
  "Failed to fast-forward %s on branch %s. Resolve local repository issues, then run git -C %s pull --ff-only origin %s." \
  "无法在分支 %s 上快进更新 %s。请先处理本地仓库问题，然后执行 git -C %s pull --ff-only origin %s。" \
  app.cyberstrikeai.error.repo_clone \
  "Failed to clone %s into %s. Remove any partial checkout, then retry: git clone --depth 1 --branch %s https://github.com/%s.git %s" \
  "无法将 %s 克隆到 %s。请移除任何不完整的检出目录后重试：git clone --depth 1 --branch %s https://github.com/%s.git %s" \
  app.cyberstrikeai.error.commit_invalid \
  "GITHUB_COMMIT must be a full 40-character git commit SHA when set: %s" \
  "设置 GITHUB_COMMIT 时必须提供完整的 40 位 git 提交 SHA：%s" \
  app.cyberstrikeai.info.repo_pinned \
  "Checking out pinned commit %s" \
  "正在检出固定提交 %s" \
  app.cyberstrikeai.error.commit_fetch \
  "Failed to fetch pinned commit %s from %s. Confirm that the commit exists in the configured repository and is accessible, then retry." \
  "无法获取固定提交 %s（仓库：%s）。请确认该提交存在于配置的仓库且可访问后重试。" \
  app.cyberstrikeai.error.commit_checkout \
  "Failed to check out pinned commit %s in %s. Check local changes or restore the checkout, then retry." \
  "无法检出固定提交 %s（目录：%s）。请检查本地改动或修复检出目录后重试。" \
  app.cyberstrikeai.error.installed_version \
  "Cannot determine the checked-out CyberStrikeAI commit in %s." \
  "无法确定 %s 中已检出的 CyberStrikeAI 提交。" \
  app.cyberstrikeai.error.nonempty_dir \
  "%s exists and is not an empty git checkout" \
  "%s 已存在且不是空的 Git 检出目录" \
  app.cyberstrikeai.success.source_ready \
  "Source ready: %s" \
  "源码已就绪：%s" \
  app.cyberstrikeai.error.install_dir_missing \
  "Install directory is unavailable: %s. Recreate it or rerun the source fetch step." \
  "安装目录不可用：%s。请重新创建该目录，或重新执行源码获取步骤。" \
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
  app.cyberstrikeai.error.python_venv \
  "Failed to create the Python virtual environment at %s. Verify python3-venv is installed and retry." \
  "无法创建 Python 虚拟环境：%s。请确认已安装 python3-venv 后重试。" \
  app.cyberstrikeai.error.python_activate \
  "Failed to activate the Python virtual environment at %s. Recreate it and retry." \
  "无法激活 Python 虚拟环境：%s。请重建该虚拟环境后重试。" \
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
  app.cyberstrikeai.error.go_modules \
  "Failed to download Go modules in %s. Check GOPROXY or network access, then retry: go mod download" \
  "无法在 %s 中下载 Go 模块。请检查 GOPROXY 或网络访问，然后重试：go mod download" \
  app.cyberstrikeai.error.binary_empty \
  "Built binary is empty" \
  "构建出的二进制为空" \
  app.cyberstrikeai.error.binary_build \
  "Binary build failed" \
  "二进制构建失败" \
  app.cyberstrikeai.warn.tmp_binary_cleanup_failed \
  "Failed to remove temporary binary %s. Remove it manually after this command finishes." \
  "删除临时二进制 %s 失败。请在本次命令结束后手动清理。" \
  app.cyberstrikeai.success.binary_built \
  "Built binary: %s" \
  "二进制已构建：%s" \
  app.cyberstrikeai.step.runtime_dirs \
  "Prepare runtime directories" \
  "准备运行目录" \
  app.cyberstrikeai.error.runtime_dirs \
  "Runtime directory setup failed. Check permissions for %s and %s, then retry." \
  "运行目录初始化失败。请检查 %s 和 %s 的权限后重试。" \
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
  app.cyberstrikeai.error.systemd_reload \
  "systemd daemon reload failed for %s. Run manually after fixing systemd: systemctl daemon-reload" \
  "无法为 %s 重新加载 systemd daemon。请在修复 systemd 问题后手动执行：systemctl daemon-reload。" \
  app.cyberstrikeai.warn.service_enable_failed \
  "Could not enable %s to start automatically on boot. Run manually after fixing systemd: systemctl enable %s" \
  "无法将 %s 设置为开机自启。请在修复 systemd 问题后手动执行：systemctl enable %s。" \
  app.cyberstrikeai.step.nginx \
  "Configure Nginx reverse proxy" \
  "配置 Nginx 反向代理" \
  app.cyberstrikeai.error.nginx_dirs \
  "Failed to prepare the Nginx config directories for %s. Check filesystem permissions and retry." \
  "无法为 %s 准备 Nginx 配置目录。请检查文件系统权限后重试。" \
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
  app.cyberstrikeai.success.ufw_port \
  "ufw allows port %s/tcp." \
  "ufw 已放行端口 %s/tcp。" \
  app.cyberstrikeai.success.iptables_saved \
  "iptables rules persisted with netfilter-persistent." \
  "iptables 规则已持久化（netfilter-persistent）。" \
  app.cyberstrikeai.info.iptables_rules_written \
  "iptables rules written to /etc/iptables/rules.v4." \
  "iptables 规则已写入 /etc/iptables/rules.v4。" \
  app.cyberstrikeai.warn.iptables_write_failed \
  "Failed to write iptables rules; rules may be lost after reboot." \
  "iptables 规则写入失败，重启后规则可能丢失。" \
  app.cyberstrikeai.warn.iptables_not_persisted \
  "iptables rules are not persisted and may be lost after reboot. Recommended: apt-get install -y iptables-persistent && netfilter-persistent save" \
  "iptables 规则未持久化（重启后失效）。建议：apt-get install -y iptables-persistent && netfilter-persistent save。" \
  app.cyberstrikeai.success.iptables_port \
  "iptables allows port %s/tcp." \
  "iptables 已放行端口 %s/tcp。" \
  app.cyberstrikeai.warn.firewall_config_failed \
  "Automatic firewall configuration failed for port %s/tcp. Open it manually or retry after fixing the firewall service." \
  "端口 %s/tcp 的防火墙自动配置失败。请在修复防火墙服务后重试，或手动放行该端口。" \
  app.cyberstrikeai.warn.no_firewall \
  "No active ufw/iptables detected. Cloud security groups may still need manual rules for port %s/tcp." \
  "未检测到活跃的 ufw/iptables。云安全组可能仍需手动放行端口 %s/tcp。" \
  app.cyberstrikeai.success.logrotate \
  "Log rotation configured (daily rotation, 14 days retained, compressed automatically)." \
  "日志轮转已配置（每日轮转，保留 14 天，自动压缩）。" \
  app.cyberstrikeai.error.logrotate \
  "Logrotate config write failed: /etc/logrotate.d/cyberstrike-ai" \
  "日志轮转配置写入失败：/etc/logrotate.d/cyberstrike-ai。" \
  app.cyberstrikeai.error.cron \
  "Scheduled backup config write failed: %s" \
  "定时备份配置写入失败：%s" \
  app.cyberstrikeai.step.start \
  "Start CyberStrikeAI" \
  "启动 CyberStrikeAI" \
  app.cyberstrikeai.error.install_dir_owner \
  "Failed to reset ownership under %s to %s. Check filesystem permissions and retry." \
  "无法将 %s 下的所有权重置为 %s。请检查文件系统权限后重试。" \
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
  "Local Nginx probe returned HTTP %s. Check the configured server_name, local listener, and Nginx error log." \
  "本地 Nginx 探测返回 HTTP %s。请检查配置的 server_name、本地监听状态和 Nginx 错误日志。" \
  app.cyberstrikeai.summary.title_ready \
  "CyberStrikeAI deployment complete" \
  "CyberStrikeAI 部署完成" \
  app.cyberstrikeai.summary.title_pending \
  "CyberStrikeAI files installed; verify backend and Nginx health before use" \
  "CyberStrikeAI 文件已安装；请先确认后端和 Nginx 健康后再使用" \
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
  app.cyberstrikeai.backup.error.backup_dir_create \
  "cannot create backup directory: %s" \
  "无法创建备份目录：%s" \
  app.cyberstrikeai.backup.warn.sqlite_integrity \
  "SQLite integrity warning for %s: %s" \
  "SQLite 完整性警告：%s：%s" \
  app.cyberstrikeai.backup.ok.created \
  "backup created: %s" \
  "备份已创建：%s" \
  app.cyberstrikeai.backup.warn.remove_failed \
  "could not remove old backup: %s" \
  "旧备份删除失败：%s" \
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
  app.cyberstrikeai.warn.cleanup_old_binary_failed \
  "Could not remove old binary backup: %s" \
  "旧二进制备份删除失败：%s" \
  app.cyberstrikeai.info.cleaned_old_binaries \
  "Removed %s old binary backups (keeping the latest 3)." \
  "已清理 %s 个过期旧二进制备份（保留最近 3 个）。" \
  app.cyberstrikeai.step.update_source \
  "Update source" \
  "更新源码" \
  app.cyberstrikeai.step.restart_updated \
  "Restart updated service" \
  "重启更新后的服务" \
  app.cyberstrikeai.success.update_complete \
  "Update complete: %s -> %s" \
  "更新完成：%s -> %s" \
  app.cyberstrikeai.warn.update_health_failed \
  "Update finished but the health check failed. The new version is running; verify backend and Nginx health before use. Inspect: journalctl -u %s -n 80 --no-pager" \
  "更新已完成但健康检查失败。新版本正在运行，请先确认后端和 Nginx 健康后再使用。请检查：journalctl -u %s -n 80 --no-pager。" \
  app.cyberstrikeai.warn.update_start_failed \
  "Updated version failed to start. Rolling back binary and config." \
  "更新后的版本启动失败。正在回滚二进制与配置。" \
  app.cyberstrikeai.error.rollback_stop_failed \
  "Updated version failed to start, but %s could not be stopped. Rollback was aborted before restoring files. Binary backup: %s Config backup: %s Inspect: systemctl status %s" \
  "更新后的版本启动失败，但无法停止 %s。回滚已在恢复文件前中止。二进制备份：%s 配置备份：%s 请检查：systemctl status %s。" \
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
  app.cyberstrikeai.warn.non_root_status \
  "Running without root; some status details may be incomplete. Recommended: sudo bash %s status" \
  "以非 root 运行，部分状态信息可能不完整（建议：sudo bash %s status）。" \
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
  app.cyberstrikeai.info.stop_disable \
  "Stopping and disabling %s service..." \
  "停止并禁用 %s 服务..." \
  app.cyberstrikeai.error.uninstall_stop_failed \
  "Could not stop %s during uninstall, and it still appears active. Uninstall aborted before deleting files. Inspect: systemctl status %s" \
  "卸载时无法停止 %s，且该服务仍处于 active 状态。已在删除文件前中止卸载。请检查：systemctl status %s。" \
  app.cyberstrikeai.warn.uninstall_stop_failed \
  "Could not stop %s during uninstall, but it is not active; continuing cleanup. Inspect systemd if this is unexpected: systemctl status %s" \
  "卸载时无法停止 %s，但该服务当前不是 active，继续清理。如不符合预期，请检查：systemctl status %s。" \
  app.cyberstrikeai.warn.uninstall_disable_failed \
  "Could not disable %s during uninstall. Remove the enablement manually after fixing systemd: systemctl disable %s" \
  "卸载时无法禁用 %s。请在修复 systemd 后手动移除开机自启：systemctl disable %s。" \
  app.cyberstrikeai.error.remove_dir \
  "Directory removal failed: %s" \
  "目录删除失败：%s" \
  app.cyberstrikeai.error.remove_file \
  "File removal failed: %s" \
  "文件删除失败：%s" \
  app.cyberstrikeai.success.removed_systemd \
  "Removed systemd service" \
  "systemd 服务已移除" \
  app.cyberstrikeai.warn.uninstall_nginx_reload_failed \
  "Nginx config files were removed, but nginx validation or reload failed. Inspect: nginx -t" \
  "Nginx 配置文件已删除，但 nginx 校验或重载失败。请检查：nginx -t" \
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
