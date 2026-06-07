#!/usr/bin/env bash

APP_ID="newapi"
APP_NAME="New API"
i18n_register app.newapi.description \
  "Binary deployment with systemd, backups, and operational checks." \
  "使用 systemd、备份和运维检查的二进制部署脚本。"
i18n_register app.newapi.error.apt_only \
  "This script only supports Debian / Ubuntu because apt-get was not found." \
  "此脚本仅支持 Debian / Ubuntu（apt-get 未找到）。"
i18n_register app.newapi.error.arch \
  "Unsupported architecture: %s. Supported: x86_64 / aarch64." \
  "不支持的架构：%s（支持 x86_64 / aarch64）。"
i18n_register app.newapi.error.github_unreachable \
  "Cannot reach GitHub. Check network/proxy settings and retry." \
  "网络不通，无法访问 GitHub，请检查网络或代理后重试。"

APP_DESCRIPTION="$(t app.newapi.description)"
APP_IMPL_SCRIPT="impl/install_newapi.sh"

load_app_impl "$APP_IMPL_SCRIPT"
