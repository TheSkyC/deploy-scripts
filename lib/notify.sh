#!/usr/bin/env bash

# Global notification integration: ntfy / Gotify push backends with a
# fail-open contract — notification failures are logged as warnings and can
# never block the operation that triggered them.
#
# Configuration lives in /etc/deploy-notify.conf (root:600, same key=value
# format and trust gate as app configs):
#   NOTIFY_ENABLED=true|false
#   NOTIFY_BACKEND=ntfy|gotify
#   NOTIFY_URL=            service origin, e.g. https://ntfy.example.com
#   NOTIFY_TOPIC=          ntfy topic (ntfy only)
#   NOTIFY_TOKEN=          access token sent as Authorization: Bearer
#   NOTIFY_USERNAME=       gotify basic-auth username (gotify only)
#   NOTIFY_PASSWORD=       gotify basic-auth password (gotify only)

NOTIFY_CONF_FILE="${NOTIFY_CONF_FILE:-/etc/deploy-notify.conf}"

notify_load_config() {
  local conf_file="$NOTIFY_CONF_FILE"
  NOTIFY_ENABLED=false NOTIFY_BACKEND="" NOTIFY_URL="" NOTIFY_TOPIC=""
  NOTIFY_TOKEN="" NOTIFY_USERNAME="" NOTIFY_PASSWORD=""
  [[ -f "$conf_file" ]] || return 0
  # Same trust gate as app configs: root-owned, mode 600/400, or ignored.
  if ! app_conf_trusted_value "$conf_file" "NOTIFY_ENABLED" >/dev/null 2>&1; then
    return 1
  fi
  local line key value
  while IFS= read -r line; do
    [[ "$line" =~ ^[A-Z_]+= ]] || continue
    key="${line%%=*}"
    value="${line#*=}"
    value="${value%\"}"
    value="${value#\"}"
    case "$key" in
      NOTIFY_ENABLED|NOTIFY_BACKEND|NOTIFY_URL|NOTIFY_TOPIC|NOTIFY_TOKEN|NOTIFY_USERNAME|NOTIFY_PASSWORD)
        printf -v "$key" '%s' "$value"
        ;;
    esac
  done < "$conf_file"
}

# Redact anything that looks like a credential from message bodies before
# they leave the machine. Reuses the operation-log redaction patterns.
notify_redact() {
  local text="$1"
  printf '%s' "$text" | sed -E \
    -e 's/([[:alnum:]_.-]*(TOKEN|PASSWORD|SECRET|API_KEY|PRIVATE_KEY|KEY)[[:alnum:]_.-]*[[:space:]]*=[[:space:]]*)[^[:space:]]+/\1[REDACTED]/Ig' \
    -e 's#(Authorization:[[:space:]]*Bearer[[:space:]]+)[^[:space:]]+#\1[REDACTED]#Ig' \
    -e 's#(https?://[^:/[:space:]]+):[^@/[:space:]]+@#\1:[REDACTED]@#g'
}

# Send one notification. Never fails the caller: every error path warns to
# stderr (or silently no-ops when notifications are disabled/unconfigured)
# and returns 0 unless explicitly asked to report failure via NOTIFY_STRICT.
notify_send() {
  local title="$1" body="${2:-}"
  notify_load_config || { warn "$(t notify.warn.untrusted_config)"; return "${NOTIFY_STRICT:-0}"; }
  [[ "${NOTIFY_ENABLED,,}" == true ]] || {
    [[ "${NOTIFY_STRICT:-0}" == 1 ]] && warn "$(t notify.warn.disabled)"
    return "${NOTIFY_STRICT:-0}"
  }
  case "${NOTIFY_BACKEND,,}" in
    ntfy|gotify) ;;
    *) warn "$(t notify.warn.no_backend)"; return "${NOTIFY_STRICT:-0}" ;;
  esac
  [[ -n "$NOTIFY_URL" ]] || { warn "$(t notify.warn.no_url)"; return "${NOTIFY_STRICT:-0}"; }
  if ! command -v curl >/dev/null 2>&1; then
    warn "$(t notify.warn.curl_missing)"
    return "${NOTIFY_STRICT:-0}"
  fi
  title="$(notify_redact "$title")"
  body="$(notify_redact "$body")"
  local args=(curl --max-time 10 -sS -o /dev/null -w '%{http_code}')
  case "${NOTIFY_BACKEND,,}" in
    ntfy)
      if [[ -n "$NOTIFY_TOKEN" ]]; then
        args+=(-H "Authorization: Bearer ${NOTIFY_TOKEN}")
      fi
      args+=(-H "Title: ${title}" -H "Tags: warning" --data-binary "$body" \
        "${NOTIFY_URL%/}/${NOTIFY_TOPIC:-deploy-scripts}")
      ;;
    gotify)
      if [[ -n "$NOTIFY_TOKEN" ]]; then
        args+=(-H "Authorization: Bearer ${NOTIFY_TOKEN}")
      elif [[ -n "$NOTIFY_USERNAME" && -n "$NOTIFY_PASSWORD" ]]; then
        args+=(-u "${NOTIFY_USERNAME}:${NOTIFY_PASSWORD}")
      fi
      local gotify_payload
      gotify_payload="{\"title\":$(app_json_string "$title"),\"message\":$(app_json_string "$body"),\"priority\":5}"
      args+=(-H "Content-Type: application/json" \
        --data "$gotify_payload" \
        "${NOTIFY_URL%/}/message")
      ;;
  esac
  local http_code
  http_code="$("${args[@]}" 2>/dev/null)" || http_code="000"
  case "$http_code" in
    2*) info "$(t notify.info.sent)"; return 0 ;;
    *)
      warn "$(t notify.warn.send_failed "$http_code")"
      [[ "${NOTIFY_STRICT:-0}" == 1 ]] && return 1
      return 0
      ;;
  esac
}

# Interactive/CLI configuration for the notification backends. Values are
# merged over the existing config so each flag can be set independently;
# --disable flips NOTIFY_ENABLED while keeping the rest, and --test sends a
# harmless probe message. The file is written root:600 via atomic_write_file.
notify_config_main() {
  require_root "notify-config"
  local enable="" backend="" url="" topic="" token="" test_only=false clear_all=false
  while (($#)); do
    case "$1" in
      --enable) enable=true; shift ;;
      --disable) enable=false; shift ;;
      --backend) backend="${2:-}"; shift 2 ;;
      --url) url="${2:-}"; shift 2 ;;
      --topic) topic="${2:-}"; shift 2 ;;
      --token) token="${2:-}"; shift 2 ;;
      --test) test_only=true; shift ;;
      --clear) clear_all=true; shift ;;
      -h|--help)
        t notify.usage "$0"
        return 0
        ;;
      *)
        t notify.usage "$0"
        return 2
        ;;
    esac
  done
  if [[ "$clear_all" == "true" ]]; then
    rm -f "$NOTIFY_CONF_FILE"
    success "$(t notify.config.cleared "$NOTIFY_CONF_FILE")"
    return 0
  fi
  # Load current values as the merge base.
  local conf_file="$NOTIFY_CONF_FILE"
  NOTIFY_ENABLED=false NOTIFY_BACKEND="" NOTIFY_URL="" NOTIFY_TOPIC=""
  NOTIFY_TOKEN="" NOTIFY_USERNAME="" NOTIFY_PASSWORD=""
  if [[ -f "$conf_file" ]]; then
    local line key value
    while IFS= read -r line; do
      [[ "$line" =~ ^[A-Z_]+= ]] || continue
      key="${line%%=*}"
      value="${line#*=}"
      value="${value%\"}"
      value="${value#\"}"
      case "$key" in
        NOTIFY_ENABLED|NOTIFY_BACKEND|NOTIFY_URL|NOTIFY_TOPIC|NOTIFY_TOKEN|NOTIFY_USERNAME|NOTIFY_PASSWORD)
          printf -v "$key" '%s' "$value"
          ;;
      esac
    done < "$conf_file"
  fi
  [[ -n "$backend" ]] || true
  case "${backend,,}" in
    ""|ntfy|gotify) : ;;
    *) error "$(t error.url_invalid NOTIFY_BACKEND "$backend")" ;;
  esac
  [[ -n "$backend" ]] && NOTIFY_BACKEND="${backend,,}"
  [[ -n "$url" ]] && NOTIFY_URL="$url"
  [[ -n "$topic" ]] && NOTIFY_TOPIC="$topic"
  [[ -n "$token" ]] && { NOTIFY_TOKEN="$token"; NOTIFY_USERNAME=""; NOTIFY_PASSWORD=""; }
  [[ -n "$enable" ]] && NOTIFY_ENABLED="$( [[ "${enable}" == true ]] && echo true || echo false )"
  if [[ "$test_only" == "true" ]]; then
    # Probe with the merged values, not whatever the disk still holds:
    # notify_send reloads the config file internally, so stage the merged
    # values into a private probe file and point notify_send at it. A test
    # without an enabled backend or a reachable URL must fail loudly instead
    # of claiming success while silently skipping the send.
    local probe_file probe_status
    probe_file="$(mktemp "${TMPDIR:-/tmp}/deploy-notify-probe.XXXXXX")" || error "$(t error.tmpdir)"
    if ! atomic_write_file "$probe_file" 600 <<PROBE
NOTIFY_ENABLED="${NOTIFY_ENABLED}"
NOTIFY_BACKEND="${NOTIFY_BACKEND}"
NOTIFY_URL="${NOTIFY_URL}"
NOTIFY_TOPIC="${NOTIFY_TOPIC}"
NOTIFY_TOKEN="${NOTIFY_TOKEN}"
NOTIFY_USERNAME="${NOTIFY_USERNAME}"
NOTIFY_PASSWORD="${NOTIFY_PASSWORD}"
PROBE
    then
      rm -f "$probe_file"
      error "$(t error.config_write "$probe_file")"
    fi
    NOTIFY_STRICT=1 NOTIFY_CONF_FILE="$probe_file" notify_send \
      "deploy-scripts notification test" \
      "If you can read this, notifications work. No secrets are included."
    probe_status=$?
    rm -f "$probe_file"
    if [[ "$probe_status" -ne 0 ]]; then
      error "$(t notify.test.failed)"
    fi
    # The probe succeeded with the merged values, so persist them so the
    # tested configuration is exactly what later runs will use.
    if ! atomic_write_file "$conf_file" 600 <<CONF
NOTIFY_ENABLED="${NOTIFY_ENABLED}"
NOTIFY_BACKEND="${NOTIFY_BACKEND}"
NOTIFY_URL="${NOTIFY_URL}"
NOTIFY_TOPIC="${NOTIFY_TOPIC}"
NOTIFY_TOKEN="${NOTIFY_TOKEN}"
NOTIFY_USERNAME="${NOTIFY_USERNAME}"
NOTIFY_PASSWORD="${NOTIFY_PASSWORD}"
CONF
    then
      error "$(t error.config_write "$conf_file")"
    fi
    success "$(t notify.test.sent_ok)"
    return 0
  fi
  if ! atomic_write_file "$conf_file" 600 <<CONF
NOTIFY_ENABLED="${NOTIFY_ENABLED}"
NOTIFY_BACKEND="${NOTIFY_BACKEND}"
NOTIFY_URL="${NOTIFY_URL}"
NOTIFY_TOPIC="${NOTIFY_TOPIC}"
NOTIFY_TOKEN="${NOTIFY_TOKEN}"
NOTIFY_USERNAME="${NOTIFY_USERNAME}"
NOTIFY_PASSWORD="${NOTIFY_PASSWORD}"
CONF
  then
    error "$(t error.config_write "$conf_file")"
  fi
  success "$(t notify.config.saved "$conf_file")"
}
