#!/usr/bin/env bash

DEPLOY_APP_IDS=(newapi sub2api vaultwarden cyberstrikeai blog tickflow)

deploy_trim() {
  local value="${1:-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "$value"
}

deploy_app_ids() {
  printf '%s\n' "${DEPLOY_APP_IDS[@]}"
}

deploy_app_file_for() {
  case "$1" in
    newapi) echo "apps/newapi.sh" ;;
    sub2api) echo "apps/sub2api.sh" ;;
    vaultwarden) echo "apps/vaultwarden.sh" ;;
    cyberstrikeai) echo "apps/cyberstrikeai.sh" ;;
    blog) echo "apps/blog.sh" ;;
    tickflow) echo "apps/tickflow.sh" ;;
    *) return 1 ;;
  esac
}

deploy_app_impl_file_for() {
  case "$1" in
    newapi) echo "impl/install_newapi.sh" ;;
    sub2api) echo "impl/install_sub2api.sh" ;;
    vaultwarden) echo "impl/install_vaultwarden.sh" ;;
    cyberstrikeai) echo "impl/install_cyberstrikeai.sh" ;;
    blog) echo "impl/install_blog.sh" ;;
    tickflow) echo "impl/install_tickflow.sh" ;;
    *) return 1 ;;
  esac
}

deploy_app_name_for() {
  case "$1" in
    newapi) echo "New API" ;;
    sub2api) echo "Sub2API" ;;
    vaultwarden) echo "Vaultwarden" ;;
    cyberstrikeai) echo "CyberStrikeAI" ;;
    blog) echo "Hugo Blog" ;;
    tickflow) echo "TickFlow Stock Panel" ;;
    *) return 1 ;;
  esac
}

deploy_app_index_for() {
  local app_id="$1" index=1 id
  for id in "${DEPLOY_APP_IDS[@]}"; do
    if [[ "$id" == "$app_id" ]]; then
      echo "$index"
      return 0
    fi
    index=$((index + 1))
  done
  return 1
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
