#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BASH_BIN="${BASH_BIN:-bash}"

cd "$ROOT_DIR"

check_shell_syntax() {
  local file
  while IFS= read -r file; do
    "$BASH_BIN" -n "$file"
  done < <(find apps bin impl lib tools -name '*.sh' -type f | sort)
}

check_release_syntax() {
  local file
  while IFS= read -r file; do
    "$BASH_BIN" -n "$file"
  done < <(find dist -maxdepth 1 -name 'install_*.sh' -type f | sort)
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

check_localized_dispatch() {
  expect_failure_output en install_newapi.sh "Invalid choice"
  expect_failure_output zh install_newapi.sh "无效选项"
  expect_failure_output en dist/install_newapi.sh "Invalid choice"
  expect_failure_output zh dist/install_newapi.sh "无效选项"
  expect_failure_output en install_blog.sh "does not support update" update
  expect_failure_output zh install_blog.sh "暂不支持 update" update
  expect_failure_output en dist/install_blog.sh "does not support update" update
  expect_failure_output zh dist/install_blog.sh "暂不支持 update" update
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
  expect_menu_output en install_blog.sh "Choose an action"
  expect_menu_output zh install_blog.sh "请选择操作"
  expect_menu_output en dist/install_blog.sh "Choose an action"
  expect_menu_output zh dist/install_blog.sh "请选择操作"
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
}

check_no_hardcoded_chinese_impl() {
  if LC_ALL=C.UTF-8 grep -R -nP '[\p{Han}]' impl; then
    echo "Implementation scripts must use i18n keys instead of hardcoded Chinese text." >&2
    return 1
  fi
}

check_no_chinese_comments() {
  if LC_ALL=C.UTF-8 grep -R -nP '^\s*#.*[\p{Han}]' apps bin impl lib tools dist install_*.sh; then
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
  if find dist -maxdepth 1 -name 'install_*.sh.*' -type f | grep -q .; then
    echo "Unexpected release build temporary file in dist/" >&2
    find dist -maxdepth 1 -name 'install_*.sh.*' -type f >&2
    return 1
  fi
}

check_release_build_outputs_are_atomic() {
  if grep -n '^[[:space:]]*} > "\$output"$' tools/build-release.sh 2>/dev/null; then
    echo "Release scripts must be generated to a temporary file before replacement." >&2
    return 1
  fi
  awk '
      /output_tmp="\$\(mktemp "\$\{output\}\.XXXXXX"\)"/ { saw_tmp=1 }
      /} > "\$output_tmp"/ { saw_write=1 }
      /mv "\$output_tmp" "\$output"/ { saw_mv=1 }
      /rm -f "\$output_tmp"/ { saw_cleanup=1 }
      END {
        if (!(saw_tmp && saw_write && saw_mv && saw_cleanup)) {
          print "Release script generation must stage, replace, and clean up temporary files." > "/dev/stderr"
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

  PATH="${tmp_dir}:$PATH" "$BASH_BIN" -c '
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
      /(pg_key_tmp|redis_key_tmp)="?\$\(mktemp/ { saw_tmp=1 }
      /(curl .* -o "\$pg_key_tmp"|gpg .* --dearmor -o "\$redis_key_tmp")/ { saw_write=1 }
      /mv "\$(pg_key_tmp|redis_key_tmp)" "\$(pg_keyring|redis_keyring)"/ { saw_mv=1 }
      /rm -f "\$(pg_key_tmp|redis_key_tmp)"/ { saw_cleanup=1 }
      END {
        if (!(saw_tmp && saw_write && saw_mv && saw_cleanup)) {
          print "Apt keyring writes must stage, replace, and clean up temporary files." > "/dev/stderr"
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
      /(pg_source_tmp|redis_source_tmp)=\$\(mktemp/ { saw_tmp=1 }
      /mv "\$(pg_source_tmp|redis_source_tmp)" "\$(pg_source_list|redis_source_list)"/ { saw_mv=1 }
      /rm -f "\$(pg_source_tmp|redis_source_tmp)"/ { saw_cleanup=1 }
      END {
        if (!(saw_tmp && saw_mv && saw_cleanup)) {
          print "Apt source list writes must stage, replace, and clean up temporary files." > "/dev/stderr"
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
      /iptables_tmp=\$\(mktemp "\$\{iptables_rules\}\.XXXXXX"\)/ { saw_tmp=1 }
      /iptables-save > "\$iptables_tmp"/ { saw_save=1 }
      /mv "\$iptables_tmp" "\$iptables_rules"/ { saw_mv=1 }
      /rm -f "\$iptables_tmp"/ { saw_cleanup=1 }
      END {
        if (!(saw_tmp && saw_save && saw_mv && saw_cleanup)) {
          print "iptables rules writes must stage, replace, and clean up temporary files." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh dist/install_newapi.sh dist/install_sub2api.sh
}

check_random_head_pipelines_handle_sigpipe() {
  if grep -R -nE 'rand .*\\|.*head -c [0-9]+\\)$|tr -dc .*\\| head -c [0-9]+\\)$' impl dist 2>/dev/null; then
    echo "Random byte pipelines ending in head -c need an explicit successful terminator under pipefail." >&2
    return 1
  fi
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
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
  awk '
      /write_tool_symlink\(\)/ { in_func=1; saw_tmp=0; saw_unlink=0; saw_ln=0; saw_mv=0; saw_cleanup=0; next }
      in_func && /link_tmp=\$\(mktemp "\$\{link_path\}\.XXXXXX"\)/ { saw_tmp=1 }
      in_func && /rm -f "\$link_tmp"/ { saw_unlink=1; saw_cleanup=1 }
      in_func && /ln -s "\$target" "\$link_tmp"/ { saw_ln=1 }
      in_func && /mv -Tf "\$link_tmp" "\$link_path"/ { saw_mv=1 }
      in_func && /^}/ {
        if (!(saw_tmp && saw_unlink && saw_ln && saw_mv && saw_cleanup)) {
          printf "%s Go tool symlink helper must stage, replace, and clean up temporary symlinks\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh
}

check_mutating_installs_acquire_locks() {
  "$BASH_BIN" -c '
    set -euo pipefail
    for file in impl/install_*.sh; do
      if grep -q "do_install()" "$file" && ! grep -q "acquire_lock" "$file"; then
        echo "Install script does not acquire a deployment lock: $file" >&2
        exit 1
      fi
    done
  '
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
      /_backup_current_binary\(\)|backup_vaultwarden_binary\(\)/ { in_func=1; saw_tmp=0; saw_cp=0; saw_mv=0; saw_cleanup=0; next }
      in_func && /backup_tmp=\$\(mktemp "\$\{backup_path\}\.XXXXXX"\)/ { saw_tmp=1 }
      in_func && /cp "\$(BIN_PATH|VW_BIN)" "\$backup_tmp"/ { saw_cp=1 }
      in_func && /mv "\$backup_tmp" "\$backup_path"/ { saw_mv=1 }
      in_func && /rm -f "\$backup_tmp"/ { saw_cleanup=1 }
      in_func && /^}/ {
        if (!(saw_tmp && saw_cp && saw_mv && saw_cleanup)) {
          printf "%s binary backup helper must stage, replace, and clean up temporary backups\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh impl/install_vaultwarden.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_vaultwarden.sh
}

check_sub2api_extract_move_failure_cleanup() {
  if grep -R -n '^[[:space:]]*mv "$bin_path" "$tmp_bin"$' impl/install_sub2api.sh dist/install_sub2api.sh 2>/dev/null; then
    echo "sub2api extraction must clean up temporary files if moving the binary fails." >&2
    return 1
  fi
}

check_sub2api_pg_dump_errors_stay_out_of_backups() {
  if grep -R -nE 'pg_dump "\$\{PG_DSN\}" 2>&1 \| gzip >|pg_dump "\$PG_DSN" 2>&1 \| gzip >' \
      impl/install_sub2api.sh dist/install_sub2api.sh 2>/dev/null; then
    echo "Sub2API pg_dump backups must not mix stderr into compressed SQL archives." >&2
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
    ' impl/install_sub2api.sh dist/install_sub2api.sh
}

check_cyberstrikeai_build_temp_cleanup() {
  if grep -R -nE '^[[:space:]]*(go build|chmod 0755 "\$tmp_bin"|mv "\$tmp_bin" "\$BIN_PATH")' impl/install_cyberstrikeai.sh dist/install_cyberstrikeai.sh 2>/dev/null; then
    echo "CyberStrikeAI binary build must clean up the temporary binary on build, chmod, and move failures." >&2
    return 1
  fi
  awk '
      /if ! go build .*"\$tmp_bin"/ { in_block=1; saw_build_cleanup=0; next }
      in_block && /rm -f "\$tmp_bin"/ { saw_build_cleanup=1 }
      in_block && /error "\$\(t app\.cyberstrikeai\.error\.binary_build\)"/ {
        if (!saw_build_cleanup) {
          print "CyberStrikeAI build failure does not clean up the temporary binary." > "/dev/stderr"
          exit 1
        }
        in_block=0
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
      /restore_update_backup\(\)/ { in_func=1; saw_bin_tmp=0; saw_bin_cp=0; saw_chmod=0; saw_bin_chown=0; saw_bin_mv=0; saw_config_tmp=0; saw_config_cp=0; saw_config_chown=0; saw_config_mv=0; next }
      in_func && /bin_restore_tmp=\$\(mktemp "\$\{BIN_PATH\}\.restore\.XXXXXX"\)/ { saw_bin_tmp=1 }
      in_func && /cp "\$bin_backup" "\$bin_restore_tmp"/ { saw_bin_cp=1 }
      in_func && /chmod 0755 "\$bin_restore_tmp"/ { saw_chmod=1 }
      in_func && /chown "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$bin_restore_tmp"/ { saw_bin_chown=1 }
      in_func && /mv "\$bin_restore_tmp" "\$BIN_PATH"/ { saw_bin_mv=1 }
      in_func && /config_restore_tmp=\$\(mktemp "\$\{CONFIG_FILE\}\.restore\.XXXXXX"\)/ { saw_config_tmp=1 }
      in_func && /cp "\$config_backup" "\$config_restore_tmp"/ { saw_config_cp=1 }
      in_func && /chown "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$config_restore_tmp"/ { saw_config_chown=1 }
      in_func && /mv "\$config_restore_tmp" "\$CONFIG_FILE"/ { saw_config_mv=1 }
      in_func && /^}/ {
        if (!(saw_bin_tmp && saw_bin_cp && saw_chmod && saw_bin_chown && saw_bin_mv && saw_config_tmp && saw_config_cp && saw_config_chown && saw_config_mv)) {
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
      /write_backup_file\(\)/ { in_func=1; saw_tmp=0; saw_cp=0; saw_mv=0; saw_cleanup=0; next }
      in_func && /backup_tmp=\$\(mktemp "\$\{backup_path\}\.XXXXXX"\)/ { saw_tmp=1 }
      in_func && /cp "\$source_path" "\$backup_tmp"/ { saw_cp=1 }
      in_func && /mv "\$backup_tmp" "\$backup_path"/ { saw_mv=1 }
      in_func && /rm -f "\$backup_tmp"/ { saw_cleanup=1 }
      in_func && /^}/ {
        if (!(saw_tmp && saw_cp && saw_mv && saw_cleanup)) {
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
      /_restore_moved_binary_backup\(\)/ { in_func=1; saw_mv=0; saw_chmod=0; saw_chown=0; next }
      in_func && /mv "\$backup_path" "\$BIN_PATH"/ { saw_mv=1 }
      in_func && /chmod \+x "\$BIN_PATH"/ { saw_chmod=1 }
      in_func && /chown "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$BIN_PATH"/ { saw_chown=1 }
      in_func && /^}/ {
        if (!(saw_mv && saw_chmod && saw_chown)) {
          printf "%s moved binary backup restores must validate move, mode, and ownership\n", FILENAME > "/dev/stderr"
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
      /_restore_binary_backup\(\)/ { in_func=1; saw_tmp=0; saw_cp=0; saw_chmod=0; saw_chown=0; saw_mv=0; next }
      in_func && /restore_tmp=\$\(mktemp "\$\{BIN_PATH\}\.restore\.XXXXXX"\)/ { saw_tmp=1 }
      in_func && /cp "\$backup_path" "\$restore_tmp"/ { saw_cp=1 }
      in_func && /chmod \+x "\$restore_tmp"/ { saw_chmod=1 }
      in_func && /chown "\$\{SERVICE_USER\}:\$\{SERVICE_USER\}" "\$restore_tmp"/ { saw_chown=1 }
      in_func && /mv "\$restore_tmp" "\$BIN_PATH"/ { saw_mv=1 }
      in_func && /^}/ {
        if (!(saw_tmp && saw_cp && saw_chmod && saw_chown && saw_mv)) {
          printf "%s restore helper must stage and atomically restore binary mode and ownership\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_func=0
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh dist/install_newapi.sh dist/install_sub2api.sh
}

check_download_validation_failures_cleanup() {
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
      /verify_checksum\(\)/ { in_checksum=1; next }
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
}

check_vaultwarden_env_file_is_atomic() {
  if grep -R -n '^[[:space:]]*cat > "\$VW_ENV_FILE"' impl/install_vaultwarden.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "Vaultwarden env files contain secrets and must be written through a temporary file before replacement." >&2
    return 1
  fi
  awk '
      /_vw_env_tmp=\$\(mktemp "\$\(dirname "\$VW_ENV_FILE"\)\/\.vaultwarden\.env\./ { saw_tmp=1 }
      /mv "\$_vw_env_tmp" "\$VW_ENV_FILE"/ { saw_mv=1 }
      /rm -f "\$_vw_env_tmp"/ { saw_cleanup=1 }
      END {
        if (!(saw_tmp && saw_mv && saw_cleanup)) {
          print "Vaultwarden env file writes must stage, replace, and clean up temporary files." > "/dev/stderr"
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
      /install_vaultwarden_binary\(\)/ { in_func=1; saw_tmp=0; saw_install=0; saw_mv=0; saw_cleanup=0; next }
      in_func && /bin_tmp=\$\(mktemp "\$\{VW_BIN\}\.XXXXXX"\)/ { saw_tmp=1 }
      in_func && /install -m 755 -o root -g root "\$source_bin" "\$bin_tmp"/ { saw_install=1 }
      in_func && /mv "\$bin_tmp" "\$VW_BIN"/ { saw_mv=1 }
      in_func && /rm -f "\$bin_tmp"/ { saw_cleanup=1 }
      in_func && /^}/ {
        if (!(saw_tmp && saw_install && saw_mv && saw_cleanup)) {
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
      /_token_tmp=\$\(mktemp \/root\/\.vaultwarden-admin-token\.XXXXXX\)/ { saw_tmp=1 }
      /chmod 600 "\$_token_tmp"/ { saw_chmod=1 }
      /printf .*\$ADMIN_PLAIN.*> "\$_token_tmp"/ { saw_write=1 }
      /rm -f "\$_token_tmp"/ { saw_cleanup=1 }
      END {
        if (!(saw_tmp && saw_chmod && saw_write && saw_cleanup)) {
          print "Vaultwarden admin token display files must be private and cleaned up on write failure." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_vaultwarden.sh dist/install_vaultwarden.sh
}

check_systemd_units_are_atomic() {
  if grep -R -nE '^[[:space:]]*cat > "?/etc/systemd/system/|^[[:space:]]*cat > "\/etc\/systemd\/system/\$\{SERVICE_NAME\}\.service"' impl dist 2>/dev/null; then
    echo "systemd unit files must be written through temporary files before replacement." >&2
    return 1
  fi
  awk '
      /unit_tmp=\$\(mktemp "\$\{?unit_path\}?\.XXXXXX"\)/ { saw_tmp=1 }
      /mv "\$unit_tmp" "\$unit_path"/ { saw_mv=1 }
      /rm -f "\$unit_tmp"/ { saw_cleanup=1 }
      END {
        if (!(saw_tmp && saw_mv && saw_cleanup)) {
          print "systemd unit writes must stage, replace, and clean up temporary files." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh impl/install_cyberstrikeai.sh impl/install_vaultwarden.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_cyberstrikeai.sh dist/install_vaultwarden.sh
}

check_backup_scripts_are_atomic() {
  if grep -R -nE '^[[:space:]]*cat (>|>>) /usr/local/bin/.*-backup|^[[:space:]]*cat > "\$BACKUP_SCRIPT"' impl dist 2>/dev/null; then
    echo "Backup scripts must be written through temporary files before replacement." >&2
    return 1
  fi
  awk '
      /backup_tmp=\$\(mktemp/ { saw_tmp=1 }
      /mv "\$backup_tmp" "(\$backup_script|\$BACKUP_SCRIPT)"/ { saw_mv=1 }
      /rm -f "\$backup_tmp"/ { saw_cleanup=1 }
      END {
        if (!(saw_tmp && saw_mv && saw_cleanup)) {
          print "Backup script writes must stage, replace, and clean up temporary files." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_newapi.sh impl/install_sub2api.sh impl/install_cyberstrikeai.sh impl/install_vaultwarden.sh \
      dist/install_newapi.sh dist/install_sub2api.sh dist/install_cyberstrikeai.sh dist/install_vaultwarden.sh
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

check_cron_logrotate_are_atomic() {
  if grep -R -nE '^[[:space:]]*cat > (/etc/logrotate\.d/|"\$LOGROTATE_FILE")|^[[:space:]]*> /etc/cron\.d/|^[[:space:]]*cat > "\$CRON_FILE"' impl dist 2>/dev/null; then
    echo "cron and logrotate configs must be written through temporary files before replacement." >&2
    return 1
  fi
  awk '
      /(cron_tmp|_vw_cron_tmp|logrotate_tmp|_vw_logrotate_tmp)=\$\(mktemp/ { saw_tmp=1 }
      /mv "\$(cron_tmp|_vw_cron_tmp|logrotate_tmp|_vw_logrotate_tmp)" "\$(cron_file|_vw_cron_file|logrotate_file|_vw_logrotate_file|CRON_FILE|LOGROTATE_FILE)"/ { saw_mv=1 }
      /rm -f "\$(cron_tmp|_vw_cron_tmp|logrotate_tmp|_vw_logrotate_tmp)"/ { saw_cleanup=1 }
      END {
        if (!(saw_tmp && saw_mv && saw_cleanup)) {
          print "cron and logrotate config writes must stage, replace, and clean up temporary files." > "/dev/stderr"
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
      /(nginx_tmp|NGINX_TMP)=\$\(mktemp/ { saw_tmp=1 }
      /mv "\$(nginx_tmp|NGINX_TMP)" "\$(nginx_conf|NGINX_CONF)"/ { saw_mv=1 }
      /rm -f "\$(nginx_tmp|NGINX_TMP)"/ { saw_cleanup=1 }
      /_write_nginx_config_file "\$NGINX_CONF"/ { saw_helper=1 }
      END {
        if (!(saw_tmp && saw_mv && saw_cleanup && saw_helper)) {
          print "Nginx site config writes must stage, replace, and clean up temporary files." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_sub2api.sh impl/install_cyberstrikeai.sh impl/install_vaultwarden.sh impl/install_blog.sh \
      dist/install_sub2api.sh dist/install_cyberstrikeai.sh dist/install_vaultwarden.sh dist/install_blog.sh
  awk '
      /_write_nginx_site_link\(\)/ { in_func=1; saw_tmp=0; saw_unlink=0; saw_ln=0; saw_mv=0; saw_cleanup=0; next }
      in_func && /link_tmp=\$\(mktemp "\$\{link_path\}\.XXXXXX"\)/ { saw_tmp=1 }
      in_func && /rm -f "\$link_tmp"/ { saw_unlink=1; saw_cleanup=1 }
      in_func && /ln -s "\$target" "\$link_tmp"/ { saw_ln=1 }
      in_func && /mv -Tf "\$link_tmp" "\$link_path"/ { saw_mv=1 }
      in_func && /^}/ {
        if (!(saw_tmp && saw_unlink && saw_ln && saw_mv && saw_cleanup)) {
          printf "%s Nginx site link helper must stage, replace, and clean up temporary symlinks\n", FILENAME > "/dev/stderr"
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

check_fail2ban_configs_are_atomic() {
  if grep -R -nE '^[[:space:]]*cat > /etc/fail2ban/' impl dist 2>/dev/null; then
    echo "Fail2Ban configs must be written through temporary files before replacement." >&2
    return 1
  fi
  awk '
      /fail2ban_tmp=\$\(mktemp/ { saw_tmp=1 }
      /mv "\$fail2ban_tmp" "\$fail2ban_conf"/ { saw_mv=1 }
      /rm -f "\$fail2ban_tmp"/ { saw_cleanup=1 }
      /_write_fail2ban_config_file \/etc\/fail2ban\// { saw_helper=1 }
      END {
        if (!(saw_tmp && saw_mv && saw_cleanup && saw_helper)) {
          print "Fail2Ban config writes must stage, replace, and clean up temporary files." > "/dev/stderr"
          exit 1
        }
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
      /restore_web_vault_backup\(\)/ { in_helper=1; saw_rm=0; saw_mv=0; saw_chown=0; saw_chmod=0; next }
      in_helper && /rm -rf "\$VW_WEB_DIR"/ { saw_rm=1 }
      in_helper && /mv "\$backup_dir" "\$VW_WEB_DIR"/ { saw_mv=1 }
      in_helper && /chown -R "\$\{VW_USER\}:\$\{VW_GROUP\}" "\$VW_WEB_DIR"/ { saw_chown=1 }
      in_helper && /chmod -R 750 "\$VW_WEB_DIR"/ { saw_chmod=1 }
      in_helper && /^}/ {
        if (!(saw_rm && saw_mv && saw_chown && saw_chmod)) {
          printf "%s restore helper must validate Web Vault replacement, ownership, and mode\n", FILENAME > "/dev/stderr"
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
  awk '
      /restore_nginx_root_backup\(\)/ { in_helper=1; saw_rm=0; saw_restore=0; next }
      in_helper && /rm -rf "\$NGINX_ROOT"/ { saw_rm=1 }
      in_helper && /mv "\$DEPLOY_BAK" "\$NGINX_ROOT"/ { saw_restore=1 }
      in_helper && /^}/ {
        if (!(saw_rm && saw_restore)) {
          print "Blog static deployment restore helper must remove partial output and restore the previous root." > "/dev/stderr"
          exit 1
        }
        in_helper=0
      }
      /DEPLOY_TMP="\$\(mktemp -d/ { saw_tmp=1 }
      /mv "\$NGINX_ROOT" "\$DEPLOY_BAK"/ { saw_backup=1 }
      /mv "\$DEPLOY_TMP" "\$NGINX_ROOT"/ { saw_swap=1 }
      /restore_nginx_root_backup/ { saw_restore=1 }
      END {
        if (!(saw_tmp && saw_backup && saw_swap && saw_restore)) {
          print "Blog static deployment must stage, swap, and restore the Nginx root." > "/dev/stderr"
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
      /backup_blog_file\(\)/ { in_backup=1; saw_tmp=0; saw_cp=0; saw_mv=0; saw_cleanup=0; next }
      in_backup && /backup_tmp=\$\(mktemp "\$\{backup_path\}\.XXXXXX"\)/ { saw_tmp=1 }
      in_backup && /cp "\$source_path" "\$backup_tmp"/ { saw_cp=1 }
      in_backup && /mv "\$backup_tmp" "\$backup_path"/ { saw_mv=1 }
      in_backup && /rm -f "\$backup_tmp"/ { saw_cleanup=1 }
      in_backup && /^}/ {
        if (!(saw_tmp && saw_cp && saw_mv && saw_cleanup)) {
          print "Blog config backup helper must stage, replace, and clean up temporary backups." > "/dev/stderr"
          exit 1
        }
        in_backup=0
      }
      /target_tmp=\$\(mktemp "\$\{target_dir\}\/\.\$\(basename "\$target_path"\)\.XXXXXX"\)/ { saw_tmp=1 }
      /mv "\$target_tmp" "\$target_path"/ { saw_mv=1 }
      /rm -f "\$target_tmp"/ { saw_cleanup=1 }
      /_write_blog_file "?\$\{?(SITE_DIR|CMS_ADMIN_DIR)\}?/ || /_write_blog_file "\$CONFIG_FILE"/ { saw_helper=1 }
      END {
        if (!(saw_tmp && saw_mv && saw_cleanup && saw_helper)) {
          print "Blog site file writes must stage, replace, and clean up temporary files." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_blog.sh dist/install_blog.sh
}

main() {
  check_shell_syntax
  DEPLOY_BUILD_COMMIT=verified SOURCE_DATE_EPOCH=0 "$BASH_BIN" tools/build-release.sh all >/dev/null
  check_release_syntax
  check_localized_dispatch
  check_no_argument_menu
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
  check_service_status_label
  check_config_crlf_handling
  check_config_write_failure_cleanup
  check_sub2api_codename_resolution
  check_no_unsupported_systemctl_options
  check_no_fixed_tmp_downloads
  check_keyring_writes_are_atomic
  check_apt_sources_are_atomic
  check_iptables_rules_are_atomic
  check_random_head_pipelines_handle_sigpipe
  check_go_tarball_failures_cleanup
  check_mutating_installs_acquire_locks
  check_update_backs_up_before_stop
  check_update_binary_backups_are_atomic
  check_sub2api_extract_move_failure_cleanup
  check_sub2api_pg_dump_errors_stay_out_of_backups
  check_cyberstrikeai_build_temp_cleanup
  check_cyberstrikeai_rollback_restore_is_validated
  check_cyberstrikeai_backups_are_atomic
  check_cyberstrikeai_config_patch_is_atomic
  check_backup_temp_moves_handle_failure
  check_binary_replacements_handle_failure
  check_binary_restores_validate_permissions
  check_download_validation_failures_cleanup
  check_vaultwarden_env_file_is_atomic
  check_vaultwarden_binary_installs_are_atomic
  check_vaultwarden_admin_token_file_is_private
  check_systemd_units_are_atomic
  check_backup_scripts_are_atomic
  check_silent_backup_tar_diagnostics_use_stderr
  check_cron_logrotate_are_atomic
  check_nginx_configs_are_atomic
  check_nginx_main_config_edits_are_atomic
  check_fail2ban_configs_are_atomic
  check_vaultwarden_webvault_restore_cleans_partial
  check_vaultwarden_install_webvault_replacement_is_recoverable
  check_blog_static_deploy_swaps_tree
  check_blog_site_files_are_atomic
  echo "Verification passed"
}

main "$@"
