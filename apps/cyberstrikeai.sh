#!/usr/bin/env bash

APP_ID="cyberstrikeai"
APP_NAME="CyberStrikeAI"
APP_DESCRIPTION="Source build deployment with Go, Python, systemd, Nginx, and backups."
APP_IMPL_SCRIPT="impl/install_cyberstrikeai.sh"

load_app_impl "$APP_IMPL_SCRIPT"
