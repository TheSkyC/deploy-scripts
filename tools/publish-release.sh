#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
REMOTE="${DEPLOY_RELEASE_REMOTE:-origin}"
VERIFY=1
WAIT=0
ALLOW_DIRTY=0
REPLACE_EXISTING=0

usage() {
  cat >&2 <<'USAGE'
Usage: bash tools/publish-release.sh [options] <vX.Y.Z>

Create an annotated version tag and push it to the configured Git remote.
The tag push triggers .github/workflows/release.yml, which verifies the
repository, rebuilds dist/, packages the source, and creates/updates the
GitHub Release idempotently.

Options:
  --remote NAME          Git remote (default: origin)
  --no-verify            Skip local tools/verify.sh release
  --wait                 Wait for the GitHub Actions release workflow
  --allow-dirty          Allow unrelated working-tree changes (not advised)
  --replace-existing     Delete and recreate the local/remote tag explicitly
  -h, --help             Show this help
USAGE
}

fail() {
  printf 'publish-release: %s\n' "$*" >&2
  exit 1
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "required command not found: $1"
}

validate_tag() {
  local tag="$1"
  [[ "$tag" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([.-][0-9A-Za-z.-]+)?$ ]] \
    || fail "invalid release tag '$tag'; expected vX.Y.Z or a semver prerelease"
}

remote_tag_exists() {
  git ls-remote --exit-code --tags "$REMOTE" "refs/tags/$1" "refs/tags/$1^{}" \
    >/dev/null 2>&1
}

check_clean_tree() {
  [[ "$ALLOW_DIRTY" -eq 1 ]] && return 0
  if [[ -n "$(git -C "$ROOT_DIR" status --porcelain)" ]]; then
    fail "working tree is not clean; commit intended changes first or pass --allow-dirty"
  fi
}

wait_for_release_workflow() {
  local tag="$1" run_id="" attempt=0 repo=""
  repo="$(cd "$ROOT_DIR" && gh repo view --json nameWithOwner --jq .nameWithOwner)" \
    || fail "cannot determine GitHub repository for remote $REMOTE"
  printf 'Waiting for GitHub Actions release workflow for %s...\n' "$tag" >&2
  while (( attempt < 30 )); do
    run_id="$(gh run list --workflow release.yml --repo "$repo" --event push --branch "$tag" --limit 1 --json databaseId --jq '.[0].databaseId // empty' 2>/dev/null || true)"
    if [[ -n "$run_id" ]]; then
      gh run watch "$run_id" --exit-status
      printf 'GitHub Actions release workflow completed: %s\n' "$run_id" >&2
      return 0
    fi
    attempt=$((attempt + 1))
    sleep 5
  done
  fail "timed out waiting for the release workflow; inspect GitHub Actions manually"
}

main() {
  local tag="" arg
  while [[ $# -gt 0 ]]; do
    arg="$1"
    case "$arg" in
      --remote)
        [[ $# -ge 2 ]] || fail "--remote requires a value"
        REMOTE="$2"
        shift 2
        ;;
      --no-verify) VERIFY=0; shift ;;
      --wait) WAIT=1; shift ;;
      --allow-dirty) ALLOW_DIRTY=1; shift ;;
      --replace-existing) REPLACE_EXISTING=1; shift ;;
      -h|--help) usage; exit 0 ;;
      --*) fail "unknown option: $arg" ;;
      *)
        [[ -z "$tag" ]] || fail "only one release tag may be supplied"
        tag="$arg"
        shift
        ;;
    esac
  done

  [[ -n "$tag" ]] || { usage; exit 2; }
  validate_tag "$tag"
  require_command git
  require_command gh
  git -C "$ROOT_DIR" rev-parse --show-toplevel >/dev/null 2>&1 \
    || fail "not a Git repository: $ROOT_DIR"
  git -C "$ROOT_DIR" remote get-url "$REMOTE" >/dev/null 2>&1 \
    || fail "Git remote not found: $REMOTE"
  gh auth status >/dev/null 2>&1 || fail "GitHub CLI is not authenticated; run gh auth login"
  check_clean_tree

  if [[ "$VERIFY" -eq 1 ]]; then
    printf 'Running release verification...\n' >&2
    (cd "$ROOT_DIR" && bash tools/verify.sh release)
  fi

  local existing_local=0 existing_remote=0
  git -C "$ROOT_DIR" rev-parse --verify --quiet "refs/tags/$tag" >/dev/null && existing_local=1 || true
  remote_tag_exists "$tag" && existing_remote=1 || true
  if (( (existing_local || existing_remote) && !REPLACE_EXISTING )); then
    fail "tag $tag already exists locally or on $REMOTE; use --replace-existing explicitly"
  fi

  if [[ "$REPLACE_EXISTING" -eq 1 ]]; then
    if (( existing_remote )); then
      printf 'Deleting existing remote tag %s from %s...\n' "$tag" "$REMOTE" >&2
      git -C "$ROOT_DIR" push "$REMOTE" ":refs/tags/$tag"
    fi
    if (( existing_local )); then
      git -C "$ROOT_DIR" tag -d "$tag" >/dev/null
    fi
  fi

  git -C "$ROOT_DIR" tag -a "$tag" -m "release $tag"
  printf 'Pushing tag %s to %s...\n' "$tag" "$REMOTE" >&2
  git -C "$ROOT_DIR" push "$REMOTE" "refs/tags/$tag"
  printf 'Tag pushed. GitHub Actions will create/update the Release automatically.\n' >&2

  if [[ "$WAIT" -eq 1 ]]; then
    wait_for_release_workflow "$tag"
  fi
}

main "$@"
