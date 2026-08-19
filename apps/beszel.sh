#!/usr/bin/env bash

APP_ID="beszel"
APP_NAME="Beszel"

i18n_register_many \
  app.beszel.description \
  "Beszel monitoring hub deployment with systemd and backups." \
  "使用 systemd 和备份的 Beszel 监控中心部署脚本。" \
  app.beszel.success.env_written \
  "Environment file written to %s." \
  "环境文件已写入 %s。" \
  app.beszel.error.env_write \
  "Failed to write environment file: %s" \
  "环境文件写入失败：%s。" \
  app.beszel.hint.open_ui \
  "Open the Beszel web interface at %s to create the first user." \
  "打开 Beszel Web 界面 %s 创建第一个用户。"

APP_DESCRIPTION="$(t app.beszel.description)"
APP_IMPL_SCRIPT="impl/install_beszel.sh"

load_app_impl "$APP_IMPL_SCRIPT"
