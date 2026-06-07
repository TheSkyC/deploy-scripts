#!/usr/bin/env bash

APP_ID="sub2api"
APP_NAME="Sub2API"
i18n_register app.sub2api.description \
  "API gateway deployment with database, cache, systemd, and backups." \
  "包含数据库、缓存、systemd 和备份的 API 网关部署脚本。"
i18n_register app.sub2api.error.package_manager \
  "No supported package manager was found. Install dependencies manually or use apt, dnf, or yum." \
  "未找到支持的包管理器（apt / dnf / yum），请手动安装依赖。"
i18n_register app.sub2api.error.arch \
  "Unsupported architecture: %s. Supported: x86_64 / aarch64." \
  "不支持的架构：%s（支持 x86_64 / aarch64）。"
i18n_register app.sub2api.error.github_unreachable \
  "Cannot reach GitHub. Check network/proxy settings and retry." \
  "网络不通，无法访问 GitHub，请检查网络或代理后重试。"

APP_DESCRIPTION="$(t app.sub2api.description)"
APP_IMPL_SCRIPT="impl/install_sub2api.sh"

load_app_impl "$APP_IMPL_SCRIPT"
