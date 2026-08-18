#!/usr/bin/env bash

APP_ID="filebrowser"
APP_NAME="Filebrowser"

i18n_register_many \
  app.filebrowser.description \
  "Filebrowser web file manager deployment with systemd and backups." \
  "使用 systemd 和备份的 Filebrowser 网页文件管理器部署脚本。" \
  app.filebrowser.success.root_prepared \
  "Served root directory ready: %s" \
  "服务根目录已就绪：%s" \
  app.filebrowser.error.root_prepare \
  "Failed to prepare the served root directory %s." \
  "准备服务根目录 %s 失败。" \
  app.filebrowser.hint.default \
  "Default credentials are admin/admin. Change them after first login." \
  "默认账号为 admin/admin，首次登录后请立即修改。"

APP_DESCRIPTION="$(t app.filebrowser.description)"
APP_IMPL_SCRIPT="impl/install_filebrowser.sh"

load_app_impl "$APP_IMPL_SCRIPT"
