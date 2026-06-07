#!/usr/bin/env bash

APP_ID="blog"
APP_NAME="Hugo Blog"
i18n_register app.blog.description \
  "Hugo and Nginx blog deployment." \
  "Hugo 与 Nginx 博客部署脚本。"
i18n_register app.blog.error.apt_only \
  "Only Debian / Ubuntu is supported by this script." \
  "此脚本仅支持 Debian / Ubuntu。"
i18n_register app.blog.error.systemd_required \
  "systemd is required by this script." \
  "此脚本需要 systemd。"
i18n_register app.blog.error.arch \
  "Unsupported architecture: %s. Supported: x86_64 / aarch64." \
  "不支持的架构：%s（支持 x86_64 / aarch64）。"

APP_DESCRIPTION="$(t app.blog.description)"
APP_IMPL_SCRIPT="impl/install_blog.sh"

load_app_impl "$APP_IMPL_SCRIPT"

do_update() { error "$(t error.unsupported_action "$APP_NAME" update)"; }
do_backup() { error "$(t error.unsupported_action "$APP_NAME" backup)"; }
do_status() { error "$(t error.unsupported_action "$APP_NAME" status)"; }
do_uninstall() { error "$(t error.unsupported_action "$APP_NAME" uninstall)"; }
