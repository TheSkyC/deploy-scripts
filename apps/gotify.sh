#!/usr/bin/env bash

APP_ID="gotify"
APP_NAME="Gotify"

i18n_register_many \
  app.gotify.description \
  "Gotify push notification server deployment with systemd and backups." \
  "使用 systemd 和备份的 Gotify 推送通知服务部署脚本。" \
  app.gotify.success.env_written \
  "Environment file written to %s." \
  "环境文件已写入 %s。" \
  app.gotify.error.env_write \
  "Failed to write environment file: %s" \
  "环境文件写入失败：%s。" \
  app.gotify.hint.admin_password \
  "The generated admin password is stored in %s (user: admin)." \
  "生成的管理员密码保存在 %s（用户名：admin）。"

APP_DESCRIPTION="$(t app.gotify.description)"
APP_IMPL_SCRIPT="impl/install_gotify.sh"

load_app_impl "$APP_IMPL_SCRIPT"
