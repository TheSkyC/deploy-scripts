#!/usr/bin/env bash

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info() { echo -e "${BLUE}[i]${NC} $*" >&2; }
success() { echo -e "${GREEN}[+]${NC} $*" >&2; }
warn() { echo -e "${YELLOW}[!]${NC} $*" >&2; }
error() { echo -e "${RED}[x]${NC} $*" >&2; exit 1; }
step() { echo -e "\n${CYAN}${BOLD}== $* ==${NC}" >&2; }
prompt() { echo -ne "${YELLOW}[?]${NC} $* " >&2; }
