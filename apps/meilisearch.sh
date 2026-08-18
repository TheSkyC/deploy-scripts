#!/usr/bin/env bash

APP_ID="meilisearch"
APP_NAME="Meilisearch"

i18n_register_many \
  app.meilisearch.description \
  "Meilisearch search engine deployment with systemd and backups." \
  "使用 systemd 和备份的 Meilisearch 搜索引擎部署脚本。" \
  app.meilisearch.success.env_written \
  "Environment file written to %s." \
  "环境文件已写入 %s。" \
  app.meilisearch.error.env_write \
  "Failed to write environment file: %s" \
  "环境文件写入失败：%s。" \
  app.meilisearch.hint.master_key \
  "Administrative API key saved in %s (MEILI_MASTER_KEY)." \
  "管理 API 密钥保存在 %s（MEILI_MASTER_KEY）。"

APP_DESCRIPTION="$(t app.meilisearch.description)"
APP_IMPL_SCRIPT="impl/install_meilisearch.sh"

load_app_impl "$APP_IMPL_SCRIPT"
