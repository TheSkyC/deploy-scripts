#!/usr/bin/env bash

APP_ID="navidrome"
APP_NAME="Navidrome"

i18n_register_many \
  app.navidrome.description \
  "Navidrome music server deployment with systemd and backups." \
  "使用 systemd 和备份的 Navidrome 音乐服务器部署脚本。" \
  app.navidrome.success.env_written \
  "Environment file written to %s." \
  "环境文件已写入 %s。" \
  app.navidrome.error.env_write \
  "Failed to write environment file: %s" \
  "环境文件写入失败：%s。" \
  app.navidrome.success.music_prepared \
  "Music folder ready: %s" \
  "音乐目录已就绪：%s。" \
  app.navidrome.error.music_prepare \
  "Failed to prepare the music folder %s." \
  "准备音乐目录 %s 失败。"

APP_DESCRIPTION="$(t app.navidrome.description)"
APP_IMPL_SCRIPT="impl/install_navidrome.sh"

load_app_impl "$APP_IMPL_SCRIPT"
