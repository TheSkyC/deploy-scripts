#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BASH_BIN="${BASH_BIN:-bash}"

cd "$ROOT_DIR"

# Localization-independent harness: most check modules assert English output
# from bash -c snippets that do not set DEPLOY_LANG themselves. Default the
# harness language to English so a Chinese desktop locale (LANGUAGE=zh_CN)
# cannot make those assertions fail, while checks that exercise translations
# keep passing DEPLOY_LANG explicitly (an assignment overrides this export).
export DEPLOY_LANG="${DEPLOY_LANG:-en}"

# Check modules and the self-update smoke check validate JSON payloads with a
# Python interpreter. Linux distributions commonly ship only python3, while
# the suite historically calls the unversioned `python` command, so resolve
# the interpreter once here and expose it as `python` on PATH when needed.
PYTHON_SHIM_DIR=""
python_shim_cleanup() {
  [[ -n "$PYTHON_SHIM_DIR" ]] && rm -rf -- "$PYTHON_SHIM_DIR"
  return 0
}
if ! command -v python >/dev/null 2>&1; then
  resolved_python="$(command -v python3 || true)"
  if [[ -z "$resolved_python" ]]; then
    echo "verify: python3 or python is required to run the verification suite" >&2
    exit 1
  fi
  PYTHON_SHIM_DIR="$(mktemp -d "${TMPDIR:-/tmp}/deploy-scripts-verify-python.XXXXXX")"
  ln -s "$resolved_python" "$PYTHON_SHIM_DIR/python"
  export PATH="${PYTHON_SHIM_DIR}:${PATH}"
  trap 'python_shim_cleanup' EXIT
fi

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
source tools/checks/security.sh

usage() {
  cat >&2 <<'EOF'
Usage: bash tools/verify.sh [all|syntax|shellcheck|release|dispatch|guards|state|operation|update|self-update|prove|help]

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
  prove     Run behavioral feature proofs (backup integrity/restore, notify,
            schedule, migrate, compose, fleet) with stub backends.
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
  # runs do not leak per-check logs. Chain the caller's EXIT trap (for
  # example the Python PATH shim cleanup) instead of replacing it.
  local previous_exit_trap
  previous_exit_trap="$(trap -p EXIT)"
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
  if [[ -n "$previous_exit_trap" ]]; then
    eval "$previous_exit_trap"
  else
    trap - EXIT
  fi
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




run_isolated_check() {
  local check_name="$1"
  shift
  if ( "$check_name" "$@" ); then
    return 0
  fi
  echo "guards verification failed in $check_name" >&2
  return 1
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
      check_dist_is_up_to_date
      check_localized_dispatch
      check_doctor_dispatch
      check_security_audit_contract
      check_app_help_dispatch
      check_status_json_dispatch
      check_status_json_legacy_contract
      check_status_json_services_and_version
      check_status_framework_version_is_reported
      check_port_conflict_is_warn_only
      check_port_conflict_strict_mode_aborts
      check_doctor_validates_saved_config
      check_doctor_config_diff_ignores_saved_quotes
      check_help_masks_sensitive_config_values
      check_newapi_status_backup_projection
      check_newapi_asset_names_keep_version_prefix
      check_newapi_summary_does_not_invent_public_url
      check_newapi_summary_warns_about_default_credentials
      check_sub2api_status_backup_projection
      check_sub2api_uninstall_supports_noninteractive_mode
      check_uninstall_cancellations_return_nonzero
      check_sub2api_uninstall_checks_directory_removal_errors
      check_sub2api_uninstall_checks_file_removal_errors
      check_sub2api_uninstall_validates_binary_path_before_removal
      check_sub2api_install_rollback_validates_binary_path_before_removal
      check_sub2api_install_rollback_surfaces_service_file_removal_failures
      check_sub2api_backup_lists_preserve_paths_with_spaces
      check_sub2api_restore_sets_data_owner
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
      check_vaultwarden_systemd_displays_no_new_privileges
      check_vaultwarden_backup_lists_preserve_paths_with_spaces
      check_blog_status_backup_projection
      check_blog_uninstall_supports_noninteractive_mode
      check_blog_install_surfaces_default_nginx_site_removal_failures
      check_cyberstrikeai_status_backup_projection
      check_cyberstrikeai_uninstall_supports_noninteractive_mode
      check_cyberstrikeai_uninstall_checks_directory_removal_errors
      check_cyberstrikeai_uninstall_checks_file_removal_errors
      check_tickflow_status_backup_projection
      check_tickflow_restore_keeps_aside_for_rollback
      check_tickflow_systemd_unit_is_sandboxed
      check_tickflow_uninstall_supports_noninteractive_mode
      check_tickflow_uninstall_checks_directory_removal_errors
      check_tickflow_uninstall_checks_file_removal_errors
      check_cyberstrikeai_backup_lists_preserve_paths_with_spaces
      check_blog_status_dispatch
      check_no_color_output
      check_no_argument_menu
      check_menu_surfaces_supported_advanced_actions
      check_doctor_strict_returns_on_warnings
      check_manager_list
      check_manager_menu_shortcuts
      check_no_tty_menu_usage
      check_app_registry_metadata
      check_app_registry_capabilities
      check_blog_localized_defaults
      check_app_localized_descriptions
      check_framework_i18n_keys_are_consistent
      check_framework_i18n_format_pairs_are_consistent
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
      check_state_backup_config_trust_gate
      check_state_status_matrix
      check_state_timeout_kills_process_group
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
      check_operation_json_escape_matches_app_json_string
      check_operation_logrotate_policy
      check_operation_logrotate_uses_shared_atomic_writer
      check_history_command
      check_operation_scopes_are_distinct
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
      check_binary_app_pinned_target_adapters
      check_update_version_cache_and_network_failures
      check_check_update_target
      check_update_all_dry_run_target
      check_update_all_execution_is_serial_and_safe
      check_update_target_selection_is_local_only
      check_update_all_writes_manager_operation_record
      check_update_adapter_hook_dispatch
      check_update_adapter_fallback_stays_unsupported
      check_update_git_branch_checker
      check_update_cpa_stack_merge_verdicts
      check_cpa_stack_component_version_manifest
      check_cpa_stack_pinned_versions_contract
      check_sub2api_component_version_manifest
      check_sub2api_pinned_version_contract
      echo "Update verification passed"
      return 0
      ;;
    self-update)
      check_release_package_artifacts
      check_self_version_and_manifest_checks
      check_self_update_manifest_validation_preserves_lock_flag
      check_self_update_keep_releases_accepts_all_nonzero_counts
      check_self_update_has_no_signature_dead_keys
      check_self_update_protects_checkout_and_standalone
      check_self_update_dry_run_validation
      check_self_update_managed_rehearsal
      check_self_update_activation_and_rollback
      check_self_update_rejects_archive_listing_failure
      check_self_update_interruption_restores_activation
      check_self_update_signal_interruption
      echo "Self-update foundation verification passed"
      return 0
      ;;
    prove)
      check_shell_syntax
      "$BASH_BIN" tools/prove-features.sh
      echo "Feature proofs verification passed"
      return 0
      ;;
    guards)
      GUARDS_CURRENT_CHECK=""
      trap 'case "${BASH_COMMAND%% *}" in check_*) GUARDS_CURRENT_CHECK="${BASH_COMMAND%% *}" ;; esac' DEBUG
      trap 'status=$?; if (( status != 0 )); then printf "guards verification failed in %s\n" "${GUARDS_CURRENT_CHECK:-unknown}" >&2; fi' EXIT
      run_isolated_check check_shell_syntax
      build_verified_release
      run_isolated_check check_dist_is_up_to_date
      run_isolated_check check_api_ports_are_validated
      run_isolated_check check_api_status_directory_sizes_are_nonfatal
      run_isolated_check check_app_json_string_escapes_controls
      run_isolated_check check_app_http_status_code_helper
      run_isolated_check check_app_http_probe_warns_missing_curl
      run_isolated_check check_app_install_executable_file_helper
      run_isolated_check check_app_prune_update_backups_behavior
      run_isolated_check check_atomic_copy_file_strict_helper
      run_isolated_check check_atomic_write_command_file_helper
      run_isolated_check check_custom_app_http_health_probes_use_shared_helper
      run_isolated_check check_binary_app_download_integrity
      run_isolated_check check_binary_app_archive_members_are_validated
      run_isolated_check check_acquire_lock_preserves_file_and_waits
      run_isolated_check check_logging_colors_are_tty_gated
      run_isolated_check check_schedule_cron_expression_validator
      run_isolated_check check_custom_executable_installs_use_shared_helper
      run_isolated_check check_update_rollback_cleanup_uses_shared_helper
      run_isolated_check check_apt_sources_are_atomic
      run_isolated_check check_atomic_helpers_are_atomic
      run_isolated_check check_backup_retention_cleanup_reports_failures
      run_isolated_check check_backup_script_dir_failures_are_explicit
      run_isolated_check check_backup_scripts_are_atomic
      run_isolated_check check_backup_temp_moves_handle_failure
      run_isolated_check check_backup_create_tar_archive_helper
      run_isolated_check check_backup_create_tar_archive_delegates
      run_isolated_check check_backup_create_gzip_archive_helper
      run_isolated_check check_backup_create_gzip_archive_delegates
      run_isolated_check check_backup_remove_archive_with_metadata_helper
      run_isolated_check check_backup_list_expired_archives_helper
      run_isolated_check check_binary_helpers_are_atomic
      run_isolated_check check_binary_replacements_handle_failure
      run_isolated_check check_binary_restores_validate_permissions
      run_isolated_check check_binary_app_systemd_paths_are_validated
      run_isolated_check check_binary_app_local_targets_follow_bind_addr
      run_isolated_check check_apt_installs_are_minimal
      run_isolated_check check_binary_app_install_rollback_cleans_system_state
      run_isolated_check check_binary_app_install_temporary_cleanup_helper
      run_isolated_check check_binary_app_pre_backup_hook_is_best_effort
      run_isolated_check check_binary_app_health_results_are_surfaced
      run_isolated_check check_binary_app_summary_management_hints
      run_isolated_check check_binary_app_unpinned_version_notice
      run_isolated_check check_blog_config_persistence
      run_isolated_check check_blog_hugo_version_contract
      run_isolated_check check_blog_dependency_failures_are_reported
      run_isolated_check check_blog_enable_failures_are_reported
      run_isolated_check check_blog_hugo_install_failures_are_actionable
      run_isolated_check check_blog_install_summary_matches_local_health
      run_isolated_check check_blog_nginx_start_path_is_explicit
      run_isolated_check check_blog_publish_guidance_uses_staging_output
      run_isolated_check check_blog_publish_helper_is_atomic
      run_isolated_check check_blog_restore_action
      run_isolated_check check_blog_site_files_are_atomic
      run_isolated_check check_blog_site_setup_failures_are_explicit
      run_isolated_check check_blog_static_deploy_failures_are_actionable
      run_isolated_check check_blog_static_deploy_swaps_tree
      run_isolated_check check_bundled_impl_cleanup
      run_isolated_check check_bundled_impl_dir_security_failure_cleanup
      run_isolated_check check_bundled_impl_empty_payload_fails_closed
      run_isolated_check check_bundled_impl_failure_cleanup
      run_isolated_check check_bundled_impl_temp_names_are_random
      run_isolated_check check_certbot_diagnostics_use_stderr
      run_isolated_check check_config_crlf_handling
      run_isolated_check check_config_empty_values_keep_defaults
      run_isolated_check check_config_sanitization_behavior
      run_isolated_check check_config_key_shape_locale_independent
      run_isolated_check check_config_reserved_keys_are_rejected
      run_isolated_check check_config_save_failures_are_explicit
      run_isolated_check check_config_value_validators
      run_isolated_check check_config_write_failure_cleanup
      run_isolated_check check_config_writes_are_centralized
      run_isolated_check check_config_export_uses_atomic_copy
      run_isolated_check check_connectivity_helper_behavior
      run_isolated_check check_cpa_stack_status_backup_projection
      run_isolated_check check_cpa_stack_status_reports_component_versions
      run_isolated_check check_cpa_stack_layout
      run_isolated_check check_cpa_stack_binary_backups_are_atomic
      run_isolated_check check_cpa_stack_pinned_versions_contract
      run_isolated_check check_cpa_stack_e2e_pinned_fixture
      run_isolated_check check_cpa_stack_cpamp_asset_resolution
      run_isolated_check check_cron_logrotate_are_atomic
      run_isolated_check check_binary_app_certbot_cron_is_published_atomically
      run_isolated_check check_binary_app_tls_failures_roll_back_artifacts
      run_isolated_check check_logrotate_writes_use_shared_helper
      run_isolated_check check_cyberstrikeai_backups_are_atomic
      run_isolated_check check_cyberstrikeai_backup_script_is_published_atomically
      run_isolated_check check_cyberstrikeai_backup_script_publish_contract
      run_isolated_check check_cyberstrikeai_booleans_are_validated
      run_isolated_check check_cyberstrikeai_mirrors_are_opt_in
      run_isolated_check check_cyberstrikeai_build_temp_cleanup
      run_isolated_check check_cyberstrikeai_config_patch_is_atomic
      run_isolated_check check_cyberstrikeai_dependency_failures_are_reported
      run_isolated_check check_cyberstrikeai_git_commit_version_contract
      run_isolated_check check_cyberstrikeai_display_sizes_are_nonfatal
      run_isolated_check check_cyberstrikeai_enable_failures_are_reported
      run_isolated_check check_cyberstrikeai_go_restore_failures_are_reported
      run_isolated_check check_cyberstrikeai_go_version_parse_failures_are_explicit
      run_isolated_check check_cyberstrikeai_health_checks_are_nonfatal_outside_install
      run_isolated_check check_cyberstrikeai_install_summary_matches_health_state
      run_isolated_check check_cyberstrikeai_nginx_apply_preserves_reload_diagnostics
      run_isolated_check check_cyberstrikeai_nginx_health_probe_matches_server_name
      run_isolated_check check_cyberstrikeai_pip_upgrade_failures_are_reported
      run_isolated_check check_cyberstrikeai_ports_are_validated
      run_isolated_check check_cyberstrikeai_python_env_failures_are_reported
      run_isolated_check check_cyberstrikeai_repo_go_install_failures_are_reported
      run_isolated_check check_cyberstrikeai_rollback_restore_is_validated
      run_isolated_check check_cyberstrikeai_runtime_dir_failures_are_explicit
      run_isolated_check check_cyberstrikeai_service_start_paths_are_explicit
      run_isolated_check check_cyberstrikeai_source_and_build_prep_failures_are_explicit
      run_isolated_check check_cyberstrikeai_uninstall_stop_disable_failures_are_reported
      run_isolated_check check_cyberstrikeai_update_rollback_stop_failure_aborts_restore
      run_isolated_check check_cyberstrikeai_update_rollbacks_report_restart_failures
      run_isolated_check check_download_temp_creation_failures_are_explicit
      run_isolated_check check_download_validation_failures_cleanup
      run_isolated_check check_fail2ban_configs_are_atomic
      run_isolated_check check_firewall_success_paths_validate_command_results
      run_isolated_check check_ufw_comment_has_fallback
      run_isolated_check check_framework_validator_errors_are_actionable
      run_isolated_check check_generated_backup_headers_are_shell_quoted
      run_isolated_check check_generated_backup_scripts_handle_missing_dirs
      run_isolated_check check_github_release_tag_behavior
      run_isolated_check check_go_tarball_failures_cleanup
      run_isolated_check check_i18n_keys_are_consistent
      run_isolated_check check_iptables_rules_are_atomic
      run_isolated_check check_keyring_writes_are_atomic
      run_isolated_check check_managed_paths_are_validated
      run_isolated_check check_manual_backup_retention_is_normalized
      run_isolated_check check_mutating_actions_acquire_locks
      run_isolated_check check_no_explicit_release_lock_calls
      run_isolated_check check_netfilter_persistent_save_reports_failures
      run_isolated_check check_newapi_secret_uses_private_env_file
      run_isolated_check check_newapi_backup_wal_hook_is_best_effort
      run_isolated_check check_newapi_backup_script_is_published_atomically
      run_isolated_check check_nginx_configs_are_atomic
      run_isolated_check check_nginx_domains_are_validated
      run_isolated_check check_nginx_main_config_edits_are_atomic
      run_isolated_check check_nginx_test_failures_report_diagnostics
      run_isolated_check check_no_chinese_comments
      run_isolated_check check_no_fixed_tmp_downloads
      run_isolated_check check_no_flag_chained_error_handlers
      run_isolated_check check_no_hardcoded_chinese_impl
      run_isolated_check check_no_unsupported_systemctl_options
      run_isolated_check check_old_backup_cleanup_reports_failures
      run_isolated_check check_optional_count_messages_are_nonfatal
      run_isolated_check check_optional_directory_cleanup_is_nonfatal
      run_isolated_check check_port_listening_process_behavior
      run_isolated_check check_port_conflict_strict_mode_aborts
      run_isolated_check check_port_conflict_is_warn_only
      run_isolated_check check_preupdate_backup_logs_match_guidance
      run_isolated_check check_preupdate_backup_warnings_include_followup_guidance
      run_isolated_check check_random_head_pipelines_handle_sigpipe
      run_isolated_check check_release_build_outputs_are_atomic
      run_isolated_check check_versioned_pre_commit_checks_release_artifacts
      run_isolated_check check_app_loader_dispatch_matches_cli
      run_isolated_check check_root_wrappers_match_bin_loaders
      run_isolated_check check_run_checks_parallel_cleans_tmpdir
      run_isolated_check check_safe_path_guard
      run_isolated_check check_safe_rm_dir_is_idempotent
      run_isolated_check check_service_status_label
      run_isolated_check check_wait_for_service_confirms_stable_start
      run_isolated_check check_shared_validators_accept_and_reject
      run_isolated_check check_silent_backup_tar_diagnostics_use_stderr
      run_isolated_check check_status_commands_allow_non_root
      run_isolated_check check_status_port_matches_are_bounded
      run_isolated_check check_sub2api_apt_failures_are_reported
      run_isolated_check check_sub2api_backup_script_is_published_atomically
      run_isolated_check check_sub2api_backup_script_publish_contract
      run_isolated_check check_sub2api_codename_resolution
      run_isolated_check check_sub2api_dependency_services_start_before_success
      run_isolated_check check_sub2api_database_restore_fails_closed
      run_isolated_check check_sub2api_database_restore_failure_is_nonzero
      run_isolated_check check_sub2api_e2e_uses_real_dependency_fixture
      run_isolated_check check_sub2api_enable_failures_are_reported
      run_isolated_check check_sub2api_extract_move_failure_cleanup
      run_isolated_check check_sub2api_health_checks_are_nonfatal_outside_install
      run_isolated_check check_sub2api_install_cleanup_reports_systemctl_failures
      run_isolated_check check_sub2api_install_summary_matches_runtime_state
      run_isolated_check check_sub2api_manual_backup_warnings_are_actionable
      run_isolated_check check_sub2api_nginx_install_starts_service_explicitly
      run_isolated_check check_sub2api_nginx_reload_results_are_checked
      run_isolated_check check_sub2api_pg_dump_errors_stay_out_of_backups
      run_isolated_check check_sub2api_pg_password_is_escaped
      run_isolated_check check_sub2api_pinned_version_contract
      run_isolated_check check_sub2api_uri_encode_ascii
      run_isolated_check check_sub2api_postgres_rpm_setup_failures_are_explicit
      run_isolated_check check_sub2api_redis_service_handling_is_explicit
      run_isolated_check check_sub2api_rpm_dependency_failures_are_reported
      run_isolated_check check_sub2api_runtime_dir_failures_are_explicit
      run_isolated_check check_sub2api_service_start_paths_are_explicit
      run_isolated_check check_sub2api_summary_does_not_print_pg_password
      run_isolated_check check_sub2api_uninstall_stop_disable_failures_are_reported
      run_isolated_check check_sub2api_update_rollback_stop_failure_aborts_restore
      run_isolated_check check_sub2api_update_rollbacks_report_restart_failures
      run_isolated_check check_sub2api_update_stop_failure_aborts_before_replace
      run_isolated_check check_summary_ip_detection_has_fallback
      run_isolated_check check_systemctl_status_diagnostics_are_nonfatal
      run_isolated_check check_systemd_daemon_reloads_are_explicit
      run_isolated_check check_systemd_helper_is_atomic
      run_isolated_check check_systemd_units_are_atomic
      run_isolated_check check_tar_diagnostics_use_stderr
      run_isolated_check check_tickflow_config_files_are_atomic
      run_isolated_check check_tickflow_dependency_failures_are_reported
      run_isolated_check check_tickflow_directory_setup_failures_are_explicit
      run_isolated_check check_tickflow_env_rewrites_preserve_existing_secrets
      run_isolated_check check_tickflow_git_commit_version_contract
      run_isolated_check check_tickflow_manual_backup_is_explicit
      run_isolated_check check_tickflow_paths_are_guarded
      run_isolated_check check_tickflow_preflight_defers_docker_runtime_checks
      run_isolated_check check_tickflow_service_start_failures_show_diagnostics
      run_isolated_check check_tickflow_status_is_structured
      run_isolated_check check_tickflow_systemctl_failures_are_reported
      run_isolated_check check_tickflow_systemd_shell_paths_are_quoted
      run_isolated_check check_tickflow_uninstall_daemon_reload_failure_is_fatal
      run_isolated_check check_tickflow_uninstall_stop_disable_failures_are_reported
      run_isolated_check check_uninstall_binary_cleanup_reports_failures
      run_isolated_check check_uninstall_nginx_paths_preserve_diagnostics
      run_isolated_check check_unsafe_config_loads_fail_closed
      run_isolated_check check_update_backs_up_before_stop
      run_isolated_check check_update_binary_backups_are_atomic
      run_isolated_check check_user_deletion_paths_are_explicit
      run_isolated_check check_vaultwarden_admin_token_file_is_private
      run_isolated_check check_vaultwarden_apt_update_failures_are_reported
      run_isolated_check check_vaultwarden_backup_failures_include_followup_guidance
      run_isolated_check check_vaultwarden_backup_script_is_published_atomically
      run_isolated_check check_vaultwarden_backup_script_publish_contract
      run_isolated_check check_vaultwarden_binary_backups_use_shared_atomic_copy
      run_isolated_check check_vaultwarden_binary_installs_are_atomic
      run_isolated_check check_vaultwarden_certbot_cron_failures_are_reported
      run_isolated_check check_vaultwarden_config_values_are_validated
      run_isolated_check check_vaultwarden_enable_failures_are_reported
      run_isolated_check check_vaultwarden_env_file_is_atomic
      run_isolated_check check_vaultwarden_extract_tool_is_pinned_and_verified
      run_isolated_check check_vaultwarden_image_digest_version_contract
      run_isolated_check check_vaultwarden_legacy_extract_tool_config_is_usable
      run_isolated_check check_vaultwarden_fail2ban_restart_failures_are_reported
      run_isolated_check check_vaultwarden_fail2ban_configs_use_shared_atomic_write
      run_isolated_check check_vaultwarden_find_head_pipelines_are_nonfatal
      run_isolated_check check_vaultwarden_install_cleanup_reports_systemctl_failures
      run_isolated_check check_vaultwarden_install_summary_matches_health_state
      run_isolated_check check_vaultwarden_install_webvault_replacement_is_recoverable
      run_isolated_check check_vaultwarden_result_chains_are_explicit
      run_isolated_check check_vaultwarden_runtime_dir_failures_are_explicit
      run_isolated_check check_vaultwarden_runtime_service_starts_are_explicit
      run_isolated_check check_vaultwarden_service_start_paths_are_explicit
      run_isolated_check check_vaultwarden_status_display_commands_are_nonfatal
      run_isolated_check check_vaultwarden_status_health_guidance_matches_local_probe
      run_isolated_check check_vaultwarden_uninstall_stop_disable_failures_are_reported
      run_isolated_check check_vaultwarden_update_stop_failure_aborts_before_replace
      run_isolated_check check_vaultwarden_version_probe_has_fallback
      run_isolated_check check_vaultwarden_webvault_archives_are_validated
      run_isolated_check check_vaultwarden_webvault_replacements_are_atomic
      run_isolated_check check_vaultwarden_webvault_restore_cleans_partial
      run_isolated_check check_vaultwarden_webvault_update_warnings_are_actionable
      run_isolated_check check_vaultwarden_workdir_cleanup_traps_are_nonfatal
      run_isolated_check check_filebrowser_uses_shared_binary_lifecycle
      run_isolated_check check_filebrowser_release_asset_mapping
      run_isolated_check check_filebrowser_root_directory_is_prepared
      run_isolated_check check_alist_uses_shared_binary_lifecycle
      run_isolated_check check_alist_release_asset_mapping
      run_isolated_check check_alist_config_rewrites_use_shared_atomic_write
      run_isolated_check check_meilisearch_uses_shared_binary_lifecycle
      run_isolated_check check_meilisearch_release_asset_mapping
      run_isolated_check check_meilisearch_config_is_managed_atomically
      run_isolated_check check_ntfy_uses_shared_binary_lifecycle
      run_isolated_check check_ntfy_release_asset_mapping
      run_isolated_check check_ntfy_config_is_managed_atomically
      run_isolated_check check_gotify_uses_shared_binary_lifecycle
      run_isolated_check check_gotify_release_asset_mapping
      run_isolated_check check_gotify_env_is_managed_atomically
      run_isolated_check check_beszel_uses_shared_binary_lifecycle
      run_isolated_check check_beszel_release_asset_mapping
      run_isolated_check check_beszel_env_is_managed_atomically
      run_isolated_check check_gitea_uses_shared_binary_lifecycle
      run_isolated_check check_gitea_release_asset_mapping
      run_isolated_check check_gitea_config_is_managed_atomically
      run_isolated_check check_frps_uses_shared_binary_lifecycle
      run_isolated_check check_frps_release_asset_mapping
      run_isolated_check check_frps_config_is_managed_atomically
      run_isolated_check check_navidrome_uses_shared_binary_lifecycle
      run_isolated_check check_navidrome_release_asset_mapping
      run_isolated_check check_navidrome_music_folder_is_prepared
      run_isolated_check check_state_json_contract
      run_isolated_check check_state_all_registered_apps_enumerated
      run_isolated_check check_state_target_selection
      run_isolated_check check_state_scalar_parser_and_severity
      run_isolated_check check_state_operation_error_code_projection
      run_isolated_check check_state_backup_extension_contract
      run_isolated_check check_state_binary_backup_adapter
      run_isolated_check check_state_backup_config_trust_gate
      run_isolated_check check_state_status_matrix
      run_isolated_check check_state_timeout_kills_process_group
      run_isolated_check check_state_load_failure_isolation
      run_isolated_check check_state_no_network_locality
      run_isolated_check check_state_problems_filtering
      run_isolated_check check_health_all_target
      run_isolated_check check_version_helpers
      run_isolated_check check_operation_records
      run_isolated_check check_operation_json_escape_matches_app_json_string
      run_isolated_check check_operation_logrotate_policy
      run_isolated_check check_operation_logrotate_uses_shared_atomic_writer
      run_isolated_check check_history_command
      run_isolated_check check_operation_scopes_are_distinct
      run_isolated_check check_app_action_operation_wrapping
      run_isolated_check check_operation_failure_traps
      run_isolated_check check_operation_signal_interruption
      run_isolated_check check_backup_all_dry_run
      run_isolated_check check_backup_all_executes_serially_and_records_manager_operation
      run_isolated_check check_backup_finalize_archive_helper
      run_isolated_check check_backup_integrity_primitives
      run_isolated_check check_sub2api_manual_backups_finalize_integrity
      run_isolated_check check_sub2api_preupdate_backup_finalizes_metadata
      run_isolated_check check_vaultwarden_preupdate_backup_finalizes_metadata
      run_isolated_check check_vaultwarden_restore_preserves_env_file
      run_isolated_check check_binary_impls_have_verify_delegate
      run_isolated_check check_custom_impls_have_verify_delegate
      run_isolated_check check_shared_impls_have_restore_delegate
      run_isolated_check check_blog_backup_writes_integrity_metadata
      run_isolated_check check_binary_app_backup_writes_integrity_metadata
      run_isolated_check check_runtime_backup_finalizes_integrity_metadata
      run_isolated_check check_generated_backup_scripts_write_sidecars
      run_isolated_check check_generated_backup_scripts_write_manifests
      run_isolated_check check_generated_backup_retention_removes_metadata
      run_isolated_check check_generated_backup_scripts_manifest_contract
      run_isolated_check check_backup_archives_are_private
      run_isolated_check check_registry_restore_capability_matches_impl
      run_isolated_check check_backup_validate_gzip_archive
      run_isolated_check check_backup_restore_directory_lifecycle
      run_isolated_check check_backup_restore_data_dir_lifecycle
      run_isolated_check check_backup_restore_aside_uses_random_suffix
      run_isolated_check check_binary_app_uninstall_removes_stage_directories
      run_isolated_check check_backup_manifest_field_skips_escaped_quotes
      run_isolated_check check_notification_fail_open_and_redaction
      run_isolated_check check_notify_credentials_stay_out_of_argv
      run_isolated_check check_schedule_units_are_atomic_and_cleaned_up
      run_isolated_check check_schedule_retries_are_configurable
      run_isolated_check check_per_app_event_notifications
      run_isolated_check check_compose_shared_layer_and_tickflow_delegation
      run_isolated_check check_compose_lifecycle_and_health
      run_isolated_check check_compose_health_supports_legacy_v1_tables
      run_isolated_check check_fleet_host_validation_and_isolation
      run_isolated_check check_migration_export_import_roundtrip
      run_isolated_check check_migrate_backups_inventory_materializes_impls
      run_isolated_check check_batch_target_selection_is_local_only
      run_isolated_check check_doctor_all_target
      run_isolated_check check_binary_app_pinned_target_adapters
      run_isolated_check check_update_version_cache_and_network_failures
      run_isolated_check check_check_update_target
      run_isolated_check check_update_all_dry_run_target
      run_isolated_check check_update_all_execution_is_serial_and_safe
      run_isolated_check check_update_target_selection_is_local_only
      run_isolated_check check_update_all_writes_manager_operation_record
      run_isolated_check check_release_package_artifacts
      run_isolated_check check_self_version_and_manifest_checks
      run_isolated_check check_self_update_manifest_validation_preserves_lock_flag
      run_isolated_check check_self_update_keep_releases_accepts_all_nonzero_counts
      run_isolated_check check_self_update_protects_checkout_and_standalone
      run_isolated_check check_self_update_dry_run_validation
      run_isolated_check check_self_update_managed_rehearsal
      run_isolated_check check_self_update_activation_and_rollback
      run_isolated_check check_self_update_rejects_archive_listing_failure
      run_isolated_check check_self_update_interruption_restores_activation
      run_isolated_check check_self_update_signal_interruption
      run_isolated_check check_security_defaults_and_public_bind_guard
      run_isolated_check check_security_audit_contract
      run_isolated_check check_target_groups_cover_all_checks
      echo "Guards verification passed"
      return 0
      ;;

    all) ;;
    shellcheck)
      run_isolated_check check_shell_syntax
      run_isolated_check check_shellcheck
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

