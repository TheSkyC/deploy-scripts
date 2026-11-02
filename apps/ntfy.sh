#!/usr/bin/env bash

APP_ID="ntfy"
APP_NAME="ntfy"
i18n_register_many \
  app.ntfy.description \
  "Push notification service deployment with systemd and backups." \
  "使用 systemd 和备份的推送通知服务部署脚本。" \
  app.ntfy.success.config_written \
  "Server configuration written to %s." \
  "服务端配置已写入 %s。" \
  app.ntfy.error.config_write \
  "Failed to write server configuration: %s" \
  "服务端配置写入失败：%s。" \
  app.ntfy.error.attachment_dir \
  "Failed to prepare the attachment cache directory: %s" \
  "附件缓存目录准备失败：%s。" \
  app.ntfy.warn.config_dir_remove \
  "Failed to remove configuration directory %s; clean it manually if needed." \
  "配置目录 %s 删除失败，如需清理请手动删除。" \
  app.ntfy.success.removed_config \
  "Server configuration removed." \
  "服务端配置已移除。" \
  app.ntfy.hint.publish \
  "Test locally: curl -d hello http://%s:%s/ntfy-test. ntfy currently listens on %s; use a reverse proxy or explicitly change BA_BIND_ADDR for remote access." \
  "本地测试：curl -d hello http://%s:%s/ntfy-test。服务当前监听 %s；如需远程访问，请使用反向代理或显式修改 BA_BIND_ADDR。"

APP_DESCRIPTION="$(t app.ntfy.description)"
APP_IMPL_SCRIPT="impl/install_ntfy.sh"

load_app_impl "$APP_IMPL_SCRIPT"
