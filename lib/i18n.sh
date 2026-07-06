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

__deploy_i18n_message() {
  local key="$1"
  case "$key" in
    action.backup) echo "backup|backup" ;;
    action.install) echo "install|install" ;;
    action.restore) echo "restore|restore" ;;
    action.status) echo "status|status" ;;
    action.uninstall) echo "uninstall|uninstall" ;;
    action.update) echo "update|update" ;;
    common.choose_action) echo "Choose an action:|请选择操作：" ;;
    common.invalid_choice) echo "Invalid choice: %s|无效选项：%s" ;;
    common.no_argument_menu) echo "No argument opens the interactive menu.|不带参数则打开交互式菜单。" ;;
    common.quit) echo "quit|退出" ;;
    common.selection_prompt) echo "Selection [1-6/q]:|请输入选项 [1-6/q]：" ;;
    common.usage) echo "Usage: sudo bash %s [install|update|backup|restore|status|uninstall]|用法：sudo bash %s [install|update|backup|restore|status|uninstall]" ;;
    config.loaded) echo "Loaded deployment config: %s|已加载部署记录：%s" ;;
    config.saved) echo "Saved deployment config: %s|部署配置已持久化：%s" ;;
    error.command_required) echo "Required command is missing: %s|缺少必要命令：%s" ;;
    error.config_permission) echo "Refusing to load unsafe config permissions: %s|拒绝加载权限不安全的配置文件：%s" ;;
    error.config_owner) echo "Refusing to load config not owned by root: %s|拒绝加载非 root 拥有的配置文件：%s" ;;
    error.config_write) echo "Failed to save deployment config: %s|部署配置保存失败：%s" ;;
    error.lock_failed) echo "Another deployment process is running: %s|已有部署进程正在运行：%s" ;;
    error.root_required) echo "Please run as root: sudo bash %s %s|请使用 root 权限运行：sudo bash %s %s" ;;
    error.unsupported_action) echo "%s does not support %s yet.|%s 暂不支持 %s。" ;;
    error.unsafe_path) echo "Unsafe path for %s: %s|%s 的路径不安全：%s" ;;
    error.port_invalid) echo "%s is invalid: '%s'. Must be a port between 1 and 65535.|%s 无效：'%s'，请输入 1-65535 之间的端口号。" ;;
    error.bool_invalid) echo "%s is invalid: '%s'. Use true/false, yes/no, on/off, or 1/0.|%s 无效：'%s'，请输入 true/false、yes/no、on/off 或 1/0。" ;;
    error.domain_invalid) echo "%s is invalid: '%s'. Use a DNS name like app.example.com, or leave it empty.|%s 无效：'%s'，请使用类似 app.example.com 的域名，或留空。" ;;
    error.system_name_invalid) echo "%s is invalid: '%s'. Use a Linux user/group style name: letters, numbers, underscore, or dash; start with a letter or underscore.|%s 无效：'%s'，请使用 Linux 用户/组风格名称：字母、数字、下划线或短横线，并以字母或下划线开头。" ;;
    error.systemd_name_invalid) echo "%s is invalid: '%s'. Use a systemd-safe unit name with letters, numbers, dot, underscore, at-sign, or dash only.|%s 无效：'%s'，请使用 systemd 安全名称，仅包含字母、数字、点、下划线、@ 或短横线。" ;;
    error.github_repo_invalid) echo "%s is invalid: '%s'. Use owner/repository with GitHub-safe name characters.|%s 无效：'%s'，请使用 owner/repository 格式，并仅包含 GitHub 安全名称字符。" ;;
    error.git_ref_invalid) echo "%s is invalid: '%s'. Use a simple branch/tag ref without spaces, shell metacharacters, '..', or '@{'.|%s 无效：'%s'，请使用简单分支/标签引用，不包含空格、shell 特殊字符、'..' 或 '@{'。" ;;
    error.db_identifier_invalid) echo "%s is invalid: '%s'. Use a database identifier with letters, numbers, or underscore; start with a letter or underscore.|%s 无效：'%s'，请使用数据库标识符：字母、数字或下划线，并以字母或下划线开头。" ;;
    error.email_invalid) echo "%s is invalid: '%s'. Use a plain email address without spaces or shell metacharacters.|%s 无效：'%s'，请使用不含空格或 shell 特殊字符的邮箱地址。" ;;
    error.url_invalid) echo "%s is invalid: '%s'. Use an http(s) URL without spaces or shell metacharacters.|%s 无效：'%s'，请使用不含空格或 shell 特殊字符的 http(s) URL。" ;;
    error.https_url_invalid) echo "%s is invalid: '%s'. Use an https URL without spaces or shell metacharacters.|%s 无效：'%s'，请使用不含空格或 shell 特殊字符的 https URL。" ;;
    error.goproxy_invalid) echo "%s is invalid: '%s'. Use http(s) proxy URLs plus optional direct/off entries, separated by comma or pipe.|%s 无效：'%s'，请使用 http(s) 代理 URL，可包含 direct/off，并用逗号或竖线分隔。" ;;
    error.image_repo_invalid) echo "%s is invalid: '%s'. Use a container image repository name without tag or digest.|%s 无效：'%s'，请使用不含标签或摘要的容器镜像仓库名称。" ;;
    error.image_tag_invalid) echo "%s is invalid: '%s'. Use a container image tag without spaces, slash, or shell metacharacters.|%s 无效：'%s'，请使用不含空格、斜杠或 shell 特殊字符的容器镜像标签。" ;;
    error.sha256_invalid) echo "%s is invalid: '%s'. Use exactly 64 hexadecimal characters.|%s 无效：'%s'，请使用正好 64 个十六进制字符。" ;;
    error.release_version_invalid) echo "%s is invalid: '%s'. Use a release version like 2024.6.2 without spaces, slash, or shell metacharacters.|%s 无效：'%s'，请使用类似 2024.6.2 的发布版本号，不包含空格、斜杠或 shell 特殊字符。" ;;
    menu.backup_desc) echo "create a manual backup|创建手动备份" ;;
    menu.install_desc) echo "full install or redeploy|完整安装或重新部署" ;;
    menu.restore_desc) echo "restore from a backup|从备份恢复" ;;
    menu.status_desc) echo "show service and runtime status|查看服务和运行状态" ;;
    menu.uninstall_desc) echo "remove service and related files|卸载服务和相关文件" ;;
    menu.update_desc) echo "update to the latest available version|更新到可用的最新版本" ;;
    manager.app_file_missing) echo "App definition file not found: %s|应用定义文件不存在：%s" ;;
    manager.app_definition_missing) echo "Bundled app definition not found: %s|内置应用定义不存在：%s" ;;
    manager.available_apps) echo "Available apps: %s|可用应用：%s" ;;
    manager.choose_app) echo "Choose an application:|请选择应用：" ;;
    manager.description) echo "Central deployment scheduler for all bundled application scripts.|所有内置应用部署脚本的中央统一调度器。" ;;
    manager.invalid_app) echo "Unknown application: %s|未知应用：%s" ;;
    manager.selection_prompt) echo "Application [number/name/q]:|请输入应用 [序号/名称/q]：" ;;
    manager.title) echo "Deployment Scheduler|部署调度器" ;;
    manager.usage) echo "Usage: sudo bash %s <app> [install, update, backup, restore, status, uninstall]|用法：sudo bash %s <应用> [install, update, backup, restore, status, uninstall]" ;;
    manager.usage_examples) echo "Examples: sudo bash %s newapi install; sudo bash %s vaultwarden status; sudo bash %s list|示例：sudo bash %s newapi install；sudo bash %s vaultwarden status；sudo bash %s list" ;;
    status.active) echo "active|运行中" ;;
    status.inactive) echo "inactive|未运行" ;;
    status.unknown) echo "unknown|未知" ;;
    warn.config_invalid_key) echo "Ignoring invalid config key: %s|已忽略非法配置键：%s" ;;
    warn.config_owner) echo "%s owner is not root (%s); ignoring it|%s 属主不是 root（当前：%s），已忽略" ;;
    warn.config_permission) echo "%s permissions are too open (%s); ignoring it|%s 权限过于宽松（%s），已忽略" ;;
    warn.config_unknown_key) echo "Ignoring unknown config key: %s|已忽略未知配置键：%s" ;;
    warn.port_in_use) echo "Port %s is already in use by %s.|端口 %s 已被 %s 占用。" ;;
    warn.port_release_hint) echo "If this is not the application you are deploying, free the port first or the service will fail to bind.|若非你要部署的应用，请先释放端口，否则服务将无法绑定。" ;;
    *) echo "$key|$key" ;;
  esac
}

t() {
  local key="$1"
  shift || true
  local pair text
  if [[ "$DEPLOY_LANG" == "zh" && -v "__DEPLOY_I18N_ZH[$key]" ]]; then
    i18n_print "${__DEPLOY_I18N_ZH[$key]}" "$@"
    return 0
  fi
  if [[ -v "__DEPLOY_I18N_EN[$key]" ]]; then
    i18n_print "${__DEPLOY_I18N_EN[$key]}" "$@"
    return 0
  fi
  pair="$(__deploy_i18n_message "$key")"
  if [[ "$DEPLOY_LANG" == "zh" ]]; then
    text="${pair#*|}"
  else
    text="${pair%%|*}"
  fi
  i18n_print "$text" "$@"
}
