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

