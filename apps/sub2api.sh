#!/usr/bin/env bash

APP_ID="sub2api"
APP_NAME="Sub2API"
APP_DESCRIPTION="API gateway deployment with database, cache, systemd, and backups."
APP_IMPL_SCRIPT="impl/install_sub2api.sh"

load_app_impl "$APP_IMPL_SCRIPT"
