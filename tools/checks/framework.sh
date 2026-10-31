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
    in_main && /^[[:space:]]+run_isolated_check check_[A-Za-z0-9_]+[[:space:]]*$/ { arm_calls[$2]=1; next }
    in_main && /^[[:space:]]+check_[A-Za-z0-9_]+[[:space:]]*$/ { arm_calls[$1]=1; next }
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

# Run the behavioral feature proofs (backup/restore, notify, schedule, migrate,
# compose, fleet) with stub backends. Wrapped as a check so the `all` target and
# the guards CI job actually execute them instead of letting them rot.
check_feature_proofs() {
  "$BASH_BIN" tools/prove-features.sh >/dev/null
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
    before_trap="$(trap -p EXIT)"
    PARALLEL_JOBS=1 run_checks_parallel ok_check
    [[ "$(trap -p EXIT)" == "$before_trap" ]] || { echo "run_checks_parallel changed the caller EXIT trap" >&2; exit 1; }
    set +e
    run_checks_parallel fail_check
    st=$?
    set -e
    [[ "$st" -ne 0 ]] || { echo "run_checks_parallel did not propagate a failing check" >&2; exit 1; }
    [[ "$(trap -p EXIT)" == "$before_trap" ]] || { echo "run_checks_parallel changed the caller EXIT trap after failure" >&2; exit 1; }
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

check_acquire_lock_preserves_file_and_waits() {
  "$BASH_BIN" -c '
    set -euo pipefail
    source "$1/lib/core.sh"
    lock_dir="$(mktemp -d)"
    trap '\''rm -rf "$lock_dir"'\'' EXIT
    lock_file="${lock_dir}/app.lock"
    printf "holder-annotation" > "$lock_file"

    acquire_lock "$lock_file" 2>/dev/null
    [[ "$(cat "$lock_file")" == "holder-annotation" ]] \
      || { echo "acquire_lock truncated the lock file" >&2; exit 1; }
    release_lock

    {
      exec 3>"$lock_file"
      flock -x 3
      sleep 0.4
      flock -u 3
    } &
    hold_pid=$!
    if ( acquire_lock "$lock_file" ) >/dev/null 2>&1; then
      echo "acquire_lock succeeded while the lock was held" >&2
      exit 1
    fi

    DEPLOY_LOCK_WAIT_SECONDS=10 acquire_lock "$lock_file" 2>/dev/null
    release_lock
    wait "$hold_pid"
  ' _ "$ROOT_DIR"
}

check_logging_colors_are_tty_gated() {
  "$BASH_BIN" -c '
    set -euo pipefail
    color_code() {
      NO_COLOR="${NO_COLOR-}" TERM="${TERM_VALUE:-xterm}" DEPLOY_FORCE_COLOR="${DEPLOY_FORCE_COLOR:-0}" \
        "$1" -c '\''source "$1/lib/logging.sh"; printf "%s" "$RED"'\'' _ "$2" 2>/dev/null
    }
    root="$1"
    [[ -z "$(color_code bash "$root")" ]] \
      || { echo "colors leaked into non-TTY output" >&2; exit 1; }
    [[ -n "$(DEPLOY_FORCE_COLOR=1 color_code bash "$root")" ]] \
      || { echo "DEPLOY_FORCE_COLOR=1 did not re-enable colors" >&2; exit 1; }
    [[ -z "$(NO_COLOR=1 DEPLOY_FORCE_COLOR=1 color_code bash "$root")" ]] \
      || { echo "NO_COLOR did not override DEPLOY_FORCE_COLOR" >&2; exit 1; }
    [[ -z "$(TERM_VALUE=dumb DEPLOY_FORCE_COLOR=1 color_code bash "$root")" ]] \
      || { echo "TERM=dumb did not override DEPLOY_FORCE_COLOR" >&2; exit 1; }
  ' _ "$ROOT_DIR"
}

check_binary_app_archive_members_are_validated() {
  BA_TEST_ROOT="$ROOT_DIR" "$BASH_BIN" <<'MEMBERTEST'
set -euo pipefail
source "$BA_TEST_ROOT/lib/core.sh"
APP_ID="membershiptest"
APP_NAME="MembershipTest"
GITHUB_REPO="example/membershiptest"
BA_ARCH="amd64"
BA_ASSET_TEMPLATE="membershiptest-ARCH.tar.gz"
BA_BIN_NAME="membershiptest"
tmp="$(mktemp -d "${TMPDIR:-/tmp}/ba-members.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

python - "$tmp/good.tar.gz" <<'PY'
import io
import sys
import tarfile

with tarfile.open(sys.argv[1], "w:gz") as archive:
    data = b"payload-bytes"
    info = tarfile.TarInfo("membershiptest")
    info.size = len(data)
    archive.addfile(info, io.BytesIO(data))
PY
BA_ARCHIVE_TYPE="tar.gz"
mkdir "$tmp/good-stage"
good_bin="$(ba_prepare_binary "$tmp/good.tar.gz" "$tmp/good-stage")"
[[ -n "$good_bin" && -f "$good_bin" ]] || { echo "clean tar.gz did not stage its binary" >&2; exit 1; }

evil_name="../escaped-$(basename "$tmp")"
python - "$tmp/evil.tar.gz" "$evil_name" <<'PY'
import io
import sys
import tarfile

with tarfile.open(sys.argv[1], "w:gz") as archive:
    data = b"evil"
    info = tarfile.TarInfo(sys.argv[2])
    info.size = len(data)
    archive.addfile(info, io.BytesIO(data))
PY
mkdir "$tmp/evil-stage"
if ( BA_ARCHIVE_TYPE="tar.gz" ba_prepare_binary "$tmp/evil.tar.gz" "$tmp/evil-stage" ) >/dev/null 2>&1; then
  echo "tar.gz with a traversal member was accepted" >&2
  exit 1
fi
[[ ! -e "$(dirname "$tmp")/$(basename "$evil_name")" ]] \
  || { echo "traversal archive escaped the staging directory" >&2; exit 1; }
[[ -z "$(find "$tmp/evil-stage" -mindepth 1 -print -quit 2>/dev/null)" ]] \
  || { echo "traversal archive wrote into the staging directory" >&2; exit 1; }

mkdir "$tmp/missing-stage"
if ( BA_ARCHIVE_TYPE="tar.gz" ba_prepare_binary "$tmp/missing.tar.gz" "$tmp/missing-stage" ) >/dev/null 2>&1; then
  echo "unreadable archive was accepted" >&2
  exit 1
fi
MEMBERTEST
}
