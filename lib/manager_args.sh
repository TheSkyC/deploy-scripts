#!/usr/bin/env bash

# Shared CLI argument parsing for the central batch commands
# (status-all / doctor-all / backup-all / check-update / update-all).
#
# Every central command used to implement its own --json/--include/--exclude
# (plus command-specific flags) loop, and some accepted flags were silently
# ignored.  This helper centralizes the common subset and rejects unknown
# flags uniformly.
#
# Usage:
#   manager_parse_args <spec> <usage_fn> [args...]
#
# <spec> is a whitespace-separated list of supported flags:
#   --json --short --strict --errors-only --only-installed --no-probe
#   --no-network --dry-run --yes --refresh --continue-on-error --help
#   --include --exclude
# Flags with values (--include/--exclude) consume the next argument or an
# =value form.  Parsed values are exported as MANAGER_ARG_* variables:
#   MANAGER_ARG_JSON              0|1
#   MANAGER_ARG_SHORT             0|1
#   MANAGER_ARG_STRICT            0|1
#   MANAGER_ARG_ERRORS_ONLY       0|1
#   MANAGER_ARG_ONLY_INSTALLED    0|1
#   MANAGER_ARG_NO_PROBE          0|1
#   MANAGER_ARG_NO_NETWORK        0|1
#   MANAGER_ARG_DRY_RUN           0|1
#   MANAGER_ARG_YES               0|1
#   MANAGER_ARG_REFRESH           0|1
#   MANAGER_ARG_CONTINUE_ON_ERROR 0|1
#   MANAGER_ARG_INCLUDE           CSV string ("" when unset)
#   MANAGER_ARG_EXCLUDE           CSV string ("" when unset)
# Returns 0 on success, 2 on a usage error (after calling the usage fn).

manager_parse_args() {
  local spec="$1" usage_fn="$2"
  shift 2
  local arg value
  local -a specs=()
  local f
  for f in $spec; do specs+=("$f"); done
  _manager_arg_supported() {
    local needle="$1"; shift
    local x
    for x in "$@"; do [[ "$x" == "$needle" ]] && return 0; done
    return 1
  }
  MANAGER_ARG_JSON=0
  MANAGER_ARG_SHORT=0
  MANAGER_ARG_STRICT=0
  MANAGER_ARG_ERRORS_ONLY=0
  MANAGER_ARG_ONLY_INSTALLED=0
  MANAGER_ARG_NO_PROBE=0
  MANAGER_ARG_NO_NETWORK=0
  MANAGER_ARG_DRY_RUN=0
  MANAGER_ARG_YES=0
  MANAGER_ARG_REFRESH=0
  MANAGER_ARG_CONTINUE_ON_ERROR=0
  MANAGER_ARG_INCLUDE=""
  MANAGER_ARG_EXCLUDE=""
  while (($#)); do
    arg="$1"; shift
    case "$arg" in
      --json)
        _manager_arg_supported --json "${specs[@]}" || { "$usage_fn"; return 2; }
        MANAGER_ARG_JSON=1 ;;
      --short)
        _manager_arg_supported --short "${specs[@]}" || { "$usage_fn"; return 2; }
        MANAGER_ARG_SHORT=1 ;;
      --strict)
        _manager_arg_supported --strict "${specs[@]}" || { "$usage_fn"; return 2; }
        MANAGER_ARG_STRICT=1 ;;
      --errors-only)
        _manager_arg_supported --errors-only "${specs[@]}" || { "$usage_fn"; return 2; }
        MANAGER_ARG_ERRORS_ONLY=1 ;;
      --only-installed)
        _manager_arg_supported --only-installed "${specs[@]}" || { "$usage_fn"; return 2; }
        MANAGER_ARG_ONLY_INSTALLED=1 ;;
      --no-probe)
        _manager_arg_supported --no-probe "${specs[@]}" || { "$usage_fn"; return 2; }
        MANAGER_ARG_NO_PROBE=1 ;;
      --no-network)
        _manager_arg_supported --no-network "${specs[@]}" || { "$usage_fn"; return 2; }
        MANAGER_ARG_NO_NETWORK=1 ;;
      --dry-run)
        _manager_arg_supported --dry-run "${specs[@]}" || { "$usage_fn"; return 2; }
        MANAGER_ARG_DRY_RUN=1 ;;
      --yes)
        _manager_arg_supported --yes "${specs[@]}" || { "$usage_fn"; return 2; }
        MANAGER_ARG_YES=1 ;;
      --refresh)
        _manager_arg_supported --refresh "${specs[@]}" || { "$usage_fn"; return 2; }
        MANAGER_ARG_REFRESH=1 ;;
      --continue-on-error)
        _manager_arg_supported --continue-on-error "${specs[@]}" || { "$usage_fn"; return 2; }
        MANAGER_ARG_CONTINUE_ON_ERROR=1 ;;
      --include)
        _manager_arg_supported --include "${specs[@]}" || { "$usage_fn"; return 2; }
        (($#)) || { "$usage_fn"; return 2; }
        value="$1"; shift; MANAGER_ARG_INCLUDE="$value" ;;
      --exclude)
        _manager_arg_supported --exclude "${specs[@]}" || { "$usage_fn"; return 2; }
        (($#)) || { "$usage_fn"; return 2; }
        value="$1"; shift; MANAGER_ARG_EXCLUDE="$value" ;;
      --include=*)
        _manager_arg_supported --include "${specs[@]}" || { "$usage_fn"; return 2; }
        MANAGER_ARG_INCLUDE="${arg#*=}" ;;
      --exclude=*)
        _manager_arg_supported --exclude "${specs[@]}" || { "$usage_fn"; return 2; }
        MANAGER_ARG_EXCLUDE="${arg#*=}" ;;
      --help|-h)
        _manager_arg_supported --help "${specs[@]}" || { "$usage_fn"; return 2; }
        "$usage_fn"; return 0 ;;
      *)
        "$usage_fn"; return 2 ;;
    esac
  done
  return 0
}
