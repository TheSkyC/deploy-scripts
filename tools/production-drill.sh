#!/usr/bin/env bash
# Executable form of docs/production-validation.md.
#
# Runs the real-host drill on a disposable Debian/Ubuntu box: read-only
# baseline, dry runs that must not change anything, one real install, backup and
# verify against the running service, the central commands, and a cleanup that
# has to leave no managed artifact behind. Every phase is logged and summarised
# into results.md/results.json for the commit or PR that records the evidence.
#
# Usage (on the target host, from the repository checkout):
#   sudo bash tools/production-drill.sh --read-only
#   sudo bash tools/production-drill.sh --yes --output-dir /root/drill
#   sudo bash tools/production-drill.sh --yes --domain app.example.com --email you@example.com
#
# --yes is required for every mutating phase. The script refuses to run against
# a host where the drill app is already installed, so it cannot overwrite a real
# deployment; on any failure it tries to uninstall what it created.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR" || exit 1

# Prefer the generated release CLI: it is what operators run on a host, and it
# does not depend on the checkout launcher's extra resolution steps.
DEPLOY_CLI="$ROOT_DIR/dist/deploy.sh"
[[ -f "$DEPLOY_CLI" ]] || DEPLOY_CLI="$ROOT_DIR/deploy.sh"

DRILL_APP="${DRILL_APP:-meilisearch}"
OUTPUT_DIR=""
CONFIRM=0
READ_ONLY=0
DOMAIN=""
EMAIL=""

usage() {
  cat >&2 <<'EOF'
Usage: sudo bash tools/production-drill.sh [options]

  --read-only          Run only the read-only baseline (phases 0-1) and stop.
  --yes                Required before any mutating phase (installs/uninstalls).
  --output-dir DIR     Where to write logs, results.md, results.json.
  --domain NAME        Also request a Let's Encrypt certificate for NAME.
  --email ADDRESS      ACME account email; required with --domain.
  --app ID             Shared-binary app to install (default: meilisearch).
  -h, --help           Show this help.
EOF
}

die() {
  echo "production-drill: $*" >&2
  exit 1
}

while (($#)); do
  case "$1" in
    --read-only) READ_ONLY=1; shift ;;
    --yes) CONFIRM=1; shift ;;
    --output-dir) OUTPUT_DIR="${2:-}"; shift 2 ;;
    --domain) DOMAIN="${2:-}"; shift 2 ;;
    --email) EMAIL="${2:-}"; shift 2 ;;
    --app) DRILL_APP="${2:-}"; shift 2 ;;
    -h|--help) usage; exit 0 ;;
    *) usage; die "unknown argument: $1" ;;
  esac
done

[[ "${EUID:-$(id -u)}" -eq 0 ]] || die "run as root (sudo)"
command -v systemctl >/dev/null 2>&1 || die "systemd is required"
systemctl is-system-running >/dev/null 2>&1 || die "systemd is not running as PID 1"
[[ -f "$DEPLOY_CLI" ]] || die "run from a repository checkout"
[[ -n "$DRILL_APP" && "$DRILL_APP" =~ ^[a-z0-9-]+$ ]] || die "invalid --app"
if [[ -n "$DOMAIN" && -z "$EMAIL" ]]; then
  die "--domain requires --email"
fi

if ((READ_ONLY == 0)); then
  ((CONFIRM)) || die "refusing to install without --yes"
  if [[ -e "/etc/systemd/system/${DRILL_APP}.service" ]] \
      || [[ -e "/opt/${DRILL_APP}" ]]; then
    die "${DRILL_APP} already looks installed; use a disposable host"
  fi
fi

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUTPUT_DIR="${OUTPUT_DIR:-/root/production-drill-${STAMP}}"
LOG_DIR="${OUTPUT_DIR}/logs"
mkdir -p "$LOG_DIR"
RESULTS_MD="${OUTPUT_DIR}/results.md"
RESULTS_JSON="${OUTPUT_DIR}/results.json"

PHASE_NAMES=()
PHASE_STATES=()
PHASE_DETAILS=()
CREATED_INSTALL=0

record() {
  local name="$1" state="$2" detail="$3"
  PHASE_NAMES+=("$name")
  PHASE_STATES+=("$state")
  PHASE_DETAILS+=("$detail")
  printf '%-28s %-8s %s\n' "$name" "$state" "$detail"
}

# Run one phase, keep its full output, and record pass/fail. A failure stops the
# drill so a later phase never runs against a half-broken host.
phase() {
  local name="$1"
  shift
  local log="${LOG_DIR}/${name}.log"
  if "$@" >"$log" 2>&1; then
    record "$name" ok "see logs/${name}.log"
    return 0
  fi
  record "$name" fail "see logs/${name}.log"
  tail -n 20 "$log" >&2 || true
  return 1
}

cleanup() {
  local status=$?
  if ((CREATED_INSTALL)) && [[ "${PHASE_CLEANED:-0}" != 1 ]]; then
    echo "production-drill: cleaning up ${DRILL_APP}" >&2
    DEPLOY_ASSUME_YES=1 DEPLOY_DELETE_DATA=1 \
      bash "$DEPLOY_CLI" "$DRILL_APP" uninstall >"${LOG_DIR}/cleanup.log" 2>&1 || true
  fi
  write_results || true
  if ((status != 0)); then
    echo "production-drill: failed; see ${OUTPUT_DIR}" >&2
  fi
}

write_results() {
  local index host_os version
  host_os="$(. /etc/os-release 2>/dev/null && printf '%s %s' "${NAME:-unknown}" "${VERSION_ID:-}")"
  version="$(bash "$DEPLOY_CLI" self-version 2>/dev/null | head -n 1 || true)"
  {
    echo "# Production drill ${STAMP}"
    echo
    echo "- host: $(uname -srm)"
    echo "- os: ${host_os}"
    echo "- version: ${version:-unknown}"
    echo "- app: ${DRILL_APP}"
    echo
    echo "| Phase | Result | Detail |"
    echo "|---|---|---|"
    for index in "${!PHASE_NAMES[@]}"; do
      echo "| ${PHASE_NAMES[$index]} | ${PHASE_STATES[$index]} | ${PHASE_DETAILS[$index]} |"
    done
  } >"$RESULTS_MD"

  {
    printf '{"schema_version":1,"generated_at":"%s","app":"%s","host":"%s","os":"%s","version":"%s","phases":[' \
      "$(json_escape "$STAMP")" "$(json_escape "$DRILL_APP")" "$(json_escape "$(uname -srm)")" \
      "$(json_escape "$host_os")" "$(json_escape "${version:-unknown}")"
    for index in "${!PHASE_NAMES[@]}"; do
      ((index)) && printf ','
      printf '{"name":"%s","state":"%s","detail":"%s"}' \
        "$(json_escape "${PHASE_NAMES[$index]}")" "$(json_escape "${PHASE_STATES[$index]}")" \
        "$(json_escape "${PHASE_DETAILS[$index]}")"
    done
    printf ']}\n'
  } >"$RESULTS_JSON"
}

# Keep the JSON report parseable even if a host string contains quotes or
# backslashes; newlines collapse to spaces.
json_escape() {
  printf '%s' "$1" | tr '\n' ' ' | sed 's/\\/\\\\/g; s/"/\\"/g'
}

trap cleanup EXIT

echo "=== production-drill: ${DRILL_APP} on $(uname -srm) ==="
echo "=== output: ${OUTPUT_DIR} ==="

phase baseline-list bash "$DEPLOY_CLI" list || exit 1
phase baseline-doctor bash "$DEPLOY_CLI" doctor security --json || exit 1
phase baseline-status bash "$DEPLOY_CLI" status-all --json --no-network || exit 1

if ((READ_ONLY)); then
  echo "=== production-drill: read-only baseline complete ==="
  exit 0
fi

# Dry runs must be no-ops: no unit, no install dir, no config file.
phase dry-run-install bash "$DEPLOY_CLI" "$DRILL_APP" --dry-run install || exit 1
if [[ -e "/etc/systemd/system/${DRILL_APP}.service" ]]; then
  record dry-run-left-artifacts fail "unit appeared after a dry run"
  exit 1
fi
record dry-run-left-artifacts ok "no unit created"

phase install env DEPLOY_ASSUME_YES=1 bash "$DEPLOY_CLI" "$DRILL_APP" install || exit 1
CREATED_INSTALL=1
phase status bash "$DEPLOY_CLI" "$DRILL_APP" status || exit 1
phase status-json bash "$DEPLOY_CLI" "$DRILL_APP" status-json || exit 1
phase doctor bash "$DEPLOY_CLI" "$DRILL_APP" doctor || exit 1
phase service-active systemctl is-active "$DRILL_APP" || exit 1
phase backup bash "$DEPLOY_CLI" "$DRILL_APP" backup || exit 1
phase verify bash "$DEPLOY_CLI" "$DRILL_APP" verify || exit 1

if [[ -n "$DOMAIN" ]]; then
  phase cert env DEPLOY_ASSUME_YES=1 CERTBOT_EMAIL="$EMAIL" DOMAIN="$DOMAIN" \
    bash "$DEPLOY_CLI" "$DRILL_APP" cert || exit 1
  phase tls-renewal-systemd systemctl list-timers 'certbot*' --all || exit 1
  phase tls-renewal-audit bash "$DEPLOY_CLI" doctor security --json || exit 1
fi

phase central-check-update bash "$DEPLOY_CLI" check-update --json --no-network || exit 1
phase central-schedule bash "$DEPLOY_CLI" schedule status || exit 1
phase central-export bash "$DEPLOY_CLI" export --output "${OUTPUT_DIR}/export.tar.gz" || exit 1

phase uninstall env DEPLOY_ASSUME_YES=1 DEPLOY_DELETE_DATA=1 \
  bash "$DEPLOY_CLI" "$DRILL_APP" uninstall || exit 1
CREATED_INSTALL=0
PHASE_CLEANED=1
if [[ -e "/etc/systemd/system/${DRILL_APP}.service" ]]; then
  record unit-removed fail "unit still present after uninstall"
  exit 1
fi
record unit-removed ok "unit removed"

phase final-doctor bash "$DEPLOY_CLI" doctor security --json || exit 1

echo "=== production-drill: complete; results in ${RESULTS_MD} ==="
