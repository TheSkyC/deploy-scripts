#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BASH_BIN="${BASH_BIN:-bash}"

cd "$ROOT_DIR"

check_shell_syntax() {
  local file
  while IFS= read -r file; do
    "$BASH_BIN" -n "$file"
  done < <(find apps bin impl lib tools -name '*.sh' -type f | sort)
}

check_release_syntax() {
  local file
  while IFS= read -r file; do
    "$BASH_BIN" -n "$file"
  done < <(find dist -maxdepth 1 -name 'install_*.sh' -type f | sort)
}

expect_failure_output() {
  local lang="$1"
  local script="$2"
  local expected="$3"
  local output status

  set +e
  output="$(DEPLOY_LANG="$lang" "$BASH_BIN" "$script" not-a-command 2>&1)"
  status=$?
  set -e

  [[ "$status" -ne 0 ]] || {
    echo "Expected ${script} to reject an invalid action" >&2
    return 1
  }
  [[ "$output" == *"$expected"* ]] || {
    echo "Expected ${script} output to contain: ${expected}" >&2
    echo "$output" >&2
    return 1
  }
}

check_localized_dispatch() {
  expect_failure_output en install_newapi.sh "Invalid choice"
  expect_failure_output zh install_newapi.sh "无效选项"
  expect_failure_output en dist/install_newapi.sh "Invalid choice"
  expect_failure_output zh dist/install_newapi.sh "无效选项"
}

check_no_release_temp_files() {
  if find dist -maxdepth 1 -name '*_impl.sh' -type f | grep -q .; then
    echo "Unexpected bundled implementation file in dist/" >&2
    find dist -maxdepth 1 -name '*_impl.sh' -type f >&2
    return 1
  fi
}

main() {
  check_shell_syntax
  DEPLOY_BUILD_COMMIT=verified SOURCE_DATE_EPOCH=0 "$BASH_BIN" tools/build-release.sh all >/dev/null
  check_release_syntax
  check_localized_dispatch
  check_no_release_temp_files
  echo "Verification passed"
}

main "$@"
