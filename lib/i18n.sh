#!/usr/bin/env bash

deploy_lang="${DEPLOY_LANG:-${LANGUAGE:-${LC_ALL:-${LC_MESSAGES:-${LANG:-en}}}}}"
deploy_lang="${deploy_lang%%.*}"
deploy_lang="${deploy_lang%%_*}"

case "${deploy_lang,,}" in
  zh|cn) DEPLOY_LANG="zh" ;;
  *) DEPLOY_LANG="en" ;;
esac

declare -gA __DEPLOY_I18N_EN=()
declare -gA __DEPLOY_I18N_ZH=()

i18n_register() {
  local key="$1"
  local en="$2"
  local zh="${3:-$2}"
  __DEPLOY_I18N_EN["$key"]="$en"
  __DEPLOY_I18N_ZH["$key"]="$zh"
}

i18n_register_many() {
  while [[ $# -gt 0 ]]; do
    if [[ $# -lt 3 ]]; then
      printf 'i18n_register_many requires key/en/zh triples\n' >&2
      return 1
    fi
    i18n_register "$1" "$2" "$3"
    shift 3
  done
}

i18n_print() {
  local text="$1"
  shift || true
  if [[ $# -gt 0 ]]; then
    printf "$text" "$@"
  else
    printf '%s' "$text"
  fi
}

i18n_register action.backup "backup" "backup"
i18n_register action.doctor "doctor" "doctor"
i18n_register action.install "install" "install"
i18n_register action.restore "restore" "restore"
i18n_register action.status "status" "status"
i18n_register action.uninstall "uninstall" "uninstall"
i18n_register action.update "update" "update"
i18n_register action.verify "verify" "verify"
i18n_register backup.verify.step "Verify backup integrity" "校验备份完整性"
i18n_register backup.verify.verified "Backup verified: %s (sha256 %s)" "备份校验通过：%s（sha256 %s）"
i18n_register backup.verify.failed "Backup verification FAILED: %s" "备份校验失败：%s"
i18n_register backup.verify.unverified "No integrity metadata for: %s (created before manifest support; run a new backup to upgrade it)" "缺少完整性元数据：%s（创建于 manifest 支持之前；请重新备份以升级）"
i18n_register backup.verify.no_backups "No backup archive found in %s" "未在 %s 中找到备份归档"
i18n_register backup.restore.step "Restore from backup" "从备份恢复"
i18n_register backup.restore.using "Restoring from backup: %s" "正在从备份恢复：%s"
i18n_register backup.restore.no_backups "No backup archive found in %s" "未在 %s 中找到备份归档"
i18n_register backup.restore.invalid_archive "Invalid or unsafe backup archive: %s" "备份归档无效或不安全：%s"
i18n_register backup.restore.stop_failed "Could not stop service %s before restore; aborting without changes." "停止服务 %s 失败，已中止且未做任何更改。"
i18n_register backup.restore.restored "Data restored from %s; service restarted." "数据已从 %s 恢复，服务已重启。"
i18n_register backup.restore.start_failed_rollback "Service failed to start after restore; rolling back to previous data." "恢复后服务启动失败，正在回滚到先前数据。"
i18n_register backup.restore.rollback_done "Rollback complete; the previous data directory is intact." "回滚完成，原数据目录保持不变。"
i18n_register backup.restore.rollback_failed "Rollback FAILED; the staged data remains at %s for manual recovery." "回滚失败，暂存数据保留在 %s 以便手动恢复。"
i18n_register notify.warn.untrusted_config "Notification config failed the trust gate; notifications skipped." "通知配置未通过信任门检查，已跳过通知。"
i18n_register notify.warn.no_backend "Notification backend is not set to ntfy or gotify; notification skipped." "通知后端不是 ntfy 或 gotify，已跳过通知。"
i18n_register notify.warn.no_url "Notification URL is empty; notification skipped." "通知服务地址为空，已跳过通知。"
i18n_register notify.warn.curl_missing "curl is not available; notification skipped." "curl 不可用，已跳过通知。"
i18n_register notify.warn.disabled "Notifications are disabled; test skipped." "通知已禁用，测试已跳过。"
i18n_register notify.info.sent "Notification sent." "通知已发送。"
i18n_register notify.warn.send_failed "Notification delivery failed (HTTP %s); continuing." "通知发送失败（HTTP %s），继续主流程。"
i18n_register notify.usage "Usage: sudo bash %s notify-config [--enable|--disable] [--backend ntfy|gotify] [--url URL] [--topic TOPIC] [--token TOKEN] [--test] [--clear]" "用法：sudo bash %s notify-config [--enable|--disable] [--backend ntfy|gotify] [--url 地址] [--topic 主题] [--token 令牌] [--test] [--clear]"
i18n_register notify.config.saved "Notification configuration saved: %s" "通知配置已保存：%s"
i18n_register notify.test.sent_ok "Test notification delivered; configuration saved." "测试通知已送达，配置已保存。"
i18n_register notify.test.failed "Test notification failed; configuration not saved." "测试通知发送失败，配置未保存。"
i18n_register notify.config.cleared "Notification configuration removed: %s" "通知配置已删除：%s"
i18n_register schedule.usage "Usage: sudo bash %s schedule [--enable|--disable] [--mode update-all|check-only] [--at 'HH:MM' | OnCalendar | 'cron expr'] [--include app1,app2] [--retries N] [--backoff SECONDS]; sudo bash %s unschedule|status|run|schedule-run" "用法：sudo bash %s schedule [--enable|--disable] [--mode update-all|check-only] [--at '时:分' | OnCalendar | cron 表达式] [--include 应用1,应用2] [--retries N] [--backoff 秒]；sudo bash %s unschedule|status|run|schedule-run"
i18n_register schedule.info.saved "Schedule configuration saved." "定时计划配置已保存。"
i18n_register schedule.info.removed "Schedule removed (timer/cron and config cleaned up)." "定时计划已移除（timer/cron 与配置已清理）。"
i18n_register schedule.warn.retry "Scheduled batch failed (exit %s); retry %s of %s after backoff." "定时批次失败（退出码 %s），退避后进行第 %s/%s 次重试。"
i18n_register migrate.usage "Usage: sudo bash %s export [--output PATH] [--redact]; sudo bash %s import --input PATH" "用法：sudo bash %s export [--output 路径] [--redact]；sudo bash %s import --input 路径"
i18n_register migrate.error.nothing_to_export "No deployment or notification configs found to export." "未找到可导出的部署或通知配置。"
i18n_register migrate.error.archive_missing "Migration archive not found: %s" "迁移归档不存在：%s"
i18n_register migrate.info.exported "Migration archive written: %s (sha256 sidecar included)" "迁移归档已生成：%s（含 sha256 sidecar）"
i18n_register migrate.info.next_steps "Replicate each app's backups to the new machine, then run import there and use per-app restore." "请将各应用备份复制到新机器，在新机器执行 import 后用各应用 restore 恢复数据。"
i18n_register migrate.info.imported "Imported %s config file(s); notification and schedule settings restored." "已导入 %s 个配置文件；通知与定时设置已恢复。"
i18n_register migrate.info.manual_steps "Binaries/data are not migrated automatically: install apps, replicate backups, then run restore per app." "二进制与数据不会自动迁移：先安装应用、复制备份，再逐应用执行 restore。"
i18n_register compose.error.docker_missing "Docker is not installed; the compose stack cannot run." "未安装 Docker，无法运行 Compose 应用栈。"
i18n_register compose.error.runtime_missing "Neither 'docker compose' nor 'docker-compose' is available." "'docker compose' 与 'docker-compose' 均不可用。"
i18n_register compose.error.project_missing "Compose project file not found: %s" "Compose 项目文件不存在：%s"
i18n_register common.choose_action "Choose an action:" "请选择操作："
i18n_register common.invalid_choice "Invalid choice: %s" "无效选项：%s"
i18n_register common.no_argument_menu "No argument opens the interactive menu." "不带参数则打开交互式菜单。"
i18n_register common.quit "quit" "退出"
i18n_register common.selection_prompt "Selection [1-7/q]:" "请输入选项 [1-7/q]："
i18n_register common.usage "Usage: sudo bash %s [install, update, backup, restore, verify, status, status-json, doctor, uninstall]" "用法：sudo bash %s [install, update, backup, restore, verify, status, status-json, doctor, uninstall]"
i18n_register common.help_config_keys "Configuration keys (current values):" "配置键（当前值）："
i18n_register common.help_env_hint "Override any key by exporting it as an environment variable, or pass --dry-run before an action to preview it." "可通过环境变量覆盖任意键；在动作前加 --dry-run 可预览将执行的操作。"
i18n_register common.dry_run_install "Dry run: would install %s with the configuration below. No changes were made." "试运行：将使用以下配置安装 %s。未做任何更改。"
i18n_register common.dry_run_update "Dry run: would update %s to the latest version. No changes were made." "试运行：将把 %s 更新到最新版本。未做任何更改。"
i18n_register common.dry_run_backup "Dry run: would create a backup for %s. No changes were made." "试运行：将为 %s 创建备份。未做任何更改。"
i18n_register common.dry_run_uninstall "Dry run: would uninstall %s (config and data are kept unless you answer the prompts). No changes were made." "试运行：将卸载 %s（除非在提示中确认，否则保留配置和数据）。未做任何更改。"
i18n_register common.dry_run_action "Dry run: would run '%s %s'. No changes were made." "试运行：将执行 '%s %s'。未做任何更改。"
i18n_register common.dry_run_config "Planned configuration:" "计划使用的配置："
i18n_register common.dry_run_requires_action "Dry run requires an action: %s --dry-run install|update|backup|uninstall" "试运行需要指定动作：%s --dry-run install|update|backup|uninstall"
i18n_register common.default_site_backed_up "Moved the default Nginx site out of the way (restored on uninstall): %s" "已将默认 Nginx 站点移开（卸载时恢复）：%s"
i18n_register common.default_site_backup_failed "Failed to move the default Nginx site %s; the new site cannot take over port 80." "无法移开默认 Nginx 站点 %s；新站点无法接管 80 端口。"
i18n_register common.default_site_restored "Restored the default Nginx site: %s" "已恢复默认 Nginx 站点：%s"
i18n_register common.default_site_restore_failed "Failed to restore the default Nginx site from %s to %s. Restore it manually if needed." "无法将默认 Nginx 站点从 %s 恢复到 %s。如需恢复请手动操作。"
i18n_register common.config_exported "Deployment config exported before uninstall: %s" "卸载前已导出部署配置：%s"
i18n_register common.config_export_failed "Could not export deployment config before uninstall: %s" "无法在卸载前导出部署配置：%s"
i18n_register common.config_export_restore_hint "To restore this deployment later: copy %s back to the app config path and reinstall." "如需恢复此部署：将 %s 复制回应用配置路径后重新安装即可。"
i18n_register config.loaded "Loaded deployment config: %s" "已加载部署记录：%s"
i18n_register config.saved "Saved deployment config: %s" "部署配置已持久化：%s"
i18n_register error.command_required "Required command is missing: %s" "缺少必要命令：%s"
i18n_register error.config_permission "Refusing to load unsafe config permissions: %s" "拒绝加载权限不安全的配置文件：%s"
i18n_register error.config_owner "Refusing to load config not owned by root: %s" "拒绝加载非 root 拥有的配置文件：%s"
i18n_register error.config_write "Failed to save deployment config: %s" "部署配置保存失败：%s"
i18n_register error.tmpdir "Failed to create a private temporary file; aborting." "无法创建私有临时文件，已中止。"
i18n_register error.lock_failed "Another deployment process is running: %s" "已有部署进程正在运行：%s"
i18n_register error.root_required "Please run as root: sudo bash %s %s" "请使用 root 权限运行：sudo bash %s %s"
i18n_register error.unsupported_action "%s does not support %s yet." "%s 暂不支持 %s。"
i18n_register error.unsafe_path "Unsafe path for %s: %s" "%s 的路径不安全：%s"
i18n_register error.port_invalid "%s is invalid: '%s'. Must be a port between 1 and 65535." "%s 无效：'%s'，请输入 1-65535 之间的端口号。"
i18n_register error.bool_invalid "%s is invalid: '%s'. Use true/false, yes/no, on/off, or 1/0." "%s 无效：'%s'，请输入 true/false、yes/no、on/off 或 1/0。"
i18n_register error.domain_invalid "%s is invalid: '%s'. Use a DNS name like app.example.com, or leave it empty." "%s 无效：'%s'，请使用类似 app.example.com 的域名，或留空。"
i18n_register error.system_name_invalid "%s is invalid: '%s'. Use a Linux user/group style name: letters, numbers, underscore, or dash; start with a letter or underscore." "%s 无效：'%s'，请使用 Linux 用户/组风格名称：字母、数字、下划线或短横线，并以字母或下划线开头。"
i18n_register error.systemd_name_invalid "%s is invalid: '%s'. Use a systemd-safe unit name with letters, numbers, dot, underscore, at-sign, or dash only." "%s 无效：'%s'，请使用 systemd 安全名称，仅包含字母、数字、点、下划线、@ 或短横线。"
i18n_register error.github_repo_invalid "%s is invalid: '%s'. Use owner/repository with GitHub-safe name characters." "%s 无效：'%s'，请使用 owner/repository 格式，并仅包含 GitHub 安全名称字符。"
i18n_register error.git_ref_invalid "%s is invalid: '%s'. Use a simple branch/tag ref without spaces, shell metacharacters, '..', or '@{'." "%s 无效：'%s'，请使用简单分支/标签引用，不包含空格、shell 特殊字符、'..' 或 '@{'。"
i18n_register error.db_identifier_invalid "%s is invalid: '%s'. Use a database identifier with letters, numbers, or underscore; start with a letter or underscore." "%s 无效：'%s'，请使用数据库标识符：字母、数字或下划线，并以字母或下划线开头。"
i18n_register error.email_invalid "%s is invalid: '%s'. Use a plain email address without spaces or shell metacharacters." "%s 无效：'%s'，请使用不含空格或 shell 特殊字符的邮箱地址。"
i18n_register error.url_invalid "%s is invalid: '%s'. Use an http(s) URL without spaces or shell metacharacters." "%s 无效：'%s'，请使用不含空格或 shell 特殊字符的 http(s) URL。"
i18n_register error.https_url_invalid "%s is invalid: '%s'. Use an https URL without spaces or shell metacharacters." "%s 无效：'%s'，请使用不含空格或 shell 特殊字符的 https URL。"
i18n_register error.goproxy_invalid "%s is invalid: '%s'. Use http(s) proxy URLs plus optional direct/off entries, separated by comma or pipe." "%s 无效：'%s'，请使用 http(s) 代理 URL，可包含 direct/off，并用逗号或竖线分隔。"
i18n_register error.image_repo_invalid "%s is invalid: '%s'. Use a container image repository name without tag or digest." "%s 无效：'%s'，请使用不含标签或摘要的容器镜像仓库名称。"
i18n_register error.image_tag_invalid "%s is invalid: '%s'. Use a container image tag without spaces, slash, or shell metacharacters." "%s 无效：'%s'，请使用不含空格、斜杠或 shell 特殊字符的容器镜像标签。"
i18n_register error.sha256_invalid "%s is invalid: '%s'. Use exactly 64 hexadecimal characters." "%s 无效：'%s'，请使用正好 64 个十六进制字符。"
i18n_register error.release_version_invalid "%s is invalid: '%s'. Use a release version like 2024.6.2 without spaces, slash, or shell metacharacters." "%s 无效：'%s'，请使用类似 2024.6.2 的发布版本号，不包含空格、斜杠或 shell 特殊字符。"
i18n_register doctor.command_missing "Missing command: %s" "缺少命令：%s"
i18n_register doctor.command_ok "Command available: %s" "命令可用：%s"
i18n_register doctor.config_missing "Config file not found yet: %s" "尚未找到配置文件：%s"
i18n_register doctor.config_mode_bad "Config file permissions are too open (%s): %s" "配置文件权限过于宽松（%s）：%s"
i18n_register doctor.config_ok "Config file looks safe: %s" "配置文件安全检查通过：%s"
i18n_register doctor.config_owner_bad "Config file owner is not root (%s): %s" "配置文件属主不是 root（当前：%s）：%s"
i18n_register doctor.config_parse_bad "Saved config could not be parsed or validated: %s" "已保存配置无法解析或校验失败：%s"
i18n_register doctor.config_parse_ok "Saved config parsed and validated: %s" "已保存配置解析和校验通过：%s"
i18n_register doctor.done_ok "Doctor checks completed without blocking issues." "诊断完成，未发现阻塞性问题。"
i18n_register doctor.done_warn "Doctor checks completed with %s blocking issue(s) and %s warning(s)." "诊断完成，发现 %s 个阻塞问题和 %s 个警告。"
i18n_register doctor.root_ok "Running as root." "当前以 root 运行。"
i18n_register doctor.root_warn "Running without root; service and config checks may be incomplete." "当前不是 root，服务和配置检查可能不完整。"
i18n_register doctor.service_active "Service is active: %s" "服务正在运行：%s"
i18n_register doctor.service_disabled "Service is not enabled on boot: %s" "服务未设置开机自启：%s"
i18n_register doctor.service_enabled "Service is enabled on boot: %s" "服务已设置开机自启：%s"
i18n_register doctor.service_inactive "Service is not active: %s" "服务未运行：%s"
i18n_register doctor.service_unit_missing "systemd unit was not found: %s.service" "未找到 systemd 单元：%s.service"
i18n_register doctor.systemctl_missing "systemctl is not available; skipping service checks." "systemctl 不可用，跳过服务检查。"
i18n_register doctor.title "Deployment doctor" "部署诊断"
i18n_register doctor.config_diff_step "Comparing saved config with current values" "对比已保存配置与当前值"
i18n_register doctor.config_diff "Config drift: %s changed from '%s' to '%s'" "配置漂移：%s 由 '%s' 变为 '%s'"
i18n_register doctor.config_diff_secret "Config drift: %s changed (value hidden)" "配置漂移：%s 已变更（值已隐藏）"
i18n_register doctor.config_diff_none "No configuration drift detected." "未检测到配置漂移。"
i18n_register menu.backup_desc "create a manual backup" "创建手动备份"
i18n_register menu.doctor_desc "run non-destructive diagnostics" "执行非破坏性诊断"
i18n_register menu.install_desc "full install or redeploy" "完整安装或重新部署"
i18n_register menu.restore_desc "restore from a backup" "从备份恢复"
i18n_register menu.status_desc "show service and runtime status" "查看服务和运行状态"
i18n_register menu.uninstall_desc "remove service and related files" "卸载服务和相关文件"
i18n_register menu.update_desc "update to the latest available version" "更新到可用的最新版本"
i18n_register manager.app_file_missing "App definition file not found: %s" "应用定义文件不存在：%s"
i18n_register manager.app_definition_missing "Bundled app definition not found: %s" "内置应用定义不存在：%s"
i18n_register manager.available_apps "Available apps: %s" "可用应用：%s"
i18n_register manager.choose_app "Choose an application:" "请选择应用："
i18n_register manager.description "Central deployment scheduler for all bundled application scripts." "所有内置应用部署脚本的中央统一调度器。"
i18n_register manager.invalid_app "Unknown application: %s" "未知应用：%s"
i18n_register manager.selection_prompt "Application [number/name/q]:" "请输入应用 [序号/名称/q]："
i18n_register manager.status_all "all application status" "全部应用状态"
i18n_register manager.problems "problems only" "仅查看异常"
i18n_register manager.check_updates "check application updates" "检查应用更新"
i18n_register manager.check_self_update "check framework updates" "检查中控更新"
i18n_register manager.title "Deployment Scheduler" "部署调度器"
i18n_register manager.usage "Usage: sudo bash %s <app> [install, update, backup, restore, verify, status, status-json, doctor, uninstall]" "用法：sudo bash %s <应用> [install, update, backup, restore, verify, status, status-json, doctor, uninstall]"
i18n_register manager.usage_central "Central commands: status-all, backup-all, update-all, check-update, notify-config, schedule, unschedule, export, import, fleet, list, self-version, self-update" "中央命令：status-all、backup-all、update-all、check-update、notify-config、schedule、unschedule、export、import、fleet、list、self-version、self-update"
i18n_register manager.usage_examples "Examples: sudo bash %s newapi install; sudo bash %s vaultwarden doctor; sudo bash %s list" "示例：sudo bash %s newapi install；sudo bash %s vaultwarden doctor；sudo bash %s list"
i18n_register status.active "active" "运行中"
i18n_register status.inactive "inactive" "未运行"
i18n_register status.unknown "unknown" "未知"
i18n_register warn.config_invalid_key "Ignoring invalid config key: %s" "已忽略非法配置键：%s"
i18n_register warn.config_reserved_key "Refusing to load reserved config key: %s" "已拒绝加载保留配置键：%s"
i18n_register warn.config_owner "%s owner is not root (%s); ignoring it" "%s 属主不是 root（当前：%s），已忽略"
i18n_register warn.config_permission "%s permissions are too open (%s); ignoring it" "%s 权限过于宽松（%s），已忽略"
i18n_register warn.config_unknown_key "Ignoring unknown config key: %s" "已忽略未知配置键：%s"
i18n_register warn.port_in_use "Port %s is already in use by %s." "端口 %s 已被 %s 占用。"
i18n_register warn.port_release_hint "If this is not the application you are deploying, free the port first or the service will fail to bind." "若非你要部署的应用，请先释放端口，否则服务将无法绑定。"
i18n_register warn.port_conflict_abort "Aborting before installation because DEPLOY_FAIL_ON_PORT_CONFLICT=1 is set. Free the port or unset the variable to proceed." "因已设置 DEPLOY_FAIL_ON_PORT_CONFLICT=1，将在安装前中止。请先释放端口，或取消该变量后继续。"

t() {
  local key="$1"
  shift || true
  if [[ "$DEPLOY_LANG" == "zh" && -v "__DEPLOY_I18N_ZH[$key]" ]]; then
    i18n_print "${__DEPLOY_I18N_ZH[$key]}" "$@"
    return 0
  fi
  if [[ -v "__DEPLOY_I18N_EN[$key]" ]]; then
    i18n_print "${__DEPLOY_I18N_EN[$key]}" "$@"
    return 0
  fi
  # Unregistered key: surface the key itself so a missing registration is
  # obvious instead of silently showing an empty string. Every framework key
  # is registered when i18n.sh is sourced; apps register their own keys.
  i18n_print "$key" "$@"
}
