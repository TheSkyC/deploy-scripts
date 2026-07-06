#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BASH_BIN="${BASH_BIN:-bash}"

cd "$ROOT_DIR"

usage() {
  cat >&2 <<'EOF'
Usage: bash tools/verify.sh [all|syntax|release|dispatch|help]

Targets:
  all       Run the full repository verification suite. This is the default.
  syntax    Check Bash syntax for source scripts only.
  release   Rebuild dist/ with deterministic metadata and check release syntax.
  dispatch  Rebuild dist/ and check CLI dispatch, menus, registry, and localization.
EOF
}

build_verified_release() {
  DEPLOY_BUILD_COMMIT=verified SOURCE_DATE_EPOCH=0 "$BASH_BIN" tools/build-release.sh all >/dev/null
}

check_shell_syntax() {
  local file
  while IFS= read -r file; do
    "$BASH_BIN" -n "$file"
  done < <(find apps bin impl lib tools -name '*.sh' -type f | sort; printf '%s\n' deploy.sh)
}

check_release_syntax() {
  local file
  while IFS= read -r file; do
    "$BASH_BIN" -n "$file"
  done < <(find dist -maxdepth 1 \( -name 'install_*.sh' -o -name 'deploy.sh' \) -type f | sort)
}

expect_failure_output() {
  local lang="$1"
  local script="$2"
  local expected="$3"
  local action="${4:-not-a-command}"
  local output status

  set +e
  output="$(DEPLOY_LANG="$lang" "$BASH_BIN" "$script" "$action" 2>&1)"
  status=$?
  set -e

  [[ "$status" -ne 0 ]] || {
    echo "Expected ${script} to reject an invalid action" >&2
    return 1
  }
  [[ "$output" == *"$expected"* ]] || {
    echo "Expected ${script} output to contain: ${expected}" >&2
    echo "$output" >&2
    return 1
  }
}

expect_success_output() {
  local lang="$1"
  local script="$2"
  local action="$3"
  local expected="$4"
  local output

  output="$(DEPLOY_LANG="$lang" "$BASH_BIN" "$script" "$action" 2>&1)"
  [[ "$output" == *"$expected"* ]] || {
    echo "Expected ${script} ${action} output to contain: ${expected}" >&2
    echo "$output" >&2
    return 1
  }
}

expect_manager_success_output() {
  local lang="$1"
  local script="$2"
  local app="$3"
  local action="$4"
  local expected="$5"
  local output

  output="$(DEPLOY_LANG="$lang" "$BASH_BIN" "$script" "$app" "$action" 2>&1)"
  [[ "$output" == *"$expected"* ]] || {
    echo "Expected ${script} ${app} ${action} output to contain: ${expected}" >&2
    echo "$output" >&2
    return 1
  }
}

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
  awk '
      /app_doctor_config_derive_hook\(\)/ { saw_hook=1 }
      /app_doctor_validate_saved_config\(\)/ { in_validate=1; saw_validate=1; next }
      in_validate && /load_config_file "\$conf_file" "\$\{CONFIG_KEYS\[@\]\}"/ { saw_load=1 }
      in_validate && /derive_hook="\$\(app_doctor_config_derive_hook 2>\/dev\/null\)"/ { saw_derive=1 }
      in_validate && /_validate_config_values/ { saw_config_validate=1 }
      in_validate && /^\}/ { in_validate=0 }
      /if app_doctor_validate_saved_config "\$conf_file"; then/ { saw_doctor_call=1 }
      END {
        if (!(saw_hook && saw_validate && saw_load && saw_derive && saw_config_validate && saw_doctor_call)) {
          print "Doctor must load, derive, and validate saved config in an isolated helper." > "/dev/stderr"
          exit 1
        }
      }
    ' lib/app.sh
}

check_newapi_uninstall_supports_noninteractive_mode() {
  awk '
      /deploy_env_truthy\(\)/ { saw_truthy=1 }
      /deploy_assume_yes\(\)/ { saw_assume=1 }
      END {
        if (!(saw_truthy && saw_assume)) {
          print "Shared app helpers must provide environment-controlled non-interactive confirmation." > "/dev/stderr"
          exit 1
        }
      }
    ' lib/app.sh
  awk '
      /prompt "\$\(t app\.newapi\.prompt\.continue\)"/ { saw_continue_prompt=1 }
      /if deploy_assume_yes; then/ && !saw_continue { saw_continue=1; next }
      saw_continue && /_c="YES"/ { saw_yes=1 }
      /local DELETE_DATA=false/ { in_data=1; next }
      in_data && /deploy_env_truthy DEPLOY_DELETE_DATA && DELETE_DATA=true/ { saw_data_env=1 }
      in_data && /prompt "\$\(t app\.newapi\.prompt\.delete_data "\$DATA_DIR"\)"/ { saw_data_prompt=1; in_data=0 }
      /local DELETE_BACKUP=false/ { in_backup=1; next }
      in_backup && /deploy_env_truthy DEPLOY_DELETE_BACKUP && DELETE_BACKUP=true/ { saw_backup_env=1 }
      in_backup && /prompt "\$\(t app\.newapi\.prompt\.delete_backup "\$BACKUP_DIR"\)"/ { saw_backup_prompt=1; in_backup=0 }
      END {
        if (!(saw_continue_prompt && saw_continue && saw_yes && saw_data_env && saw_data_prompt && saw_backup_env && saw_backup_prompt)) {
          printf "%s NewAPI uninstall must support DEPLOY_ASSUME_YES while requiring explicit env flags for data and backup deletion\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
}

check_sub2api_uninstall_supports_noninteractive_mode() {
  awk '
      /prompt "\$\(t app\.sub2api\.prompt\.continue\)"/ { saw_continue_prompt=1 }
      /if deploy_assume_yes; then/ && !saw_continue { saw_continue=1; next }
      saw_continue && /_c="YES"/ { saw_yes=1 }
      /local DELETE_DATA=false/ { in_data=1; next }
      in_data && /deploy_env_truthy DEPLOY_DELETE_DATA && DELETE_DATA=true/ { saw_data_env=1 }
      in_data && /prompt "\$\(t app\.sub2api\.prompt\.delete_data "\$DATA_DIR"\)"/ { saw_data_prompt=1; in_data=0 }
      /local DELETE_CONF=false/ { in_conf=1; next }
      in_conf && /deploy_env_truthy DEPLOY_DELETE_CONFIG && DELETE_CONF=true/ { saw_conf_env=1 }
      in_conf && /prompt "\$\(t app\.sub2api\.prompt\.delete_config "\$CONFIG_DIR"\)"/ { saw_conf_prompt=1; in_conf=0 }
      /local DELETE_BACKUP=false/ { in_backup=1; next }
      in_backup && /deploy_env_truthy DEPLOY_DELETE_BACKUP && DELETE_BACKUP=true/ { saw_backup_env=1 }
      in_backup && /prompt "\$\(t app\.sub2api\.prompt\.delete_backup "\$BACKUP_DIR"\)"/ { saw_backup_prompt=1; in_backup=0 }
      END {
        if (!(saw_continue_prompt && saw_continue && saw_yes && saw_data_env && saw_data_prompt && saw_conf_env && saw_conf_prompt && saw_backup_env && saw_backup_prompt)) {
          printf "%s Sub2API uninstall must support DEPLOY_ASSUME_YES while requiring explicit env flags for data, config, and backup deletion\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
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
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
}

check_blog_uninstall_supports_noninteractive_mode() {
  awk '
      /prompt "\$\(t app\.blog\.uninstall\.continue_prompt\)"/ { saw_continue_prompt=1 }
      /if deploy_assume_yes; then/ && !saw_continue { saw_continue=1; next }
      saw_continue && /confirm="YES"/ { saw_yes=1 }
      /if deploy_env_truthy DEPLOY_DELETE_BACKUP; then/ { saw_backup_env=1 }
      /delete_backups="yes"/ { saw_backup_yes=1 }
      /delete_backups="no"/ { saw_backup_no=1 }
      /prompt "\$\(t app\.blog\.uninstall\.delete_backups_prompt "\$BLOG_BACKUP_DIR"\)"/ { saw_backup_prompt=1 }
      END {
        if (!(saw_continue_prompt && saw_continue && saw_yes && saw_backup_env && saw_backup_yes && saw_backup_no && saw_backup_prompt)) {
          printf "%s Blog uninstall must support DEPLOY_ASSUME_YES while requiring DEPLOY_DELETE_BACKUP for backup deletion\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_blog.sh dist/install_blog.sh
}

check_cyberstrikeai_uninstall_supports_noninteractive_mode() {
  awk '
      /prompt "\$\(t app\.cyberstrikeai\.prompt\.continue\)"/ { saw_continue_prompt=1 }
      /if deploy_assume_yes; then/ && !saw_continue { saw_continue=1; next }
      saw_continue && /confirm="YES"/ { saw_yes=1 }
      /if deploy_env_truthy DEPLOY_DELETE_INSTALL; then/ { saw_install_env=1 }
      /del_install="yes"/ { saw_install_yes=1 }
      /del_install="no"/ { saw_install_no=1 }
      /prompt "\$\(t app\.cyberstrikeai\.prompt\.delete_install "\$INSTALL_DIR"\)"/ { saw_install_prompt=1 }
      /if deploy_env_truthy DEPLOY_DELETE_BACKUP; then/ { saw_backup_env=1 }
      /del_backup="yes"/ { saw_backup_yes=1 }
      /del_backup="no"/ { saw_backup_no=1 }
      /prompt "\$\(t app\.cyberstrikeai\.prompt\.delete_backup "\$BACKUP_DIR"\)"/ { saw_backup_prompt=1 }
      END {
        if (!(saw_continue_prompt && saw_continue && saw_yes && saw_install_env && saw_install_yes && saw_install_no && saw_install_prompt && saw_backup_env && saw_backup_yes && saw_backup_no && saw_backup_prompt)) {
          printf "%s CyberStrikeAI uninstall must support DEPLOY_ASSUME_YES while requiring explicit env flags for install and backup deletion\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_blog_status_dispatch() {
  expect_success_output en install_blog.sh status "Inspect Hugo Blog deployment status"
  expect_success_output zh install_blog.sh status "检查 Hugo Blog 部署状态"
  expect_success_output en dist/install_blog.sh status "Inspect Hugo Blog deployment status"
  expect_success_output zh dist/install_blog.sh status "检查 Hugo Blog 部署状态"
  expect_failure_output en install_blog.sh "Please run as root" backup
  expect_failure_output zh install_blog.sh "请使用 root 权限运行" backup
  expect_failure_output en dist/install_blog.sh "Please run as root" backup
  expect_failure_output zh dist/install_blog.sh "请使用 root 权限运行" backup
  expect_failure_output en install_blog.sh "Please run as root" restore
  expect_failure_output zh install_blog.sh "请使用 root 权限运行" restore
  expect_failure_output en dist/install_blog.sh "Please run as root" restore
  expect_failure_output zh dist/install_blog.sh "请使用 root 权限运行" restore
  expect_failure_output en install_blog.sh "Please run as root" uninstall
  expect_failure_output zh install_blog.sh "请使用 root 权限运行" uninstall
  expect_failure_output en dist/install_blog.sh "Please run as root" uninstall
  expect_failure_output zh dist/install_blog.sh "请使用 root 权限运行" uninstall
  expect_failure_output en install_blog.sh "Please run as root" update
  expect_failure_output zh install_blog.sh "请使用 root 权限运行" update
  expect_failure_output en dist/install_blog.sh "Please run as root" update
  expect_failure_output zh dist/install_blog.sh "请使用 root 权限运行" update
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

expect_manager_failure_output() {
  local lang="$1"
  local script="$2"
  local app="$3"
  local expected="$4"
  local action="${5:-not-a-command}"
  local output status

  set +e
  output="$(DEPLOY_LANG="$lang" "$BASH_BIN" "$script" "$app" "$action" 2>&1)"
  status=$?
  set -e

  [[ "$status" -ne 0 ]] || {
    echo "Expected ${script} ${app} to reject ${action}" >&2
    return 1
  }
  [[ "$output" == *"$expected"* ]] || {
    echo "Expected ${script} ${app} output to contain: ${expected}" >&2
    echo "$output" >&2
    return 1
  }
}

expect_menu_output() {
  local lang="$1"
  local script="$2"
  local expected="$3"
  local output

  output="$(printf 'q\n' | DEPLOY_LANG="$lang" "$BASH_BIN" "$script" 2>&1)"
  [[ "$output" == *"$expected"* ]] || {
    echo "Expected ${script} without arguments to show menu text: ${expected}" >&2
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

expect_manager_list_output() {
  local script="$1"
  local command="${2:-list}"
  local output

  output="$("$BASH_BIN" "$script" "$command")"
  [[ "$output" == *"newapi"* && "$output" == *"vaultwarden"* && "$output" == *"tickflow"* ]] || {
    echo "Expected ${script} ${command} to show registered applications" >&2
    echo "$output" >&2
    return 1
  }
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

expect_blog_defaults() {
  local lang="$1"
  local expected_title="$2"
  local expected_lang="$3"
  local output

  output="$(DEPLOY_LANG="$lang" "$BASH_BIN" -c '
    source lib/core.sh
    source apps/blog.sh
    printf "%s|%s\n" "$BLOG_TITLE" "$BLOG_LANG"
  ')"

  [[ "$output" == "${expected_title}|${expected_lang}" ]] || {
    echo "Unexpected blog defaults for ${lang}: ${output}" >&2
    return 1
  }
}

check_blog_localized_defaults() {
  expect_blog_defaults en "Abyte's Blog" "en-us"
  expect_blog_defaults zh "Abyte 的个人博客" "zh-cn"
}

expect_app_description() {
  local app="$1"
  local lang="$2"
  local expected="$3"
  local output

  output="$(DEPLOY_LANG="$lang" "$BASH_BIN" -c "
    source lib/core.sh
    source apps/${app}.sh
    printf '%s\n' \"\$APP_DESCRIPTION\"
  ")"

  [[ "$output" == "$expected" ]] || {
    echo "Unexpected ${app} description for ${lang}: ${output}" >&2
    return 1
  }
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

check_no_release_temp_files() {
  if find dist -maxdepth 1 -name '*_impl.sh' -type f | grep -q .; then
    echo "Unexpected bundled implementation file in dist/" >&2
    find dist -maxdepth 1 -name '*_impl.sh' -type f >&2
    return 1
  fi
  if find dist -maxdepth 1 \( -name 'install_*.sh.*' -o -name 'deploy.sh.*' \) -type f | grep -q .; then
    echo "Unexpected release build temporary file in dist/" >&2
    find dist -maxdepth 1 \( -name 'install_*.sh.*' -o -name 'deploy.sh.*' \) -type f >&2
    return 1
  fi
}

check_release_build_outputs_are_atomic() {
  if grep -n '^[[:space:]]*} > "\$output"$' tools/build-release.sh 2>/dev/null; then
    echo "Release scripts must be generated to a temporary file before replacement." >&2
    return 1
  fi
  awk '
      /prepare_output_file\(\)/ { in_prepare=1; next }
      in_prepare && /if ! mkdir -p "\$DIST_DIR"; then/ { saw_dir_if=1 }
      in_prepare && /fail "cannot create output directory: \$\{DIST_DIR\}"/ { saw_dir_error=1 }
      in_prepare && /if ! output_tmp="\$\(mktemp "\$\{output\}\.XXXXXX"\)"; then/ { saw_tmp=1 }
      in_prepare && /fail "cannot create temporary output for \$\{output\}"/ { saw_tmp_error=1 }
      in_prepare && /^}/ { in_prepare=0 }
      /install_output_file\(\)/ { in_install=1; next }
      in_install && /chmod 755 "\$output_tmp"/ { saw_chmod=1 }
      in_install && /mv "\$output_tmp" "\$output"/ { saw_mv=1 }
      in_install && /rm -f "\$output_tmp"/ { saw_cleanup=1 }
      in_install && /fail "failed to install release script: \$\{output\}"/ { saw_install_error=1 }
      in_install && /^}/ { in_install=0 }
      /} > "\$output_tmp"/ { saw_write=1 }
      /fail "failed to compose release script for \$\{app\}: \$\{output\}"/ { saw_app_write_error=1 }
      /fail "failed to compose release script for manager: \$\{output\}"/ { saw_manager_write_error=1 }
      END {
        if (!(saw_dir_if && saw_dir_error && saw_tmp && saw_tmp_error && saw_chmod && saw_mv && saw_cleanup && saw_install_error && saw_write && saw_app_write_error && saw_manager_write_error)) {
          print "Release script generation must prepare output directories, stage, replace, clean up temporary files, and report failures." > "/dev/stderr"
          exit 1
        }
      }
    ' tools/build-release.sh
}

check_bundled_impl_temp_names_are_random() {
  if grep -R -n 'tmp_path="\${script_path}\.\$\$"' lib dist 2>/dev/null; then
    echo "Bundled implementation extraction must use mktemp instead of a pid-derived temporary path." >&2
    return 1
  fi
  awk '
      /tmp_path="\$\(mktemp "\$\{script_path\}\.XXXXXX"\)"/ { saw_tmp=1 }
      /rm -f "\$tmp_path"/ { saw_cleanup=1 }
      /mv "\$tmp_path" "\$script_path"/ { saw_mv=1 }
      END {
        if (!(saw_tmp && saw_cleanup && saw_mv)) {
          print "Bundled implementation extraction must stage, replace, and clean up a mktemp file." > "/dev/stderr"
          exit 1
        }
      }
    ' lib/app_loader.sh dist/install_newapi.sh
}

check_bundled_impl_dir_security_failure_cleanup() {
  if grep -R -n 'chmod 700 "\$DEPLOY_BUNDLED_IMPL_DIR".*|| true' lib dist 2>/dev/null; then
    echo "Bundled implementation directory permission failures must stop extraction." >&2
    return 1
  fi

  local tmp_root stub_dir
  tmp_root="$(mktemp -d)"
  stub_dir="$(mktemp -d)"

  cat > "${stub_dir}/chmod" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in
    */deploy-scripts.*) exit 1 ;;
  esac
done
exec /usr/bin/chmod "$@"
STUB
  chmod +x "${stub_dir}/chmod"

  set +e
  TMPDIR="$tmp_root" PATH="${stub_dir}:$PATH" DEPLOY_LANG=en "$BASH_BIN" dist/install_newapi.sh not-a-command >/dev/null 2>&1
  status=$?
  set -e

  [[ "$status" -ne 0 ]] || {
    echo "Expected bundled script to fail when implementation directory chmod fails" >&2
    rm -rf "$tmp_root" "$stub_dir"
    return 1
  }
  if find "$tmp_root" -maxdepth 1 -name 'deploy-scripts.*' -type d | grep -q .; then
    echo "Bundled implementation directory was left behind after chmod failure" >&2
    find "$tmp_root" -maxdepth 1 -name 'deploy-scripts.*' -type d >&2
    rm -rf "$tmp_root" "$stub_dir"
    return 1
  fi
  rm -rf "$tmp_root" "$stub_dir"
}

check_bundled_impl_cleanup() {
  local tmp_root
  tmp_root="$(mktemp -d)"

  TMPDIR="$tmp_root" expect_failure_output en dist/install_newapi.sh "Invalid choice" not-a-command

  if find "$tmp_root" -name 'install_*_impl.sh' -type f | grep -q .; then
    echo "Bundled implementation script was left behind under ${tmp_root}" >&2
    find "$tmp_root" -name 'install_*_impl.sh' -type f >&2
    rm -rf "$tmp_root"
    return 1
  fi
  rm -rf "$tmp_root"
}

check_bundled_impl_failure_cleanup() {
  local tmp_root stub_dir
  tmp_root="$(mktemp -d)"
  stub_dir="$(mktemp -d)"

  cat > "${stub_dir}/chmod" <<'STUB'
#!/usr/bin/env bash
for arg in "$@"; do
  case "$arg" in
    */deploy-scripts.*/*_impl.sh.*) exit 1 ;;
  esac
done
exec /usr/bin/chmod "$@"
STUB
  chmod +x "${stub_dir}/chmod"

  set +e
  TMPDIR="$tmp_root" PATH="${stub_dir}:$PATH" DEPLOY_LANG=en "$BASH_BIN" dist/install_newapi.sh not-a-command >/dev/null 2>&1
  status=$?
  set -e

  [[ "$status" -ne 0 ]] || {
    echo "Expected bundled script to fail while chmod was stubbed" >&2
    rm -rf "$tmp_root" "$stub_dir"
    return 1
  }
  if find "$tmp_root" -name 'install_*_impl.sh*' -type f | grep -q .; then
    echo "Bundled implementation payload was left behind after extraction failure" >&2
    find "$tmp_root" -name 'install_*_impl.sh*' -type f >&2
    rm -rf "$tmp_root" "$stub_dir"
    return 1
  fi
  rm -rf "$tmp_root" "$stub_dir"
}

check_safe_path_guard() {
  "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh

    unsafe_paths=("" "/" "." ".." "relative/path" "/tmp" "/opt" "/var" "/var/log" "/var/lib" "/usr/local/bin" "/opt/app/../other")
    for path in "${unsafe_paths[@]}"; do
      if is_safe_path "$path"; then
        echo "Expected unsafe path to be rejected: ${path:-empty}" >&2
        exit 1
      fi
    done

    safe_paths=("/opt/new-api" "/opt/new-api/data" "/var/lib/vaultwarden" "/var/log/vaultwarden" "/tmp/deploy-scripts.newapi.abc123")
    for path in "${safe_paths[@]}"; do
      if ! is_safe_path "$path"; then
        echo "Expected safe path to be accepted: ${path}" >&2
        exit 1
      fi
    done
  '
  awk '
      /restore_web_vault_backup\(\)/ { in_vw=1; saw_safe=0; next }
      in_vw && /safe_rm_dir "\$VW_WEB_DIR" "VW_WEB_DIR"/ { saw_safe=1 }
      in_vw && /mv "\$backup_dir" "\$VW_WEB_DIR"/ {
        if (!saw_safe) {
          print "Vaultwarden Web Vault restore must use safe_rm_dir before replacing the live directory." > "/dev/stderr"
          exit 1
        }
        in_vw=0
      }
      /^restore_nginx_root_backup\(\)/ { in_blog=1; saw_blog_safe=0; next }
      in_blog && /safe_rm_dir "\$NGINX_ROOT" "NGINX_ROOT"/ { saw_blog_safe=1 }
      in_blog && /mv "\$DEPLOY_BAK" "\$NGINX_ROOT"/ {
        if (!saw_blog_safe) {
          print "Blog Nginx root restore must use safe_rm_dir before replacing the live directory." > "/dev/stderr"
          exit 1
        }
        in_blog=0
      }
    ' impl/install_blog.sh impl/install_vaultwarden.sh
  awk '
      /do_uninstall\(\)/ { in_uninstall=1; saw_install_dir_guard=0; saw_vw_bin_guard=0; next }
      in_uninstall && /require_safe_path "INSTALL_DIR" "\$INSTALL_DIR"/ { saw_install_dir_guard=1 }
      in_uninstall && /error "\$\(t error\.unsafe_path "VW_BIN" "\$\{VW_BIN:-empty\}"\)"/ { saw_vw_bin_guard=1 }
      in_uninstall && /find "\$INSTALL_DIR" -maxdepth 1 -name "(new-api|sub2api)\./ {
        if (!saw_install_dir_guard) {
          printf "%s uninstall cleanup must validate INSTALL_DIR before deleting generated files\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
      in_uninstall && /find "\$\(dirname "\$VW_BIN"\)" -maxdepth 1 -name "vaultwarden\.bak\./ {
        if (!saw_vw_bin_guard) {
          printf "%s Vaultwarden uninstall must validate VW_BIN before deleting generated binary backups\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
      in_uninstall && /^}/ { in_uninstall=0 }
    ' impl/install_newapi.sh impl/install_sub2api.sh impl/install_vaultwarden.sh
}

check_managed_paths_are_validated() {
  awk '
      /_validate_config_values\(\)/ { in_func=1; next }
      in_func && /require_safe_path "INSTALL_DIR" "\$INSTALL_DIR"/ { saw_install=1 }
      in_func && /require_safe_path "BIN_PATH" "\$BIN_PATH"/ { saw_bin=1 }
      in_func && /require_safe_path "DATA_DIR" "\$DATA_DIR"/ { saw_data=1 }
      in_func && /require_safe_path "LOG_DIR" "\$LOG_DIR"/ { saw_log=1 }
      in_func && /require_safe_path "LOG_FILE" "\$LOG_FILE"/ { saw_log_file=1 }
      in_func && /require_safe_path "ENV_FILE" "\$ENV_FILE"/ { saw_env=1 }
      in_func && /require_safe_path "BACKUP_DIR" "\$BACKUP_DIR"/ { saw_backup=1 }
      in_func && /^}/ {
        if (!(saw_install && saw_bin && saw_data && saw_log && saw_log_file && saw_env && saw_backup)) {
          printf "%s NewAPI must validate managed directory and derived file paths before use\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
  awk '
      /_validate_config_values\(\)/ { in_func=1; next }
      in_func && /require_safe_path "INSTALL_DIR" "\$INSTALL_DIR"/ { saw_install=1 }
      in_func && /require_safe_path "BIN_PATH" "\$BIN_PATH"/ { saw_bin=1 }
      in_func && /require_safe_path "DATA_DIR" "\$DATA_DIR"/ { saw_data=1 }
      in_func && /require_safe_path "LOG_DIR" "\$LOG_DIR"/ { saw_log=1 }
      in_func && /require_safe_path "CONFIG_DIR" "\$CONFIG_DIR"/ { saw_config=1 }
      in_func && /require_safe_path "BACKUP_DIR" "\$BACKUP_DIR"/ { saw_backup=1 }
      in_func && /^}/ {
        if (!(saw_install && saw_bin && saw_data && saw_log && saw_config && saw_backup)) {
          printf "%s Sub2API must validate managed directory and derived binary paths before use\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
  awk '
      /_validate_config_values\(\)/ { in_func=1; next }
      in_func && /require_safe_path "VW_DATA_DIR" "\$VW_DATA_DIR"/ { saw_data=1 }
      in_func && /require_safe_path "VW_WEB_DIR" "\$VW_WEB_DIR"/ { saw_web=1 }
      in_func && /require_safe_path "LOG_DIR" "\$\(dirname "\$VW_LOG_FILE"\)"/ { saw_log=1 }
      in_func && /require_safe_path "VW_BACKUP_DIR" "\$VW_BACKUP_DIR"/ { saw_backup=1 }
      in_func && /error "\$\(t error\.unsafe_path "VW_BIN" "\$\{VW_BIN:-empty\}"\)"/ { saw_bin=1 }
      in_func && /^}/ {
        if (!(saw_data && saw_web && saw_log && saw_backup && saw_bin)) {
          printf "%s Vaultwarden must validate managed paths and VW_BIN before use\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
  awk '
      /_validate_config_values\(\)/ { in_func=1; next }
      in_func && /require_safe_path "INSTALL_DIR" "\$INSTALL_DIR"/ { saw_install=1 }
      in_func && /require_safe_path "BIN_PATH" "\$BIN_PATH"/ { saw_bin=1 }
      in_func && /require_safe_path "CONFIG_FILE" "\$CONFIG_FILE"/ { saw_config=1 }
      in_func && /require_safe_path "VENV_DIR" "\$VENV_DIR"/ { saw_venv=1 }
      in_func && /require_safe_path "LOG_DIR" "\$LOG_DIR"/ { saw_log=1 }
      in_func && /require_safe_path "BACKUP_DIR" "\$BACKUP_DIR"/ { saw_backup=1 }
      in_func && /^}/ {
        if (!(saw_install && saw_bin && saw_config && saw_venv && saw_log && saw_backup)) {
          printf "%s CyberStrikeAI must validate managed directory and derived file paths before use\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
  awk '
      /_validate_config_values\(\)/ { in_func=1; next }
      in_func && /require_safe_path "TICKFLOW_INSTALL_DIR" "\$TICKFLOW_INSTALL_DIR"/ { saw_install=1 }
      in_func && /require_safe_path "TICKFLOW_DATA_DIR" "\$TICKFLOW_DATA_DIR"/ { saw_data=1 }
      in_func && /require_safe_path "TICKFLOW_LOG_DIR" "\$TICKFLOW_LOG_DIR"/ { saw_log=1 }
      in_func && /require_safe_path "TICKFLOW_ENV_FILE" "\$TICKFLOW_ENV_FILE"/ { saw_env=1 }
      in_func && /require_safe_path "TICKFLOW_COMPOSE_FILE" "\$TICKFLOW_COMPOSE_FILE"/ { saw_compose=1 }
      in_func && /require_safe_path "TICKFLOW_TIERS_FILE" "\$TICKFLOW_TIERS_FILE"/ { saw_tiers=1 }
      in_func && /^}/ {
        if (!(saw_install && saw_data && saw_log && saw_env && saw_compose && saw_tiers)) {
          printf "%s TickFlow must validate managed directory and file paths before use\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_tickflow.sh dist/install_tickflow.sh
  awk '
      /_validate_config_values\(\)/ { in_func=1; next }
      in_func && /require_safe_path "SITE_DIR" "\$SITE_DIR"/ { saw_site=1 }
      in_func && /require_safe_path "PUBLIC_DIR" "\$PUBLIC_DIR"/ { saw_public=1 }
      in_func && /require_safe_path "NGINX_ROOT" "\$NGINX_ROOT"/ { saw_nginx=1 }
      in_func && /require_safe_path "BLOG_BACKUP_DIR" "\$BLOG_BACKUP_DIR"/ { saw_backup=1 }
      in_func && /^}/ {
        if (!(saw_site && saw_public && saw_nginx && saw_backup)) {
          printf "%s Blog must validate managed directory paths before use\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_blog.sh dist/install_blog.sh
}

check_tickflow_preflight_defers_docker_runtime_checks() {
  awk '
      /preflight_check\(\)/ { in_func=1; saw_docker=0; saw_compose=0; next }
      in_func && /command -v docker/ { saw_docker=1 }
      in_func && /docker compose version/ { saw_compose=1 }
      in_func && /^}/ {
        if (saw_docker || saw_compose) {
          printf "%s TickFlow preflight must not require Docker before install dependencies are present\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_tickflow.sh dist/install_tickflow.sh
}

check_tickflow_env_rewrites_preserve_existing_secrets() {
  "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    source impl/install_tickflow.sh

    tmp_dir="$(mktemp -d)"
    trap '"'"'rm -rf "$tmp_dir"'"'"' EXIT

    TICKFLOW_INSTALL_DIR="${tmp_dir}/tickflow"
    TICKFLOW_ENV_FILE="${TICKFLOW_INSTALL_DIR}/.env"
    TICKFLOW_PORT="4010"
    TICKFLOW_AUTH_PASSWORD="newpass123"
    TICKFLOW_BACKEND_EXTRAS="alpha,beta"

    mkdir -p "$TICKFLOW_INSTALL_DIR"
    cat > "$TICKFLOW_ENV_FILE" <<'"'"'EOF'"'"'
TICKFLOW_API_KEY=existing-panel-key
AI_PROVIDER=anthropic_compat
AI_BASE_URL=https://example.com/v1
AI_API_KEY=existing-ai-key
AI_MODEL=claude-like
AI_DAILY_TOKEN_BUDGET=123
HOST=127.0.0.1
PORT=9999
LOG_LEVEL=DEBUG
AUTH_PASSWORD=oldpass
BACKEND_EXTRAS=old
DATA_DIR=./old-data
EOF

    _write_env_file

    grep -Fxq "TICKFLOW_API_KEY=existing-panel-key" "$TICKFLOW_ENV_FILE"
    grep -Fxq "AI_PROVIDER=anthropic_compat" "$TICKFLOW_ENV_FILE"
    grep -Fxq "AI_BASE_URL=https://example.com/v1" "$TICKFLOW_ENV_FILE"
    grep -Fxq "AI_API_KEY=existing-ai-key" "$TICKFLOW_ENV_FILE"
    grep -Fxq "AI_MODEL=claude-like" "$TICKFLOW_ENV_FILE"
    grep -Fxq "AI_DAILY_TOKEN_BUDGET=123" "$TICKFLOW_ENV_FILE"
    grep -Fxq "LOG_LEVEL=DEBUG" "$TICKFLOW_ENV_FILE"
    grep -Fxq "PORT=4010" "$TICKFLOW_ENV_FILE"
    grep -Fxq "AUTH_PASSWORD=newpass123" "$TICKFLOW_ENV_FILE"
    grep -Fxq "BACKEND_EXTRAS=alpha,beta" "$TICKFLOW_ENV_FILE"
    grep -Fxq "DATA_DIR=./data" "$TICKFLOW_ENV_FILE"
  '
}

check_tickflow_paths_are_guarded() {
  awk '
      /_clone_or_update_repo\(\)/ { in_clone=1; saw_clone_guard=0; saw_clone_rm=0; next }
      in_clone && /require_safe_path "TICKFLOW_INSTALL_DIR" "\$repo_dir"/ { saw_clone_guard=1 }
      in_clone && /safe_rm_dir "\$repo_dir" "TICKFLOW_INSTALL_DIR"/ {
        if (!saw_clone_guard) {
          printf "%s TickFlow repo reset must validate TICKFLOW_INSTALL_DIR before deletion\n", FILENAME > "/dev/stderr"
          exit 1
        }
        saw_clone_rm=1
      }
      in_clone && /^}/ {
        if (!(saw_clone_guard && saw_clone_rm)) {
          printf "%s TickFlow repo setup must guard and safely reset the install directory\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_clone=0
      }
      /do_uninstall\(\)/ { in_uninstall=1; saw_uninstall_guard=0; saw_uninstall_rm=0; next }
      in_uninstall && /require_safe_path "TICKFLOW_INSTALL_DIR" "\$TICKFLOW_INSTALL_DIR"/ { saw_uninstall_guard=1 }
      in_uninstall && /safe_rm_dir "\$TICKFLOW_INSTALL_DIR" "TICKFLOW_INSTALL_DIR"/ {
        if (!saw_uninstall_guard) {
          printf "%s TickFlow uninstall must validate TICKFLOW_INSTALL_DIR before deletion\n", FILENAME > "/dev/stderr"
          exit 1
        }
        saw_uninstall_rm=1
      }
      in_uninstall && /^}/ {
        if (!(saw_uninstall_guard && saw_uninstall_rm)) {
          printf "%s TickFlow uninstall must use safe_rm_dir for TICKFLOW_INSTALL_DIR\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_uninstall=0
      }
    ' impl/install_tickflow.sh dist/install_tickflow.sh
}

check_safe_rm_dir_is_idempotent() {
  "$BASH_BIN" -c '
    set -euo pipefail
    source lib/fs.sh
    tmp=$(mktemp -d)
    child="${tmp}/missing-dir"
    rmdir "$tmp"
    safe_rm_dir "$child" "TEST_PATH"
  '
  awk '
      /_write_publish_script\(\)/ { saw_helper=1; next }
      saw_helper && /<< BKSH$/ { in_heredoc=1; next }
      in_heredoc && /safe_rm_dir\(\)/ { in_func=1; saw_missing=0; saw_type_guard=0; next }
      in_func && /\[\[ -e "\\\$path" \|\| -L "\\\$path" \]\] \|\| return 0/ { saw_missing=1 }
      in_func && /\[\[ -d "\\\$path" \|\| -L "\\\$path" \]\] \|\| return 1/ { saw_type_guard=1 }
      in_func && /^}/ {
        if (!(saw_missing && saw_type_guard)) {
          printf "%s Blog publish helper safe_rm_dir must treat missing safe paths as already removed and reject non-directory paths\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
        in_heredoc=0
      }
    ' impl/install_blog.sh dist/install_blog.sh
}

check_atomic_helpers_are_atomic() {
  awk '
      /atomic_write_file\(\)/ { in_write=1; saw_dir=0; saw_tmp=0; saw_cat=0; saw_chmod=0; saw_chown=0; saw_mv=0; saw_cleanup=0; next }
      in_write && /mkdir -p "\$target_dir"/ { saw_dir=1 }
      in_write && /mktemp "\$\{target_dir\}\/\.\$\(basename "\$target_path"\)\.XXXXXX"/ { saw_tmp=1 }
      in_write && /cat > "\$target_tmp"/ { saw_cat=1 }
      in_write && /chmod "\$mode" "\$target_tmp"/ { saw_chmod=1 }
      in_write && /chown "\$owner" "\$target_tmp"/ { saw_chown=1 }
      in_write && /mv "\$target_tmp" "\$target_path"/ { saw_mv=1 }
      in_write && /rm -f "\$target_tmp"/ { saw_cleanup=1 }
      in_write && /^}/ {
        if (!(saw_dir && saw_tmp && saw_cat && saw_chmod && saw_chown && saw_mv && saw_cleanup)) {
          printf "%s atomic_write_file must stage, permission, replace, and clean up temporary files\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_write=0
      }
      /atomic_copy_file\(\)/ { in_copy=1; saw_dir=0; saw_tmp=0; saw_cp=0; saw_chmod=0; saw_chown=0; saw_mv=0; saw_cleanup=0; next }
      in_copy && /mkdir -p "\$target_dir"/ { saw_dir=1 }
      in_copy && /mktemp "\$\{target_path\}\.XXXXXX"/ { saw_tmp=1 }
      in_copy && /cp "\$source_path" "\$target_tmp"/ { saw_cp=1 }
      in_copy && /chmod "\$mode" "\$target_tmp"/ { saw_chmod=1 }
      in_copy && /chown "\$owner" "\$target_tmp"/ { saw_chown=1 }
      in_copy && /mv "\$target_tmp" "\$target_path"/ { saw_mv=1 }
      in_copy && /rm -f "\$target_tmp"/ { saw_cleanup=1 }
      in_copy && /^}/ {
        if (!(saw_dir && saw_tmp && saw_cp && saw_chmod && saw_chown && saw_mv && saw_cleanup)) {
          printf "%s atomic_copy_file must stage, permission, replace, and clean up temporary files\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_copy=0
      }
      /atomic_symlink\(\)/ { in_link=1; saw_dir=0; saw_tmp=0; saw_unlink=0; saw_ln=0; saw_mv=0; saw_cleanup=0; next }
      in_link && /mkdir -p "\$link_dir"/ { saw_dir=1 }
      in_link && /mktemp "\$\{link_path\}\.XXXXXX"/ { saw_tmp=1 }
      in_link && /rm -f "\$link_tmp"/ { saw_unlink=1; saw_cleanup=1 }
      in_link && /ln -s "\$target_path" "\$link_tmp"/ { saw_ln=1 }
      in_link && /mv -Tf "\$link_tmp" "\$link_path"/ { saw_mv=1 }
      in_link && /^}/ {
        if (!(saw_dir && saw_tmp && saw_unlink && saw_ln && saw_mv && saw_cleanup)) {
          printf "%s atomic_symlink must stage, replace, and clean up temporary symlinks\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_link=0
      }
    ' lib/atomic.sh dist/install_newapi.sh
}

check_binary_helpers_are_atomic() {
  awk '
      /app_binary_restore_moved_backup\(\)/ { in_moved=1; saw_tmp=0; saw_tmp_return=0; saw_cp=0; saw_chmod=0; saw_chown=0; saw_mv=0; saw_cleanup=0; next }
      in_moved && /mktemp "\$\{BIN_PATH\}\.restore\.XXXXXX"/ { saw_tmp=1 }
      in_moved && saw_tmp && /return 1/ { saw_tmp_return=1 }
      in_moved && /cp "\$backup_path" "\$restore_tmp"/ { saw_cp=1 }
      in_moved && /chmod \+x "\$restore_tmp"/ { saw_chmod=1 }
      in_moved && /chown "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$restore_tmp"/ { saw_chown=1 }
      in_moved && /mv "\$restore_tmp" "\$BIN_PATH"/ { saw_mv=1 }
      in_moved && /rm -f "\$backup_path"/ { saw_cleanup=1 }
      in_moved && /^}/ {
        if (!(saw_tmp && saw_tmp_return && saw_cp && saw_chmod && saw_chown && saw_mv && saw_cleanup)) {
          printf "%s app_binary_restore_moved_backup must stage, restore atomically, and remove moved backups\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_moved=0
      }
      /app_binary_install_candidate\(\)/ { in_install=1; saw_backup=0; saw_mv=0; saw_restore=0; saw_chmod=0; saw_chown=0; saw_cleanup=0; next }
      in_install && /mv "\$BIN_PATH" "\$backup_path"/ { saw_backup=1 }
      in_install && /mv "\$tmp_bin" "\$BIN_PATH"/ { saw_mv=1 }
      in_install && /app_binary_restore_moved_backup "\$backup_path"/ { saw_restore=1 }
      in_install && /chmod \+x "\$BIN_PATH"/ { saw_chmod=1 }
      in_install && /chown "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$BIN_PATH"/ { saw_chown=1 }
      in_install && /rm -f "\$tmp_bin"/ { saw_cleanup=1 }
      in_install && /^}/ {
        if (!(saw_backup && saw_mv && saw_restore && saw_chmod && saw_chown && saw_cleanup)) {
          printf "%s app_binary_install_candidate must back up, replace, restore on failure, and clean up candidates\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_install=0
      }
      /app_binary_restore_backup\(\)/ { in_restore=1; saw_tmp=0; saw_tmp_return=0; saw_cp=0; saw_chmod=0; saw_chown=0; saw_mv=0; next }
      in_restore && /mktemp "\$\{BIN_PATH\}\.restore\.XXXXXX"/ { saw_tmp=1 }
      in_restore && saw_tmp && /return 1/ { saw_tmp_return=1 }
      in_restore && /cp "\$backup_path" "\$restore_tmp"/ { saw_cp=1 }
      in_restore && /chmod \+x "\$restore_tmp"/ { saw_chmod=1 }
      in_restore && /chown "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$restore_tmp"/ { saw_chown=1 }
      in_restore && /mv "\$restore_tmp" "\$BIN_PATH"/ { saw_mv=1 }
      in_restore && /^}/ {
        if (!(saw_tmp && saw_tmp_return && saw_cp && saw_chmod && saw_chown && saw_mv)) {
          printf "%s app_binary_restore_backup must stage and atomically restore binary mode and ownership\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_restore=0
      }
      /app_binary_backup_current\(\)/ { in_backup=1; saw_atomic=0; next }
      in_backup && /atomic_copy_file "\$BIN_PATH" "\$backup_path"/ { saw_atomic=1 }
      in_backup && /^}/ {
        if (!saw_atomic) {
          printf "%s app_binary_backup_current must use atomic_copy_file\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_backup=0
      }
    ' lib/binary.sh dist/install_newapi.sh
}

check_systemd_helper_is_atomic() {
  awk '
      /systemd_write_unit\(\)/ { in_func=1; saw_atomic=0; next }
      in_func && /atomic_write_file "\$unit_path" 644 root:root/ { saw_atomic=1 }
      in_func && /^}/ {
        if (!saw_atomic) {
          printf "%s systemd_write_unit must use atomic_write_file with root ownership\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' lib/service.sh dist/install_newapi.sh
}

check_service_status_label() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"
  cat > "${tmp_dir}/systemctl" <<'STUB'
#!/usr/bin/env bash
case "$1" in
  is-active)
    [[ "${3:-}" == "active-service" ]] && exit 0
    exit 3
    ;;
  list-unit-files)
    for arg in "$@"; do
      if [[ "$arg" == "inactive-service.service" ]]; then
        echo "inactive-service.service disabled"
        exit 0
      fi
      if [[ "$arg" == "missing-service.service" ]]; then
        exit 0
      fi
    done
    exit 0
    ;;
esac
exit 1
STUB
  chmod +x "${tmp_dir}/systemctl"

  PATH="${tmp_dir}:$PATH" DEPLOY_LANG=en "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    [[ "$(service_status_label active-service)" == "active" ]]
    [[ "$(service_status_label inactive-service)" == "inactive" ]]
    [[ "$(service_status_label missing-service)" == "unknown" ]]
  '
  rm -rf "$tmp_dir"
}

check_config_crlf_handling() {
  local tmp_dir conf
  tmp_dir="$(mktemp -d)"
  conf="${tmp_dir}/deploy.conf"
  printf ' FOO = "bar"\r\n\tBAZ\t= qux \r\nQUOTED = " spaced value "\r\n' > "$conf"

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
    source lib/core.sh
    FOO=""
    BAZ=""
    QUOTED=""
    load_config_file "$1" FOO BAZ QUOTED
    [[ "$FOO" == "bar" ]] || { printf "FOO contained unexpected bytes: " >&2; printf "%s" "$FOO" | od -An -tx1 >&2; exit 1; }
    [[ "$BAZ" == "qux" ]] || { printf "BAZ contained unexpected bytes: " >&2; printf "%s" "$BAZ" | od -An -tx1 >&2; exit 1; }
    [[ "$QUOTED" == " spaced value " ]] || { printf "QUOTED contained unexpected bytes: " >&2; printf "%s" "$QUOTED" | od -An -tx1 >&2; exit 1; }
    sanitized="$(sanitize_conf_val $'"'"'one\ntwo'"'"')"
    [[ "$sanitized" == "one" ]] || { printf "sanitize_conf_val returned unexpected bytes: " >&2; printf "%s" "$sanitized" | od -An -tx1 >&2; exit 1; }
  ' _ "$conf"

  rm -rf "$tmp_dir"
}

check_config_write_failure_cleanup() {
  local tmp_dir conf
  tmp_dir="$(mktemp -d)"
  conf="${tmp_dir}/deploy.conf"

  cat > "${tmp_dir}/chmod" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  chmod +x "${tmp_dir}/chmod"

  "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    FOO="bar"
    PATH="$1:$PATH"
    set +e
    write_config_file "$2" FOO
    status=$?
    set -e
    [[ "$status" -ne 0 ]] || { echo "write_config_file unexpectedly succeeded" >&2; exit 1; }
    if find "$(dirname "$2")" -maxdepth 1 -name "$(basename "$2").tmp.*" -type f | grep -q .; then
      echo "write_config_file left a temporary config file behind" >&2
      find "$(dirname "$2")" -maxdepth 1 -name "$(basename "$2").tmp.*" -type f >&2
      exit 1
    fi
  ' _ "$tmp_dir" "$conf"

  rm -f "${tmp_dir}/chmod"
  cat > "${tmp_dir}/chown" <<'STUB'
#!/usr/bin/env bash
exit 1
STUB
  chmod +x "${tmp_dir}/chown"

  "$BASH_BIN" -c '
    set -euo pipefail
    source lib/core.sh
    FOO="bar"
    PATH="$1:$PATH"
    set +e
    write_config_file "$2" FOO
    status=$?
    set -e
    [[ "$status" -ne 0 ]] || { echo "write_config_file unexpectedly ignored chown failure" >&2; exit 1; }
    if find "$(dirname "$2")" -maxdepth 1 -name "$(basename "$2").tmp.*" -type f | grep -q .; then
      echo "write_config_file left a temporary config file behind after chown failure" >&2
      find "$(dirname "$2")" -maxdepth 1 -name "$(basename "$2").tmp.*" -type f >&2
      exit 1
    fi
  ' _ "$tmp_dir" "$conf"

  rm -rf "$tmp_dir"
}

check_unsafe_config_loads_fail_closed() {
  if grep -R -n 'load_config_file "\$CONF_FILE" "\${CONFIG_KEYS\[@\]}" || return 0' impl dist 2>/dev/null; then
    echo "App config loaders must not ignore unsafe or unreadable config files." >&2
    return 1
  fi
  awk '
      /error "\$\(t error\.config_owner "\$conf_file"\)"/ { saw_owner=1 }
      /error "\$\(t error\.config_permission "\$conf_file"\)"/ { saw_permission=1 }
      /warn "\$\(t warn\.config_(owner|permission)/ { saw_warn=1 }
      END {
        if (!(saw_owner && saw_permission) || saw_warn) {
          print "Unsafe config ownership or permissions must fail closed with config errors." > "/dev/stderr"
          exit 1
        }
      }
    ' lib/config.sh
}

check_config_save_failures_are_explicit() {
  awk '
      /write_config_file\(\)/ { in_func=1; saw_tmp=0; saw_tmp_return=0; saw_chmod=0; saw_mv=0; saw_cleanup=0; next }
      in_func && /if ! tmp_file="\$\(mktemp "\$\{conf_file\}\.tmp\.XXXXXX"\)"; then/ { saw_tmp=1 }
      in_func && saw_tmp && /return 1/ { saw_tmp_return=1 }
      in_func && /chmod 600 "\$tmp_file"/ { saw_chmod=1 }
      in_func && /mv "\$tmp_file" "\$conf_file"/ { saw_mv=1 }
      in_func && /rm -f "\$tmp_file"/ { saw_cleanup=1 }
      in_func && /^}/ {
        if (!(saw_tmp && saw_tmp_return && saw_chmod && saw_mv && saw_cleanup)) {
          printf "%s write_config_file must report temp creation failures, secure, replace, and clean up temporary config files\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' lib/config.sh dist/install_newapi.sh
  awk '
      /error\.config_write/ { saw_key=1 }
      END {
        if (!saw_key) {
          print "Config save failures must have a shared error message." > "/dev/stderr"
          exit 1
        }
      }
    ' lib/i18n.sh dist/install_newapi.sh
  awk '
      /^(app_)?save_config\(\)/ { in_func=1; saw_if=0; saw_error=0; next }
      in_func && /write_config_file/ { saw_if=1 }
      in_func && /error.*config_write/ { saw_error=1 }
      in_func && /^}/ {
        if (!(saw_if && saw_error)) {
          printf "%s save_config must report config write failures explicitly\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh impl/install_cyberstrikeai.sh impl/install_vaultwarden.sh impl/install_blog.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_cyberstrikeai.sh dist/install_vaultwarden.sh dist/install_blog.sh lib/app.sh
}

check_blog_config_persistence() {
  awk '
      /^CONFIG_KEYS=\(/ { saw_keys=1; next }
      saw_keys && /BLOG_DOMAIN/ { saw_domain=1 }
      saw_keys && /SITE_DIR PUBLIC_DIR NGINX_ROOT BLOG_BACKUP_DIR BLOG_BACKUP_KEEP_DAYS/ { saw_paths=1 }
      saw_keys && /THEME_NAME THEME_REPO ENABLE_CMS CMS_BACKEND CMS_REPO CMS_BRANCH CMS_SITE_URL/ { saw_cms=1 }
      /_BLOG_DERIVE_PATHS\(\)/ { saw_derive=1 }
      /_blog_load_config_if_root\(\)/ { in_load=1; saw_root_guard=0; saw_app_load=0; next }
      in_load && /\[\[ \$\{EUID:-\$\(id -u\)\} -eq 0 \]\]/ { saw_root_guard=1 }
      in_load && /app_load_config _BLOG_DERIVE_PATHS/ { saw_app_load=1 }
      in_load && /^}/ { in_load=0 }
      /^_validate_config_values$/ { saw_install_validate=1 }
      /^app_save_config$/ { saw_install_save=1 }
      /^do_status\(\) \{/ { current="status"; saw_status=1; next }
      /^do_update\(\) \{/ { current="update"; saw_update=1; next }
      /^do_backup\(\) \{/ { current="backup"; saw_backup=1; next }
      /^do_uninstall\(\) \{/ { current="uninstall"; saw_uninstall=1; next }
      current == "status" && /_blog_load_config_if_root/ { loaded_status=1; current="" }
      current == "update" && /_blog_load_config_if_root/ { loaded_update=1; current="" }
      current == "backup" && /_blog_load_config_if_root/ { loaded_backup=1; current="" }
      current == "uninstall" && /_blog_load_config_if_root/ { loaded_uninstall=1; current="" }
      END {
        if (!(saw_keys && saw_domain && saw_paths && saw_cms && saw_derive && saw_root_guard && saw_app_load && saw_install_validate && saw_install_save && saw_status && saw_update && saw_backup && saw_uninstall && loaded_status && loaded_update && loaded_backup && loaded_uninstall)) {
          printf "%s Blog must persist install config and load it for status/update/backup/uninstall\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_blog.sh dist/install_blog.sh
}

check_tickflow_config_files_are_atomic() {
  if grep -R -nE '^[[:space:]]*cat > "\$TICKFLOW_(ENV|COMPOSE|TIERS)_FILE"|^[[:space:]]*} > "\$env_tmp"' \
      impl/install_tickflow.sh dist/install_tickflow.sh 2>/dev/null; then
    echo "TickFlow config files must be written with atomic_write_file." >&2
    return 1
  fi
  awk '
      /_ensure_data_layout\(\)/ { in_tiers=1; saw_tiers=0; next }
      in_tiers && /atomic_write_file "\$TICKFLOW_TIERS_FILE" 644/ { saw_tiers=1 }
      in_tiers && /^}/ { in_tiers=0 }
      /_write_env_file\(\)/ { in_env=1; saw_env=0; next }
      in_env && /atomic_write_file "\$TICKFLOW_ENV_FILE" 600/ { saw_env=1 }
      in_env && /^}/ { in_env=0 }
      /_write_compose_file\(\)/ { in_compose=1; saw_compose=0; next }
      in_compose && /atomic_write_file "\$TICKFLOW_COMPOSE_FILE" 644/ { saw_compose=1 }
      in_compose && /^}/ { in_compose=0 }
      END {
        if (!(saw_tiers && saw_env && saw_compose)) {
          printf "%s TickFlow must atomically write tiers, env, and compose files\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_tickflow.sh dist/install_tickflow.sh
}

check_tickflow_systemd_shell_paths_are_quoted() {
  if grep -R -nE 'Exec(Start|Stop|Reload)=/bin/bash -lc '\''cd "\$\{TICKFLOW_INSTALL_DIR\}"| -f "\$\{TICKFLOW_COMPOSE_FILE\}"' \
      impl/install_tickflow.sh dist/install_tickflow.sh 2>/dev/null; then
    echo "TickFlow systemd shell commands must not interpolate raw paths." >&2
    return 1
  fi
  awk '
      /_write_systemd_unit\(\)/ { in_func=1; saw_install=0; saw_compose=0; saw_exec=0; next }
      in_func && /printf -v install_dir_literal '\''%q'\'' "\$TICKFLOW_INSTALL_DIR"/ { saw_install=1 }
      in_func && /printf -v compose_file_literal '\''%q'\'' "\$TICKFLOW_COMPOSE_FILE"/ { saw_compose=1 }
      in_func && /ExecStart=\/bin\/bash -lc '\''cd \$\{install_dir_literal\} && \$\{compose_cmd\} -f \$\{compose_file_literal\} up -d --build'\''/ { saw_exec=1 }
      in_func && /^}/ {
        if (!(saw_install && saw_compose && saw_exec)) {
          printf "%s TickFlow systemd shell command paths must use printf %%q literals\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_tickflow.sh dist/install_tickflow.sh
}

check_tickflow_systemctl_failures_are_reported() {
  if grep -R -nE 'systemctl (enable --now docker|enable "\$TICKFLOW_SERVICE_NAME"|stop "\$TICKFLOW_SERVICE_NAME"|disable "\$TICKFLOW_SERVICE_NAME"|daemon-reload).* \|\| true' \
      impl/install_tickflow.sh dist/install_tickflow.sh 2>/dev/null; then
    echo "TickFlow systemctl failures must be reported instead of silently ignored." >&2
    return 1
  fi
  awk '
      /app\.tickflow\.warn\.docker_enable_failed/ { saw_docker_key=1 }
      /app\.tickflow\.warn\.service_enable_failed/ { saw_enable_key=1 }
      /app\.tickflow\.warn\.service_stop_failed/ { saw_stop_key=1 }
      /app\.tickflow\.warn\.service_disable_failed/ { saw_disable_key=1 }
      /app\.tickflow\.warn\.systemd_reload_failed/ { saw_reload_key=1 }
      END {
        if (!(saw_docker_key && saw_enable_key && saw_stop_key && saw_disable_key && saw_reload_key)) {
          print "TickFlow must provide localized warnings for nonfatal systemctl failures." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/tickflow.sh
  awk '
      /systemctl enable --now docker/ { saw_docker=1 }
      saw_docker && /warn "\$\(t app\.tickflow\.warn\.docker_enable_failed\)"/ { saw_docker_warn=1; saw_docker=0 }
      /systemctl enable "\$TICKFLOW_SERVICE_NAME"/ { saw_enable=1 }
      saw_enable && /warn "\$\(t app\.tickflow\.warn\.service_enable_failed "\$TICKFLOW_SERVICE_NAME" "\$TICKFLOW_SERVICE_NAME"\)"/ { saw_enable_warn=1; saw_enable=0 }
      /systemctl stop "\$TICKFLOW_SERVICE_NAME"/ { saw_stop=1 }
      saw_stop && /warn "\$\(t app\.tickflow\.warn\.service_stop_failed "\$TICKFLOW_SERVICE_NAME" "\$TICKFLOW_SERVICE_NAME"\)"/ { saw_stop_warn=1; saw_stop=0 }
      /systemctl disable "\$TICKFLOW_SERVICE_NAME"/ { saw_disable=1 }
      saw_disable && /warn "\$\(t app\.tickflow\.warn\.service_disable_failed "\$TICKFLOW_SERVICE_NAME" "\$TICKFLOW_SERVICE_NAME"\)"/ { saw_disable_warn=1; saw_disable=0 }
      /systemctl daemon-reload/ { saw_reload=1 }
      saw_reload && /warn "\$\(t app\.tickflow\.warn\.systemd_reload_failed "\$TICKFLOW_SERVICE_NAME"\)"/ { saw_reload_warn=1; saw_reload=0 }
      END {
        if (!(saw_docker_warn && saw_enable_warn && saw_stop_warn && saw_disable_warn && saw_reload_warn)) {
          printf "%s TickFlow must warn on nonfatal systemctl failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_tickflow.sh dist/install_tickflow.sh
}

check_tickflow_manual_backup_is_explicit() {
  awk '
      /app\.tickflow\.backup\.error_dir/ { saw_dir_key=1 }
      /app\.tickflow\.backup\.error_archive/ { saw_archive_key=1 }
      /app\.tickflow\.backup\.success/ { saw_success_key=1 }
      END {
        if (!(saw_dir_key && saw_archive_key && saw_success_key)) {
          print "TickFlow manual backup must provide localized backup messages." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/tickflow.sh
  awk '
      /do_backup\(\)/ { in_backup=1; saw_dir=0; saw_dir_error=0; saw_tmp=0; saw_tar=0; saw_cleanup=0; saw_chmod=0; saw_mv=0; saw_success=0; next }
      in_backup && /if ! mkdir -p "\$backup_dir"; then/ { saw_dir=1 }
      in_backup && /error "\$\(t app\.tickflow\.backup\.error_dir "\$backup_dir"\)"/ { saw_dir_error=1 }
      in_backup && /local archive_tmp="\$\{archive\}\.tmp"/ { saw_tmp=1 }
      in_backup && /if ! tar -czf "\$archive_tmp" -C "\$TICKFLOW_INSTALL_DIR" data tiers\.yaml \.env >&2; then/ { saw_tar=1 }
      in_backup && /rm -f "\$archive_tmp"/ { saw_cleanup=1 }
      in_backup && /chmod 600 "\$archive_tmp"/ { saw_chmod=1 }
      in_backup && /mv "\$archive_tmp" "\$archive"/ { saw_mv=1 }
      in_backup && /success "\$\(t app\.tickflow\.backup\.success "\$archive"\)"/ { saw_success=1 }
      in_backup && /release_lock/ {
        if (!(saw_dir && saw_dir_error && saw_tmp && saw_tar && saw_cleanup && saw_chmod && saw_mv && saw_success)) {
          printf "%s TickFlow manual backup must handle directory, tar, permission, and move failures explicitly\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_backup=0
      }
    ' impl/install_tickflow.sh dist/install_tickflow.sh
}

check_blog_restore_action() {
  grep -Fq 'app.blog.restore.success' apps/blog.sh || {
    echo "Blog restore action must provide localized success text." >&2
    return 1
  }
  awk '
      /do_restore\(\)/ { in_restore=1; saw_restore=1; next }
      in_restore && /require_root "restore"/ { saw_root=1 }
      in_restore && /_blog_load_config_if_root/ { saw_config=1 }
      in_restore && /acquire_lock/ { saw_lock=1 }
      in_restore && /require_safe_path "BLOG_BACKUP_DIR"/ { saw_backup_path=1 }
      in_restore && /_blog_latest_backup_archive/ { saw_latest=1 }
      in_restore && /_blog_archive_paths_are_safe/ { saw_safe_archive=1 }
      in_restore && /tar -xzf "\$archive" -C "\$extract_dir" >&2/ { saw_tar_stderr=1 }
      in_restore && /_blog_restore_dir_from_backup "\$\{extract_dir\}\/site" "SITE_DIR" "\$SITE_DIR"/ { saw_site=1 }
      in_restore && /_blog_restore_dir_from_backup "\$\{extract_dir\}\/public" "PUBLIC_DIR" "\$PUBLIC_DIR"/ { saw_public=1 }
      in_restore && /_blog_restore_dir_from_backup "\$\{extract_dir\}\/nginx-root" "NGINX_ROOT" "\$NGINX_ROOT"/ { saw_nginx_root=1 }
      in_restore && /_blog_restore_file_from_backup "\$\{extract_dir\}\/nginx-site\.conf" "NGINX_SITE" \/etc\/nginx\/sites-available\/blog 644/ { saw_nginx_conf=1 }
      in_restore && /_blog_restore_file_from_backup "\$\{extract_dir\}\/blog-publish" "BLOG_PUBLISH" \/usr\/local\/bin\/blog-publish 750/ { saw_publish=1 }
      in_restore && /nginx -t/ { saw_nginx_test=1 }
      in_restore && /systemctl reload nginx/ { saw_reload=1 }
      in_restore && /^}/ { in_restore=0 }
      END {
        if (!(saw_restore && saw_root && saw_config && saw_lock && saw_backup_path && saw_latest && saw_safe_archive && saw_tar_stderr && saw_site && saw_public && saw_nginx_root && saw_nginx_conf && saw_publish && saw_nginx_test && saw_reload)) {
          printf "%s Blog restore action must safely restore backup archives and validate nginx before reload\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_blog.sh dist/install_blog.sh
}

check_sub2api_codename_resolution() {
  local tmp_dir
  tmp_dir="$(mktemp -d)"

  cat > "${tmp_dir}/lsb_release" <<'STUB'
#!/usr/bin/env bash
[[ "${1:-}" == "-cs" ]] || exit 1
echo jammy
STUB
  chmod +x "${tmp_dir}/lsb_release"

  PATH="${tmp_dir}:$PATH" "$BASH_BIN" -c '
    set -euo pipefail
    unset VERSION_CODENAME UBUNTU_CODENAME
    source lib/core.sh
    source apps/sub2api.sh
    [[ "$(_apt_codename)" == "jammy" ]]
  '

  rm -rf "$tmp_dir"
}

check_no_unsupported_systemctl_options() {
  if grep -R -nE 'systemctl[[:space:]]+stop[[:space:]][^;&|]*--timeout' impl lib dist 2>/dev/null; then
    echo "systemctl stop does not support --timeout; use the default blocking stop behavior." >&2
    return 1
  fi
}

check_no_fixed_tmp_downloads() {
  if grep -R -n '/tmp/hugo\.deb' impl dist 2>/dev/null; then
    echo "Use mktemp for Hugo package downloads instead of a fixed /tmp path." >&2
    return 1
  fi
}

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
      /warn "\$\(t app\.(newapi|sub2api)\.warn\.iptables_write_failed\)"/ { saw_warn=1 }
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
    ' impl/install_newapi.sh impl/install_sub2api.sh dist/install_newapi.sh dist/install_sub2api.sh
}

check_netfilter_persistent_save_reports_failures() {
  if grep -R -nE 'netfilter-persistent save 2>/dev/null( && success .*\\|\\| true|[[:space:]]*\\[?;?)' \
      impl/install_newapi.sh impl/install_sub2api.sh impl/install_vaultwarden.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "netfilter-persistent save failures must not be silently ignored." >&2
    return 1
  fi
  awk '
      /if command -v netfilter-persistent &>\/dev\/null; then/ { in_block=1; saw_save=0; saw_success=0; saw_warn=0; next }
      in_block && /if netfilter-persistent save 2>\/dev\/null; then/ { saw_save=1 }
      in_block && /success "\$\(t app\.(newapi|sub2api|vaultwarden)\.success\.iptables_saved\)"/ { saw_success=1 }
      in_block && /warn "\$\(t app\.(newapi|sub2api|vaultwarden)\.warn\.iptables_not_persisted\)"/ { saw_warn=1 }
      in_block && /elif command -v iptables-save &>\/dev\/null; then|else$/ {
        if (!(saw_save && saw_success && saw_warn)) {
          printf "%s netfilter-persistent save must report both success and failure outcomes\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh impl/install_vaultwarden.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_vaultwarden.sh
}

check_random_head_pipelines_handle_sigpipe() {
  if grep -R -nE 'rand .*\\|.*head -c [0-9]+\\)$|tr -dc .*\\| head -c [0-9]+\\)$' impl dist 2>/dev/null; then
    echo "Random byte pipelines ending in head -c need an explicit successful terminator under pipefail." >&2
    return 1
  fi
}

check_summary_ip_detection_has_fallback() {
  if grep -R -n 'hostname -I .*| awk '\''{print $1}'\''' \
      impl/install_blog.sh impl/install_newapi.sh impl/install_sub2api.sh impl/install_vaultwarden.sh impl/install_cyberstrikeai.sh \
      dist/install_blog.sh dist/install_newapi.sh dist/install_sub2api.sh dist/install_vaultwarden.sh dist/install_cyberstrikeai.sh 2>/dev/null \
      | grep -v '|| true'; then
    echo "Summary IP detection must tolerate hostname -I failures and provide YOUR_SERVER_IP fallback." >&2
    return 1
  fi
  local file
  for file in impl/install_blog.sh impl/install_newapi.sh impl/install_sub2api.sh impl/install_vaultwarden.sh impl/install_cyberstrikeai.sh \
      dist/install_blog.sh dist/install_newapi.sh dist/install_sub2api.sh dist/install_vaultwarden.sh dist/install_cyberstrikeai.sh; do
    awk '
        /hostname -I 2>\/dev\/null \| awk '\''\{print \$1\}'\'' \|\| true/ { saw_safe=1 }
        /YOUR_SERVER_IP/ { saw_fallback=1 }
        END {
          if (!(saw_safe && saw_fallback)) {
            printf "%s summary IP detection must use a non-fatal hostname pipeline and fallback value\n", FILENAME > "/dev/stderr"
            exit 1
          }
        }
      ' "$file"
  done
}

check_systemctl_status_diagnostics_are_nonfatal() {
  awk '
      /systemctl status .*\| head .*\| sed/ {
        pending=1
        pending_line=FNR
        if (/&&|\|\| true/) {
          pending=0
        }
        next
      }
      pending {
        if (/\|\| (true|echo|warn|error)/) {
          pending=0
          next
        }
        printf "%s:%d systemctl status diagnostic pipelines must be non-fatal under pipefail.\n", FILENAME, pending_line > "/dev/stderr"
        exit 1
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh impl/install_vaultwarden.sh impl/install_cyberstrikeai.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_vaultwarden.sh dist/install_cyberstrikeai.sh
}

check_status_commands_allow_non_root() {
  awk '
      /app\.sub2api\.warn\.non_root_status/ { saw_sub2api=1 }
      /app\.cyberstrikeai\.warn\.non_root_status/ { saw_csai=1 }
      /app\.tickflow\.warn\.non_root_status/ { saw_tickflow=1 }
      END {
        if (!(saw_sub2api && saw_csai && saw_tickflow)) {
          print "Status commands that run without root must warn when details may be incomplete." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/sub2api.sh apps/cyberstrikeai.sh apps/tickflow.sh
  awk '
      /preflight_check\(\)/ { in_preflight=1; saw_status_exemption=0; next }
      in_preflight && /status/ && /\$EUID/ { saw_status_exemption=1 }
      in_preflight && /^}/ {
        if (!saw_status_exemption) {
          printf "%s preflight must allow the status action without root\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_preflight=0
      }
      /do_status\(\)/ { in_status=1; saw_warn=0; next }
      in_status && /warn "\$\(t app\.(newapi|sub2api|cyberstrikeai|tickflow)\.warn\.non_root_status "\$0"\)"/ { saw_warn=1 }
      in_status && /^}/ {
        if (!saw_warn) {
          printf "%s status must warn when running without root\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_status=0
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh impl/install_cyberstrikeai.sh impl/install_tickflow.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_cyberstrikeai.sh dist/install_tickflow.sh
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
      in_status && /ls -lh "\$\{VW_DATA_DIR\}" 2>\/dev\/null \| tail -n \+2 \| awk .* \|\| true/ { saw_ls=1 }
      in_status && /_data_size=\$\(du -sh "\$VW_DATA_DIR" 2>\/dev\/null \| cut -f1 \|\| t status\.unknown\)/ { saw_data_size=1 }
      in_status && /DB_SIZE=\$\(du -sh "\$\{VW_DATA_DIR\}\/db\.sqlite3" 2>\/dev\/null \| cut -f1 \|\| t status\.unknown\)/ { saw_db_size=1 }
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
}

check_vaultwarden_find_head_pipelines_are_nonfatal() {
  if grep -R -nE '\$\(find [^)]*\| head -1\)' \
      impl/install_vaultwarden.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "Vaultwarden find/head lookups must fall back so empty results reach explicit handling under pipefail." >&2
    return 1
  fi
}

check_cyberstrikeai_display_sizes_are_nonfatal() {
  awk '
      /do_backup\(\)/ { in_backup=1; next }
      in_backup && /^}/ {
        if (!(saw_backup_file_size && saw_backup_loop)) {
          printf "%s CyberStrikeAI backup listing must tolerate disappearing backup files\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_backup=0
      }
      in_backup && /du -sh "\$file" 2>\/dev\/null \| awk '\''\{print \$1\}'\'' \|\| t status\.unknown/ { saw_backup_file_size=1 }
      in_backup && /done \|\| true/ { saw_backup_loop=1 }
      /do_status\(\)/ { in_status=1; next }
      in_status && /^}/ {
        if (!(saw_binary_size && saw_backup_dir_size && saw_status_file_size && saw_status_loop)) {
          printf "%s CyberStrikeAI status display sizes must fall back instead of failing under pipefail\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_status=0
      }
      in_status && /du -sh "\$BIN_PATH" 2>\/dev\/null \| awk '\''\{print \$1\}'\'' \|\| t status\.unknown/ { saw_binary_size=1 }
      in_status && /size=\$\(du -sh "\$BACKUP_DIR" 2>\/dev\/null \| awk '\''\{print \$1\}'\'' \|\| t status\.unknown\)/ { saw_backup_dir_size=1 }
      in_status && /du -sh "\$file" 2>\/dev\/null \| awk '\''\{print \$1\}'\'' \|\| t status\.unknown/ { saw_status_file_size=1 }
      in_status && /done \|\| true/ { saw_status_loop=1 }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_api_status_directory_sizes_are_nonfatal() {
  awk '
      /do_status\(\)/ { in_status=1; next }
      in_status && /^}/ {
        if (!(saw_data && saw_db && saw_backup)) {
          printf "%s NewAPI status directory sizes must fall back instead of failing under pipefail\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_status=0
      }
      in_status && /data_size=\$\(du -sh "\$DATA_DIR" 2>\/dev\/null \| awk '\''\{print \$1\}'\'' \|\| t app\.newapi\.status\.unknown\)/ { saw_data=1 }
      in_status && /db_size=\$\(du -sh "\$\{DATA_DIR\}\/one-api\.db" 2>\/dev\/null \| awk '\''\{print \$1\}'\'' \|\| t app\.newapi\.status\.unknown\)/ { saw_db=1 }
      in_status && /bak_total_size=\$\(du -sh "\$BACKUP_DIR" 2>\/dev\/null \| awk '\''\{print \$1\}'\'' \|\| t app\.newapi\.status\.unknown\)/ { saw_backup=1 }
    ' impl/install_newapi.sh dist/install_newapi.sh
  awk '
      /do_status\(\)/ { in_status=1; next }
      in_status && /^}/ {
        if (!(saw_dir && saw_backup)) {
          printf "%s Sub2API status directory sizes must fall back instead of failing under pipefail\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_status=0
      }
      in_status && /_sz=\$\(du -sh "\$_d" 2>\/dev\/null \| awk '\''\{print \$1\}'\'' \|\| t app\.sub2api\.status\.unknown\)/ { saw_dir=1 }
      in_status && /bak_total_size=\$\(du -sh "\$BACKUP_DIR" 2>\/dev\/null \| awk '\''\{print \$1\}'\'' \|\| t app\.sub2api\.status\.unknown\)/ { saw_backup=1 }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_api_ports_are_validated() {
  awk '
      /app\.newapi\.error\.port_invalid/ { saw_key=1 }
      /Set a port between 1 and 65535/ { saw_guidance=1 }
      END {
        if (!(saw_key && saw_guidance)) {
          print "NewAPI must provide an actionable invalid port error." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/newapi.sh
  awk '
      /app\.sub2api\.error\.port_invalid/ { saw_key=1 }
      /Set a port between 1 and 65535/ { saw_guidance=1 }
      END {
        if (!(saw_key && saw_guidance)) {
          print "Sub2API must provide an actionable invalid port error." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/sub2api.sh
  awk '
      /preflight_check\(\)/ { in_preflight=1; next }
      in_preflight && /^}/ {
        if (!saw_preflight) {
          printf "%s NewAPI preflight must validate PORT defaults\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_preflight=0
      }
      in_preflight && /_validate_config_values/ { saw_preflight=1 }
      /_validate_config_values\(\)/ { in_validate=1; next }
      in_validate && /app_validate_port/ { saw_valport=1 }
      in_validate && /^}/ { in_validate=0 }
      END {
        if (!(saw_preflight && saw_valport)) {
          printf "%s NewAPI must validate PORT range via _validate_config_values\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
  awk '
      /preflight_check\(\)/ { in_preflight=1; next }
      in_preflight && /^}/ {
        if (!saw_preflight) {
          printf "%s Sub2API preflight must validate PORT defaults\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_preflight=0
      }
      in_preflight && /_validate_config_values/ { saw_preflight=1 }
      /_validate_config_values\(\)/ { in_validate=1; next }
      in_validate && /app_validate_port/ { saw_valport=1 }
      in_validate && /^}/ { in_validate=0 }
      END {
        if (!(saw_preflight && saw_valport)) {
          printf "%s Sub2API must validate PORT range via _validate_config_values\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_cyberstrikeai_ports_are_validated() {
  awk '
      /app\.cyberstrikeai\.error\.port_invalid/ { saw_key=1 }
      /Set a port between 1 and 65535/ { saw_guidance=1 }
      END {
        if (!(saw_key && saw_guidance)) {
          print "CyberStrikeAI must provide an actionable invalid port error." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/cyberstrikeai.sh
  awk '
      /preflight_check\(\)/ { in_preflight=1; next }
      in_preflight && /^}/ {
        if (!saw_preflight) {
          printf "%s CyberStrikeAI preflight must validate PORT and PUBLIC_PORT defaults\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_preflight=0
      }
      in_preflight && /_validate_config_values/ { saw_preflight=1 }
      /_validate_config_values\(\)/ { in_validate=1; next }
      in_validate && /app_validate_port "\$PORT"/ { saw_port=1 }
      in_validate && /app_validate_port "\$PUBLIC_PORT"/ { saw_public_port=1 }
      in_validate && /^}/ { in_validate=0 }
      END {
        if (!(saw_preflight && saw_port && saw_public_port)) {
          printf "%s CyberStrikeAI must validate PORT and PUBLIC_PORT via _validate_config_values\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_booleans_are_validated() {
  awk '
      /app\.cyberstrikeai\.error\.bool_invalid/ { saw_key=1 }
      /true\/false, yes\/no, on\/off, or 1\/0/ { saw_guidance=1 }
      END {
        if (!(saw_key && saw_guidance)) {
          print "CyberStrikeAI must provide an actionable invalid boolean config error." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/cyberstrikeai.sh
  awk '
      /preflight_check\(\)/ { in_preflight=1; next }
      in_preflight && /^}/ {
        if (!saw_preflight) {
          printf "%s CyberStrikeAI preflight must validate boolean config defaults\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_preflight=0
      }
      in_preflight && /_validate_config_values/ { saw_preflight=1 }
      /_validate_config_values\(\)/ { in_validate=1; next }
      in_validate && /app_validate_bool/ { saw_bool=1 }
      in_validate && /^}/ { in_validate=0 }
      END {
        if (!(saw_preflight && saw_bool)) {
          printf "%s CyberStrikeAI must validate ENABLE_NGINX, CSAI_HTTPS, and OPEN_FIREWALL before using them\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_nginx_domains_are_validated() {
  awk '
      /is_valid_dns_name\(\)/ { saw_helper=1 }
      /name=.*\{1:-\}/ { saw_name=1 }
      /\[\[ "\$name" != \*\.\.\* \]\] \|\| return 1/ { saw_dots=1 }
      /\[\[ "\$name" == \*\.\* \]\] \|\| return 1/ { saw_dot_required=1 }
      END {
        if (!(saw_helper && saw_name && saw_dots && saw_dot_required)) {
          print "Shared DNS validation helper must reject empty, overlong, malformed, and single-label server names." > "/dev/stderr"
          exit 1
        }
      }
    ' lib/network.sh
  awk '
      /app\.cyberstrikeai\.error\.domain_invalid/ { saw_csai=1 }
      /app\.sub2api\.error\.domain_invalid/ { saw_sub2api=1 }
      /app\.vaultwarden\.error\.domain_invalid/ { saw_vw=1 }
      /app\.blog\.error\.keep_days_invalid/ { saw_blog_keep_days=1 }
      END {
        if (!(saw_csai && saw_sub2api && saw_vw && saw_blog_keep_days)) {
          print "Nginx domain and Blog retention validation errors must be localized." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/cyberstrikeai.sh apps/sub2api.sh apps/vaultwarden.sh apps/blog.sh
  awk '
      /_validate_config_values\(\)/ { in_func=1; saw_domain=0; next }
      in_func && /app_validate_domain "CSAI_DOMAIN"/ { saw_domain=1 }
      in_func && /^}/ {
        if (!saw_domain) {
          printf "%s CyberStrikeAI must validate CSAI_DOMAIN via _validate_config_values\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
  awk '
      /_validate_config_values\(\)/ { in_func=1; saw_domain=0; next }
      in_func && /app_validate_domain "SUB2API_DOMAIN"/ { saw_domain=1 }
      in_func && /^}/ {
        if (!saw_domain) {
          printf "%s Sub2API must validate SUB2API_DOMAIN via _validate_config_values\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
  awk '
      /_validate_config_values\(\)/ { in_func=1; saw_domain=0; next }
      in_func && /is_valid_dns_name "\$VW_DOMAIN"/ { saw_domain=1 }
      in_func && /^}/ {
        if (!saw_domain) {
          printf "%s Vaultwarden must validate VW_DOMAIN via _validate_config_values\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
      /prompt "\$\(t app\.vaultwarden\.prompt\.domain\)"/ { in_prompt=1; next }
      in_prompt && /if ! is_valid_dns_name "\$_input"; then/ { saw_prompt=1 }
      in_prompt && /VW_DOMAIN="\$_input"/ {
        if (!saw_prompt) {
          printf "%s Vaultwarden domain wizard must use shared DNS validation\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_prompt=0
      }
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
  awk '
      /_validate_config_values\(\)/ { in_func=1; saw_domain=0; saw_bool=0; saw_theme_url=0; saw_site_url=0; saw_repo=0; saw_ref=0; saw_keep_days=0; next }
      in_func && /app_validate_domain "BLOG_DOMAIN"/ { saw_domain=1 }
      in_func && /app_validate_bool "ENABLE_CMS"/ { saw_bool=1 }
      in_func && /app_validate_https_url "THEME_REPO"/ { saw_theme_url=1 }
      in_func && /app_validate_http_url "CMS_SITE_URL"/ { saw_site_url=1 }
      in_func && /app_validate_github_repo "CMS_REPO"/ { saw_repo=1 }
      in_func && /app_validate_git_ref "CMS_BRANCH"/ { saw_ref=1 }
      in_func && /app\.blog\.error\.keep_days_invalid/ { saw_keep_days=1 }
      in_func && /^}/ {
        if (!(saw_domain && saw_bool && saw_theme_url && saw_site_url && saw_repo && saw_ref && saw_keep_days)) {
          printf "%s Blog must validate domain, CMS settings, and backup retention config values\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_blog.sh dist/install_blog.sh
}

check_config_value_validators() {
  "$BASH_BIN" -c '
    source lib/core.sh

    app_validate_domain DOMAIN api.example.com
    app_validate_systemd_name SERVICE_NAME new-api
    app_validate_system_name SERVICE_USER newapi
    app_validate_github_repo GITHUB_REPO QuantumNous/new-api
    app_validate_git_ref GITHUB_BRANCH release/v1.2.3
    app_validate_db_identifier PG_DB sub2api_db
    app_validate_http_url CMS_SITE_URL http://localhost:1313/admin/
    app_validate_https_url THEME_REPO https://github.com/CaiJimmy/hugo-theme-stack.git
    app_validate_goproxy GOPROXY "https://goproxy.cn,direct"
    app_validate_goproxy GOPROXY "https://proxy.example.com|direct"
    app_validate_image_repo VW_IMAGE_REPO vaultwarden/server
    app_validate_image_repo VW_IMAGE_REPO ghcr.io/dani-garcia/vaultwarden
    app_validate_image_repo VW_IMAGE_REPO registry.example.com:5000/team/vaultwarden
    app_validate_image_tag VW_IMAGE_TAG 1.36.0-alpine
    app_validate_sha256 EXTRACT_TOOL_SHA256 a58f4995f568d66d9908649d4df7fc8c36f72096ca5e01f4c2c4291285125685
    app_validate_email CERTBOT_EMAIL admin@example.com
    app_validate_release_version WEB_VAULT_VER 2024.6.2

    validator_must_reject() {
      local label="$1"
      shift
      if ( "$@" ) >/dev/null 2>&1; then
        echo "Validator unexpectedly accepted invalid ${label}." >&2
        exit 1
      fi
    }

    validator_must_reject systemd-name app_validate_systemd_name SERVICE_NAME "../new-api"
    validator_must_reject domain app_validate_domain DOMAIN "api example.com"
    validator_must_reject system-name app_validate_system_name SERVICE_USER "new api"
    validator_must_reject github-repo app_validate_github_repo GITHUB_REPO "owner/repo;rm"
    validator_must_reject git-ref app_validate_git_ref GITHUB_BRANCH "feature/../main"
    validator_must_reject db-identifier app_validate_db_identifier PG_DB "sub2api-db"
    validator_must_reject http-url app_validate_http_url CMS_SITE_URL "https://example.com/a path"
    validator_must_reject https-url app_validate_https_url THEME_REPO "git://github.com/owner/repo.git"
    validator_must_reject goproxy app_validate_goproxy GOPROXY "https://proxy.example.com,;rm"
    validator_must_reject image-repo-tag app_validate_image_repo VW_IMAGE_REPO "vaultwarden/server:latest"
    validator_must_reject image-repo-digest app_validate_image_repo VW_IMAGE_REPO "vaultwarden/server@sha256:abc"
    validator_must_reject image-repo-metachar app_validate_image_repo VW_IMAGE_REPO "vaultwarden/server;rm"
    validator_must_reject image-tag app_validate_image_tag VW_IMAGE_TAG "latest/amd64"
    validator_must_reject sha256 app_validate_sha256 EXTRACT_TOOL_SHA256 abc
    validator_must_reject email app_validate_email CERTBOT_EMAIL "admin@example.com;rm"
    validator_must_reject email-domain app_validate_email CERTBOT_EMAIL "admin@example"
    validator_must_reject release-version app_validate_release_version WEB_VAULT_VER "2024.6/evil"
  '

  local checks=(
    'impl/install_newapi.sh|app_validate_systemd_name "SERVICE_NAME" "$SERVICE_NAME"'
    'impl/install_newapi.sh|app_validate_domain "DOMAIN" "$DOMAIN"'
    'impl/install_newapi.sh|app_validate_system_name "SERVICE_USER" "$SERVICE_USER"'
    'impl/install_newapi.sh|app_validate_github_repo "GITHUB_REPO" "$GITHUB_REPO"'
    'impl/install_sub2api.sh|app_validate_db_identifier "PG_USER" "$PG_USER"'
    'impl/install_sub2api.sh|app_validate_db_identifier "PG_DB" "$PG_DB"'
    'impl/install_cyberstrikeai.sh|app_validate_git_ref "GITHUB_BRANCH" "$GITHUB_BRANCH"'
    'impl/install_cyberstrikeai.sh|app_validate_http_url "PIP_INDEX_URL" "$PIP_INDEX_URL"'
    'impl/install_cyberstrikeai.sh|app_validate_goproxy "GOPROXY" "$GOPROXY"'
    'impl/install_tickflow.sh|app_validate_git_ref "TICKFLOW_BRANCH" "$TICKFLOW_BRANCH"'
    'impl/install_vaultwarden.sh|app_validate_system_name "VW_USER" "$VW_USER"'
    'impl/install_vaultwarden.sh|app_validate_email "CERTBOT_EMAIL" "$CERTBOT_EMAIL"'
    'impl/install_vaultwarden.sh|app_validate_image_repo "VW_IMAGE_REPO" "$VW_IMAGE_REPO"'
    'impl/install_vaultwarden.sh|app_validate_image_tag "VW_IMAGE_TAG" "$VW_IMAGE_TAG"'
    'impl/install_vaultwarden.sh|app_validate_git_ref "EXTRACT_TOOL_COMMIT" "$EXTRACT_TOOL_COMMIT"'
    'impl/install_vaultwarden.sh|app_validate_sha256 "EXTRACT_TOOL_SHA256" "$EXTRACT_TOOL_SHA256"'
    'impl/install_vaultwarden.sh|app_validate_release_version "WEB_VAULT_VER" "$WEB_VAULT_VER"'
    'impl/install_blog.sh|app_validate_https_url "THEME_REPO" "$THEME_REPO"'
    'impl/install_blog.sh|app_validate_http_url "CMS_SITE_URL" "$CMS_SITE_URL"'
  )
  local check file pattern
  for check in "${checks[@]}"; do
    file="${check%%|*}"
    pattern="${check#*|}"
    if ! grep -Fq "$pattern" "$file"; then
      echo "${file} must validate config value with: ${pattern}" >&2
      return 1
    fi
  done
}

check_vaultwarden_config_values_are_validated() {
  awk '
      /app\.vaultwarden\.error\.port_invalid/ { saw_port=1 }
      /app\.vaultwarden\.error\.bool_invalid/ { saw_bool=1 }
      /true or false/ { saw_guidance=1 }
      END {
        if (!(saw_port && saw_bool && saw_guidance)) {
          print "Vaultwarden must provide actionable invalid port and boolean config errors." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/vaultwarden.sh
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
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
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
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
}

check_status_port_matches_are_bounded() {
  if grep -R -nF 'grep ":${PORT}"' \
      impl/install_newapi.sh impl/install_sub2api.sh dist/install_newapi.sh dist/install_sub2api.sh 2>/dev/null; then
    echo "API port owner detection must not use substring port matches." >&2
    return 1
  fi
  if grep -R -nF 'grep "${PORT}"' \
      impl/install_newapi.sh impl/install_sub2api.sh dist/install_newapi.sh dist/install_sub2api.sh 2>/dev/null; then
    echo "API firewall status checks must not use substring port matches." >&2
    return 1
  fi
  if grep -R -nF 'grep ":${VW_PORT}"' \
      impl/install_vaultwarden.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "Vaultwarden port owner detection must not use substring port matches." >&2
    return 1
  fi
  awk '
      index($0, "ss -ltn \"( sport = :$port )\"") { saw_listen=1 }
      index($0, "ss -ltnp \"( sport = :$port )\"") { saw_owner=1 }
      /lsof -iTCP:"\$port" -sTCP:LISTEN -Pn/ { saw_lsof=1 }
      END {
        if (!(saw_listen && saw_owner && saw_lsof)) {
          printf "%s shared port conflict helpers must use bounded port matches for listeners and owners\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' lib/network.sh dist/install_newapi.sh dist/install_sub2api.sh dist/install_vaultwarden.sh
  awk '
      /app_check_port_conflict "\$PORT"/ { saw_owner++ }
      /grep -E "\(\^\|\[\[:space:\]\]\)\$\{PORT\}\/tcp\(\[\[:space:\]\]\|\$\)"/ { saw_ufw++ }
      END {
        if (!(saw_owner >= 1 && saw_ufw >= 1)) {
          printf "%s API checks must use shared bounded PORT conflict detection and bounded UFW rules\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh dist/install_newapi.sh dist/install_sub2api.sh
  awk '
      /app_check_port_conflict "\$VW_PORT"/ { saw_owner++ }
      END {
        if (saw_owner < 2) {
          printf "%s Vaultwarden checks must use shared bounded VW_PORT conflict detection\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
}

check_go_tarball_failures_cleanup() {
  if grep -R -n 'tar -C /usr/local -xzf "$tmp"$' impl dist 2>/dev/null; then
    echo "Go tarball extraction failures must remove the downloaded temporary archive." >&2
    return 1
  fi
  if grep -R -n 'rm -rf /usr/local/go' impl dist 2>/dev/null; then
    echo "Do not remove the existing Go toolchain before the replacement archive is extracted." >&2
    return 1
  fi
  if grep -R -n 'mv "$old_go_backup" /usr/local/go 2>/dev/null || true' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "CyberStrikeAI Go toolchain rollback must validate restoring the previous /usr/local/go." >&2
    return 1
  fi
  if grep -R -nE '^[[:space:]]*ln -sf /usr/local/go/bin/(go|gofmt) /usr/local/bin/(go|gofmt)$' \
      impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "CyberStrikeAI Go tool symlinks must be staged before replacement." >&2
    return 1
  fi
  awk '
      /if ! tmp=\$\(mktemp\); then/ { saw_download_tmp=1 }
      /if ! extract_dir=\$\(mktemp -d \/usr\/local\/go\.extract\.XXXXXX\); then/ { saw_extract_tmp=1 }
      /if ! old_go_backup=\$\(mktemp -d \/usr\/local\/go\.previous\.XXXXXX\); then/ { saw_backup_tmp=1 }
      /if ! rmdir "\$old_go_backup"; then/ { saw_backup_rmdir=1 }
      /error "\$\(t app\.cyberstrikeai\.error\.(go_query|go_extract|go_failed)\)"/ { saw_tmp_error=1 }
      /restore_old_go_toolchain\(\)/ { in_func=1; saw_exists=0; saw_absent=0; saw_mv=0; next }
      in_func && /\[\[ -n "\$old_go_backup" && -e "\$old_go_backup" \]\]/ { saw_exists=1 }
      in_func && /\[\[ ! -e \/usr\/local\/go \]\]/ { saw_absent=1 }
      in_func && /mv "\$old_go_backup" \/usr\/local\/go/ { saw_mv=1 }
      in_func && /^}/ {
        if (!(saw_exists && saw_absent && saw_mv)) {
          printf "%s Go toolchain rollback helper must validate backup existence, target absence, and restore move\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
      END {
        if (!(saw_download_tmp && saw_extract_tmp && saw_backup_tmp && saw_backup_rmdir && saw_tmp_error)) {
          print "CyberStrikeAI Go installation must report download, extract, and backup temp path preparation failures." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
  awk '
      /write_tool_symlink\(\)/ { in_func=1; saw_atomic=0; saw_error=0; next }
      in_func && /atomic_symlink "\$target" "\$link_path"/ { saw_atomic=1 }
      in_func && /error "\$\(t app\.cyberstrikeai\.error\.go_failed\)"/ { saw_error=1 }
      in_func && /^}/ {
        if (!(saw_atomic && saw_error)) {
          printf "%s Go tool symlink helper must use atomic_symlink and report failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_go_version_parse_failures_are_explicit() {
  awk '
      /version=\$\(printf .*\| grep -oE .*go\[0-9\].*\| head -1 \| sed .* \|\| true\)/ { saw_safe_parse=1 }
      /\[\[ -n "\$version" \]\] \|\| error "\$\(t app\.cyberstrikeai\.error\.go_parse\)"/ { saw_parse_error=1 }
      END {
        if (!(saw_safe_parse && saw_parse_error)) {
          printf "%s CyberStrikeAI Go version parsing must allow empty parse results to reach the explicit go_parse error under pipefail\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_go_restore_failures_are_reported() {
  if grep -R -n 'warn "\$\(t app\.cyberstrikeai\.error\.go_failed\)"' \
      impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "CyberStrikeAI Go restore failures must not reuse the generic install failure message as a warning." >&2
    return 1
  fi
  awk '
      /app\.cyberstrikeai\.warn\.go_restore_failed/ { saw_warn_key=1 }
      /if ! mv "\$extract_dir\/go" \/usr\/local\/go; then/ { in_block=1; saw_restore_if=0; saw_warn=0; next }
      in_block && /if ! restore_old_go_toolchain "\$old_go_backup"; then/ { saw_restore_if=1 }
      in_block && /warn "\$\(t app\.cyberstrikeai\.warn\.go_restore_failed\)"/ { saw_warn=1 }
      in_block && /error "\$\(t app\.cyberstrikeai\.error\.go_failed\)"/ {
        if (!(saw_warn_key && saw_restore_if && saw_warn)) {
          printf "%s CyberStrikeAI must warn explicitly when restoring the previous Go toolchain fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' apps/cyberstrikeai.sh impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_pip_upgrade_failures_are_reported() {
  if grep -R -n 'python -m pip install --index-url "\$PIP_INDEX_URL" --upgrade pip >/dev/null 2>&1 || true' \
      impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "CyberStrikeAI pip upgrade failures must not be silently ignored." >&2
    return 1
  fi
  awk '
      /app\.cyberstrikeai\.warn\.pip_upgrade/ { saw_warn_key=1 }
      /step "\$\(t app\.cyberstrikeai\.step\.python_env\)"/ { in_block=1; saw_pip_if=0; saw_warn=0; next }
      in_block && /if ! python -m pip install --index-url "\$PIP_INDEX_URL" --upgrade pip >\/dev\/null 2>&1; then/ { saw_pip_if=1 }
      in_block && /warn "\$\(t app\.cyberstrikeai\.warn\.pip_upgrade\)"/ { saw_warn=1 }
      in_block && /if \[\[ -f requirements\.txt \]\]; then/ {
        if (!(saw_warn_key && saw_pip_if && saw_warn)) {
          printf "%s CyberStrikeAI must warn explicitly when virtualenv pip upgrade fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' apps/cyberstrikeai.sh impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_python_env_failures_are_reported() {
  awk '
      /app\.cyberstrikeai\.error\.python_venv/ { saw_venv_key=1 }
      /python3-venv/ { saw_venv_guidance=1 }
      /app\.cyberstrikeai\.error\.python_activate/ { saw_activate_key=1 }
      /Recreate it and retry/ { saw_activate_guidance=1 }
      END {
        if (!(saw_venv_key && saw_venv_guidance && saw_activate_key && saw_activate_guidance)) {
          print "CyberStrikeAI Python environment failures must provide actionable setup guidance." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/cyberstrikeai.sh
  awk '
      /step "\$\(t app\.cyberstrikeai\.step\.python_env\)"/ { in_block=1; saw_venv_if=0; saw_venv_error=0; saw_activate_if=0; saw_activate_error=0; next }
      in_block && /if ! python3 -m venv "\$VENV_DIR"; then/ { saw_venv_if=1 }
      in_block && /error "\$\(t app\.cyberstrikeai\.error\.python_venv "\$VENV_DIR"\)"/ { saw_venv_error=1 }
      in_block && /if ! source "\$VENV_DIR\/bin\/activate"; then/ { saw_activate_if=1 }
      in_block && /error "\$\(t app\.cyberstrikeai\.error\.python_activate "\$VENV_DIR"\)"/ { saw_activate_error=1 }
      in_block && /if ! python -m pip install --index-url "\$PIP_INDEX_URL" --upgrade pip >\/dev\/null 2>&1; then/ {
        if (!(saw_venv_if && saw_venv_error && saw_activate_if && saw_activate_error)) {
          printf "%s CyberStrikeAI Python environment setup must fail explicitly when venv creation or activation fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_repo_go_install_failures_are_reported() {
  if grep -R -n 'apt-get install -y -qq golang-go || true' \
      impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "CyberStrikeAI repository Go installation failures must not be silently ignored." >&2
    return 1
  fi
  awk '
      /app\.cyberstrikeai\.warn\.go_repo_install_failed/ { saw_warn_key=1 }
      /step "\$\(t app\.cyberstrikeai\.step\.install_go\)"/ { in_block=1; saw_install_if=0; saw_warn=0; next }
      in_block && /if ! apt-get install -y -qq golang-go; then/ { saw_install_if=1 }
      in_block && /warn "\$\(t app\.cyberstrikeai\.warn\.go_repo_install_failed\)"/ { saw_warn=1 }
      in_block && /if command -v go >\/dev\/null 2>&1; then/ {
        if (!(saw_warn_key && saw_install_if && saw_warn)) {
          printf "%s CyberStrikeAI must warn when apt-based Go installation fails before falling back to the official toolchain\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' apps/cyberstrikeai.sh impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_vaultwarden_apt_update_failures_are_reported() {
  if grep -R -n 'apt-get update -qq[[:space:]\\]*\\$' \
      impl/install_vaultwarden.sh dist/install_vaultwarden.sh 2>/dev/null | grep '\|\| warn'; then
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
    ' apps/vaultwarden.sh impl/install_vaultwarden.sh dist/install_vaultwarden.sh
}

check_vaultwarden_workdir_cleanup_traps_are_nonfatal() {
  if grep -R -nE '\[\[ -d "\$\{WORK_DIR:-\}" \]\] && rm -rf "\$WORK_DIR"' \
      impl/install_vaultwarden.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "Vaultwarden WORK_DIR cleanup traps must not return failure when the directory is already gone." >&2
    return 1
  fi
  local file
  for file in impl/install_vaultwarden.sh dist/install_vaultwarden.sh; do
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

check_optional_directory_cleanup_is_nonfatal() {
  if grep -R -nE '\[\[ (-n "\$old_go_backup"|-d "\$_wv_install_bak") \]\] && rm -rf' \
      impl/install_cyberstrikeai.sh impl/install_vaultwarden.sh \
      dist/install_cyberstrikeai.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "Optional directory cleanup must use explicit if branches so absent paths do not trip set -e." >&2
    return 1
  fi
}

check_blog_dependency_failures_are_reported() {
  if grep -R -nE '^[[:space:]]*apt-get update -qq$|^[[:space:]]*apt-get install -y -qq curl wget git nginx ca-certificates$' \
      impl/install_blog.sh dist/install_blog.sh 2>/dev/null; then
    echo "Blog dependency installation must use explicit conditionals with actionable errors." >&2
    return 1
  fi
  awk '
      /app\.blog\.error\.apt_update/ { saw_update_key=1 }
      /\/var\/log\/apt\/\*/ { saw_update_guidance=1 }
      /app\.blog\.error\.deps_install/ { saw_install_key=1 }
      /apt-get install -y curl wget git nginx ca-certificates/ { saw_install_guidance=1 }
      END {
        if (!(saw_update_key && saw_update_guidance && saw_install_key && saw_install_guidance)) {
          print "Blog dependency failures must tell users how to inspect apt logs and retry package installation." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/blog.sh
  awk '
      /step "\$\(t app\.blog\.step_install_deps\)"/ { in_block=1; saw_update_if=0; saw_update_error=0; saw_install_if=0; saw_install_error=0; next }
      in_block && /if ! apt-get update -qq; then/ { saw_update_if=1 }
      in_block && /error "\$\(t app\.blog\.error\.apt_update\)"/ { saw_update_error=1 }
      in_block && /if ! apt-get install -y -qq curl wget git nginx ca-certificates; then/ { saw_install_if=1 }
      in_block && /error "\$\(t app\.blog\.error\.deps_install\)"/ { saw_install_error=1 }
      in_block && /success "\$\(t app\.blog\.deps_installed\)"/ {
        if (!(saw_update_if && saw_update_error && saw_install_if && saw_install_error)) {
          printf "%s Blog dependency installation must fail through explicit conditionals with actionable errors\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_blog.sh dist/install_blog.sh
}

check_blog_hugo_install_failures_are_actionable() {
  awk '
      /app\.blog\.error\.hugo_install/ { saw_key=1 }
      /apt-get install -f/ { saw_fix_deps=1 }
      /dpkg -i <downloaded-hugo\.deb>/ { saw_retry=1 }
      END {
        if (!(saw_key && saw_fix_deps && saw_retry)) {
          print "Blog Hugo package install failures must explain how to repair dependencies and retry the dpkg install." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/blog.sh
  awk '
      /if ! HUGO_DEB="\$\(mktemp \/tmp\/hugo\.XXXXXX\.deb\)"; then/ { saw_tmp_if=1 }
      /error "\$\(t app\.blog\.error\.hugo_download\)"/ { saw_tmp_error=1 }
      /if \[\[ ! -s "\$HUGO_DEB" \]\]; then/ { saw_empty_if=1 }
      saw_empty_if && /rm -f "\$HUGO_DEB"/ { saw_empty_cleanup=1 }
      /if ! dpkg -i "\$HUGO_DEB"; then/ { in_block=1; saw_error=0; next }
      in_block && /error "\$\(t app\.blog\.error\.hugo_install\)"/ { saw_error=1 }
      in_block && /rm -f "\$HUGO_DEB"/ { saw_cleanup=1 }
      in_block && /^fi$/ {
        if (!(saw_error && saw_cleanup)) {
          printf "%s Blog Hugo package install failure must clean up and report an actionable error\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
      END {
        if (!(saw_tmp_if && saw_tmp_error && saw_empty_if && saw_empty_cleanup)) {
          print "Blog Hugo package download must report temporary file creation and empty download failures." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_blog.sh dist/install_blog.sh
}

check_blog_site_setup_failures_are_explicit() {
  awk '
      /app\.blog\.error\.site_parent_dir/ { saw_parent_key=1 }
      /site parent directory/ { saw_parent_guidance=1 }
      /app\.blog\.error\.site_create/ { saw_site_create_key=1 }
      /hugo new site %s --format toml/ { saw_site_create_guidance=1 }
      /app\.blog\.error\.git_init/ { saw_git_init_key=1 }
      /git -C %s init -q/ { saw_git_init_guidance=1 }
      /app\.blog\.error\.git_config/ { saw_git_config_key=1 }
      /app\.blog\.error\.theme_install/ { saw_theme_key=1 }
      /partial theme directory/ { saw_theme_guidance=1 }
      /app\.blog\.error\.content_dirs/ { saw_content_key=1 }
      /content directories under %s/ { saw_content_guidance=1 }
      /app\.blog\.error\.cms_admin_dir/ { saw_cms_key=1 }
      /CMS admin directory/ { saw_cms_guidance=1 }
      /app\.blog\.error\.public_dir/ { saw_public_key=1 }
      /build output directory/ { saw_public_guidance=1 }
      /app\.blog\.error\.site_access/ { saw_access_key=1 }
      /rerun the initialization step/ { saw_access_guidance=1 }
      /app\.blog\.error\.git_stage/ { saw_git_stage_key=1 }
      /app\.blog\.error\.git_diff/ { saw_git_diff_key=1 }
      /app\.blog\.error\.git_commit/ { saw_git_commit_key=1 }
      /app\.blog\.error\.nginx_root_parent/ { saw_nginx_parent_key=1 }
      /site root parent directory/ { saw_nginx_parent_guidance=1 }
      END {
        if (!(saw_parent_key && saw_parent_guidance && saw_site_create_key && saw_site_create_guidance && saw_git_init_key && saw_git_init_guidance && saw_git_config_key && saw_theme_key && saw_theme_guidance && saw_content_key && saw_content_guidance && saw_cms_key && saw_cms_guidance && saw_public_key && saw_public_guidance && saw_access_key && saw_access_guidance && saw_git_stage_key && saw_git_diff_key && saw_git_commit_key && saw_nginx_parent_key && saw_nginx_parent_guidance)) {
          print "Blog site setup failures must provide actionable initialization, Git, theme, content, CMS, build, and Nginx root guidance." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/blog.sh
  awk '
      /step "\$\(t app\.blog\.step_init_site\)"/ { in_init=1; saw_parent_if=0; saw_parent_error=0; saw_hugo_if=0; saw_hugo_error=0; saw_git_init_if=0; saw_git_init_error=0; saw_git_cfg_if=0; saw_git_cfg_error=0; next }
      in_init && /if ! mkdir -p "\$\(dirname "\$SITE_DIR"\)"; then/ { saw_parent_if=1 }
      in_init && /error "\$\(t app\.blog\.error\.site_parent_dir "\$SITE_DIR"\)"/ { saw_parent_error=1 }
      in_init && /if ! hugo new site "\$SITE_DIR" --format toml; then/ { saw_hugo_if=1 }
      in_init && /error "\$\(t app\.blog\.error\.site_create "\$SITE_DIR" "\$SITE_DIR"\)"/ { saw_hugo_error=1 }
      in_init && /if ! git -C "\$SITE_DIR" init -q; then/ { saw_git_init_if=1 }
      in_init && /error "\$\(t app\.blog\.error\.git_init "\$SITE_DIR" "\$SITE_DIR"\)"/ { saw_git_init_error=1 }
      in_init && /if ! git -C "\$SITE_DIR" config user.email "blog@localhost" \\/ { saw_git_cfg_if=1 }
      in_init && /error "\$\(t app\.blog\.error\.git_config "\$SITE_DIR"\)"/ { saw_git_cfg_error=1 }
      in_init && /success "\$\(t app\.blog\.git_initialized\)"/ {
        if (!(saw_parent_if && saw_parent_error && saw_hugo_if && saw_hugo_error && saw_git_init_if && saw_git_init_error && saw_git_cfg_if && saw_git_cfg_error)) {
          printf "%s Blog site initialization must fail explicitly when parent-dir creation, hugo new site, git init, or git config fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_init=0
      }
      /step "\$\(t app\.blog\.step_theme\)"/ { in_theme=1; saw_theme_clone_if=0; saw_theme_error=0; next }
      in_theme && /if ! git -C "\$SITE_DIR" submodule add --depth 1 "\$THEME_REPO" "themes\/\$\{THEME_NAME\}" 2>\/dev\/null; then/ { saw_theme_clone_if=1 }
      in_theme && /error "\$\(t app\.blog\.error\.theme_install "\$THEME_DIR"\)"/ { saw_theme_error=1 }
      in_theme && /success "\$\(t app\.blog\.theme_installed\)"/ {
        if (!(saw_theme_clone_if && saw_theme_error)) {
          printf "%s Blog theme install must fail explicitly when both submodule and clone paths fail\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_theme=0
      }
      /step "\$\(t app\.blog\.step_content\)"/ { in_content=1; saw_content_mkdir_if=0; saw_content_error=0; next }
      in_content && /if ! mkdir -p \\/ { saw_content_mkdir_if=1 }
      in_content && /error "\$\(t app\.blog\.error\.content_dirs "\$SITE_DIR"\)"/ { saw_content_error=1 }
      in_content && /if \[\[ ! -f "\$\{SITE_DIR\}\/content\/post\/hello-world\/index\.md" \]\]; then/ {
        if (!(saw_content_mkdir_if && saw_content_error)) {
          printf "%s Blog content setup must fail explicitly when sample content directories cannot be created\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_content=0
      }
      /step "\$\(t app\.blog\.step_cms\)"/ { in_cms=1; saw_cms_if=0; saw_cms_error=0; next }
      in_cms && /if ! mkdir -p "\$CMS_ADMIN_DIR"; then/ { saw_cms_if=1 }
      in_cms && /error "\$\(t app\.blog\.error\.cms_admin_dir "\$CMS_ADMIN_DIR"\)"/ { saw_cms_error=1 }
      in_cms && /_write_blog_file "\$\{CMS_ADMIN_DIR\}\/index\.html"/ {
        if (!(saw_cms_if && saw_cms_error)) {
          printf "%s Blog CMS setup must fail explicitly when the admin directory cannot be created\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_cms=0
      }
      /step "\$\(t app\.blog\.step_build\)"/ { in_build=1; saw_public_if=0; saw_public_error=0; saw_cd_if=0; saw_cd_error=0; saw_git_add_if=0; saw_git_add_error=0; saw_git_diff_if=0; saw_git_diff_error=0; saw_git_commit_if=0; saw_git_commit_error=0; next }
      in_build && /if ! mkdir -p "\$PUBLIC_DIR"; then/ { saw_public_if=1 }
      in_build && /error "\$\(t app\.blog\.error\.public_dir "\$PUBLIC_DIR"\)"/ { saw_public_error=1 }
      in_build && /if ! cd "\$SITE_DIR"; then/ { saw_cd_if=1 }
      in_build && /error "\$\(t app\.blog\.error\.site_access "\$SITE_DIR"\)"/ { saw_cd_error=1 }
      in_build && /if ! git add -A; then/ { saw_git_add_if=1 }
      in_build && /error "\$\(t app\.blog\.error\.git_stage "\$SITE_DIR"\)"/ { saw_git_add_error=1 }
      in_build && /if git diff --cached --quiet; then/ { saw_git_diff_if=1 }
      in_build && /error "\$\(t app\.blog\.error\.git_diff "\$SITE_DIR"\)"/ { saw_git_diff_error=1 }
      in_build && /if ! git commit -q -m "init: add site content"; then/ { saw_git_commit_if=1 }
      in_build && /error "\$\(t app\.blog\.error\.git_commit "\$SITE_DIR"\)"/ { saw_git_commit_error=1 }
      in_build && /info "\$\(t app\.blog\.git_committed\)"/ {
        if (!(saw_public_if && saw_public_error && saw_cd_if && saw_cd_error && saw_git_add_if && saw_git_add_error && saw_git_diff_if && saw_git_diff_error && saw_git_commit_if && saw_git_commit_error)) {
          printf "%s Blog build prep must fail explicitly when the public dir, site dir, git staging, staged-diff inspection, or commit fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_build=0
      }
      /step "\$\(t app\.blog\.step_nginx\)"/ { in_nginx=1; saw_nginx_parent_if=0; saw_nginx_parent_error=0; next }
      in_nginx && /if ! mkdir -p "\$NGINX_ROOT_PARENT"; then/ { saw_nginx_parent_if=1 }
      in_nginx && /error "\$\(t app\.blog\.error\.nginx_root_parent "\$NGINX_ROOT_PARENT"\)"/ { saw_nginx_parent_error=1 }
      in_nginx && /DEPLOY_TMP=\$\(mktemp -d "\$\{NGINX_ROOT_PARENT\}\/\.\$\{NGINX_ROOT_NAME\}\.new\.XXXXXX"\)/ {
        if (!(saw_nginx_parent_if && saw_nginx_parent_error)) {
          printf "%s Blog Nginx deployment prep must fail explicitly when the site-root parent directory cannot be created\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_nginx=0
      }
    ' impl/install_blog.sh dist/install_blog.sh
}

check_newapi_dependency_failures_are_reported() {
  if grep -R -nE '^[[:space:]]*apt-get update -qq$|^[[:space:]]*apt-get install -y -qq curl ca-certificates sqlite3$' \
      impl/install_newapi.sh dist/install_newapi.sh 2>/dev/null; then
    echo "NewAPI dependency installation must use explicit conditionals with actionable errors." >&2
    return 1
  fi
  awk '
      /app\.newapi\.error\.apt_update/ { saw_update_key=1 }
      /\/var\/log\/apt\/\*/ { saw_update_guidance=1 }
      /app\.newapi\.error\.deps_install/ { saw_install_key=1 }
      /apt-get install -y curl ca-certificates sqlite3/ { saw_install_guidance=1 }
      END {
        if (!(saw_update_key && saw_update_guidance && saw_install_key && saw_install_guidance)) {
          print "NewAPI dependency failures must tell users how to inspect apt logs and retry package installation." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/newapi.sh
  awk '
      /step "\$\(t app\.newapi\.step\.deps\)"/ { in_block=1; saw_update_if=0; saw_update_error=0; saw_install_if=0; saw_install_error=0; next }
      in_block && /if ! apt-get update -qq; then/ { saw_update_if=1 }
      in_block && /error "\$\(t app\.newapi\.error\.apt_update\)"/ { saw_update_error=1 }
      in_block && /if ! apt-get install -y -qq curl ca-certificates sqlite3; then/ { saw_install_if=1 }
      in_block && /error "\$\(t app\.newapi\.error\.deps_install\)"/ { saw_install_error=1 }
      in_block && /success "\$\(t app\.newapi\.success\.deps\)"/ {
        if (!(saw_update_if && saw_update_error && saw_install_if && saw_install_error)) {
          printf "%s NewAPI dependency installation must fail through explicit conditionals with actionable errors\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
}

check_newapi_runtime_dir_failures_are_explicit() {
  awk '
      /app\.newapi\.error\.user_create/ { saw_user_key=1 }
      /app\.newapi\.error\.dir_create/ { saw_dir_key=1 }
      /Check permissions for %s and %s, then retry/ { saw_dir_guidance=1 }
      /app\.newapi\.error\.dir_owner/ { saw_owner_key=1 }
      /Check filesystem permissions and retry/ { saw_owner_guidance=1 }
      END {
        if (!(saw_user_key && saw_dir_key && saw_dir_guidance && saw_owner_key && saw_owner_guidance)) {
          print "NewAPI runtime directory failures must provide actionable user, mkdir, and chown guidance." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/newapi.sh
  awk '
      /step "\$\(t app\.newapi\.step\.user_dirs\)"/ { in_dirs=1; saw_user_if=0; saw_user_error=0; saw_mkdir_if=0; saw_mkdir_error=0; saw_install_guard=0; saw_log_guard=0; saw_backup_guard=0; saw_chown_if=0; saw_chown_error=0; next }
      in_dirs && /if ! useradd -r -s \/usr\/sbin\/nologin -d "\$INSTALL_DIR" "\$SERVICE_USER"; then/ { saw_user_if=1 }
      in_dirs && /error "\$\(t app\.newapi\.error\.user_create "\$SERVICE_USER"\)"/ { saw_user_error=1 }
      in_dirs && /if ! mkdir -p "\$INSTALL_DIR" "\$DATA_DIR" "\$LOG_DIR" "\$BACKUP_DIR"; then/ { saw_mkdir_if=1 }
      in_dirs && /error "\$\(t app\.newapi\.error\.dir_create "\$INSTALL_DIR" "\$BACKUP_DIR"\)"/ { saw_mkdir_error=1 }
      in_dirs && /require_safe_path "INSTALL_DIR" "\$INSTALL_DIR"/ { saw_install_guard=1 }
      in_dirs && /require_safe_path "LOG_DIR" "\$LOG_DIR"/ { saw_log_guard=1 }
      in_dirs && /require_safe_path "BACKUP_DIR" "\$BACKUP_DIR"/ { saw_backup_guard=1 }
      in_dirs && /if ! chown -R "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$INSTALL_DIR" "\$LOG_DIR" "\$BACKUP_DIR"; then/ { saw_chown_if=1 }
      in_dirs && /error "\$\(t app\.newapi\.error\.dir_owner "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$INSTALL_DIR"\)"/ { saw_chown_error=1 }
      in_dirs && /success "\$\(t app\.newapi\.success\.dirs "\$INSTALL_DIR" "\$DATA_DIR" "\$LOG_DIR"\)"/ {
        if (!(saw_user_if && saw_user_error && saw_mkdir_if && saw_mkdir_error && saw_install_guard && saw_log_guard && saw_backup_guard && saw_chown_if && saw_chown_error)) {
          printf "%s NewAPI install must fail explicitly when user creation, directory creation, or directory ownership setup fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_dirs=0
      }
      /if \[\[ -n "\$OLD_BIN_BAK" \]\]; then/ { in_binary=1; saw_binary_chown_if=0; saw_binary_chown_error=0; next }
      in_binary && /if ! chown -R "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$INSTALL_DIR"; then/ { saw_binary_chown_if=1 }
      in_binary && /error "\$\(t app\.newapi\.error\.dir_owner "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$INSTALL_DIR"\)"/ { saw_binary_chown_error=1 }
      in_binary && /success "\$\(t app\.newapi\.success\.binary_installed "\$BIN_PATH"\)"/ {
        if (!(saw_binary_chown_if && saw_binary_chown_error)) {
          printf "%s NewAPI binary install must fail explicitly when ownership repair fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_binary=0
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
}

check_cyberstrikeai_dependency_failures_are_reported() {
  if grep -R -nE '^[[:space:]]*apt-get update -qq$' \
      impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "CyberStrikeAI dependency installation must use an explicit conditional for apt-get update." >&2
    return 1
  fi
  if grep -R -nE '^[[:space:]]*apt-get install -y -qq nginx$' \
      impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "CyberStrikeAI nginx installation must use an explicit conditional with an actionable error." >&2
    return 1
  fi
  awk '
      /app\.cyberstrikeai\.error\.apt_update/ { saw_update_key=1 }
      /\/var\/log\/apt\/\*/ { saw_update_guidance=1 }
      /app\.cyberstrikeai\.error\.deps_install/ { saw_install_key=1 }
      /apt-get install -y ca-certificates curl git build-essential python3 python3-venv python3-pip sqlite3 tar gzip openssl lsof/ { saw_install_guidance=1 }
      /app\.cyberstrikeai\.error\.nginx_deps_install/ { saw_nginx_key=1 }
      /apt-get install -y nginx/ { saw_nginx_guidance=1 }
      END {
        if (!(saw_update_key && saw_update_guidance && saw_install_key && saw_install_guidance && saw_nginx_key && saw_nginx_guidance)) {
          print "CyberStrikeAI dependency failures must tell users how to inspect apt logs and retry package installation." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/cyberstrikeai.sh
  awk '
      /step "\$\(t app\.cyberstrikeai\.step\.install_deps\)"/ { in_block=1; saw_update_if=0; saw_update_error=0; saw_install_if=0; saw_install_error=0; saw_nginx_if=0; saw_nginx_error=0; next }
      in_block && /if ! apt-get update -qq; then/ { saw_update_if=1 }
      in_block && /error "\$\(t app\.cyberstrikeai\.error\.apt_update\)"/ { saw_update_error=1 }
      in_block && /if ! apt-get install -y -qq \\/ { saw_install_if=1 }
      in_block && /error "\$\(t app\.cyberstrikeai\.error\.deps_install\)"/ { saw_install_error=1 }
      in_block && /if ! apt-get install -y -qq nginx; then/ { saw_nginx_if=1 }
      in_block && /error "\$\(t app\.cyberstrikeai\.error\.nginx_deps_install\)"/ { saw_nginx_error=1 }
      in_block && /success "\$\(t app\.cyberstrikeai\.success\.deps\)"/ {
        if (!(saw_update_if && saw_update_error && saw_install_if && saw_install_error && saw_nginx_if && saw_nginx_error)) {
          printf "%s CyberStrikeAI dependency installation must fail through explicit conditionals with actionable errors\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_sub2api_apt_failures_are_reported() {
  if grep -R -nE '^[[:space:]]*apt-get update -qq$' \
      impl/install_sub2api.sh dist/install_sub2api.sh 2>/dev/null; then
    echo "Sub2API apt-get update paths must use explicit conditionals with actionable errors." >&2
    return 1
  fi
  awk '
      /app\.sub2api\.error\.apt_update/ { saw_base_update_key=1 }
      /app\.sub2api\.error\.base_deps_install/ { saw_base_install_key=1 }
      /app\.sub2api\.error\.postgres_apt_update/ { saw_pg_update_key=1 }
      /app\.sub2api\.error\.postgres_apt_install/ { saw_pg_install_key=1 }
      /app\.sub2api\.error\.redis_apt_update/ { saw_redis_update_key=1 }
      /app\.sub2api\.error\.redis_apt_install/ { saw_redis_install_key=1 }
      /\/var\/log\/apt\/\*/ { saw_apt_guidance=1 }
      /apt-get install -y curl ca-certificates gnupg lsb-release/ { saw_base_install_guidance=1 }
      /apt-get install -y postgresql-15 postgresql-client-15/ { saw_pg_install_guidance=1 }
      /apt-get install -y redis/ { saw_redis_install_guidance=1 }
      /\/etc\/apt\/sources\.list\.d\/pgdg\.list/ { saw_pg_source_guidance=1 }
      /\/etc\/apt\/sources\.list\.d\/redis\.list/ { saw_redis_source_guidance=1 }
      END {
        if (!(saw_base_update_key && saw_base_install_key && saw_pg_update_key && saw_pg_install_key && saw_redis_update_key && saw_redis_install_key && saw_apt_guidance && saw_base_install_guidance && saw_pg_install_guidance && saw_redis_install_guidance && saw_pg_source_guidance && saw_redis_source_guidance)) {
          print "Sub2API apt failures must tell users how to inspect apt logs, repair repository files, and retry package installation." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/sub2api.sh
  awk '
      /_install_base_deps\(\)/ { in_base=1; saw_update_if=0; saw_update_error=0; saw_install_if=0; saw_install_error=0; next }
      in_base && /if ! apt-get update -qq; then/ { saw_update_if=1 }
      in_base && /error "\$\(t app\.sub2api\.error\.apt_update\)"/ { saw_update_error=1 }
      in_base && /if ! DEBIAN_FRONTEND=noninteractive apt-get install -y -qq \\/ { saw_install_if=1 }
      in_base && /error "\$\(t app\.sub2api\.error\.base_deps_install\)"/ { saw_install_error=1 }
      in_base && /success "\$\(t app\.sub2api\.success\.base_deps\)"/ {
        if (!(saw_update_if && saw_update_error && saw_install_if && saw_install_error)) {
          printf "%s Sub2API base dependency installation must fail through explicit conditionals with actionable errors\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_base=0
      }
      /_install_postgres\(\)/ { in_pg_func=1; next }
      /_install_redis\(\)/ { in_redis_func=1; next }
      in_pg_func && /if \[\[ "\$PKG_MANAGER" == "apt" \]\]; then/ { in_pg=1; in_pg_func=0; next }
      in_redis_func && /if \[\[ "\$PKG_MANAGER" == "apt" \]\]; then/ { in_redis=1; in_redis_func=0; next }
      in_pg && /if ! apt-get update -qq; then/ { saw_pg_update_if=1 }
      in_pg && /error "\$\(t app\.sub2api\.error\.postgres_apt_update\)"/ { saw_pg_update_error=1 }
      in_pg && /if ! DEBIAN_FRONTEND=noninteractive apt-get install -y postgresql-15 postgresql-client-15; then/ { saw_pg_install_if=1 }
      in_pg && /error "\$\(t app\.sub2api\.error\.postgres_apt_install\)"/ { saw_pg_install_error=1 }
      in_pg && /if ! systemctl enable postgresql 2>\/dev\/null; then/ {
        if (!(saw_pg_update_if && saw_pg_update_error && saw_pg_install_if && saw_pg_install_error)) {
          printf "%s Sub2API PostgreSQL apt installation must fail through explicit conditionals with actionable errors\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_pg=0
      }
      in_redis && /if ! apt-get update -qq; then/ { saw_redis_update_if=1 }
      in_redis && /error "\$\(t app\.sub2api\.error\.redis_apt_update\)"/ { saw_redis_update_error=1 }
      in_redis && /if ! DEBIAN_FRONTEND=noninteractive apt-get install -y redis; then/ { saw_redis_install_if=1 }
      in_redis && /error "\$\(t app\.sub2api\.error\.redis_apt_install\)"/ { saw_redis_install_error=1 }
      in_redis && /_ensure_redis_running \|\| error "\$\(t app\.sub2api\.error\.redis_start\)"/ {
        if (!(saw_redis_update_if && saw_redis_update_error && saw_redis_install_if && saw_redis_install_error)) {
          printf "%s Sub2API Redis apt installation must fail through explicit conditionals with actionable errors\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_redis=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_sub2api_rpm_dependency_failures_are_reported() {
  awk '
      /app\.sub2api\.error\.base_deps_install_pkg/ { saw_base_key=1 }
      /dnf or yum/ { saw_base_guidance=1 }
      /app\.sub2api\.error\.postgres_rpm_install/ { saw_pg_key=1 }
      /dnf install -y postgresql15-server postgresql15-contrib/ { saw_pg_dnf_guidance=1 }
      /yum install -y postgresql15-server postgresql15-contrib/ { saw_pg_yum_guidance=1 }
      /app\.sub2api\.error\.redis_pkg_install/ { saw_redis_key=1 }
      /dnf install -y redis/ { saw_redis_dnf_guidance=1 }
      /yum install -y redis/ { saw_redis_yum_guidance=1 }
      END {
        if (!(saw_base_key && saw_base_guidance && saw_pg_key && saw_pg_dnf_guidance && saw_pg_yum_guidance && saw_redis_key && saw_redis_dnf_guidance && saw_redis_yum_guidance)) {
          print "Sub2API RPM/dnf/yum failures must tell users how to retry package installation." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/sub2api.sh
  awk '
      /_install_base_deps\(\)/ { in_base=1; saw_dnf_base=0; saw_yum_base=0; next }
      in_base && /dnf install -y -q curl ca-certificates \|\| error "\$\(t app\.sub2api\.error\.base_deps_install_pkg\)"/ { saw_dnf_base=1 }
      in_base && /yum install -y -q curl ca-certificates \|\| error "\$\(t app\.sub2api\.error\.base_deps_install_pkg\)"/ { saw_yum_base=1 }
      in_base && /success "\$\(t app\.sub2api\.success\.base_deps\)"/ {
        if (!(saw_dnf_base && saw_yum_base)) {
          printf "%s Sub2API RPM base dependency installation must fail explicitly with actionable errors\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_base=0
      }
      /\[\[ "\$PKG_MANAGER" == "dnf" \|\| "\$PKG_MANAGER" == "yum" \]\]/ { in_pg=1; saw_dnf_pg=0; saw_yum_pg=0; next }
      in_pg && /dnf install -y postgresql15-server postgresql15-contrib \|\| error "\$\(t app\.sub2api\.error\.postgres_rpm_install\)"/ { saw_dnf_pg=1 }
      in_pg && /yum install -y postgresql15-server postgresql15-contrib \|\| error "\$\(t app\.sub2api\.error\.postgres_rpm_install\)"/ { saw_yum_pg=1 }
      in_pg && /success "\$\(t app\.sub2api\.success\.postgres15\)"/ {
        if (!(saw_dnf_pg && saw_yum_pg)) {
          printf "%s Sub2API PostgreSQL RPM package installation must fail explicitly with actionable errors\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_pg=0
      }
      /_install_redis\(\)/ { in_redis_func=1; next }
      in_redis_func && /elif \[\[ "\$PKG_MANAGER" == "dnf" \]\]; then/ { in_redis_dnf=1; in_redis_func=0; next }
      in_redis_dnf && /dnf install -y redis \|\| error "\$\(t app\.sub2api\.error\.redis_pkg_install\)"/ { saw_dnf_redis=1 }
      /elif \[\[ "\$PKG_MANAGER" == "yum" \]\]; then/ { if (in_redis_dnf) { in_redis_yum=1; in_redis_dnf=0; next } }
      in_redis_yum && /yum install -y redis \|\| error "\$\(t app\.sub2api\.error\.redis_pkg_install\)"/ { saw_yum_redis=1 }
      in_redis_yum && /success "\$\(t app\.sub2api\.success\.redis\)"/ {
        if (!(saw_dnf_redis && saw_yum_redis)) {
          printf "%s Sub2API Redis RPM package installation must fail explicitly with actionable errors\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_redis_yum=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_sub2api_runtime_dir_failures_are_explicit() {
  awk '
      /app\.sub2api\.error\.user_create/ { saw_user_key=1 }
      /app\.sub2api\.error\.dir_create/ { saw_dir_key=1 }
      /Check permissions for %s and %s, then retry/ { saw_dir_guidance=1 }
      /app\.sub2api\.error\.dir_owner/ { saw_owner_key=1 }
      /app\.sub2api\.error\.config_dir_mode/ { saw_mode_key=1 }
      /directory mode 750/ { saw_mode_guidance=1 }
      END {
        if (!(saw_user_key && saw_dir_key && saw_dir_guidance && saw_owner_key && saw_mode_key && saw_mode_guidance)) {
          print "Sub2API runtime directory failures must provide actionable user, mkdir, chown, and chmod guidance." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/sub2api.sh
  awk '
      /step "\$\(t app\.sub2api\.step\.user_dirs\)"/ { in_dirs=1; saw_user_if=0; saw_user_error=0; saw_mkdir_if=0; saw_mkdir_error=0; saw_install_guard=0; saw_log_guard=0; saw_config_guard=0; saw_chown_if=0; saw_chown_error=0; saw_chmod_if=0; saw_chmod_error=0; next }
      in_dirs && /if ! useradd -r -s \/usr\/sbin\/nologin -d "\$INSTALL_DIR" "\$SERVICE_USER"; then/ { saw_user_if=1 }
      in_dirs && /error "\$\(t app\.sub2api\.error\.user_create "\$SERVICE_USER"\)"/ { saw_user_error=1 }
      in_dirs && /if ! mkdir -p "\$INSTALL_DIR" "\$DATA_DIR" "\$LOG_DIR" "\$CONFIG_DIR" "\$BACKUP_DIR"; then/ { saw_mkdir_if=1 }
      in_dirs && /error "\$\(t app\.sub2api\.error\.dir_create "\$INSTALL_DIR" "\$BACKUP_DIR"\)"/ { saw_mkdir_error=1 }
      in_dirs && /require_safe_path "INSTALL_DIR" "\$INSTALL_DIR"/ { saw_install_guard=1 }
      in_dirs && /require_safe_path "LOG_DIR" "\$LOG_DIR"/ { saw_log_guard=1 }
      in_dirs && /require_safe_path "CONFIG_DIR" "\$CONFIG_DIR"/ { saw_config_guard=1 }
      in_dirs && /if ! chown -R "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$INSTALL_DIR" "\$LOG_DIR" "\$CONFIG_DIR"; then/ { saw_chown_if=1 }
      in_dirs && /error "\$\(t app\.sub2api\.error\.dir_owner "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$INSTALL_DIR"\)"/ { saw_chown_error=1 }
      in_dirs && /if ! chmod 750 "\$CONFIG_DIR"; then/ { saw_chmod_if=1 }
      in_dirs && /error "\$\(t app\.sub2api\.error\.config_dir_mode "\$CONFIG_DIR"\)"/ { saw_chmod_error=1 }
      in_dirs && /success "\$\(t app\.sub2api\.success\.dirs_created\)"/ {
        if (!(saw_user_if && saw_user_error && saw_mkdir_if && saw_mkdir_error && saw_install_guard && saw_log_guard && saw_config_guard && saw_chown_if && saw_chown_error && saw_chmod_if && saw_chmod_error)) {
          printf "%s Sub2API install must fail explicitly when user creation, directory creation, ownership setup, or config-dir chmod fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_dirs=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_backup_script_dir_failures_are_explicit() {
  awk '
      /_write_backup_script\(\)/ { in_newapi=1; saw_newapi_if=0; saw_newapi_error=0; next }
      in_newapi && /if ! mkdir -p "\$BACKUP_DIR"; then/ { saw_newapi_if=1 }
      in_newapi && /error "\$\(t app\.newapi\.error\.backup_dir_create "\$BACKUP_DIR"\)"/ { saw_newapi_error=1 }
      in_newapi && /local msg_start/ {
        if (!(saw_newapi_if && saw_newapi_error)) {
          printf "%s NewAPI backup-script generator must fail explicitly when the backup directory cannot be created\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_newapi=0
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
  awk '
      /_write_backup_script\(\)/ { in_sub2api=1; saw_sub2api_if=0; saw_sub2api_error=0; next }
      in_sub2api && /if ! mkdir -p "\$BACKUP_DIR"; then/ { saw_sub2api_if=1 }
      in_sub2api && /error "\$\(t app\.sub2api\.error\.backup_dir_create "\$BACKUP_DIR"\)"/ { saw_sub2api_error=1 }
      in_sub2api && /local msg_start/ {
        if (!(saw_sub2api_if && saw_sub2api_error)) {
          printf "%s Sub2API backup-script generator must fail explicitly when the backup directory cannot be created\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_sub2api=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
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
      in_nginx && /_write_nginx_config_file "\$NGINX_CONF"/ {
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
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
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
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
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
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
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
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
}

check_preupdate_backup_warnings_include_followup_guidance() {
  awk '
      /app\.newapi\.warn\.pre_backup_failed/ { saw_newapi=1 }
      /\/opt\/new-api-backups\/backup\.log/ { saw_newapi_log=1 }
      /\/usr\/local\/bin\/new-api-backup/ { saw_newapi_cmd=1 }
      /app\.sub2api\.warn\.pre_update_backup/ { saw_sub2api=1 }
      /\/opt\/sub2api-backups\/backup\.log/ { saw_sub2api_log=1 }
      /\/usr\/local\/bin\/sub2api-backup/ { saw_sub2api_cmd=1 }
      /app\.cyberstrikeai\.warn\.preupdate_backup/ { saw_csai=1 }
      /\/opt\/cyberstrike-ai\/logs\/backup\.log/ { saw_csai_log=1 }
      /\/usr\/local\/bin\/cyberstrike-ai-backup/ { saw_csai_cmd=1 }
      END {
        if (!(saw_newapi && saw_newapi_log && saw_newapi_cmd && saw_sub2api && saw_sub2api_log && saw_sub2api_cmd && saw_csai && saw_csai_log && saw_csai_cmd)) {
          print "Pre-update backup warnings must tell users where to inspect backup logs and how to run a manual backup." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/newapi.sh apps/sub2api.sh apps/cyberstrikeai.sh
  awk '
      /step "\$\(t app\.newapi\.step\.pre_backup\)"/ { in_newapi=1; saw_newapi_if=0; next }
      in_newapi && /if ! _backup_silent "pre-update"; then/ { saw_newapi_if=1 }
      in_newapi && /warn "\$\(t app\.newapi\.warn\.pre_backup_failed\)"/ {
        if (!saw_newapi_if) {
          printf "%s NewAPI pre-update backup warning must come from an explicit conditional\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_newapi=0
      }
      /step "\$\(t app\.sub2api\.step\.pre_update_backup\)"/ { in_sub2api=1; saw_sub2api_if=0; next }
      in_sub2api && /if ! _backup_silent "pre-update"; then/ { saw_sub2api_if=1 }
      in_sub2api && /warn "\$\(t app\.sub2api\.warn\.pre_update_backup\)"/ {
        if (!saw_sub2api_if) {
          printf "%s Sub2API pre-update backup warning must come from an explicit conditional\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_sub2api=0
      }
      /step "\$\(t app\.cyberstrikeai\.step\.preupdate_backup\)"/ { in_csai=1; saw_csai_if=0; next }
      in_csai && /if ! "\$BACKUP_SCRIPT"; then/ { saw_csai_if=1 }
      in_csai && /warn "\$\(t app\.cyberstrikeai\.warn\.preupdate_backup\)"/ {
        if (!saw_csai_if) {
          printf "%s CyberStrikeAI pre-update backup warning must come from an explicit conditional\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_csai=0
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh impl/install_cyberstrikeai.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_cyberstrikeai.sh
  awk '
      /_backup_silent\(\)/ { in_helper=1; saw_failed_flag=0; saw_pg_fail=0; saw_config_fail=0; saw_return=0; next }
      in_helper && /if ! mkdir -p "\$BACKUP_DIR"; then/ { saw_mkdir_if=1 }
      in_helper && /warn "\$\(t app\.sub2api\.warn\.backup_dir_unwritable "\$BACKUP_DIR"\)"/ { saw_mkdir_warn=1 }
      in_helper && /local backup_failed=0/ { saw_failed_flag=1 }
      in_helper && /_log_backup_helper "\$\(t app\.sub2api\.backup\.log\.pg_dump_failed\)"/ { saw_pg_fail_log=1 }
      in_helper && /warn "\$\(t app\.sub2api\.warn\.pg_dump_failed\)"/ { saw_pg_fail=1 }
      in_helper && /_log_backup_helper "\$\(t app\.sub2api\.backup\.log\.config_failed\)"/ { saw_config_fail_log=1 }
      in_helper && /warn "\$\(t app\.sub2api\.warn\.config_backup_failed\)"/ { saw_config_fail=1 }
      in_helper && /\[\[ "\$backup_failed" -eq 0 \]\]/ { saw_return=1 }
      in_helper && /^}/ {
        if (!(saw_mkdir_if && saw_mkdir_warn && saw_failed_flag && saw_pg_fail_log && saw_pg_fail && saw_config_fail_log && saw_config_fail && saw_return)) {
          printf "%s Sub2API silent backup helper must handle backup-directory creation failures, log backup failures, and propagate them after warning\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_helper=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_sub2api_manual_backup_warnings_are_actionable() {
  awk '
      /app\.sub2api\.warn\.config_backup_failed/ { saw_config_fail=1 }
      /partial archives may still exist in the backup directory/ { saw_partial=1 }
      /app\.sub2api\.warn\.data_missing/ { saw_data_missing=1 }
      /skipping data archive creation/ { saw_data_missing_guidance=1 }
      /app\.sub2api\.warn\.data_backup_failed/ { saw_data_fail=1 }
      END {
        if (!(saw_config_fail && saw_partial && saw_data_missing && saw_data_missing_guidance && saw_data_fail)) {
          print "Sub2API backup warnings must describe partial archive state and missing data directories." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/sub2api.sh
  awk '
      /step "\$\(t app\.sub2api\.step\.manual_backup\)"/ { in_backup=1; next }
      in_backup && /if ! mkdir -p "\$BACKUP_DIR"; then/ { saw_dir_if=1 }
      in_backup && /error "\$\(t app\.sub2api\.error\.backup_dir_create "\$BACKUP_DIR"\)"/ { saw_dir_error=1 }
      in_backup && /warn "\$\(t app\.sub2api\.warn\.config_backup_failed\)"/ { saw_config_warn=1 }
      in_backup && /warn "\$\(t app\.sub2api\.warn\.data_backup_failed\)"/ { saw_data_warn=1 }
      in_backup && /warn "\$\(t app\.sub2api\.warn\.data_missing "\$DATA_DIR"\)"/ { saw_data_missing_warn=1 }
      in_backup && /success "\$\(t app\.sub2api\.success\.backup_done "\$BACKUP_DIR"\)"/ { in_backup=0 }
      END {
        if (!(saw_dir_if && saw_dir_error && saw_config_warn && saw_data_warn && saw_data_missing_warn)) {
          print "Sub2API manual backup must fail explicitly when the backup directory cannot be created, and warn for config/data archive failures and missing data directories." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_preupdate_backup_logs_match_guidance() {
  "$BASH_BIN" -c '
    set -euo pipefail
    for file in impl/install_newapi.sh dist/install_newapi.sh; do
      block=$(sed -n "/^_backup_silent()/,/^_print_install_summary()/p" "$file")
      grep -Fq '\''local backup_log="${BACKUP_DIR}/backup.log"'\'' <<<"$block" || {
        echo "$file NewAPI silent backup helper must declare backup.log output" >&2
        exit 1
      }
      grep -Fq "_log_backup_helper()" <<<"$block" || {
        echo "$file NewAPI silent backup helper must define a backup log helper" >&2
        exit 1
      }
      grep -Fq "[[ -d \"\$BACKUP_DIR\" ]] || return 1" <<<"$block" || {
        echo "$file NewAPI silent backup helper must guard log writes when the backup directory cannot be created" >&2
        exit 1
      }
      grep -Fq "if ! mkdir -p \"\$BACKUP_DIR\"; then" <<<"$block" || {
        echo "$file NewAPI silent backup helper must handle backup directory creation failures explicitly" >&2
        exit 1
      }
      grep -Fq "warn \"\$(t app.newapi.warn.silent_backup_dir_failed \"\$BACKUP_DIR\")\"" <<<"$block" || {
        echo "$file NewAPI silent backup helper must warn explicitly when the backup directory cannot be created" >&2
        exit 1
      }
      grep -Fq ">> \"\$backup_log\"" <<<"$block" || {
        echo "$file NewAPI silent backup helper must append lines to backup.log" >&2
        exit 1
      }
      grep -Fq "_log_backup_helper \"\$(t app.newapi.backup.log.data_missing \"\$DATA_DIR\")\"" <<<"$block" || {
        echo "$file NewAPI silent backup helper must log missing data directory failures" >&2
        exit 1
      }
      grep -Fq "_log_backup_helper \"\$(t app.newapi.backup.log.tar_failed)\"" <<<"$block" || {
        echo "$file NewAPI silent backup helper must log tar failures" >&2
        exit 1
      }
    done
    for file in impl/install_vaultwarden.sh dist/install_vaultwarden.sh; do
      block=$(sed -n "/^_backup_silent()/,/^do_backup()/p" "$file")
      grep -Fq '\''local backup_log="${VW_BACKUP_DIR}/backup.log"'\'' <<<"$block" || {
        echo "$file Vaultwarden silent backup helper must declare backup.log output" >&2
        exit 1
      }
      grep -Fq "_log_backup_helper()" <<<"$block" || {
        echo "$file Vaultwarden silent backup helper must define a backup log helper" >&2
        exit 1
      }
      grep -Fq "[[ -d \"\$VW_BACKUP_DIR\" ]] || return 1" <<<"$block" || {
        echo "$file Vaultwarden silent backup helper must guard log writes when the backup directory cannot be created" >&2
        exit 1
      }
      grep -Fq "if ! mkdir -p \"\$VW_BACKUP_DIR\"; then" <<<"$block" || {
        echo "$file Vaultwarden silent backup helper must handle backup directory creation failures explicitly" >&2
        exit 1
      }
      grep -Fq "warn \"\$(t app.vaultwarden.warn.backup_dir_failed \"\$VW_BACKUP_DIR\")\"" <<<"$block" || {
        echo "$file Vaultwarden silent backup helper must warn explicitly when the backup directory cannot be created" >&2
        exit 1
      }
      grep -Fq ">> \"\$backup_log\"" <<<"$block" || {
        echo "$file Vaultwarden silent backup helper must append lines to backup.log" >&2
        exit 1
      }
      grep -Fq "_log_backup_helper \"\$(t app.vaultwarden.backup.script.data_missing \"\$VW_DATA_DIR\")\"" <<<"$block" || {
        echo "$file Vaultwarden silent backup helper must log missing data directory failures" >&2
        exit 1
      }
      grep -Fq "_log_backup_helper \"\$(t app.vaultwarden.backup.script.failed)\"" <<<"$block" || {
        echo "$file Vaultwarden silent backup helper must log archive failures" >&2
        exit 1
      }
    done
  '
}

check_cyberstrikeai_runtime_dir_failures_are_explicit() {
  awk '
      /app\.cyberstrikeai\.error\.runtime_dirs/ { saw_error_key=1 }
      /Check permissions for %s and %s, then retry/ { saw_guidance=1 }
      END {
        if (!(saw_error_key && saw_guidance)) {
          print "CyberStrikeAI runtime directory failures must explain which paths to inspect." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/cyberstrikeai.sh
  awk '
      /install_runtime_dirs\(\)/ { in_func=1; saw_mkdir_if=0; saw_install_guard=0; saw_backup_guard=0; saw_chown_if=0; saw_mode_if=0; saw_child_mode_if=0; saw_error=0; next }
      in_func && /if ! mkdir -p "\$LOG_DIR" "\$INSTALL_DIR\/data" "\$INSTALL_DIR\/tmp" "\$BACKUP_DIR"; then/ { saw_mkdir_if=1 }
      in_func && /require_safe_path "INSTALL_DIR" "\$INSTALL_DIR"/ { saw_install_guard=1 }
      in_func && /require_safe_path "BACKUP_DIR" "\$BACKUP_DIR"/ { saw_backup_guard=1 }
      in_func && /if ! chown -R "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$INSTALL_DIR" "\$BACKUP_DIR"; then/ { saw_chown_if=1 }
      in_func && /if ! chmod 750 "\$INSTALL_DIR" "\$BACKUP_DIR"; then/ { saw_mode_if=1 }
      in_func && /if ! chmod 750 "\$LOG_DIR" "\$INSTALL_DIR\/data" "\$INSTALL_DIR\/tmp"; then/ { saw_child_mode_if=1 }
      in_func && /error "\$\(t app\.cyberstrikeai\.error\.runtime_dirs "\$INSTALL_DIR" "\$BACKUP_DIR"\)"/ { saw_error=1 }
      in_func && /success "\$\(t app\.cyberstrikeai\.success\.runtime_dirs\)"/ {
        if (!(saw_mkdir_if && saw_install_guard && saw_backup_guard && saw_chown_if && saw_mode_if && saw_child_mode_if && saw_error)) {
          printf "%s CyberStrikeAI runtime directory setup must fail explicitly on mkdir, chown, and chmod errors\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_source_and_build_prep_failures_are_explicit() {
  awk '
      /app\.cyberstrikeai\.error\.user_create/ { saw_user_key=1 }
      /app\.cyberstrikeai\.error\.source_parent_dir/ { saw_parent_key=1 }
      /app\.cyberstrikeai\.error\.repo_fetch/ { saw_fetch_key=1 }
      /git -C %s fetch --prune origin %s/ { saw_fetch_guidance=1 }
      /app\.cyberstrikeai\.error\.repo_checkout/ { saw_checkout_key=1 }
      /git -C %s checkout %s/ { saw_checkout_guidance=1 }
      /app\.cyberstrikeai\.error\.repo_pull/ { saw_pull_key=1 }
      /git -C %s pull --ff-only origin %s/ { saw_pull_guidance=1 }
      /app\.cyberstrikeai\.error\.repo_clone/ { saw_clone_key=1 }
      /git clone --depth 1 --branch %s https:\/\/github.com\/%s\.git %s/ { saw_clone_guidance=1 }
      /app\.cyberstrikeai\.error\.install_dir_missing/ { saw_dir_key=1 }
      /app\.cyberstrikeai\.error\.go_modules/ { saw_mod_key=1 }
      /go mod download/ { saw_mod_guidance=1 }
      /app\.cyberstrikeai\.error\.nginx_dirs/ { saw_nginx_key=1 }
      /app\.cyberstrikeai\.error\.install_dir_owner/ { saw_owner_key=1 }
      END {
        if (!(saw_user_key && saw_parent_key && saw_fetch_key && saw_fetch_guidance && saw_checkout_key && saw_checkout_guidance && saw_pull_key && saw_pull_guidance && saw_clone_key && saw_clone_guidance && saw_dir_key && saw_mod_key && saw_mod_guidance && saw_nginx_key && saw_owner_key)) {
          print "CyberStrikeAI source and build-prep failures must provide actionable recovery guidance." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/cyberstrikeai.sh
  awk '
      /ensure_service_user\(\)/ { in_user=1; saw_user_if=0; saw_user_error=0; next }
      in_user && /if ! useradd --system --home "\$INSTALL_DIR" --shell \/usr\/sbin\/nologin "\$SERVICE_USER"; then/ { saw_user_if=1 }
      in_user && /error "\$\(t app\.cyberstrikeai\.error\.user_create "\$SERVICE_USER"\)"/ { saw_user_error=1 }
      in_user && /success "\$\(t app\.cyberstrikeai\.success\.user_created "\$SERVICE_USER"\)"/ {
        if (!(saw_user_if && saw_user_error)) {
          printf "%s CyberStrikeAI service-user setup must fail explicitly when useradd fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_user=0
      }
      /sync_repo_branch\(\)/ { in_sync=1; saw_fetch_if=0; saw_fetch_error=0; saw_checkout_if=0; saw_checkout_error=0; saw_pull_if=0; saw_pull_error=0; next }
      in_sync && /if ! git -C "\$INSTALL_DIR" fetch --prune origin "\$GITHUB_BRANCH"; then/ { saw_fetch_if=1 }
      in_sync && /error "\$\(t app\.cyberstrikeai\.error\.repo_fetch "\$GITHUB_BRANCH" "\$INSTALL_DIR" "\$INSTALL_DIR" "\$GITHUB_BRANCH"\)"/ { saw_fetch_error=1 }
      in_sync && /if ! git -C "\$INSTALL_DIR" checkout -q "\$GITHUB_BRANCH"; then/ { saw_checkout_if=1 }
      in_sync && /error "\$\(t app\.cyberstrikeai\.error\.repo_checkout "\$INSTALL_DIR" "\$GITHUB_BRANCH" "\$INSTALL_DIR" "\$GITHUB_BRANCH"\)"/ { saw_checkout_error=1 }
      in_sync && /if ! git -C "\$INSTALL_DIR" pull --ff-only origin "\$GITHUB_BRANCH"; then/ { saw_pull_if=1 }
      in_sync && /error "\$\(t app\.cyberstrikeai\.error\.repo_pull "\$INSTALL_DIR" "\$GITHUB_BRANCH" "\$INSTALL_DIR" "\$GITHUB_BRANCH"\)"/ { saw_pull_error=1 }
      in_sync && /^}/ {
        if (!(saw_fetch_if && saw_fetch_error && saw_checkout_if && saw_checkout_error && saw_pull_if && saw_pull_error)) {
          printf "%s CyberStrikeAI git fetch, checkout, and pull steps must fail through explicit conditionals with actionable errors\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_sync=0
      }
      /clone_or_update_repo\(\)/ { in_clone=1; saw_parent_if=0; saw_parent_error=0; saw_sync_call=0; saw_clone_if=0; saw_clone_error=0; next }
      in_clone && /if ! mkdir -p "\$\(dirname "\$INSTALL_DIR"\)"; then/ { saw_parent_if=1 }
      in_clone && /error "\$\(t app\.cyberstrikeai\.error\.source_parent_dir "\$INSTALL_DIR"\)"/ { saw_parent_error=1 }
      in_clone && /sync_repo_branch/ { saw_sync_call=1 }
      in_clone && /if ! git clone --depth 1 --branch "\$GITHUB_BRANCH" "https:\/\/github.com\/\$\{GITHUB_REPO\}\.git" "\$INSTALL_DIR"; then/ { saw_clone_if=1 }
      in_clone && /error "\$\(t app\.cyberstrikeai\.error\.repo_clone "\$GITHUB_REPO" "\$INSTALL_DIR" "\$GITHUB_BRANCH" "\$GITHUB_REPO" "\$INSTALL_DIR"\)"/ { saw_clone_error=1 }
      in_clone && /success "\$\(t app\.cyberstrikeai\.success\.source_ready "\$INSTALL_DIR"\)"/ {
        if (!(saw_parent_if && saw_parent_error && saw_sync_call && saw_clone_if && saw_clone_error)) {
          printf "%s CyberStrikeAI source checkout must fail explicitly when preparing directories or cloning the repository\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_clone=0
      }
      /setup_python_env\(\)/ { in_python=1; saw_python_cd_if=0; saw_python_cd_error=0; next }
      in_python && /if ! cd "\$INSTALL_DIR"; then/ { saw_python_cd_if=1 }
      in_python && /error "\$\(t app\.cyberstrikeai\.error\.install_dir_missing "\$INSTALL_DIR"\)"/ { saw_python_cd_error=1 }
      in_python && /if ! pip_log=\$\(mktemp\); then/ { saw_pip_tmp_if=1 }
      in_python && /warn "\$\(t app\.cyberstrikeai\.warn\.python_requirements\)"/ { saw_pip_tmp_warn=1 }
      in_python && /warn "\$\(t app\.cyberstrikeai\.warn\.requirements_missing\)"/ {
        if (!(saw_python_cd_if && saw_python_cd_error && saw_pip_tmp_if && saw_pip_tmp_warn)) {
          printf "%s CyberStrikeAI Python setup must guard install-directory access and pip log creation explicitly\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_python=0
      }
      /build_binary\(\)/ { in_build=1; saw_build_cd_if=0; saw_build_cd_error=0; saw_mod_if=0; saw_mod_error=0; next }
      in_build && /if ! cd "\$INSTALL_DIR"; then/ { saw_build_cd_if=1 }
      in_build && /error "\$\(t app\.cyberstrikeai\.error\.install_dir_missing "\$INSTALL_DIR"\)"/ { saw_build_cd_error=1 }
      in_build && /if ! go mod download; then/ { saw_mod_if=1 }
      in_build && /error "\$\(t app\.cyberstrikeai\.error\.go_modules "\$INSTALL_DIR"\)"/ { saw_mod_error=1 }
      in_build && /local tmp_bin="\$\{BIN_PATH\}\.tmp\.\$\$"/ {
        if (!(saw_build_cd_if && saw_build_cd_error && saw_mod_if && saw_mod_error)) {
          printf "%s CyberStrikeAI build prep must fail explicitly when the checkout is missing or Go modules cannot be downloaded\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_build=0
      }
      /write_nginx_config\(\)/ { in_nginx=1; saw_nginx_mkdir_if=0; saw_nginx_error=0; next }
      in_nginx && /if ! mkdir -p "\$\(dirname "\$NGINX_CONF"\)" "\$\(dirname "\$NGINX_LINK"\)"; then/ { saw_nginx_mkdir_if=1 }
      in_nginx && /error "\$\(t app\.cyberstrikeai\.error\.nginx_dirs "\$NGINX_CONF"\)"/ { saw_nginx_error=1 }
      in_nginx && /local nginx_tmp/ {
        if (!(saw_nginx_mkdir_if && saw_nginx_error)) {
          printf "%s CyberStrikeAI Nginx setup must guard directory creation explicitly\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_nginx=0
      }
      /step "\$\(t app\.cyberstrikeai\.step\.update_source\)"/ { in_update=1; saw_update_sync=0; saw_owner_if=0; saw_owner_error=0; next }
      in_update && /sync_repo_branch/ { saw_update_sync=1 }
      in_update && /if ! chown -R "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$INSTALL_DIR"; then/ { saw_owner_if=1 }
      in_update && /error "\$\(t app\.cyberstrikeai\.error\.install_dir_owner "\$INSTALL_DIR" "\$SERVICE_USER"\)"/ { saw_owner_error=1 }
      in_update && /if \$service_was_active; then/ {
        if (!(saw_update_sync && saw_owner_if && saw_owner_error)) {
          printf "%s CyberStrikeAI update prep must guard repository sync and ownership repair explicitly\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_update=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_mutating_actions_acquire_locks() {
  "$BASH_BIN" -c '
    set -euo pipefail
    for file in impl/install_*.sh; do
      for action in install update backup uninstall; do
        if grep -q "do_${action}()" "$file"; then
          if ! awk -v fn="do_${action}()" "
              index(\$0, fn \" {\") == 1 { in_func=1; saw_lock=0; next }
              in_func && /acquire_lock/ { saw_lock=1 }
              in_func && /^}/ {
                if (!saw_lock) {
                  printf \"%s %s does not acquire a deployment lock\\n\", FILENAME, fn > \"/dev/stderr\"
                  exit 1
                }
                in_func=0
              }
            " "$file"; then
            exit 1
          fi
        fi
      done
    done
  '
  awk '
      /deploy_add_exit_handler\(\)/ { in_add=1; saw_array_append=0; saw_trap=0; next }
      in_add && /__DEPLOY_EXIT_HANDLERS\+=\("\$handler"\)/ { saw_array_append=1 }
      in_add && /trap '\''__deploy_run_exit_handlers'\'' EXIT/ { saw_trap=1 }
      in_add && /^}/ {
        if (!(saw_array_append && saw_trap)) {
          print "Exit handlers must be appended and installed through the shared dispatcher." > "/dev/stderr"
          exit 1
        }
        in_add=0
      }
      /__deploy_run_exit_handlers\(\)/ { in_run=1; saw_status=0; saw_reverse=0; saw_handler_call=0; next }
      in_run && /local status=\$\?/ { saw_status=1 }
      in_run && /index=\$\{#__DEPLOY_EXIT_HANDLERS\[@\]\} - 1/ { saw_reverse=1 }
      in_run && /"\$handler" \|\| true/ { saw_handler_call=1 }
      in_run && /^}/ {
        if (!(saw_status && saw_reverse && saw_handler_call)) {
          print "Exit handler dispatcher must preserve exit status and run handlers best-effort in reverse order." > "/dev/stderr"
          exit 1
        }
        in_run=0
      }
      /acquire_lock\(\)/ { in_func=1; saw_mkdir=0; saw_error=0; saw_exec=0; saw_handler=0; next }
      in_func && /if ! mkdir -p "\$\(dirname "\$lock_file"\)"; then/ { saw_mkdir=1 }
      in_func && /if ! exec 9>"\$lock_file"; then/ { saw_exec=1 }
      in_func && /error "\$\(t error\.lock_failed "\$lock_file"\)"/ { saw_error=1 }
      in_func && /deploy_add_exit_handler release_lock/ { saw_handler=1 }
      in_func && /trap '\''release_lock'\'' EXIT/ {
        print "Lock acquisition must use deploy_add_exit_handler instead of replacing EXIT trap." > "/dev/stderr"
        exit 1
      }
      in_func && /^}/ {
        if (!(saw_mkdir && saw_exec && saw_error && saw_handler)) {
          print "Lock acquisition must report creation failures and register lock release with the shared exit handler stack." > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' lib/lock.sh dist/install_newapi.sh

  local handler_tmp handler_status handler_output
  handler_tmp="$(mktemp -d)"
  set +e
  HANDLER_LOG="${handler_tmp}/handlers.log" "$BASH_BIN" -c '
    source lib/core.sh
    h1() { echo h1 >> "$HANDLER_LOG"; }
    h2() { echo h2 >> "$HANDLER_LOG"; }
    deploy_add_exit_handler h1
    deploy_add_exit_handler h2
    exit 7
  '
  handler_status=$?
  set -e
  handler_output="$(cat "${handler_tmp}/handlers.log" 2>/dev/null || true)"
  rm -rf "$handler_tmp"
  [[ "$handler_status" -eq 7 ]] || {
    echo "Exit handler dispatcher must preserve the original exit status." >&2
    return 1
  }
  [[ "$handler_output" == $'h2\nh1' ]] || {
    echo "Exit handler dispatcher must run handlers in reverse registration order." >&2
    echo "$handler_output" >&2
    return 1
  }
}

check_update_backs_up_before_stop() {
  local file
  for file in impl/install_newapi.sh impl/install_sub2api.sh; do
    awk '
      /local BAK_PATH=/ { seen_bak=1; seen_cp=0 }
      seen_bak && index($0, "_backup_current_binary \"$BAK_PATH\"") { seen_cp=1 }
      seen_bak && index($0, "systemctl stop \"$SERVICE_NAME\"") {
        if (!seen_cp) {
          printf "%s stops the service before backing up the current binary\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' "$file"
  done
}

check_update_binary_backups_are_atomic() {
  if grep -R -nE '^[[:space:]]*cp "\$(BIN_PATH|VW_BIN)" "?\$\{?(BAK_PATH|VW_BIN)\}?' \
      impl/install_newapi.sh impl/install_sub2api.sh impl/install_vaultwarden.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "Update binary backups must copy to a temporary file before replacing the final backup path." >&2
    return 1
  fi
  awk '
      /_backup_current_binary\(\)|backup_vaultwarden_binary\(\)/ { in_func=1; saw_tmp=0; saw_tmp_error=0; saw_cp=0; saw_mv=0; saw_cleanup=0; saw_atomic=0; saw_app_helper=0; next }
      in_func && /atomic_copy_file "\$(BIN_PATH|VW_BIN)" "\$backup_path"/ { saw_atomic=1 }
      in_func && /app_binary_backup_current "\$backup_path"/ { saw_app_helper=1 }
      in_func && /if ! backup_tmp=\$\(mktemp "\$\{backup_path\}\.XXXXXX"\); then/ { saw_tmp=1 }
      in_func && /error "\$\(t app\.(newapi|sub2api|vaultwarden)\.error\.binary_install/ { saw_tmp_error=1 }
      in_func && /cp "\$(BIN_PATH|VW_BIN)" "\$backup_tmp"/ { saw_cp=1 }
      in_func && /mv "\$backup_tmp" "\$backup_path"/ { saw_mv=1 }
      in_func && /rm -f "\$backup_tmp"/ { saw_cleanup=1 }
      in_func && /^}/ {
        if (!((saw_tmp && saw_tmp_error && saw_cp && saw_mv && saw_cleanup) || (saw_atomic && saw_tmp_error) || (saw_app_helper && saw_tmp_error))) {
          printf "%s binary backup helper must report temp creation failures, stage, replace, and clean up temporary backups\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh impl/install_vaultwarden.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_vaultwarden.sh
}

check_old_backup_cleanup_reports_failures() {
  local file
  awk '
      /app\.cyberstrikeai\.warn\.cleanup_old_binary_failed/ { saw_warn_key=1 }
      /app\.cyberstrikeai\.info\.cleaned_old_binaries/ { saw_count_key=1 }
      END {
        if (!(saw_warn_key && saw_count_key)) {
          print "CyberStrikeAI old binary cleanup messages must be localized." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/cyberstrikeai.sh
  for file in impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh; do
    awk '
        /while IFS= read -r -d '\'''\'' _old_bak; do/ { saw_loop=1 }
        /warn "\$\(t app\.cyberstrikeai\.warn\.cleanup_old_binary_failed "\$_old_bak"\)"/ { saw_warn=1 }
        /info "\$\(t app\.cyberstrikeai\.info\.cleaned_old_binaries "\$_cleaned_old"\)"/ { saw_count=1 }
        /xargs -r rm -f/ {
          printf "%s CyberStrikeAI must not silently batch-remove old binary backups\n", FILENAME > "/dev/stderr"
          exit 1
        }
        END {
          if (!(saw_loop && saw_warn && saw_count)) {
            printf "%s CyberStrikeAI old binary backup cleanup must report per-file failures and count successful removals\n", FILENAME > "/dev/stderr"
            exit 1
          }
        }
      ' "$file"
  done
  for file in impl/install_newapi.sh dist/install_newapi.sh; do
    awk '
        /for _old_bak in "\$\{_old_baks\[@\]\}"/ { saw_loop=1 }
        /warn "\$\(t app\.newapi\.warn\.cleanup_old_failed "\$_old_bak"\)"/ { saw_warn=1 }
        /info "\$\(t app\.newapi\.info\.cleaned_old "\$_cleaned_old"\)"/ { saw_count=1 }
        /rm -f "\$\{_old_baks\[@\]\}"/ {
          printf "%s NewAPI must not silently batch-remove old binary backups\n", FILENAME > "/dev/stderr"
          exit 1
        }
        END {
          if (!(saw_loop && saw_warn && saw_count)) {
            printf "%s NewAPI old binary backup cleanup must report per-file failures and count successful removals\n", FILENAME > "/dev/stderr"
            exit 1
          }
        }
      ' "$file"
  done
  for file in impl/install_sub2api.sh dist/install_sub2api.sh; do
    awk '
        /for _old_bak in "\$\{_old_baks\[@\]\}"/ { saw_loop=1 }
        /warn "\$\(t app\.sub2api\.warn\.cleanup_old_binary_failed "\$_old_bak"\)"/ { saw_warn=1 }
        /info "\$\(t app\.sub2api\.info\.cleaned_old_binaries "\$_cleaned_old"\)"/ { saw_count=1 }
        /rm -f "\$\{_old_baks\[@\]\}"/ {
          printf "%s Sub2API must not silently batch-remove old binary backups\n", FILENAME > "/dev/stderr"
          exit 1
        }
        END {
          if (!(saw_loop && saw_warn && saw_count)) {
            printf "%s Sub2API old binary backup cleanup must report per-file failures and count successful removals\n", FILENAME > "/dev/stderr"
            exit 1
          }
        }
      ' "$file"
  done
  for file in impl/install_vaultwarden.sh dist/install_vaultwarden.sh; do
    awk '
        /for _old_bak in "\$\{_old_baks\[@\]\}"/ { saw_binary_loop=1 }
        /warn "\$\(t app\.vaultwarden\.warn\.cleanup_old_binary_failed "\$_old_bak"\)"/ { saw_binary_warn=1 }
        /info "\$\(t app\.vaultwarden\.info\.cleaned_old_binaries "\$_cleaned_old"\)"/ { saw_binary_count=1 }
        /for _old_wv_bak in "\$\{_old_wv_baks\[@\]\}"/ { saw_web_loop=1 }
        /warn "\$\(t app\.vaultwarden\.warn\.cleanup_old_webvault_failed "\$_old_wv_bak"\)"/ { saw_web_warn=1 }
        /info "\$\(t app\.vaultwarden\.info\.cleaned_webvault_backups "\$_cleaned_wv"\)"/ { saw_web_count=1 }
        /rm -f "\$\{_old_baks\[@\]\}"/ || /rm -rf "\$\{_old_wv_baks\[@\]\}"/ {
          printf "%s Vaultwarden must not silently batch-remove old backups\n", FILENAME > "/dev/stderr"
          exit 1
        }
        END {
          if (!(saw_binary_loop && saw_binary_warn && saw_binary_count && saw_web_loop && saw_web_warn && saw_web_count)) {
            printf "%s Vaultwarden old backup cleanup must report per-path failures and count successful removals\n", FILENAME > "/dev/stderr"
            exit 1
          }
        }
      ' "$file"
  done
}

check_uninstall_binary_cleanup_reports_failures() {
  if grep -R -nE 'find "\$INSTALL_DIR" -maxdepth 1 .* -delete 2>/dev/null \|\| true|find "\$\(dirname "\$VW_BIN"\)" -maxdepth 1 .* -delete 2>/dev/null \|\| true' \
      impl/install_newapi.sh impl/install_sub2api.sh impl/install_vaultwarden.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "Uninstall binary cleanup must report per-path removal failures instead of ignoring find -delete errors." >&2
    return 1
  fi
  awk '
      /do_uninstall\(\)/ { in_uninstall=1; saw_loop=0; saw_warn=0; next }
      in_uninstall && /while IFS= read -r -d '\'''\'' _cleanup_path; do/ { saw_loop=1 }
      in_uninstall && /warn "\$\(t app\.newapi\.warn\.cleanup_old_failed "\$_cleanup_path"\)"/ { saw_warn=1 }
      in_uninstall && /success "\$\(t app\.newapi\.success\.removed_binary\)"/ {
        if (!(saw_loop && saw_warn)) {
          printf "%s NewAPI uninstall binary cleanup must warn on per-path removal failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_uninstall=0
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
  awk '
      /do_uninstall\(\)/ { in_uninstall=1; saw_file_loop=0; saw_dir_loop=0; saw_warn=0; next }
      in_uninstall && /-type f -print0/ { saw_file_loop=1 }
      in_uninstall && /-type d -print0/ { saw_dir_loop=1 }
      in_uninstall && /warn "\$\(t app\.sub2api\.warn\.cleanup_old_binary_failed "\$_cleanup_path"\)"/ { saw_warn=1 }
      in_uninstall && /success "\$\(t app\.sub2api\.success\.removed_binary\)"/ {
        if (!(saw_file_loop && saw_dir_loop && saw_warn)) {
          printf "%s Sub2API uninstall binary cleanup must warn on file and directory removal failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_uninstall=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
  awk '
      /do_uninstall\(\)/ { in_uninstall=1; saw_loop=0; saw_warn=0; next }
      in_uninstall && /while IFS= read -r -d '\'''\'' _cleanup_path; do/ { saw_loop=1 }
      in_uninstall && /warn "\$\(t app\.vaultwarden\.warn\.cleanup_old_binary_failed "\$_cleanup_path"\)"/ { saw_warn=1 }
      in_uninstall && /success "\$\(t app\.vaultwarden\.success\.removed_binary\)"/ {
        if (!(saw_loop && saw_warn)) {
          printf "%s Vaultwarden uninstall binary cleanup must warn on per-path removal failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_uninstall=0
      }
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
}

check_sub2api_extract_move_failure_cleanup() {
  if grep -R -n '^[[:space:]]*mv "$bin_path" "$tmp_bin"$' impl/install_sub2api.sh dist/install_sub2api.sh 2>/dev/null; then
    echo "sub2api extraction must clean up temporary files if moving the binary fails." >&2
    return 1
  fi
  awk '
      /extract_and_verify\(\)/ { in_func=1; saw_extract_tmp=0; saw_extract_archive_rm=0; saw_extract_error=0; saw_bin_tmp=0; saw_bin_archive_rm=0; saw_bin_extract_rm=0; saw_bin_error=0; next }
      in_func && index($0, "if ! tmp_extract=$(mktemp -d \"${dest_dir}/sub2api-extract.XXXXXX\"); then") { saw_extract_tmp=1; next }
      in_func && saw_bin_tmp && index($0, "rm -f \"$archive\"") { saw_bin_archive_rm=1; next }
      in_func && saw_bin_tmp && index($0, "rm -rf \"$tmp_extract\"") { saw_bin_extract_rm=1; next }
      in_func && saw_bin_tmp && index($0, "error \"$(t app.sub2api.error.archive_missing_binary)\"") { saw_bin_error=1; next }
      in_func && saw_extract_tmp && index($0, "rm -f \"$archive\"") { saw_extract_archive_rm=1; next }
      in_func && saw_extract_tmp && index($0, "error \"$(t app.sub2api.error.tar_extract)\"") { saw_extract_error=1; next }
      in_func && index($0, "if ! tmp_bin=$(mktemp \"${dest_dir}/sub2api.tmp.XXXXXX\"); then") { saw_bin_tmp=1; next }
      in_func && index($0, "echo \"$tmp_bin\"") {
        if (!(saw_extract_tmp && saw_extract_archive_rm && saw_extract_error && saw_bin_tmp && saw_bin_archive_rm && saw_bin_extract_rm && saw_bin_error)) {
          printf "%s sub2api extraction must report and clean up temporary file creation failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_sub2api_pg_dump_errors_stay_out_of_backups() {
  if grep -R -nE 'pg_dump "\$\{PG_DSN\}" 2>&1 \| gzip >|pg_dump "\$PG_DSN" 2>&1 \| gzip >' \
      impl/install_sub2api.sh dist/install_sub2api.sh 2>/dev/null; then
    echo "Sub2API pg_dump backups must not mix stderr into compressed SQL archives." >&2
    return 1
  fi
  if grep -R -nE 'pg_dump "\$\{PG_DSN\}" 2>/dev/null \| gzip >|pg_dump "\$PG_DSN" 2>/dev/null \| gzip >' \
      impl/install_sub2api.sh dist/install_sub2api.sh 2>/dev/null; then
    echo "Sub2API pg_dump backups must preserve stderr diagnostics instead of discarding them." >&2
    return 1
  fi
  awk '
      /PG_DUMP_FILE="\$\{BACKUP_DIR\}\/sub2api_db_\$\{TS\}\.sql\.gz"/ { in_script=1; saw_stderr_log=0; saw_archive=0; next }
      in_script && /pg_dump "\$\{PG_DSN\}" 2> >\(/ { saw_stderr_log=1 }
      in_script && /gzip > "\$\{PG_DUMP_TMP\}"/ { saw_archive=1 }
      in_script && /# ── 2\. Configuration and local data backup/ {
        if (!(saw_stderr_log && saw_archive)) {
          printf "%s Sub2API backup script must keep pg_dump stderr separate from SQL archive data\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_script=0
      }
      /do_backup\(\)/ { in_manual=1; saw_manual_archive=0; next }
      in_manual && /pg_dump "\$\{PG_DSN\}" \| gzip > "\$PG_TMP"/ { saw_manual_archive=1 }
      in_manual && /^}/ {
        if (!saw_manual_archive) {
          printf "%s Sub2API manual backup must archive only pg_dump stdout\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_manual=0
      }
      /_backup_silent\(\)/ { in_silent=1; saw_silent_stderr=0; next }
      in_silent && /pg_dump "\$\{PG_DSN\}" 2> >\(sed .* >&2\) \| gzip > "\$pg_tmp"/ { saw_silent_stderr=1 }
      in_silent && /^}/ {
        if (!saw_silent_stderr) {
          printf "%s Sub2API silent backup must preserve pg_dump stderr while archiving only stdout\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_silent=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_sub2api_summary_does_not_print_pg_password() {
  if grep -R -nE 'summary\.password.*\$\{?PG_PASS\}?' impl/install_sub2api.sh dist/install_sub2api.sh 2>/dev/null; then
    echo "Sub2API install summary must not print the generated PostgreSQL password." >&2
    return 1
  fi
  awk '
      /_print_install_summary\(\)/ { in_summary=1; saw_password_written=0; next }
      in_summary && /summary\.password_written "\$CONF_FILE"/ { saw_password_written=1 }
      in_summary && /^}/ {
        if (!saw_password_written) {
          printf "%s Sub2API install summary must tell users where the PostgreSQL password was written\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_summary=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_sub2api_pg_password_is_escaped() {
  if grep -R -nF "WITH PASSWORD '\${PG_PASS}'" impl/install_sub2api.sh dist/install_sub2api.sh 2>/dev/null; then
    echo "Sub2API must not interpolate PG_PASS directly into SQL literals." >&2
    return 1
  fi
  if grep -R -nF 'postgresql://${PG_USER}:${PG_PASS}@' impl/install_sub2api.sh dist/install_sub2api.sh 2>/dev/null; then
    echo "Sub2API must URI-encode PG_PASS before building PG_DSN." >&2
    return 1
  fi
  awk '
      /_uri_encode\(\)/ { saw_encoder=1 }
      /psql -v pg_pass="\$PG_PASS" -c/ { saw_psql_var++ }
      /WITH PASSWORD :'\''pg_pass'\'';/ { saw_literal++ }
      index($0, "PG_DSN=\"postgresql://${PG_USER}:$(_uri_encode \"$PG_PASS\")@localhost:5432/${PG_DB}?sslmode=disable\"") { saw_dsn=1 }
      END {
        if (!(saw_encoder && saw_psql_var >= 2 && saw_literal >= 2 && saw_dsn)) {
          printf "%s Sub2API must escape PG_PASS for SQL and URI contexts\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_cyberstrikeai_build_temp_cleanup() {
  if grep -R -n '\${BIN_PATH}\.tmp\.\$\$' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "CyberStrikeAI binary build must use mktemp instead of a pid-derived temporary binary path." >&2
    return 1
  fi
  if grep -R -nE '^[[:space:]]*(go build|chmod 0755 "\$tmp_bin"|mv "\$tmp_bin" "\$BIN_PATH")' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "CyberStrikeAI binary build must clean up the temporary binary on build, chmod, and move failures." >&2
    return 1
  fi
  awk '
      /if ! tmp_bin=\$\(mktemp "\$\{BIN_PATH\}\.tmp\.XXXXXX"\); then/ { saw_tmp=1 }
      /error "\$\(t app\.cyberstrikeai\.error\.binary_build\)"/ { saw_tmp_error=1 }
      /if ! go build .*"\$tmp_bin"/ { in_block=1; saw_build_cleanup=0; next }
      in_block && /rm -f "\$tmp_bin"/ { saw_build_cleanup=1 }
      in_block && /error "\$\(t app\.cyberstrikeai\.error\.binary_build\)"/ {
        if (!saw_build_cleanup) {
          print "CyberStrikeAI build failure does not clean up the temporary binary." > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
      END {
        if (!(saw_tmp && saw_tmp_error)) {
          print "CyberStrikeAI build must report temporary binary creation failures." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_rollback_restore_is_validated() {
  if grep -R -nE '^[[:space:]]*(\[\[ -f "\$(bin_bak|config_bak)" \]\] && cp "\$(bin_bak|config_bak)"|chown "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$BIN_PATH" "\$CONFIG_FILE" 2>/dev/null \|\| true)' \
      impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "CyberStrikeAI update rollback must validate backup restore, mode, and ownership changes." >&2
    return 1
  fi
  awk '
      /restore_update_backup\(\)/ { in_func=1; saw_bin_tmp=0; saw_bin_tmp_return=0; saw_bin_cp=0; saw_chmod=0; saw_bin_chown=0; saw_bin_mv=0; saw_config_tmp=0; saw_config_tmp_return=0; saw_config_cp=0; saw_config_chown=0; saw_config_mv=0; next }
      in_func && /if ! bin_restore_tmp=\$\(mktemp "\$\{BIN_PATH\}\.restore\.XXXXXX"\); then/ { saw_bin_tmp=1 }
      in_func && saw_bin_tmp && /return 1/ { saw_bin_tmp_return=1 }
      in_func && /cp "\$bin_backup" "\$bin_restore_tmp"/ { saw_bin_cp=1 }
      in_func && /chmod 0755 "\$bin_restore_tmp"/ { saw_chmod=1 }
      in_func && /chown "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$bin_restore_tmp"/ { saw_bin_chown=1 }
      in_func && /mv "\$bin_restore_tmp" "\$BIN_PATH"/ { saw_bin_mv=1 }
      in_func && /if ! config_restore_tmp=\$\(mktemp "\$\{CONFIG_FILE\}\.restore\.XXXXXX"\); then/ { saw_config_tmp=1 }
      in_func && saw_config_tmp && /return 1/ { saw_config_tmp_return=1 }
      in_func && /cp "\$config_backup" "\$config_restore_tmp"/ { saw_config_cp=1 }
      in_func && /chown "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$config_restore_tmp"/ { saw_config_chown=1 }
      in_func && /mv "\$config_restore_tmp" "\$CONFIG_FILE"/ { saw_config_mv=1 }
      in_func && /^}/ {
        if (!(saw_bin_tmp && saw_bin_tmp_return && saw_bin_cp && saw_chmod && saw_bin_chown && saw_bin_mv && saw_config_tmp && saw_config_tmp_return && saw_config_cp && saw_config_chown && saw_config_mv)) {
          printf "%s CyberStrikeAI rollback helper must stage and atomically restore binary and config state\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_backups_are_atomic() {
  if grep -R -nE '^[[:space:]]*(cp "\$CONFIG_FILE" "\$backup"|\[\[ -f "\$(BIN_PATH|CONFIG_FILE)" \]\] && cp "\$(BIN_PATH|CONFIG_FILE)")' \
      impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "CyberStrikeAI rollback/config backups must copy to a temporary file before replacing the final backup path." >&2
    return 1
  fi
  awk '
      /write_backup_file\(\)/ { in_func=1; saw_tmp=0; saw_tmp_return=0; saw_cp=0; saw_mv=0; saw_cleanup=0; saw_atomic=0; next }
      in_func && /atomic_copy_file "\$source_path" "\$backup_path"/ { saw_atomic=1 }
      in_func && /if ! backup_tmp=\$\(mktemp "\$\{backup_path\}\.XXXXXX"\); then/ { saw_tmp=1 }
      in_func && saw_tmp && /return 1/ { saw_tmp_return=1 }
      in_func && /cp "\$source_path" "\$backup_tmp"/ { saw_cp=1 }
      in_func && /mv "\$backup_tmp" "\$backup_path"/ { saw_mv=1 }
      in_func && /rm -f "\$backup_tmp"/ { saw_cleanup=1 }
      in_func && /^}/ {
        if (!((saw_tmp && saw_tmp_return && saw_cp && saw_mv && saw_cleanup) || saw_atomic)) {
          printf "%s CyberStrikeAI backup helper must stage, replace, and clean up temporary backups\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_config_patch_is_atomic() {
  if grep -R -n 'path.write_text(text, encoding="utf-8")' \
      impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "CyberStrikeAI config patching must write via a staged temporary file and atomic replace." >&2
    return 1
  fi
  awk '
      /patch_config_port_and_paths\(\)/ { in_func=1; saw_stat=0; saw_tmpfile=0; saw_fsync=0; saw_chmod=0; saw_chown=0; saw_replace=0; saw_cleanup=0; next }
      in_func && /file_stat = path\.stat\(\)/ { saw_stat=1 }
      in_func && /tempfile\.NamedTemporaryFile\(/ { saw_tmpfile=1 }
      in_func && /os\.fsync\(handle\.fileno\(\)\)/ { saw_fsync=1 }
      in_func && /os\.chmod\(tmp_path, file_stat\.st_mode & 0o777\)/ { saw_chmod=1 }
      in_func && /os\.chown\(tmp_path, file_stat\.st_uid, file_stat\.st_gid\)/ { saw_chown=1 }
      in_func && /os\.replace\(tmp_path, path\)/ { saw_replace=1 }
      in_func && /Path\(tmp_path\)\.unlink\(missing_ok=True\)/ { saw_cleanup=1 }
      in_func && /^}/ {
        if (!(saw_stat && saw_tmpfile && saw_fsync && saw_chmod && saw_chown && saw_replace && saw_cleanup)) {
          printf "%s CyberStrikeAI config patch helper must stage writes and atomically replace the config file\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_backup_temp_moves_handle_failure() {
  if grep -R -nE '^[[:space:]]*mv "\$[^"]*(TMP|tmp|ARCHIVE_TMP|archive_tmp|PG_TMP|pg_tmp|CONF_TMP|conf_tmp|DATA_TMP|data_tmp|DUMP_TMP|dump_tmp)[^"]*" "\$[^"]*(ARCHIVE|archive|FILE|file)' impl dist 2>/dev/null; then
    echo "Backup temporary files must be removed when the final move fails." >&2
    return 1
  fi
}

check_binary_replacements_handle_failure() {
  if grep -R -nE '^[[:space:]]*(mv "\$TMP_(BIN|ARCHIVE)" "\$BIN_PATH"|chmod \+x "\$BIN_PATH"|chown "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$BIN_PATH")$' \
      impl/install_newapi.sh impl/install_sub2api.sh dist/install_newapi.sh dist/install_sub2api.sh 2>/dev/null; then
    echo "Binary replacements must clean up candidates and restore backups on move, chmod, and chown failures." >&2
    return 1
  fi
  if grep -R -n 'mv "$backup_path" "$BIN_PATH" 2>/dev/null || true' \
      impl/install_newapi.sh impl/install_sub2api.sh dist/install_newapi.sh dist/install_sub2api.sh 2>/dev/null; then
    echo "Binary candidate installs must validate moving backups back into place." >&2
    return 1
  fi
  awk '
      /_install_binary_candidate\(\)/ { in_func=1; saw_helper=0; next }
      in_func && /app_binary_install_candidate "\$@"/ { saw_helper=1 }
      in_func && /^}/ {
        if (!saw_helper) {
          printf "%s install binary wrapper must call app_binary_install_candidate\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh dist/install_newapi.sh dist/install_sub2api.sh
  awk '
      /_restore_moved_binary_backup\(\)/ { in_func=1; saw_tmp=0; saw_tmp_return=0; saw_cp=0; saw_chmod=0; saw_chown=0; saw_mv=0; saw_cleanup=0; saw_app_helper=0; next }
      in_func && /app_binary_restore_moved_backup "\$1"/ { saw_app_helper=1 }
      in_func && /if ! restore_tmp=\$\(mktemp "\$\{BIN_PATH\}\.restore\.XXXXXX"\); then/ { saw_tmp=1 }
      in_func && saw_tmp && /return 1/ { saw_tmp_return=1 }
      in_func && /cp "\$backup_path" "\$restore_tmp"/ { saw_cp=1 }
      in_func && /chmod \+x "\$restore_tmp"/ { saw_chmod=1 }
      in_func && /chown "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$restore_tmp"/ { saw_chown=1 }
      in_func && /mv "\$restore_tmp" "\$BIN_PATH"/ { saw_mv=1 }
      in_func && /rm -f "\$backup_path"/ { saw_cleanup=1 }
      in_func && /^}/ {
        if (!((saw_tmp && saw_tmp_return && saw_cp && saw_chmod && saw_chown && saw_mv && saw_cleanup) || saw_app_helper)) {
          printf "%s moved binary backup restores must stage, restore atomically, and clean up the moved backup\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh dist/install_newapi.sh dist/install_sub2api.sh
}

check_binary_restores_validate_permissions() {
  if grep -R -nE '^[[:space:]]*(chmod \+x "\$BIN_PATH"|chown "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$BIN_PATH") 2>/dev/null \|\| true$' \
      impl/install_newapi.sh impl/install_sub2api.sh dist/install_newapi.sh dist/install_sub2api.sh 2>/dev/null; then
    echo "Binary rollback restores must validate executable mode and ownership changes." >&2
    return 1
  fi
  if grep -R -n '_restore_binary_backup "\$OLD_BIN_BAK" || true' \
      impl/install_newapi.sh impl/install_sub2api.sh dist/install_newapi.sh dist/install_sub2api.sh 2>/dev/null; then
    echo "Install rollback restores must not ignore backup restore failures." >&2
    return 1
  fi
  awk '
      /_restore_binary_backup\(\)/ { in_func=1; saw_tmp=0; saw_tmp_return=0; saw_cp=0; saw_chmod=0; saw_chown=0; saw_mv=0; saw_app_helper=0; next }
      in_func && /app_binary_restore_backup "\$1"/ { saw_app_helper=1 }
      in_func && /if ! restore_tmp=\$\(mktemp "\$\{BIN_PATH\}\.restore\.XXXXXX"\); then/ { saw_tmp=1 }
      in_func && saw_tmp && /return 1/ { saw_tmp_return=1 }
      in_func && /cp "\$backup_path" "\$restore_tmp"/ { saw_cp=1 }
      in_func && /chmod \+x "\$restore_tmp"/ { saw_chmod=1 }
      in_func && /chown "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$restore_tmp"/ { saw_chown=1 }
      in_func && /mv "\$restore_tmp" "\$BIN_PATH"/ { saw_mv=1 }
      in_func && /^}/ {
        if (!((saw_tmp && saw_tmp_return && saw_cp && saw_chmod && saw_chown && saw_mv) || saw_app_helper)) {
          printf "%s restore helper must stage and atomically restore binary mode and ownership\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh dist/install_newapi.sh dist/install_sub2api.sh
}

check_download_validation_failures_cleanup() {
  if grep -R -n 'app\.sub2api\.warn\.\(checksum_download\|checksum_missing\|sha_tool_missing\)' \
      apps/sub2api.sh impl/install_sub2api.sh dist/install_sub2api.sh 2>/dev/null; then
    echo "Sub2API checksum verification must fail closed instead of warning and continuing." >&2
    return 1
  fi
  awk '
      /verify_binary\(\)/ { in_func=1; saw_rm=0; next }
      in_func && /rm -f "\$bin"/ { saw_rm=1 }
      in_func && /error "\$\(t app\.newapi\.error\.binary_/ {
        if (!saw_rm) {
          printf "%s does not remove the downloaded binary before validation failure\n", FILENAME > "/dev/stderr"
          exit 1
        }
        saw_rm=0
      }
      in_func && /^}/ { in_func=0 }
    ' impl/install_newapi.sh dist/install_newapi.sh
  awk '
      /verify_checksum\(\)/ { in_checksum=1; saw_checksum_archive_rm=0; next }
      in_checksum && /rm -f "\$archive"/ { saw_checksum_archive_rm=1 }
      in_checksum && /error "\$\(t app\.sub2api\.error\.(checksum_temp|checksum_download|checksum_missing|sha_tool_missing)/ {
        if (!saw_checksum_archive_rm) {
          printf "%s does not remove the downloaded archive before checksum verification availability failure\n", FILENAME > "/dev/stderr"
          exit 1
        }
        saw_checksum_archive_rm=0
      }
      in_checksum && /if \[\[ "\$actual_hash" != "\$expected_hash" \]\]/ { in_sha_failure=1; saw_rm=0; next }
      in_sha_failure && /rm -f "\$archive"/ { saw_rm=1 }
      in_sha_failure && /error "\$\(t app\.sub2api\.error\.sha_failed/ {
        if (!saw_rm) {
          printf "%s does not remove the downloaded archive before checksum failure\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_sha_failure=0
      }
      in_checksum && /^}/ { in_checksum=0 }
      /extract_and_verify\(\)/ { in_extract=1; saw_archive_rm=0; next }
      in_extract && /rm -f "\$archive"/ { saw_archive_rm=1 }
      in_extract && /error "\$\(t app\.sub2api\.error\.(tar_extract|archive_missing_binary|not_elf|elf_machine)/ {
        if (!saw_archive_rm) {
          printf "%s does not remove the downloaded archive before extraction validation failure\n", FILENAME > "/dev/stderr"
          exit 1
        }
        saw_archive_rm=0
      }
      in_extract && /^}/ { in_extract=0 }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
  awk '
      /verify_go_archive_checksum\(\)/ { in_func=1; saw_archive_rm=0; saw_compare=0; next }
      in_func && /rm -f "\$archive"/ { saw_archive_rm=1 }
      in_func && /error "\$\(t app\.cyberstrikeai\.error\.(go_checksum_missing|go_sha_tool_missing|go_sha_failed)/ {
        if (!saw_archive_rm) {
          printf "%s does not remove the downloaded Go archive before checksum verification failure\n", FILENAME > "/dev/stderr"
          exit 1
        }
        saw_archive_rm=0
      }
      in_func && /if \[\[ "\$actual_sha" != "\$expected_sha" \]\]; then/ { saw_compare=1 }
      in_func && /info "\$\(t app\.cyberstrikeai\.info\.go_sha_ok "\$\{actual_sha:0:16\}"\)"/ {
        if (!saw_compare) {
          printf "%s Go checksum verification must compare the downloaded archive against release metadata\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
      END {
        if (in_func) {
          printf "%s Go checksum verifier did not reach a successful verification path\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
  awk '
      /tarball="\$\{version\}\.linux-\$\{go_arch\}\.tar\.gz"/ { saw_tarball=1 }
      /expected_sha=\$\(go_release_sha256 "\$latest_json" "\$tarball" \|\| true\)/ { saw_expected=1 }
      /verify_go_archive_checksum "\$tmp" "\$expected_sha" "\$tarball"/ { saw_verify=1 }
      END {
        if (!(saw_tarball && saw_expected && saw_verify)) {
          printf "%s CyberStrikeAI Go install must verify official release checksums before extraction\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_download_temp_creation_failures_are_explicit() {
  awk '
      /verify_checksum\(\)/ { in_func=1; saw_tmp=0; saw_rm=0; saw_error=0; next }
      in_func && index($0, "if ! tmp_sum=$(mktemp); then") { saw_tmp=1; next }
      in_func && saw_tmp && /rm -f "\$archive"/ { saw_rm=1; next }
      in_func && saw_tmp && index($0, "error \"$(t app.sub2api.error.checksum_temp)\"") { saw_error=1; next }
      in_func && index($0, "success \"$(t app.sub2api.success.sha_ok \"${actual_hash:0:16}\")\"") {
        if (!(saw_tmp && saw_rm && saw_error)) {
          printf "%s Sub2API checksum temporary file creation failures must remove the archive and fail explicitly\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
  awk '
      /step "\$\(t app\.newapi\.step\.download "\$BIN_ARCH"\)"/ { in_install=1; saw_install_tmp=0; saw_install_error=0; next }
      in_install && /if ! TMP_BIN=\$\(mktemp "\$\{INSTALL_DIR\}\/new-api\.tmp\.XXXXXX"\); then/ { saw_install_tmp=1 }
      in_install && /error "\$\(t app\.newapi\.error\.download "\$GITHUB_REPO"\)"/ { saw_install_error=1 }
      in_install && /if ! curl -fL --progress-bar -o "\$TMP_BIN" "\$DOWNLOAD_URL"; then/ {
        if (!(saw_install_tmp && saw_install_error)) {
          printf "%s NewAPI install must report temporary download file creation failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_install=0
      }
      /step "\$\(t app\.newapi\.step\.download_update "\$CURRENT" "\$LATEST"\)"/ { in_update=1; saw_update_tmp=0; saw_update_error=0; next }
      in_update && /if ! TMP_BIN=\$\(mktemp "\$\{INSTALL_DIR\}\/new-api\.tmp\.XXXXXX"\); then/ { saw_update_tmp=1 }
      in_update && /error "\$\(t app\.newapi\.error\.update_download\)"/ { saw_update_error=1 }
      in_update && /if ! curl -fL --progress-bar -o "\$TMP_BIN" "\$DOWNLOAD_URL"; then/ {
        if (!(saw_update_tmp && saw_update_error)) {
          printf "%s NewAPI update must report temporary download file creation failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_update=0
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
  awk '
      /step "\$\(t app\.sub2api\.step\.download_binary "\$BIN_ARCH"\)"/ { in_install=1; saw_install_tmp=0; saw_install_error=0; next }
      in_install && /if ! TMP_ARCHIVE=\$\(mktemp "\$\{INSTALL_DIR\}\/sub2api-release\.XXXXXX\.tar\.gz"\); then/ { saw_install_tmp=1 }
      in_install && /error "\$\(t app\.sub2api\.error\.download_failed "\$GITHUB_REPO"\)"/ { saw_install_error=1 }
      in_install && /if ! curl -fL --progress-bar -o "\$TMP_ARCHIVE" "\$DOWNLOAD_URL"; then/ {
        if (!(saw_install_tmp && saw_install_error)) {
          printf "%s Sub2API install must report temporary download archive creation failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_install=0
      }
      /step "\$\(t app\.sub2api\.step\.download_update "\$CURRENT" "\$LATEST"\)"/ { in_update=1; saw_update_tmp=0; saw_update_error=0; next }
      in_update && /if ! TMP_ARCHIVE=\$\(mktemp "\$\{INSTALL_DIR\}\/sub2api-release\.XXXXXX\.tar\.gz"\); then/ { saw_update_tmp=1 }
      in_update && /error "\$\(t app\.sub2api\.error\.update_download\)"/ { saw_update_error=1 }
      in_update && /if ! curl -fL --progress-bar -o "\$TMP_ARCHIVE" "\$DOWNLOAD_URL"; then/ {
        if (!(saw_update_tmp && saw_update_error)) {
          printf "%s Sub2API update must report temporary download archive creation failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_update=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_vaultwarden_env_file_is_atomic() {
  if grep -R -n '^[[:space:]]*cat > "\$VW_ENV_FILE"' impl/install_vaultwarden.sh dist/install_vaultwarden.sh 2>/dev/null; then
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
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
}

check_vaultwarden_binary_installs_are_atomic() {
  if grep -R -n 'install -m 755 -o root -g root .* "$VW_BIN"' impl/install_vaultwarden.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "Vaultwarden binary installs must stage to a temporary file before replacing VW_BIN." >&2
    return 1
  fi
  awk '
      /install_vaultwarden_binary\(\)/ { in_func=1; saw_dir=0; saw_dir_return=0; saw_tmp=0; saw_tmp_return=0; saw_install=0; saw_mv=0; saw_cleanup=0; next }
      in_func && /if ! mkdir -p "\$VW_BIN_DIR"; then/ { saw_dir=1 }
      in_func && saw_dir && /return 1/ { saw_dir_return=1 }
      in_func && /if ! bin_tmp=\$\(mktemp "\$\{VW_BIN\}\.XXXXXX"\); then/ { saw_tmp=1 }
      in_func && saw_tmp && /return 1/ { saw_tmp_return=1 }
      in_func && /install -m 755 -o root -g root "\$source_bin" "\$bin_tmp"/ { saw_install=1 }
      in_func && /mv "\$bin_tmp" "\$VW_BIN"/ { saw_mv=1 }
      in_func && /rm -f "\$bin_tmp"/ { saw_cleanup=1 }
      in_func && /^}/ {
        if (!(saw_dir && saw_dir_return && saw_tmp && saw_tmp_return && saw_install && saw_mv && saw_cleanup)) {
          print "Vaultwarden binary install helper must stage, replace, and clean up temporary files." > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
}

check_vaultwarden_admin_token_file_is_private() {
  if grep -R -n 'mktemp /tmp/vw_token_' impl/install_vaultwarden.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "Vaultwarden admin token display files must not be created in world-writable /tmp." >&2
    return 1
  fi
  awk '
      /if ! _token_tmp=\$\(mktemp \/root\/\.vaultwarden-admin-token\.XXXXXX\); then/ { saw_tmp=1 }
      /error "\$\(t app\.vaultwarden\.error\.admin_token_hash\)"/ { saw_tmp_error=1 }
      /chmod 600 "\$_token_tmp"/ { saw_chmod=1 }
      /printf .*\$ADMIN_PLAIN.*> "\$_token_tmp"/ { saw_write=1 }
      /rm -f "\$_token_tmp"/ { saw_cleanup=1 }
      END {
        if (!(saw_tmp && saw_tmp_error && saw_chmod && saw_write && saw_cleanup)) {
          print "Vaultwarden admin token display files must report temp creation failures, be private, and clean up on write failure." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
}

check_vaultwarden_extract_tool_is_pinned_and_verified() {
  if grep -R -n 'EXTRACT_TOOL_COMMIT="\${EXTRACT_TOOL_COMMIT:-main}"' impl/install_vaultwarden.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "Vaultwarden must not default docker-image-extract to a floating branch." >&2
    return 1
  fi
  if grep -R -nE 'VW_IMAGE_TAG="\$\{VW_IMAGE_TAG:-(latest|latest-[^}]*)\}"' impl/install_vaultwarden.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "Vaultwarden must not default to a mutable image tag." >&2
    return 1
  fi
  if grep -R -n 'EXTRACT_TOOL_SHA256="\${EXTRACT_TOOL_SHA256:-}"' impl/install_vaultwarden.sh dist/install_vaultwarden.sh 2>/dev/null; then
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
    ' apps/vaultwarden.sh impl/install_vaultwarden.sh dist/install_vaultwarden.sh
}

check_newapi_secret_uses_private_env_file() {
  if grep -R -n 'Environment="SESSION_SECRET=' impl/install_newapi.sh dist/install_newapi.sh 2>/dev/null; then
    echo "NewAPI must not embed SESSION_SECRET directly in a world-readable systemd unit." >&2
    return 1
  fi
  awk '
      /_write_env_file\(\)/ { in_func=1; saw_atomic=0; saw_secret=0; next }
      in_func && /atomic_write_file "\$ENV_FILE" 600 root:root/ { saw_atomic=1 }
      in_func && /SESSION_SECRET=\$\{session_secret\}/ { saw_secret=1 }
      in_func && /^}/ {
        if (!(saw_atomic && saw_secret)) {
          printf "%s NewAPI runtime secrets must be written through a private environment file\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
      /EnvironmentFile=\$\{ENV_FILE\}/ { saw_envfile=1 }
      /error "\$\(t app\.newapi\.error\.env_file "\$ENV_FILE"\)"/ { saw_error=1 }
      /success "\$\(t app\.newapi\.success\.env_file "\$ENV_FILE"\)"/ { saw_success=1 }
      /rm -f "\$ENV_FILE"/ { saw_remove=1 }
      END {
        if (!(saw_envfile && saw_error && saw_success && saw_remove)) {
          printf "%s NewAPI must wire the private environment file through install and uninstall\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
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

check_backup_scripts_are_atomic() {
  if grep -R -nE '^[[:space:]]*cat (>|>>) /usr/local/bin/.*-backup|^[[:space:]]*cat > "\$BACKUP_SCRIPT"' impl dist 2>/dev/null; then
    echo "Backup scripts must be written through temporary files before replacement." >&2
    return 1
  fi
  awk '
      /if ! backup_tmp=\$\(mktemp/ { saw_tmp=1 }
      /error "\$\(t app\.(newapi|sub2api|cyberstrikeai|vaultwarden)\.error\.(backup_script|backup_write)\)"/ { saw_tmp_error=1 }
      /mv "\$backup_tmp" "(\$backup_script|\$BACKUP_SCRIPT)"/ { saw_mv=1 }
      /rm -f "\$backup_tmp"/ { saw_cleanup=1 }
      END {
        if (!(saw_tmp && saw_tmp_error && saw_mv && saw_cleanup)) {
          print "Backup script writes must report temp creation failures, stage, replace, and clean up temporary files." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh impl/install_cyberstrikeai.sh impl/install_vaultwarden.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_cyberstrikeai.sh dist/install_vaultwarden.sh
}

check_generated_backup_headers_are_shell_quoted() {
  if grep -R -nE '^(BACKUP_DIR|DATA_DIR|CONFIG_DIR|INSTALL_DIR|PG_DSN|SERVICE_NAME)="\$\{(BACKUP_DIR|DATA_DIR|CONFIG_DIR|INSTALL_DIR|PG_DSN|SERVICE_NAME)\}"$|^KEEP_DAYS="\$\{BACKUP_KEEP_DAYS\}"$|^LOG_FILE="\$\{LOG_DIR\}/backup\.log"$' \
      impl/install_newapi.sh impl/install_sub2api.sh impl/install_cyberstrikeai.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "Generated backup script headers must use shell-quoted literals instead of interpolating raw values." >&2
    return 1
  fi
  awk '
      /_write_backup_script\(\)/ { in_func=1; saw_backup=0; saw_data=0; next }
      in_func && /printf -v backup_dir_literal '\''%q'\'' "\$BACKUP_DIR"/ { saw_backup=1 }
      in_func && /printf -v data_dir_literal '\''%q'\'' "\$DATA_DIR"/ { saw_data=1 }
      in_func && /^BKSH_HEADER$/ {
        if (!(saw_backup && saw_data)) {
          printf "%s generated NewAPI backup header must shell-quote configured paths\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
  awk '
      /_write_backup_script\(\)/ { in_func=1; saw_backup=0; saw_data=0; saw_config=0; saw_dsn=0; next }
      in_func && /printf -v backup_dir_literal '\''%q'\'' "\$BACKUP_DIR"/ { saw_backup=1 }
      in_func && /printf -v data_dir_literal '\''%q'\'' "\$DATA_DIR"/ { saw_data=1 }
      in_func && /printf -v config_dir_literal '\''%q'\'' "\$CONFIG_DIR"/ { saw_config=1 }
      in_func && /printf -v pg_dsn_literal '\''%q'\'' "\$PG_DSN"/ { saw_dsn=1 }
      in_func && /^BKSH_HEADER$/ {
        if (!(saw_backup && saw_data && saw_config && saw_dsn)) {
          printf "%s generated Sub2API backup header must shell-quote configured paths and DSN\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
  awk '
      /write_backup_script\(\)/ { in_func=1; saw_install=0; saw_backup=0; saw_log=0; next }
      in_func && /printf -v install_dir_literal '\''%q'\'' "\$INSTALL_DIR"/ { saw_install=1 }
      in_func && /printf -v backup_dir_literal '\''%q'\'' "\$BACKUP_DIR"/ { saw_backup=1 }
      in_func && /printf -v log_file_literal '\''%q'\'' "\$\{LOG_DIR\}\/backup\.log"/ { saw_log=1 }
      in_func && /^BACKUP$/ {
        if (!(saw_install && saw_backup && saw_log)) {
          printf "%s generated CyberStrikeAI backup header must shell-quote configured paths\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_generated_backup_scripts_handle_missing_dirs() {
  awk '
      /KEEP_DAYS="\$\{BACKUP_KEEP_DAYS\}"/ { saw_assignment=1; next }
      saw_assignment && index($0, "KEEP_DAYS=0") && index($0, "^[0-9]+$") { saw_guard=1; saw_assignment=0 }
      END {
        if (!saw_guard) {
          printf "%s generated backup script must normalize non-numeric BACKUP_KEEP_DAYS before numeric comparisons\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh impl/install_cyberstrikeai.sh impl/install_vaultwarden.sh
  awk '
      /app\.newapi\.backup\.log\.dir_failed/ { saw_newapi=1 }
      /app\.sub2api\.backup\.log\.dir_failed/ { saw_sub2api=1 }
      /app\.cyberstrikeai\.backup\.error\.backup_dir_create/ { saw_csai=1 }
      /app\.vaultwarden\.backup\.script\.dir_failed/ { saw_vw=1 }
      END {
        if (!(saw_newapi && saw_sub2api && saw_csai && saw_vw)) {
          print "Generated backup scripts must have localized backup-directory creation failure messages." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/newapi.sh apps/sub2api.sh apps/cyberstrikeai.sh apps/vaultwarden.sh
  awk '
      /_write_backup_script\(\)/ { in_func=1; saw_msg=0; saw_mkdir=0; saw_stderr=0; next }
      in_func && /MSG_BACKUP_DIR_FAILED=/ { saw_msg=1 }
      in_func && /if ! mkdir -p "\$\{BACKUP_DIR\}"; then/ { saw_mkdir=1 }
      in_func && /MSG_BACKUP_DIR_FAILED.*>&2/ { saw_stderr=1 }
      in_func && /_log ".*MSG_START/ {
        if (!(saw_msg && saw_mkdir && saw_stderr)) {
          printf "%s generated NewAPI backup script must create the backup directory explicitly before writing backup.log\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
  awk '
      /_write_backup_script\(\)/ { in_func=1; saw_msg=0; saw_mkdir=0; saw_stderr=0; next }
      in_func && /MSG_BACKUP_DIR_FAILED=/ { saw_msg=1 }
      in_func && /if ! mkdir -p "\$\{BACKUP_DIR\}"; then/ { saw_mkdir=1 }
      in_func && /MSG_BACKUP_DIR_FAILED.*>&2/ { saw_stderr=1 }
      in_func && /_log ".*MSG_START/ {
        if (!(saw_msg && saw_mkdir && saw_stderr)) {
          printf "%s generated Sub2API backup script must create the backup directory explicitly before writing backup.log\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
  awk '
      /write_backup_script\(\)/ { in_func=1; saw_msg=0; saw_mkdir=0; saw_stderr=0; next }
      in_func && /MSG_BACKUP_DIR_FAILED=/ { saw_msg=1 }
      in_func && /if ! mkdir -p "\\\$BACKUP_DIR"; then/ { saw_mkdir=1 }
      in_func && /MSG_BACKUP_DIR_FAILED.*>&2/ { saw_stderr=1 }
      in_func && /if \[\[ ! -d "\\\$INSTALL_DIR" \]\]; then/ {
        if (!(saw_msg && saw_mkdir && saw_stderr)) {
          printf "%s generated CyberStrikeAI backup script must create the backup directory explicitly before logging backup failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
  awk '
      /_write_backup_script\(\)/ { in_func=1; saw_msg=0; saw_mkdir=0; saw_stderr=0; saw_maxdepth=0; next }
      in_func && /MSG_BACKUP_DIR_FAILED=/ { saw_msg=1 }
      in_func && index($0, "if ! mkdir -p \"${BACKUP_DIR}\"; then") { saw_mkdir=1 }
      in_func && index($0, "${MSG_BACKUP_DIR_FAILED}") && index($0, ">&2") { saw_stderr=1 }
      in_func && index($0, "find \"${BACKUP_DIR}\" -maxdepth 1 -name \"vaultwarden_*.tar.gz\"") { saw_maxdepth=1 }
      in_func && /mv "\$backup_tmp" "\$backup_script"/ {
        if (!(saw_msg && saw_mkdir && saw_stderr && saw_maxdepth)) {
          printf "%s generated Vaultwarden backup script must create the backup directory explicitly and limit retention cleanup before archiving\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
}

check_manual_backup_retention_is_normalized() {
  awk '
      /^do_backup\(\) \{/ {
        in_func=1
        saw_assignment=0
        saw_guard=0
        saw_positive_guard=0
        saw_find=0
        next
      }
      in_func && /^}/ {
        if (!(saw_assignment && saw_guard && saw_positive_guard && saw_find)) {
          printf "%s NewAPI manual backup retention cleanup must normalize BACKUP_KEEP_DAYS and skip cleanup when it is zero\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
      in_func && /local _keep_days="\$\{BACKUP_KEEP_DAYS\}"/ { saw_assignment=1 }
      in_func && /\[\[ "\$_keep_days" =~ \^\[0-9\]\+\$ \]\] \|\| _keep_days=0/ { saw_guard=1 }
      in_func && /\[\[ "\$_keep_days" -gt 0 \]\]/ { saw_positive_guard=1 }
      in_func && /-mtime "\+\$\{_keep_days\}"/ { saw_find=1 }
    ' impl/install_newapi.sh dist/install_newapi.sh
  awk '
      /^do_backup\(\) \{/ {
        in_func=1
        saw_assignment=0
        saw_guard=0
        saw_positive_guard=0
        saw_find=0
        next
      }
      in_func && /^}/ {
        if (!(saw_assignment && saw_guard && saw_positive_guard && saw_find)) {
          printf "%s Blog manual backup retention cleanup must normalize BLOG_BACKUP_KEEP_DAYS and skip cleanup when it is zero\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
      in_func && /local _keep_days="\$\{BLOG_BACKUP_KEEP_DAYS\}"/ { saw_assignment=1 }
      in_func && /\[\[ "\$_keep_days" =~ \^\[0-9\]\+\$ \]\] \|\| _keep_days=0/ { saw_guard=1 }
      in_func && /\[\[ "\$_keep_days" -gt 0 \]\]/ { saw_positive_guard=1 }
      in_func && /-mtime "\+\$\{_keep_days\}"/ { saw_find=1 }
    ' impl/install_blog.sh dist/install_blog.sh
  awk '
      /^do_backup\(\) \{/ {
        in_func=1
        saw_assignment=0
        saw_guard=0
        saw_positive_guard=0
        saw_find=0
        next
      }
      in_func && /^}/ {
        if (!(saw_assignment && saw_guard && saw_positive_guard && saw_find)) {
          printf "%s Sub2API manual backup retention cleanup must normalize BACKUP_KEEP_DAYS and skip cleanup when it is zero\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
      in_func && /local _keep_days="\$\{BACKUP_KEEP_DAYS\}"/ { saw_assignment=1 }
      in_func && /\[\[ "\$_keep_days" =~ \^\[0-9\]\+\$ \]\] \|\| _keep_days=0/ { saw_guard=1 }
      in_func && /\[\[ "\$_keep_days" -gt 0 \]\]/ { saw_positive_guard=1 }
      in_func && /-mtime "\+\$\{_keep_days\}"/ { saw_find=1 }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_backup_retention_cleanup_reports_failures() {
  if grep -R -nE 'rm -f "\$f" && [^|]+ \|\| true|find "\\?\$BACKUP_DIR" -maxdepth 1 .* -delete 2>/dev/null \|\| true' \
      impl/install_newapi.sh impl/install_sub2api.sh impl/install_cyberstrikeai.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "Backup retention cleanup must report per-file removal failures instead of ignoring them." >&2
    return 1
  fi
  awk '
      /app\.newapi\.backup\.log\.remove_failed/ { saw_newapi_log_key=1 }
      /app\.newapi\.warn\.backup_cleanup_failed/ { saw_newapi_warn_key=1 }
      /app\.sub2api\.backup\.log\.remove_failed/ { saw_sub2api_log_key=1 }
      /app\.sub2api\.warn\.backup_cleanup_failed/ { saw_sub2api_warn_key=1 }
      /app\.cyberstrikeai\.backup\.warn\.remove_failed/ { saw_csai_log_key=1 }
      END {
        if (!(saw_newapi_log_key && saw_newapi_warn_key && saw_sub2api_log_key && saw_sub2api_warn_key && saw_csai_log_key)) {
          print "Backup cleanup failure messages must be localized." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/newapi.sh apps/sub2api.sh apps/cyberstrikeai.sh
  awk '
      /MSG_REMOVE_FAILED="\$\{msg_remove_failed\}"/ { saw_msg=1 }
      /_log "\$\(printf "\$MSG_REMOVE_FAILED" "\$f"\)"/ { saw_log=1 }
      /warn "\$\(t app\.newapi\.warn\.backup_cleanup_failed "\$f"\)"/ { saw_warn=1 }
      END {
        if (!(saw_msg && saw_log && saw_warn)) {
          printf "%s NewAPI backup retention cleanup must log generated-script failures and warn for manual backup cleanup failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
  awk '
      /MSG_REMOVE_FAILED="\$\{msg_remove_failed\}"/ { saw_msg=1 }
      /_log "\$\(printf "\$MSG_REMOVE_FAILED" "\$f"\)"/ { saw_log=1 }
      END {
        if (!(saw_msg && saw_log)) {
          printf "%s Sub2API generated backup retention cleanup must log per-file removal failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
  awk '
      /^do_backup\(\) \{/ { in_backup=1; saw_warn=0; saw_info=0; saw_pattern=0; next }
      in_backup && /warn "\$\(t app\.sub2api\.warn\.backup_cleanup_failed "\$_old_backup"\)"/ { saw_warn=1 }
      in_backup && /info "\$\(t app\.sub2api\.info\.cleaned_old_backups "\$_cleaned" "\$_keep_days"\)"/ { saw_info=1 }
      in_backup && /-name "sub2api_db_\*\.sql\.gz"/ { saw_pattern=1 }
      in_backup && /success "\$\(t app\.sub2api\.success\.backup_done "\$BACKUP_DIR"\)"/ {
        if (!(saw_warn && saw_info && saw_pattern)) {
          printf "%s Sub2API manual backup retention cleanup must report per-file failures and include database backup archives\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_backup=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
  awk '
      /MSG_REMOVE_FAILED="\$\{msg_remove_failed\}"/ { saw_msg=1 }
      index($0, "_log \"[WARN] \\$(printf \"\\$MSG_REMOVE_FAILED\" \"\\$old_backup\")\"") { saw_log=1 }
      END {
        if (!(saw_msg && saw_log)) {
          printf "%s CyberStrikeAI generated backup retention cleanup must log per-file removal failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_optional_count_messages_are_nonfatal() {
  if grep -R -nE '\[\[ (\$\{?REMOVED\}?|\$_cleaned|\$_cleaned_old|\$_cleaned_wv|\$_cnt) -(gt|eq) 0 \]\] &&' \
      impl/install_newapi.sh impl/install_sub2api.sh impl/install_vaultwarden.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "Optional count-based status messages must use explicit if branches so zero counts do not trip set -e." >&2
    return 1
  fi
}

check_silent_backup_tar_diagnostics_use_stderr() {
  if grep -R -n '2>&1 >&2; then' \
      impl/install_newapi.sh impl/install_sub2api.sh impl/install_vaultwarden.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "Silent backup tar diagnostics must be written directly to stderr." >&2
    return 1
  fi
  awk '
      /_backup_silent\(\)/ { in_func=1; saw_tar=0; saw_stderr=0; next }
      in_func && /if tar -czf/ { saw_tar=1 }
      in_func && / >&2; then/ { saw_stderr=1 }
      in_func && /^}/ {
        if (!(saw_tar && saw_stderr)) {
          printf "%s silent backup helper must send tar diagnostics to stderr\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh impl/install_vaultwarden.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_vaultwarden.sh
}

check_tar_diagnostics_use_stderr() {
  if grep -R -nE 'tar -(czf|xzf) .*2>&1; then' \
      impl/install_newapi.sh impl/install_sub2api.sh impl/install_vaultwarden.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "Tar diagnostics in backup and extract paths must be written to stderr." >&2
    return 1
  fi
  awk '
      /extract_and_verify\(\)/ { in_extract=1; saw_stderr=0; next }
      in_extract && /tar -xzf "\$archive" -C "\$tmp_extract" >&2/ { saw_stderr=1 }
      in_extract && /^}/ {
        if (!saw_stderr) {
          printf "%s Sub2API extract helper must send tar diagnostics to stderr\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_extract=0
      }
      /do_backup\(\)/ { in_backup=1; saw_tar_stderr=0; next }
      in_backup && /if tar -czf "\$ARCHIVE_TMP"/ { saw_tar_start=1 }
      in_backup && / >&2; then/ { saw_tar_stderr=1 }
      in_backup && /while IFS= read -r f; do/ {
        if (saw_tar_start && !saw_tar_stderr) {
          printf "%s manual backup helper must send tar diagnostics to stderr\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_backup=0
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
  awk '
      /do_backup\(\)/ { in_backup=1; saw_conf_stderr=0; saw_data_stderr=0; next }
      in_backup && /if tar -czf "\$CONF_TMP"/ { in_conf=1; next }
      in_conf && / >&2; then/ { saw_conf_stderr=1; in_conf=0 }
      in_backup && /if tar -czf "\$DATA_TMP"/ { in_data=1; next }
      in_data && / >&2; then/ { saw_data_stderr=1; in_data=0 }
      in_backup && /release_lock/ {
        if (!(saw_conf_stderr && saw_data_stderr)) {
          printf "%s Sub2API manual backup tar diagnostics must go to stderr\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_backup=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
  awk '
      /ARCHIVE_TMP="\$\{ARCHIVE\}\.tmp"/ { in_script=1; saw_tar_stderr=0; next }
      in_script && /TAR_EXTRA.*>&2; then/ { saw_tar_stderr=1 }
      in_script && /printf .*\$\{MSG_SUCCESS\}/ {
        if (!saw_tar_stderr) {
          printf "%s Vaultwarden backup script must send tar diagnostics to stderr\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_script=0
      }
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
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
      /if ! mkdir -p \/etc\/nginx\/sites-available \/etc\/nginx\/sites-enabled; then/ { saw_nginx_dirs=1 }
      /_write_nginx_config_file\(\)/ { in_func=1; saw_atomic=0; saw_error=0; next }
      in_func && /atomic_write_file "\$(nginx_conf|NGINX_CONF)" 644 root:root/ { saw_atomic=1 }
      in_func && /error "\$\(t app\.(sub2api|cyberstrikeai|vaultwarden|blog)\.error\.(nginx_config_write|nginx|nginx_write|nginx_conf)/ { saw_error=1 }
      in_func && /^}/ {
        if (!(saw_atomic && saw_error)) {
          printf "%s Nginx config helper must use atomic_write_file and report failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
      /_write_nginx_config_file "\$NGINX_CONF"/ { saw_helper=1 }
      /_write_nginx_config_file "\$nginx_conf"/ { saw_helper=1 }
      END {
        if (!(saw_nginx_dirs && saw_helper)) {
          print "Nginx site config writes must prepare directories and use _write_nginx_config_file." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_sub2api.sh impl/install_cyberstrikeai.sh impl/install_vaultwarden.sh impl/install_blog.sh \
      dist/install_sub2api.sh dist/install_cyberstrikeai.sh dist/install_vaultwarden.sh dist/install_blog.sh
  awk '
      /_write_nginx_site_link\(\)/ { in_func=1; saw_atomic=0; saw_error=0; next }
      in_func && /atomic_symlink "\$target" "\$link_path"/ { saw_atomic=1 }
      in_func && /error "\$\(t app\.(blog|sub2api|cyberstrikeai|vaultwarden)\.error\.(nginx_write|nginx_config_write|nginx)/ { saw_error=1 }
      in_func && /^}/ {
        if (!(saw_atomic && saw_error)) {
          printf "%s Nginx site link helper must use atomic_symlink and report failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_sub2api.sh impl/install_cyberstrikeai.sh impl/install_vaultwarden.sh impl/install_blog.sh \
      dist/install_sub2api.sh dist/install_cyberstrikeai.sh dist/install_vaultwarden.sh dist/install_blog.sh
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

check_sub2api_nginx_reload_results_are_checked() {
  if grep -R -n 'nginx -t 2>/dev/null; then[[:space:]]*$' \
      impl/install_sub2api.sh dist/install_sub2api.sh 2>/dev/null | grep -v 'if nginx -t 2>/dev/null; then'; then
    echo "Sub2API nginx apply path must keep the nginx test as an explicit conditional." >&2
    return 1
  fi
  if grep -R -n '^[[:space:]]*systemctl reload nginx$' \
      impl/install_sub2api.sh dist/install_sub2api.sh 2>/dev/null; then
    echo "Sub2API nginx apply path must validate nginx reload results." >&2
    return 1
  fi
  awk '
      /if nginx -t 2>\/dev\/null; then/ { in_block=1; saw_reload_if=0; saw_domain_success=0; saw_fallback_success=0; saw_reload_warn=0; next }
      in_block && /if systemctl reload nginx; then/ { saw_reload_if=1 }
      in_block && /success "\$\(t app\.sub2api\.success\.nginx_domain "\$SUB2API_DOMAIN" "\$PORT"\)"/ { saw_domain_success=1 }
      in_block && /success "\$\(t app\.sub2api\.success\.nginx_fallback "\$PORT"\)"/ { saw_fallback_success=1 }
      in_block && /warn "\$\(t app\.sub2api\.warn\.nginx_reload_failed\)"/ { saw_reload_warn=1 }
      in_block && /warn "\$\(t app\.sub2api\.warn\.nginx_test_failed\)"/ {
        if (!(saw_reload_if && saw_domain_success && saw_fallback_success && saw_reload_warn)) {
          printf "%s Sub2API nginx apply path must branch on reload failure before reporting success\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_sub2api_postgres_rpm_setup_failures_are_explicit() {
  if grep -R -nE 'dnf install -y "\$pgdg_rpm" 2>/dev/null \|\| true|dnf -qy module disable postgresql 2>/dev/null \|\| true|yum install -y "\$pgdg_rpm" 2>/dev/null \|\| true|/usr/pgsql-15/bin/postgresql-15-setup initdb 2>/dev/null \|\| true' \
      impl/install_sub2api.sh dist/install_sub2api.sh 2>/dev/null; then
    echo "Sub2API PostgreSQL RPM setup must not suppress repository, module, or initdb failures." >&2
    return 1
  fi
  awk '
      /\[\[ "\$PKG_MANAGER" == "dnf" \|\| "\$PKG_MANAGER" == "yum" \]\]/ { in_block=1; saw_repo=0; saw_module=0; saw_initdb_guard=0; saw_initdb=0; next }
      in_block && /dnf install -y "\$pgdg_rpm" \|\| error "\$\(t app\.sub2api\.error\.postgres_repo\)"/ { saw_repo=1 }
      in_block && /dnf -qy module disable postgresql \|\| error "\$\(t app\.sub2api\.error\.postgres_module\)"/ { saw_module=1 }
      in_block && /yum install -y "\$pgdg_rpm" \|\| error "\$\(t app\.sub2api\.error\.postgres_repo\)"/ { saw_repo=1 }
      in_block && /if \[\[ ! -f "\$pg_data_version" \]\]; then/ { saw_initdb_guard=1 }
      in_block && /\/usr\/pgsql-15\/bin\/postgresql-15-setup initdb \|\| error "\$\(t app\.sub2api\.error\.postgres_initdb\)"/ { saw_initdb=1 }
      in_block && /success "\$\(t app\.sub2api\.success\.postgres15\)"/ {
        if (!(saw_repo && saw_initdb_guard && saw_initdb)) {
          printf "%s Sub2API PostgreSQL RPM setup must fail explicitly when repository install or initdb fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        if (!saw_module) {
          printf "%s Sub2API dnf path must fail explicitly when module disable fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_sub2api_dependency_services_start_before_success() {
  if grep -R -nE 'systemctl start postgresql 2>/dev/null \|\|[[:space:]\\]*systemctl start "postgresql-\$\{pg_ver\}" 2>/dev/null \|\||systemctl start postgresql 2>/dev/null \|\|[[:space:]\\]*systemctl start postgresql-15 2>/dev/null \|\|' \
      impl/install_sub2api.sh dist/install_sub2api.sh 2>/dev/null; then
    echo "Sub2API PostgreSQL startup fallbacks must use explicit conditionals." >&2
    return 1
  fi
  if grep -R -nE 'success "\$\(t app\.sub2api\.success\.(postgres_exists|redis_exists)[^"]*"\)[[:space:]]*$' \
      impl/install_sub2api.sh dist/install_sub2api.sh 2>/dev/null; then
    awk '
        /if \[\[ "\$pg_ver" -ge 15 \]\]; then/ { in_pg=1; saw_ensure=0; next }
        in_pg && /_ensure_postgres_running "\$pg_ver"/ { saw_ensure=1 }
        in_pg && /success "\$\(t app\.sub2api\.success\.postgres_exists "\$pg_ver"\)"/ {
          if (!saw_ensure) {
            printf "%s Sub2API must ensure PostgreSQL is running before reporting an existing installation as ready\n", FILENAME > "/dev/stderr"
            exit 1
          }
          in_pg=0
        }
        /if \[\[ "\$redis_ver" -ge 7 \]\]; then/ { in_redis=1; saw_redis_ensure=0; next }
      in_redis && /_ensure_redis_running \|\| error "\$\(t app\.sub2api\.error\.redis_start\)"/ { saw_redis_ensure=1 }
      in_redis && /success "\$\(t app\.sub2api\.success\.redis_exists "\$redis_ver"\)"/ {
        if (!saw_redis_ensure) {
            printf "%s Sub2API must ensure Redis is running before reporting an existing installation as ready\n", FILENAME > "/dev/stderr"
            exit 1
          }
          in_redis=0
        }
      ' impl/install_sub2api.sh dist/install_sub2api.sh
  fi
  awk '
      /_ensure_postgres_running\(\)/ { saw_pg_helper=1 }
      /if systemctl start postgresql 2>\/dev\/null; then/ { saw_pg_start_if=1 }
      /if systemctl start "postgresql-\$\{pg_ver\}" 2>\/dev\/null; then/ { saw_pg_version_start_if=1 }
      /_ensure_redis_running\(\)/ { saw_redis_helper=1 }
      /app\.sub2api\.error\.redis_start/ { saw_redis_error=1 }
      /if ! systemctl start postgresql 2>\/dev\/null/ { saw_pg_setup_if=1 }
      /! systemctl start postgresql-15 2>\/dev\/null; then/ { saw_pg_setup_fallback=1 }
      END {
        if (!(saw_pg_helper && saw_pg_start_if && saw_pg_version_start_if && saw_pg_setup_if && saw_pg_setup_fallback && saw_redis_helper && saw_redis_error)) {
          print "Sub2API must keep explicit helpers and error reporting for PostgreSQL and Redis service startup." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh apps/sub2api.sh dist/install_sub2api.sh
}

check_sub2api_nginx_install_starts_service_explicitly() {
  if grep -R -nE 'systemctl start nginx 2>/dev/null \|\| true|systemctl start nginx 2>/dev/null \|\| error "\$\(t app\.sub2api\.error\.nginx_start\)"' \
      impl/install_sub2api.sh dist/install_sub2api.sh 2>/dev/null; then
    echo "Sub2API nginx installation must not suppress nginx start failures." >&2
    return 1
  fi
  awk '
      /app\.sub2api\.error\.nginx_install/ { saw_install_key=1 }
      /apt-get install -y nginx/ { saw_apt_guidance=1 }
      /dnf install -y nginx/ { saw_dnf_guidance=1 }
      /yum install -y nginx/ { saw_yum_guidance=1 }
      /_ensure_nginx_running\(\)/ { saw_helper=1 }
      /app\.sub2api\.error\.nginx_start/ { saw_error=1 }
      /if ! systemctl start nginx 2>\/dev\/null; then/ { saw_start_if=1 }
      /if ! systemctl is-active --quiet nginx 2>\/dev\/null; then/ { saw_active_if=1 }
      /_install_nginx\(\)/ { in_block=1; saw_ensure=0; saw_success=0; next }
      in_block && /if ! DEBIAN_FRONTEND=noninteractive apt-get install -y nginx; then/ { saw_apt_if=1 }
      in_block && /dnf install -y nginx \|\| error "\$\(t app\.sub2api\.error\.nginx_install\)"/ { saw_dnf_if=1 }
      in_block && /yum install -y nginx \|\| error "\$\(t app\.sub2api\.error\.nginx_install\)"/ { saw_yum_if=1 }
      in_block && /error "\$\(t app\.sub2api\.error\.nginx_install\)"/ { saw_install_error=1 }
      in_block && /_ensure_nginx_running/ { saw_ensure=1 }
      in_block && /success "\$\(t app\.sub2api\.success\.nginx_installed\)"/ { saw_success=1 }
      in_block && /^}/ {
        if (!(saw_install_key && saw_apt_guidance && saw_dnf_guidance && saw_yum_guidance && saw_helper && saw_error && saw_start_if && saw_active_if && saw_apt_if && saw_dnf_if && saw_yum_if && saw_install_error && saw_ensure && saw_success)) {
          printf "%s Sub2API nginx installation must fail explicitly on package install errors and ensure the service starts before reporting success\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh apps/sub2api.sh dist/install_sub2api.sh
}

check_newapi_service_start_paths_are_explicit() {
  if grep -R -nE '^[[:space:]]*systemctl (start|restart) "\$SERVICE_NAME"$' \
      impl/install_newapi.sh dist/install_newapi.sh 2>/dev/null; then
    echo "NewAPI service start/restart paths must branch explicitly on command failure." >&2
    return 1
  fi
  awk '
      /if ! systemctl enable "\$SERVICE_NAME" --quiet; then/ { in_install=1; saw_restart_wait=0; next }
      in_install && /if systemctl restart "\$SERVICE_NAME" && wait_for_service "\$SERVICE_NAME" 20; then/ { saw_restart_wait=1 }
      in_install && /warn "\$\(t app\.newapi\.warn\.start_rollback\)"/ {
        if (!saw_restart_wait) {
          printf "%s NewAPI install must gate service success on an explicit restart-and-wait branch\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_install=0
      }
      /systemctl daemon-reload/ && !seen_reload++ { next }
      /if ! _install_binary_candidate "\$TMP_BIN"; then/ { in_update=1; saw_start_wait=0; next }
      in_update && /if systemctl start "\$SERVICE_NAME" && wait_for_service "\$SERVICE_NAME" 20; then/ { saw_start_wait=1 }
      in_update && /warn "\$\(t app\.newapi\.warn\.update_start_failed "\$LATEST" "\$CURRENT"\)"/ {
        if (!saw_start_wait) {
          printf "%s NewAPI update must gate service success on an explicit start-and-wait branch\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_update=0
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
}

check_cyberstrikeai_service_start_paths_are_explicit() {
  if grep -R -nE '^[[:space:]]*systemctl restart "\$SERVICE_NAME"$' \
      impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "CyberStrikeAI service restart paths must branch explicitly on command failure." >&2
    return 1
  fi
  awk '
      /step "\$\(t app\.cyberstrikeai\.step\.start\)"/ { in_start=1; saw_restart_wait=0; next }
      in_start && /if systemctl restart "\$SERVICE_NAME" && wait_for_service "\$SERVICE_NAME" 35; then/ { saw_restart_wait=1 }
      in_start && /journalctl -u "\$SERVICE_NAME" -n 40 --no-pager >&2 \|\| true/ {
        if (!saw_restart_wait) {
          printf "%s CyberStrikeAI startup must gate success on an explicit restart-and-wait branch\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_start=0
      }
      /step "\$\(t app\.cyberstrikeai\.step\.restart_updated\)"/ { in_update=1; saw_restart_wait2=0; next }
      in_update && /if systemctl restart "\$SERVICE_NAME" && wait_for_service "\$SERVICE_NAME" 35; then/ { saw_restart_wait2=1 }
      in_update && /warn "\$\(t app\.cyberstrikeai\.warn\.update_start_failed\)"/ {
        if (!saw_restart_wait2) {
          printf "%s CyberStrikeAI update must gate service success on an explicit restart-and-wait branch\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_update=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_sub2api_enable_failures_are_reported() {
  if grep -R -nE 'systemctl enable postgresql 2>/dev/null \|\| true|systemctl enable postgresql-15 2>/dev/null \|\| true|systemctl enable "postgresql-\$\{pg_ver\}" 2>/dev/null \|\| true' \
      impl/install_sub2api.sh dist/install_sub2api.sh 2>/dev/null; then
    echo "Sub2API service enable failures must not be silently ignored." >&2
    return 1
  fi
  awk '
      /app\.sub2api\.warn\.service_enable_failed/ { saw_warn_key=1 }
      /if ! systemctl enable postgresql 2>\/dev\/null &&/ { saw_existing_pg=1 }
      /warn "\$\(t app\.sub2api\.warn\.service_enable_failed "postgresql-\$\{pg_ver\}" "postgresql-\$\{pg_ver\}"\)"/ { saw_existing_pg_warn=1 }
      /if ! systemctl enable postgresql 2>\/dev\/null; then/ { saw_apt_pg=1 }
      /warn "\$\(t app\.sub2api\.warn\.service_enable_failed "postgresql" "postgresql"\)"/ { saw_apt_pg_warn=1 }
      /if ! systemctl enable postgresql-15 2>\/dev\/null; then/ { saw_rpm_pg=1 }
      /warn "\$\(t app\.sub2api\.warn\.service_enable_failed "postgresql-15" "postgresql-15"\)"/ { saw_rpm_pg_warn=1 }
      /if ! systemctl enable nginx; then/ { saw_nginx=1 }
      /warn "\$\(t app\.sub2api\.warn\.service_enable_failed "nginx" "nginx"\)"/ { saw_nginx_warn=1 }
      /if ! systemctl enable "\$SERVICE_NAME" --quiet; then/ { saw_service=1 }
      /warn "\$\(t app\.sub2api\.warn\.service_enable_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_service_warn=1 }
      END {
        if (!(saw_warn_key && saw_existing_pg && saw_existing_pg_warn && saw_apt_pg && saw_apt_pg_warn && saw_rpm_pg && saw_rpm_pg_warn && saw_nginx && saw_nginx_warn && saw_service && saw_service_warn)) {
          print "Sub2API must warn when service enablement fails for PostgreSQL, Nginx, or the app service." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/sub2api.sh impl/install_sub2api.sh dist/install_sub2api.sh
}

check_sub2api_service_start_paths_are_explicit() {
  if grep -R -nE '^[[:space:]]*systemctl (start|restart) "\$SERVICE_NAME"$' \
      impl/install_sub2api.sh dist/install_sub2api.sh 2>/dev/null; then
    echo "Sub2API service start/restart paths must branch explicitly on command failure." >&2
    return 1
  fi
  awk '
      /if ! systemctl enable "\$SERVICE_NAME" --quiet; then/ { in_install=1; saw_restart_wait=0; next }
      in_install && /if systemctl restart "\$SERVICE_NAME" && wait_for_service "\$SERVICE_NAME" 25; then/ { saw_restart_wait=1 }
      in_install && /if systemctl is-failed --quiet "\$SERVICE_NAME" 2>\/dev\/null; then/ {
        if (!saw_restart_wait) {
          printf "%s Sub2API install must gate service success on an explicit restart-and-wait branch\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_install=0
      }
      /if ! _install_binary_candidate "\$TMP_BIN"; then/ { in_update=1; saw_start_wait=0; next }
      in_update && /if systemctl start "\$SERVICE_NAME" && wait_for_service "\$SERVICE_NAME" 25; then/ { saw_start_wait=1 }
      in_update && /warn "\$\(t app\.sub2api\.warn\.new_version_failed "\$LATEST" "\$CURRENT"\)"/ {
        if (!saw_start_wait) {
          printf "%s Sub2API update must gate service success on an explicit start-and-wait branch\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_update=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_sub2api_redis_service_handling_is_explicit() {
  if grep -R -n 'systemctl enable --now redis-server 2>/dev/null' \
      impl/install_sub2api.sh dist/install_sub2api.sh 2>/dev/null; then
    echo "Sub2API Redis helper must not conflate service startup with enablement." >&2
    return 1
  fi
  awk '
      /_ensure_redis_running\(\)/ { in_helper=1; saw_probe_loop=0; saw_start_loop=0; saw_enable_warn=0; next }
      in_helper && /for redis_unit in redis-server redis; do/ { saw_loop_count++; next }
      in_helper && /if systemctl is-active --quiet "\$redis_unit" 2>\/dev\/null; then/ { saw_probe_loop=1 }
      in_helper && /if systemctl start "\$redis_unit" 2>\/dev\/null; then/ { saw_start_loop=1 }
      in_helper && /warn "\$\(t app\.sub2api\.warn\.service_enable_failed "\$redis_unit" "\$redis_unit"\)"/ { saw_enable_warn=1 }
      in_helper && /^}/ {
        if (!(saw_loop_count >= 2 && saw_probe_loop && saw_start_loop && saw_enable_warn)) {
          printf "%s Sub2API Redis helper must probe units, start them explicitly, and warn on enable failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_helper=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_blog_enable_failures_are_reported() {
  awk '
      /app\.blog\.warn\.service_enable_failed/ { saw_warn_key=1 }
      /if ! systemctl enable nginx --quiet; then/ { saw_enable_if=1 }
      /warn "\$\(t app\.blog\.warn\.service_enable_failed "nginx" "nginx"\)"/ { saw_warn=1 }
      END {
        if (!(saw_warn_key && saw_enable_if && saw_warn)) {
          print "Blog must warn when Nginx service enablement fails." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/blog.sh impl/install_blog.sh dist/install_blog.sh
}

check_blog_nginx_start_path_is_explicit() {
  if grep -R -n '^systemctl restart nginx$' \
      impl/install_blog.sh dist/install_blog.sh 2>/dev/null; then
    echo "Blog nginx startup must branch explicitly on restart failure." >&2
    return 1
  fi
  awk '
      /wait_for_service\(\)/ { in_helper=1; saw_active=0; saw_loop=0; next }
      in_helper && /while \(\( elapsed < timeout \)\); do/ { saw_loop=1 }
      in_helper && /systemctl is-active --quiet "\$service"/ { saw_active=1 }
      in_helper && /^}/ { in_helper=0 }
      /step "\$\(t app\.blog\.step_start_nginx\)"/ { in_block=1; saw_restart_if=0; saw_wait=0; next }
      in_block && /if systemctl restart nginx && wait_for_service nginx 10; then/ { saw_restart_if=1; saw_wait=1 }
      in_block && /step "\$\(t app\.blog\.step_health\)"/ {
        if (!(saw_loop && saw_active && saw_restart_if && saw_wait)) {
          printf "%s Blog nginx startup must use an explicit restart-and-wait branch before the health check\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_blog.sh dist/install_blog.sh
}

check_blog_install_summary_matches_local_health() {
  awk '
      /app\.blog\.http_warn/ { saw_warn=1 }
      /local Nginx probe/ { saw_probe_text=1 }
      /app\.blog\.summary_title_ready/ { saw_title_ready=1 }
      /app\.blog\.summary_title_pending/ { saw_title_pending=1 }
      END {
        if (!(saw_warn && saw_probe_text && saw_title_ready && saw_title_pending)) {
          print "Blog health guidance must describe the local probe and distinguish ready vs pending summaries." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/blog.sh
  awk '
      /step "\$\(t app\.blog\.step_health\)"/ { in_health=1; saw_state=0; saw_host_header=0; saw_pending=0; saw_pending_title=0; saw_ready_title=0; next }
      in_health && /local _blog_summary_state="ready"/ { saw_state=1 }
      in_health && /curl -H "Host: \$\{BLOG_DOMAIN:-localhost\}"/ { saw_host_header=1 }
      in_health && /_blog_summary_state="pending"/ { saw_pending=1 }
      in_health && /app\.blog\.summary_title_pending/ { saw_pending_title=1 }
      in_health && /app\.blog\.summary_title_ready/ { saw_ready_title=1 }
      in_health && /echo "  ╚══════════════════════════════════════════════════════╝"/ {
        if (!(saw_state && saw_host_header && saw_pending && saw_pending_title && saw_ready_title)) {
          printf "%s Blog install summary must track local health state and probe the configured host locally\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_health=0
      }
    ' impl/install_blog.sh dist/install_blog.sh
}

check_newapi_enable_failures_are_reported() {
  awk '
      /app\.newapi\.warn\.service_enable_failed/ { saw_warn_key=1 }
      /if ! systemctl enable "\$SERVICE_NAME" --quiet; then/ { saw_enable_if=1 }
      /warn "\$\(t app\.newapi\.warn\.service_enable_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_warn=1 }
      END {
        if (!(saw_warn_key && saw_enable_if && saw_warn)) {
          print "NewAPI must warn when service enablement fails." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/newapi.sh impl/install_newapi.sh dist/install_newapi.sh
}

check_newapi_manual_backup_wal_result_is_explicit() {
  if grep -R -n '&& success "\$\(t app\.newapi\.success\.wal\)"' \
      impl/install_newapi.sh dist/install_newapi.sh 2>/dev/null; then
    echo "NewAPI manual backup WAL checkpoint must use explicit conditionals." >&2
    return 1
  fi
  awk '
      /step "\$\(t app\.newapi\.step\.manual_backup\)"/ { in_backup=1; saw_dir_if=0; saw_dir_error=0; saw_wal_if=0; saw_wal_success=0; saw_wal_warn=0; next }
      in_backup && /if ! mkdir -p "\$BACKUP_DIR"; then/ { saw_dir_if=1 }
      in_backup && /error "\$\(t app\.newapi\.error\.backup_dir_create "\$BACKUP_DIR"\)"/ { saw_dir_error=1 }
      in_backup && /if sqlite3 "\$DB_FILE" "PRAGMA wal_checkpoint\(TRUNCATE\);" 2>\/dev\/null; then/ { saw_wal_if=1 }
      in_backup && /success "\$\(t app\.newapi\.success\.wal\)"/ { saw_wal_success=1 }
      in_backup && /warn "\$\(t app\.newapi\.warn\.wal\)"/ { saw_wal_warn=1 }
      in_backup && /local _ic/ {
        if (!(saw_dir_if && saw_dir_error && saw_wal_if && saw_wal_success && saw_wal_warn)) {
          printf "%s NewAPI manual backup must fail explicitly when the backup directory cannot be created, and must branch on WAL checkpoint results before integrity checks\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_backup=0
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
}

check_cyberstrikeai_enable_failures_are_reported() {
  awk '
      /app\.cyberstrikeai\.warn\.service_enable_failed/ { saw_warn_key=1 }
      /if ! systemctl enable "\$SERVICE_NAME" --quiet; then/ { saw_service_if=1 }
      /warn "\$\(t app\.cyberstrikeai\.warn\.service_enable_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_service_warn=1 }
      /if ! systemctl enable nginx --quiet; then/ { saw_nginx_if=1 }
      /warn "\$\(t app\.cyberstrikeai\.warn\.service_enable_failed "nginx" "nginx"\)"/ { saw_nginx_warn=1 }
      END {
        if (!(saw_warn_key && saw_service_if && saw_service_warn && saw_nginx_if && saw_nginx_warn)) {
          print "CyberStrikeAI must warn when service enablement fails for the app service or Nginx." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/cyberstrikeai.sh impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
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
    ' apps/vaultwarden.sh impl/install_vaultwarden.sh dist/install_vaultwarden.sh
}

check_vaultwarden_certbot_cron_failures_are_reported() {
  awk '
      /app\.vaultwarden\.error\.certbot_cron/ { saw_error_key=1 }
      /30 2 \* \* \* certbot renew --quiet --post-hook/ { saw_guidance=1 }
      /if crontab -l 2>\/dev\/null \| grep -q "certbot renew"; then/ { in_block=1; saw_write_if=0; saw_error=0; next }
      in_block && /if ! \(crontab -l 2>\/dev\/null; echo "30 2 \* \* \* certbot renew --quiet --post-hook '\''systemctl reload nginx'\''"\) \| crontab -; then/ { saw_write_if=1 }
      in_block && /error "\$\(t app\.vaultwarden\.error\.certbot_cron\)"/ { saw_error=1 }
      in_block && /success "\$\(t app\.vaultwarden\.success\.certbot_cron\)"/ {
        if (!(saw_error_key && saw_guidance && saw_write_if && saw_error)) {
          printf "%s Vaultwarden must fail explicitly with manual guidance when writing the Certbot auto-renew crontab entry fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' apps/vaultwarden.sh impl/install_vaultwarden.sh dist/install_vaultwarden.sh
}

check_vaultwarden_runtime_service_starts_are_explicit() {
  if grep -R -nE '^[[:space:]]*systemctl restart (nginx|fail2ban)$' \
      impl/install_vaultwarden.sh dist/install_vaultwarden.sh 2>/dev/null; then
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
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
}

check_vaultwarden_service_start_paths_are_explicit() {
  if grep -R -nE '^[[:space:]]*systemctl start vaultwarden$' \
      impl/install_vaultwarden.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "Vaultwarden service start paths must branch explicitly on command failure." >&2
    return 1
  fi
  awk '
      /warn "\$\(t app\.vaultwarden\.warn\.port_hint\)"/ { in_install=1; saw_start_wait=0; next }
      in_install && /if systemctl start vaultwarden && wait_for_service vaultwarden 20; then/ { saw_start_wait=1 }
      in_install && /warn "\$\(t app\.vaultwarden\.warn\.service_cleanup\)"/ {
        if (!saw_start_wait) {
          printf "%s Vaultwarden install must gate service success on an explicit start-and-wait branch\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_install=0
      }
      /warn "\$\(t app\.vaultwarden\.warn\.update_port_used "\$VW_PORT" "\$_port_owner_upd"\)"/ { in_update=1; saw_start_wait2=0; saw_start_wait3=0; next }
      in_update && /if systemctl start vaultwarden && wait_for_service vaultwarden 20; then/ {
        if (!saw_start_wait2) {
          saw_start_wait2=1
        } else {
          saw_start_wait3=1
        }
      }
      in_update && /error "\$\(t app\.vaultwarden\.error\.update_rolled_back "\$OLD_VER" "\$_backup_kept"\)"/ {
        if (!(saw_start_wait2 && saw_start_wait3)) {
          printf "%s Vaultwarden update must gate both primary restart and rollback restart on explicit start-and-wait branches\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_update=0
      }
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
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
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
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
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
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
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
}

check_newapi_update_rollbacks_report_restart_failures() {
  if grep -R -n 'systemctl start "\$SERVICE_NAME" 2>/dev/null || true' \
      impl/install_newapi.sh dist/install_newapi.sh 2>/dev/null; then
    echo "NewAPI update rollback paths must not suppress service restart failures." >&2
    return 1
  fi
  awk '
      /if ! _install_binary_candidate "\$TMP_BIN"; then/ { in_install_failure=1; saw_restore=0; saw_start_if=0; saw_warn=0; next }
      in_install_failure && /if _restore_binary_backup "\$BAK_PATH"; then/ { saw_restore=1 }
      in_install_failure && /if ! systemctl start "\$SERVICE_NAME"; then/ { saw_start_if=1 }
      in_install_failure && /warn "\$\(t app\.newapi\.warn\.rollback_start_failed "\$SERVICE_NAME"\)"/ { saw_warn=1 }
      in_install_failure && /error "\$\(t app\.newapi\.error\.binary_install "\$BIN_PATH"\)"/ {
        if (!(saw_restore && saw_start_if && saw_warn)) {
          printf "%s NewAPI binary-install rollback must warn when service restart fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_install_failure=0
      }
      /warn "\$\(t app\.newapi\.warn\.update_start_failed "\$LATEST" "\$CURRENT"\)"/ { in_update_failure=1; saw_restore2=0; saw_start_if2=0; saw_wait=0; saw_warn2=0; next }
      in_update_failure && /if ! _restore_binary_backup "\$BAK_PATH"; then/ { saw_restore2=1 }
      in_update_failure && /if systemctl start "\$SERVICE_NAME"; then/ { saw_start_if2=1 }
      in_update_failure && /if wait_for_service "\$SERVICE_NAME" 15; then/ { saw_wait=1 }
      in_update_failure && /warn "\$\(t app\.newapi\.warn\.rollback_start_failed "\$SERVICE_NAME"\)"/ { saw_warn2=1 }
      in_update_failure && saw_start_if2 && /error "\$\(t app\.newapi\.error\.update_failed "\$CURRENT" "\$SERVICE_NAME" "\$BAK_PATH"\)"/ {
        if (!(saw_restore2 && saw_start_if2 && saw_wait && saw_warn2)) {
          printf "%s NewAPI update rollback must branch explicitly on restart failures before reporting rollback outcome\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_update_failure=0
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
}

check_newapi_install_cleanup_reports_systemctl_failures() {
  awk '
      /app\.newapi\.warn\.cleanup_stop_failed/ { saw_stop_key=1 }
      /app\.newapi\.warn\.cleanup_disable_failed/ { saw_disable_key=1 }
      /app\.newapi\.warn\.cleanup_reload_failed/ { saw_reload_key=1 }
      END {
        if (!(saw_stop_key && saw_disable_key && saw_reload_key)) {
          print "NewAPI must provide localized install rollback cleanup warnings." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/newapi.sh
  awk '
      /warn "\$\(t app\.newapi\.warn\.start_rollback\)"/ { in_cleanup=1; saw_stop=0; saw_disable=0; saw_reload=0; saw_suppressed=0; next }
      in_cleanup && /\|\| true/ { saw_suppressed=1 }
      in_cleanup && /warn "\$\(t app\.newapi\.warn\.cleanup_stop_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_stop=1 }
      in_cleanup && /warn "\$\(t app\.newapi\.warn\.cleanup_disable_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_disable=1 }
      in_cleanup && /warn "\$\(t app\.newapi\.warn\.cleanup_reload_failed\)"/ { saw_reload=1 }
      in_cleanup && /error "\$\(t app\.newapi\.error\.install_start_failed "\$SERVICE_NAME"\)"/ {
        if (!(saw_stop && saw_disable && saw_reload) || saw_suppressed) {
          printf "%s NewAPI install rollback cleanup must warn on stop, disable, and daemon-reload failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_cleanup=0
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
}

check_newapi_update_stop_failure_aborts_before_replace() {
  awk '
      /app\.newapi\.error\.stop_service_failed/ { saw_key=1 }
      END {
        if (!saw_key) {
          print "NewAPI must provide an actionable update stop failure error." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/newapi.sh
  awk '
      /info "\$\(t app\.newapi\.info\.stop_service\)"/ { in_stop=1; saw_if=0; saw_cleanup=0; saw_error=0; saw_suppressed=0; next }
      in_stop && /systemctl stop "\$SERVICE_NAME" 2>\/dev\/null \|\| true/ { saw_suppressed=1 }
      in_stop && /if ! systemctl stop "\$SERVICE_NAME" 2>\/dev\/null; then/ { saw_if=1 }
      in_stop && /rm -f "\$TMP_BIN"/ { saw_cleanup=1 }
      in_stop && /error "\$\(t app\.newapi\.error\.stop_service_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_error=1 }
      in_stop && /if ! _install_binary_candidate "\$TMP_BIN"; then/ {
        if (!(saw_if && saw_cleanup && saw_error) || saw_suppressed) {
          printf "%s NewAPI update must abort and clean the downloaded binary when stopping the service fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_stop=0
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
}

check_newapi_update_rollback_stop_failure_aborts_restore() {
  awk '
      /app\.newapi\.error\.rollback_stop_failed/ { saw_key=1 }
      END {
        if (!saw_key) {
          print "NewAPI must provide an actionable rollback stop failure error." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/newapi.sh
  awk '
      /warn "\$\(t app\.newapi\.warn\.update_start_failed "\$LATEST" "\$CURRENT"\)"/ { in_rollback=1; saw_if=0; saw_error=0; saw_suppressed=0; next }
      in_rollback && /systemctl stop "\$SERVICE_NAME" 2>\/dev\/null \|\| true/ { saw_suppressed=1 }
      in_rollback && /if ! systemctl stop "\$SERVICE_NAME" 2>\/dev\/null; then/ { saw_if=1 }
      in_rollback && /error "\$\(t app\.newapi\.error\.rollback_stop_failed "\$SERVICE_NAME" "\$BAK_PATH" "\$SERVICE_NAME"\)"/ { saw_error=1 }
      in_rollback && /if ! _restore_binary_backup "\$BAK_PATH"; then/ {
        if (!(saw_if && saw_error) || saw_suppressed) {
          printf "%s NewAPI update rollback must abort before restoring files when stopping the failed new service fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_rollback=0
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
}

check_newapi_uninstall_stop_disable_failures_are_reported() {
  awk '
      /app\.newapi\.error\.uninstall_stop_failed/ { saw_stop_error=1 }
      /app\.newapi\.warn\.uninstall_stop_failed/ { saw_stop_warn=1 }
      /app\.newapi\.warn\.uninstall_disable_failed/ { saw_disable_warn=1 }
      END {
        if (!(saw_stop_error && saw_stop_warn && saw_disable_warn)) {
          print "NewAPI must provide localized uninstall stop and disable failure messages." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/newapi.sh
  awk '
      /info "\$\(t app\.newapi\.info\.stop_disable "\$SERVICE_NAME"\)"/ { in_uninstall=1; saw_stop_if=0; saw_active_if=0; saw_stop_error=0; saw_stop_warn=0; saw_disable_if=0; saw_disable_warn=0; saw_suppressed=0; next }
      in_uninstall && /systemctl (stop|disable).* \|\| true/ { saw_suppressed=1 }
      in_uninstall && /if ! systemctl stop "\$SERVICE_NAME" 2>\/dev\/null; then/ { saw_stop_if=1 }
      in_uninstall && /if systemctl is-active --quiet "\$SERVICE_NAME" 2>\/dev\/null; then/ { saw_active_if=1 }
      in_uninstall && /error "\$\(t app\.newapi\.error\.uninstall_stop_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_stop_error=1 }
      in_uninstall && /warn "\$\(t app\.newapi\.warn\.uninstall_stop_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_stop_warn=1 }
      in_uninstall && /if ! systemctl disable "\$SERVICE_NAME" 2>\/dev\/null; then/ { saw_disable_if=1 }
      in_uninstall && /warn "\$\(t app\.newapi\.warn\.uninstall_disable_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_disable_warn=1 }
      in_uninstall && /rm -f "\/etc\/systemd\/system\/\$\{SERVICE_NAME\}\.service"/ {
        if (!(saw_stop_if && saw_active_if && saw_stop_error && saw_stop_warn && saw_disable_if && saw_disable_warn) || saw_suppressed) {
          printf "%s NewAPI uninstall must abort when an active service cannot be stopped and warn on disable failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_uninstall=0
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
}

check_sub2api_update_rollbacks_report_restart_failures() {
  if grep -R -n 'systemctl start "\$SERVICE_NAME" 2>/dev/null || true' \
      impl/install_sub2api.sh dist/install_sub2api.sh 2>/dev/null; then
    echo "Sub2API update rollback paths must not suppress service restart failures." >&2
    return 1
  fi
  awk '
      /if ! _install_binary_candidate "\$TMP_BIN"; then/ { in_install_failure=1; saw_restore=0; saw_start_if=0; saw_warn=0; next }
      in_install_failure && /if _restore_binary_backup "\$BAK_PATH"; then/ { saw_restore=1 }
      in_install_failure && /if ! systemctl start "\$SERVICE_NAME"; then/ { saw_start_if=1 }
      in_install_failure && /warn "\$\(t app\.sub2api\.warn\.rollback_start_failed "\$SERVICE_NAME"\)"/ { saw_warn=1 }
      in_install_failure && /error "\$\(t app\.sub2api\.error\.binary_install "\$BIN_PATH"\)"/ {
        if (!(saw_restore && saw_start_if && saw_warn)) {
          printf "%s Sub2API binary-install rollback must warn when service restart fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_install_failure=0
      }
      /warn "\$\(t app\.sub2api\.warn\.new_version_failed "\$LATEST" "\$CURRENT"\)"/ { in_update_failure=1; saw_restore2=0; saw_start_if2=0; saw_wait=0; saw_warn2=0; next }
      in_update_failure && /if ! _restore_binary_backup "\$BAK_PATH"; then/ { saw_restore2=1 }
      in_update_failure && /if systemctl start "\$SERVICE_NAME"; then/ { saw_start_if2=1 }
      in_update_failure && /if wait_for_service "\$SERVICE_NAME" 15; then/ { saw_wait=1 }
      in_update_failure && /warn "\$\(t app\.sub2api\.warn\.rollback_start_failed "\$SERVICE_NAME"\)"/ { saw_warn2=1 }
      in_update_failure && saw_start_if2 && /error "\$\(t app\.sub2api\.error\.update_failed "\$CURRENT" "\$SERVICE_NAME"\)"/ {
        if (!(saw_restore2 && saw_start_if2 && saw_wait && saw_warn2)) {
          printf "%s Sub2API update rollback must branch explicitly on restart failures before reporting rollback outcome\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_update_failure=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_sub2api_install_cleanup_reports_systemctl_failures() {
  awk '
      /app\.sub2api\.warn\.cleanup_stop_failed/ { saw_stop_key=1 }
      /app\.sub2api\.warn\.cleanup_disable_failed/ { saw_disable_key=1 }
      /app\.sub2api\.warn\.cleanup_reload_failed/ { saw_reload_key=1 }
      END {
        if (!(saw_stop_key && saw_disable_key && saw_reload_key)) {
          print "Sub2API must provide localized install rollback cleanup warnings." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/sub2api.sh
  awk '
      /warn "\$\(t app\.sub2api\.warn\.service_failed_rollback\)"/ { in_cleanup=1; saw_stop=0; saw_disable=0; saw_reload=0; saw_suppressed=0; next }
      in_cleanup && /\|\| true/ { saw_suppressed=1 }
      in_cleanup && /warn "\$\(t app\.sub2api\.warn\.cleanup_stop_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_stop=1 }
      in_cleanup && /warn "\$\(t app\.sub2api\.warn\.cleanup_disable_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_disable=1 }
      in_cleanup && /warn "\$\(t app\.sub2api\.warn\.cleanup_reload_failed\)"/ { saw_reload=1 }
      in_cleanup && /error "\$\(t app\.sub2api\.error\.install_failed_rollback "\$SERVICE_NAME"\)"/ {
        if (!(saw_stop && saw_disable && saw_reload) || saw_suppressed) {
          printf "%s Sub2API install rollback cleanup must warn on stop, disable, and daemon-reload failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_cleanup=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_sub2api_update_stop_failure_aborts_before_replace() {
  awk '
      /app\.sub2api\.error\.stop_service_failed/ { saw_key=1 }
      END {
        if (!saw_key) {
          print "Sub2API must provide an actionable update stop failure error." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/sub2api.sh
  awk '
      /info "\$\(t app\.sub2api\.info\.stopping_service\)"/ { in_stop=1; saw_if=0; saw_cleanup=0; saw_error=0; saw_suppressed=0; next }
      in_stop && /systemctl stop "\$SERVICE_NAME" 2>\/dev\/null \|\| true/ { saw_suppressed=1 }
      in_stop && /if ! systemctl stop "\$SERVICE_NAME" 2>\/dev\/null; then/ { saw_if=1 }
      in_stop && /rm -f "\$TMP_BIN"/ { saw_cleanup=1 }
      in_stop && /error "\$\(t app\.sub2api\.error\.stop_service_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_error=1 }
      in_stop && /if ! _install_binary_candidate "\$TMP_BIN"; then/ {
        if (!(saw_if && saw_cleanup && saw_error) || saw_suppressed) {
          printf "%s Sub2API update must abort and clean the extracted binary when stopping the service fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_stop=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_sub2api_update_rollback_stop_failure_aborts_restore() {
  awk '
      /app\.sub2api\.error\.rollback_stop_failed/ { saw_key=1 }
      END {
        if (!saw_key) {
          print "Sub2API must provide an actionable rollback stop failure error." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/sub2api.sh
  awk '
      /warn "\$\(t app\.sub2api\.warn\.new_version_failed "\$LATEST" "\$CURRENT"\)"/ { in_rollback=1; saw_if=0; saw_error=0; saw_suppressed=0; next }
      in_rollback && /systemctl stop "\$SERVICE_NAME" 2>\/dev\/null \|\| true/ { saw_suppressed=1 }
      in_rollback && /if ! systemctl stop "\$SERVICE_NAME" 2>\/dev\/null; then/ { saw_if=1 }
      in_rollback && /error "\$\(t app\.sub2api\.error\.rollback_stop_failed "\$SERVICE_NAME" "\$BAK_PATH" "\$SERVICE_NAME"\)"/ { saw_error=1 }
      in_rollback && /if ! _restore_binary_backup "\$BAK_PATH"; then/ {
        if (!(saw_if && saw_error) || saw_suppressed) {
          printf "%s Sub2API update rollback must abort before restoring files when stopping the failed new service fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_rollback=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_sub2api_uninstall_stop_disable_failures_are_reported() {
  awk '
      /app\.sub2api\.error\.uninstall_stop_failed/ { saw_stop_error=1 }
      /app\.sub2api\.warn\.uninstall_stop_failed/ { saw_stop_warn=1 }
      /app\.sub2api\.warn\.uninstall_disable_failed/ { saw_disable_warn=1 }
      END {
        if (!(saw_stop_error && saw_stop_warn && saw_disable_warn)) {
          print "Sub2API must provide localized uninstall stop and disable failure messages." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/sub2api.sh
  awk '
      /info "\$\(t app\.sub2api\.info\.stop_disable "\$SERVICE_NAME"\)"/ { in_uninstall=1; saw_stop_if=0; saw_active_if=0; saw_stop_error=0; saw_stop_warn=0; saw_disable_if=0; saw_disable_warn=0; saw_suppressed=0; next }
      in_uninstall && /systemctl (stop|disable).* \|\| true/ { saw_suppressed=1 }
      in_uninstall && /if ! systemctl stop "\$SERVICE_NAME" 2>\/dev\/null; then/ { saw_stop_if=1 }
      in_uninstall && /if systemctl is-active --quiet "\$SERVICE_NAME" 2>\/dev\/null; then/ { saw_active_if=1 }
      in_uninstall && /error "\$\(t app\.sub2api\.error\.uninstall_stop_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_stop_error=1 }
      in_uninstall && /warn "\$\(t app\.sub2api\.warn\.uninstall_stop_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_stop_warn=1 }
      in_uninstall && /if ! systemctl disable "\$SERVICE_NAME" 2>\/dev\/null; then/ { saw_disable_if=1 }
      in_uninstall && /warn "\$\(t app\.sub2api\.warn\.uninstall_disable_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_disable_warn=1 }
      in_uninstall && /rm -f "\/etc\/systemd\/system\/\$\{SERVICE_NAME\}\.service"/ {
        if (!(saw_stop_if && saw_active_if && saw_stop_error && saw_stop_warn && saw_disable_if && saw_disable_warn) || saw_suppressed) {
          printf "%s Sub2API uninstall must abort when an active service cannot be stopped and warn on disable failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_uninstall=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_sub2api_install_summary_matches_runtime_state() {
  awk '
      /app\.sub2api\.summary\.title_ready/ { saw_title_ready=1 }
      /app\.sub2api\.summary\.title_pending/ { saw_title_pending=1 }
      /app\.sub2api\.summary\.next2_ready/ { saw_next_ready=1 }
      /app\.sub2api\.summary\.next2_pending/ { saw_next_pending=1 }
      END {
        if (!(saw_title_ready && saw_title_pending && saw_next_ready && saw_next_pending)) {
          print "Sub2API install summary strings must distinguish ready and pending service states." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/sub2api.sh
  awk '
      /_health_check\(\)/ { in_health=1; saw_success=0; saw_return_ok=0; saw_warn=0; saw_return_fail=0; next }
      in_health && /success "\$\(t app\.sub2api\.success\.http_health "\$HTTP_CODE"\)"/ { saw_success=1 }
      in_health && /return 0/ { saw_return_ok=1 }
      in_health && /warn "\$\(t app\.sub2api\.warn\.http_health "\$HTTP_CODE"\)"/ { saw_warn=1 }
      in_health && /return 1/ { saw_return_fail=1 }
      in_health && /^}/ {
        if (!(saw_success && saw_return_ok && saw_warn && saw_return_fail)) {
          printf "%s Sub2API health helper must return explicit ready/pending status\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_health=0
      }
      /_print_install_summary\(\)/ { in_summary=1; saw_state=0; saw_pending=0; saw_ready=0; next }
      in_summary && /local summary_state="\$\{2:-ready\}"/ { saw_state=1 }
      in_summary && /summary_title="\$\(t app\.sub2api\.summary\.title_pending\)"/ { saw_pending=1 }
      in_summary && /summary_title="\$\(t app\.sub2api\.summary\.title_ready\)"/ { saw_ready=1 }
      in_summary && /^}/ {
        if (!(saw_state && saw_pending && saw_ready)) {
          printf "%s Sub2API install summary helper must branch on ready vs pending runtime state\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_summary=0
      }
      /step "\$\(t app\.sub2api\.step\.start_service\)"/ { in_install=1; saw_init=0; saw_pending_state=0; saw_summary_call=0; next }
      in_install && /local _install_summary_state="ready"/ { saw_init=1 }
      in_install && /_install_summary_state="pending"/ { saw_pending_state=1 }
      in_install && /_print_install_summary "\$LATEST" "\$_install_summary_state"/ {
        saw_summary_call=1
        if (!(saw_init && saw_pending_state)) {
          printf "%s Sub2API install path must downgrade the summary when the service did not become ready\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_install=0
      }
      END {
        if (!saw_summary_call) {
          print "Sub2API install path must pass runtime state into the install summary." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_sub2api_health_checks_are_nonfatal_outside_install() {
  awk '
      /if systemctl start "\$SERVICE_NAME" && wait_for_service "\$SERVICE_NAME" 25; then/ { in_update=1; saw_health_if=0; next }
      in_update && /if ! _health_check; then/ { saw_health_if=1 }
      in_update && /echo -e "  \$\{BOLD\}\$\{GREEN\}\$\(t app\.sub2api\.success\.update_done/ {
        if (!saw_health_if) {
          printf "%s Sub2API update must treat post-restart health warnings as nonfatal\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_update=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_newapi_install_summary_matches_health_state() {
  awk '
      /app\.newapi\.summary\.title_ready/ { saw_title_ready=1 }
      /app\.newapi\.summary\.title_pending/ { saw_title_pending=1 }
      END {
        if (!(saw_title_ready && saw_title_pending)) {
          print "NewAPI install summary strings must distinguish ready and pending health states." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/newapi.sh
  awk '
      /_health_check\(\)/ { in_health=1; saw_success=0; saw_return_ok=0; saw_warn=0; saw_return_fail=0; next }
      in_health && /success "\$\(t app\.newapi\.success\.http_health "\$HTTP_CODE"\)"/ { saw_success=1 }
      in_health && /return 0/ { saw_return_ok=1 }
      in_health && /warn "\$\(t app\.newapi\.warn\.http_health "\$HTTP_CODE"\)"/ { saw_warn=1 }
      in_health && /return 1/ { saw_return_fail=1 }
      in_health && /^}/ {
        if (!(saw_success && saw_return_ok && saw_warn && saw_return_fail)) {
          printf "%s NewAPI health helper must return explicit ready/pending status\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_health=0
      }
      /_print_install_summary\(\)/ { in_summary=1; saw_state=0; saw_pending=0; saw_ready=0; next }
      in_summary && /local summary_state="\$\{2:-ready\}"/ { saw_state=1 }
      in_summary && /summary_title="\$\(t app\.newapi\.summary\.title_pending\)"/ { saw_pending=1 }
      in_summary && /summary_title="\$\(t app\.newapi\.summary\.title_ready\)"/ { saw_ready=1 }
      in_summary && /^}/ {
        if (!(saw_state && saw_pending && saw_ready)) {
          printf "%s NewAPI install summary helper must branch on health state\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_summary=0
      }
      /local _install_summary_state="ready"/ { saw_init=1 }
      /step "\$\(t app\.newapi\.step\.health\)"/ { in_install=1; saw_pending_state=0; saw_health_if=0; saw_summary_call=0; next }
      in_install && /if ! _health_check; then/ { saw_health_if=1 }
      in_install && /_install_summary_state="pending"/ { saw_pending_state=1 }
      in_install && /_print_install_summary "\$LATEST" "\$_install_summary_state"/ {
        saw_summary_call=1
        if (!(saw_init && saw_health_if && saw_pending_state)) {
          printf "%s NewAPI install flow must downgrade the summary when health checks stay pending\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_install=0
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
}

check_newapi_health_checks_are_nonfatal_outside_install() {
  awk '
      /if systemctl start "\$SERVICE_NAME" && wait_for_service "\$SERVICE_NAME" 20; then/ { in_update=1; saw_health_if=0; next }
      in_update && /if ! _health_check; then/ { saw_health_if=1 }
      in_update && /echo -e "  \$\{BOLD\}\$\{GREEN\}\$\(t app\.newapi\.success\.update_done/ {
        if (!saw_health_if) {
          printf "%s NewAPI update must treat post-restart health warnings as nonfatal\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_update=0
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
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
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
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
      in_status && /HTTP_CODE=\$\(curl -o \/dev\/null -s -w "%\{http_code\}" --max-time 5 "http:\/\/127\.0\.0\.1:\$\{VW_PORT\}\// { saw_local_probe=1 }
      in_status && /app\.vaultwarden\.status\.local_response_warn/ { saw_warn=1 }
      in_status && /echo -e "\\n\$\{BOLD\}\[\$\(t app\.vaultwarden\.status\.tls\)\]\$\{NC\}"/ {
        if (!(saw_local_probe && saw_warn)) {
          printf "%s Vaultwarden status must pair the local 127.0.0.1 probe with the matching local-response warning\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_status=0
      }
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
}

check_cyberstrikeai_update_rollbacks_report_restart_failures() {
  if grep -R -n 'systemctl start "\$SERVICE_NAME" 2>/dev/null' \
      impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "CyberStrikeAI update rollback paths must not suppress service restart diagnostics." >&2
    return 1
  fi
  awk '
      /warn "\$\(t app\.cyberstrikeai\.warn\.update_start_failed\)"/ { in_update_failure=1; saw_restore=0; saw_start_if=0; saw_wait=0; saw_ok_error=0; saw_failed_error=0; next }
      in_update_failure && /if restore_update_backup "\$bin_bak" "\$config_bak"; then/ { saw_restore=1 }
      in_update_failure && /if systemctl start "\$SERVICE_NAME"; then/ { saw_start_if=1 }
      in_update_failure && /if wait_for_service "\$SERVICE_NAME" 35; then/ { saw_wait=1 }
      in_update_failure && /error "\$\(t app\.cyberstrikeai\.error\.update_rollback_ok "\$SERVICE_NAME"\)"/ { saw_ok_error=1 }
      in_update_failure && /error "\$\(t app\.cyberstrikeai\.error\.update_rollback_failed "\$SERVICE_NAME"\)"/ { saw_failed_error=1 }
      in_update_failure && /^    fi$/ {
        if (saw_restore && !(saw_start_if && saw_wait && saw_ok_error && saw_failed_error)) {
          printf "%s CyberStrikeAI update rollback must branch explicitly on restart failures before reporting rollback outcome\n", FILENAME > "/dev/stderr"
          exit 1
        }
      }
      in_update_failure && /^  else$/ { in_update_failure=0 }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_update_rollback_stop_failure_aborts_restore() {
  awk '
      /app\.cyberstrikeai\.error\.rollback_stop_failed/ { saw_key=1 }
      END {
        if (!saw_key) {
          print "CyberStrikeAI must provide an actionable rollback stop failure error." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/cyberstrikeai.sh
  awk '
      /warn "\$\(t app\.cyberstrikeai\.warn\.update_start_failed\)"/ { in_rollback=1; saw_if=0; saw_error=0; saw_suppressed=0; next }
      in_rollback && /systemctl stop "\$SERVICE_NAME" 2>\/dev\/null \|\| true/ { saw_suppressed=1 }
      in_rollback && /if ! systemctl stop "\$SERVICE_NAME" 2>\/dev\/null; then/ { saw_if=1 }
      in_rollback && /error "\$\(t app\.cyberstrikeai\.error\.rollback_stop_failed "\$SERVICE_NAME" "\$bin_bak" "\$config_bak" "\$SERVICE_NAME"\)"/ { saw_error=1 }
      in_rollback && /if restore_update_backup "\$bin_bak" "\$config_bak"; then/ {
        if (!(saw_if && saw_error) || saw_suppressed) {
          printf "%s CyberStrikeAI update rollback must abort before restoring files when stopping the failed updated service fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_rollback=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_uninstall_stop_disable_failures_are_reported() {
  awk '
      /app\.cyberstrikeai\.info\.stop_disable/ { saw_info=1 }
      /app\.cyberstrikeai\.error\.uninstall_stop_failed/ { saw_stop_error=1 }
      /app\.cyberstrikeai\.warn\.uninstall_stop_failed/ { saw_stop_warn=1 }
      /app\.cyberstrikeai\.warn\.uninstall_disable_failed/ { saw_disable_warn=1 }
      END {
        if (!(saw_info && saw_stop_error && saw_stop_warn && saw_disable_warn)) {
          print "CyberStrikeAI must provide localized uninstall stop and disable failure messages." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/cyberstrikeai.sh
  awk '
      /info "\$\(t app\.cyberstrikeai\.info\.stop_disable "\$SERVICE_NAME"\)"/ { in_uninstall=1; saw_stop_if=0; saw_active_if=0; saw_stop_error=0; saw_stop_warn=0; saw_disable_if=0; saw_disable_warn=0; saw_suppressed=0; next }
      in_uninstall && /systemctl (stop|disable).* \|\| true/ { saw_suppressed=1 }
      in_uninstall && /if ! systemctl stop "\$SERVICE_NAME" 2>\/dev\/null; then/ { saw_stop_if=1 }
      in_uninstall && /if systemctl is-active --quiet "\$SERVICE_NAME" 2>\/dev\/null; then/ { saw_active_if=1 }
      in_uninstall && /error "\$\(t app\.cyberstrikeai\.error\.uninstall_stop_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_stop_error=1 }
      in_uninstall && /warn "\$\(t app\.cyberstrikeai\.warn\.uninstall_stop_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_stop_warn=1 }
      in_uninstall && /if ! systemctl disable "\$SERVICE_NAME" 2>\/dev\/null; then/ { saw_disable_if=1 }
      in_uninstall && /warn "\$\(t app\.cyberstrikeai\.warn\.uninstall_disable_failed "\$SERVICE_NAME" "\$SERVICE_NAME"\)"/ { saw_disable_warn=1 }
      in_uninstall && /rm -f "\/etc\/systemd\/system\/\$\{SERVICE_NAME\}\.service"/ {
        if (!(saw_stop_if && saw_active_if && saw_stop_error && saw_stop_warn && saw_disable_if && saw_disable_warn) || saw_suppressed) {
          printf "%s CyberStrikeAI uninstall must abort when an active service cannot be stopped and warn on disable failures\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_uninstall=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_install_summary_matches_health_state() {
  awk '
      /app\.cyberstrikeai\.summary\.title_ready/ { saw_title_ready=1 }
      /app\.cyberstrikeai\.summary\.title_pending/ { saw_title_pending=1 }
      END {
        if (!(saw_title_ready && saw_title_pending)) {
          print "CyberStrikeAI install summary strings must distinguish ready and pending health states." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/cyberstrikeai.sh
  awk '
      /health_check\(\)/ { in_health=1; saw_pending_flag=0; saw_backend_warn=0; saw_nginx_warn=0; saw_return=0; next }
      in_health && /local health_pending=0/ { saw_pending_flag=1 }
      in_health && /warn "\$\(t app\.cyberstrikeai\.warn\.backend_health "\$code"\)"/ { saw_backend_warn=1 }
      in_health && /warn "\$\(t app\.cyberstrikeai\.warn\.nginx_health "\$code"\)"/ { saw_nginx_warn=1 }
      in_health && /\[\[ "\$health_pending" -eq 0 \]\]/ { saw_return=1 }
      in_health && /^}/ {
        if (!(saw_pending_flag && saw_backend_warn && saw_nginx_warn && saw_return)) {
          printf "%s CyberStrikeAI health check must return explicit ready/pending status\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_health=0
      }
      /print_summary\(\)/ { in_summary=1; saw_state=0; saw_pending=0; saw_ready=0; next }
      in_summary && /local summary_state="\$\{1:-ready\}"/ { saw_state=1 }
      in_summary && /app\.cyberstrikeai\.summary\.title_pending/ { saw_pending=1 }
      in_summary && /app\.cyberstrikeai\.summary\.title_ready/ { saw_ready=1 }
      in_summary && /^}/ {
        if (!(saw_state && saw_pending && saw_ready)) {
          printf "%s CyberStrikeAI summary printer must branch on health state\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_summary=0
      }
      /start_service/ { saw_start=1 }
      /local _install_summary_state="ready"/ { saw_init=1 }
      /if ! health_check; then/ { saw_health_if=1 }
      /_install_summary_state="pending"/ { saw_pending_state=1 }
      /print_summary "\$_install_summary_state"/ {
        if (!(saw_start && saw_init && saw_health_if && saw_pending_state)) {
          printf "%s CyberStrikeAI install flow must downgrade the summary when health checks stay pending\n", FILENAME > "/dev/stderr"
          exit 1
        }
        saw_summary_call=1
      }
      END {
        if (!saw_summary_call) {
          print "CyberStrikeAI install flow must pass health state into the install summary." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_nginx_health_probe_matches_server_name() {
  awk '
      /app\.cyberstrikeai\.warn\.nginx_health/ { saw_warn=1 }
      /Local Nginx probe returned HTTP %s/ { saw_probe_text=1 }
      /configured server_name/ { saw_guidance=1 }
      END {
        if (!(saw_warn && saw_probe_text && saw_guidance)) {
          print "CyberStrikeAI Nginx health warnings must describe the local probe and server_name guidance." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/cyberstrikeai.sh
  awk '
      /step "\$\(t app\.cyberstrikeai\.step\.health\)"/ { in_health=1; next }
      in_health && /public_url="http:\/\/127\.0\.0\.1:\$\{PUBLIC_PORT\}\/"/ { saw_url=1 }
      in_health && /curl -H "Host: \$\{CSAI_DOMAIN:-localhost\}"/ { saw_host_header=1 }
      in_health && /warn "\$\(t app\.cyberstrikeai\.warn\.nginx_health "\$code"\)"/ { saw_warn=1 }
      in_health && /\[\[ "\$health_pending" -eq 0 \]\]/ {
        if (!(saw_url && saw_host_header && saw_warn)) {
          printf "%s CyberStrikeAI local Nginx probe must send the configured Host header before warning on mismatches\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_health=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_cyberstrikeai_health_checks_are_nonfatal_outside_install() {
  awk '
      /success "\$\(t app\.cyberstrikeai\.success\.update_complete "\$old_rev" "\$new_rev"\)"/ { in_update=1; saw_health_if=0; next }
      in_update && /if ! health_check; then/ { saw_health_if=1 }
      in_update && /warn "\$\(t app\.cyberstrikeai\.warn\.update_start_failed\)"/ {
        if (!saw_health_if) {
          printf "%s CyberStrikeAI update must treat post-restart health warnings as nonfatal\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_update=0
      }
      /step "\$\(t app\.cyberstrikeai\.step\.health\)"/ { in_status=1; saw_status_if=0; next }
      in_status && /if ! health_check; then/ { saw_status_if=1 }
      in_status && /step "\$\(t app\.cyberstrikeai\.step\.nginx\)"/ {
        if (!saw_status_if) {
          printf "%s CyberStrikeAI status must keep reporting after local health warnings\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_status=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
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
      /_configure_firewall\(\)/ { in_block=1; saw_ufw_if=0; saw_iptables_if=0; saw_failure_warn=0; next }
      in_block && /if ufw allow "\$\{PORT\}\/tcp" comment "New API" > \/dev\/null; then/ { saw_ufw_if=1 }
      in_block && /if iptables -C INPUT -p tcp --dport "\$PORT" -j ACCEPT 2>\/dev\/null/ { saw_iptables_if=1 }
      in_block && /warn "\$\(t app\.newapi\.warn\.firewall_config_failed "\$PORT"\)"/ { saw_failure_warn=1 }
      in_block && /^}/ {
        if (!(saw_ufw_if && saw_iptables_if && saw_failure_warn)) {
          printf "%s NewAPI firewall configuration must only report success after command success and warn on failure\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_newapi.sh dist/install_newapi.sh
  awk '
      /_configure_firewall\(\)/ { in_block=1; saw_ufw_if=0; saw_firewalld_if=0; saw_iptables_if=0; saw_failure_warn=0; next }
      in_block && /if ufw allow "\$\{PORT\}\/tcp" comment "Sub2API" > \/dev\/null; then/ { saw_ufw_if=1 }
      in_block && /if firewall-cmd --permanent --add-port="\$\{PORT\}\/tcp" >\/dev\/null 2>&1/ { saw_firewalld_if=1 }
      in_block && /if iptables -C INPUT -p tcp --dport "\$PORT" -j ACCEPT 2>\/dev\/null/ { saw_iptables_if=1 }
      in_block && /warn "\$\(t app\.sub2api\.warn\.firewall_config_failed "\$PORT"\)"/ { saw_failure_warn=1 }
      in_block && /^}/ {
        if (!(saw_ufw_if && saw_firewalld_if && saw_iptables_if && saw_failure_warn)) {
          printf "%s Sub2API firewall configuration must only report success after command success and warn on failure\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
  awk '
      /open_firewall_ports\(\)/ { in_block=1; saw_ufw_if=0; saw_iptables_if=0; saw_failure_warn=0; next }
      in_block && /if ufw allow "\$\{port_to_open\}\/tcp" >\/dev\/null 2>&1; then/ { saw_ufw_if=1 }
      in_block && /if iptables -C INPUT -p tcp --dport "\$port_to_open" -j ACCEPT 2>\/dev\/null/ { saw_iptables_if=1 }
      in_block && /warn "\$\(t app\.cyberstrikeai\.warn\.firewall_config_failed "\$port_to_open"\)"/ { saw_failure_warn=1 }
      in_block && /^}/ {
        if (!(saw_ufw_if && saw_iptables_if && saw_failure_warn)) {
          printf "%s CyberStrikeAI firewall configuration must only report success after command success and warn on failure\n", FILENAME > "/dev/stderr"
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

check_cyberstrikeai_nginx_apply_preserves_reload_diagnostics() {
  if grep -R -n 'systemctl reload nginx 2>/dev/null || systemctl restart nginx' \
      impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "CyberStrikeAI nginx apply path must not suppress reload diagnostics." >&2
    return 1
  fi
  awk '
      /_write_nginx_site_link "\$NGINX_CONF" "\$NGINX_LINK"/ { in_block=1; saw_test=0; saw_reload=0; saw_restart=0; next }
      in_block && /if ! nginx -t; then/ { saw_test=1 }
      in_block && /error "\$\(t app\.cyberstrikeai\.error\.nginx_test\)"/ { saw_test_error=1 }
      in_block && /if systemctl is-active --quiet nginx; then/ { saw_active_check=1 }
      in_block && /if ! systemctl reload nginx; then/ { saw_reload=1 }
      in_block && /if ! systemctl restart nginx; then/ { saw_restart=1 }
      in_block && /error "\$\(t app\.cyberstrikeai\.error\.nginx_start\)"/ { saw_start_error=1 }
      in_block && /if ! wait_for_service nginx 10; then/ { saw_wait=1 }
      in_block && /success "\$\(t app\.cyberstrikeai\.success\.nginx\)"/ {
        if (!(saw_test && saw_test_error && saw_active_check && saw_reload && saw_restart && saw_start_error && saw_wait)) {
          printf "%s CyberStrikeAI nginx apply path must validate config, preserve reload diagnostics, and report start failures explicitly\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_uninstall_nginx_paths_preserve_diagnostics() {
  if grep -R -nE 'nginx -t 2>/dev/null && systemctl reload nginx 2>/dev/null \|\| true|systemctl reload nginx 2>/dev/null \|\| true$' \
      impl/install_sub2api.sh impl/install_cyberstrikeai.sh impl/install_vaultwarden.sh \
      dist/install_sub2api.sh dist/install_cyberstrikeai.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "Uninstall-time nginx cleanup must preserve nginx test/reload diagnostics." >&2
    return 1
  fi
  awk '
      /rm -f \/etc\/nginx\/sites-enabled\/sub2api/ { in_block=1; saw_test=0; saw_reload=0; saw_diag=0; saw_fallback=0; next }
      in_block && /if nginx -t >\/dev\/null 2>&1; then/ { saw_test=1 }
      in_block && /if systemctl reload nginx >\/dev\/null 2>&1; then/ { saw_reload=1 }
      in_block && /nginx -t >&2 \|\| true/ { saw_diag=1 }
      in_block && /success "\$\(t app\.sub2api\.success\.removed_nginx\)"/ { saw_fallback=1 }
      in_block && /rm -f \/etc\/cron\.d\/sub2api-backup/ {
        if (!(saw_test && saw_reload && saw_diag && saw_fallback)) {
          printf "%s Sub2API uninstall nginx cleanup must validate reloads and emit diagnostics on failure\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_sub2api.sh dist/install_sub2api.sh
  awk '
      /rm -f "\$NGINX_LINK" "\$NGINX_CONF"/ { in_block=1; saw_test=0; saw_reload=0; saw_diag=0; next }
      in_block && /if nginx -t >\/dev\/null 2>&1; then/ { saw_test=1 }
      in_block && /systemctl reload nginx >\/dev\/null 2>&1 \|\| nginx -t >&2 \|\| true/ { saw_reload=1; saw_diag=1 }
      in_block && /^    else$/ { saw_else=1 }
      in_block && saw_else && /nginx -t >&2 \|\| true/ { saw_diag=1 }
      in_block && /success "\$\(t app\.cyberstrikeai\.success\.removed_nginx\)"/ {
        if (!(saw_test && saw_reload && saw_diag)) {
          printf "%s CyberStrikeAI uninstall nginx cleanup must emit diagnostics when validation or reload fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
  awk '
      /rm -f \/etc\/nginx\/sites-enabled\/vaultwarden \/etc\/nginx\/sites-available\/vaultwarden/ { in_block=1; saw_test=0; saw_reload=0; saw_diag=0; next }
      in_block && /if nginx -t >\/dev\/null 2>&1; then/ { saw_test=1 }
      in_block && /systemctl reload nginx >\/dev\/null 2>&1 \|\| nginx -t >&2 \|\| true/ { saw_reload=1; saw_diag=1 }
      in_block && /^    else$/ { saw_else=1 }
      in_block && saw_else && /nginx -t >&2 \|\| true/ { saw_diag=1 }
      in_block && /success "\$\(t app\.vaultwarden\.success\.removed_nginx\)"/ {
        if (!(saw_test && saw_reload && saw_diag)) {
          printf "%s Vaultwarden uninstall nginx cleanup must emit diagnostics when validation or reload fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
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

check_vaultwarden_fail2ban_restart_failures_are_reported() {
  if grep -R -n 'systemctl restart fail2ban 2>/dev/null || true' \
      impl/install_vaultwarden.sh dist/install_vaultwarden.sh 2>/dev/null; then
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
    ' apps/vaultwarden.sh impl/install_vaultwarden.sh dist/install_vaultwarden.sh
}

check_vaultwarden_result_chains_are_explicit() {
  if grep -R -nE 'nginx -t && systemctl reload nginx[[:space:]\\]*$' \
      impl/install_vaultwarden.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "Vaultwarden must use explicit conditionals for nginx reload outcomes." >&2
    return 1
  fi
  awk '
      /} \| _write_nginx_config_file "\$NGINX_CONF"/ { in_https=1; saw_test=0; saw_reload=0; saw_success=0; saw_warn=0; next }
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

check_vaultwarden_webvault_restore_cleans_partial() {
  if grep -R -nE '^[[:space:]]*\[\[ -d "\$_wv_(bak_ts|install_bak)" \]\] && mv "\$_wv_(bak_ts|install_bak)" "\$VW_WEB_DIR" \|\| true' \
      impl/install_vaultwarden.sh dist/install_vaultwarden.sh 2>/dev/null; then
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
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
}

check_vaultwarden_webvault_replacements_are_atomic() {
  if grep -R -nE 'cp -a "\$EXTRACTED_WEBVAULT_PATH" "\$VW_WEB_DIR"|tar -xzf "\$\{WORK_DIR\}/web-vault\.tar\.gz" -C "\$\(dirname "\$VW_WEB_DIR"\)"' \
      impl/install_vaultwarden.sh dist/install_vaultwarden.sh 2>/dev/null; then
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
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
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
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
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
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
}

check_vaultwarden_webvault_archives_are_validated() {
  awk '
      /app\.vaultwarden\.error\.web_vault_archive_empty/ { saw_empty=1 }
      /app\.vaultwarden\.error\.web_vault_archive_small/ { saw_small=1 }
      /app\.vaultwarden\.error\.web_vault_archive_format/ { saw_format=1 }
      END {
        if (!(saw_empty && saw_small && saw_format)) {
          print "Vaultwarden Web Vault archive validation messages must cover empty, tiny, and non-gzip downloads." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/vaultwarden.sh
  local file
  for file in impl/install_vaultwarden.sh dist/install_vaultwarden.sh; do
    awk '
        /_verify_web_vault_archive\(\)/ {
          in_helper=1
          saw_empty=0
          saw_small=0
          saw_magic=0
          saw_nonfatal=0
          next
        }
        in_helper && /^}/ {
          if (!(saw_empty && saw_small && saw_magic && saw_nonfatal)) {
            printf "%s must validate downloaded Web Vault archives before extraction\n", FILENAME > "/dev/stderr"
            exit 1
          }
          in_helper=0
        }
        in_helper && /\[\[ ! -s "\$archive" \]\]/ { saw_empty=1 }
        in_helper && /\[\[ "\$size" -lt 65536 \]\]/ { saw_small=1 }
        in_helper && /"\$magic" != "1f8b"/ { saw_magic=1 }
        in_helper && /local mode="\$\{2:-fatal\}"/ { saw_nonfatal=1 }
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

check_blog_static_deploy_swaps_tree() {
  if grep -R -n '^[[:space:]]*cp -a "\${PUBLIC_DIR}/\." "\$NGINX_ROOT/"' impl/install_blog.sh dist/install_blog.sh 2>/dev/null; then
    echo "Blog static deployment must not copy directly into the live Nginx root." >&2
    return 1
  fi
  if grep -R -n '^[[:space:]]*\[\[ -e "\$DEPLOY_BAK" || -L "\$DEPLOY_BAK" \]\] && mv "\$DEPLOY_BAK" "\$NGINX_ROOT" || true' \
      impl/install_blog.sh dist/install_blog.sh 2>/dev/null; then
    echo "Blog static deployment rollback must validate restoring the Nginx root." >&2
    return 1
  fi
  if grep -R -nE '\[\[ -e "\\?\$DEPLOY_BAK" \|\| -L "\\?\$DEPLOY_BAK" \]\] && rm -rf "\\?\$DEPLOY_BAK"' \
      impl/install_blog.sh dist/install_blog.sh 2>/dev/null; then
    echo "Blog static deployment must not let a missing previous backup trip set -e after a successful first deploy." >&2
    return 1
  fi
  awk '
      /<< BKSH$/ { in_heredoc=1 }
      in_heredoc && /^BKSH$/ { in_heredoc=0; next }
      in_heredoc { next }
      /^[[:space:]]*restore_nginx_root_backup\(\)/ { in_helper=1; saw_rm=0; saw_rm_return=0; saw_restore=0; saw_restore_return=0; next }
      in_helper && /if ! safe_rm_dir "\$NGINX_ROOT" "NGINX_ROOT"; then/ { saw_rm=1 }
      in_helper && saw_rm && /return 1/ { saw_rm_return=1 }
      in_helper && /if ! mv "\$DEPLOY_BAK" "\$NGINX_ROOT"; then/ { saw_restore=1 }
      in_helper && saw_restore && /return 1/ { saw_restore_return=1 }
      in_helper && /^}/ {
        if (!(saw_rm && saw_rm_return && saw_restore && saw_restore_return)) {
          print "Blog static deployment restore helper must remove partial output and restore the previous root." > "/dev/stderr"
          exit 1
        }
        in_helper=0
      }
      /step "\$\(t app\.blog\.step_nginx\)"/ { in_deploy=1; saw_tmp=0; saw_backup=0; saw_swap=0; saw_tmp_cleanup=0; saw_restore_call=0; next }
      in_deploy && /if ! DEPLOY_TMP="\$\(mktemp -d/ { saw_tmp=1 }
      in_deploy && /error "\$\(t app\.blog\.error\.static_deploy "\$NGINX_ROOT"\)"/ { saw_tmp_error=1 }
      in_deploy && /mv "\$NGINX_ROOT" "\$DEPLOY_BAK"/ { saw_backup=1 }
      in_deploy && /mv "\$DEPLOY_TMP" "\$NGINX_ROOT"/ { saw_swap=1 }
      in_deploy && /if \[\[ -e "\$DEPLOY_BAK" \|\| -L "\$DEPLOY_BAK" \]\]; then/ { saw_backup_cleanup_if=1 }
      in_deploy && /rm -rf "\$DEPLOY_TMP"/ { saw_tmp_cleanup=1 }
      in_deploy && /restore_nginx_root_backup/ { saw_restore_call=1 }
      in_deploy && /success "\$\(t app\.blog\.static_deployed "\$NGINX_ROOT"\)"/ {
        if (!(saw_tmp && saw_tmp_error && saw_backup && saw_swap && saw_backup_cleanup_if && saw_tmp_cleanup && saw_restore_call)) {
          print "Blog static deployment must report temp creation failures, stage, swap, clean up previous backups explicitly, clean up failed staging directories, and restore the Nginx root." > "/dev/stderr"
          exit 1
        }
        in_deploy=0
      }
      END {
        if (in_deploy) {
          print "Blog static deployment verifier did not observe the full deploy block." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_blog.sh dist/install_blog.sh
}

check_blog_static_deploy_failures_are_actionable() {
  awk '
      /app\.blog\.error\.static_deploy/ { saw_key=1 }
      /previous site was kept or a restore was attempted/ { saw_state=1 }
      /Inspect %s and retry after fixing filesystem or copy errors/ { saw_guidance=1 }
      END {
        if (!(saw_key && saw_state && saw_guidance)) {
          print "Blog static deployment failures must describe preserved state and tell users how to recover." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/blog.sh
  awk '
      /step "\$\(t app\.blog\.step_nginx\)"/ { in_block=1; next }
      in_block && /error "\$\(t app\.blog\.error\.static_deploy "\$NGINX_ROOT"\)"/ { saw_error=1 }
      in_block && /success "\$\(t app\.blog\.static_deployed "\$NGINX_ROOT"\)"/ { in_block=0 }
      END {
        if (!saw_error) {
          print "Blog static deployment path must pass the live Nginx root into actionable deployment failures." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_blog.sh dist/install_blog.sh
}

check_blog_site_files_are_atomic() {
  if grep -R -nE '^[[:space:]]*cat > "\$CONFIG_FILE"|^[[:space:]]*cat > "\$\{SITE_DIR\}/|^[[:space:]]*cat > "\$\{CMS_ADMIN_DIR\}/' \
      impl/install_blog.sh dist/install_blog.sh 2>/dev/null; then
    echo "Blog site files must be written through temporary files before replacement." >&2
    return 1
  fi
  if grep -R -n '^[[:space:]]*cp "\$CONFIG_FILE" "\${CONFIG_FILE}.bak.' impl/install_blog.sh dist/install_blog.sh 2>/dev/null; then
    echo "Blog config backups must copy to a temporary file before replacing the final backup path." >&2
    return 1
  fi
  awk '
      /backup_blog_file\(\)/ { in_backup=1; saw_tmp=0; saw_tmp_return=0; saw_cp=0; saw_mv=0; saw_cleanup=0; saw_atomic_copy=0; next }
      in_backup && /atomic_copy_file "\$source_path" "\$backup_path"/ { saw_atomic_copy=1 }
      in_backup && /if ! backup_tmp=\$\(mktemp "\$\{backup_path\}\.XXXXXX"\); then/ { saw_tmp=1 }
      in_backup && saw_tmp && /return 1/ { saw_tmp_return=1 }
      in_backup && /cp "\$source_path" "\$backup_tmp"/ { saw_cp=1 }
      in_backup && /mv "\$backup_tmp" "\$backup_path"/ { saw_mv=1 }
      in_backup && /rm -f "\$backup_tmp"/ { saw_cleanup=1 }
      in_backup && /^}/ {
        if (!((saw_tmp && saw_tmp_return && saw_cp && saw_mv && saw_cleanup) || saw_atomic_copy)) {
          print "Blog config backup helper must stage, replace, and clean up temporary backups." > "/dev/stderr"
          exit 1
        }
        in_backup=0
      }
      /_write_blog_file\(\)/ { in_write=1; saw_atomic_write=0; saw_write_error=0; next }
      in_write && /atomic_write_file "\$target_path" 644/ { saw_atomic_write=1 }
      in_write && /error "\$\(t app\.blog\.error\.file_write "\$target_path"\)"/ { saw_write_error=1 }
      in_write && /^}/ {
        if (!(saw_atomic_write && saw_write_error)) {
          print "Blog site file writes must use atomic_write_file and report write failures." > "/dev/stderr"
          exit 1
        }
        in_write=0
      }
      /_write_blog_file "?\$\{?(SITE_DIR|CMS_ADMIN_DIR)\}?/ || /_write_blog_file "\$CONFIG_FILE"/ { saw_helper=1 }
      END {
        if (!saw_helper) {
          print "Blog site setup must write generated files through _write_blog_file." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_blog.sh dist/install_blog.sh
}

check_blog_publish_guidance_uses_staging_output() {
  awk '
      /app\.blog\.workflow_publish/ { saw_publish=1 }
      /staging directory, then run blog-publish/ { saw_publish_guidance=1 }
      /app\.blog\.success\.publish_script/ { saw_publish_script=1 }
      /app\.blog\.error\.publish_script/ { saw_publish_script_error=1 }
      /app\.blog\.rebuild_hint/ { saw_rebuild=1 }
      /then run \/usr\/local\/bin\/blog-publish/ { saw_rebuild_guidance=1 }
      END {
        if (!(saw_publish && saw_publish_guidance && saw_publish_script && saw_publish_script_error && saw_rebuild && saw_rebuild_guidance)) {
          print "Blog publish guidance must direct users through the generated blog-publish helper." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/blog.sh
  awk '
      /# \$\(t app\.blog\.workflow_publish\)/ { in_publish=1; saw_build=0; saw_sync=0; next }
      in_publish && /hugo --destination \$\{PUBLIC_DIR\} --gc --minify/ { saw_build=1 }
      in_publish && /\/usr\/local\/bin\/blog-publish/ { saw_sync=1 }
      in_publish && /^echo ""$/ {
        if (!(saw_build && saw_sync)) {
          printf "%s Blog publish guidance must build into PUBLIC_DIR and then invoke blog-publish\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_publish=0
      }
      /rebuild_hint "\$PUBLIC_DIR"/ { saw_hint_target=1 }
      END {
        if (!saw_hint_target) {
          print "Blog rebuild hint must point to the staging PUBLIC_DIR, not the live Nginx root." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_blog.sh dist/install_blog.sh
}

check_blog_publish_helper_is_atomic() {
  awk '
      /_write_publish_script\(\)/ { saw_helper=1; next }
      saw_helper && /<< BKSH$/ { in_heredoc=1; saw_tmp=0; saw_parent_dir=0; saw_parent_dir_error=0; saw_safe_rm=0; saw_copy=0; saw_backup=0; saw_swap=0; saw_tmp_cleanup=0; saw_restore=0; next }
      in_heredoc && /DEPLOY_TMP="\\\$\(mktemp -d/ { saw_tmp=1 }
      in_heredoc && /Failed to create a staging directory under \\\$NGINX_ROOT_PARENT/ { saw_tmp_error=1 }
      in_heredoc && /if ! mkdir -p "\\\$NGINX_ROOT_PARENT"; then/ { saw_parent_dir=1 }
      in_heredoc && /Failed to create the Nginx root parent: \\\$NGINX_ROOT_PARENT/ { saw_parent_dir_error=1 }
      in_heredoc && /safe_rm_dir\(\)/ { saw_safe_rm=1 }
      in_heredoc && /cp -a "\\\$\{PUBLIC_DIR\}\/\." "\\\$DEPLOY_TMP\/"/ { saw_copy=1 }
      in_heredoc && /mv "\\\$NGINX_ROOT" "\\\$DEPLOY_BAK"/ { saw_backup=1 }
      in_heredoc && /mv "\\\$DEPLOY_TMP" "\\\$NGINX_ROOT"/ { saw_swap=1 }
      in_heredoc && /if \[\[ -e "\\\$DEPLOY_BAK" \|\| -L "\\\$DEPLOY_BAK" \]\]; then/ { saw_backup_cleanup_if=1 }
      in_heredoc && /rm -rf "\\\$DEPLOY_TMP"/ { saw_tmp_cleanup=1 }
      in_heredoc && /restore_nginx_root_backup\(\)/ { saw_restore=1 }
      in_heredoc && /^BKSH$/ {
        if (!(saw_tmp && saw_tmp_error && saw_parent_dir && saw_parent_dir_error && saw_safe_rm && saw_copy && saw_backup && saw_swap && saw_backup_cleanup_if && saw_tmp_cleanup && saw_restore)) {
          printf "%s Blog publish helper must report directory/temp creation failures, stage output, clean up previous backups explicitly, clean up failed staging directories, back up the live root, and restore safely on failure\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_heredoc=0
        saw_heredoc=1
      }
      END {
        if (!(saw_helper && saw_heredoc)) {
          print "Blog publish helper verifier did not observe the generated helper script body." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_blog.sh dist/install_blog.sh
}

main() {
  local target="${1:-all}"
  case "$target" in
    syntax)
      check_shell_syntax
      echo "Syntax verification passed"
      return 0
      ;;
    release)
      check_shell_syntax
      build_verified_release
      check_release_syntax
      check_no_release_temp_files
      echo "Release verification passed"
      return 0
      ;;
    dispatch)
      build_verified_release
      check_localized_dispatch
      check_doctor_dispatch
      check_app_help_dispatch
      check_status_json_dispatch
      check_doctor_validates_saved_config
      check_newapi_uninstall_supports_noninteractive_mode
      check_sub2api_uninstall_supports_noninteractive_mode
      check_vaultwarden_uninstall_supports_noninteractive_mode
      check_blog_uninstall_supports_noninteractive_mode
      check_cyberstrikeai_uninstall_supports_noninteractive_mode
      check_blog_status_dispatch
      check_no_color_output
      check_no_argument_menu
      check_manager_list
      check_app_registry_metadata
      check_blog_localized_defaults
      check_app_localized_descriptions
      echo "Dispatch verification passed"
      return 0
      ;;
    all) ;;
    help|-h|--help)
      usage
      return 0
      ;;
    *)
      usage
      echo "Unknown verification target: ${target}" >&2
      return 1
      ;;
  esac

  check_shell_syntax
  build_verified_release
  check_release_syntax
  check_localized_dispatch
  check_doctor_dispatch
  check_app_help_dispatch
  check_status_json_dispatch
  check_doctor_validates_saved_config
  check_newapi_uninstall_supports_noninteractive_mode
  check_sub2api_uninstall_supports_noninteractive_mode
  check_vaultwarden_uninstall_supports_noninteractive_mode
  check_blog_uninstall_supports_noninteractive_mode
  check_cyberstrikeai_uninstall_supports_noninteractive_mode
  check_blog_status_dispatch
  check_no_color_output
  check_no_argument_menu
  check_manager_list
  check_app_registry_metadata
  check_blog_localized_defaults
  check_app_localized_descriptions
  check_no_hardcoded_chinese_impl
  check_no_chinese_comments
  check_no_release_temp_files
  check_release_build_outputs_are_atomic
  check_bundled_impl_temp_names_are_random
  check_bundled_impl_dir_security_failure_cleanup
  check_bundled_impl_cleanup
  check_bundled_impl_failure_cleanup
  check_safe_path_guard
  check_managed_paths_are_validated
  check_tickflow_preflight_defers_docker_runtime_checks
  check_tickflow_env_rewrites_preserve_existing_secrets
  check_tickflow_paths_are_guarded
  check_safe_rm_dir_is_idempotent
  check_atomic_helpers_are_atomic
  check_binary_helpers_are_atomic
  check_systemd_helper_is_atomic
  check_service_status_label
  check_config_crlf_handling
  check_config_write_failure_cleanup
  check_unsafe_config_loads_fail_closed
  check_config_save_failures_are_explicit
  check_blog_config_persistence
  check_tickflow_config_files_are_atomic
  check_tickflow_systemd_shell_paths_are_quoted
  check_tickflow_systemctl_failures_are_reported
  check_tickflow_manual_backup_is_explicit
  check_sub2api_codename_resolution
  check_no_unsupported_systemctl_options
  check_no_fixed_tmp_downloads
  check_keyring_writes_are_atomic
  check_apt_sources_are_atomic
  check_iptables_rules_are_atomic
  check_random_head_pipelines_handle_sigpipe
  check_summary_ip_detection_has_fallback
  check_systemctl_status_diagnostics_are_nonfatal
  check_status_commands_allow_non_root
  check_vaultwarden_status_display_commands_are_nonfatal
  check_vaultwarden_find_head_pipelines_are_nonfatal
  check_cyberstrikeai_display_sizes_are_nonfatal
  check_api_status_directory_sizes_are_nonfatal
  check_api_ports_are_validated
  check_cyberstrikeai_ports_are_validated
  check_cyberstrikeai_booleans_are_validated
  check_nginx_domains_are_validated
  check_config_value_validators
  check_vaultwarden_config_values_are_validated
  check_status_port_matches_are_bounded
  check_go_tarball_failures_cleanup
  check_cyberstrikeai_go_version_parse_failures_are_explicit
  check_cyberstrikeai_go_restore_failures_are_reported
  check_cyberstrikeai_pip_upgrade_failures_are_reported
  check_cyberstrikeai_python_env_failures_are_reported
  check_cyberstrikeai_repo_go_install_failures_are_reported
  check_vaultwarden_apt_update_failures_are_reported
  check_vaultwarden_workdir_cleanup_traps_are_nonfatal
  check_optional_directory_cleanup_is_nonfatal
  check_blog_dependency_failures_are_reported
  check_blog_hugo_install_failures_are_actionable
  check_blog_site_setup_failures_are_explicit
  check_newapi_dependency_failures_are_reported
  check_newapi_runtime_dir_failures_are_explicit
  check_cyberstrikeai_dependency_failures_are_reported
  check_sub2api_apt_failures_are_reported
  check_sub2api_rpm_dependency_failures_are_reported
  check_sub2api_runtime_dir_failures_are_explicit
  check_backup_script_dir_failures_are_explicit
  check_vaultwarden_runtime_dir_failures_are_explicit
  check_vaultwarden_backup_failures_include_followup_guidance
  check_preupdate_backup_warnings_include_followup_guidance
  check_preupdate_backup_logs_match_guidance
  check_mutating_actions_acquire_locks
  check_update_backs_up_before_stop
  check_update_binary_backups_are_atomic
  check_old_backup_cleanup_reports_failures
  check_uninstall_binary_cleanup_reports_failures
  check_sub2api_extract_move_failure_cleanup
  check_cyberstrikeai_runtime_dir_failures_are_explicit
  check_cyberstrikeai_source_and_build_prep_failures_are_explicit
  check_sub2api_pg_dump_errors_stay_out_of_backups
  check_sub2api_summary_does_not_print_pg_password
  check_sub2api_pg_password_is_escaped
  check_cyberstrikeai_build_temp_cleanup
  check_cyberstrikeai_rollback_restore_is_validated
  check_cyberstrikeai_backups_are_atomic
  check_cyberstrikeai_config_patch_is_atomic
  check_backup_temp_moves_handle_failure
  check_binary_replacements_handle_failure
  check_binary_restores_validate_permissions
  check_download_validation_failures_cleanup
  check_download_temp_creation_failures_are_explicit
  check_vaultwarden_env_file_is_atomic
  check_vaultwarden_binary_installs_are_atomic
  check_vaultwarden_admin_token_file_is_private
  check_vaultwarden_extract_tool_is_pinned_and_verified
  check_newapi_secret_uses_private_env_file
  check_systemd_units_are_atomic
  check_systemd_daemon_reloads_are_explicit
  check_backup_scripts_are_atomic
  check_generated_backup_headers_are_shell_quoted
  check_generated_backup_scripts_handle_missing_dirs
  check_manual_backup_retention_is_normalized
  check_backup_retention_cleanup_reports_failures
  check_optional_count_messages_are_nonfatal
  check_silent_backup_tar_diagnostics_use_stderr
  check_tar_diagnostics_use_stderr
  check_cron_logrotate_are_atomic
  check_nginx_configs_are_atomic
  check_nginx_main_config_edits_are_atomic
  check_nginx_test_failures_report_diagnostics
  check_sub2api_nginx_reload_results_are_checked
  check_sub2api_postgres_rpm_setup_failures_are_explicit
  check_sub2api_dependency_services_start_before_success
  check_newapi_service_start_paths_are_explicit
  check_cyberstrikeai_service_start_paths_are_explicit
  check_sub2api_nginx_install_starts_service_explicitly
  check_sub2api_service_start_paths_are_explicit
  check_sub2api_enable_failures_are_reported
  check_sub2api_redis_service_handling_is_explicit
  check_blog_enable_failures_are_reported
  check_blog_nginx_start_path_is_explicit
  check_blog_install_summary_matches_local_health
  check_blog_restore_action
  check_newapi_enable_failures_are_reported
  check_newapi_manual_backup_wal_result_is_explicit
  check_cyberstrikeai_enable_failures_are_reported
  check_vaultwarden_enable_failures_are_reported
  check_vaultwarden_certbot_cron_failures_are_reported
  check_vaultwarden_runtime_service_starts_are_explicit
  check_vaultwarden_service_start_paths_are_explicit
  check_vaultwarden_install_cleanup_reports_systemctl_failures
  check_vaultwarden_update_stop_failure_aborts_before_replace
  check_vaultwarden_uninstall_stop_disable_failures_are_reported
  check_sub2api_update_rollbacks_report_restart_failures
  check_sub2api_install_cleanup_reports_systemctl_failures
  check_sub2api_update_stop_failure_aborts_before_replace
  check_sub2api_update_rollback_stop_failure_aborts_restore
  check_sub2api_uninstall_stop_disable_failures_are_reported
  check_sub2api_install_summary_matches_runtime_state
  check_sub2api_health_checks_are_nonfatal_outside_install
  check_cyberstrikeai_update_rollbacks_report_restart_failures
  check_cyberstrikeai_update_rollback_stop_failure_aborts_restore
  check_cyberstrikeai_uninstall_stop_disable_failures_are_reported
  check_cyberstrikeai_install_summary_matches_health_state
  check_cyberstrikeai_nginx_health_probe_matches_server_name
  check_cyberstrikeai_health_checks_are_nonfatal_outside_install
  check_newapi_update_rollbacks_report_restart_failures
  check_newapi_install_cleanup_reports_systemctl_failures
  check_newapi_update_stop_failure_aborts_before_replace
  check_newapi_update_rollback_stop_failure_aborts_restore
  check_newapi_uninstall_stop_disable_failures_are_reported
  check_newapi_install_summary_matches_health_state
  check_newapi_health_checks_are_nonfatal_outside_install
  check_vaultwarden_install_summary_matches_health_state
  check_vaultwarden_status_health_guidance_matches_local_probe
  check_firewall_success_paths_validate_command_results
  check_cyberstrikeai_nginx_apply_preserves_reload_diagnostics
  check_uninstall_nginx_paths_preserve_diagnostics
  check_fail2ban_configs_are_atomic
  check_vaultwarden_fail2ban_restart_failures_are_reported
  check_vaultwarden_result_chains_are_explicit
  check_user_deletion_paths_are_explicit
  check_sub2api_manual_backup_warnings_are_actionable
  check_vaultwarden_webvault_restore_cleans_partial
  check_vaultwarden_webvault_replacements_are_atomic
  check_vaultwarden_install_webvault_replacement_is_recoverable
  check_vaultwarden_webvault_update_warnings_are_actionable
  check_vaultwarden_webvault_archives_are_validated
  check_blog_static_deploy_swaps_tree
  check_blog_static_deploy_failures_are_actionable
  check_blog_site_files_are_atomic
  check_blog_publish_guidance_uses_staging_output
  check_blog_publish_helper_is_atomic
  echo "Verification passed"
}

main "$@"
