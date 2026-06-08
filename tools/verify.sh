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
      /_ensure_nginx_running\(\)/ { saw_helper=1 }
      /app\.sub2api\.error\.nginx_start/ { saw_error=1 }
      /if ! systemctl start nginx 2>\/dev\/null; then/ { saw_start_if=1 }
      /if ! systemctl is-active --quiet nginx 2>\/dev\/null; then/ { saw_active_if=1 }
      /_install_nginx\(\)/ { in_block=1; saw_ensure=0; saw_success=0; next }
      in_block && /_ensure_nginx_running/ { saw_ensure=1 }
      in_block && /success "\$\(t app\.sub2api\.success\.nginx_installed\)"/ { saw_success=1 }
      in_block && /^}/ {
        if (!(saw_helper && saw_error && saw_start_if && saw_active_if && saw_ensure && saw_success)) {
          printf "%s Sub2API nginx installation must ensure the service starts before reporting success\n", FILENAME > "/dev/stderr"
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
      /step "\$\(t app\.blog\.step_start_nginx\)"/ { in_block=1; saw_restart_if=0; saw_active_check=0; next }
      in_block && /if systemctl restart nginx; then/ { saw_restart_if=1 }
      in_block && /if systemctl is-active --quiet nginx; then/ { saw_active_check=1 }
      in_block && /step "\$\(t app\.blog\.step_health\)"/ {
        if (!(saw_restart_if && saw_active_check)) {
          printf "%s Blog nginx startup must keep restart failure handling explicit before the health check\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
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
      /step "\$\(t app\.newapi\.step\.manual_backup\)"/ { in_backup=1; saw_wal_if=0; saw_wal_success=0; saw_wal_warn=0; next }
      in_backup && /if sqlite3 "\$DB_FILE" "PRAGMA wal_checkpoint\(TRUNCATE\);" 2>\/dev\/null; then/ { saw_wal_if=1 }
      in_backup && /success "\$\(t app\.newapi\.success\.wal\)"/ { saw_wal_success=1 }
      in_backup && /warn "\$\(t app\.newapi\.warn\.wal\)"/ { saw_wal_warn=1 }
      in_backup && /local _ic/ {
        if (!(saw_wal_if && saw_wal_success && saw_wal_warn)) {
          printf "%s NewAPI manual backup WAL checkpoint result must branch explicitly before integrity checks\n", FILENAME > "/dev/stderr"
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

check_vaultwarden_webvault_replacements_are_atomic() {
  if grep -R -nE 'cp -a "\$EXTRACTED_WEBVAULT_PATH" "\$VW_WEB_DIR"|tar -xzf "\$\{WORK_DIR\}/web-vault\.tar\.gz" -C "\$\(dirname "\$VW_WEB_DIR"\)"' \
      impl/install_vaultwarden.sh dist/install_vaultwarden.sh 2>/dev/null; then
    echo "Vaultwarden Web Vault installs and updates must stage replacement trees before swapping them live." >&2
    return 1
  fi
  awk '
      /deploy_web_vault_from_dir\(\)/ { in_helper=1; saw_tmp=0; saw_copy=0; saw_chown=0; saw_chmod=0; saw_backup=0; saw_swap=0; saw_cleanup=0; next }
      in_helper && /staged_dir=\$\(mktemp -d "\$\{VW_WEB_DIR\}\.new\.XXXXXX"\)/ { saw_tmp=1 }
      in_helper && /cp -a "\$\{source_dir\}\/\." "\$staged_dir\/"/ { saw_copy=1 }
      in_helper && /chown -R "\$\{VW_USER\}:\$\{VW_GROUP\}" "\$staged_dir"/ { saw_chown=1 }
      in_helper && /chmod -R 750 "\$staged_dir"/ { saw_chmod=1 }
      in_helper && /mv "\$VW_WEB_DIR" "\$backup_dir"/ { saw_backup=1 }
      in_helper && /mv "\$staged_dir" "\$VW_WEB_DIR"/ { saw_swap=1 }
      in_helper && /rm -rf "\$staged_dir"/ { saw_cleanup=1 }
      in_helper && /^}/ {
        if (!(saw_tmp && saw_copy && saw_chown && saw_chmod && saw_backup && saw_swap && saw_cleanup)) {
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
  check_cyberstrikeai_go_restore_failures_are_reported
  check_preupdate_backup_warnings_include_followup_guidance
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
  check_newapi_enable_failures_are_reported
  check_newapi_manual_backup_wal_result_is_explicit
  check_cyberstrikeai_enable_failures_are_reported
  check_vaultwarden_enable_failures_are_reported
  check_vaultwarden_runtime_service_starts_are_explicit
  check_vaultwarden_service_start_paths_are_explicit
  check_sub2api_update_rollbacks_report_restart_failures
  check_cyberstrikeai_update_rollbacks_report_restart_failures
  check_newapi_update_rollbacks_report_restart_failures
  check_firewall_success_paths_validate_command_results
  check_cyberstrikeai_nginx_apply_preserves_reload_diagnostics
  check_uninstall_nginx_paths_preserve_diagnostics
  check_fail2ban_configs_are_atomic
  check_vaultwarden_fail2ban_restart_failures_are_reported
  check_vaultwarden_result_chains_are_explicit
  check_user_deletion_paths_are_explicit
  check_vaultwarden_webvault_restore_cleans_partial
  check_vaultwarden_webvault_replacements_are_atomic
  check_vaultwarden_install_webvault_replacement_is_recoverable
  check_blog_static_deploy_swaps_tree
  check_blog_site_files_are_atomic
  echo "Verification passed"
}

main "$@"
