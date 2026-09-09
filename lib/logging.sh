#!/usr/bin/env bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ANSI colors are only emitted when stderr is an interactive terminal.
# Piped output, log files, and CI captures stay escape-free by default.
# NO_COLOR (https://no-color.org/) and TERM=dumb disable colors everywhere,
# while DEPLOY_FORCE_COLOR=1 re-enables them for non-TTY captures on demand.
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
error() { echo -e "${RED}[x]${NC} $*" >&2; exit 1; }
step() { echo -e "\n${CYAN}${BOLD}== $* ==${NC}" >&2; }
prompt() { echo -ne "${YELLOW}[?]${NC} $* " >&2; }
