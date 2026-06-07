#!/usr/bin/env bash

APP_ID="cyberstrikeai"
APP_NAME="CyberStrikeAI"
APP_DESCRIPTION="Source build deployment with Go, Python, systemd, Nginx, and backups."
LEGACY_SCRIPT="legacy/install_cyberstrikeai.sh"

do_install() { legacy_dispatch install; }
do_update() { legacy_dispatch update; }
do_backup() { legacy_dispatch backup; }
do_status() { legacy_dispatch status; }
do_uninstall() { legacy_dispatch uninstall; }
