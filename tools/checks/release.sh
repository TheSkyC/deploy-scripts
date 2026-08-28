# shellcheck shell=bash
# shellcheck source=../verify.sh
# Verify checks for release/dist artifact integrity.

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


# dist/ must always match the current source tree; run this after
# build_verified_release so dist/ reflects the sources under verification.

# lib/app_loader.sh's restore_framework_functions re-defines dispatch_action
# for the dist per-app scripts. It must carry the exact same action branches
# as lib/cli.sh; a drift here silently breaks actions in release scripts
# (D1/D2 added verify to cli.sh but not the app_loader copy, so `verify`
# died with "Invalid choice" in dist/install_*.sh).
check_app_loader_dispatch_matches_cli() {
  # Both dispatch_action copies must dispatch the same actions. Extract the
  # normalized action patterns (strip leading whitespace and the trailing
  # `)` + payload) from each function and compare the sorted sets, so an
  # indentation difference cannot mask a real branch drift.
  local cli_actions loader_actions
  cli_actions="$(awk '
    /^dispatch_action\(\)/ { in_fn=1; next }
    in_fn && /^[[:space:]]*[^[:space:]]+\)/ {
      line=$0
      sub(/^[[:space:]]*/, "", line)
      sub(/\).*$/, "", line)
      gsub(/[|" ]/, "", line)
      if (line != "") print line
    }
    in_fn && /^}/ { exit }
  ' lib/cli.sh | sort -u)"
  loader_actions="$(awk '
    /^  dispatch_action\(\)/ { in_fn=1; next }
    in_fn && /^[[:space:]]*[^[:space:]]+\)/ {
      line=$0
      sub(/^[[:space:]]*/, "", line)
      sub(/\).*$/, "", line)
      gsub(/[|" ]/, "", line)
      if (line != "") print line
    }
    in_fn && /^  }/ { exit }
  ' lib/app_loader.sh | sort -u)"
  [[ "$cli_actions" == "$loader_actions" ]] || {
    echo "app_loader.sh dispatch_action must dispatch the same actions as lib/cli.sh (restore_framework_functions copy drifted)" >&2
    diff <(printf '%s\n' "$cli_actions") <(printf '%s\n' "$loader_actions") >&2 || true
    return 1
  }
}

check_dist_is_up_to_date() {
  if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "dist freshness check requires a git checkout" >&2
    return 1
  fi
  if ! git diff --quiet -- dist/; then
    echo "dist/ is out of date with the source tree; rebuild and commit the release scripts:" >&2
    git diff --stat -- dist/ >&2
    return 1
  fi
}
