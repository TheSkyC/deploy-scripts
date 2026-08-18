# shellcheck shell=bash
# shellcheck source=../verify.sh
# Verify checks for CLI dispatch, menus, registry, and localization.

check_localized_dispatch() {
  expect_failure_output en install_newapi.sh "Invalid choice"
  expect_failure_output zh install_newapi.sh "无效选项"
  expect_failure_output en dist/install_newapi.sh "Invalid choice"
  expect_failure_output zh dist/install_newapi.sh "无效选项"
  expect_manager_failure_output en deploy.sh newapi "Invalid choice"
  expect_manager_failure_output zh deploy.sh newapi "无效选项"
  expect_manager_failure_output en dist/deploy.sh newapi "Invalid choice"
  expect_manager_failure_output zh dist/deploy.sh newapi "无效选项"
  expect_manager_failure_output en deploy.sh " newapi " "Invalid choice" " not-a-command "
  expect_manager_failure_output zh deploy.sh " newapi " "无效选项" " not-a-command "
  expect_manager_failure_output en dist/deploy.sh " newapi " "Invalid choice" " not-a-command "
  expect_manager_failure_output zh dist/deploy.sh " newapi " "无效选项" " not-a-command "
  expect_failure_output en install_blog.sh "Please run as root" update
  expect_failure_output zh install_blog.sh "请使用 root 权限运行" update
  expect_failure_output en dist/install_blog.sh "Please run as root" update
  expect_failure_output zh dist/install_blog.sh "请使用 root 权限运行" update
  expect_manager_failure_output en deploy.sh blog "Please run as root" update
  expect_manager_failure_output zh deploy.sh blog "请使用 root 权限运行" update
  expect_manager_failure_output en dist/deploy.sh blog "Please run as root" update
  expect_manager_failure_output zh dist/deploy.sh blog "请使用 root 权限运行" update
  expect_failure_output en install_tickflow.sh "Invalid choice"
  expect_failure_output zh install_tickflow.sh "无效选项"
  expect_failure_output en dist/install_tickflow.sh "Invalid choice"
  expect_failure_output zh dist/install_tickflow.sh "无效选项"
  expect_failure_output en install_newapi.sh "does not support restore" restore
  expect_failure_output zh install_newapi.sh "暂不支持 restore" restore
  expect_failure_output en dist/install_newapi.sh "does not support restore" restore
  expect_failure_output zh dist/install_newapi.sh "暂不支持 restore" restore
}

check_doctor_dispatch() {
  expect_success_output en install_newapi.sh doctor "Deployment doctor"
  expect_success_output zh install_newapi.sh doctor "部署诊断"
  expect_success_output en dist/install_newapi.sh doctor "Deployment doctor"
  expect_success_output zh dist/install_newapi.sh doctor "部署诊断"
  expect_manager_success_output en deploy.sh newapi doctor "Deployment doctor"
  expect_manager_success_output zh deploy.sh newapi doctor "部署诊断"
  expect_manager_success_output en dist/deploy.sh newapi doctor "Deployment doctor"
  expect_manager_success_output zh dist/deploy.sh newapi doctor "部署诊断"
}

check_app_help_dispatch() {
  expect_success_output en install_newapi.sh --help "Usage: sudo bash"
  expect_success_output zh install_newapi.sh help "用法：sudo bash"
  expect_success_output en dist/install_newapi.sh -h "Usage: sudo bash"
  expect_success_output zh dist/install_newapi.sh --help "用法：sudo bash"
}

check_status_json_dispatch() {
  expect_success_output en install_newapi.sh status-json '"app_id":"newapi"'
  expect_success_output en dist/install_newapi.sh json-status '"app_name":"New API"'
  expect_manager_success_output en deploy.sh tickflow status-json '"app_id":"tickflow"'
  expect_manager_success_output en dist/deploy.sh tickflow json-status '"service"'
}

# status-json must expose a services array for multi-service apps and a
# version field for automation consumers.
check_status_json_services_and_version() {
  expect_success_output en dist/install_cpa_stack.sh status-json '"services":['
  expect_success_output en dist/install_cpa_stack.sh status-json '"cli-proxy-api"'
  expect_success_output en dist/install_cpa_stack.sh status-json '"cpa-manager-plus"'
  expect_success_output en dist/install_cpa_stack.sh status-json '"version":null'
  expect_success_output en install_newapi.sh status-json '"version":null'
}

check_doctor_validates_saved_config() {
  awk '
      /doctor\.config_parse_ok/ { saw_ok_key=1 }
      /doctor\.config_parse_bad/ { saw_bad_key=1 }
      END {
        if (!(saw_ok_key && saw_bad_key)) {
          print "Doctor must provide localized saved-config validation results." > "/dev/stderr"
          exit 1
        }
      }
    ' lib/i18n.sh
  grep -Fq 'app_doctor_config_derive_hook()' lib/app.sh \
    && grep -Fq 'app_doctor_validate_saved_config()' lib/app.sh \
    && grep -Fq 'load_config_file "$conf_file" "${CONFIG_KEYS[@]}"' lib/app.sh \
    && grep -Fq 'derive_hook="$(app_doctor_config_derive_hook 2>/dev/null)"' lib/app.sh \
    && grep -Fq '_validate_config_values' lib/app.sh \
    && grep -Fq 'if app_doctor_validate_saved_config "$conf_file"; then' lib/app.sh \
    || {
      echo "Doctor must load, derive, and validate saved config in an isolated helper." >&2
      return 1
    }
}

check_no_color_output() {
  local output

  set +e
  output="$(NO_COLOR=1 DEPLOY_LANG=en "$BASH_BIN" install_newapi.sh not-a-command 2>&1)"
  set -e
  [[ "$output" != *$'\033'* ]] || {
    echo "NO_COLOR=1 output must not contain ANSI escape sequences." >&2
    echo "$output" >&2
    return 1
  }

  set +e
  output="$(TERM=dumb DEPLOY_LANG=en "$BASH_BIN" dist/install_newapi.sh not-a-command 2>&1)"
  set -e
  [[ "$output" != *$'\033'* ]] || {
    echo "TERM=dumb output must not contain ANSI escape sequences." >&2
    echo "$output" >&2
    return 1
  }
}

check_no_argument_menu() {
  expect_menu_output en deploy.sh "Choose an application"
  expect_menu_output zh deploy.sh "请选择应用"
  expect_menu_output en dist/deploy.sh "Choose an application"
  expect_menu_output zh dist/deploy.sh "请选择应用"
  expect_menu_output en install_blog.sh "Choose an action"
  expect_menu_output zh install_blog.sh "请选择操作"
  expect_menu_output en dist/install_blog.sh "Choose an action"
  expect_menu_output zh dist/install_blog.sh "请选择操作"
  expect_menu_output en install_tickflow.sh "Choose an action"
  expect_menu_output zh install_tickflow.sh "请选择操作"
  expect_menu_output en dist/install_tickflow.sh "Choose an action"
  expect_menu_output zh dist/install_tickflow.sh "请选择操作"
}

check_manager_list() {
  expect_manager_list_output deploy.sh
  expect_manager_list_output deploy.sh " list "
  expect_manager_list_output dist/deploy.sh
  expect_manager_list_output dist/deploy.sh " list "
}

check_app_registry_metadata() {
  "$BASH_BIN" -c '
    source lib/app_registry.sh

    [[ "${#DEPLOY_APP_IDS[@]}" -gt 0 ]] || {
      echo "Application registry must not be empty." >&2
      exit 1
    }

    mapfile -t app_ids_from_function < <(deploy_app_ids)
    [[ "${app_ids_from_function[*]}" == "${DEPLOY_APP_IDS[*]}" ]] || {
      echo "deploy_app_ids output must match DEPLOY_APP_IDS." >&2
      exit 1
    }

    duplicate_ids="$(printf "%s\n" "${DEPLOY_APP_IDS[@]}" | sort | uniq -d)"
    [[ -z "$duplicate_ids" ]] || {
      echo "Application registry contains duplicate ids:" >&2
      echo "$duplicate_ids" >&2
      exit 1
    }

    index=1
    for app_id in "${DEPLOY_APP_IDS[@]}"; do
      app_file="$(deploy_app_file_for "$app_id")" || {
        echo "Missing app definition path for ${app_id}." >&2
        exit 1
      }
      impl_file="$(deploy_app_impl_file_for "$app_id")" || {
        echo "Missing implementation path for ${app_id}." >&2
        exit 1
      }
      app_name="$(deploy_app_name_for "$app_id")" || {
        echo "Missing display name for ${app_id}." >&2
        exit 1
      }

      [[ -n "$app_name" ]] || {
        echo "Application display name must not be empty for ${app_id}." >&2
        exit 1
      }
      [[ -f "$app_file" ]] || {
        echo "Application definition file is missing: ${app_file}" >&2
        exit 1
      }
      [[ -f "$impl_file" ]] || {
        echo "Application implementation file is missing: ${impl_file}" >&2
        exit 1
      }
      [[ "$(deploy_app_index_for "$app_id")" == "$index" ]] || {
        echo "Application index mismatch for ${app_id}." >&2
        exit 1
      }
      [[ "$(deploy_app_id_from_selection "$index")" == "$app_id" ]] || {
        echo "Numeric selection must resolve to ${app_id}." >&2
        exit 1
      }
      [[ "$(deploy_app_id_from_selection "$app_id")" == "$app_id" ]] || {
        echo "String selection must resolve to ${app_id}." >&2
        exit 1
      }

      index=$((index + 1))
    done
  '
}

# Every app i18n key referenced by an impl script, an apps file, the verify
# runner, or a check module must be registered in the corresponding apps/*.sh
# file, and every registered key must be referenced somewhere. This catches
# keys removed while still in use (e.g., by check module content checks) and
# references to keys that were never registered.
check_i18n_keys_are_consistent() {
  local fail=0 apps_file prefix impl_file tmp_dir
  tmp_dir="$(mktemp -d)"
  # Full literal app keys referenced by the verify runner and check modules
  # (escaped tokens only; regex alternations and unterminated fragments are
  # pattern matchers, not keys).
  awk '
      {
        line = $0
        while (match(line, /app\\\.[a-z0-9_]+(\\\.[a-z0-9_]+)*/)) {
          tok = substr(line, RSTART, RLENGTH)
          tail = substr(line, RSTART + RLENGTH, 2)
          if (tail != "\\(" && tail != "\\." && tok !~ /_$/) {
            gsub(/\\\./, ".", tok)
            print tok
          }
          line = substr(line, RSTART + RLENGTH)
        }
      }
    ' tools/verify.sh tools/checks/*.sh | sort -u > "$tmp_dir/verify_keys" || true
  for apps_file in apps/*.sh; do
    prefix="$(basename "$apps_file" .sh)"
    impl_file="impl/install_${prefix}.sh"
    [[ -f "$impl_file" ]] || continue
    # Registered keys: single-key i18n_register lines plus bare app.* tokens
    # inside i18n_register_many blocks (EN/ZH text lines are quoted).
    awk '
        /^[[:space:]]*i18n_register[[:space:]]+app\.[a-z0-9_.]+/ { print $2 }
        /^[[:space:]]*app\.[a-z0-9_.]+[[:space:]]*\\?$/ { print $1 }
      ' "$apps_file" | sort -u > "$tmp_dir/reg" || true
    # References from the impl script (t calls and helper key arguments).
    grep -oE "app\.${prefix}\.[a-z0-9_.]+" "$impl_file" | sort -u > "$tmp_dir/refs_impl" || true
    # References from t() calls inside the apps file (e.g., APP_DESCRIPTION).
    grep -oE "\bt[[:space:]]+app\.${prefix}\.[a-z0-9_.]+" "$apps_file" | awk '{print $2}' | sort -u > "$tmp_dir/refs_apps" || true
    # References from the verify runner / check modules and the shared lib / deploy manager.
    grep "^app\.${prefix}\." "$tmp_dir/verify_keys" > "$tmp_dir/refs_verify" || true
    grep -hoE "app\.${prefix}\.[a-z0-9_.]+" lib/*.sh deploy.sh 2>/dev/null | sort -u > "$tmp_dir/refs_mgr" || true
    cat "$tmp_dir/refs_impl" "$tmp_dir/refs_apps" "$tmp_dir/refs_verify" "$tmp_dir/refs_mgr" \
      | sort -u > "$tmp_dir/refs_all" || true
    while IFS= read -r key; do
      echo "$impl_file references unregistered i18n key $key (register it in $apps_file)" >&2
      fail=1
    done < <(comm -23 "$tmp_dir/refs_impl" "$tmp_dir/reg")
    while IFS= read -r key; do
      echo "$apps_file calls t $key but does not register it" >&2
      fail=1
    done < <(comm -23 "$tmp_dir/refs_apps" "$tmp_dir/reg")
    while IFS= read -r key; do
      echo "verify runner or check modules reference unregistered i18n key $key (register it in $apps_file)" >&2
      fail=1
    done < <(comm -23 "$tmp_dir/refs_verify" "$tmp_dir/reg")
    while IFS= read -r key; do
      echo "$apps_file registers unused i18n key $key (no impl/apps/verify/checks/lib reference)" >&2
      fail=1
    done < <(comm -13 "$tmp_dir/refs_all" "$tmp_dir/reg")
  done
  rm -rf "$tmp_dir"
  if [[ "$fail" -ne 0 ]]; then
    echo "i18n keys must be consistently registered and referenced." >&2
    return 1
  fi
}

check_app_localized_descriptions() {
  expect_app_description cyberstrikeai en "Source build deployment with Go, Python, systemd, Nginx, and backups."
  expect_app_description cyberstrikeai zh "包含 Go、Python、systemd、Nginx 和备份的源码构建部署脚本。"
  expect_app_description newapi en "Binary deployment with systemd, backups, and operational checks."
  expect_app_description newapi zh "使用 systemd、备份和运维检查的二进制部署脚本。"
  expect_app_description sub2api en "API gateway deployment with database, cache, systemd, and backups."
  expect_app_description sub2api zh "包含数据库、缓存、systemd 和备份的 API 网关部署脚本。"
  expect_app_description vaultwarden en "Vaultwarden deployment with Web Vault, Nginx, TLS, and backups."
  expect_app_description vaultwarden zh "包含 Web Vault、Nginx、TLS 和备份的 Vaultwarden 部署脚本。"
  expect_app_description tickflow en "Docker Compose deployment for the TickFlow stock analysis panel."
  expect_app_description tickflow zh "TickFlow 股票分析面板的 Docker Compose 部署脚本。"
  expect_app_description cpa_stack en "Native CLIProxyAPI (CPA) and CPA Manager Plus deployment with systemd, Nginx, HTTPS, backups, and diagnostics."
  expect_app_description cpa_stack zh "使用 systemd、Nginx、HTTPS、备份和诊断部署原生 CLIProxyAPI（CPA）与 CPA Manager Plus。"
  expect_app_description ntfy en "Push notification service deployment with systemd and backups."
  expect_app_description ntfy zh "使用 systemd 和备份的推送通知服务部署脚本。"
  expect_app_description meilisearch en "Meilisearch search engine deployment with systemd and backups."
  expect_app_description meilisearch zh "使用 systemd 和备份的 Meilisearch 搜索引擎部署脚本。"
  expect_app_description alist en "Alist file listing service deployment with systemd and backups."
  expect_app_description alist zh "使用 systemd 和备份的 Alist 文件列表服务部署脚本。"
  expect_app_description filebrowser en "Filebrowser web file manager deployment with systemd and backups."
  expect_app_description filebrowser zh "使用 systemd 和备份的 Filebrowser 网页文件管理器部署脚本。"
}
check_no_hardcoded_chinese_impl() {
  if LC_ALL=C.UTF-8 grep -R -nP '[\p{Han}]' impl; then
    echo "Implementation scripts must use i18n keys instead of hardcoded Chinese text." >&2
    return 1
  fi
}

check_no_chinese_comments() {
  if LC_ALL=C.UTF-8 grep -R -nP '^\s*#.*[\p{Han}]' apps bin impl lib tools dist install_*.sh deploy.sh; then
    echo "Comments must be written in English." >&2
    return 1
  fi
}
