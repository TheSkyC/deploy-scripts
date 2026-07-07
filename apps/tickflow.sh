#!/usr/bin/env bash

APP_ID="tickflow"
APP_NAME="TickFlow Stock Panel"
i18n_register_many \
  app.tickflow.description \
  "Docker Compose deployment for the TickFlow stock analysis panel." \
  "TickFlow 股票分析面板的 Docker Compose 部署脚本。" \
  app.tickflow.error.apt_only \
  "This script only supports Debian / Ubuntu because apt-get was not found." \
  "此脚本仅支持 Debian / Ubuntu（apt-get 未找到）。" \
  app.tickflow.error.systemd_required \
  "systemd is required by this script." \
  "此脚本需要 systemd。" \
  app.tickflow.error.arch \
  "Unsupported architecture: %s. Supported: x86_64 / aarch64." \
  "不支持的架构：%s（支持 x86_64 / aarch64）。" \
  app.tickflow.error.port_invalid \
  "PORT is invalid: '%s'. Set a port between 1 and 65535 in the script or config file." \
  "PORT 无效：'%s'，请在脚本或配置文件中设置 1-65535 之间的端口号。" \
  app.tickflow.error.domain_invalid \
  "TICKFLOW_DOMAIN is invalid: '%s'. Use a DNS name such as panel.example.com, or leave it empty." \
  "TICKFLOW_DOMAIN 无效：'%s'，请使用类似 panel.example.com 的 DNS 名称，或留空。" \
  app.tickflow.error.repo_unreachable \
  "Cannot reach GitHub. Check network/proxy settings and retry." \
  "无法访问 GitHub，请检查网络或代理后重试。" \
  app.tickflow.error.repo_clone \
  "Failed to clone %s into %s. Remove any partial checkout, then retry." \
  "无法将 %s 克隆到 %s。请先移除不完整的检出目录后重试。" \
  app.tickflow.error.repo_update \
  "Failed to update %s. Check local changes or network access and retry." \
  "无法更新 %s。请检查本地改动或网络访问后重试。" \
  app.tickflow.error.install_parent_dir \
  "Cannot prepare install parent directory: %s. Check filesystem permissions and retry." \
  "无法准备安装父目录：%s。请检查文件系统权限后重试。" \
  app.tickflow.error.install_dir_not_repo \
  "Install directory exists but is not a git checkout: %s. It may contain data or secrets; back it up and move or remove it manually before retrying." \
  "安装目录已存在但不是 git 检出目录：%s。它可能包含数据或密钥；请先备份并手动移动或删除后再重试。" \
  app.tickflow.error.runtime_dirs \
  "Cannot prepare TickFlow runtime directories: %s and %s. Check filesystem permissions and retry." \
  "无法准备 TickFlow 运行目录：%s 和 %s。请检查文件系统权限后重试。" \
  app.tickflow.error.docker_missing \
  "Docker is required but was not found." \
  "需要 Docker，但当前未找到。" \
  app.tickflow.error.compose_missing \
  "Docker Compose is required but was not found." \
  "需要 Docker Compose，但当前未找到。" \
  app.tickflow.error.compose_write \
  "Failed to write compose file: %s" \
  "写入 compose 文件失败：%s" \
  app.tickflow.error.env_write \
  "Failed to write environment file: %s" \
  "写入环境变量文件失败：%s" \
  app.tickflow.error.tiers_write \
  "Failed to write tiers file: %s" \
  "写入 tiers 文件失败：%s" \
  app.tickflow.error.service_write \
  "Failed to write systemd unit: %s" \
  "写入 systemd 单元失败：%s" \
  app.tickflow.error.service_reload \
  "Failed to reload systemd for %s" \
  "重载 systemd 失败：%s" \
  app.tickflow.error.service_start \
  "Failed to start %s" \
  "启动 %s 失败" \
  app.tickflow.error.service_stop \
  "Failed to stop %s" \
  "停止 %s 失败" \
  app.tickflow.warn.apt_update \
  "apt-get update partially failed. Continuing install, but package versions may be affected. Inspect /var/log/apt/* or rerun apt-get update after fixing repository/network issues." \
  "apt-get update 部分仓库失败，将尝试继续安装（可能影响包版本）。请检查 /var/log/apt/*，或在修复仓库/网络问题后重新执行 apt-get update。" \
  app.tickflow.error.deps_install \
  "Dependency installation failed. Run apt-get install -y git curl ca-certificates docker.io docker-compose-plugin or apt-get install -y git curl ca-certificates docker.io docker-compose after fixing the package manager state." \
  "依赖安装失败。请在修复软件包管理器状态后执行 apt-get install -y git curl ca-certificates docker.io docker-compose-plugin，或执行 apt-get install -y git curl ca-certificates docker.io docker-compose。" \
  app.tickflow.warn.docker_enable_failed \
  "Could not enable or start Docker automatically. If the service fails later, run manually: systemctl enable --now docker" \
  "无法自动启用或启动 Docker。若后续服务失败，请手动执行：systemctl enable --now docker。" \
  app.tickflow.warn.service_enable_failed \
  "Could not enable %s to start automatically on boot. Run manually after fixing systemd: systemctl enable %s" \
  "无法将 %s 设置为开机自启。请在修复 systemd 问题后手动执行：systemctl enable %s。" \
  app.tickflow.warn.service_diagnostics \
  "Recent service diagnostics:" \
  "最近的服务诊断：" \
  app.tickflow.error.service_stop_failed_active \
  "Could not stop %s during uninstall, and it still appears active. Uninstall aborted before removing files. Inspect: systemctl status %s" \
  "卸载时无法停止 %s，且该服务仍处于 active 状态。已在删除文件前中止卸载。请检查：systemctl status %s。" \
  app.tickflow.warn.service_stop_failed \
  "Could not stop %s during uninstall, but it is not active; continuing cleanup. Inspect systemd if this is unexpected: systemctl status %s." \
  "卸载时无法停止 %s，但该服务当前不是 active，继续清理。如不符合预期，请检查：systemctl status %s。" \
  app.tickflow.warn.service_disable_failed \
  "Could not disable %s during uninstall. Remove it manually after fixing systemd: systemctl disable %s" \
  "卸载时无法禁用 %s。请在修复 systemd 问题后手动执行：systemctl disable %s。" \
  app.tickflow.warn.systemd_reload_failed \
  "Could not reload systemd after removing %s. Run manually: systemctl daemon-reload" \
  "删除 %s 后无法重新加载 systemd。请手动执行：systemctl daemon-reload。" \
  app.tickflow.error.health \
  "Health check failed. The panel may still be starting; run status again later." \
  "健康检查失败，面板可能仍在启动；稍后可再次执行 status。" \
  app.tickflow.warn.non_root_status \
  "Running without root; some status details may be incomplete. Recommended: sudo bash %s status" \
  "以非 root 运行，部分状态信息可能不完整（建议：sudo bash %s status）。" \
  app.tickflow.status.systemd \
  "systemd" \
  "systemd" \
  app.tickflow.status.service_active \
  "%s is active." \
  "%s 正在运行。" \
  app.tickflow.status.service_inactive \
  "%s is not active." \
  "%s 未运行。" \
  app.tickflow.status.service_enabled \
  "%s is enabled on boot." \
  "%s 已设置开机自启。" \
  app.tickflow.status.service_disabled \
  "%s is not enabled on boot." \
  "%s 未设置开机自启。" \
  app.tickflow.status.paths \
  "Paths" \
  "路径" \
  app.tickflow.status.install_dir \
  "Install dir" \
  "安装目录" \
  app.tickflow.status.data_dir \
  "Data dir" \
  "数据目录" \
  app.tickflow.status.env_file \
  "Env file" \
  "环境文件" \
  app.tickflow.status.compose_file \
  "Compose file" \
  "Compose 文件" \
  app.tickflow.status.tiers_file \
  "Tiers file" \
  "Tiers 文件" \
  app.tickflow.status.log_dir \
  "Log dir" \
  "日志目录" \
  app.tickflow.status.path_ok \
  "%s exists: %s" \
  "%s 存在：%s" \
  app.tickflow.status.path_missing \
  "%s missing: %s" \
  "%s 缺失：%s" \
  app.tickflow.status.backups \
  "Backups" \
  "备份" \
  app.tickflow.status.backup_count \
  "Backup files: %s (%s)" \
  "备份文件：%s（%s）" \
  app.tickflow.status.backup_missing \
  "Backup directory missing: %s" \
  "备份目录缺失：%s" \
  app.tickflow.status.http_health \
  "HTTP health" \
  "HTTP 健康" \
  app.tickflow.status.local_response \
  "Local response OK: %s" \
  "本地响应正常：%s" \
  app.tickflow.status.local_response_warn \
  "Local response is %s; the service may still be starting or unreachable." \
  "本地响应为 %s；服务可能仍在启动或不可达。" \
  app.tickflow.status.curl_missing \
  "curl is unavailable; skipping local HTTP probe." \
  "curl 不可用，跳过本地 HTTP 探测。" \
  app.tickflow.warn.auth_password_short \
  "AUTH_PASSWORD is shorter than 6 characters; it will be ignored by the panel." \
  "AUTH_PASSWORD 少于 6 个字符，面板会忽略它。" \
  app.tickflow.uninstall.removes \
  "This will remove the TickFlow systemd service and deploy config." \
  "这将删除 TickFlow systemd 服务和部署配置。" \
  app.tickflow.uninstall.keep_install \
  "Install directory is kept by default because it contains data and secrets: %s" \
  "默认保留安装目录，因为其中包含数据和密钥：%s" \
  app.tickflow.uninstall.keep_backup \
  "Backup directory is kept by default: %s" \
  "默认保留备份目录：%s" \
  app.tickflow.prompt.continue \
  "Type YES to uninstall TickFlow:" \
  "输入 YES 以卸载 TickFlow：" \
  app.tickflow.prompt.delete_install \
  "Delete install directory %s? This removes data and .env secrets. (y/N):" \
  "是否删除安装目录 %s？这会删除数据和 .env 密钥。（y/N）：" \
  app.tickflow.prompt.delete_backup \
  "Delete backup directory %s too? (y/N):" \
  "是否同时删除备份目录 %s？（y/N）：" \
  app.tickflow.info.cancelled \
  "Cancelled." \
  "已取消。" \
  app.tickflow.info.kept_install \
  "Kept install directory: %s" \
  "已保留安装目录：%s" \
  app.tickflow.info.kept_backup \
  "Kept backup directory: %s" \
  "已保留备份目录：%s" \
  app.tickflow.success.removed \
  "TickFlow removed" \
  "TickFlow 已移除" \
  app.tickflow.success.deleted_install \
  "Deleted install directory: %s" \
  "已删除安装目录：%s" \
  app.tickflow.success.deleted_backup \
  "Deleted backup directory: %s" \
  "已删除备份目录：%s" \
  app.tickflow.step.deps \
  "Install system dependencies" \
  "安装系统依赖" \
  app.tickflow.success.deps \
  "Dependencies installed" \
  "系统依赖安装完成" \
  app.tickflow.step.fetch_source \
  "Fetch TickFlow source" \
  "获取 TickFlow 源码" \
  app.tickflow.info.repo_exists \
  "Repository exists, updating branch %s" \
  "仓库已存在，正在更新分支 %s" \
  app.tickflow.success.source_ready \
  "Source ready: %s" \
  "源码已就绪：%s" \
  app.tickflow.step.config \
  "Write compose and env files" \
  "写入 compose 和环境变量文件" \
  app.tickflow.success.config \
  "Deployment files written" \
  "部署文件已写入" \
  app.tickflow.step.systemd \
  "Install systemd service" \
  "安装 systemd 服务" \
  app.tickflow.success.systemd \
  "systemd service installed: %s" \
  "systemd 服务已安装：%s" \
  app.tickflow.step.start \
  "Start TickFlow" \
  "启动 TickFlow" \
  app.tickflow.success.started \
  "Service started" \
  "服务已启动" \
  app.tickflow.success.health \
  "HTTP health check passed (status %s)." \
  "HTTP 健康检查通过（状态码 %s）。" \
  app.tickflow.warn.health \
  "Health check returned %s. The service may still be initializing." \
  "健康检查返回 %s，服务可能仍在初始化。" \
  app.tickflow.summary.title_ready \
  "TickFlow deployment complete" \
  "TickFlow 部署完成" \
  app.tickflow.summary.title_pending \
  "TickFlow files installed; verify service health before use" \
  "TickFlow 文件已安装；请先确认服务健康后再使用" \
  app.tickflow.summary.public \
  "Public URL" \
  "公网访问" \
  app.tickflow.summary.internal \
  "Internal URL" \
  "内网直连" \
  app.tickflow.summary.repo \
  "Repository" \
  "源码仓库" \
  app.tickflow.summary.compose \
  "Compose dir" \
  "Compose 目录" \
  app.tickflow.summary.data \
  "Data dir" \
  "数据目录" \
  app.tickflow.summary.env \
  "Env file" \
  "环境变量文件" \
  app.tickflow.summary.systemd \
  "systemd commands:" \
  "systemd 命令：" \
  app.tickflow.summary.status_cmd \
  "show service status" \
  "查看服务状态" \
  app.tickflow.summary.logs_cmd \
  "follow logs" \
  "实时日志" \
  app.tickflow.summary.restart_cmd \
  "restart service" \
  "重启服务" \
  app.tickflow.summary.update_cmd \
  "update to the latest version" \
  "更新到最新版" \
  app.tickflow.summary.backup_cmd \
  "back up data now" \
  "立即备份数据" \
  app.tickflow.backup.error_dir \
  "Cannot prepare backup directory: %s" \
  "无法准备备份目录：%s" \
  app.tickflow.backup.error_source_missing \
  "Cannot create backup because required source is missing: %s" \
  "无法创建备份，缺少必要源文件：%s" \
  app.tickflow.backup.error_archive \
  "Failed to create backup archive: %s" \
  "创建备份归档失败：%s" \
  app.tickflow.backup.success \
  "Backup created: %s" \
  "备份已创建：%s" \
  app.tickflow.summary.uninstall_cmd \
  "uninstall the service" \
  "卸载服务"

APP_DESCRIPTION="$(t app.tickflow.description)"
APP_IMPL_SCRIPT="impl/install_tickflow.sh"

load_app_impl "$APP_IMPL_SCRIPT"
