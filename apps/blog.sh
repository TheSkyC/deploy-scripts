#!/usr/bin/env bash

APP_ID="blog"
APP_NAME="Hugo Blog"
APP_DESCRIPTION="Hugo and Nginx blog deployment."
LEGACY_SCRIPT="legacy/install_blog.sh"

do_install() { legacy_dispatch install; }
do_update() { error "The blog installer does not support update yet."; }
do_backup() { error "The blog installer does not support backup yet."; }
do_status() { error "The blog installer does not support status yet."; }
do_uninstall() { error "The blog installer does not support uninstall yet."; }
