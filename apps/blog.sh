#!/usr/bin/env bash

APP_ID="blog"
APP_NAME="Hugo Blog"
APP_DESCRIPTION="Hugo and Nginx blog deployment."
LEGACY_SCRIPT="legacy/install_blog.sh"

do_install() { legacy_dispatch install; }
do_update() { error "$(t error.unsupported_action "$APP_NAME" update)"; }
do_backup() { error "$(t error.unsupported_action "$APP_NAME" backup)"; }
do_status() { error "$(t error.unsupported_action "$APP_NAME" status)"; }
do_uninstall() { error "$(t error.unsupported_action "$APP_NAME" uninstall)"; }
