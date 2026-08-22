#!/usr/bin/env bash

# Shared lifecycle for GitHub-release single-binary services.
#
# A binary app provides BA_* configuration variables, optional hook
# functions (ba_asset_name, ba_download_urls, ba_write_config,
# ba_systemd_unit, bapp_health_probe, ba_status_extra, ba_uninstall_extra,
# ba_validate_extra, ba_preflight_extra, ba_pre_start, ba_summary_extra),
# then calls binary_app_bootstrap.  The bapp_* functions implement the
# lifecycle; each thin impl/install_<app>.sh defines the standard command
# functions (do_install, do_update, do_backup, do_status, do_uninstall) as
# short delegates that acquire the deployment lock, plus app-specific
# download, config, and runtime hooks.

i18n_register_many \
  binary_app.error.apt_only \
  "This script only supports Debian / Ubuntu because apt-get was not found." \
  "此脚本仅支持 Debian / Ubuntu（apt-get 未找到）。" \
  binary_app.error.arch \
  "Unsupported architecture: %s. Supported: x86_64 / aarch64." \
  "不支持的架构：%s（支持 x86_64 / aarch64）。" \
  binary_app.error.github_unreachable \
  "Cannot reach GitHub. Check network/proxy settings and retry." \
  "网络不通，无法访问 GitHub，请检查网络或代理后重试。" \
  binary_app.warn.github_api \
  "Cannot reach GitHub API." \
  "无法访问 GitHub API。" \
  binary_app.error.version_failed \
  "Could not determine the latest release version." \
  "无法获取最新版本号。" \
  binary_app.error.apt_update \
  "apt-get update failed." \
  "apt-get update 失败。" \
  binary_app.error.deps_install \
  "Failed to install required packages." \
  "安装依赖包失败。" \
  binary_app.error.user_create \
  "Failed to create system user %s." \
  "创建系统用户 %s 失败。" \
  binary_app.error.dir_create \
  "Failed to create directories: %s." \
  "创建目录失败：%s。" \
  binary_app.error.dir_owner \
  "Failed to set ownership %s on %s." \
  "设置 %s 的所有者为 %s 失败。" \
  binary_app.error.path_whitespace \
  "Path for %s must not contain whitespace: %s" \
  "%s 的路径不能包含空白字符：%s" \
  binary_app.error.download \
  "Failed to download the release from %s." \
  "从 %s 下载发布包失败。" \
  binary_app.warn.tmp_cleanup_failed \
  "Failed to remove temporary file: %s." \
  "清理临时文件失败：%s。" \
  binary_app.error.binary_empty \
  "Binary file is empty; the download likely failed." \
  "二进制文件为空，疑似下载失败。" \
  binary_app.error.binary_too_small \
  "Binary file is too small (%s bytes); the download may be incomplete." \
  "二进制文件过小（%s 字节），疑似下载不完整。" \
  binary_app.error.binary_not_elf \
  "Binary file is not a valid ELF file (magic: %s)." \
  "二进制文件不是有效的 ELF 格式（magic: %s）。" \
  binary_app.success.binary_verified \
  "Binary verification passed (ELF, %s MB)." \
  "二进制校验通过（ELF，%s MB）。" \
  binary_app.error.binary_install \
  "Failed to install the binary at %s." \
  "安装二进制到 %s 失败。" \
  binary_app.error.extract \
  "Failed to extract the release archive." \
  "解压发布包失败。" \
  binary_app.error.binary_missing \
  "Binary %s was not found in the release archive." \
  "在发布包中未找到二进制 %s。" \
  binary_app.success.dirs \
  "Directories ready: %s." \
  "目录就绪：%s。" \
  binary_app.info.user_exists \
  "System user %s already exists; reusing it." \
  "系统用户 %s 已存在，直接复用。" \
  binary_app.success.user_created \
  "System user %s created." \
  "系统用户 %s 已创建。" \
  binary_app.success.deps \
  "Required packages installed." \
  "依赖包已安装。"\
  binary_app.step.latest \
  "Querying the latest release" \
  "查询最新版本" \
  binary_app.step.deps \
  "Installing dependencies" \
  "安装依赖" \
  binary_app.step.user_dirs \
  "Setting up user and directories" \
  "创建用户与目录" \
  binary_app.step.download \
  "Downloading %s release" \
  "下载 %s 发布包" \
  binary_app.step.config \
  "Writing configuration" \
  "写入配置" \
  binary_app.step.systemd \
  "Installing systemd service" \
  "安装 systemd 服务" \
  binary_app.step.firewall \
  "Configuring firewall" \
  "配置防火墙" \
  binary_app.step.logrotate \
  "Configuring log rotation" \
  "配置日志轮转" \
  binary_app.step.start \
  "Starting service" \
  "启动服务" \
  binary_app.step.health \
  "Health check" \
  "健康检查" \
  binary_app.step.manual_backup \
  "Creating a manual backup" \
  "创建手动备份" \
  binary_app.step.check_update \
  "Checking for updates" \
  "检查更新" \
  binary_app.step.pre_backup \
  "Backing up current data" \
  "备份当前数据" \
  binary_app.step.download_update \
  "Downloading %s (current %s)" \
  "下载 %s（当前 %s）" \
  binary_app.step.replace_restart \
  "Replacing binary and restarting" \
  "替换二进制并重启" \
  binary_app.step.uninstall \
  "Uninstalling %s" \
  "卸载 %s" \
  binary_app.info.query_latest \
  "Querying the latest version from GitHub..." \
  "正在从 GitHub 查询最新版本..." \
  binary_app.info.download_url \
  "Download URL: %s" \
  "下载地址：%s" \
  binary_app.info.current \
  "Current version: %s" \
  "当前版本：%s" \
  binary_app.info.github_latest \
  "Latest version: %s" \
  "最新版本：%s" \
  binary_app.success.latest \
  "Latest release: %s" \
  "最新版本：%s" \
  binary_app.success.env_file \
  "Configuration written: %s" \
  "配置已写入：%s" \
  binary_app.error.env_file \
  "Failed to write configuration: %s" \
  "写入配置失败：%s" \
  binary_app.success.systemd \
  "systemd unit installed: %s" \
  "systemd 单元已安装：%s" \
  binary_app.error.systemd_unit \
  "Failed to write systemd unit for %s." \
  "写入 %s 的 systemd 单元失败。" \
  binary_app.error.systemd_reload \
  "Failed to reload systemd for %s." \
  "重载 systemd 失败（%s）。" \
  binary_app.warn.enable_failed \
  "Failed to enable %s on boot; run manually: systemctl enable %s" \
  "设置 %s 开机自启失败；可手动执行：systemctl enable %s" \
  binary_app.success.started \
  "Service started: %s" \
  "服务已启动：%s" \
  binary_app.warn.start_rollback \
  "Service failed to start; rolling back install." \
  "服务启动失败，正在回滚安装。" \
  binary_app.warn.stop_failed \
  "Failed to stop %s during cleanup." \
  "清理过程中停止 %s 失败。" \
  binary_app.warn.disable_failed \
  "Failed to disable %s during cleanup." \
  "清理过程中禁用 %s 失败。" \
  binary_app.warn.reload_failed \
  "Failed to reload systemd during cleanup." \
  "清理过程中重载 systemd 失败。" \
  binary_app.error.install_start_failed \
  "%s failed to start. Inspect: journalctl -u %s -n 50 --no-pager" \
  "%s 启动失败。请检查：journalctl -u %s -n 50 --no-pager" \
  binary_app.success.health \
  "HTTP health check passed (status %s)." \
  "HTTP 健康检查通过（状态码 %s）。" \
  binary_app.warn.health \
  "Health check returned %s. The service may still be initializing; run status again later." \
  "健康检查返回 %s，服务可能仍在初始化（稍后可用 status 再次确认）。" \
  binary_app.warn.debug_command \
  "Debug command: journalctl -u %s -n 30 --no-pager" \
  "调试命令：journalctl -u %s -n 30 --no-pager" \
  binary_app.error.not_installed \
  "%s is not installed (missing %s)." \
  "%s 未安装（缺少 %s）。" \
  binary_app.success.already_latest \
  "Already running the latest version: %s." \
  "已是最新版本：%s。" \
  binary_app.warn.pre_failed_state \
  "Service was in a failed state before the update." \
  "更新前服务处于 failed 状态。" \
  binary_app.warn.pre_failed_debug \
  "Inspect the failure: journalctl -u %s -n 50 --no-pager" \
  "请检查失败原因：journalctl -u %s -n 50 --no-pager" \
  binary_app.warn.pre_backup_failed \
  "Pre-update backup failed; continuing anyway." \
  "更新前备份失败，继续执行更新。" \
  binary_app.error.stop_service_failed \
  "Failed to stop %s before replacing the binary." \
  "替换二进制前停止 %s 失败。" \
  binary_app.success.update_started \
  "Updated service started." \
  "更新后的服务已启动。" \
  binary_app.warn.update_start_failed \
  "Updated service failed to start; rolling back to %s." \
  "更新后的服务启动失败，正在回滚到 %s。" \
  binary_app.error.rollback_stop_failed \
  "Failed to stop %s during rollback." \
  "回滚过程中停止 %s 失败。" \
  binary_app.warn.rollback_start_failed \
  "Failed to restart %s after rollback." \
  "回滚后重启 %s 失败。" \
  binary_app.error.update_failed \
  "Update failed; %s was restored from backup." \
  "更新失败，已从备份恢复 %s。" \
  binary_app.success.rollback \
  "Rolled back to %s." \
  "已回滚到 %s。" \
  binary_app.info.old_binary \
  "Previous binary kept at: %s" \
  "旧二进制保留在：%s" \
  binary_app.warn.old_binary_backup \
  "Old binary backed up as %s." \
  "旧二进制已备份为 %s。" \
  binary_app.info.cleaned_old \
  "Removed %s old binary backup(s)." \
  "已清理 %s 个旧二进制备份。" \
  binary_app.warn.cleanup_old_failed \
  "Failed to remove old binary backup: %s" \
  "删除旧二进制备份失败：%s"\
  binary_app.error.data_missing \
  "Data directory does not exist (%s); backup aborted." \
  "数据目录不存在（%s），备份中止。" \
  binary_app.error.backup_dir_create \
  "Failed to create backup directory: %s" \
  "创建备份目录失败：%s" \
  binary_app.info.backing_up \
  "Backing up %s to %s" \
  "正在备份 %s 到 %s" \
  binary_app.success.backup_done \
  "Backup created: %s (%s)" \
  "备份已创建：%s（%s）" \
  binary_app.error.backup_failed \
  "Backup failed." \
  "备份失败。" \
  binary_app.warn.backup_cleanup_failed \
  "Failed to remove old backup: %s" \
  "删除旧备份失败：%s" \
  binary_app.info.cleaned_backups \
  "Removed %s backup(s) older than %s day(s)." \
  "已清理 %s 个超过 %s 天的备份。" \
  binary_app.info.backup_list \
  "Backups in %s:" \
  "%s 中的备份：" \
  binary_app.success.silent_backup \
  "Backup created: %s (%s)" \
  "备份已创建：%s（%s）" \
  binary_app.warn.silent_backup_failed \
  "Backup failed; see %s for details." \
  "备份失败，详见 %s。" \
  binary_app.status.service \
  "Service: %s (%s)" \
  "服务：%s（%s）" \
  binary_app.status.version \
  "Installed version: %s" \
  "已安装版本：%s" \
  binary_app.status.paths \
  "Paths:" \
  "路径：" \
  binary_app.status.not_installed \
  "Not installed (no deployment config found)." \
  "未安装（未找到部署记录）。" \
  binary_app.status.health_url \
  "Local health URL: %s" \
  "本地健康检查地址：%s" \
  binary_app.prompt.continue \
  "Continue with uninstall? Type YES:" \
  "是否继续卸载？请输入 YES：" \
  binary_app.prompt.delete_data \
  "Delete data directory too (%s)? [y/N]:" \
  "是否同时删除数据目录（%s）？[y/N]：" \
  binary_app.prompt.delete_backup \
  "Delete backup directory too (%s)? [y/N]:" \
  "是否同时删除备份目录（%s）？[y/N]：" \
  binary_app.info.cancelled \
  "Uninstall cancelled." \
  "已取消卸载。" \
  binary_app.info.stop_disable \
  "Stopping and disabling %s service..." \
  "正在停止并禁用 %s 服务..." \
  binary_app.warn.uninstall_stop_failed \
  "Could not stop %s during uninstall; continuing cleanup." \
  "卸载时无法停止 %s，继续清理。" \
  binary_app.error.uninstall_stop_failed \
  "Could not stop %s during uninstall and it is still active; aborted before deleting files." \
  "卸载时无法停止 %s 且服务仍为 active，已在删除文件前中止。" \
  binary_app.warn.uninstall_disable_failed \
  "Could not disable %s during uninstall." \
  "卸载时无法禁用 %s。" \
  binary_app.success.removed_systemd \
  "systemd service removed." \
  "systemd 服务已移除。" \
  binary_app.success.removed_binary \
  "Binary and related files removed." \
  "二进制及相关文件已删除。" \
  binary_app.success.removed_config \
  "Configuration and deployment config removed." \
  "配置与部署记录已清除。" \
  binary_app.error.remove_dir \
  "Directory removal failed: %s" \
  "目录删除失败：%s。" \
  binary_app.error.remove_file \
  "File removal failed: %s" \
  "文件删除失败：%s。" \
  binary_app.success.deleted_data \
  "Data directory deleted: %s" \
  "数据目录已删除：%s。" \
  binary_app.info.kept_data \
  "Data directory kept: %s" \
  "数据目录已保留：%s。" \
  binary_app.success.deleted_backup \
  "Backup directory deleted: %s" \
  "备份目录已删除：%s。" \
  binary_app.info.kept_backup \
  "Backup directory kept: %s" \
  "备份目录已保留：%s。" \
  binary_app.success.deleted_user \
  "System user %s deleted." \
  "系统用户 %s 已删除。" \
  binary_app.warn.delete_user \
  "Failed to delete system user %s; it may be referenced elsewhere." \
  "删除系统用户 %s 失败，可能被其他服务引用。" \
  binary_app.success.uninstalled \
  "%s fully uninstalled." \
  "%s 已完全卸载。" \
  binary_app.hint.data_kept \
  "Data was kept at %s." \
  "数据已保留在 %s。" \
  binary_app.hint.remove_data \
  "To remove it later: sudo rm -rf %s" \
  "如需删除：sudo rm -rf %s" \
  binary_app.hint.backup_kept \
  "Backups were kept at %s." \
  "备份已保留在 %s。" \
  binary_app.warn.log_path \
  "Log directory path is unusual (%s); skipped deletion." \
  "日志目录路径异常（%s），已跳过删除。" \
  binary_app.warn.cleanup_install_failed \
  "Install directory cleanup skipped because removal failed: %s" \
  "安装目录清理失败，已跳过：%s" \
  binary_app.success.cleaned_install \
  "Install directory cleaned: %s" \
  "安装目录已清理：%s。" \
  binary_app.summary.title_ready \
  "Deployment Ready" \
  "部署完成" \
  binary_app.summary.public \
  "Public:" \
  "公网地址：" \
  binary_app.summary.internal \
  "Internal:" \
  "内网地址：" \
  binary_app.summary.version \
  "Version:" \
  "版本：" \
  binary_app.summary.data_dir \
  "Data directory:" \
  "数据目录：" \
  binary_app.summary.log_dir \
  "Log directory:" \
  "日志目录：" \
  binary_app.summary.backup_dir \
  "Backup directory:" \
  "备份目录：" \
  binary_app.summary.management \
  "Management" \
  "常用管理命令" \
  binary_app.summary.status_cmd \
  "show status" \
  "查看状态" \
  binary_app.summary.update_cmd \
  "update to latest" \
  "更新到最新版" \
  binary_app.summary.backup_cmd \
  "manual backup" \
  "手动备份" \
  binary_app.summary.uninstall_cmd \
  "uninstall" \
  "卸载" \
  binary_app.summary.systemd \
  "Systemd" \
  "Systemd" \
  binary_app.summary.show_status \
  "show service status" \
  "查看服务状态" \
  binary_app.summary.live_logs \
  "tail live logs" \
  "实时查看日志" \
  binary_app.summary.restart \
  "restart service" \
  "重启服务"\
  binary_app.success.ufw_port \
  "ufw allows port %s." \
  "ufw 已放行端口 %s。" \
  binary_app.warn.firewall_config_failed \
  "Automatic firewall configuration failed for port %s. Open it manually or retry after fixing the firewall service." \
  "端口 %s 的防火墙自动配置失败。请在修复防火墙服务后重试，或手动放行该端口。" \
  binary_app.success.iptables_saved \
  "iptables rules persisted with netfilter-persistent." \
  "iptables 规则已持久化（netfilter-persistent）。" \
  binary_app.info.iptables_rules_written \
  "iptables rules written to /etc/iptables/rules.v4." \
  "iptables 规则已写入 /etc/iptables/rules.v4。" \
  binary_app.warn.iptables_write_failed \
  "Failed to write iptables rules; rules may be lost after reboot." \
  "iptables 规则写入失败，重启后规则可能丢失。" \
  binary_app.warn.iptables_not_persisted \
  "iptables rules are not persisted and may be lost after reboot. Recommended: apt-get install -y iptables-persistent && netfilter-persistent save" \
  "iptables 规则未持久化（重启后失效）。建议：apt-get install -y iptables-persistent && netfilter-persistent save。" \
  binary_app.success.iptables_port \
  "iptables allows port %s." \
  "iptables 已放行端口 %s。" \
  binary_app.warn.no_firewall \
  "No active firewall detected. If you use a cloud security group, allow port %s manually." \
  "未检测到活跃防火墙，如有云安全组（如 AWS/阿里云/腾讯云）请手动放行端口 %s。" \
  binary_app.success.logrotate \
  "Log rotation configured (daily rotation, 14 days retained, compressed automatically)." \
  "日志轮转已配置（每日轮转，保留 14 天，自动压缩）。" \
  binary_app.error.logrotate \
  "Logrotate config write failed: /etc/logrotate.d/%s" \
  "日志轮转配置写入失败：/etc/logrotate.d/%s。"

# Derive standard paths from the app configuration.  Apps may override
# APP_CONFIG_DERIVE_HOOK before load; this default matches the binary-app
# layout (binary under INSTALL_DIR, data and logs separated).
_binary_app_derive_paths() {
  BIN_PATH="${INSTALL_DIR}/${BA_BIN_NAME}"
  LOG_FILE="${LOG_DIR}/${BA_BIN_NAME}.log"
  ENV_FILE="/etc/${SERVICE_NAME}.env"
}
# systemd unit directives (ExecStart, ReadWritePaths) cannot contain
# whitespace; reject any custom path early so it cannot silently break the
# generated unit file.
bapp_validate_no_whitespace() {
  local name="$1" value="$2"
  if [[ "$value" =~ [[:space:]] ]]; then
    error "$(t binary_app.error.path_whitespace "$name" "$value")"
  fi
}

# Shared validators run for every binary app; apps add checks through
# ba_validate_extra when they need more.
bapp_validate_cfg() {
  local attr rw_path
  app_validate_port "$PORT" "PORT"
  app_validate_domain "DOMAIN" "$DOMAIN"
  app_validate_systemd_name "SERVICE_NAME" "$SERVICE_NAME"
  app_validate_system_name "SERVICE_USER" "$SERVICE_USER"
  app_validate_github_repo "GITHUB_REPO" "$GITHUB_REPO"
  require_safe_path "INSTALL_DIR" "$INSTALL_DIR"
  require_safe_path "BIN_PATH" "$BIN_PATH"
  require_safe_path "DATA_DIR" "$DATA_DIR"
  require_safe_path "LOG_DIR" "$LOG_DIR"
  require_safe_path "BACKUP_DIR" "${BACKUP_DIR:-}"
  for attr in INSTALL_DIR BIN_PATH DATA_DIR LOG_DIR BACKUP_DIR; do
    bapp_validate_no_whitespace "$attr" "${!attr}"
  done
  if [[ -n "${BA_READWRITE_PATHS:-}" ]]; then
    for rw_path in ${BA_READWRITE_PATHS}; do
      require_safe_path "BA_READWRITE_PATHS" "$rw_path"
      bapp_validate_no_whitespace "BA_READWRITE_PATHS" "$rw_path"
    done
  fi
  if declare -f ba_validate_extra >/dev/null 2>&1; then
    ba_validate_extra
  fi
}

# Wire app_conf_file/app_lock_file once APP_ID is known (called from the
# impl after configuration defaults and hooks are declared).
binary_app_bootstrap() {
  APP_CONFIG_DERIVE_HOOK=_binary_app_derive_paths
  APP_STATUS_BACKUP_FN=bapp_status_backup_json
  CONF_FILE="$(app_conf_file)"
  LOCK_FILE="$(app_lock_file)"
  _binary_app_derive_paths
  bapp_validate_cfg
}

# Status adapters used by the central status and check-update commands. These
# deliberately share only the GitHub-release binary lifecycle: applications
# with custom update logic must opt in with their own adapter instead.
bapp_status_backup_json() {
  local conf_file backup_dir latest_archive archive_name archive_mtime last_success_at
  backup_dir="${BACKUP_DIR:-}"
  conf_file="$(app_conf_file 2>/dev/null || true)"
  if [[ -f "$conf_file" ]]; then
    local owner mode configured_dir
    owner="$(stat -c '%U' "$conf_file" 2>/dev/null || printf unknown)"
    mode="$(stat -c '%a' "$conf_file" 2>/dev/null || printf unknown)"
    if [[ "$owner" == root && ( "$mode" == 600 || "$mode" == 400 ) ]]; then
      configured_dir="$(awk -F= '
        /^[[:space:]]*BACKUP_DIR=/ {
          value=$0
          sub(/^[^=]*=[[:space:]]*/, "", value)
          gsub(/^"|"$/, "", value)
          gsub(/[[:space:]]+$/, "", value)
          print value
          exit
        }
      ' "$conf_file" 2>/dev/null)"
      [[ -n "$configured_dir" ]] && backup_dir="$configured_dir"
    fi
  fi
  if [[ ! -d "$backup_dir" ]]; then
    printf '{"state":"missing","last_success_at":null,"path":%s,"message":"backup directory is missing"}' "$(app_json_string "$backup_dir")"
    return
  fi
  if ! latest_archive="$(find "$backup_dir" -maxdepth 1 -type f -name "${APP_ID}_*.tar.gz" -printf '%T@|%p\n' 2>/dev/null | sort -t'|' -k1,1nr)"; then
    printf '{"state":"failed","last_success_at":null,"path":%s,"message":"cannot inspect backup directory"}' "$(app_json_string "$backup_dir")"
    return
  fi
  latest_archive="${latest_archive%%$'\n'*}"
  if [[ -z "$latest_archive" ]]; then
    printf '{"state":"missing","last_success_at":null,"path":%s,"message":"no backup archive found"}' "$(app_json_string "$backup_dir")"
    return
  fi
  archive_name="${latest_archive#*|}"
  archive_mtime="${latest_archive%%|*}"
  if ! last_success_at="$(date -d "@${archive_mtime%.*}" '+%Y-%m-%dT%H:%M:%S%:z' 2>/dev/null)"; then
    printf '{"state":"unknown","last_success_at":null,"path":%s,"message":"cannot read backup timestamp"}' "$(app_json_string "$archive_name")"
    return
  fi
  printf '{"state":"available","last_success_at":%s,"path":%s,"message":null}' \
    "$(app_json_string "$last_success_at")" "$(app_json_string "$archive_name")"
}
bapp_status_version_json() {
  local conf_file installed
  conf_file="$(app_conf_file)"
  installed="$(app_config_installed_version "$conf_file" 2>/dev/null || true)"
  version_check_cached_binary_release_json "$APP_ID" "$installed"
}

bapp_check_update_json() {
  local installed="$1" refresh="${2:-0}" no_network="${3:-0}"
  version_check_binary_release_json "$APP_ID" "${GITHUB_REPO:-}" "$installed" "$refresh" "$no_network"
}

# Root/apt/arch preflight shared by install, update, backup, and uninstall.
bapp_preflight() {
  local action="${1:-}"
  if [[ "$action" != "status" && ${EUID:-$(id -u)} -ne 0 ]]; then
    error "$(t error.root_required "$0" "$action")"
  fi
  command -v apt-get >/dev/null 2>&1 \
    || error "$(t binary_app.error.apt_only)"
  case "$(uname -m)" in
    x86_64) BA_ARCH="amd64" ;;
    aarch64) BA_ARCH="arm64" ;;
    *) error "$(t binary_app.error.arch "$(uname -m)")" ;;
  esac
  if declare -f ba_preflight_extra >/dev/null 2>&1; then
    ba_preflight_extra "$action"
  fi
}

# Verify network reachability to the release host(s).
bapp_check_net() {
  app_check_connectivity binary_app.error.github_unreachable \
    "https://api.github.com" \
    "https://github.com" \
    "https://objects.githubusercontent.com"
}

# Echo the latest release tag for GITHUB_REPO, or the empty string.
ba_latest_version() {
  local tag
  tag="$(github_latest_release_tag "$GITHUB_REPO" "binary_app.warn.github_api")"
  printf '%s\n' "$tag"
}

# Default release download URL: one asset from the version tag.  Apps whose
# asset naming differs override ba_asset_name (and optionally ba_download_urls).
ba_asset_name() {
  local version="$1"
  printf '%s\n' "${BA_ASSET_TEMPLATE//ARCH/${BA_ARCH}}"
}

ba_download_urls() {
  local version="$1" asset
  asset="$(ba_asset_name "$version")"
  printf 'https://github.com/%s/releases/download/%s/%s\n' "$GITHUB_REPO" "$version" "$asset"
}

# Download the first reachable URL for the given version into $1.
ba_download_release() {
  local version="$1" target="$2" url
  while IFS= read -r url; do
    [[ -n "$url" ]] || continue
    if curl -fL --progress-bar -o "$target" "$url"; then
      return 0
    fi
    rm -f "$target" 2>/dev/null || true
  done < <(ba_download_urls "$version")
  return 1
}

# Extract/copy the downloaded release into a staging directory and print the
# path of the binary inside it.  Handles raw binaries, tar.gz, and zip.
ba_prepare_binary() {
  local downloaded="$1" stage="$2" found
  case "${BA_ARCHIVE_TYPE:-none}" in
    tar.gz)
      tar -xzf "$downloaded" -C "$stage" || return 1
      ;;
    zip)
      command -v unzip >/dev/null 2>&1 || return 1
      unzip -q "$downloaded" -d "$stage" || return 1
      ;;
    none)
      cp "$downloaded" "${stage}/${BA_BIN_NAME}" || return 1
      ;;
    *)
      return 1
      ;;
  esac
  found="$(find "$stage" -type f -name "${BA_BIN_NAME}" -print -quit 2>/dev/null)"
  [[ -n "$found" && -f "$found" ]] || return 1
  printf '%s\n' "$found"
}

# Sanity-check a candidate binary: non-empty, large enough, ELF magic.
bapp_inspect_binary() {
  local bin="$1"
  local min_size="${BA_MIN_SIZE:-1048576}"
  local size magic
  [[ -s "$bin" ]] || error "$(t binary_app.error.binary_empty)"
  size="$(wc -c < "$bin")"
  if [[ "$size" -lt "$min_size" ]]; then
    rm -f "$bin"
    error "$(t binary_app.error.binary_too_small "$size")"
  fi
  magic="$(dd if="$bin" bs=1 count=4 2>/dev/null | od -An -tx1 | tr -d ' \n')"
  if [[ "$magic" != "7f454c46" ]]; then
    rm -f "$bin"
    error "$(t binary_app.error.binary_not_elf "${magic:-read failed}")"
  fi
  local size_mb=$(( size / 1024 / 1024 ))
  success "$(t binary_app.success.binary_verified "$size_mb")"
}
# Set up the service user, directories, and ownership for a fresh install.
ba_setup_user_dirs() {
  local dirs=("$INSTALL_DIR" "$DATA_DIR" "$LOG_DIR" "$BACKUP_DIR")
  local d
  if ! id "$SERVICE_USER" >/dev/null 2>&1; then
    if ! useradd -r -s /usr/sbin/nologin -d "$INSTALL_DIR" "$SERVICE_USER"; then
      error "$(t binary_app.error.user_create "$SERVICE_USER")"
    fi
    success "$(t binary_app.success.user_created "$SERVICE_USER")"
  else
    info "$(t binary_app.info.user_exists "$SERVICE_USER")"
  fi
  local -a new_dirs=() existing_dirs=()
  local existed=false
  for d in "${dirs[@]}"; do
    require_safe_path "$(basename "$d")" "$d"
    existed=false
    [[ -e "$d" || -L "$d" ]] && existed=true
    if ! mkdir -p "$d"; then
      error "$(t binary_app.error.dir_create "$d")"
    fi
    if $existed; then
      existing_dirs+=("$d")
    else
      new_dirs+=("$d")
    fi
  done
  # Recursively own only directories created by this deployment; pre-existing
  # directories get non-recursive ownership so unrelated files are untouched.
  if [[ ${#new_dirs[@]} -gt 0 ]]; then
    if ! chown -R "${SERVICE_USER}:${SERVICE_USER}" "${new_dirs[@]}"; then
      error "$(t binary_app.error.dir_owner "${SERVICE_USER}:${SERVICE_USER}" "${new_dirs[*]}")"
    fi
  fi
  if [[ ${#existing_dirs[@]} -gt 0 ]]; then
    if ! chown "${SERVICE_USER}:${SERVICE_USER}" "${existing_dirs[@]}"; then
      error "$(t binary_app.error.dir_owner "${SERVICE_USER}:${SERVICE_USER}" "${existing_dirs[*]}")"
    fi
  fi
  success "$(t binary_app.success.dirs "$INSTALL_DIR $DATA_DIR $LOG_DIR")"
}

# Install the downloaded candidate at BIN_PATH, preserving the previous
# binary (when present) as a rollback backup.
ba_install_binary() {
  local tmp_bin="$1"
  local backup_path="${2:-}"
  if ! app_binary_install_candidate "$tmp_bin" "$backup_path"; then
    error "$(t binary_app.error.binary_install "$BIN_PATH")"
  fi
}

ba_remove_file_or_error() {
  local path="$1" name="$2"
  require_safe_path "$name" "$path"
  if ! rm -f "$path"; then
    error "$(t binary_app.error.remove_file "$path")"
  fi
}

ba_remove_dir_or_error() {
  local path="$1" name="$2"
  if ! safe_rm_dir "$path" "$name"; then
    error "$(t binary_app.error.remove_dir "$path")"
  fi
}

# Default systemd unit; apps override ba_systemd_unit for service-specific
# ExecStart flags, environment, or hardening needs.
ba_systemd_unit() {
  local unit_path="/etc/systemd/system/${SERVICE_NAME}.service"
  local env_line=""
  if [[ "${BA_USE_ENV_FILE:-0}" == "1" ]]; then
    env_line="EnvironmentFile=${ENV_FILE}"
  fi
  local extra=""
  if declare -f ba_systemd_extra >/dev/null 2>&1; then
    extra="$(ba_systemd_extra)"
  fi
  if ! systemd_write_unit "$unit_path" <<EOF
[Unit]
Description=${BA_SERVICE_DESCRIPTION:-${APP_NAME} service}
Documentation=https://github.com/${GITHUB_REPO}
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
Group=${SERVICE_USER}
WorkingDirectory=${DATA_DIR}
ExecStart="${BIN_PATH}"${BA_SERVICE_ARGS:+ ${BA_SERVICE_ARGS}}
Restart=always
RestartSec=5
StartLimitInterval=60
StartLimitBurst=5
${env_line}
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=strict
ReadWritePaths=${DATA_DIR} ${LOG_DIR}${BA_READWRITE_PATHS:+ ${BA_READWRITE_PATHS}}
StandardOutput=journal
StandardError=journal
SyslogIdentifier=${SERVICE_NAME}
${extra}
[Install]
WantedBy=multi-user.target
EOF
  then
    error "$(t binary_app.error.systemd_unit "$SERVICE_NAME")"
  fi
}

# Run after the unit is written: daemon-reload, enable, start, wait.
ba_start_service() {
  app_check_port_conflict "$PORT"
  if ! command systemctl daemon-reload; then
    error "$(t binary_app.error.systemd_reload "$SERVICE_NAME")"
  fi
  if ! systemctl enable "$SERVICE_NAME" --quiet; then
    warn "$(t binary_app.warn.enable_failed "$SERVICE_NAME" "$SERVICE_NAME")"
  fi
  if systemctl restart "$SERVICE_NAME" && wait_for_service "$SERVICE_NAME" 20; then
    success "$(t binary_app.success.started "$SERVICE_NAME")"
    systemctl status "$SERVICE_NAME" --no-pager -l 2>/dev/null | head -12 | sed 's/^/  /' >&2 || true
    return 0
  fi
  return 1
}

# Default HTTP health check; apps override bapp_health_probe when the service
# exposes a different endpoint or requires other status codes.
bapp_health_probe() {
  local url="${BA_HEALTH_URL:-http://127.0.0.1:${PORT}/}"
  local codes="${BA_HEALTH_CODES:-^(200|301|302)$}"
  local elapsed=0 code
  until code="$(curl -o /dev/null -s -w "%{http_code}" --max-time 5 "$url" 2>/dev/null || echo "000")" \
      && [[ "$code" =~ $codes ]]; do
    sleep 1
    elapsed=$((elapsed + 1))
    [[ $elapsed -ge 15 ]] && break
  done
  if [[ "$code" =~ $codes ]]; then
    success "$(t binary_app.success.health "$code")"
    return 0
  fi
  warn "$(t binary_app.warn.health "$code")"
  warn "$(t binary_app.warn.debug_command "$SERVICE_NAME")"
  return 1
}

# Firewall + logrotate for the service port and log directory.
ba_configure_ops() {
  if [[ "${BA_FIREWALL:-1}" == "1" ]]; then
    app_configure_firewall "$PORT" "binary_app" "$APP_NAME"
  fi
  app_write_logrotate "/etc/logrotate.d/${SERVICE_NAME}" "$LOG_DIR" \
    "binary_app.error.logrotate" "binary_app.success.logrotate"
}

# Print the install summary box (localized, generic fields).
bapp_summary() {
  local version="$1"
  local internal_ip
  local hostname_scan
  hostname_scan="$(hostname -I 2>/dev/null | awk '{print $1}' || true)"
  internal_ip="${hostname_scan:-YOUR_SERVER_IP}"
  echo ""
  echo -e "${BOLD}${GREEN}"
  echo "  =========================================================="
  echo -e "  ${BOLD}$(t binary_app.summary.title_ready)${GREEN}"
  echo "  =========================================================="
  if [[ -n "$DOMAIN" ]]; then
    echo -e "  $(t binary_app.summary.public)  ${CYAN}http://${DOMAIN}${GREEN}"
  fi
  echo -e "  $(t binary_app.summary.internal)  ${CYAN}http://${internal_ip}:${PORT}${GREEN}"
  echo -e "  $(t binary_app.summary.version)  ${YELLOW}${version}${GREEN}"
  echo -e "  $(t binary_app.summary.data_dir)  ${YELLOW}${DATA_DIR}${GREEN}"
  echo -e "  $(t binary_app.summary.log_dir)  ${YELLOW}${LOG_DIR}${GREEN}"
  echo -e "  $(t binary_app.summary.backup_dir)  ${YELLOW}${BACKUP_DIR}${GREEN}"
  if declare -f ba_summary_extra >/dev/null 2>&1; then
    ba_summary_extra
  fi
  echo "  =========================================================="
  echo -e "${NC}"
  echo -e "  ${BOLD}$(t binary_app.summary.management)${NC}"
  echo -e "    ${CYAN}bash $0 status${NC}      - $(t binary_app.summary.status_cmd)"
  echo -e "    ${CYAN}bash $0 update${NC}      - $(t binary_app.summary.update_cmd)"
  echo -e "    ${CYAN}bash $0 backup${NC}      - $(t binary_app.summary.backup_cmd)"
  echo -e "    ${CYAN}bash $0 uninstall${NC}   - $(t binary_app.summary.uninstall_cmd)"
  echo ""
  echo -e "  ${BOLD}$(t binary_app.summary.systemd)${NC}"
  echo -e "    ${CYAN}systemctl status ${SERVICE_NAME}${NC}     $(t binary_app.summary.show_status)"
  echo -e "    ${CYAN}journalctl -u ${SERVICE_NAME} -f${NC}     $(t binary_app.summary.live_logs)"
  echo -e "    ${CYAN}systemctl restart ${SERVICE_NAME}${NC}    $(t binary_app.summary.restart)"
  echo ""
}
bapp_install() {
  show_banner
  bapp_preflight "install"

  step "$(t binary_app.step.latest)"
  bapp_check_net
  info "$(t binary_app.info.query_latest)"
  local latest
  latest="$(ba_latest_version)"
  [[ -n "$latest" ]] || error "$(t binary_app.error.version_failed)"
  success "$(t binary_app.success.latest "${BOLD}${latest}${NC}")"
  step "$(t binary_app.step.deps)"
  if ! apt-get update -qq; then
    error "$(t binary_app.error.apt_update)"
  fi
  local apt_deps="curl ca-certificates"
  if [[ -n "${BA_APT_PACKAGES:-}" ]]; then
    apt_deps="${apt_deps} ${BA_APT_PACKAGES}"
  fi
  # shellcheck disable=SC2086
  if ! apt-get install -y -qq $apt_deps; then
    error "$(t binary_app.error.deps_install)"
  fi
  success "$(t binary_app.success.deps)"
  step "$(t binary_app.step.user_dirs)"
  ba_setup_user_dirs
  step "$(t binary_app.step.download "$BA_ARCH")"
  local tmp_bin old_bin_bak=""
  if ! tmp_bin="$(mktemp "${INSTALL_DIR}/.${BA_BIN_NAME}.tmp.XXXXXX")"; then
    error "$(t binary_app.error.download "$GITHUB_REPO")"
  fi
  local download_url
  download_url="$(ba_download_urls "$latest" | head -1)"
  info "$(t binary_app.info.download_url "$download_url")"
  if ! ba_download_release "$latest" "$tmp_bin"; then
    rm -f "$tmp_bin" 2>/dev/null || true
    error "$(t binary_app.error.download "$download_url")"
  fi
  local stage
  if ! stage="$(mktemp -d "${INSTALL_DIR}/.${BA_BIN_NAME}.stage.XXXXXX")"; then
    rm -f "$tmp_bin" 2>/dev/null || true
    error "$(t binary_app.error.extract)"
  fi
  local candidate
  if ! candidate="$(ba_prepare_binary "$tmp_bin" "$stage")"; then
    rm -f "$tmp_bin" 2>/dev/null || true
    safe_rm_dir "$stage" "binary staging directory" || true
    error "$(t binary_app.error.extract)"
  fi
  bapp_inspect_binary "$candidate"
  if ! mv -f "$candidate" "$tmp_bin"; then
    rm -f "$tmp_bin" 2>/dev/null || true
    safe_rm_dir "$stage" "binary staging directory" || true
    error "$(t binary_app.error.extract)"
  fi
  safe_rm_dir "$stage" "binary staging directory" || true
  if [[ -f "$BIN_PATH" ]]; then
    old_bin_bak="${INSTALL_DIR}/${BA_BIN_NAME}.bak.$(date +%Y%m%d_%H%M%S)"
  fi
  ba_install_binary "$tmp_bin" "$old_bin_bak"
  if [[ -n "$old_bin_bak" ]]; then
    warn "$(t binary_app.warn.old_binary_backup "$(basename "$old_bin_bak")")"
  fi
  if ! chown "${SERVICE_USER}:${SERVICE_USER}" "$BIN_PATH"; then
    error "$(t binary_app.error.dir_owner "${SERVICE_USER}:${SERVICE_USER}" "$BIN_PATH")"
  fi
  success "$(t binary_app.success.binary_verified "$(( $(wc -c < "$BIN_PATH") / 1024 / 1024 ))")"
  if declare -f ba_write_config >/dev/null 2>&1; then
    step "$(t binary_app.step.config)"
    ba_write_config "$latest"
  fi
  step "$(t binary_app.step.systemd)"
  ba_systemd_unit
  success "$(t binary_app.success.systemd "$SERVICE_NAME")"
  if declare -f ba_pre_start >/dev/null 2>&1; then
    ba_pre_start "$latest"
  fi
  step "$(t binary_app.step.firewall)"
  ba_configure_ops
  step "$(t binary_app.step.start)"
  if ba_start_service; then
    INSTALLED_VERSION="$latest"
    app_save_config
  else
    warn "$(t binary_app.warn.start_rollback)"
    if ! systemctl stop "$SERVICE_NAME" 2>/dev/null; then
      warn "$(t binary_app.warn.stop_failed "$SERVICE_NAME")"
    fi
    if ! systemctl disable "$SERVICE_NAME" 2>/dev/null; then
      warn "$(t binary_app.warn.disable_failed "$SERVICE_NAME")"
    fi
    ba_remove_file_or_error "/etc/systemd/system/${SERVICE_NAME}.service" "SERVICE_FILE"
    if ! systemctl daemon-reload 2>/dev/null; then
      warn "$(t binary_app.warn.reload_failed)"
    fi
    if [[ -n "$old_bin_bak" && -f "$old_bin_bak" ]]; then
      app_binary_restore_backup "$old_bin_bak" \
        || error "$(t binary_app.error.install_start_failed "$SERVICE_NAME" "$SERVICE_NAME")"
    else
      ba_remove_file_or_error "$BIN_PATH" "BIN_PATH"
    fi
    error "$(t binary_app.error.install_start_failed "$SERVICE_NAME" "$SERVICE_NAME")"
  fi
  step "$(t binary_app.step.health)"
  bapp_health_probe || true
  bapp_summary "$latest"
}
# Back up DATA_DIR to BACKUP_DIR as <app>_<label>_<timestamp>.tar.gz with
# retention; logs progress to BACKUP_DIR/backup.log.  Returns 0 on success.
_ba_backup() {
  local label="$1"
  local backup_log="${BACKUP_DIR}/backup.log"
  _ba_backup_log() {
    [[ -d "$BACKUP_DIR" ]] || return 1
    printf '%s  %s\n' "$(date '+%F %T')" "$1" >> "$backup_log"
  }
  if ! mkdir -p "$BACKUP_DIR"; then
    warn "$(t binary_app.error.backup_dir_create "$BACKUP_DIR")"
    return 1
  fi
  if [[ ! -d "$DATA_DIR" ]]; then
    _ba_backup_log "$(t binary_app.error.data_missing "$DATA_DIR")"
    warn "$(t binary_app.error.data_missing "$DATA_DIR")"
    return 1
  fi
  local archive archive_tmp
  archive="${BACKUP_DIR}/${APP_ID}_${label}_$(date +%Y%m%d_%H%M%S).tar.gz"
  archive_tmp="${archive}.tmp"
  if tar -czf "$archive_tmp" \
      --exclude="*.log" --exclude="*.log.*" \
      -C "$(dirname "$DATA_DIR")" "$(basename "$DATA_DIR")" >&2; then
    if mv "$archive_tmp" "$archive"; then
      local sz
      sz="$(du -sh "$archive" 2>/dev/null | awk '{print $1}')"
      _ba_backup_log "$(t binary_app.success.backup_done "$archive" "$sz")"
      success "$(t binary_app.success.silent_backup "$archive" "$sz")"
    else
      rm -f "$archive_tmp"
      _ba_backup_log "$(t binary_app.error.backup_failed)"
      warn "$(t binary_app.warn.silent_backup_failed "$BACKUP_DIR")"
      return 1
    fi
  else
    rm -f "$archive_tmp"
    _ba_backup_log "$(t binary_app.error.backup_failed)"
    warn "$(t binary_app.warn.silent_backup_failed "$BACKUP_DIR")"
    return 1
  fi
  _ba_prune_backups
}

_ba_prune_backups() {
  local keep_days="${BACKUP_KEEP_DAYS:-0}"
  [[ "$keep_days" =~ ^[0-9]+$ ]] || keep_days=0
  if [[ "$keep_days" -gt 0 ]]; then
    local cleaned=0 f
    while IFS= read -r -d '' f; do
      if rm -f "$f"; then
        cleaned=$((cleaned + 1))
      else
        warn "$(t binary_app.warn.backup_cleanup_failed "$f")"
      fi
    done < <(find "$BACKUP_DIR" -maxdepth 1 -name "${APP_ID}_*.tar.gz" \
             -mtime "+${keep_days}" -type f -print0 2>/dev/null)
    if [[ "$cleaned" -gt 0 ]]; then
      info "$(t binary_app.info.cleaned_backups "$cleaned" "$keep_days")"
    fi
  fi
}

bapp_backup() {
  show_banner
  bapp_preflight "backup"
  app_load_config _binary_app_derive_paths

  step "$(t binary_app.step.manual_backup)"
  if ! _ba_backup "manual"; then
    error "$(t binary_app.error.backup_failed)"
  fi
  echo ""
  info "$(t binary_app.info.backup_list "$BACKUP_DIR")"
  local f
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    printf '  %s\n' "$f"
  done < <(find "$BACKUP_DIR" -maxdepth 1 -name "${APP_ID}_*.tar.gz" -type f \
           -printf '%T@ %f\n' 2>/dev/null | sort -rn | sed 's/^[0-9.]* //')
  echo ""
}
_ba_prune_old_bins() {
  local -a old_bins=()
  local entry
  while IFS= read -r -d '' entry; do
    old_bins+=("${entry#* }")
  done < <(
    find "$INSTALL_DIR" -maxdepth 1 -name "${BA_BIN_NAME}.bak.*" -type f \
      -printf '%T@ %p\0' 2>/dev/null | sort -z -rn | tail -z -n +4
  )
  if [[ ${#old_bins[@]} -gt 0 ]]; then
    local cleaned=0 bin_path
    for bin_path in "${old_bins[@]}"; do
      if rm -f "$bin_path"; then
        cleaned=$((cleaned + 1))
      else
        warn "$(t binary_app.warn.cleanup_old_failed "$bin_path")"
      fi
    done
    if [[ "$cleaned" -gt 0 ]]; then
      info "$(t binary_app.info.cleaned_old "$cleaned")"
    fi
  fi
}

bapp_update() {
  show_banner
  bapp_preflight "update"
  app_load_config _binary_app_derive_paths

  [[ -x "$BIN_PATH" ]] || error "$(t binary_app.error.not_installed "${APP_NAME:-app}" "$BIN_PATH")"
  step "$(t binary_app.step.check_update)"
  bapp_check_net
  info "$(t binary_app.info.query_latest)"
  local latest current
  latest="$(ba_latest_version)"
  [[ -n "$latest" ]] || error "$(t binary_app.error.version_failed)"
  current="${INSTALLED_VERSION:-unknown}"
  info "$(t binary_app.info.current "${YELLOW}${current}${NC}")"
  info "$(t binary_app.info.github_latest "${YELLOW}${latest}${NC}")"
  if [[ "$current" == "$latest" ]]; then
    success "$(t binary_app.success.already_latest "$latest")"
    exit 0
  fi
  local pre_state
  pre_state="$(systemctl is-active "$SERVICE_NAME" 2>/dev/null || echo "inactive")"
  if [[ "$pre_state" == "failed" ]]; then
    warn "$(t binary_app.warn.pre_failed_state)"
    warn "$(t binary_app.warn.pre_failed_debug "$SERVICE_NAME")"
  fi
  step "$(t binary_app.step.pre_backup)"
  if ! _ba_backup "pre-update"; then
    warn "$(t binary_app.warn.pre_backup_failed)"
  fi
  step "$(t binary_app.step.download_update "$current" "$latest")"
  local tmp_bin download_url
  download_url="$(ba_download_urls "$latest" | head -1)"
  info "$(t binary_app.info.download_url "$download_url")"
  if ! tmp_bin="$(mktemp "${INSTALL_DIR}/.${BA_BIN_NAME}.tmp.XXXXXX")"; then
    error "$(t binary_app.error.download "$GITHUB_REPO")"
  fi
  if ! ba_download_release "$latest" "$tmp_bin"; then
    rm -f "$tmp_bin" 2>/dev/null || true
    error "$(t binary_app.error.download "$download_url")"
  fi
  local stage candidate
  if ! stage="$(mktemp -d "${INSTALL_DIR}/.${BA_BIN_NAME}.stage.XXXXXX")"; then
    rm -f "$tmp_bin" 2>/dev/null || true
    error "$(t binary_app.error.extract)"
  fi
  if ! candidate="$(ba_prepare_binary "$tmp_bin" "$stage")"; then
    rm -f "$tmp_bin" 2>/dev/null || true
    safe_rm_dir "$stage" "binary staging directory" || true
    error "$(t binary_app.error.extract)"
  fi
  bapp_inspect_binary "$candidate"
  if ! mv -f "$candidate" "$tmp_bin"; then
    rm -f "$tmp_bin" 2>/dev/null || true
    safe_rm_dir "$stage" "binary staging directory" || true
    error "$(t binary_app.error.extract)"
  fi
  safe_rm_dir "$stage" "binary staging directory" || true
  step "$(t binary_app.step.replace_restart)"
  local bak_path
  bak_path="${INSTALL_DIR}/${BA_BIN_NAME}.bak.$(date +%Y%m%d_%H%M%S)"
  if ! app_binary_backup_current "$bak_path"; then
    error "$(t binary_app.error.binary_install "$BIN_PATH")"
  fi
  info "$(t binary_app.info.old_binary "$bak_path")"
  if ! systemctl stop "$SERVICE_NAME" 2>/dev/null; then
    rm -f "$tmp_bin" 2>/dev/null || true
    error "$(t binary_app.error.stop_service_failed "$SERVICE_NAME")"
  fi
  ba_install_binary "$tmp_bin"
  if ! command systemctl daemon-reload; then
    error "$(t binary_app.error.systemd_reload "$SERVICE_NAME")"
  fi
  if systemctl start "$SERVICE_NAME" && wait_for_service "$SERVICE_NAME" 20; then
    success "$(t binary_app.success.update_started)"
    INSTALLED_VERSION="$latest"
    app_save_config
    _ba_prune_old_bins
    bapp_health_probe || true
    echo ""
    echo -e "  ${BOLD}${GREEN}$(t binary_app.info.github_latest "$latest")${NC}"
    echo ""
  else
    warn "$(t binary_app.warn.update_start_failed "$current")"
    if ! systemctl stop "$SERVICE_NAME" 2>/dev/null; then
      error "$(t binary_app.error.rollback_stop_failed "$SERVICE_NAME")"
    fi
    if ! app_binary_restore_backup "$bak_path"; then
      warn "$(t binary_app.warn.rollback_start_failed "$SERVICE_NAME")"
      error "$(t binary_app.error.update_failed "$current")"
    fi
    if systemctl start "$SERVICE_NAME"; then
      if wait_for_service "$SERVICE_NAME" 15; then
        success "$(t binary_app.success.rollback "$current")"
      else
        warn "$(t binary_app.warn.rollback_start_failed "$SERVICE_NAME")"
      fi
    else
      warn "$(t binary_app.warn.rollback_start_failed "$SERVICE_NAME")"
    fi
    error "$(t binary_app.error.update_failed "$current")"
  fi
}
bapp_status() {
  show_banner
  bapp_preflight "status"
  app_load_config _binary_app_derive_paths
  step "$(t status.title)"
  if [[ -f "$CONF_FILE" ]]; then
    printf '%s\n' "$(t binary_app.status.service "$SERVICE_NAME" "$(service_status_label "$SERVICE_NAME")")"
    printf '%s\n' "$(t binary_app.status.version "${INSTALLED_VERSION:-unknown}")"
    printf '%s\n' "$(t binary_app.status.health_url "${BA_HEALTH_URL:-http://127.0.0.1:${PORT}/}")"
    printf '\n%s\n' "$(t binary_app.status.paths)"
    local path
    for path in "$BIN_PATH" "$DATA_DIR" "$LOG_DIR" "$BACKUP_DIR"; do
      if [[ -e "$path" ]]; then
        printf '  [ok] %s\n' "$path"
      else
        printf '  [--] %s\n' "$path"
      fi
    done
    if declare -f ba_status_extra >/dev/null 2>&1; then
      ba_status_extra
    fi
  else
    info "$(t binary_app.status.not_installed)"
  fi
}

bapp_uninstall() {
  show_banner
  bapp_preflight "uninstall"
  app_load_config _binary_app_derive_paths

  local confirm delete_data=false delete_backup=false
  step "$(t binary_app.step.uninstall "$APP_NAME")"
  if deploy_assume_yes; then
    confirm="YES"
  else
    prompt "$(t binary_app.prompt.continue)"
    read -r confirm
  fi
  [[ "$confirm" == "YES" ]] || { info "$(t binary_app.info.cancelled)"; exit 0; }
  if deploy_assume_yes; then
    deploy_env_truthy DEPLOY_DELETE_DATA && delete_data=true
    deploy_env_truthy DEPLOY_DELETE_BACKUP && delete_backup=true
  else
    prompt "$(t binary_app.prompt.delete_data "$DATA_DIR")"
    local answer
    read -r answer
    [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]] && delete_data=true
    prompt "$(t binary_app.prompt.delete_backup "$BACKUP_DIR")"
    read -r answer
    [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]] && delete_backup=true
  fi
  info "$(t binary_app.info.stop_disable "$SERVICE_NAME")"
  if ! systemctl stop "$SERVICE_NAME" 2>/dev/null; then
    if systemctl is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
      error "$(t binary_app.error.uninstall_stop_failed "$SERVICE_NAME")"
    fi
    warn "$(t binary_app.warn.uninstall_stop_failed "$SERVICE_NAME")"
  fi
  if ! systemctl disable "$SERVICE_NAME" 2>/dev/null; then
    warn "$(t binary_app.warn.uninstall_disable_failed "$SERVICE_NAME")"
  fi
  ba_remove_file_or_error "/etc/systemd/system/${SERVICE_NAME}.service" "SERVICE_FILE"
  if ! command systemctl daemon-reload; then
    error "$(t binary_app.error.systemd_reload "$SERVICE_NAME")"
  fi
  success "$(t binary_app.success.removed_systemd)"
  ba_remove_file_or_error "$BIN_PATH" "BIN_PATH"
  require_safe_path "INSTALL_DIR" "$INSTALL_DIR"
  local cleanup_path
  while IFS= read -r -d '' cleanup_path; do
    if ! rm -f "$cleanup_path"; then
      warn "$(t binary_app.warn.cleanup_old_failed "$cleanup_path")"
    fi
  done < <(find "$INSTALL_DIR" -maxdepth 1 \( -name "${BA_BIN_NAME}.bak.*" \
           -o -name ".${BA_BIN_NAME}.tmp.*" -o -name ".${BA_BIN_NAME}.stage.*" \) \
           -type f -print0 2>/dev/null)
  success "$(t binary_app.success.removed_binary)"
  ba_remove_file_or_error "/etc/logrotate.d/${SERVICE_NAME}" "LOGROTATE_FILE"
  if [[ "${BA_USE_ENV_FILE:-0}" == "1" ]]; then
    ba_remove_file_or_error "$ENV_FILE" "ENV_FILE"
  fi
  if declare -f ba_uninstall_extra >/dev/null 2>&1; then
    ba_uninstall_extra
  fi
  ba_remove_file_or_error "$CONF_FILE" "CONF_FILE"
  success "$(t binary_app.success.removed_config)"
  if [[ -n "${LOG_DIR:-}" && "$LOG_DIR" != "." && "$LOG_DIR" != "/" && -d "$LOG_DIR" ]]; then
    ba_remove_dir_or_error "$LOG_DIR" "LOG_DIR"
  else
    warn "$(t binary_app.warn.log_path "${LOG_DIR:-unset}")"
  fi
  if $delete_data; then
    ba_remove_dir_or_error "$DATA_DIR" "DATA_DIR"
    if [[ -d "$INSTALL_DIR" ]] && [[ -z "$(ls -A "$INSTALL_DIR" 2>/dev/null)" ]]; then
      if ! safe_rm_dir "$INSTALL_DIR" "INSTALL_DIR"; then
        warn "$(t binary_app.warn.cleanup_install_failed "$INSTALL_DIR")"
      else
        success "$(t binary_app.success.cleaned_install "$INSTALL_DIR")"
      fi
    fi
  else
    info "$(t binary_app.info.kept_data "$DATA_DIR")"
  fi
  if $delete_backup; then
    ba_remove_dir_or_error "$BACKUP_DIR" "BACKUP_DIR"
  else
    info "$(t binary_app.info.kept_backup "$BACKUP_DIR")"
  fi
  if $delete_data && id "$SERVICE_USER" >/dev/null 2>&1; then
    if userdel "$SERVICE_USER" 2>/dev/null; then
      success "$(t binary_app.success.deleted_user "$SERVICE_USER")"
    else
      warn "$(t binary_app.warn.delete_user "$SERVICE_USER")"
    fi
  fi
  echo ""
  echo -e "${BOLD}${GREEN}  $(t binary_app.success.uninstalled "$APP_NAME")${NC}"
  if ! $delete_data; then
    echo -e "  ${YELLOW}[hint]${NC} $(t binary_app.hint.data_kept "$DATA_DIR")"
    echo -e "  ${YELLOW}[hint]${NC} $(t binary_app.hint.remove_data "$DATA_DIR")"
  fi
  if ! $delete_backup; then
    echo -e "  ${YELLOW}[hint]${NC} $(t binary_app.hint.backup_kept "$BACKUP_DIR")"
  fi
  echo ""
}


