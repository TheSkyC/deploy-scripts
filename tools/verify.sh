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
}

main() {
  check_shell_syntax
  DEPLOY_BUILD_COMMIT=verified SOURCE_DATE_EPOCH=0 "$BASH_BIN" tools/build-release.sh all >/dev/null
  check_release_syntax
  check_localized_dispatch
  check_blog_localized_defaults
  check_app_localized_descriptions
  check_no_hardcoded_chinese_impl
  check_no_chinese_comments
  check_no_release_temp_files
  echo "Verification passed"
}

main "$@"
