#!/usr/bin/env bash

APP_ID="rustdesk"
APP_NAME="RustDesk Server OSS"
i18n_register_many \
  app.rustdesk.description \
  "RustDesk OSS ID and relay server (hbbs + hbbr) managed with Docker Compose." \
  "通过 Docker Compose 管理 RustDesk OSS ID 与中继服务（hbbs + hbbr）。" \
  app.rustdesk.info.public_key \
  "RustDesk public key (share this with clients):" \
  "RustDesk 公钥（配置客户端时使用）：" \
  app.rustdesk.warn.no_key \
  "Public key is not available yet. Start the server first." \
  "公钥尚不可用，请先启动服务。"
APP_DESCRIPTION="$(t app.rustdesk.description)"
APP_IMPL_SCRIPT="impl/install_rustdesk.sh"
load_app_impl "$APP_IMPL_SCRIPT"
