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


