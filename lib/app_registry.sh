#!/usr/bin/env bash

DEPLOY_APP_SPECS=(
  "newapi|New API|apps/newapi.sh|impl/install_newapi.sh"
  "sub2api|Sub2API|apps/sub2api.sh|impl/install_sub2api.sh"
  "vaultwarden|Vaultwarden|apps/vaultwarden.sh|impl/install_vaultwarden.sh"
  "cyberstrikeai|CyberStrikeAI|apps/cyberstrikeai.sh|impl/install_cyberstrikeai.sh"
  "blog|Hugo Blog|apps/blog.sh|impl/install_blog.sh"
  "tickflow|TickFlow Stock Panel|apps/tickflow.sh|impl/install_tickflow.sh"
  "cpa-stack|CLIProxyAPI + CPA Manager Plus|apps/cpa_stack.sh|impl/install_cpa_stack.sh"
  "ntfy|ntfy|apps/ntfy.sh|impl/install_ntfy.sh"
  "meilisearch|Meilisearch|apps/meilisearch.sh|impl/install_meilisearch.sh"
  "alist|Alist|apps/alist.sh|impl/install_alist.sh"
)

DEPLOY_APP_IDS=()
DEPLOY_APP_NAMES=()
DEPLOY_APP_FILES=()
DEPLOY_APP_IMPL_FILES=()

for deploy_app_spec in "${DEPLOY_APP_SPECS[@]}"; do
  IFS='|' read -r deploy_app_id deploy_app_name deploy_app_file deploy_app_impl_file <<< "$deploy_app_spec"
  DEPLOY_APP_IDS+=("$deploy_app_id")
  DEPLOY_APP_NAMES+=("$deploy_app_name")
  DEPLOY_APP_FILES+=("$deploy_app_file")
  DEPLOY_APP_IMPL_FILES+=("$deploy_app_impl_file")
done
unset deploy_app_spec deploy_app_id deploy_app_name deploy_app_file deploy_app_impl_file

deploy_trim() {
  local value="${1:-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

deploy_app_ids() {
  printf '%s\n' "${DEPLOY_APP_IDS[@]}"
}

deploy_app_offset_for() {
  local app_id="$1" offset
  for offset in "${!DEPLOY_APP_IDS[@]}"; do
    if [[ "${DEPLOY_APP_IDS[$offset]}" == "$app_id" ]]; then
      echo "$offset"
      return 0
    fi
  done
  return 1
}

deploy_app_metadata_for() {
  local app_id="$1" field="$2" offset
  offset="$(deploy_app_offset_for "$app_id")" || return 1
  case "$field" in
    file) echo "${DEPLOY_APP_FILES[$offset]}" ;;
    impl_file) echo "${DEPLOY_APP_IMPL_FILES[$offset]}" ;;
    name) echo "${DEPLOY_APP_NAMES[$offset]}" ;;
    *) return 1 ;;
  esac
}

deploy_app_file_for() {
  deploy_app_metadata_for "$1" file
}

deploy_app_impl_file_for() {
  deploy_app_metadata_for "$1" impl_file
}

deploy_app_name_for() {
  deploy_app_metadata_for "$1" name
}

deploy_app_index_for() {
  local offset
  offset="$(deploy_app_offset_for "$1")" || return 1
  echo "$((offset + 1))"
}

deploy_app_id_from_selection() {
  local selection index=1 id
  selection="$(deploy_trim "${1:-}")"
  case "${selection,,}" in
    q|quit|exit) return 2 ;;
  esac
  for id in "${DEPLOY_APP_IDS[@]}"; do
    if [[ "${selection,,}" == "$id" || "$selection" == "$index" ]]; then
      echo "$id"
      return 0
    fi
    index=$((index + 1))
  done
  return 1
}
