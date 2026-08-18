#!/usr/bin/env bash

APP_ID="gitea"
APP_NAME="Gitea"

i18n_register_many \
  app.gitea.description \
  "Gitea git server deployment with systemd and backups." \
  "使用 systemd 和备份的 Gitea 代码托管服务部署脚本。" \
  app.gitea.success.config_written \
  "Server configuration written to %s." \
  "服务端配置已写入 %s。" \
  app.gitea.error.config_write \
  "Failed to write server configuration: %s" \
  "服务端配置写入失败：%s。" \
  app.gitea.warn.config_dir_remove \
  "Failed to remove configuration directory %s; clean it manually if needed." \
  "配置目录 %s 删除失败，如需清理请手动删除。" \
  app.gitea.success.removed_config \
  "Server configuration removed." \
  "服务端配置已移除。" \
  app.gitea.hint.admin_create \
  "Create an admin user with: gitea admin create-user --admin --config /etc/gitea/app.ini" \
  "创建管理员账号：gitea admin create-user --admin --config /etc/gitea/app.ini"

APP_DESCRIPTION="$(t app.gitea.description)"
APP_IMPL_SCRIPT="impl/install_gitea.sh"

load_app_impl "$APP_IMPL_SCRIPT"
