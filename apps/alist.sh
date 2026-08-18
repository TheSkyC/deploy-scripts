#!/usr/bin/env bash

APP_ID="alist"
APP_NAME="Alist"

i18n_register_many \
  app.alist.description \
  "Alist file listing service deployment with systemd and backups." \
  "使用 systemd 和备份的 Alist 文件列表服务部署脚本。" \
  app.alist.hint.admin \
  "Initialize the administrator password with: alist admin --data %s" \
  "初始化管理员密码：alist admin --data %s"

APP_DESCRIPTION="$(t app.alist.description)"
APP_IMPL_SCRIPT="impl/install_alist.sh"

load_app_impl "$APP_IMPL_SCRIPT"
