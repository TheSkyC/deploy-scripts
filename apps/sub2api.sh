#!/usr/bin/env bash

APP_ID="sub2api"
APP_NAME="Sub2API"
APP_DESCRIPTION="API gateway deployment with database, cache, systemd, and backups."
LEGACY_SCRIPT="legacy/install_sub2api.sh"

do_install() { legacy_dispatch install; }
do_update() { legacy_dispatch update; }
do_backup() { legacy_dispatch backup; }
do_status() { legacy_dispatch status; }
do_uninstall() { legacy_dispatch uninstall; }
