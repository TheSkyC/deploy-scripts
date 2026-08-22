#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BASH_BIN="${BASH_BIN:-bash}"

cd "$ROOT_DIR"

# Check definitions are split into per-area modules under tools/checks/;
# each module defines only check_* functions and is sourced before main().
source tools/checks/app-blog.sh
source tools/checks/app-alist.sh
source tools/checks/app-cpa-stack.sh
source tools/checks/app-cyberstrikeai.sh
source tools/checks/app-filebrowser.sh
source tools/checks/app-frps.sh
source tools/checks/app-gitea.sh
source tools/checks/app-gotify.sh
source tools/checks/app-beszel.sh
source tools/checks/app-navidrome.sh
source tools/checks/app-newapi.sh
source tools/checks/app-ntfy.sh
source tools/checks/app-meilisearch.sh
source tools/checks/app-sub2api.sh
source tools/checks/app-tickflow.sh
source tools/checks/app-vaultwarden.sh
source tools/checks/backup.sh
source tools/checks/config-status.sh
source tools/checks/dispatch.sh
source tools/checks/firewall-nginx.sh
source tools/checks/framework.sh
source tools/checks/release.sh
source tools/checks/static.sh
source tools/checks/operation.sh
source tools/checks/state.sh
source tools/checks/self_update.sh
source tools/checks/update.sh
source tools/checks/validators.sh

usage() {
  cat >&2 <<'EOF'
Usage: bash tools/verify.sh [all|syntax|shellcheck|release|dispatch|guards|state|operation|update|self-update|help]

Targets:
  all       Run the full repository verification suite. This is the default.
            Independent checks run concurrently; set PARALLEL_JOBS=1 to run serially.
  syntax    Check Bash syntax for source scripts only.
  shellcheck  Run shellcheck static analysis on source scripts (skips if absent).
  release   Rebuild dist/ with deterministic metadata and check release syntax.
  dispatch  Rebuild dist/ and check CLI dispatch, menus, registry, and localization.
  guards    Rebuild dist/ and run structural/behavioral guardrail checks.
  state     Run state-center and status JSON checks.
  operation Run version and operation-record checks.
  update    Run cached application version-check and check-update checks.
  self-update  Run release package and self-update foundation checks.
EOF
}

build_verified_release() {
  DEPLOY_BUILD_COMMIT=verified SOURCE_DATE_EPOCH=0 "$BASH_BIN" tools/build-release.sh all >/dev/null
}

# Run the given check functions concurrently (up to PARALLEL_JOBS at once) and
# fail if any of them fails. Each check runs in a subshell with its output
# captured to a temp file that is replayed (indented) only on failure, so
# parallel failures stay readable. Checks are read-only after the release
# build, so concurrent subshell execution is safe.
run_checks_parallel() {
  local max_jobs="${PARALLEL_JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 4)}"
  local -a queue=("$@")
  local -a pids=() names=() logs=()
  local i=0 slot status=0 tmp_dir
  if [[ ! "$max_jobs" =~ ^[0-9]+$ ]] || [[ "$max_jobs" -lt 1 ]]; then
    max_jobs=4
  fi
  tmp_dir="$(mktemp -d)"
  # Remove the temp dir on any exit path (including Ctrl-C) so interrupted
  # runs do not leak per-check logs.
  trap 'rm -rf "$tmp_dir"' EXIT
  while [[ "$i" -lt "${#queue[@]}" ]]; do
    pids=()
    names=()
    logs=()
    slot=0
    while [[ "$slot" -lt "$max_jobs" && "$i" -lt "${#queue[@]}" ]]; do
      names+=("${queue[$i]}")
      logs+=("${tmp_dir}/${slot}-${queue[$i]}.log")
      ( "${queue[$i]}" ) >"${logs[$slot]}" 2>&1 &
      pids+=("$!")
      slot=$((slot + 1))
      i=$((i + 1))
    done
    for j in "${!pids[@]}"; do
      if ! wait "${pids[$j]}"; then
        echo "check failed: ${names[$j]}" >&2
        sed 's/^/  /' "${logs[$j]}" >&2 || true
        status=1
      fi
    done
  done
  rm -rf "$tmp_dir"
  trap - EXIT
  return "$status"
}

# Enumerate every defined check_* function and run it concurrently as the all
# target's second phase. check_shell_syntax and check_shellcheck already ran in
# the first phase, so they are excluded here. New check_* functions are picked
# up automatically; they still must be registered in a CI target arm, which
# check_target_groups_cover_all_checks enforces.
run_all_checks() {
  local -a all_checks=()
  local fn
  while IFS= read -r fn; do
    case "$fn" in
      check_shell_syntax|check_shellcheck) continue ;;
    esac
    all_checks+=("$fn")
  done < <(compgen -A function check_ | LC_ALL=C sort)
  run_checks_parallel "${all_checks[@]}" || return 1
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
      check_dist_is_up_to_date
      echo "Release verification passed"
      return 0
      ;;
    dispatch)
      build_verified_release
      check_localized_dispatch
      check_doctor_dispatch
      check_app_help_dispatch
      check_status_json_dispatch
      check_status_json_legacy_contract
      check_status_json_services_and_version
      check_port_conflict_is_warn_only
      check_doctor_validates_saved_config
      check_newapi_uninstall_supports_noninteractive_mode
      check_newapi_uninstall_checks_directory_removal_errors
      check_newapi_uninstall_checks_file_removal_errors
      check_newapi_uninstall_validates_binary_path_before_removal
      check_newapi_install_rollback_validates_binary_path_before_removal
      check_newapi_install_rollback_surfaces_service_file_removal_failures
      check_newapi_backup_lists_preserve_paths_with_spaces
      check_newapi_status_backup_projection
      check_sub2api_status_backup_projection
      check_sub2api_uninstall_supports_noninteractive_mode
      check_sub2api_uninstall_checks_directory_removal_errors
      check_sub2api_uninstall_checks_file_removal_errors
      check_sub2api_uninstall_validates_binary_path_before_removal
      check_sub2api_install_rollback_validates_binary_path_before_removal
      check_sub2api_install_rollback_surfaces_service_file_removal_failures
      check_sub2api_backup_lists_preserve_paths_with_spaces
      check_vaultwarden_status_backup_projection
      check_vaultwarden_uninstall_supports_noninteractive_mode
      check_vaultwarden_uninstall_checks_directory_removal_errors
      check_vaultwarden_uninstall_checks_file_removal_errors
      check_vaultwarden_uninstall_validates_binary_path_before_removal
      check_vaultwarden_install_rollback_validates_binary_path_before_removal
      check_vaultwarden_install_rollback_surfaces_service_file_removal_failures
      check_vaultwarden_install_supports_noninteractive_mode
      check_vaultwarden_install_surfaces_default_nginx_site_removal_failures
      check_vaultwarden_install_summary_is_localized
      check_vaultwarden_backup_lists_preserve_paths_with_spaces
      check_blog_status_backup_projection
      check_blog_uninstall_supports_noninteractive_mode
      check_blog_install_surfaces_default_nginx_site_removal_failures
      check_cyberstrikeai_status_backup_projection
      check_cyberstrikeai_uninstall_supports_noninteractive_mode
      check_cyberstrikeai_uninstall_checks_directory_removal_errors
      check_cyberstrikeai_uninstall_checks_file_removal_errors
      check_tickflow_status_backup_projection
      check_tickflow_uninstall_supports_noninteractive_mode
      check_tickflow_uninstall_checks_directory_removal_errors
      check_tickflow_uninstall_checks_file_removal_errors
      check_cyberstrikeai_backup_lists_preserve_paths_with_spaces
      check_blog_status_dispatch
      check_no_color_output
      check_no_argument_menu
      check_manager_list
      check_manager_menu_shortcuts
      check_app_registry_metadata
      check_blog_localized_defaults
      check_app_localized_descriptions
      echo "Dispatch verification passed"
      return 0
      ;;
    state)
      check_state_json_contract
      check_state_all_registered_apps_enumerated
      check_state_target_selection
      check_state_scalar_parser_and_severity
      check_state_operation_error_code_projection
      check_state_backup_extension_contract
      check_state_binary_backup_adapter
      check_state_status_matrix
      check_state_load_failure_isolation
      check_state_no_network_locality
      check_state_problems_filtering
      check_health_all_target
      echo "State verification passed"
      return 0
      ;;
    operation)
      check_version_helpers
      check_operation_records
      check_operation_logrotate_policy
      check_history_command
      check_app_action_operation_wrapping
      check_operation_failure_traps
      check_operation_signal_interruption
      check_backup_all_dry_run
      check_backup_all_executes_serially_and_records_manager_operation
      check_batch_target_selection_is_local_only
      check_doctor_all_target
      echo "Operation verification passed"
      return 0
      ;;
    update)
      check_update_version_cache_and_network_failures
      check_check_update_target
      check_update_all_dry_run_target
      check_update_all_execution_is_serial_and_safe
      check_update_target_selection_is_local_only
      check_update_all_writes_manager_operation_record
      echo "Update verification passed"
      return 0
      ;;
    self-update)
      check_release_package_artifacts
      check_self_version_and_manifest_checks
      check_self_update_dry_run_validation
      check_self_update_managed_rehearsal
      check_self_update_activation_and_rollback
      check_self_update_rejects_archive_listing_failure
      check_self_update_interruption_restores_activation
      check_self_update_signal_interruption
      echo "Self-update foundation verification passed"
      return 0
      ;;
    guards)
      check_shell_syntax
      build_verified_release
      check_api_ports_are_validated
      check_api_status_directory_sizes_are_nonfatal
      check_app_json_string_escapes_controls
      check_apt_sources_are_atomic
      check_atomic_helpers_are_atomic
      check_backup_retention_cleanup_reports_failures
      check_backup_script_dir_failures_are_explicit
      check_backup_scripts_are_atomic
      check_backup_temp_moves_handle_failure
      check_binary_helpers_are_atomic
      check_binary_replacements_handle_failure
      check_binary_restores_validate_permissions
      check_binary_app_systemd_paths_are_validated
      check_blog_config_persistence
      check_blog_dependency_failures_are_reported
      check_blog_enable_failures_are_reported
      check_blog_hugo_install_failures_are_actionable
      check_blog_install_summary_matches_local_health
      check_blog_nginx_start_path_is_explicit
      check_blog_publish_guidance_uses_staging_output
      check_blog_publish_helper_is_atomic
      check_blog_restore_action
      check_blog_site_files_are_atomic
      check_blog_site_setup_failures_are_explicit
      check_blog_static_deploy_failures_are_actionable
      check_blog_static_deploy_swaps_tree
      check_bundled_impl_cleanup
      check_bundled_impl_dir_security_failure_cleanup
      check_bundled_impl_failure_cleanup
      check_bundled_impl_temp_names_are_random
      check_certbot_diagnostics_use_stderr
      check_config_crlf_handling
      check_config_empty_values_keep_defaults
      check_config_sanitization_behavior
      check_config_key_shape_locale_independent
      check_config_reserved_keys_are_rejected
      check_config_save_failures_are_explicit
      check_config_value_validators
      check_config_write_failure_cleanup
      check_config_writes_are_centralized
      check_connectivity_helper_behavior
      check_cpa_stack_status_backup_projection
      check_cpa_stack_layout
      check_cron_logrotate_are_atomic
      check_logrotate_writes_use_shared_helper
      check_cyberstrikeai_backups_are_atomic
      check_cyberstrikeai_booleans_are_validated
      check_cyberstrikeai_build_temp_cleanup
      check_cyberstrikeai_config_patch_is_atomic
      check_cyberstrikeai_dependency_failures_are_reported
      check_cyberstrikeai_display_sizes_are_nonfatal
      check_cyberstrikeai_enable_failures_are_reported
      check_cyberstrikeai_go_restore_failures_are_reported
      check_cyberstrikeai_go_version_parse_failures_are_explicit
      check_cyberstrikeai_health_checks_are_nonfatal_outside_install
      check_cyberstrikeai_install_summary_matches_health_state
      check_cyberstrikeai_nginx_apply_preserves_reload_diagnostics
      check_cyberstrikeai_nginx_health_probe_matches_server_name
      check_cyberstrikeai_pip_upgrade_failures_are_reported
      check_cyberstrikeai_ports_are_validated
      check_cyberstrikeai_python_env_failures_are_reported
      check_cyberstrikeai_repo_go_install_failures_are_reported
      check_cyberstrikeai_rollback_restore_is_validated
      check_cyberstrikeai_runtime_dir_failures_are_explicit
      check_cyberstrikeai_service_start_paths_are_explicit
      check_cyberstrikeai_source_and_build_prep_failures_are_explicit
      check_cyberstrikeai_uninstall_stop_disable_failures_are_reported
      check_cyberstrikeai_update_rollback_stop_failure_aborts_restore
      check_cyberstrikeai_update_rollbacks_report_restart_failures
      check_download_temp_creation_failures_are_explicit
      check_download_validation_failures_cleanup
      check_fail2ban_configs_are_atomic
      check_firewall_success_paths_validate_command_results
      check_framework_validator_errors_are_actionable
      check_generated_backup_headers_are_shell_quoted
      check_generated_backup_scripts_handle_missing_dirs
      check_github_release_tag_behavior
      check_go_tarball_failures_cleanup
      check_i18n_keys_are_consistent
      check_iptables_rules_are_atomic
      check_keyring_writes_are_atomic
      check_managed_paths_are_validated
      check_manual_backup_retention_is_normalized
      check_mutating_actions_acquire_locks
      check_netfilter_persistent_save_reports_failures
      check_newapi_dependency_failures_are_reported
      check_newapi_enable_failures_are_reported
      check_newapi_health_checks_are_nonfatal_outside_install
      check_newapi_install_cleanup_reports_systemctl_failures
      check_newapi_install_summary_matches_health_state
      check_newapi_manual_backup_wal_result_is_explicit
      check_newapi_runtime_dir_failures_are_explicit
      check_newapi_secret_uses_private_env_file
      check_newapi_service_start_paths_are_explicit
      check_newapi_uninstall_stop_disable_failures_are_reported
      check_newapi_update_rollback_stop_failure_aborts_restore
      check_newapi_update_rollbacks_report_restart_failures
      check_newapi_update_stop_failure_aborts_before_replace
      check_nginx_configs_are_atomic
      check_nginx_domains_are_validated
      check_nginx_main_config_edits_are_atomic
      check_nginx_test_failures_report_diagnostics
      check_no_chinese_comments
      check_no_fixed_tmp_downloads
      check_no_flag_chained_error_handlers
      check_no_hardcoded_chinese_impl
      check_no_unsupported_systemctl_options
      check_old_backup_cleanup_reports_failures
      check_optional_count_messages_are_nonfatal
      check_optional_directory_cleanup_is_nonfatal
      check_port_listening_process_behavior
      check_preupdate_backup_logs_match_guidance
      check_preupdate_backup_warnings_include_followup_guidance
      check_random_head_pipelines_handle_sigpipe
      check_release_build_outputs_are_atomic
      check_root_wrappers_match_bin_loaders
      check_run_checks_parallel_cleans_tmpdir
      check_safe_path_guard
      check_safe_rm_dir_is_idempotent
      check_service_status_label
      check_shared_validators_accept_and_reject
      check_silent_backup_tar_diagnostics_use_stderr
      check_status_commands_allow_non_root
      check_status_port_matches_are_bounded
      check_sub2api_apt_failures_are_reported
      check_sub2api_codename_resolution
      check_sub2api_dependency_services_start_before_success
      check_sub2api_enable_failures_are_reported
      check_sub2api_extract_move_failure_cleanup
      check_sub2api_health_checks_are_nonfatal_outside_install
      check_sub2api_install_cleanup_reports_systemctl_failures
      check_sub2api_install_summary_matches_runtime_state
      check_sub2api_manual_backup_warnings_are_actionable
      check_sub2api_nginx_install_starts_service_explicitly
      check_sub2api_nginx_reload_results_are_checked
      check_sub2api_pg_dump_errors_stay_out_of_backups
      check_sub2api_pg_password_is_escaped
      check_sub2api_uri_encode_ascii
      check_sub2api_postgres_rpm_setup_failures_are_explicit
      check_sub2api_redis_service_handling_is_explicit
      check_sub2api_rpm_dependency_failures_are_reported
      check_sub2api_runtime_dir_failures_are_explicit
      check_sub2api_service_start_paths_are_explicit
      check_sub2api_summary_does_not_print_pg_password
      check_sub2api_uninstall_stop_disable_failures_are_reported
      check_sub2api_update_rollback_stop_failure_aborts_restore
      check_sub2api_update_rollbacks_report_restart_failures
      check_sub2api_update_stop_failure_aborts_before_replace
      check_summary_ip_detection_has_fallback
      check_systemctl_status_diagnostics_are_nonfatal
      check_systemd_daemon_reloads_are_explicit
      check_systemd_helper_is_atomic
      check_systemd_units_are_atomic
      check_tar_diagnostics_use_stderr
      check_tickflow_config_files_are_atomic
      check_tickflow_dependency_failures_are_reported
      check_tickflow_directory_setup_failures_are_explicit
      check_tickflow_env_rewrites_preserve_existing_secrets
      check_tickflow_manual_backup_is_explicit
      check_tickflow_paths_are_guarded
      check_tickflow_preflight_defers_docker_runtime_checks
      check_tickflow_service_start_failures_show_diagnostics
      check_tickflow_status_is_structured
      check_tickflow_systemctl_failures_are_reported
      check_tickflow_systemd_shell_paths_are_quoted
      check_tickflow_uninstall_daemon_reload_failure_is_fatal
      check_tickflow_uninstall_stop_disable_failures_are_reported
      check_uninstall_binary_cleanup_reports_failures
      check_uninstall_nginx_paths_preserve_diagnostics
      check_unsafe_config_loads_fail_closed
      check_update_backs_up_before_stop
      check_update_binary_backups_are_atomic
      check_user_deletion_paths_are_explicit
      check_vaultwarden_admin_token_file_is_private
      check_vaultwarden_apt_update_failures_are_reported
      check_vaultwarden_backup_failures_include_followup_guidance
      check_vaultwarden_binary_installs_are_atomic
      check_vaultwarden_certbot_cron_failures_are_reported
      check_vaultwarden_config_values_are_validated
      check_vaultwarden_enable_failures_are_reported
      check_vaultwarden_env_file_is_atomic
      check_vaultwarden_extract_tool_is_pinned_and_verified
      check_vaultwarden_legacy_extract_tool_config_is_usable
      check_vaultwarden_fail2ban_restart_failures_are_reported
      check_vaultwarden_find_head_pipelines_are_nonfatal
      check_vaultwarden_install_cleanup_reports_systemctl_failures
      check_vaultwarden_install_summary_matches_health_state
      check_vaultwarden_install_webvault_replacement_is_recoverable
      check_vaultwarden_result_chains_are_explicit
      check_vaultwarden_runtime_dir_failures_are_explicit
      check_vaultwarden_runtime_service_starts_are_explicit
      check_vaultwarden_service_start_paths_are_explicit
      check_vaultwarden_status_display_commands_are_nonfatal
      check_vaultwarden_status_health_guidance_matches_local_probe
      check_vaultwarden_uninstall_stop_disable_failures_are_reported
      check_vaultwarden_update_stop_failure_aborts_before_replace
      check_vaultwarden_version_probe_has_fallback
      check_vaultwarden_webvault_archives_are_validated
      check_vaultwarden_webvault_replacements_are_atomic
      check_vaultwarden_webvault_restore_cleans_partial
      check_vaultwarden_webvault_update_warnings_are_actionable
      check_vaultwarden_workdir_cleanup_traps_are_nonfatal
      check_filebrowser_uses_shared_binary_lifecycle
      check_filebrowser_release_asset_mapping
      check_filebrowser_root_directory_is_prepared
      check_alist_uses_shared_binary_lifecycle
      check_alist_release_asset_mapping
      check_meilisearch_uses_shared_binary_lifecycle
      check_meilisearch_release_asset_mapping
      check_meilisearch_config_is_managed_atomically
      check_ntfy_uses_shared_binary_lifecycle
      check_ntfy_release_asset_mapping
      check_ntfy_config_is_managed_atomically
      check_gotify_uses_shared_binary_lifecycle
      check_gotify_release_asset_mapping
      check_gotify_env_is_managed_atomically
      check_beszel_uses_shared_binary_lifecycle
      check_beszel_release_asset_mapping
      check_beszel_env_is_managed_atomically
      check_gitea_uses_shared_binary_lifecycle
      check_gitea_release_asset_mapping
      check_gitea_config_is_managed_atomically
      check_frps_uses_shared_binary_lifecycle
      check_frps_release_asset_mapping
      check_frps_config_is_managed_atomically
      check_navidrome_uses_shared_binary_lifecycle
      check_navidrome_release_asset_mapping
      check_navidrome_music_folder_is_prepared
      check_state_json_contract
      check_state_all_registered_apps_enumerated
      check_state_target_selection
      check_state_scalar_parser_and_severity
      check_state_operation_error_code_projection
      check_state_backup_extension_contract
      check_state_binary_backup_adapter
      check_state_status_matrix
      check_state_load_failure_isolation
      check_state_no_network_locality
      check_state_problems_filtering
      check_health_all_target
      check_version_helpers
      check_operation_records
      check_operation_logrotate_policy
      check_history_command
      check_app_action_operation_wrapping
      check_operation_failure_traps
      check_operation_signal_interruption
      check_backup_all_dry_run
      check_backup_all_executes_serially_and_records_manager_operation
      check_batch_target_selection_is_local_only
      check_doctor_all_target
      check_update_version_cache_and_network_failures
      check_check_update_target
      check_update_all_dry_run_target
      check_update_all_execution_is_serial_and_safe
      check_update_target_selection_is_local_only
      check_update_all_writes_manager_operation_record
      check_release_package_artifacts
      check_self_version_and_manifest_checks
      check_self_update_dry_run_validation
      check_self_update_managed_rehearsal
      check_self_update_activation_and_rollback
      check_self_update_rejects_archive_listing_failure
      check_self_update_interruption_restores_activation
      check_self_update_signal_interruption
      check_target_groups_cover_all_checks
      echo "Guards verification passed"
      return 0
      ;;

    all) ;;
    shellcheck)
      check_shell_syntax
      check_shellcheck
      echo "Shellcheck verification passed"
      return 0
      ;;
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

  run_checks_parallel \
    check_shell_syntax \
    check_shellcheck \
    || return 1
  build_verified_release
  run_all_checks || return 1
  echo "Verification passed"
}

main "$@"


