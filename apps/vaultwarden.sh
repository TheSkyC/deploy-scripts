#!/usr/bin/env bash

APP_ID="vaultwarden"
APP_NAME="Vaultwarden"
APP_DESCRIPTION="Vaultwarden deployment with Web Vault, Nginx, TLS, and backups."
LEGACY_SCRIPT="legacy/install_vaultwarden.sh"

do_install() { legacy_dispatch install; }
do_update() { legacy_dispatch update; }
do_backup() { legacy_dispatch backup; }
do_status() { legacy_dispatch status; }
do_uninstall() { legacy_dispatch uninstall; }
