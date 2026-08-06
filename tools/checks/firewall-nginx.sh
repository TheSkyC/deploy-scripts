# shellcheck shell=bash
# shellcheck source=../verify.sh
# System-config atomic-write and diagnostics guardrails: firewall, nginx, cron/logrotate, fail2ban, keyring, apt sources, and systemd units.

check_keyring_writes_are_atomic() {
  if grep -R -nE '(^[[:space:]]*-o /usr/share/postgresql-common/pgdg/|gpg .*--dearmor -o /usr/share/keyrings/)' impl dist 2>/dev/null; then
    echo "Write apt keyrings to a temporary file before replacing the final keyring." >&2
    return 1
  fi
  awk '
      /(postgres_keyring_dir|redis_keyring_dir)=/ { saw_dir_var=1 }
      /if ! install -d "\$(pg_keyring_dir|redis_keyring_dir)"; then/ { saw_dir_if=1 }
      /error "\$\(t app\.sub2api\.error\.(postgres|redis)_keyring_dir "\$(pg_keyring_dir|redis_keyring_dir)"\)"/ { saw_dir_error=1 }
      /if ! (pg_key_tmp|redis_key_tmp)="?\$\(mktemp/ { saw_tmp=1 }
      /error "\$\(t app\.sub2api\.error\.(postgres|redis)_key\)"/ { saw_tmp_error=1 }
      /(curl .* -o "\$pg_key_tmp"|gpg .* --dearmor -o "\$redis_key_tmp")/ { saw_write=1 }
      /mv "\$(pg_key_tmp|redis_key_tmp)" "\$(pg_keyring|redis_keyring)"/ { saw_mv=1 }
      /rm -f "\$(pg_key_tmp|redis_key_tmp)"/ { saw_cleanup=1 }
      END {
        if (!(saw_dir_var && saw_dir_if && saw_dir_error && saw_tmp && saw_tmp_error && saw_write && saw_mv && saw_cleanup)) {
          print "Apt keyring writes must prepare directories, stage, replace, and clean up temporary files." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_apt_sources_are_atomic() {
  if grep -R -nE '^[[:space:]]*(echo|printf).*>[[:space:]]*/etc/apt/sources\.list\.d/' impl dist 2>/dev/null; then
    echo "Apt source lists must be written through temporary files before replacement." >&2
    return 1
  fi
  awk '
      /apt_source_dir="\/etc\/apt\/sources\.list\.d"/ { saw_dir_var=1 }
      /if ! mkdir -p "\$apt_source_dir"; then/ { saw_dir_if=1 }
      /error "\$\(t app\.sub2api\.error\.(postgres|redis)_source_dir "\$apt_source_dir"\)"/ { saw_dir_error=1 }
      /if ! (pg_source_tmp|redis_source_tmp)=\$\(mktemp/ { saw_tmp=1 }
      /error "\$\(t app\.sub2api\.error\.(postgres|redis)_source\)"/ { saw_tmp_error=1 }
      /mv "\$(pg_source_tmp|redis_source_tmp)" "\$(pg_source_list|redis_source_list)"/ { saw_mv=1 }
      /rm -f "\$(pg_source_tmp|redis_source_tmp)"/ { saw_cleanup=1 }
      END {
        if (!(saw_dir_var && saw_dir_if && saw_dir_error && saw_tmp && saw_tmp_error && saw_mv && saw_cleanup)) {
          print "Apt source list writes must prepare directories, stage, replace, and clean up temporary files." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_iptables_rules_are_atomic() {
  if grep -R -nE '^[[:space:]]*iptables-save > /etc/iptables/rules\.v4' impl dist 2>/dev/null; then
    echo "iptables rules must be saved to a temporary file before replacing rules.v4." >&2
    return 1
  fi
  awk '
      /iptables_dir="\/etc\/iptables"/ { saw_dir=1 }
      /if mkdir -p "\$iptables_dir"; then/ { saw_dir_if=1 }
      /app_prefix\}\.warn\.iptables_write_failed/ { saw_warn=1 }
      /if ! iptables_tmp=\$\(mktemp "\$\{iptables_rules\}\.XXXXXX"\); then/ { saw_tmp=1 }
      /iptables-save > "\$iptables_tmp"/ { saw_save=1 }
      /mv "\$iptables_tmp" "\$iptables_rules"/ { saw_mv=1 }
      /rm -f "\$iptables_tmp"/ { saw_cleanup=1 }
      END {
        if (!(saw_dir && saw_dir_if && saw_warn && saw_tmp && saw_save && saw_mv && saw_cleanup)) {
          print "iptables rules writes must prepare directories, stage, replace, and clean up temporary files." > "/dev/stderr"
          exit 1
        }
      }
    ' lib/app.sh dist/install_newapi.sh dist/install_sub2api.sh
}

check_netfilter_persistent_save_reports_failures() {
  if grep -R -nE 'netfilter-persistent save 2>/dev/null( && success .*\\|\\| true|[[:space:]]*\\[?;?)' \
      impl/install_newapi.sh impl/install_sub2api.sh impl/install_vaultwarden.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "netfilter-persistent save failures must not be silently ignored." >&2
    return 1
  fi
  awk '
      /if command -v netfilter-persistent &>\/dev\/null; then/ {
        in_block=1; saw_save=0; saw_success=0; saw_warn=0
        block_indent=$0; sub(/[^ \t].*/, "", block_indent)
        next
      }
      in_block && /if netfilter-persistent save 2>\/dev\/null; then/ { saw_save=1; next }
      in_block && /success "\$\(t app\.(newapi|sub2api|vaultwarden)\.success\.iptables_saved\)"/ { saw_success=1; next }
      in_block && /success "\$\(t "\$\{app_prefix\}\.success\.iptables_saved"\)"/ { saw_success=1; next }
      in_block && /warn "\$\(t app\.(newapi|sub2api|vaultwarden)\.warn\.iptables_not_persisted\)"/ { saw_warn=1; next }
      in_block && /warn "\$\(t "\$\{app_prefix\}\.warn\.iptables_not_persisted"\)"/ { saw_warn=1; next }
      in_block && ($0 ~ ("^" block_indent "elif command -v iptables-save ") || $0 == (block_indent "else")) {
        if (!(saw_save && saw_success && saw_warn)) {
          printf "%s netfilter-persistent save must report both success and failure outcomes\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' lib/app.sh impl/install_vaultwarden.sh dist/install_vaultwarden.sh
}

check_systemd_units_are_atomic() {
  if grep -R -nE '^[[:space:]]*cat > "?/etc/systemd/system/|^[[:space:]]*cat > "\/etc\/systemd\/system/\$\{SERVICE_NAME\}\.service"' impl dist 2>/dev/null; then
    echo "systemd unit files must be written through temporary files before replacement." >&2
    return 1
  fi
  awk '
      /systemd_write_unit "\$unit_path"/ { saw_helper=1 }
      /error "\$\(t app\.(newapi|sub2api|cyberstrikeai|vaultwarden|tickflow)\.error\.(systemd_unit|systemd|service_write)/ { saw_error=1 }
      END {
        if (!(saw_helper && saw_error)) {
          print "systemd unit writes must use systemd_write_unit and report write failures." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh impl/install_cyberstrikeai.sh impl/install_vaultwarden.sh impl/install_tickflow.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_cyberstrikeai.sh dist/install_vaultwarden.sh dist/install_tickflow.sh
}

check_systemd_daemon_reloads_are_explicit() {
  if grep -R -nE '^[[:space:]]*systemctl daemon-reload$' impl dist 2>/dev/null; then
    echo "systemd daemon reload failures must be handled explicitly or intentionally ignored in cleanup paths." >&2
    return 1
  fi
  awk '
      /app\.newapi\.error\.systemd_reload/ { saw_newapi_key=1 }
      /app\.sub2api\.error\.systemd_reload/ { saw_sub2api_key=1 }
      /app\.cyberstrikeai\.error\.systemd_reload/ { saw_cyberstrikeai_key=1 }
      /app\.vaultwarden\.error\.systemd_reload/ { saw_vaultwarden_key=1 }
      END {
        if (!(saw_newapi_key && saw_sub2api_key && saw_cyberstrikeai_key && saw_vaultwarden_key)) {
          print "All systemd apps must define actionable daemon reload failure messages." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/newapi.sh apps/sub2api.sh apps/cyberstrikeai.sh apps/vaultwarden.sh
  awk '
      /if ! systemctl daemon-reload; then/ { reloads++ }
      /error "\$\(t app\.newapi\.error\.systemd_reload "\$SERVICE_NAME"\)"/ { errors++ }
      END {
        if (!(reloads == 3 && errors == 3)) {
          printf "%s NewAPI must handle install, update, and uninstall daemon reload failures explicitly\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_newapi.sh
  awk '
      /if ! systemctl daemon-reload; then/ { reloads++ }
      /error "\$\(t app\.newapi\.error\.systemd_reload "\$SERVICE_NAME"\)"/ { errors++ }
      END {
        if (!(reloads == 3 && errors == 3)) {
          printf "%s NewAPI must handle install, update, and uninstall daemon reload failures explicitly\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' dist/install_newapi.sh
  awk '
      /if ! systemctl daemon-reload; then/ { reloads++ }
      /error "\$\(t app\.sub2api\.error\.systemd_reload "\$SERVICE_NAME"\)"/ { errors++ }
      END {
        if (!(reloads == 3 && errors == 3)) {
          printf "%s Sub2API must handle install, update, and uninstall daemon reload failures explicitly\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_sub2api.sh
  awk '
      /if ! systemctl daemon-reload; then/ { reloads++ }
      /error "\$\(t app\.sub2api\.error\.systemd_reload "\$SERVICE_NAME"\)"/ { errors++ }
      END {
        if (!(reloads == 3 && errors == 3)) {
          printf "%s Sub2API must handle install, update, and uninstall daemon reload failures explicitly\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' dist/install_sub2api.sh
  awk '
      /if ! systemctl daemon-reload; then/ { reloads++ }
      /error "\$\(t app\.cyberstrikeai\.error\.systemd_reload "\$SERVICE_NAME"\)"/ { errors++ }
      END {
        if (!(reloads == 2 && errors == 2)) {
          printf "%s CyberStrikeAI must handle install and uninstall daemon reload failures explicitly\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_cyberstrikeai.sh
  awk '
      /if ! systemctl daemon-reload; then/ { reloads++ }
      /error "\$\(t app\.cyberstrikeai\.error\.systemd_reload "\$SERVICE_NAME"\)"/ { errors++ }
      END {
        if (!(reloads == 2 && errors == 2)) {
          printf "%s CyberStrikeAI must handle install and uninstall daemon reload failures explicitly\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' dist/install_cyberstrikeai.sh
  awk '
      /if ! systemctl daemon-reload; then/ { reloads++ }
      /error "\$\(t app\.vaultwarden\.error\.systemd_reload\)"/ { errors++ }
      END {
        if (!(reloads == 2 && errors == 2)) {
          printf "%s Vaultwarden must handle install and uninstall daemon reload failures explicitly\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_vaultwarden.sh
  awk '
      /if ! systemctl daemon-reload; then/ { reloads++ }
      /error "\$\(t app\.vaultwarden\.error\.systemd_reload\)"/ { errors++ }
      END {
        if (!(reloads == 2 && errors == 2)) {
          printf "%s Vaultwarden must handle install and uninstall daemon reload failures explicitly\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' dist/install_vaultwarden.sh
}

check_certbot_diagnostics_use_stderr() {
  if grep -R -n 'certbot certonly .*2>&1; then' \
      impl/install_vaultwarden.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "Vaultwarden certbot diagnostics must be written to stderr." >&2
    return 1
  fi
  awk '
      /step "\$\(t app\.vaultwarden\.step\.certbot\)"/ { in_block=1; saw_certbot=0; saw_stderr=0; next }
      in_block && /if certbot certonly --webroot/ { saw_certbot=1 }
      in_block && /--non-interactive >&2; then/ { saw_stderr=1 }
      in_block && /if systemctl list-timers certbot/ {
        if (!(saw_certbot && saw_stderr)) {
          printf "%s Vaultwarden certbot flow must send diagnostics to stderr\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
}

check_cron_logrotate_are_atomic() {
  if grep -R -nE '^[[:space:]]*cat > (/etc/logrotate\.d/|"\$LOGROTATE_FILE")|^[[:space:]]*> /etc/cron\.d/|^[[:space:]]*cat > "\$CRON_FILE"' impl dist 2>/dev/null; then
    echo "cron and logrotate configs must be written through temporary files before replacement." >&2
    return 1
  fi
  awk '
      /if ! (cron_tmp|_vw_cron_tmp|logrotate_tmp|_vw_logrotate_tmp)=\$\(mktemp/ { saw_tmp=1 }
      /error "\$\(t app\.(newapi|sub2api|cyberstrikeai|vaultwarden)\.error\.(cron|cron_backup|auto_backup|logrotate)\)"/ { saw_tmp_error=1 }
      /mv "\$(cron_tmp|_vw_cron_tmp|logrotate_tmp|_vw_logrotate_tmp)" "\$(cron_file|_vw_cron_file|logrotate_file|_vw_logrotate_file|CRON_FILE|LOGROTATE_FILE)"/ { saw_mv=1 }
      /rm -f "\$(cron_tmp|_vw_cron_tmp|logrotate_tmp|_vw_logrotate_tmp)"/ { saw_cleanup=1 }
      END {
        if (!(saw_tmp && saw_tmp_error && saw_mv && saw_cleanup)) {
          print "cron and logrotate config writes must stage, replace, clean up temporary files, and report temp creation failures." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh impl/install_cyberstrikeai.sh impl/install_vaultwarden.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_cyberstrikeai.sh dist/install_vaultwarden.sh
}

check_logrotate_writes_use_shared_helper() {
  grep -Fq 'app_write_logrotate() {' lib/app.sh     && grep -Fq 'app_write_logrotate "/etc/logrotate.d/new-api" "$LOG_DIR" "app.newapi.error.logrotate" "app.newapi.success.logrotate"' impl/install_newapi.sh     && grep -Fq 'app_write_logrotate "/etc/logrotate.d/new-api" "$LOG_DIR" "app.newapi.error.logrotate" "app.newapi.success.logrotate"' dist/install_newapi.sh     && grep -Fq 'app_write_logrotate "/etc/logrotate.d/sub2api" "$LOG_DIR" "app.sub2api.error.logrotate" "app.sub2api.success.logrotate"' impl/install_sub2api.sh     && grep -Fq 'app_write_logrotate "/etc/logrotate.d/sub2api" "$LOG_DIR" "app.sub2api.error.logrotate" "app.sub2api.success.logrotate"' dist/install_sub2api.sh     && grep -Fq 'app_write_logrotate "$LOGROTATE_FILE" "$LOG_DIR" "app.cyberstrikeai.error.logrotate" "app.cyberstrikeai.success.logrotate"' impl/install_cyberstrikeai.sh     && grep -Fq 'app_write_logrotate "$LOGROTATE_FILE" "$LOG_DIR" "app.cyberstrikeai.error.logrotate" "app.cyberstrikeai.success.logrotate"' dist/install_cyberstrikeai.sh     || {
      echo "NewAPI, Sub2API, and CyberStrikeAI logrotate configs must be written through the shared app_write_logrotate helper." >&2
      return 1
    }
  if grep -nE '^_write_logrotate\(\)' impl/install_newapi.sh impl/install_sub2api.sh dist/install_newapi.sh dist/install_sub2api.sh; then
    echo "NewAPI and Sub2API must not define a per-app _write_logrotate copy." >&2
    return 1
  fi
  if grep -nE '^write_logrotate\(\)' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh; then
    echo "CyberStrikeAI must not define a per-app write_logrotate copy." >&2
    return 1
  fi
}

check_nginx_configs_are_atomic() {
  if grep -R -nE '^[[:space:]]*cat > (/etc/nginx/sites-available/|"\$NGINX_CONF")|^[[:space:]]*} >> "\$NGINX_CONF"' \
      impl dist 2>/dev/null; then
    echo "Nginx site configs must be written through temporary files before replacement." >&2
    return 1
  fi
  if grep -R -nE '^[[:space:]]*ln -s[f]? .*sites-enabled' impl dist 2>/dev/null; then
    echo "Nginx sites-enabled symlinks must be staged before replacement." >&2
    return 1
  fi
  awk '
      /^_write_nginx_(config_file|site_link)\(\)/ {
        printf "%s per-app Nginx helpers must be removed in favor of lib/app.sh shared helpers\n", FILENAME > "/dev/stderr"
        exit 1
      }
      /app_write_nginx_config_file\(\)/ { in_cfg=1; saw_cfg_atomic=0; saw_cfg_error=0; next }
      in_cfg && /atomic_write_file "\$nginx_conf" 644 root:root/ { saw_cfg_atomic=1 }
      in_cfg && /error "\$\(t "\$error_key" "\$nginx_conf"\)"/ { saw_cfg_error=1 }
      in_cfg && /^}/ {
        if (!(saw_cfg_atomic && saw_cfg_error)) {
          printf "%s shared Nginx config helper must use atomic_write_file and report failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_cfg=0
      }
      /app_write_nginx_site_link\(\)/ { in_link=1; saw_link_atomic=0; saw_link_error=0; next }
      in_link && /atomic_symlink "\$target" "\$link_path"/ { saw_link_atomic=1 }
      in_link && /error "\$\(t "\$error_key" "\$target"\)"/ { saw_link_error=1 }
      in_link && /^}/ {
        if (!(saw_link_atomic && saw_link_error)) {
          printf "%s shared Nginx site link helper must use atomic_symlink and report failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_link=0
      }
    ' lib/app.sh \
      dist/install_blog.sh dist/install_cyberstrikeai.sh dist/install_sub2api.sh dist/install_vaultwarden.sh
  awk '
      FNR == 1 {
        if (NR > 1 && !(prev_cfg && prev_link)) {
          printf "%s Nginx site config writes must use the shared app_write_nginx_config_file / app_write_nginx_site_link helpers\n", prev_file > "/dev/stderr"
          exit 1
        }
        prev_cfg=0; prev_link=0; prev_file=FILENAME
      }
      /^_write_nginx_(config_file|site_link)\(\)/ {
        printf "%s per-app Nginx helpers must be removed in favor of lib/app.sh shared helpers\n", FILENAME > "/dev/stderr"
        exit 1
      }
      /if ! mkdir -p \/etc\/nginx\/sites-available \/etc\/nginx\/sites-enabled; then/ { saw_nginx_dirs=1 }
      /app_write_nginx_config_file "\$NGINX_CONF"/ { prev_cfg=1 }
      /app_write_nginx_config_file "\$nginx_conf"/ { prev_cfg=1 }
      /app_write_nginx_site_link/ { prev_link=1 }
      END {
        if (!(prev_cfg && prev_link) || !saw_nginx_dirs) {
          printf "%s Nginx site config writes must prepare directories and use the shared app_write_nginx_config_file / app_write_nginx_site_link helpers\n", prev_file > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_sub2api.sh impl/install_cyberstrikeai.sh impl/install_vaultwarden.sh impl/install_blog.sh
}

check_nginx_main_config_edits_are_atomic() {
  if grep -R -nE '^[[:space:]]*sed -i ' impl dist 2>/dev/null; then
    echo "Nginx main config edits must be staged through a temporary file before replacement." >&2
    return 1
  fi
  awk '
      /nginx_main_tmp=\$\(mktemp "\$\{nginx_main_conf\}\.XXXXXX"\)/ { saw_tmp=1 }
      /awk .*/ { saw_render=1 }
      /mv "\$nginx_main_tmp" "\$nginx_main_conf"/ { saw_mv=1 }
      /rm -f "\$nginx_main_tmp"/ { saw_cleanup=1 }
      END {
        if (!(saw_tmp && saw_render && saw_mv && saw_cleanup)) {
          print "Nginx main config edits must stage, replace, and clean up temporary files." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_nginx_test_failures_report_diagnostics() {
  if grep -R -n 'nginx -t >&2 2>/dev/null' impl/install_sub2api.sh dist/install_sub2api.sh 2>/dev/null; then
    echo "Sub2API nginx test failures must preserve diagnostic stderr output." >&2
    return 1
  fi
  awk '
      /warn "\$\(t app\.sub2api\.warn\.nginx_test_failed\)"/ { in_block=1; saw_diag=0; next }
      in_block && /nginx -t >&2 \|\| true/ { saw_diag=1 }
      in_block && /^  fi$/ {
        if (!saw_diag) {
          printf "%s Sub2API nginx failure path must emit nginx -t diagnostics to stderr\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_firewall_success_paths_validate_command_results() {
  if grep -R -nE 'ufw allow "?\$\{?(PORT|PUBLIC_PORT)[^"]*"?[^[:cntrl:]]*\|\| true|firewall-cmd --permanent --add-port=.*\|\| true|firewall-cmd --reload.*\|\| true' \
      impl/install_newapi.sh impl/install_sub2api.sh impl/install_cyberstrikeai.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "Firewall success paths must not ignore command failures." >&2
    return 1
  fi
  if grep -R -n 'ufw allow "Nginx Full" > /dev/null 2>&1 || ufw allow 80/tcp > /dev/null' \
      impl/install_blog.sh dist/install_blog.sh 2>/dev/null; then
    echo "Blog firewall fallback must not report success unless both HTTP and HTTPS rules are applied." >&2
    return 1
  fi
  awk '
      /app_configure_firewall\(\)/ { in_block=1; saw_ufw_if=0; saw_firewalld_if=0; saw_iptables_if=0; saw_failure_warn=0; next }
      in_block && /if ufw allow "\$\{port\}\/tcp" comment "\$app_label" > \/dev\/null; then/ { saw_ufw_if=1 }
      in_block && /if firewall-cmd --permanent --add-port="\$\{port\}\/tcp" >\/dev\/null 2>&1/ { saw_firewalld_if=1 }
      in_block && /if iptables -C INPUT -p tcp --dport "\$port" -j ACCEPT 2>\/dev\/null/ { saw_iptables_if=1 }
      in_block && /warn "\$\(t "\$\{app_prefix\}\.warn\.firewall_config_failed" "\$port"\)"/ { saw_failure_warn=1 }
      in_block && /^}/ {
        if (!(saw_ufw_if && saw_firewalld_if && saw_iptables_if && saw_failure_warn)) {
          printf "%s shared firewall helper must only report success after command success and warn on failure\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' lib/app.sh
  grep -Fq 'app_configure_firewall "$PORT" "app.newapi" "New API"' impl/install_newapi.sh \
    && grep -Fq 'app_configure_firewall "$PORT" "app.newapi" "New API"' dist/install_newapi.sh \
    && grep -Fq 'app_configure_firewall "$PORT" "app.sub2api" "Sub2API" true' impl/install_sub2api.sh \
    && grep -Fq 'app_configure_firewall "$PORT" "app.sub2api" "Sub2API" true' dist/install_sub2api.sh \
    && grep -Fq 'app_configure_firewall "$port_to_open" "app.cyberstrikeai" "CyberStrikeAI"' impl/install_cyberstrikeai.sh \
    && grep -Fq 'app_configure_firewall "$port_to_open" "app.cyberstrikeai" "CyberStrikeAI"' dist/install_cyberstrikeai.sh \
    || {
      echo "NewAPI, Sub2API, and CyberStrikeAI firewall configuration must use the shared app_configure_firewall helper." >&2
      return 1
    }
  if grep -nE '^_configure_firewall\(\)' impl/install_newapi.sh impl/install_sub2api.sh \
      dist/install_newapi.sh dist/install_sub2api.sh; then
    echo "NewAPI and Sub2API must not define a per-app _configure_firewall copy." >&2
    return 1
  fi
  awk '
      /app\.newapi\.success\.ufw_port/ { newapi_ufw=1 }
      /app\.newapi\.success\.iptables_saved/ { newapi_saved=1 }
      /app\.newapi\.info\.iptables_rules_written/ { newapi_info=1 }
      /app\.newapi\.warn\.iptables_write_failed/ { newapi_write_failed=1 }
      /app\.newapi\.warn\.iptables_not_persisted/ { newapi_not_persisted=1 }
      /app\.newapi\.success\.iptables_port/ { newapi_port=1 }
      /app\.newapi\.warn\.firewall_config_failed/ { newapi_cfg_failed=1 }
      /app\.newapi\.warn\.no_firewall/ { newapi_no_fw=1 }
      /app\.sub2api\.success\.ufw_port/ { sub2api_ufw=1 }
      /app\.sub2api\.success\.firewalld_port/ { sub2api_firewalld=1 }
      /app\.sub2api\.success\.iptables_saved/ { sub2api_saved=1 }
      /app\.sub2api\.info\.iptables_rules_written/ { sub2api_info=1 }
      /app\.sub2api\.warn\.iptables_write_failed/ { sub2api_write_failed=1 }
      /app\.sub2api\.warn\.iptables_not_persisted/ { sub2api_not_persisted=1 }
      /app\.sub2api\.success\.iptables_port/ { sub2api_port=1 }
      /app\.sub2api\.warn\.firewall_config_failed/ { sub2api_cfg_failed=1 }
      /app\.sub2api\.warn\.no_firewall/ { sub2api_no_fw=1 }
      /app\.cyberstrikeai\.success\.ufw_port/ { csai_ufw=1 }
      /app\.cyberstrikeai\.success\.iptables_saved/ { csai_saved=1 }
      /app\.cyberstrikeai\.info\.iptables_rules_written/ { csai_info=1 }
      /app\.cyberstrikeai\.warn\.iptables_write_failed/ { csai_write_failed=1 }
      /app\.cyberstrikeai\.warn\.iptables_not_persisted/ { csai_not_persisted=1 }
      /app\.cyberstrikeai\.success\.iptables_port/ { csai_port=1 }
      /app\.cyberstrikeai\.warn\.firewall_config_failed/ { csai_cfg_failed=1 }
      /app\.cyberstrikeai\.warn\.no_firewall/ { csai_no_fw=1 }
      END {
        if (!(newapi_ufw && newapi_saved && newapi_info && newapi_write_failed &&
              newapi_not_persisted && newapi_port && newapi_cfg_failed && newapi_no_fw &&
              sub2api_ufw && sub2api_firewalld && sub2api_saved && sub2api_info &&
              sub2api_write_failed && sub2api_not_persisted && sub2api_port &&
              sub2api_cfg_failed && sub2api_no_fw &&
              csai_ufw && csai_saved && csai_info && csai_write_failed &&
              csai_not_persisted && csai_port && csai_cfg_failed && csai_no_fw)) {
          print "firewall i18n keys must be registered for apps using app_configure_firewall" > "/dev/stderr"
          exit 1
        }
      }
    ' apps/newapi.sh apps/sub2api.sh apps/cyberstrikeai.sh
  awk '
      /open_firewall_ports\(\)/ { in_block=1; saw_gate=0; saw_step=0; saw_port=0; saw_shared=0; next }
      in_block && /_bool_true "\$OPEN_FIREWALL" \|\| return 0/ { saw_gate=1 }
      in_block && /step "\$\(t app\.cyberstrikeai\.step\.firewall\)"/ { saw_step=1 }
      in_block && /_bool_true "\$ENABLE_NGINX" && port_to_open="\$PUBLIC_PORT"/ { saw_port=1 }
      in_block && /app_configure_firewall "\$port_to_open" "app\.cyberstrikeai" "CyberStrikeAI"/ { saw_shared=1 }
      in_block && /^}/ {
        if (!(saw_gate && saw_step && saw_port && saw_shared)) {
          printf "%s CyberStrikeAI firewall configuration must gate on OPEN_FIREWALL and delegate to app_configure_firewall\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
  awk '
      /step "\$\(t app\.vaultwarden\.step\.firewall\)"/ { in_block=1; saw_ufw_if=0; saw_iptables_ok=0; saw_failure_warn=0; next }
      in_block && /if ufw allow "Nginx Full" >\/dev\/null 2>&1; then/ { saw_ufw_if=1 }
      in_block && /local iptables_ok=true/ { saw_iptables_ok=1 }
      in_block && /warn "\$\(t app\.vaultwarden\.warn\.firewall_config_failed\)"/ { saw_failure_warn=1 }
      in_block && /step "\$\(t app\.vaultwarden\.step\.auto_backup\)"/ {
        if (!(saw_ufw_if && saw_iptables_ok && saw_failure_warn)) {
          printf "%s Vaultwarden firewall configuration must only report success after command success and warn on failure\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
  awk '
      /step "\$\(t app\.blog\.step_firewall\)"/ { in_block=1; saw_ufw_if=0; saw_iptables_ok=0; saw_failure_warn=0; next }
      in_block && /if ufw allow "Nginx Full" > \/dev\/null 2>&1/ { saw_ufw_if=1 }
      in_block && /iptables_ok=true/ { saw_iptables_ok=1 }
      in_block && /warn "\$\(t app\.blog\.firewall_config_failed\)"/ { saw_failure_warn=1 }
      in_block && /step "\$\(t app\.blog\.step_start_nginx\)"/ {
        if (!(saw_ufw_if && saw_iptables_ok && saw_failure_warn)) {
          printf "%s Blog firewall configuration must only report success after command success and warn on failure\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_blog.sh dist/install_blog.sh
}

check_uninstall_nginx_paths_preserve_diagnostics() {
  if grep -R -nE 'nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null \|\| true|systemctl reload nginx 2>/dev/null \|\| true$' \
      impl/install_sub2api.sh impl/install_cyberstrikeai.sh impl/install_vaultwarden.sh \
      dist/install_sub2api.sh dist/install_cyberstrikeai.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "Uninstall-time nginx cleanup must preserve nginx test/reload diagnostics." >&2
    return 1
  fi
  grep -Fq 'app.sub2api.warn.uninstall_nginx_reload_failed' apps/sub2api.sh \
    && grep -Fq 'app.sub2api.warn.uninstall_nginx_test_failed' apps/sub2api.sh \
    || {
      echo "Sub2API must localize nginx uninstall warnings." >&2
      return 1
    }
  awk '
      /rm -f \/etc\/nginx\/sites-enabled\/sub2api/ { in_block=1; saw_test=0; saw_reload=0; saw_diag=0; saw_reload_warn=0; saw_test_warn=0; saw_fallback=0; next }
      in_block && /if nginx -t >\/dev\/null 2>&1; then/ { saw_test=1 }
      in_block && /if systemctl reload nginx >\/dev\/null 2>&1; then/ { saw_reload=1 }
      in_block && /nginx -t >&2 \|\| true/ { saw_diag=1 }
      in_block && /warn "\$\(t app\.sub2api\.warn\.uninstall_nginx_reload_failed\)"/ { saw_reload_warn=1 }
      in_block && /warn "\$\(t app\.sub2api\.warn\.uninstall_nginx_test_failed\)"/ { saw_test_warn=1 }
      in_block && /success "\$\(t app\.sub2api\.success\.removed_nginx\)"/ { saw_fallback=1 }
      in_block && /rm -f \/etc\/cron\.d\/sub2api-backup/ {
        if (!(saw_test && saw_reload && saw_diag && saw_reload_warn && saw_test_warn && saw_fallback)) {
          printf "%s Sub2API uninstall nginx cleanup must validate reloads, emit diagnostics, and warn on validation or reload failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
  grep -Fq 'app.cyberstrikeai.warn.uninstall_nginx_reload_failed' apps/cyberstrikeai.sh || {
    echo "CyberStrikeAI must localize nginx reload warnings during uninstall." >&2
    return 1
  }
  awk '
      /rm -f "\$NGINX_LINK" "\$NGINX_CONF"/ { in_block=1; saw_test=0; saw_reload=0; saw_diag=0; saw_warn=0; next }
      in_block && /if nginx -t >\/dev\/null 2>&1; then/ { saw_test=1 }
      in_block && /if ! systemctl reload nginx >\/dev\/null 2>&1; then/ { saw_reload=1 }
      in_block && /^    else$/ { saw_else=1 }
      in_block && saw_else && /nginx -t >&2 \|\| true/ { saw_diag=1 }
      in_block && /warn "\$\(t app\.cyberstrikeai\.warn\.uninstall_nginx_reload_failed\)"/ { saw_warn=1 }
      in_block && /nginx -t >&2 \|\| true/ { saw_diag=1 }
      in_block && /success "\$\(t app\.cyberstrikeai\.success\.removed_nginx\)"/ {
        if (!(saw_test && saw_reload && saw_diag && saw_warn)) {
          printf "%s CyberStrikeAI uninstall nginx cleanup must emit diagnostics and an explicit warning when validation or reload fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
  grep -Fq 'app.vaultwarden.warn.uninstall_nginx_reload_failed' apps/vaultwarden.sh || {
    echo "Vaultwarden must localize nginx reload warnings during uninstall." >&2
    return 1
  }
  awk '
      /rm -f \/etc\/nginx\/sites-enabled\/vaultwarden \/etc\/nginx\/sites-available\/vaultwarden/ { in_block=1; saw_test=0; saw_reload=0; saw_diag=0; saw_warn=0; next }
      in_block && /if nginx -t >\/dev\/null 2>&1; then/ { saw_test=1 }
      in_block && /if ! systemctl reload nginx >\/dev\/null 2>&1; then/ { saw_reload=1 }
      in_block && /^    else$/ { saw_else=1 }
      in_block && saw_else && /nginx -t >&2 \|\| true/ { saw_diag=1 }
      in_block && /warn "\$\(t app\.vaultwarden\.warn\.uninstall_nginx_reload_failed\)"/ { saw_warn=1 }
      in_block && /nginx -t >&2 \|\| true/ { saw_diag=1 }
      in_block && /success "\$\(t app\.vaultwarden\.success\.removed_nginx\)"/ {
        if (!(saw_test && saw_reload && saw_diag && saw_warn)) {
          printf "%s Vaultwarden uninstall nginx cleanup must emit diagnostics and an explicit warning when validation or reload fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
  grep -Fq 'app.blog.uninstall.nginx_test_failed' apps/blog.sh || {
    echo "Blog must localize nginx uninstall validation warnings." >&2
    return 1
  }
  awk '
      /if command -v nginx >\/dev\/null 2>&1 && command -v systemctl >\/dev\/null 2>&1; then/ { in_block=1; saw_test_if=0; saw_reload_if=0; saw_diag=0; saw_reload_warn=0; saw_test_warn=0; saw_success=0; next }
      in_block && /if nginx -t >\/dev\/null 2>&1; then/ { saw_test_if=1 }
      in_block && /if systemctl reload nginx >\/dev\/null 2>&1; then/ { saw_reload_if=1 }
      in_block && /nginx -t >&2 \|\| true/ { saw_diag=1 }
      in_block && /warn "\$\(t app\.blog\.uninstall\.nginx_reload_failed\)"/ { saw_reload_warn=1 }
      in_block && /warn "\$\(t app\.blog\.uninstall\.nginx_test_failed\)"/ { saw_test_warn=1 }
      in_block && /success "\$\(t app\.blog\.uninstall\.nginx_reloaded\)"/ { saw_success=1 }
      in_block && /success "\$\(t app\.blog\.uninstall\.success\)"/ {
        if (!(saw_test_if && saw_reload_if && saw_diag && saw_reload_warn && saw_test_warn && saw_success)) {
          printf "%s Blog uninstall nginx cleanup must distinguish nginx validation failures from reload failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_blog.sh dist/install_blog.sh
}

check_fail2ban_configs_are_atomic() {
  if grep -R -nE '^[[:space:]]*cat > /etc/fail2ban/' impl dist 2>/dev/null; then
    echo "Fail2Ban configs must be written through temporary files before replacement." >&2
    return 1
  fi
  awk '
      /fail2ban_tmp=\$\(mktemp/ { saw_tmp=1 }
      /if ! fail2ban_tmp=\$\(mktemp "\$\{fail2ban_conf\}\.XXXXXX"\); then/ { saw_tmp_if=1 }
      /error "\$\(t app\.vaultwarden\.error\.fail2ban_write "\$fail2ban_conf"\)"/ { saw_tmp_error=1 }
      /mv "\$fail2ban_tmp" "\$fail2ban_conf"/ { saw_mv=1 }
      /rm -f "\$fail2ban_tmp"/ { saw_cleanup=1 }
      /_write_fail2ban_config_file \/etc\/fail2ban\// { saw_helper=1 }
      END {
        if (!(saw_tmp && saw_tmp_if && saw_tmp_error && saw_mv && saw_cleanup && saw_helper)) {
          print "Fail2Ban config writes must stage, replace, clean up temporary files, and report temp creation failures." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
}

check_user_deletion_paths_are_explicit() {
  if grep -R -nE 'userdel "\$(SERVICE_USER|VW_USER)" 2>/dev/null[[:space:]\\]*&& success .* \|\| (warn|true)' \
      impl/install_newapi.sh impl/install_sub2api.sh impl/install_cyberstrikeai.sh impl/install_vaultwarden.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_cyberstrikeai.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "User deletion paths must use explicit conditionals for userdel outcomes." >&2
    return 1
  fi
  awk '
      /if \$DELETE_DATA && id "\$SERVICE_USER" &>\/dev\/null; then/ { in_userdel=1; saw_userdel_if=0; saw_success=0; saw_warn=0; next }
      in_userdel && /if userdel "\$SERVICE_USER" 2>\/dev\/null; then/ { saw_userdel_if=1 }
      in_userdel && /success "\$\(t app\.newapi\.success\.deleted_user "\$SERVICE_USER"\)"/ { saw_success=1 }
      in_userdel && /warn "\$\(t app\.newapi\.warn\.delete_user "\$SERVICE_USER"\)"/ { saw_warn=1 }
      in_userdel && /^  fi$/ {
        if (!(saw_userdel_if && saw_success && saw_warn)) {
          printf "%s NewAPI uninstall user deletion must branch explicitly on userdel result\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_userdel=0
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
  awk '
      /if \$DELETE_DATA && \$DELETE_CONF && id "\$SERVICE_USER" &>\/dev\/null; then/ { in_userdel=1; saw_userdel_if=0; saw_success=0; saw_warn=0; next }
      in_userdel && /if userdel "\$SERVICE_USER" 2>\/dev\/null; then/ { saw_userdel_if=1 }
      in_userdel && /success "\$\(t app\.sub2api\.success\.deleted_user "\$SERVICE_USER"\)"/ { saw_success=1 }
      in_userdel && /warn "\$\(t app\.sub2api\.warn\.delete_user "\$SERVICE_USER"\)"/ { saw_warn=1 }
      in_userdel && /^  fi$/ {
        if (!(saw_userdel_if && saw_success && saw_warn)) {
          printf "%s Sub2API uninstall user deletion must branch explicitly on userdel result\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_userdel=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
  awk '
      /if \[\[ "\$\{del_install,,\}" == "y" \]\] && id "\$SERVICE_USER" >\/dev\/null 2>&1; then/ { in_userdel=1; saw_userdel_if=0; saw_success=0; saw_warn=0; next }
      in_userdel && /if userdel "\$SERVICE_USER" 2>\/dev\/null; then/ { saw_userdel_if=1 }
      in_userdel && /success "\$\(t app\.cyberstrikeai\.success\.deleted_user "\$SERVICE_USER"\)"/ { saw_success=1 }
      in_userdel && /warn "\$\(t app\.cyberstrikeai\.warn\.delete_user "\$SERVICE_USER"\)"/ { saw_warn=1 }
      in_userdel && /^  fi$/ {
        if (!(saw_userdel_if && saw_success && saw_warn)) {
          printf "%s CyberStrikeAI uninstall user deletion must branch explicitly on userdel result\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_userdel=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
  awk '
      /if \$DELETE_DATA && id "\$VW_USER" &>\/dev\/null; then/ { in_userdel=1; saw_userdel_if=0; saw_success=0; next }
      in_userdel && /if userdel "\$VW_USER" 2>\/dev\/null; then/ { saw_userdel_if=1 }
      in_userdel && /success "\$\(t app\.vaultwarden\.success\.deleted_user "\$VW_USER"\)"/ { saw_success=1 }
      in_userdel && /^  fi$/ {
        if (!(saw_userdel_if && saw_success)) {
          printf "%s Vaultwarden uninstall user deletion must branch explicitly on userdel result\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_userdel=0
      }
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
}

