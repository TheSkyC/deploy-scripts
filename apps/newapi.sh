#!/usr/bin/env bash

APP_ID="newapi"
APP_NAME="New API"
APP_DESCRIPTION="Binary deployment with systemd, backups, and operational checks."
APP_IMPL_SCRIPT="impl/install_newapi.sh"

load_app_impl "$APP_IMPL_SCRIPT"
