# shellcheck shell=bash
# shellcheck source=../verify.sh
# Verify checks for the blog app (apps/blog.sh, impl/install_hugo_blog.sh).

check_blog_status_backup_projection() {
  local output
  output="$($BASH_BIN -c '
    set -euo pipefail
    tmp_dir="$(mktemp -d)"
    backup_dir="$tmp_dir/blog backups"
    mkdir -p "$backup_dir"
    touch -d "2026-08-20 12:34:56 UTC" "$backup_dir/blog_20260820123456.tar.gz"
    source lib/core.sh
    APP_ID=blog
    APP_NAME="Hugo Blog"
    BLOG_BACKUP_DIR="$backup_dir"
    app_conf_file() { printf "%s" "$tmp_dir/missing.conf"; }
    source impl/install_hugo_blog.sh
    _blog_status_backup
    rm -rf "$tmp_dir"
  ')"
  python -c 'import json,sys; x=json.loads(sys.argv[1]); assert x["state"] == "available"; assert "blog backups" in x["path"]; assert x["path"].endswith("blog_20260820123456.tar.gz"); assert x["last_success_at"]' "$output"
  grep -Fq 'APP_STATUS_BACKUP_FN=_blog_status_backup' impl/install_hugo_blog.sh
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
    ' impl/install_hugo_blog.sh
}

check_blog_status_dispatch() {
  expect_success_output en install_hugo_blog.sh status "Inspect Hugo Blog deployment status"
  expect_success_output zh install_hugo_blog.sh status "检查 Hugo Blog 部署状态"
  expect_success_output en dist/install_hugo_blog.sh status "Inspect Hugo Blog deployment status"
  expect_success_output zh dist/install_hugo_blog.sh status "检查 Hugo Blog 部署状态"
  expect_failure_output en install_hugo_blog.sh "Please run as root" backup
  expect_failure_output zh install_hugo_blog.sh "请使用 root 权限运行" backup
  expect_failure_output en dist/install_hugo_blog.sh "Please run as root" backup
  expect_failure_output zh dist/install_hugo_blog.sh "请使用 root 权限运行" backup
  expect_failure_output en install_hugo_blog.sh "Please run as root" restore
  expect_failure_output zh install_hugo_blog.sh "请使用 root 权限运行" restore
  expect_failure_output en dist/install_hugo_blog.sh "Please run as root" restore
  expect_failure_output zh dist/install_hugo_blog.sh "请使用 root 权限运行" restore
  expect_failure_output en install_hugo_blog.sh "Please run as root" uninstall
  expect_failure_output zh install_hugo_blog.sh "请使用 root 权限运行" uninstall
  expect_failure_output en dist/install_hugo_blog.sh "Please run as root" uninstall
  expect_failure_output zh dist/install_hugo_blog.sh "请使用 root 权限运行" uninstall
  expect_failure_output en install_hugo_blog.sh "Please run as root" update
  expect_failure_output zh install_hugo_blog.sh "请使用 root 权限运行" update
  expect_failure_output en dist/install_hugo_blog.sh "Please run as root" update
  expect_failure_output zh dist/install_hugo_blog.sh "请使用 root 权限运行" update
}

check_blog_install_surfaces_default_nginx_site_removal_failures() {
  awk '
      /app_write_nginx_site_link "\$NGINX_CONF" \/etc\/nginx\/sites-enabled\/blog/ { in_nginx=1; saw_backup=0; saw_raw_rm=0; next }
      in_nginx && /app_nginx_default_site_backup/ { saw_backup=1 }
      in_nginx && /_blog_remove_file \/etc\/nginx\/sites-enabled\/default/ { saw_backup=1 }
      in_nginx && /rm -f \/etc\/nginx\/sites-enabled\/default/ { saw_raw_rm=1 }
      in_nginx && /nginx -t \|\| error "\$\(t app\.blog\.error\.nginx_config\)"/ {
        if (!saw_backup || saw_raw_rm) {
          printf "%s Blog install must move the default Nginx site aside (recoverably) before testing Nginx config\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_nginx=0
      }
    ' impl/install_hugo_blog.sh
}

check_blog_localized_defaults() {
  expect_blog_defaults en "Abyte's Blog" "en-us"
  expect_blog_defaults zh "Abyte 的个人博客" "zh-cn"
}

check_blog_hugo_version_contract() {
  local output
  output="$($BASH_BIN -c '
    set -euo pipefail
    temp_root="$(mktemp -d)"
    trap "rm -rf \"$temp_root\"" EXIT
    export DEPLOY_VERSION_CACHE_ROOT="${temp_root}/version-cache"
    source lib/core.sh
    APP_ID=blog
    APP_NAME="Hugo Blog"
    app_conf_file() { printf "%s" "/nonexistent/blog-deploy.conf"; }
    HUGO_VERSION=1.2.3
    INSTALLED_VERSION=1.0.0
    source impl/install_hugo_blog.sh

    pinned="$(_blog_check_update_json "$INSTALLED_VERSION" 0 1)"
    [[ "$(state_json_field "$pinned" installed)" == 1.0.0 ]]
    [[ "$(state_json_field "$pinned" latest)" == 1.2.3 ]]
    [[ "$(state_json_field "$pinned" update_state)" == update_available ]]
    [[ "$(state_json_field "$pinned" source)" == github_release ]]
    [[ "$(state_json_field "$pinned" cache_state)" == pinned ]]

    HUGO_VERSION=""
    INSTALLED_VERSION=1.2.3
    github_latest_release_tag_checked() { printf "v1.3.0\\n"; }
    latest="$(_blog_check_update_json "$INSTALLED_VERSION" 1 0)"
    [[ "$(state_json_field "$latest" latest)" == v1.3.0 ]]
    [[ "$(state_json_field "$latest" update_state)" == update_available ]]
    [[ "$(state_json_field "$latest" source)" == github_release ]]
    printf ok
  ')"
  [[ "$output" == ok ]]
  grep -Fq 'HUGO_VERSION INSTALLED_VERSION' impl/install_hugo_blog.sh
  grep -Fq 'APP_CHECK_UPDATE_FN=_blog_check_update_json' impl/install_hugo_blog.sh
  grep -Fq 'APP_STATUS_VERSION_FN=_blog_status_version_json' impl/install_hugo_blog.sh
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
    ' impl/install_hugo_blog.sh
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
    ' impl/install_hugo_blog.sh
}

check_blog_dependency_failures_are_reported() {
  if grep -R -nE '^[[:space:]]*apt-get update -qq$|^[[:space:]]*apt-get install -y -qq curl wget git nginx ca-certificates$' \
      impl/install_hugo_blog.sh 2>/dev/null; then
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
    ' impl/install_hugo_blog.sh
}

check_blog_hugo_install_failures_are_actionable() {
  awk '
      /app\.blog\.error\.hugo_install/ { saw_key=1 }
      /app\.blog\.warn\.hugo_cleanup_failed/ { saw_warn_key=1 }
      /app\.blog\.error\.hugo_cleanup/ { saw_cleanup_key=1 }
      /apt-get install -f/ { saw_fix_deps=1 }
      /dpkg -i <downloaded-hugo\.deb>/ { saw_retry=1 }
      END {
        if (!(saw_key && saw_warn_key && saw_cleanup_key && saw_fix_deps && saw_retry)) {
          print "Blog Hugo package install and cleanup failures must explain recovery steps." > "/dev/stderr"
          exit 1
        }
      }
    ' apps/blog.sh
  awk '
      /if ! hugo_deb="\$\(mktemp \/tmp\/hugo\.XXXXXX\.deb\)"; then/ { saw_tmp_if=1 }
      /error "\$\(t app\.blog\.error\.hugo_download\)"/ { saw_tmp_error=1 }
      /if ! wget -q --show-progress -O "\$hugo_deb" "\$deb_url"; then/ { in_download_fail=1; saw_download_cleanup_if=0; saw_download_warn=0; next }
      in_download_fail && /if ! rm -f "\$hugo_deb"; then/ { saw_download_cleanup_if=1 }
      in_download_fail && /warn "\$\(t app\.blog\.warn\.hugo_cleanup_failed "\$hugo_deb"\)"/ { saw_download_warn=1 }
      in_download_fail && /error "\$\(t app\.blog\.error\.hugo_download\)"/ {
        if (!(saw_download_cleanup_if && saw_download_warn)) {
          printf "%s Blog Hugo download failure must warn when temporary package cleanup fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_download_fail=0
      }
      /if \[\[ ! -s "\$hugo_deb" \]\]; then/ { in_empty_fail=1; saw_empty_if=1; saw_empty_cleanup_if=0; saw_empty_cleanup_warn=0; next }
      in_empty_fail && /if ! rm -f "\$hugo_deb"; then/ { saw_empty_cleanup_if=1 }
      in_empty_fail && /warn "\$\(t app\.blog\.warn\.hugo_cleanup_failed "\$hugo_deb"\)"/ { saw_empty_cleanup_warn=1 }
      in_empty_fail && /error "\$\(t app\.blog\.error\.hugo_download\)"/ {
        if (!(saw_empty_cleanup_if && saw_empty_cleanup_warn)) {
          printf "%s Blog Hugo empty download failure must warn when temporary package cleanup fails\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_empty_fail=0
      }
      /if ! dpkg -i "\$hugo_deb"; then/ { in_block=1; saw_error=0; saw_cleanup_if=0; saw_cleanup_warn=0; next }
      in_block && /if ! rm -f "\$hugo_deb"; then/ { saw_cleanup_if=1 }
      in_block && /warn "\$\(t app\.blog\.warn\.hugo_cleanup_failed "\$hugo_deb"\)"/ { saw_cleanup_warn=1 }
      in_block && /error "\$\(t app\.blog\.error\.hugo_install\)"/ {
        saw_error=1
        if (!(saw_error && saw_cleanup_if && saw_cleanup_warn)) {
          printf "%s Blog Hugo package install failure must warn when temporary package cleanup fails and report an actionable error\n", FILENAME > "/dev/stderr"
          exit 1
        }
        expect_success_cleanup=1
        in_block=0
      }
      expect_success_cleanup && /if ! rm -f "\$hugo_deb"; then/ { saw_success_cleanup_if=1; in_success_cleanup=1; expect_success_cleanup=0; next }
      in_success_cleanup && /error "\$\(t app\.blog\.error\.hugo_cleanup "\$hugo_deb"\)"/ { saw_success_cleanup_error=1 }
      /success "\$\(t app\.blog\.hugo_installed "\$\(hugo version \| head -1\)"\)"/ {
        if (!(saw_success_cleanup_if && saw_success_cleanup_error)) {
          printf "%s Blog Hugo install must surface temporary package cleanup failures before reporting success\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_success_cleanup=0
      }
      END {
        if (!(saw_tmp_if && saw_tmp_error && saw_empty_if && saw_empty_cleanup_if && saw_empty_cleanup_warn)) {
          print "Blog Hugo package download must report temporary file creation and cleanup failures for empty downloads." > "/dev/stderr"
          exit 1
        }
      }
    ' impl/install_hugo_blog.sh
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
    ' impl/install_hugo_blog.sh
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
    ' apps/blog.sh impl/install_hugo_blog.sh
}

check_blog_nginx_start_path_is_explicit() {
  if grep -R -n '^systemctl restart nginx$' \
      impl/install_hugo_blog.sh 2>/dev/null; then
    echo "Blog nginx startup must branch explicitly on restart failure." >&2
    return 1
  fi
  awk '
      /step "\$\(t app\.blog\.step_start_nginx\)"/ { in_block=1; saw_restart_if=0; saw_wait=0; next }
      in_block && /if systemctl restart nginx && wait_for_service nginx 10; then/ { saw_restart_if=1; saw_wait=1 }
      in_block && /step "\$\(t app\.blog\.step_health\)"/ {
        if (!(saw_restart_if && saw_wait)) {
          printf "%s Blog nginx startup must use an explicit restart-and-wait branch before the health check\n", FILENAME > "/dev/stderr"
          exit 1
        }
        in_block=0
      }
    ' impl/install_hugo_blog.sh
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
    ' impl/install_hugo_blog.sh
}

check_blog_static_deploy_swaps_tree() {
  if grep -R -n '^[[:space:]]*cp -a "\${PUBLIC_DIR}/\." "\$NGINX_ROOT/"' impl/install_hugo_blog.sh 2>/dev/null; then
    echo "Blog static deployment must not copy directly into the live Nginx root." >&2
    return 1
  fi
  if grep -R -n '^[[:space:]]*\[\[ -e "\$DEPLOY_BAK" || -L "\$DEPLOY_BAK" \]\] && mv "\$DEPLOY_BAK" "\$NGINX_ROOT" || true' \
      impl/install_hugo_blog.sh 2>/dev/null; then
    echo "Blog static deployment rollback must validate restoring the Nginx root." >&2
    return 1
  fi
  if grep -R -nE '\[\[ -e "\\?\$DEPLOY_BAK" \|\| -L "\\?\$DEPLOY_BAK" \]\] && rm -rf "\\?\$DEPLOY_BAK"' \
      impl/install_hugo_blog.sh 2>/dev/null; then
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
    ' impl/install_hugo_blog.sh
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
    ' impl/install_hugo_blog.sh
}

check_blog_site_files_are_atomic() {
  if grep -R -nE '^[[:space:]]*cat > "\$CONFIG_FILE"|^[[:space:]]*cat > "\$\{SITE_DIR\}/|^[[:space:]]*cat > "\$\{CMS_ADMIN_DIR\}/' \
      impl/install_hugo_blog.sh 2>/dev/null; then
    echo "Blog site files must be written through temporary files before replacement." >&2
    return 1
  fi
  if grep -R -n '^[[:space:]]*cp "\$CONFIG_FILE" "\${CONFIG_FILE}.bak.' impl/install_hugo_blog.sh 2>/dev/null; then
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
    ' impl/install_hugo_blog.sh
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
    ' impl/install_hugo_blog.sh
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
    ' impl/install_hugo_blog.sh
}
