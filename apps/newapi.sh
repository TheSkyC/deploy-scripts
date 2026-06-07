#!/usr/bin/env bash

APP_ID="newapi"
APP_NAME="New API"
APP_DESCRIPTION="Binary deployment with systemd, backups, and operational checks."
LEGACY_SCRIPT="legacy/install_newapi.sh"

do_install() { legacy_dispatch install; }
do_update() { legacy_dispatch update; }
do_backup() { legacy_dispatch backup; }
do_status() { legacy_dispatch status; }
do_uninstall() { legacy_dispatch uninstall; }
