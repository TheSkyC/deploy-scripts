#!/usr/bin/env bash

APP_ID="vaultwarden"
APP_NAME="Vaultwarden"
i18n_register app.vaultwarden.description \
  "Vaultwarden deployment with Web Vault, Nginx, TLS, and backups." \
  "包含 Web Vault、Nginx、TLS 和备份的 Vaultwarden 部署脚本。"
i18n_register app.vaultwarden.error.apt_only \
  "This script only supports Debian / Ubuntu because apt-get was not found." \
  "此脚本仅支持 Debian / Ubuntu（apt-get 未找到）。"
i18n_register app.vaultwarden.error.arch \
  "Unsupported architecture: %s. Supported: x86_64 / aarch64 / armv7l." \
  "不支持的架构：%s（支持 x86_64 / aarch64 / armv7l）。"
i18n_register app.vaultwarden.error.registry_unreachable \
  "Cannot reach Docker Registry or GitHub. Check network/proxy settings and retry." \
  "网络不通，无法访问 Docker Registry / GitHub，请检查网络或代理后重试。"

APP_DESCRIPTION="$(t app.vaultwarden.description)"
APP_IMPL_SCRIPT="impl/install_vaultwarden.sh"

load_app_impl "$APP_IMPL_SCRIPT"
