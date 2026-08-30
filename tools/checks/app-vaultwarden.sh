# shellcheck shell=bash
# shellcheck source=../verify.sh
# Verify checks for the vaultwarden app (apps/vaultwarden.sh).

check_vaultwarden_status_backup_projection() {
  local output
  output="$($BASH_BIN -c '
    set -euo pipefail
    tmp_dir="$(mktemp -d)"
    backup_dir="$tmp_dir/vaultwarden backups"
    mkdir -p "$backup_dir"
    touch -d "2026-08-20 12:34:56 UTC" "$backup_dir/vaultwarden_20260820123456.tar.gz"
    source lib/core.sh
    APP_ID=vaultwarden
    APP_NAME="Vaultwarden"
    VW_BACKUP_DIR="$backup_dir"
    app_conf_file() { printf "%s" "$tmp_dir/missing.conf"; }
    source impl/install_vaultwarden.sh
    _vw_status_backup
    rm -rf "$tmp_dir"
  ')"
  python -c 'import json,sys; x=json.loads(sys.argv[1]); assert x["state"] == "available"; assert "vaultwarden backups" in x["path"]; assert x["path"].endswith("vaultwarden_20260820123456.tar.gz"); assert x["last_success_at"]' "$output"
  grep -Fq 'APP_STATUS_BACKUP_FN=_vw_status_backup' impl/install_vaultwarden.sh
}

check_vaultwarden_uninstall_supports_noninteractive_mode() {
  awk '
      /prompt "\$\(t app\.vaultwarden\.prompt\.continue\)"/ { saw_continue_prompt=1 }
      /if deploy_assume_yes; then/ && !saw_continue { saw_continue=1; next }
      saw_continue && /_c="YES"/ { saw_yes=1 }
      /local DELETE_DATA=false/ { in_data=1; next }
      in_data && /deploy_env_truthy DEPLOY_DELETE_DATA && DELETE_DATA=true/ { saw_data_env=1 }
      in_data && /prompt "\$\(t app\.vaultwarden\.prompt\.delete_data "\$VW_DATA_DIR"\)"/ { saw_data_prompt=1; in_data=0 }
      /local DELETE_BACKUP=false/ { in_backup=1; next }
      in_backup && /deploy_env_truthy DEPLOY_DELETE_BACKUP && DELETE_BACKUP=true/ { saw_backup_env=1 }
      in_backup && /prompt "\$\(t app\.vaultwarden\.prompt\.delete_backup "\$VW_BACKUP_DIR"\)"/ { saw_backup_prompt=1; in_backup=0 }
      END {
        if (!(saw_continue_prompt && saw_continue && saw_yes && saw_data_env && saw_data_prompt && saw_backup_env && saw_backup_prompt)) {
          printf "%s Vaultwarden uninstall must support DEPLOY_ASSUME_YES while requiring explicit env flags for data and backup deletion\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_vaultwarden.sh
}

check_vaultwarden_uninstall_checks_directory_removal_errors() {
  grep -Fq '_vw_remove_dir_or_error() {' impl/install_vaultwarden.sh \
    && grep -Fq 'app_remove_dir_or_error "$1" "$2" "$3" "app.vaultwarden.error.remove_dir"' impl/install_vaultwarden.sh \
    && grep -Fq '_vw_remove_dir_or_error "$_log_dir" "LOG_DIR" "$(t app.vaultwarden.success.deleted_log "$_log_dir")"' impl/install_vaultwarden.sh \
    && grep -Fq '_vw_remove_dir_or_error "$VW_DATA_DIR" "VW_DATA_DIR" "$(t app.vaultwarden.success.deleted_data "$VW_DATA_DIR")"' impl/install_vaultwarden.sh \
    && grep -Fq '_vw_remove_dir_or_error "$VW_BACKUP_DIR" "VW_BACKUP_DIR" "$(t app.vaultwarden.success.deleted_backup "$VW_BACKUP_DIR")"' impl/install_vaultwarden.sh \
    && grep -Fq 'app.vaultwarden.error.remove_dir' apps/vaultwarden.sh \
    || {
      echo "Vaultwarden uninstall must surface directory removal failures instead of reporting unconditional success." >&2
      return 1
    }
}

check_vaultwarden_uninstall_checks_file_removal_errors() {
  grep -Fq '_vw_remove_file_or_error() {' impl/install_vaultwarden.sh \
    && grep -Fq 'app_remove_file_or_error "$1" "$2" "app.vaultwarden.error.remove_file"' impl/install_vaultwarden.sh \
    && grep -Fq '_vw_remove_file_or_error "/etc/systemd/system/vaultwarden.service" "VAULTWARDEN_SERVICE_FILE"' impl/install_vaultwarden.sh \
    && grep -Fq '_vw_remove_file_or_error "/etc/nginx/sites-enabled/vaultwarden" "VAULTWARDEN_NGINX_LINK"' impl/install_vaultwarden.sh \
    && grep -Fq '_vw_remove_file_or_error "/etc/nginx/sites-available/vaultwarden" "VAULTWARDEN_NGINX_CONF"' impl/install_vaultwarden.sh \
    && grep -Fq '_vw_remove_file_or_error "/etc/fail2ban/filter.d/vaultwarden.conf" "VAULTWARDEN_FAIL2BAN_FILTER"' impl/install_vaultwarden.sh \
    && grep -Fq '_vw_remove_file_or_error "/etc/fail2ban/filter.d/vaultwarden-admin.conf" "VAULTWARDEN_FAIL2BAN_ADMIN_FILTER"' impl/install_vaultwarden.sh \
    && grep -Fq '_vw_remove_file_or_error "/etc/fail2ban/jail.d/vaultwarden.conf" "VAULTWARDEN_FAIL2BAN_JAIL"' impl/install_vaultwarden.sh \
    && grep -Fq '_vw_remove_file_or_error "/etc/cron.d/vaultwarden-backup" "VAULTWARDEN_CRON_FILE"' impl/install_vaultwarden.sh \
    && grep -Fq '_vw_remove_file_or_error "/usr/local/bin/vaultwarden-backup" "VAULTWARDEN_BACKUP_SCRIPT"' impl/install_vaultwarden.sh \
    && grep -Fq '_vw_remove_file_or_error "/etc/logrotate.d/vaultwarden" "VAULTWARDEN_LOGROTATE_FILE"' impl/install_vaultwarden.sh \
    && grep -Fq '_vw_remove_file_or_error "$VW_ENV_FILE" "VW_ENV_FILE"' impl/install_vaultwarden.sh \
    && grep -Fq '_vw_remove_file_or_error "$CONF_FILE" "CONF_FILE"' impl/install_vaultwarden.sh \
    && grep -Fq 'app.vaultwarden.error.remove_file' apps/vaultwarden.sh \
    || {
      echo "Vaultwarden uninstall must surface file removal failures instead of reporting unconditional success." >&2
      return 1
    }
}

check_vaultwarden_uninstall_validates_binary_path_before_removal() {
  grep -Fq '_require_safe_vw_bin_path() {' impl/install_vaultwarden.sh \
    || {
      echo "Vaultwarden must centralize VW_BIN safety validation in a reusable helper." >&2
      return 1
    }
  awk '
      /do_uninstall\(\)/ { in_uninstall=1; saw_guard=0; saw_remove=0; saw_raw_rm=0; next }
      in_uninstall && /_require_safe_vw_bin_path/ && !saw_guard { saw_guard=1; next }
      in_uninstall && /_vw_remove_file_or_error "\$VW_BIN" "VW_BIN"/ {
        if (!saw_guard) {
          printf "%s Vaultwarden uninstall must validate VW_BIN before removing the binary\n", FILENAME > "/dev/stderr"
          exit 1
        }
        saw_remove=1
      }
      in_uninstall && /rm -f "\$VW_BIN"|rm -f "\$\{VW_BIN\}"/ { saw_raw_rm=1 }
      in_uninstall && /success "\$\(t app\.vaultwarden\.success\.removed_binary\)"/ {
        if (!(saw_guard && saw_remove) || saw_raw_rm) {
          printf "%s Vaultwarden uninstall must guard binary removal and surface VW_BIN cleanup failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_uninstall=0
      }
    ' impl/install_vaultwarden.sh
}

check_vaultwarden_install_supports_noninteractive_mode() {
  awk '
      /app\.vaultwarden\.error\.noninteractive_domain/ { saw_domain_msg=1 }
      /app\.vaultwarden\.error\.noninteractive_email/ { saw_email_msg=1 }
      END {
        if (!(saw_domain_msg && saw_email_msg)) {
          print "Vaultwarden non-interactive install guardrails must be localized." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/vaultwarden.sh
  awk '
      /prompt "\$\(t app\.vaultwarden\.prompt\.force_reinstall\)"/ { saw_reinstall_prompt=1 }
      /prompt "\$\(t app\.vaultwarden\.prompt\.domain\)"/ { saw_domain_prompt=1 }
      /prompt "\$\(t app\.vaultwarden\.prompt\.email\)"/ { saw_email_prompt=1 }
      /prompt "\$\(t app\.vaultwarden\.prompt\.confirm_config\)"/ { saw_confirm_prompt=1 }
      /if deploy_assume_yes; then/ && !saw_reinstall_assume { saw_reinstall_assume=1; next }
      saw_reinstall_assume && /_c="y"/ { saw_reinstall_yes=1 }
      /\[\[ "\$VW_DOMAIN" == "vault\.example\.com" \]\]/ { in_domain=1; next }
      in_domain && /if deploy_assume_yes; then/ { saw_domain_assume=1 }
      in_domain && /error "\$\(t app\.vaultwarden\.error\.noninteractive_domain\)"/ { saw_domain_error=1 }
      in_domain && /VW_DOMAIN="\$_input"/ { in_domain=0 }
      /\[\[ "\$ENABLE_HTTPS" == "true" \]\] && \[\[ -z "\$CERTBOT_EMAIL" \]\]/ { in_email=1; next }
      in_email && /if deploy_assume_yes; then/ { saw_email_assume=1 }
      in_email && /error "\$\(t app\.vaultwarden\.error\.noninteractive_email\)"/ { saw_email_error=1 }
      in_email && /CERTBOT_EMAIL="\$_email"/ { in_email=0 }
      /if deploy_assume_yes; then/ && saw_email_error && !saw_confirm_assume { saw_confirm_assume=1; next }
      saw_confirm_assume && /_c="y"/ { saw_confirm_yes=1 }
      END {
        if (!(saw_reinstall_prompt && saw_domain_prompt && saw_email_prompt && saw_confirm_prompt && saw_reinstall_assume && saw_reinstall_yes && saw_domain_assume && saw_domain_error && saw_email_assume && saw_email_error && saw_confirm_assume && saw_confirm_yes)) {
          printf "%s Vaultwarden install must support DEPLOY_ASSUME_YES while rejecting placeholder domain and missing HTTPS email\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_vaultwarden.sh
}

check_vaultwarden_install_summary_is_localized() {
  awk '
      /app\.vaultwarden\.info\.web_vault/ { saw_web_key=1 }
      /app\.vaultwarden\.info\.https/ { saw_https_key=1 }
      END {
        if (!(saw_web_key && saw_https_key)) {
          print "Vaultwarden install summary fields must have localization keys." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/vaultwarden.sh
  awk '
      /info "\$\(t app\.vaultwarden\.info\.web_vault "\$VW_WEB_DIR"\)"/ { saw_web=1 }
      /info "\$\(t app\.vaultwarden\.info\.https "\$ENABLE_HTTPS"\)"/ { saw_https=1 }
      /info "Web Vault:/ || /info "HTTPS    :/ {
        printf "%s Vaultwarden install summary must use i18n helpers instead of hardcoded English fields.\n", FILENAME > "/dev/stderr"
        exit 1
      }
      END {
        if (!(saw_web && saw_https)) {
          printf "%s Vaultwarden install summary must print localized Web Vault and HTTPS fields.\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_vaultwarden.sh
}

check_vaultwarden_backup_lists_preserve_paths_with_spaces() {
  if grep -R -n -- "-printf '%T@ %p\\\\n'" impl/install_vaultwarden.sh 2>/dev/null; then
    echo "Vaultwarden backup and rollback lists must not split paths on spaces." >&2
    return 1
  fi
  awk '
      /NEWEST_BAK=""/ { in_newest=1 }
      in_newest && /NEWEST_BAK="\$\{_newest_bak_entry#\* \}"/ { saw_newest_strip=1 }
      in_newest && /-printf '\''%T@ %p\\0'\''/ { saw_newest_print0=1 }
      in_newest && /sort -z -rn \| head -z -n 1/ { saw_newest_sort=1; in_newest=0 }
      /local -a _old_baks/ { in_binary=1 }
      in_binary && /_old_baks\+=\("\$\{_old_bak_entry#\* \}"\)/ { saw_binary_strip=1 }
      in_binary && /-printf '\''%T@ %p\\0'\''/ { saw_binary_print0=1 }
      in_binary && /sort -z -rn \| tail -z -n \+4/ { saw_binary_sort=1; in_binary=0 }
      /local -a _old_wv_baks/ { in_web=1 }
      in_web && /_old_wv_baks\+=\("\$\{_old_wv_bak_entry#\* \}"\)/ { saw_web_strip=1 }
      in_web && /-printf '\''%T@ %p\\0'\''/ { saw_web_print0=1 }
      in_web && /sort -z -rn \| tail -z -n \+4/ { saw_web_sort=1; in_web=0 }
      /info "\$\(t app\.vaultwarden\.info\.backup_list\)"/ { in_backup=1 }
      in_backup && /_bak_list\+=\("\$\{_bak_entry#\* \}"\)/ { saw_backup_strip=1 }
      in_backup && /-printf '\''%T@ %p\\0'\''/ { saw_backup_print0=1 }
      in_backup && /sort -z -rn \| head -z -n 10/ { saw_backup_sort=1; in_backup=0 }
      END {
        if (!(saw_newest_strip && saw_newest_print0 && saw_newest_sort && saw_binary_strip && saw_binary_print0 && saw_binary_sort && saw_web_strip && saw_web_print0 && saw_web_sort && saw_backup_strip && saw_backup_print0 && saw_backup_sort)) {
          printf "%s Vaultwarden backup, rollback, and retention lists must use NUL-delimited sorting without splitting paths on spaces\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_vaultwarden.sh
}

check_vaultwarden_status_display_commands_are_nonfatal() {
  awk '
      /do_status\(\)/ { in_status=1; next }
      in_status && /^}/ {
        if (!(saw_bin_size && saw_bin_time && saw_ls && saw_data_size && saw_db_size)) {
          printf "%s Vaultwarden status display commands must fall back instead of failing under pipefail\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_status=0
      }
      in_status && /_bin_size=\$\(du -sh "\$VW_BIN" 2>\/dev\/null \| cut -f1 \|\| t status\.unknown\)/ { saw_bin_size=1 }
      in_status && /_bin_time=\$\(stat -c '\''%y'\'' "\$VW_BIN" 2>\/dev\/null \| cut -d'\''\.'\'' -f1 \|\| t status\.unknown\)/ { saw_bin_time=1 }
      in_status && /find "\$VW_DATA_DIR" -mindepth 1 -maxdepth 1 -printf '\''%p\\0'\'' 2>\/dev\/null \| sort -z\) \|\| true/ { saw_ls=1 }
      in_status && /_data_size=\$\(du -sh "\$VW_DATA_DIR" 2>\/dev\/null \| cut -f1 \|\| t status\.unknown\)/ { saw_data_size=1 }
      in_status && /DB_SIZE=\$\(du -sh "\$\{VW_DATA_DIR\}\/db\.sqlite3" 2>\/dev\/null \| cut -f1 \|\| t status\.unknown\)/ { saw_db_size=1 }
    ' impl/install_vaultwarden.sh
}

check_vaultwarden_version_probe_has_fallback() {
  awk '
      /get_installed_version\(\)/ { in_func=1; saw_local=0; saw_missing=0; saw_parse=0; saw_unknown=0; next }
      in_func && /local version/ { saw_local=1 }
      in_func && /\[\[ ! -x "\$VW_BIN" \]\]/ { saw_missing=1 }
      in_func && /t app\.vaultwarden\.status\.not_installed/ { saw_not_installed=1 }
      in_func && /version=\$\("\$VW_BIN" --version 2>\/dev\/null \| awk '\''NF >= 2 \{ print \$2; exit \}'\'' \|\| true\)/ { saw_parse=1 }
      in_func && /if \[\[ -n "\$version" \]\]; then/ { saw_if=1 }
      in_func && /^[[:space:]]*t status\.unknown/ { saw_unknown=1 }
      in_func && /^}/ {
        if (!(saw_local && saw_missing && saw_not_installed && saw_parse && saw_if && saw_unknown)) {
          printf "%s Vaultwarden version probe must distinguish missing binaries from unparsable version output and fall back under pipefail.\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_vaultwarden.sh
}

check_vaultwarden_find_head_pipelines_are_nonfatal() {
  if grep -R -nE '\$\(find [^)]*\| head -1\)' \
      impl/install_vaultwarden.sh 2>/dev/null; then
    echo "Vaultwarden find/head lookups must fall back so empty results reach explicit handling under pipefail." >&2
    return 1
  fi
}

check_vaultwarden_config_values_are_validated() {
  awk '
      /preflight_check\(\)/ { in_preflight=1; next }
      in_preflight && /^}/ {
        if (!saw_preflight) {
          printf "%s Vaultwarden preflight must validate config defaults\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_preflight=0
      }
      in_preflight && /_validate_config_values/ { saw_preflight=1 }
      /_validate_config_values\(\)/ { in_validate=1; next }
      in_validate && /app_validate_port/ { saw_valport=1 }
      in_validate && /app_validate_bool/ { saw_valbool=1 }
      in_validate && /is_valid_dns_name/ { saw_valdomain=1 }
      in_validate && /app_validate_email "CERTBOT_EMAIL"/ { saw_email=1 }
      in_validate && /app_validate_image_repo/ { saw_image_repo=1 }
      in_validate && /app_validate_image_tag/ { saw_image_tag=1 }
      in_validate && /app_validate_git_ref "EXTRACT_TOOL_COMMIT"/ { saw_extract_commit=1 }
      in_validate && /app_validate_sha256 "EXTRACT_TOOL_SHA256"/ { saw_extract_sha=1 }
      in_validate && /app_validate_release_version "WEB_VAULT_VER"/ { saw_web_vault_ver=1 }
      in_validate && /^}/ { in_validate=0 }
      END {
        if (!(saw_preflight && saw_valport && saw_valbool && saw_valdomain && saw_email && saw_image_repo && saw_image_tag && saw_extract_commit && saw_extract_sha && saw_web_vault_ver)) {
          printf "%s Vaultwarden must validate ports, booleans, domain, certbot email, image settings, extract tool pin, and web vault version via _validate_config_values\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_vaultwarden.sh
  awk '
      /step "\$\(t app\.vaultwarden\.step\.certbot\)"/ { in_certbot=1; saw_email=0; next }
      in_certbot && /app_validate_email "CERTBOT_EMAIL"/ { saw_email=1 }
      in_certbot && /certbot certonly --webroot/ {
        if (!saw_email) {
          printf "%s Vaultwarden must validate CERTBOT_EMAIL immediately before certbot\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_certbot=0
      }
    ' impl/install_vaultwarden.sh
}

check_vaultwarden_apt_update_failures_are_reported() {
  if grep -R -n 'apt-get update -qq[[:space:]\\]*\\$' \
      impl/install_vaultwarden.sh 2>/dev/null | grep '\|\| warn'; then
    echo "Vaultwarden apt-get update failures must use an explicit conditional." >&2
    return 1
  fi
  awk '
      /app\.vaultwarden\.warn\.apt_update/ { saw_warn_key=1 }
      /\/var\/log\/apt\/\*/ { saw_guidance=1 }
      /app\.vaultwarden\.error\.deps_install/ { saw_install_key=1 }
      /apt-get install -y curl wget ca-certificates nginx certbot python3-certbot-nginx sqlite3 argon2 openssl fail2ban logrotate/ { saw_install_guidance=1 }
      /step "\$\(t app\.vaultwarden\.step\.deps\)"/ { in_block=1; saw_update_if=0; saw_warn=0; next }
      in_block && /if ! DEBIAN_FRONTEND=noninteractive apt-get update -qq; then/ { saw_update_if=1 }
      in_block && /warn "\$\(t app\.vaultwarden\.warn\.apt_update\)"/ { saw_warn=1 }
      in_block && /if ! DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \\/ { saw_install_if=1 }
      in_block && /error "\$\(t app\.vaultwarden\.error\.deps_install\)"/ { saw_install_error=1 }
      in_block && /success "\$\(t app\.vaultwarden\.success\.deps\)"/ {
        if (!(saw_warn_key && saw_guidance && saw_install_key && saw_install_guidance && saw_update_if && saw_warn && saw_install_if && saw_install_error)) {
          printf "%s Vaultwarden dependency installation must warn on apt-get update degradation and fail through an explicit install conditional with actionable guidance\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' apps/vaultwarden.sh impl/install_vaultwarden.sh
}

check_vaultwarden_install_surfaces_default_nginx_site_removal_failures() {
  awk '
      /step "\$\(t app\.vaultwarden\.step\.nginx_http\)"/ { in_nginx=1; saw_backup=0; saw_raw_rm=0; next }
      in_nginx && /app_nginx_default_site_backup/ { saw_backup=1 }
      in_nginx && /_vw_remove_file_or_error "\/etc\/nginx\/sites-enabled\/default" "VAULTWARDEN_DEFAULT_NGINX_SITE"/ { saw_backup=1 }
      in_nginx && /rm -f \/etc\/nginx\/sites-enabled\/default/ { saw_raw_rm=1 }
      in_nginx && /nginx -t \|\| error "\$\(t app\.vaultwarden\.error\.nginx_http_test\)"/ {
        if (!saw_backup || saw_raw_rm) {
          printf "%s Vaultwarden install must move the default Nginx site aside (recoverably) before testing Nginx config\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_nginx=0
      }
    ' impl/install_vaultwarden.sh
}

check_vaultwarden_workdir_cleanup_traps_are_nonfatal() {
  if grep -R -nE '\[\[ -d "\$\{WORK_DIR:-\}" \]\] && rm -rf "\$WORK_DIR"' \
      impl/install_vaultwarden.sh 2>/dev/null; then
    echo "Vaultwarden WORK_DIR cleanup traps must not return failure when the directory is already gone." >&2
    return 1
  fi
  local file
  # shellcheck disable=SC2043 # Fixed target; retain the shared per-file guard body.
  for file in impl/install_vaultwarden.sh; do
    awk '
        /_cleanup_(install|update)\(\)/ { in_func=1; saw_if=0; saw_rm=0; next }
        in_func && /if \[\[ -d "\$\{WORK_DIR:-\}" \]\]; then/ { saw_if=1 }
        in_func && /rm -rf "\$WORK_DIR"/ { saw_rm=1 }
        in_func && /^}/ {
          if (!(saw_if && saw_rm)) {
            printf "%s Vaultwarden WORK_DIR cleanup trap must use an explicit optional-directory branch\n", FILENAME > "/dev/stderr"
            exit 1
          }
          count++
          in_func=0
        }
        /deploy_add_exit_handler _cleanup_install/ { saw_install_handler=1 }
        /deploy_add_exit_handler _cleanup_update/ { saw_update_handler=1 }
        /trap '\''_cleanup_(install|update)'\'' EXIT/ {
          printf "%s Vaultwarden cleanup must register with deploy_add_exit_handler instead of replacing EXIT trap\n", FILENAME > "/dev/stderr"
          exit 1
        }
        END {
          if (count != 2 || !saw_install_handler || !saw_update_handler) {
            printf "%s verifier expected install and update WORK_DIR cleanup handlers\n", FILENAME > "/dev/stderr"
            exit 1
          }
        }
      ' "$file"
  done
}

check_vaultwarden_runtime_dir_failures_are_explicit() {
  awk '
      /app\.vaultwarden\.error\.user_create/ { saw_user_key=1 }
      /app\.vaultwarden\.error\.dir_create/ { saw_dir_key=1 }
      /Check permissions for %s and %s, then retry/ { saw_dir_guidance=1 }
      /app\.vaultwarden\.error\.dir_owner/ { saw_owner_key=1 }
      /app\.vaultwarden\.error\.data_dir_mode/ { saw_mode_key=1 }
      /app\.vaultwarden\.error\.web_vault_extract_dir/ { saw_extract_key=1 }
      /Web Vault extraction directory/ { saw_extract_guidance=1 }
      /app\.vaultwarden\.error\.nginx_dirs/ { saw_nginx_dir_key=1 }
      /Nginx support directories/ { saw_nginx_dir_guidance=1 }
      /app\.vaultwarden\.error\.fail2ban_dirs/ { saw_fail2ban_dir_key=1 }
      /Fail2Ban configuration directories/ { saw_fail2ban_dir_guidance=1 }
      END {
        if (!(saw_user_key && saw_dir_key && saw_dir_guidance && saw_owner_key && saw_mode_key && saw_extract_key && saw_extract_guidance && saw_nginx_dir_key && saw_nginx_dir_guidance && saw_fail2ban_dir_key && saw_fail2ban_dir_guidance)) {
          print "Vaultwarden runtime directory failures must provide actionable user, mkdir, chown, chmod, Web Vault extract-dir, Nginx-dir, and Fail2Ban-dir guidance." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/vaultwarden.sh
  awk '
      /step "\$\(t app\.vaultwarden\.step\.user_dirs\)"/ { in_dirs=1; saw_user_if=0; saw_user_error=0; saw_mkdir_if=0; saw_mkdir_error=0; saw_data_guard=0; saw_log_guard=0; saw_chown_if=0; saw_chown_error=0; saw_chmod_if=0; saw_chmod_error=0; next }
      in_dirs && /if ! useradd --system --no-create-home \\/ { saw_user_if=1 }
      in_dirs && /error "\$\(t app\.vaultwarden\.error\.user_create "\$VW_USER"\)"/ { saw_user_error=1 }
      in_dirs && /if ! mkdir -p "\$VW_DATA_DIR" "\$\(dirname "\$VW_LOG_FILE"\)" "\$VW_BACKUP_DIR"; then/ { saw_mkdir_if=1 }
      in_dirs && /error "\$\(t app\.vaultwarden\.error\.dir_create "\$VW_DATA_DIR" "\$VW_BACKUP_DIR"\)"/ { saw_mkdir_error=1 }
      in_dirs && /require_safe_path "VW_DATA_DIR" "\$VW_DATA_DIR"/ { saw_data_guard=1 }
      in_dirs && /require_safe_path "LOG_DIR" "\$\(dirname "\$VW_LOG_FILE"\)"/ { saw_log_guard=1 }
      in_dirs && /if ! chown -R "\$\{VW_USER\}:\$\{VW_GROUP\}" "\$VW_DATA_DIR" "\$\(dirname "\$VW_LOG_FILE"\)"; then/ { saw_chown_if=1 }
      in_dirs && /error "\$\(t app\.vaultwarden\.error\.dir_owner "\$\{VW_USER\}:\$\{VW_GROUP\}" "\$VW_DATA_DIR"\)"/ { saw_chown_error=1 }
      in_dirs && /if ! chmod 750 "\$VW_DATA_DIR"; then/ { saw_chmod_if=1 }
      in_dirs && /error "\$\(t app\.vaultwarden\.error\.data_dir_mode "\$VW_DATA_DIR"\)"/ { saw_chmod_error=1 }
      in_dirs && /success "\$\(t app\.vaultwarden\.success\.dirs\)"/ {
        if (!(saw_user_if && saw_user_error && saw_mkdir_if && saw_mkdir_error && saw_data_guard && saw_log_guard && saw_chown_if && saw_chown_error && saw_chmod_if && saw_chmod_error)) {
          printf "%s Vaultwarden install must fail explicitly when user creation, directory creation, ownership setup, or data-dir chmod fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_dirs=0
      }
      /if ! WORK_DIR=\$\(mktemp -d \/tmp\/vaultwarden_(install|update)_XXXXXX\); then/ { saw_workdir_if++ }
      /error "\$\(t app\.vaultwarden\.error\.image_extract\)"/ { saw_image_extract_error=1 }
      /if ! chmod \+x "\$\{workdir\}\/docker-image-extract"; then/ { saw_extract_chmod_if=1 }
      /if ! mkdir -p "\$out_dir"; then/ { saw_image_out_if=1 }
      /web-vault-extract/ { in_extract=1; saw_extract_if=0; saw_extract_error=0; next }
      in_extract && /if ! mkdir -p "\$_wv_extract_root"; then/ { saw_extract_if=1 }
      in_extract && /error "\$\(t app\.vaultwarden\.error\.web_vault_extract_dir "\$_wv_extract_root"\)"/ { saw_extract_error=1 }
      in_extract && /if tar -xzf .* -C "\$_wv_extract_root"; then/ {
        if (!(saw_extract_if && saw_extract_error)) {
          printf "%s Vaultwarden Web Vault extraction must fail explicitly when the extraction directory cannot be created\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_extract=0
      }
      /step "\$\(t app\.vaultwarden\.step\.nginx_http\)"/ { in_nginx=1; saw_nginx_dirs_if=0; saw_nginx_dirs_error=0; next }
      in_nginx && /if ! mkdir -p \/var\/www\/certbot \/etc\/nginx\/sites-available \/etc\/nginx\/sites-enabled; then/ { saw_nginx_dirs_if=1 }
      in_nginx && /error "\$\(t app\.vaultwarden\.error\.nginx_dirs "\$NGINX_CONF"\)"/ { saw_nginx_dirs_error=1 }
      in_nginx && /app_write_nginx_config_file "\$NGINX_CONF"/ {
        if (!(saw_nginx_dirs_if && saw_nginx_dirs_error)) {
          printf "%s Vaultwarden Nginx bootstrap must fail explicitly when support directories cannot be created\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_nginx=0
      }
      /step "\$\(t app\.vaultwarden\.step\.fail2ban\)"/ { in_fail2ban=1; saw_fail2ban_dirs_if=0; saw_fail2ban_dirs_error=0; next }
      in_fail2ban && /if ! mkdir -p \/etc\/fail2ban\/filter\.d \/etc\/fail2ban\/jail\.d; then/ { saw_fail2ban_dirs_if=1 }
      in_fail2ban && /error "\$\(t app\.vaultwarden\.error\.fail2ban_dirs\)"/ { saw_fail2ban_dirs_error=1 }
      in_fail2ban && /_write_fail2ban_config_file \/etc\/fail2ban\/filter\.d\/vaultwarden\.conf/ {
        if (!(saw_fail2ban_dirs_if && saw_fail2ban_dirs_error)) {
          printf "%s Vaultwarden Fail2Ban setup must fail explicitly when configuration directories cannot be created\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_fail2ban=0
      }
      END {
        if (!(saw_workdir_if >= 2 && saw_image_extract_error && saw_extract_chmod_if && saw_image_out_if)) {
          print "Vaultwarden image extraction must report workdir, helper chmod, and image output directory preparation failures." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_vaultwarden.sh
}

check_vaultwarden_backup_failures_include_followup_guidance() {
  awk '
      /app\.vaultwarden\.warn\.backup_failed_continue/ { saw_warn_key=1 }
      /\/opt\/vaultwarden-backups\/backup\.log/ { saw_log_guidance=1 }
      /\/usr\/local\/bin\/vaultwarden-backup/ { saw_cmd_guidance=1 }
      END {
        if (!(saw_warn_key && saw_log_guidance && saw_cmd_guidance)) {
          print "Vaultwarden backup failure warnings must point to backup.log and the manual backup command." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/vaultwarden.sh
  awk '
      /_backup_silent\(\)/ { in_block=1; saw_warn=0; saw_return=0; next }
      in_block && /warn "\$\(t app\.vaultwarden\.warn\.backup_failed_continue\)"/ { saw_warn=1 }
      in_block && /return 1/ { saw_return=1 }
      in_block && /^}/ {
        if (!(saw_warn && saw_return)) {
          printf "%s Vaultwarden silent backup helper must return failure after warning about backup creation failure\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_vaultwarden.sh
  awk '
      /info "\$\(t app\.vaultwarden\.info\.pre_update_backup\)"/ { in_update=1; saw_if=0; next }
      in_update && /if ! _backup_silent "pre-update"; then/ { saw_if=1 }
      in_update && /local _pre_update_svc_state/ {
        if (!saw_if) {
          printf "%s Vaultwarden pre-update backup must use an explicit conditional so backup failures do not abort the update under set -e\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_update=0
      }
    ' impl/install_vaultwarden.sh
  awk '
      /app\.vaultwarden\.error\.manual_backup_failed/ { saw_error_key=1 }
      /\/opt\/vaultwarden-backups\/backup\.log/ { saw_log_guidance=1 }
      /review the existing backups above/ { saw_existing_guidance=1 }
      END {
        if (!(saw_error_key && saw_log_guidance && saw_existing_guidance)) {
          print "Vaultwarden manual backup failures must point to backup.log and the existing backup list." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/vaultwarden.sh
  awk '
      /step "\$\(t app\.vaultwarden\.step\.manual_backup\)"/ { in_backup=1; saw_if=0; saw_flag=0; saw_error=0; next }
      in_backup && /local _backup_failed=0/ { saw_flag=1 }
      in_backup && /if ! _backup_silent "manual"; then/ { saw_if=1 }
      in_backup && /error "\$\(t app\.vaultwarden\.error\.manual_backup_failed\)"/ {
        saw_error=1
        if (!(saw_if && saw_flag)) {
          printf "%s Vaultwarden manual backup must handle silent-backup failures explicitly before exiting\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
      in_backup && /release_lock/ {
        if (!saw_error) {
          printf "%s Vaultwarden manual backup must fail explicitly after printing backup context\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_backup=0
      }
    ' impl/install_vaultwarden.sh
}

check_vaultwarden_binary_backups_use_shared_atomic_copy() {
  awk '
      /^backup_vaultwarden_binary\(\) \{/ { in_func=1; saw_atomic=0; next }
      in_func && /atomic_copy_file "\$VW_BIN" "\$backup_path"/ { saw_atomic=1 }
      in_func && /^}/ {
        if (!saw_atomic) {
          print "Vaultwarden binary backups must delegate atomic staging to atomic_copy_file." > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_vaultwarden.sh
}

check_vaultwarden_env_file_is_atomic() {
  if grep -R -n '^[[:space:]]*cat > "\$VW_ENV_FILE"' impl/install_vaultwarden.sh 2>/dev/null; then
    echo "Vaultwarden env files contain secrets and must be written through a temporary file before replacement." >&2
    return 1
  fi
  awk '
      /if ! _vw_env_tmp=\$\(mktemp "\$\(dirname "\$VW_ENV_FILE"\)\/\.vaultwarden\.env\./ { saw_tmp=1 }
      /error "\$\(t app\.vaultwarden\.error\.env_file "\$VW_ENV_FILE"\)"/ { saw_tmp_error=1 }
      /mv "\$_vw_env_tmp" "\$VW_ENV_FILE"/ { saw_mv=1 }
      /rm -f "\$_vw_env_tmp"/ { saw_cleanup=1 }
      END {
        if (!(saw_tmp && saw_tmp_error && saw_mv && saw_cleanup)) {
          print "Vaultwarden env file writes must report temp creation failures, stage, replace, and clean up temporary files." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_vaultwarden.sh
}

check_vaultwarden_binary_installs_are_atomic() {
  if grep -R -n 'install -m 755 -o root -g root .* "$VW_BIN"' impl/install_vaultwarden.sh 2>/dev/null; then
    echo "Vaultwarden binary installs must stage to a temporary file before replacing VW_BIN." >&2
    return 1
  fi
  awk '
      /app\.vaultwarden\.warn\.tmp_binary_cleanup_failed/ { saw_warn_key=1 }
      END {
        if (!saw_warn_key) {
          print "Vaultwarden must provide a localized temporary binary cleanup warning." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/vaultwarden.sh
  awk '
      /install_vaultwarden_binary\(\)/ { in_func=1; saw_helper=0; saw_dir=0; saw_dir_return=0; saw_tmp=0; saw_tmp_return=0; saw_install=0; saw_mv=0; saw_cleanup=0; saw_cleanup_warn=0; next }
      in_func && /app_install_executable_file "\$source_bin" "\$VW_BIN" root:root 0755/ { saw_helper=1 }
      in_func && /if ! mkdir -p "\$VW_BIN_DIR"; then/ { saw_dir=1 }
      in_func && saw_dir && /return 1/ { saw_dir_return=1 }
      in_func && /if ! bin_tmp=\$\(mktemp "\$\{VW_BIN\}\.XXXXXX"\); then/ { saw_tmp=1 }
      in_func && saw_tmp && /return 1/ { saw_tmp_return=1 }
      in_func && /install -m 755 -o root -g root "\$source_bin" "\$bin_tmp"/ { saw_install=1 }
      in_func && /mv "\$bin_tmp" "\$VW_BIN"/ { saw_mv=1 }
      in_func && /if ! rm -f "\$bin_tmp"; then/ { saw_cleanup=1 }
      in_func && /warn "\$\(t app\.vaultwarden\.warn\.tmp_binary_cleanup_failed "\$bin_tmp"\)"/ { saw_cleanup_warn=1 }
      in_func && /^}/ {
        if (!(saw_helper || (saw_dir && saw_dir_return && saw_tmp && saw_tmp_return && saw_install && saw_mv && saw_cleanup && saw_cleanup_warn))) {
          print "Vaultwarden binary install helper must delegate to the shared executable staging helper or preserve its atomic cleanup contract." > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_vaultwarden.sh
}

check_vaultwarden_admin_token_file_is_private() {
  if grep -R -n 'mktemp /tmp/vw_token_' impl/install_vaultwarden.sh 2>/dev/null; then
    echo "Vaultwarden admin token display files must not be created in world-writable /tmp." >&2
    return 1
  fi
  # The plaintext Admin Token must be persisted to a fixed mode-600 path
  # through an atomic helper, and never printed to the terminal or left in a
  # throwaway /root/.vaultwarden-admin-token.* file.
  awk '
      /^_write_admin_token_file\(\) \{/ { in_func=1 }
      in_func && /chmod 600 "\$tmp"/ { saw_chmod=1 }
      in_func && /mv -f "\$tmp" "\$VW_ADMIN_TOKEN_FILE"/ { saw_mv=1 }
      in_func && /rm -f "\$tmp"/ { saw_cleanup=1 }
      in_func && /^}/ { in_func=0 }
      /mktemp \/root\/\.vaultwarden-admin-token\.XXXXXX/ { saw_legacy_tmp=1 }
      /cat "\$\{_token_tmp\}"/ { saw_terminal_print=1 }
      /echo.*\$ADMIN_PLAIN/ { saw_terminal_print=1 }
      END {
        if (!(saw_chmod && saw_mv && saw_cleanup)) {
          print "Vaultwarden admin token file helper must be atomic and mode 600." > "/dev/stderr"
          exit 1
        }
        if (saw_legacy_tmp) {
          print "Vaultwarden must not use throwaway /root/.vaultwarden-admin-token.* temp files." > "/dev/stderr"
          exit 1
        }
        if (saw_terminal_print) {
          print "Vaultwarden must not print the plaintext Admin Token to the terminal." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_vaultwarden.sh
}

check_vaultwarden_extract_tool_is_pinned_and_verified() {
  if grep -R -n 'EXTRACT_TOOL_COMMIT="\${EXTRACT_TOOL_COMMIT:-main}"' impl/install_vaultwarden.sh 2>/dev/null; then
    echo "Vaultwarden must not default docker-image-extract to a floating branch." >&2
    return 1
  fi
  if grep -R -nE 'VW_IMAGE_TAG="\$\{VW_IMAGE_TAG:-(latest|latest-[^}]*)\}"' impl/install_vaultwarden.sh 2>/dev/null; then
    echo "Vaultwarden must not default to a mutable image tag." >&2
    return 1
  fi
  if grep -R -n 'EXTRACT_TOOL_SHA256="\${EXTRACT_TOOL_SHA256:-}"' impl/install_vaultwarden.sh 2>/dev/null; then
    echo "Vaultwarden must ship a pinned docker-image-extract SHA256 by default." >&2
    return 1
  fi
  awk '
      /app\.vaultwarden\.error\.extract_tool_sha_missing/ { saw_key=1 }
      /app\.vaultwarden\.error\.extract_tool_sha_tool_missing/ { saw_tool_key=1 }
      /if \[\[ -z "\$\{EXTRACT_TOOL_SHA256:-\}" \]\]; then/ { saw_empty_guard=1 }
      /error "\$\(t app\.vaultwarden\.error\.extract_tool_sha_missing\)"/ { saw_empty_error=1 }
      /if command -v sha256sum >\/dev\/null 2>&1; then/ { saw_sha256sum=1 }
      /_actual_sha256=\$\(sha256sum "\$\{workdir\}\/docker-image-extract" \| awk '\''\{print \$1\}'\''\)/ { saw_hash=1 }
      /elif command -v shasum >\/dev\/null 2>&1; then/ { saw_shasum=1 }
      /_actual_sha256=\$\(shasum -a 256 "\$\{workdir\}\/docker-image-extract" \| awk '\''\{print \$1\}'\''\)/ { saw_shasum_hash=1 }
      /error "\$\(t app\.vaultwarden\.error\.extract_tool_sha_tool_missing\)"/ { saw_tool_error=1 }
      /if \[\[ "\$_actual_sha256" != "\$EXTRACT_TOOL_SHA256" \]\]; then/ { saw_compare=1 }
      /success "\$\(t app\.vaultwarden\.success\.extract_tool_sha\)"/ { saw_success=1 }
      END {
        if (!(saw_key && saw_tool_key && saw_empty_guard && saw_empty_error && saw_sha256sum && saw_hash && saw_shasum && saw_shasum_hash && saw_tool_error && saw_compare && saw_success)) {
          print "Vaultwarden docker-image-extract downloads must be pinned, fail closed without a SHA or SHA tool, and verify before execution." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/vaultwarden.sh impl/install_vaultwarden.sh
}

check_vaultwarden_enable_failures_are_reported() {
  awk '
      /app\.vaultwarden\.warn\.service_enable_failed/ { saw_warn_key=1 }
      /if ! systemctl enable vaultwarden --quiet; then/ { saw_service_if=1 }
      /warn "\$\(t app\.vaultwarden\.warn\.service_enable_failed "vaultwarden" "vaultwarden"\)"/ { saw_service_warn=1 }
      /if ! systemctl enable nginx --quiet; then/ { saw_nginx_if=1 }
      /warn "\$\(t app\.vaultwarden\.warn\.service_enable_failed "nginx" "nginx"\)"/ { saw_nginx_warn=1 }
      /if ! systemctl enable fail2ban --quiet; then/ { saw_fail2ban_if=1 }
      /warn "\$\(t app\.vaultwarden\.warn\.service_enable_failed "fail2ban" "fail2ban"\)"/ { saw_fail2ban_warn=1 }
      END {
        if (!(saw_warn_key && saw_service_if && saw_service_warn && saw_nginx_if && saw_nginx_warn && saw_fail2ban_if && saw_fail2ban_warn)) {
          print "Vaultwarden must warn when service enablement fails for Vaultwarden, Nginx, or Fail2ban." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/vaultwarden.sh impl/install_vaultwarden.sh
}

check_vaultwarden_certbot_cron_failures_are_reported() {
  if grep -R -nE 'crontab -l.*crontab -' impl/install_vaultwarden.sh 2>/dev/null; then
    echo "Vaultwarden must not rewrite the whole root crontab for Certbot renewal; use an /etc/cron.d file instead." >&2
    return 1
  fi
  awk '
      /app\.vaultwarden\.error\.certbot_cron/ { saw_error_key=1 }
      /30 2 \* \* \* root certbot renew --quiet --post-hook/ { saw_guidance=1 }
      /_certbot_cron_file="\/etc\/cron\.d\/certbot-renew"/ { saw_file=1 }
      /_certbot_cron_tmp=\$\(mktemp "\$\{_certbot_cron_file\}\.XXXXXX"\)/ { saw_tmp=1 }
      /error "\$\(t app\.vaultwarden\.error\.certbot_cron\)"/ { saw_error=1 }
      /success "\$\(t app\.vaultwarden\.success\.certbot_cron\)"/ {
        if (!(saw_error_key && saw_guidance && saw_file && saw_tmp && saw_error)) {
          printf "%s Vaultwarden must write the Certbot renewal cron atomically to /etc/cron.d and fail explicitly with guidance\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' apps/vaultwarden.sh impl/install_vaultwarden.sh
}

check_vaultwarden_runtime_service_starts_are_explicit() {
  if grep -R -nE '^[[:space:]]*systemctl restart (nginx|fail2ban)$' \
      impl/install_vaultwarden.sh 2>/dev/null; then
    echo "Vaultwarden nginx/fail2ban restart paths must branch explicitly on command failure." >&2
    return 1
  fi
  awk '
      /step "\$\(t app\.vaultwarden\.step\.certbot\)"/ { in_nginx=1; saw_restart_wait=0; next }
      in_nginx && /if ! systemctl restart nginx \|\| ! wait_for_service nginx 10; then/ { saw_restart_wait=1 }
      in_nginx && /success "\$\(t app\.vaultwarden\.success\.nginx_ready\)"/ {
        if (!saw_restart_wait) {
          printf "%s Vaultwarden nginx startup must keep restart failure handling explicit\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_nginx=0
      }
      /JAIL/ { in_fail2ban=1; saw_fail2ban_if=0; next }
      in_fail2ban && /if ! systemctl restart fail2ban; then/ { saw_fail2ban_if=1 }
      in_fail2ban && /error "\$\(t app\.vaultwarden\.error\.fail2ban_start\)"/ { saw_fail2ban_error=1 }
      in_fail2ban && /success "\$\(t app\.vaultwarden\.success\.fail2ban\)"/ {
        if (!(saw_fail2ban_if && saw_fail2ban_error)) {
          printf "%s Vaultwarden fail2ban startup must branch explicitly on restart failure\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_fail2ban=0
      }
    ' impl/install_vaultwarden.sh
}

check_vaultwarden_service_start_paths_are_explicit() {
  if grep -R -nE '^[[:space:]]*systemctl start vaultwarden$' \
      impl/install_vaultwarden.sh 2>/dev/null; then
    echo "Vaultwarden service start paths must branch explicitly on command failure." >&2
    return 1
  fi
  awk '
      /^do_install\(\)/ { in_install=1; saw_start_wait=0; next }
      in_install && /if systemctl start vaultwarden && wait_for_service vaultwarden 20; then/ { saw_start_wait=1 }
      in_install && /^}/ {
        if (!saw_start_wait) {
          printf "%s Vaultwarden install must gate service success on an explicit start-and-wait branch\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_install=0
      }
      /^do_update\(\)/ { in_update=1; saw_start_wait_count=0; next }
      in_update && /if systemctl start vaultwarden && wait_for_service vaultwarden 20; then/ { saw_start_wait_count++ }
      in_update && /^}/ {
        if (saw_start_wait_count < 2) {
          printf "%s Vaultwarden update must gate both primary restart and rollback restart on explicit start-and-wait branches\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_update=0
      }
    ' impl/install_vaultwarden.sh
}

check_vaultwarden_install_cleanup_reports_systemctl_failures() {
  awk '
      /app\.vaultwarden\.warn\.cleanup_stop_failed/ { saw_stop_key=1 }
      /app\.vaultwarden\.warn\.cleanup_disable_failed/ { saw_disable_key=1 }
      /app\.vaultwarden\.warn\.cleanup_reload_failed/ { saw_reload_key=1 }
      END {
        if (!(saw_stop_key && saw_disable_key && saw_reload_key)) {
          print "Vaultwarden must provide localized install rollback cleanup warnings." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/vaultwarden.sh
  awk '
      /warn "\$\(t app\.vaultwarden\.warn\.service_cleanup\)"/ { in_cleanup=1; saw_stop=0; saw_disable=0; saw_reload=0; saw_suppressed=0; next }
      in_cleanup && /\|\| true/ { saw_suppressed=1 }
      in_cleanup && /warn "\$\(t app\.vaultwarden\.warn\.cleanup_stop_failed "vaultwarden" "vaultwarden"\)"/ { saw_stop=1 }
      in_cleanup && /warn "\$\(t app\.vaultwarden\.warn\.cleanup_disable_failed "vaultwarden" "vaultwarden"\)"/ { saw_disable=1 }
      in_cleanup && /warn "\$\(t app\.vaultwarden\.warn\.cleanup_reload_failed\)"/ { saw_reload=1 }
      in_cleanup && /error "\$\(t app\.vaultwarden\.error\.install_failed_start\)"/ {
        if (!(saw_stop && saw_disable && saw_reload) || saw_suppressed) {
          printf "%s Vaultwarden install rollback cleanup must warn on stop, disable, and daemon-reload failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_cleanup=0
      }
    ' impl/install_vaultwarden.sh
}

check_vaultwarden_install_rollback_validates_binary_path_before_removal() {
  awk '
      /warn "\$\(t app\.vaultwarden\.warn\.service_cleanup\)"/ { in_cleanup=1; saw_guard=0; saw_remove=0; saw_raw_rm=0; next }
      in_cleanup && /_require_safe_vw_bin_path/ { saw_guard=1 }
      in_cleanup && /_vw_remove_file_or_error "\$VW_BIN" "VW_BIN"/ {
        if (!saw_guard) {
          printf "%s Vaultwarden install rollback must validate VW_BIN before removing the failed binary\n", FILENAME > "/dev/stderr"
          exit 1
        }
        saw_remove=1
      }
      in_cleanup && /rm -f "\$VW_BIN"|rm -f "\$\{VW_BIN\}"/ { saw_raw_rm=1 }
      in_cleanup && /error "\$\(t app\.vaultwarden\.error\.install_failed_start\)"/ {
        if (!(saw_guard && saw_remove) || saw_raw_rm) {
          printf "%s Vaultwarden install rollback must guard VW_BIN and surface cleanup failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_cleanup=0
      }
    ' impl/install_vaultwarden.sh
}

check_vaultwarden_install_rollback_surfaces_service_file_removal_failures() {
  awk '
      /warn "\$\(t app\.vaultwarden\.warn\.service_cleanup\)"/ { in_cleanup=1; saw_remove=0; saw_raw_rm=0; next }
      in_cleanup && /_vw_remove_file_or_error "\/etc\/systemd\/system\/vaultwarden\.service" "VAULTWARDEN_SERVICE_FILE"/ { saw_remove=1 }
      in_cleanup && /rm -f \/etc\/systemd\/system\/vaultwarden\.service/ { saw_raw_rm=1 }
      in_cleanup && /if ! systemctl daemon-reload 2>\/dev\/null; then/ {
        if (!saw_remove || saw_raw_rm) {
          printf "%s Vaultwarden install rollback must surface service unit removal failures before daemon-reload\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
      in_cleanup && /error "\$\(t app\.vaultwarden\.error\.install_failed_start\)"/ { in_cleanup=0 }
    ' impl/install_vaultwarden.sh
}

check_vaultwarden_update_stop_failure_aborts_before_replace() {
  awk '
      /app\.vaultwarden\.error\.stop_service_failed/ { saw_key=1 }
      END {
        if (!saw_key) {
          print "Vaultwarden must provide an actionable update stop failure error." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/vaultwarden.sh
  awk '
      /local _pre_update_svc_state/ { in_update=1 }
      in_update && /info "\$\(t app\.vaultwarden\.info\.stop_service\)"/ { in_stop=1; saw_if=0; saw_error=0; saw_suppressed=0; next }
      in_stop && /systemctl stop vaultwarden 2>\/dev\/null \|\| true/ { saw_suppressed=1 }
      in_stop && /if ! systemctl stop vaultwarden 2>\/dev\/null; then/ { saw_if=1 }
      in_stop && /error "\$\(t app\.vaultwarden\.error\.stop_service_failed\)"/ { saw_error=1 }
      in_stop && /case \$ARCH in/ {
        if (!(saw_if && saw_error) || saw_suppressed) {
          printf "%s Vaultwarden update must abort before extraction when stopping the service fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_update=0
        in_stop=0
      }
    ' impl/install_vaultwarden.sh
}

check_vaultwarden_uninstall_stop_disable_failures_are_reported() {
  awk '
      /app\.vaultwarden\.error\.uninstall_stop_failed/ { saw_stop_error=1 }
      /app\.vaultwarden\.warn\.uninstall_stop_failed/ { saw_stop_warn=1 }
      /app\.vaultwarden\.warn\.uninstall_disable_failed/ { saw_disable_warn=1 }
      END {
        if (!(saw_stop_error && saw_stop_warn && saw_disable_warn)) {
          print "Vaultwarden must provide localized uninstall stop and disable failure messages." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/vaultwarden.sh
  awk '
      /do_uninstall\(\)/ { in_func=1 }
      in_func && /info "\$\(t app\.vaultwarden\.info\.stop_service\)"/ { in_uninstall=1; saw_stop_if=0; saw_active_if=0; saw_stop_error=0; saw_stop_warn=0; saw_disable_if=0; saw_disable_warn=0; saw_suppressed=0; next }
      in_uninstall && /systemctl (stop|disable).* \|\| true/ { saw_suppressed=1 }
      in_uninstall && /if ! systemctl stop vaultwarden 2>\/dev\/null; then/ { saw_stop_if=1 }
      in_uninstall && /if systemctl is-active --quiet vaultwarden 2>\/dev\/null; then/ { saw_active_if=1 }
      in_uninstall && /error "\$\(t app\.vaultwarden\.error\.uninstall_stop_failed\)"/ { saw_stop_error=1 }
      in_uninstall && /warn "\$\(t app\.vaultwarden\.warn\.uninstall_stop_failed\)"/ { saw_stop_warn=1 }
      in_uninstall && /if ! systemctl disable vaultwarden 2>\/dev\/null; then/ { saw_disable_if=1 }
      in_uninstall && /warn "\$\(t app\.vaultwarden\.warn\.uninstall_disable_failed\)"/ { saw_disable_warn=1 }
      in_uninstall && /rm -f \/etc\/systemd\/system\/vaultwarden\.service/ {
        if (!(saw_stop_if && saw_active_if && saw_stop_error && saw_stop_warn && saw_disable_if && saw_disable_warn) || saw_suppressed) {
          printf "%s Vaultwarden uninstall must abort when an active service cannot be stopped and warn on disable failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_uninstall=0
      }
      in_func && /^}/ { in_func=0 }
    ' impl/install_vaultwarden.sh
}

check_vaultwarden_install_summary_matches_health_state() {
  awk '
      /app\.vaultwarden\.summary\.title_ready/ { saw_title_ready=1 }
      /app\.vaultwarden\.summary\.title_pending/ { saw_title_pending=1 }
      END {
        if (!(saw_title_ready && saw_title_pending)) {
          print "Vaultwarden install summary strings must distinguish ready and pending health states." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/vaultwarden.sh
  awk '
      /step "\$\(t app\.vaultwarden\.step\.health\)"/ { in_install=1; saw_ready=0; saw_pending=0; saw_pending_title=0; saw_ready_title=0; next }
      in_install && /local _health_state="ready"/ { saw_ready=1 }
      in_install && /local _health_state="pending"/ { saw_pending=1 }
      in_install && /app\.vaultwarden\.summary\.title_pending/ { saw_pending_title=1 }
      in_install && /app\.vaultwarden\.summary\.title_ready/ { saw_ready_title=1 }
      in_install && /echo -e "  \$\{YELLOW\}\$\{BOLD\}\$\(t app\.vaultwarden\.summary\.important\)/ {
        if (!(saw_ready && saw_pending && saw_pending_title && saw_ready_title)) {
          printf "%s Vaultwarden install summary must branch on ready vs pending local health state\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_install=0
      }
    ' impl/install_vaultwarden.sh
}

check_vaultwarden_status_health_guidance_matches_local_probe() {
  awk '
      /app\.vaultwarden\.status\.local_response_warn/ { saw_warn=1 }
      /still initializing/ { saw_init=1 }
      END {
        if (!(saw_warn && saw_init)) {
          print "Vaultwarden status health warnings must acknowledge local initialization as a possible cause." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/vaultwarden.sh
  awk '
      /app\.vaultwarden\.status\.http_health/ { in_status=1; next }
      in_status && /HTTP_CODE=\$\(app_http_status_code "http:\/\/127\.0\.0\.1:\$\{VW_PORT\}\/" 5\)/ { saw_local_probe=1 }
      in_status && /app\.vaultwarden\.status\.local_response_warn/ { saw_warn=1 }
      in_status && /echo -e "\\n\$\{BOLD\}\[\$\(t app\.vaultwarden\.status\.tls\)\]\$\{NC\}"/ {
        if (!(saw_local_probe && saw_warn)) {
          printf "%s Vaultwarden status must pair the local 127.0.0.1 probe with the matching local-response warning\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_status=0
      }
    ' impl/install_vaultwarden.sh
}

check_vaultwarden_fail2ban_restart_failures_are_reported() {
  if grep -R -n 'systemctl restart fail2ban 2>/dev/null || true' \
      impl/install_vaultwarden.sh 2>/dev/null; then
    echo "Vaultwarden uninstall must not silently ignore fail2ban restart failures." >&2
    return 1
  fi
  awk '
      /app\.vaultwarden\.warn\.fail2ban_restart/ { saw_warn_key=1 }
      /rm -f \/etc\/fail2ban\/filter\.d\/vaultwarden\.conf/ { in_block=1; saw_restart_if=0; saw_warn=0; next }
      in_block && /if ! systemctl restart fail2ban 2>\/dev\/null; then/ { saw_restart_if=1 }
      in_block && /warn "\$\(t app\.vaultwarden\.warn\.fail2ban_restart\)"/ { saw_warn=1 }
      in_block && /success "\$\(t app\.vaultwarden\.success\.removed_fail2ban\)"/ {
        if (!(saw_warn_key && saw_restart_if && saw_warn)) {
          printf "%s Vaultwarden uninstall must warn when fail2ban restart fails after removing its rules\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' apps/vaultwarden.sh impl/install_vaultwarden.sh
}

check_vaultwarden_result_chains_are_explicit() {
  if grep -R -nE 'nginx -t && systemctl reload nginx[[:space:]\\]*$' \
      impl/install_vaultwarden.sh 2>/dev/null; then
    echo "Vaultwarden must use explicit conditionals for nginx reload outcomes." >&2
    return 1
  fi
  awk '
      /} \| app_write_nginx_config_file "\$NGINX_CONF"/ { in_https=1; saw_test=0; saw_reload=0; saw_success=0; saw_warn=0; next }
      in_https && /if nginx -t; then/ { saw_test=1 }
      in_https && /if systemctl reload nginx; then/ { saw_reload=1 }
      in_https && /success "\$\(t app\.vaultwarden\.success\.nginx_https\)"/ { saw_success=1 }
      in_https && /warn "\$\(t app\.vaultwarden\.warn\.nginx_https_test\)"/ { saw_warn=1 }
      in_https && /^    else$/ {
        if (!(saw_test && saw_reload && saw_success && saw_warn)) {
          printf "%s Vaultwarden HTTPS apply path must make nginx test and reload outcomes explicit\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_https=0
      }
    ' impl/install_vaultwarden.sh
}

check_vaultwarden_webvault_restore_cleans_partial() {
  if grep -R -nE '^[[:space:]]*\[\[ -d "\$_wv_(bak_ts|install_bak)" \]\] && mv "\$_wv_(bak_ts|install_bak)" "\$VW_WEB_DIR" \|\| true' \
      impl/install_vaultwarden.sh 2>/dev/null; then
    echo "Vaultwarden Web Vault backup restores must validate replacement and permissions." >&2
    return 1
  fi
  awk '
      /restore_web_vault_backup\(\)/ { in_helper=1; saw_rm=0; saw_rm_return=0; saw_mv=0; saw_mv_return=0; saw_guard=0; saw_chown=0; saw_chown_return=0; saw_chmod=0; saw_chmod_return=0; next }
      in_helper && /if ! safe_rm_dir "\$VW_WEB_DIR" "VW_WEB_DIR"; then/ { saw_rm=1 }
      in_helper && saw_rm && /return 1/ { saw_rm_return=1 }
      in_helper && /if ! mv "\$backup_dir" "\$VW_WEB_DIR"; then/ { saw_mv=1 }
      in_helper && saw_mv && /return 1/ { saw_mv_return=1 }
      in_helper && /require_safe_path "VW_WEB_DIR" "\$VW_WEB_DIR"/ { saw_guard=1 }
      in_helper && /if ! chown -R "\$\{VW_USER\}:\$\{VW_GROUP\}" "\$VW_WEB_DIR"; then/ { saw_chown=1 }
      in_helper && saw_chown && /return 1/ { saw_chown_return=1 }
      in_helper && /if ! chmod -R 750 "\$VW_WEB_DIR"; then/ { saw_chmod=1 }
      in_helper && saw_chmod && /return 1/ { saw_chmod_return=1 }
      in_helper && /^}/ {
        if (!(saw_rm && saw_rm_return && saw_mv && saw_mv_return && saw_guard && saw_chown && saw_chown_return && saw_chmod && saw_chmod_return)) {
          printf "%s restore helper must validate Web Vault replacement, ownership, and mode\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_helper=0
      }
    ' impl/install_vaultwarden.sh
}

check_vaultwarden_webvault_replacements_are_atomic() {
  if grep -R -nE 'cp -a "\$EXTRACTED_WEBVAULT_PATH" "\$VW_WEB_DIR"|tar -xzf "\$\{WORK_DIR\}/web-vault\.tar\.gz" -C "\$\(dirname "\$VW_WEB_DIR"\)"' \
      impl/install_vaultwarden.sh 2>/dev/null; then
    echo "Vaultwarden Web Vault installs and updates must stage replacement trees before swapping them live." >&2
    return 1
  fi
  awk '
      /deploy_web_vault_from_dir\(\)/ { in_helper=1; saw_guard=0; saw_dir=0; saw_dir_return=0; saw_tmp=0; saw_tmp_return=0; saw_copy=0; saw_chown=0; saw_chmod=0; saw_backup=0; saw_swap=0; saw_cleanup=0; next }
      in_helper && /require_safe_path "VW_WEB_DIR" "\$VW_WEB_DIR"/ { saw_guard=1 }
      in_helper && /if ! mkdir -p "\$\(dirname "\$VW_WEB_DIR"\)"; then/ { saw_dir=1 }
      in_helper && saw_dir && /return 1/ { saw_dir_return=1 }
      in_helper && /if ! staged_dir=\$\(mktemp -d "\$\{VW_WEB_DIR\}\.new\.XXXXXX"\); then/ { saw_tmp=1 }
      in_helper && saw_tmp && /return 1/ { saw_tmp_return=1 }
      in_helper && /cp -a "\$\{source_dir\}\/\." "\$staged_dir\/"/ { saw_copy=1 }
      in_helper && /chown -R "\$\{VW_USER\}:\$\{VW_GROUP\}" "\$staged_dir"/ { saw_chown=1 }
      in_helper && /chmod -R 750 "\$staged_dir"/ { saw_chmod=1 }
      in_helper && /mv "\$VW_WEB_DIR" "\$backup_dir"/ { saw_backup=1 }
      in_helper && /mv "\$staged_dir" "\$VW_WEB_DIR"/ { saw_swap=1 }
      in_helper && /rm -rf "\$staged_dir"/ { saw_cleanup=1 }
      in_helper && /^}/ {
        if (!(saw_guard && saw_dir && saw_dir_return && saw_tmp && saw_tmp_return && saw_copy && saw_chown && saw_chmod && saw_backup && saw_swap && saw_cleanup)) {
          printf "%s Vaultwarden Web Vault replacement helper must stage, permission, back up, and atomically swap trees\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_helper=0
      }
    ' impl/install_vaultwarden.sh
}

check_vaultwarden_install_webvault_replacement_is_recoverable() {
  awk '
      /step "\$\(t app\.vaultwarden\.step\.web_vault\)"/ {
        in_install=1
        saw_backup=0
        next
      }
      in_install && /mv "\$VW_WEB_DIR" "\$_wv_install_bak"/ { saw_backup=1 }
      in_install && /rm -rf "\$VW_WEB_DIR"/ {
        if (!saw_backup) {
          printf "%s removes the existing Web Vault before backing it up during install\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
      in_install && /restore_web_vault_backup "\$_wv_install_bak"/ {
        if (!saw_backup) {
          printf "%s restores the install Web Vault backup without backing it up first\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
      in_install && /info "\$\(t app\.vaultwarden\.info\.web_vault_path/ { in_install=0 }
    ' impl/install_vaultwarden.sh
}

check_vaultwarden_webvault_update_warnings_are_actionable() {
  awk '
      /app\.vaultwarden\.warn\.web_vault_update_extract/ { saw_extract=1 }
      /existing Web Vault was kept or a backup restore was attempted/ { saw_extract_state=1 }
      /Inspect %s and retry after fixing the archive or filesystem issue/ { saw_extract_guidance=1 }
      /app\.vaultwarden\.warn\.web_vault_update_download/ { saw_download=1 }
      /existing Web Vault was left unchanged/ { saw_unchanged=1 }
      /download the release manually from GitHub/ { saw_download_guidance=1 }
      /app\.vaultwarden\.warn\.web_vault_update_version/ { saw_version=1 }
      /Retry the update later after fixing network access to GitHub/ { saw_version_guidance=1 }
      END {
        if (!(saw_extract && saw_extract_state && saw_extract_guidance && saw_download && saw_unchanged && saw_download_guidance && saw_version && saw_version_guidance)) {
          print "Vaultwarden Web Vault update warnings must describe the preserved state and give actionable recovery guidance." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/vaultwarden.sh
  awk '
      /step "\$\(t app\.vaultwarden\.step\.update_web_vault\)"/ { in_update=1; next }
      in_update && /warn "\$\(t app\.vaultwarden\.warn\.web_vault_update_extract "\$VW_WEB_DIR"\)"/ { saw_extract_warn=1 }
      in_update && /warn "\$\(t app\.vaultwarden\.warn\.web_vault_update_download\)"/ { saw_download_warn=1 }
      in_update && /warn "\$\(t app\.vaultwarden\.warn\.web_vault_update_version\)"/ { saw_version_warn=1 }
      in_update && /if ss -ltn 2>\/dev\/null \| grep -qE/ { in_update=0 }
      END {
        if (!(saw_extract_warn && saw_download_warn && saw_version_warn)) {
          print "Vaultwarden Web Vault update path must use the dedicated actionable warning messages for extract, download, and version failures." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_vaultwarden.sh
}

check_vaultwarden_webvault_archives_are_validated() {
  awk '
      /app\.vaultwarden\.error\.web_vault_archive_empty/ { saw_empty=1 }
      /app\.vaultwarden\.error\.web_vault_archive_small/ { saw_small=1 }
      /app\.vaultwarden\.error\.web_vault_archive_format/ { saw_format=1 }
      /app\.vaultwarden\.warn\.web_vault_archive_cleanup_failed/ { saw_warn=1 }
      END {
        if (!(saw_empty && saw_small && saw_format && saw_warn)) {
          print "Vaultwarden Web Vault archive validation messages must cover empty, tiny, non-gzip, and cleanup failure cases." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/vaultwarden.sh
  local file
  # shellcheck disable=SC2043 # Fixed target; retain the shared per-file guard body.
  for file in impl/install_vaultwarden.sh; do
    awk '
        /_verify_web_vault_archive\(\)/ {
          in_helper=1
          saw_empty=0
          saw_small=0
          saw_magic=0
          saw_nonfatal=0
          saw_cleanup_if=0
          saw_cleanup_warn=0
          next
        }
        in_helper && /^}/ {
          if (!(saw_empty && saw_small && saw_magic && saw_nonfatal && saw_cleanup_if && saw_cleanup_warn)) {
            printf "%s must validate downloaded Web Vault archives before extraction\n", FILENAME > "/dev/stderr"
            exit 1
          }
          in_helper=0
        }
        in_helper && /\[\[ ! -s "\$archive" \]\]/ { saw_empty=1 }
        in_helper && /\[\[ "\$size" -lt 65536 \]\]/ { saw_small=1 }
        in_helper && /"\$magic" != "1f8b"/ { saw_magic=1 }
        in_helper && /local mode="\$\{2:-fatal\}"/ { saw_nonfatal=1 }
        in_helper && /if ! rm -f "\$archive"; then/ { saw_cleanup_if=1 }
        in_helper && /warn "\$\(t app\.vaultwarden\.warn\.web_vault_archive_cleanup_failed "\$archive"\)"/ { saw_cleanup_warn=1 }
        /wget -q --show-progress -O "\$\{WORK_DIR\}\/web-vault\.tar\.gz" "\$WV_URL"/ { saw_download=1; next }
        saw_download && /^[[:space:]]*_verify_web_vault_archive "\$\{WORK_DIR\}\/web-vault\.tar\.gz"$/ { saw_install_verify=1; saw_download=0 }
        saw_download && /^[[:space:]]*if _verify_web_vault_archive "\$\{WORK_DIR\}\/web-vault\.tar\.gz" nonfatal; then/ { saw_update_verify=1; saw_download=0 }
        END {
          if (!(saw_install_verify && saw_update_verify)) {
            printf "%s must validate Web Vault archives after install and update downloads\n", FILENAME > "/dev/stderr"
            exit 1
          }
        }
      ' "$file"
  done
}

check_vaultwarden_legacy_extract_tool_config_is_usable() {
  local tmp_dir conf
  tmp_dir="$(mktemp -d)"
  conf="${tmp_dir}/deploy.conf"
  printf 'EXTRACT_TOOL_COMMIT=main\nEXTRACT_TOOL_SHA256=""\n' > "$conf"

  cat > "${tmp_dir}/stat" <<'STUB'
#!/usr/bin/env bash
case "${2:-}" in
  %U) echo root ;;
  %a) echo 600 ;;
  *) /usr/bin/stat "$@" ;;
esac
STUB
  chmod +x "${tmp_dir}/stat"

  PATH="${tmp_dir}:$PATH" "$BASH_BIN" -c '
    set -euo pipefail
    source "$1/lib/core.sh"
    source "$1/impl/install_vaultwarden.sh"
    load_config_file "$2" "${CONFIG_KEYS[@]}"
    _VW_DERIVE_PATHS
    _validate_config_values
    [[ "$EXTRACT_TOOL_COMMIT" == "4273b2796da5055e431b4db5efe29a71bba12b45" ]] \
      || { echo "legacy EXTRACT_TOOL_COMMIT=main was not migrated: [$EXTRACT_TOOL_COMMIT]" >&2; exit 1; }
    [[ "$EXTRACT_TOOL_SHA256" == "a58f4995f568d66d9908649d4df7fc8c36f72096ca5e01f4c2c4291285125685" ]] \
      || { echo "empty EXTRACT_TOOL_SHA256 clobbered the pinned default: [$EXTRACT_TOOL_SHA256]" >&2; exit 1; }
    EXTRACT_TOOL_COMMIT="4273b2796da5055e431b4db5efe29a71bba12b45"
    _VW_DERIVE_PATHS
    [[ "$EXTRACT_TOOL_COMMIT" == "4273b2796da5055e431b4db5efe29a71bba12b45" ]] \
      || { echo "an explicitly pinned commit was unexpectedly rewritten: [$EXTRACT_TOOL_COMMIT]" >&2; exit 1; }
    exit 0
  ' _ "$ROOT_DIR" "$conf"

  rm -rf "$tmp_dir"
}


check_vaultwarden_image_digest_version_contract() {
  "$BASH_BIN" -c '
    set -euo pipefail
    tmp_dir="$(mktemp -d)"
    trap '"'"'rm -rf "$tmp_dir"'"'"' EXIT
    digest="sha256:aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    source lib/core.sh
    APP_ID=vaultwarden
    APP_NAME=Vaultwarden
    VW_IMAGE_DIGEST="$digest"
    INSTALLED_IMAGE_DIGEST="sha256:bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    app_conf_file() { printf "%s" "$tmp_dir/missing.conf"; }
    source impl/install_vaultwarden.sh

    [[ "$(_vw_image_reference)" == "vaultwarden/server:${digest}" ]]
    result="$(_vw_check_update_json "" 0 0)"
    [[ "$(state_json_field "$result" installed)" == "$INSTALLED_IMAGE_DIGEST" ]]
    [[ "$(state_json_field "$result" latest)" == "$digest" ]]
    [[ "$(state_json_field "$result" update_state)" == update_available ]]
    [[ "$(state_json_field "$result" source)" == docker_image ]]
    [[ "$(state_json_field "$result" cache_state)" == pinned ]]
    INSTALLED_IMAGE_DIGEST="$digest"
    result="$(_vw_check_update_json "" 0 0)"
    [[ "$(state_json_field "$result" update_state)" == up_to_date ]]
    status="$(_vw_status_version_json)"
    [[ "$(state_json_field "$status" update_state)" == up_to_date ]]
  '
  grep -Fq 'VW_IMAGE_DIGEST' impl/install_vaultwarden.sh
  grep -Fq 'INSTALLED_IMAGE_DIGEST INSTALLED_VERSION' impl/install_vaultwarden.sh
  grep -Fq 'app.vaultwarden.error.image_digest_invalid' apps/vaultwarden.sh
  grep -Fq '"$image_reference" >&2' impl/install_vaultwarden.sh
  grep -Fq '_vw_pinned_image_json' impl/install_vaultwarden.sh
}
