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
    action.status) echo "status|status" ;;
    action.uninstall) echo "uninstall|uninstall" ;;
    action.update) echo "update|update" ;;
    common.choose_action) echo "Choose an action:|请选择操作：" ;;
    common.invalid_choice) echo "Invalid choice: %s|无效选项：%s" ;;
    common.no_argument_menu) echo "No argument opens the interactive menu.|不带参数则打开交互式菜单。" ;;
    common.quit) echo "quit|退出" ;;
    common.selection_prompt) echo "Selection [1-5/q]:|请输入选项 [1-5/q]：" ;;
    common.usage) echo "Usage: sudo bash %s [install|update|backup|status|uninstall]|用法：sudo bash %s [install|update|backup|status|uninstall]" ;;
    config.loaded) echo "Loaded deployment config: %s|已加载部署记录：%s" ;;
    config.saved) echo "Saved deployment config: %s|部署配置已持久化：%s" ;;
    error.command_required) echo "Required command is missing: %s|缺少必要命令：%s" ;;
    error.config_permission) echo "Refusing to load unsafe config permissions: %s|拒绝加载权限不安全的配置文件：%s" ;;
    error.config_owner) echo "Refusing to load config not owned by root: %s|拒绝加载非 root 拥有的配置文件：%s" ;;
    error.lock_failed) echo "Another deployment process is running: %s|已有部署进程正在运行：%s" ;;
    error.root_required) echo "Please run as root: sudo bash %s %s|请使用 root 权限运行：sudo bash %s %s" ;;
    error.unsupported_action) echo "%s does not support %s yet.|%s 暂不支持 %s。" ;;
    error.unsafe_path) echo "Unsafe path for %s: %s|%s 的路径不安全：%s" ;;
    menu.backup_desc) echo "create a manual backup|创建手动备份" ;;
    menu.install_desc) echo "full install or redeploy|完整安装或重新部署" ;;
    menu.status_desc) echo "show service and runtime status|查看服务和运行状态" ;;
    menu.uninstall_desc) echo "remove service and related files|卸载服务和相关文件" ;;
    menu.update_desc) echo "update to the latest available version|更新到可用的最新版本" ;;
    status.active) echo "active|运行中" ;;
    status.inactive) echo "inactive|未运行" ;;
    status.unknown) echo "unknown|未知" ;;
    warn.config_invalid_key) echo "Ignoring invalid config key: %s|已忽略非法配置键：%s" ;;
    warn.config_owner) echo "%s owner is not root (%s); ignoring it|%s 属主不是 root（当前：%s），已忽略" ;;
    warn.config_permission) echo "%s permissions are too open (%s); ignoring it|%s 权限过于宽松（%s），已忽略" ;;
    warn.config_unknown_key) echo "Ignoring unknown config key: %s|已忽略未知配置键：%s" ;;
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
