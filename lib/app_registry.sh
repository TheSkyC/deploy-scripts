#!/usr/bin/env bash

# Registry spec columns: id|name|definition file|impl file|capabilities
# The capabilities column is a comma-separated list; "backup" marks apps whose
# do_backup performs a real backup. Apps without it are skipped by backup-all
# without loading their implementation — the previous grep-the-source probe
# (searching do_backup's body for unsupported_action) was fragile and required
# sourcing every app just to plan a batch.
DEPLOY_APP_SPECS=(
  "newapi|New API|apps/newapi.sh|impl/install_newapi.sh|backup,restore"
  "sub2api|Sub2API|apps/sub2api.sh|impl/install_sub2api.sh|backup,restore"
  "vaultwarden|Vaultwarden|apps/vaultwarden.sh|impl/install_vaultwarden.sh|backup,restore"
  "cyberstrikeai|CyberStrikeAI|apps/cyberstrikeai.sh|impl/install_cyberstrikeai.sh|backup,restore"
  "blog|Hugo Blog|apps/blog.sh|impl/install_hugo_blog.sh|backup,restore"
  "tickflow|TickFlow Stock Panel|apps/tickflow.sh|impl/install_tickflow.sh|backup,restore"
  "cpa-stack|CLIProxyAPI + CPA Manager Plus|apps/cpa_stack.sh|impl/install_cpa_stack.sh|backup,restore"
  "ntfy|ntfy|apps/ntfy.sh|impl/install_ntfy.sh|backup"
  "meilisearch|Meilisearch|apps/meilisearch.sh|impl/install_meilisearch.sh|backup"
  "alist|Alist|apps/alist.sh|impl/install_alist.sh|backup"
  "filebrowser|Filebrowser|apps/filebrowser.sh|impl/install_filebrowser.sh|backup"
  "navidrome|Navidrome|apps/navidrome.sh|impl/install_navidrome.sh|backup"
  "frps|frps|apps/frps.sh|impl/install_frps.sh|backup"
  "gitea|Gitea|apps/gitea.sh|impl/install_gitea.sh|backup"
  "gotify|Gotify|apps/gotify.sh|impl/install_gotify.sh|backup"
  "beszel|Beszel|apps/beszel.sh|impl/install_beszel.sh|backup"
)

DEPLOY_APP_IDS=()
DEPLOY_APP_NAMES=()
DEPLOY_APP_FILES=()
DEPLOY_APP_IMPL_FILES=()
DEPLOY_APP_CAPABILITIES=()

for deploy_app_spec in "${DEPLOY_APP_SPECS[@]}"; do
  IFS='|' read -r deploy_app_id deploy_app_name deploy_app_file deploy_app_impl_file deploy_app_caps <<< "$deploy_app_spec"
  DEPLOY_APP_IDS+=("$deploy_app_id")
  DEPLOY_APP_NAMES+=("$deploy_app_name")
  DEPLOY_APP_FILES+=("$deploy_app_file")
  DEPLOY_APP_IMPL_FILES+=("$deploy_app_impl_file")
  DEPLOY_APP_CAPABILITIES+=("${deploy_app_caps:-}")
done
unset deploy_app_spec deploy_app_id deploy_app_name deploy_app_file deploy_app_impl_file deploy_app_caps

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
    capabilities) echo "${DEPLOY_APP_CAPABILITIES[$offset]}" ;;
    *) return 1 ;;
  esac
}

deploy_app_file_for() {
  deploy_app_metadata_for "$1" file
}

deploy_app_impl_file_for() {
  deploy_app_metadata_for "$1" impl_file
}

deploy_app_script_name_for() {
  local app_id="$1"
  case "$app_id" in
    blog) echo "install_hugo_blog.sh" ;;
    *) echo "install_${app_id//-/_}.sh" ;;
  esac
}

deploy_app_bundled_impl_script_name_for() {
  local app_id="$1"
  case "$app_id" in
    blog) echo "install_hugo_blog_impl.sh" ;;
    *) echo "install_${app_id}_impl.sh" ;;
  esac
}

deploy_app_name_for() {
  deploy_app_metadata_for "$1" name
}

# Print 0/1 for whether the app's capabilities list contains the given
# capability (for example "backup" or "restore").
deploy_app_has_capability() {
  local app_id="$1" capability="$2" caps cap
  caps="$(deploy_app_metadata_for "$app_id" capabilities)" || return 1
  case ",${caps}," in
    *,"$capability",*) return 0 ;;
    *) return 1 ;;
  esac
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
