# shellcheck shell=bash
# shellcheck source=../verify.sh
# Meta guardrail: verifies every check_* function is registered in a CI target arm and in the all list.

check_target_groups_cover_all_checks() {
  awk '
    /^check_[A-Za-z0-9_]+\(\)/ { d=$0; sub(/\(.*/, "", d); defs[d]=1; next }
    /^main\(\) \{/ { in_main=1; next }
    in_main && /^main "\$@"/ { in_main=0; next }
    in_main && /^  check_[A-Za-z0-9_]+$/ { all_calls[$1]=1; next }
    in_main && /^      check_[A-Za-z0-9_]+$/ { arm_calls[$1]=1; next }
    END {
      for (d in defs) {
        if (!(d in all_calls) && !(d in arm_calls)) {
          printf "uninvoked check function: %s\n", d > "/dev/stderr"; exit 1
        }
      }
      for (c in all_calls) {
        if (!(c in arm_calls)) {
          printf "check missing from CI targets (syntax/shellcheck/release/dispatch/guards): %s\n", c > "/dev/stderr"; exit 1
        }
      }
      for (c in arm_calls) {
        if (!(c in all_calls)) {
          printf "target-only check missing from all: %s\n", c > "/dev/stderr"; exit 1
        }
      }
    }
  ' "$ROOT_DIR/tools/verify.sh" "$ROOT_DIR"/tools/checks/*.sh
}

