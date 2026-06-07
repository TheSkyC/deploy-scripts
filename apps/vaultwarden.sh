#!/usr/bin/env bash

APP_ID="vaultwarden"
APP_NAME="Vaultwarden"
APP_DESCRIPTION="Vaultwarden deployment with Web Vault, Nginx, TLS, and backups."
APP_IMPL_SCRIPT="impl/install_vaultwarden.sh"

load_app_impl "$APP_IMPL_SCRIPT"
