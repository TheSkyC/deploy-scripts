#!/usr/bin/env bash

APP_ID="cyberstrikeai"
APP_NAME="CyberStrikeAI"
i18n_register app.cyberstrikeai.description \
  "Source build deployment with Go, Python, systemd, Nginx, and backups." \
  "包含 Go、Python、systemd、Nginx 和备份的源码构建部署脚本。"
i18n_register app.cyberstrikeai.error.apt_only \
  "Only Debian / Ubuntu is supported by this script." \
  "此脚本仅支持 Debian / Ubuntu。"
i18n_register app.cyberstrikeai.error.systemd_required \
  "systemd is required by this script." \
  "此脚本需要 systemd。"
i18n_register app.cyberstrikeai.error.arch \
  "Unsupported architecture: %s." \
  "不支持的架构：%s。"
i18n_register app.cyberstrikeai.error.github_unreachable \
  "Cannot reach GitHub. Check network/proxy settings and retry." \
  "无法访问 GitHub，请检查网络或代理后重试。"

APP_DESCRIPTION="$(t app.cyberstrikeai.description)"
APP_IMPL_SCRIPT="impl/install_cyberstrikeai.sh"

load_app_impl "$APP_IMPL_SCRIPT"
