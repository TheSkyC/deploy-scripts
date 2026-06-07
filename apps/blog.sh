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

APP_DESCRIPTION="$(t app.blog.description)"
APP_IMPL_SCRIPT="impl/install_blog.sh"

do_install() { app_impl_dispatch install; }
do_update() { error "$(t error.unsupported_action "$APP_NAME" update)"; }
do_backup() { error "$(t error.unsupported_action "$APP_NAME" backup)"; }
do_status() { error "$(t error.unsupported_action "$APP_NAME" status)"; }
do_uninstall() { error "$(t error.unsupported_action "$APP_NAME" uninstall)"; }
