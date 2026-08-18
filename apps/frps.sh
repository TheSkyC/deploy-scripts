#!/usr/bin/env bash

APP_ID="frps"
APP_NAME="frps"

i18n_register_many \
  app.frps.description \
  "frp server (frps) deployment with systemd and backups." \
  "使用 systemd 和备份的 frp 服务端（frps）部署脚本。" \
  app.frps.success.config_written \
  "Server configuration written to %s." \
  "服务端配置已写入 %s。" \
  app.frps.error.config_write \
  "Failed to write server configuration: %s" \
  "服务端配置写入失败：%s。" \
  app.frps.warn.config_dir_remove \
  "Failed to remove configuration directory %s; clean it manually if needed." \
  "配置目录 %s 删除失败，如需清理请手动删除。" \
  app.frps.success.removed_config \
  "Server configuration removed." \
  "服务端配置已移除。" \
  app.frps.hint.token \
  "Client authentication token saved in %s (auth.token)." \
  "客户端认证令牌保存在 %s（auth.token）。"

APP_DESCRIPTION="$(t app.frps.description)"
APP_IMPL_SCRIPT="impl/install_frps.sh"

load_app_impl "$APP_IMPL_SCRIPT"
