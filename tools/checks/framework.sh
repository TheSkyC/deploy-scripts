# shellcheck shell=bash
# shellcheck source=../verify.sh
# Meta guardrail: verifies every check_* function is registered in a CI target
# arm and that target arms reference defined checks. The all target
# auto-enumerates check_* functions, so no separate all list is maintained.

check_target_groups_cover_all_checks() {
  awk '
    /^check_[A-Za-z0-9_]+\(\)/ { d=$0; sub(/\(.*/, "", d); defs[d]=1; next }
    /^main\(\) \{/ { in_main=1; next }
    /^main "\$@"/ { in_main=0; next }
    in_main && /^      check_[A-Za-z0-9_]+[[:space:]]*$/ { arm_calls[$1]=1; next }
    END {
      for (d in defs) {
        if (!(d in arm_calls)) {
          printf "check function not registered in a verify target arm: %s\n", d > "/dev/stderr"; exit 1
        }
      }
      for (c in arm_calls) {
        if (!(c in defs)) {
          printf "verify target arm references undefined check: %s\n", c > "/dev/stderr"; exit 1
        }
      }
    }
  ' "$ROOT_DIR/tools/verify.sh" "$ROOT_DIR"/tools/checks/*.sh
}


check_run_checks_parallel_cleans_tmpdir() {
  local tmp_parent
  tmp_parent="$(mktemp -d)"
  TMPDIR="$tmp_parent" "$BASH_BIN" -c '
    set -euo pipefail
    source "$1/tools/verify.sh" help >/dev/null 2>&1
    ok_check() { return 0; }
    fail_check() { return 1; }
    before="$(find "$TMPDIR" -mindepth 1 2>/dev/null | wc -l)"
    PARALLEL_JOBS=1 run_checks_parallel ok_check
    [[ -z "$(trap -p EXIT)" ]] || { echo "run_checks_parallel left an EXIT trap installed" >&2; exit 1; }
    set +e
    run_checks_parallel fail_check
    st=$?
    set -e
    [[ "$st" -ne 0 ]] || { echo "run_checks_parallel did not propagate a failing check" >&2; exit 1; }
    [[ -z "$(trap -p EXIT)" ]] || { echo "run_checks_parallel left an EXIT trap installed after failure" >&2; exit 1; }
    after="$(find "$TMPDIR" -mindepth 1 2>/dev/null | wc -l)"
    [[ "$after" -eq "$before" ]] || { echo "run_checks_parallel leaked a temp directory" >&2; exit 1; }
    exit 0
  ' _ "$ROOT_DIR"
  rm -rf "$tmp_parent"
}


# Meta guardrail: top-level wrappers (deploy.sh, install_*.sh) and bin/
# loaders must mirror each other one-to-one, and each loader must wire the
# documented sources so a new app cannot ship without its entry points.

check_root_wrappers_match_bin_loaders() {
  local name app_id app_file candidate_id missing=0
  local -a wrappers loaders

  # Wrapper names are derived by the registry and may intentionally differ
  # from an app ID (for example blog -> install_hugo_blog.sh).
  source "${ROOT_DIR}/lib/app_registry.sh"

  mapfile -t wrappers < <(cd "$ROOT_DIR" && printf '%s\n' deploy.sh install_*.sh | LC_ALL=C sort)
  mapfile -t loaders < <(cd "$ROOT_DIR/bin" && printf '%s\n' *.sh | LC_ALL=C sort)

  if [[ "${wrappers[*]}" != "${loaders[*]}" ]]; then
    echo "Top-level wrappers and bin/ loaders are out of sync:" >&2
    echo "  root: ${wrappers[*]}" >&2
    echo "  bin:  ${loaders[*]}" >&2
    missing=1
  fi

  for name in "${wrappers[@]}"; do
    if ! grep -qxF "exec bash \"\${SCRIPT_DIR}/bin/${name}\" \"\$@\"" "${ROOT_DIR}/${name}"; then
      echo "Top-level wrapper ${name} does not exec bin/${name}" >&2
      missing=1
    fi

    if [[ "$name" == "deploy.sh" ]]; then
      grep -qxF 'source "${DEPLOY_ROOT_DIR}/lib/core.sh"' "${ROOT_DIR}/bin/${name}" \
        && grep -qxF 'manager_main "$@"' "${ROOT_DIR}/bin/${name}" \
        || { echo "bin/${name} must source lib/core.sh and call manager_main" >&2; missing=1; }
    else
      app_id=""
      for candidate_id in "${DEPLOY_APP_IDS[@]}"; do
        if [[ "$(deploy_app_script_name_for "$candidate_id")" == "$name" ]]; then
          app_id="$candidate_id"
          break
        fi
      done
      if [[ -z "$app_id" ]]; then
        echo "bin/${name} has no matching app registry entry" >&2
        missing=1
        continue
      fi
      app_file="$(deploy_app_file_for "$app_id")"
      grep -qxF 'source "${DEPLOY_ROOT_DIR}/lib/core.sh"' "${ROOT_DIR}/bin/${name}" \
        && grep -qxF "source \"\${DEPLOY_ROOT_DIR}/${app_file}\"" "${ROOT_DIR}/bin/${name}" \
        && grep -qxF 'main "$@"' "${ROOT_DIR}/bin/${name}" \
        || { echo "bin/${name} must source lib/core.sh and ${app_file}, then call main" >&2; missing=1; }
      if [[ ! -f "${ROOT_DIR}/${app_file}" ]]; then
        echo "bin/${name} references missing ${app_file}" >&2
        missing=1
      fi
    fi
  done

  [[ "$missing" -eq 0 ]] || return 1
}

