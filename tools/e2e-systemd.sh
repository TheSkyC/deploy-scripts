#!/usr/bin/env bash
# Real-systemd install rehearsal.
#
# tools/e2e-smoke.sh stubs systemd, so it can only prove which files the install
# flow writes. This harness boots a real systemd as PID 1 in a disposable
# privileged container and runs the shipped release script against it: the unit
# is really enabled and started, nginx validates the generated site, the
# schedule command has to create a real timer, and uninstall must leave neither
# unit nor service behind.
#
# Usage: bash tools/e2e-systemd.sh    (needs docker; Linux or Docker Desktop)
#
# The container is removed on exit, including on failure.
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR" || exit 1

command -v docker >/dev/null 2>&1 || {
  echo "e2e-systemd: docker is required" >&2
  exit 1
}

IMAGE="deploy-e2e-systemd"
CONTAINER="deploy-e2e-systemd-run"

cleanup() {
  docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

ROOT_MOUNT="$ROOT_DIR"
if command -v cygpath >/dev/null 2>&1; then
  ROOT_MOUNT="$(cygpath -w "$ROOT_DIR")"
fi

echo "=== e2e-systemd: building systemd image (cached) ==="
# The build context is empty on purpose: the image is generated from the
# Dockerfile alone, so the repository tree is never sent to the daemon.
docker build -t "$IMAGE" - <"$ROOT_DIR/tools/e2e-systemd/Dockerfile"

cleanup
echo "=== e2e-systemd: booting container ==="
docker run -d --name "$CONTAINER" --privileged --cgroupns=host \
  -v /sys/fs/cgroup:/sys/fs/cgroup:rw \
  --tmpfs /run --tmpfs /run/lock --tmpfs /tmp \
  -v "$ROOT_MOUNT:/repo:ro" \
  "$IMAGE" >/dev/null

system_state=""
for _ in $(seq 1 60); do
  system_state="$(docker exec "$CONTAINER" systemctl is-system-running 2>/dev/null || true)"
  case "$system_state" in
    running|degraded) break ;;
  esac
  sleep 2
done
case "$system_state" in
  running|degraded) ;;
  *)
    echo "e2e-systemd: systemd did not boot (state: ${system_state:-unknown})" >&2
    docker logs "$CONTAINER" >&2 || true
    exit 1
    ;;
esac
echo "=== e2e-systemd: systemd state: ${system_state} ==="

docker exec -i "$CONTAINER" bash -s <"$ROOT_DIR/tools/e2e-systemd/harness.sh"
