#!/usr/bin/env bash

APP_ID="newapi"
APP_NAME="New API"
APP_DESCRIPTION="Binary deployment with systemd, backups, and operational checks."
LEGACY_SCRIPT="legacy/install_newapi.sh"

load_legacy_functions "$LEGACY_SCRIPT"
