#!/usr/bin/env bash

# Machine migration: `deploy.sh export` bundles every app deployment config,
# the notification/schedule configs, and a backup manifest inventory into a
# single sha256-stamped tarball; `deploy.sh import` verifies and unpacks it
# on the new machine. App binaries/data themselves are NOT included — they
# are recovered on the new host via each app's restore action against
# replicated backups, which keeps the export small and secret-surface low.
#
# Layout inside <output>.tar.gz:
#   manifest.json                     single-line inventory (sha256 stamped)
#   etc/deploy-notify.conf
#   etc/deploy-schedule.conf          (optional, when present)
#   etc/<app>-deploy.conf             one per installed app
#   backups-inventory.json            latest backup + integrity per app

MIGRATE_EXPORT_DIR="${MIGRATE_EXPORT_DIR:-/etc}"

migrate_conf_files() {
  local f
  for f in "$MIGRATE_EXPORT_DIR"/*-deploy.conf; do
    [[ -f "$f" ]] && printf '%s\n' "$f"
  done
}

# Build the staged tree under a mktemp dir and print its path. Fails when
# nothing exportable exists rather than producing an empty archive.
migrate_stage_tree() {
  local stage="$1"
  local staged_any=false f app_id conf_name
  mkdir -p "$stage/etc"
  if [[ -f "$NOTIFY_CONF_FILE" ]]; then
    cp "$NOTIFY_CONF_FILE" "$stage/etc/deploy-notify.conf"
    staged_any=true
  fi
  if [[ -f "$SCHEDULE_CONF_FILE" ]]; then
    cp "$SCHEDULE_CONF_FILE" "$stage/etc/deploy-schedule.conf"
    staged_any=true
  fi
  for f in $(migrate_conf_files); do
    conf_name="$(basename "$f")"
    cp "$f" "$stage/etc/$conf_name"
    staged_any=true
  done
  [[ "$staged_any" == "true" ]] || return 1
}

# Single-line JSON: per-app latest archive name + integrity verdict, so the
# new machine knows which backups to replicate before restoring.
migrate_backups_inventory() {
  local stage="$1"
  local out first=1 app_id impl_file backup_dir_var backup_dir glob record
  out="{\"schema_version\":1,\"apps\":["
  for app_id in "${DEPLOY_APP_IDS[@]}"; do
    impl_file="$(deploy_app_impl_file_for "$app_id")"
    [[ -f "$impl_file" ]] || continue
    record="$("${BASH_BIN:-bash}" -c '
      source lib/core.sh 2>/dev/null
      APP_ID="'"$app_id"'"
      source "'"$(pwd)/$impl_file"'" >/dev/null 2>&1 || exit 0
      app_load_config >/dev/null 2>&1 || true
      dir=""
      for candidate in BACKUP_DIR VW_BACKUP_DIR CPA_STACK_BACKUP_DIR; do
        v="${!candidate:-}"
        [[ -n "$v" ]] && { dir="$v"; break; }
      done
      [[ -n "$dir" && -d "$dir" ]] || exit 0
      case '"$app_id"' in
        blog) glob="blog_*.tar.gz" ;;
        tickflow) glob="tickflow-data-*.tar.gz" ;;
        cpa-stack) glob="cpa-stack-*.tar.gz" ;;
        cyberstrikeai) glob="cyberstrike-ai_*.tar.gz" ;;
        vaultwarden) glob="vaultwarden_*.tar.gz" ;;
        newapi) glob="new-api_*.tar.gz" ;;
        sub2api) glob="sub2api_*.tar.gz sub2api_db_*.sql.gz" ;;
        *) glob="${APP_ID}_*.tar.gz" ;;
      esac
      backup_verify_latest_json "$dir" $glob
    ' 2>/dev/null)" || record=""
    [[ -n "$record" ]] || continue
    (( first )) || out+=","
    first=0
    out+="{\"app\":$(app_json_string "$app_id"),\"latest\":$record}"
  done
  out+="]}"
  printf '%s' "$out" > "${stage}/backups-inventory.json"
}

migrate_main() {
  require_root "migrate"
  local subcommand="${1:-}"
  shift || true
  case "${subcommand,,}" in
    export)
      local output="" redact=false
      while (($#)); do
        case "$1" in
          --output) output="${2:-}"; shift 2 ;;
          --redact) redact=true; shift ;;
          *) t migrate.usage "$0"; return 2 ;;
        esac
      done
      [[ -n "$output" ]] || output="/root/deploy-migration-$(date +%Y%m%d%H%M%S).tar.gz"
      local stage
      stage="$(mktemp -d "${output}.stage.XXXXXX")"
      if ! migrate_stage_tree "$stage"; then
        rm -rf "$stage"
        error "$(t migrate.error.nothing_to_export)"
      fi
      migrate_backups_inventory "$stage"
      # Redacted variant is an additional human-readable reference copy of
      # every conf with secret values masked; the real values still ship in
      # the plain files so import remains functional.
      if [[ "$redact" == "true" ]]; then
        local rf rf_out
        mkdir -p "$stage/redacted-reference"
        for rf in "$stage"/etc/*.conf; do
          rf_out="$stage/redacted-reference/$(basename "$rf").redacted.txt"
          sed -E 's/^((TOKEN|PASSWORD|SECRET|API_KEY|PRIVATE_KEY)[A-Za-z_]*=)".*"/\1"[REDACTED]"/I' \
            "$rf" > "$rf_out"
        done
      fi
      # Stamp the archive itself after creation.
      if ! tar -czf "$output" -C "$stage" . >&2; then
        rm -rf "$stage"
        error "$(t error.config_write "$output")"
      fi
      chmod 600 "$output" 2>/dev/null || true
      backup_write_sha256 "$output" >/dev/null || true
      rm -rf "$stage"
      success "$(t migrate.info.exported "$output")"
      info "$(t migrate.info.next_steps)"
      ;;
    import)
      local input=""
      while (($#)); do
        case "$1" in
          --input) input="${2:-}"; shift 2 ;;
          *) t migrate.usage "$0"; return 2 ;;
        esac
      done
      [[ -n "$input" && -f "$input" ]] || error "$(t migrate.error.archive_missing "${input:-none}")"
      # Integrity first: refuse a damaged bundle before touching /etc.
      if [[ -f "${input}.sha256" ]]; then
        backup_verify_archive "$input" || error "$(t backup.verify.failed "$(basename "$input")")"
      fi
      local stage
      stage="$(mktemp -d "${input}.import.XXXXXX")"
      if ! tar -xzf "$input" -C "$stage" >&2; then
        rm -rf "$stage"
        error "$(t backup.restore.invalid_archive "$(basename "$input")")"
      fi
      local f target installed=0
      for f in "$stage"/etc/*.conf; do
        [[ -f "$f" ]] || continue
        target="$MIGRATE_EXPORT_DIR/$(basename "$f")"
        atomic_copy_file "$f" "$target" 600 root:root || {
          rm -rf "$stage"
          error "$(t error.config_write "$target")"
        }
        installed=$((installed + 1))
      done
      rm -rf "$stage"
      success "$(t migrate.info.imported "$installed")"
      info "$(t migrate.info.manual_steps)"
      ;;
    *)
      t migrate.usage "$0"
      return 2
      ;;
  esac
}
