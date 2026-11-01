#!/usr/bin/env bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Colors are for interactive terminals only; pipes, log files, and CI
# captures stay escape-free. NO_COLOR/TERM=dumb always win, and
# DEPLOY_FORCE_COLOR=1 explicitly enables colors for non-TTY captures.
if [[ -n "${NO_COLOR:-}" || "${TERM:-}" == "dumb" ]] \
    || { [[ ! -t 2 ]] && [[ "${DEPLOY_FORCE_COLOR:-0}" != "1" ]]; }; then
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  CYAN=''
  BOLD=''
  NC=''
fi

info() { echo -e "${BLUE}[i]${NC} $*" >&2; }
success() { echo -e "${GREEN}[+]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[!]${NC} $*" >&2; }
# error() terminates the current shell, which is only the command
# substitution subshell when called inside $() — callers that must tolerate
# a failed lookup should check the guard themselves instead of relying on
# error() inside a substitution.
error() { echo -e "${RED}[x]${NC} $*" >&2; exit 1; }
step() { echo -e "\n${CYAN}${BOLD}== $* ==${NC}" >&2; }
prompt() { echo -ne "${YELLOW}[?]${NC} $* " >&2; }
