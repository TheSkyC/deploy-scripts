#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS_PATH=".githooks"

usage() {
  cat >&2 <<'EOF'
Usage: bash tools/install-git-hooks.sh [--check|--force]

Install the repository's versioned Git hooks for this checkout.
  --check  Exit successfully only when core.hooksPath is .githooks.
  --force  Replace an existing core.hooksPath for this checkout.
EOF
}

main() {
  local mode="install" current_path
  case "${1:-}" in
    '') ;;
    --check) mode="check" ;;
    --force) mode="force" ;;
    --help|-h) usage; return 0 ;;
    *) usage; return 2 ;;
  esac

  git -C "$ROOT_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
    echo "install-git-hooks: ${ROOT_DIR} is not a Git worktree" >&2
    return 1
  }

  current_path="$(git -C "$ROOT_DIR" config --get core.hooksPath || true)"
  if [[ "$mode" == "check" ]]; then
    if [[ "$current_path" == "$HOOKS_PATH" ]]; then
      echo "Git hooks are enabled from ${HOOKS_PATH}."
      return 0
    fi
    echo "Git hooks are not enabled; run: bash tools/install-git-hooks.sh" >&2
    return 1
  fi

  if [[ -n "$current_path" && "$current_path" != "$HOOKS_PATH" && "$mode" != "force" ]]; then
    cat >&2 <<EOF
install-git-hooks: refusing to replace existing core.hooksPath: ${current_path}
Use --force only after confirming that replacing the current hook path is intended.
EOF
    return 1
  fi

  git -C "$ROOT_DIR" config --local core.hooksPath "$HOOKS_PATH"
  echo "Enabled repository Git hooks from ${HOOKS_PATH}."
}

main "$@"
