#!/usr/bin/env bash
# hook.sh
# Test double for scripts/release/create-release.local.sh, installed into
# throwaway repos by tests/create-release.bats. Prints HOOK_STDOUT to stdout
# (backslash escapes expanded), HOOK_STDERR to stderr, then exits HOOK_EXIT.
# Records its arguments in HOOK_ARGS_FILE when set.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare -rx HOOK_STDOUT="${HOOK_STDOUT:-patch\n}"
declare -rx HOOK_STDERR="${HOOK_STDERR:-}"
declare -rx HOOK_EXIT="${HOOK_EXIT:-0}"
declare -rx HOOK_ARGS_FILE="${HOOK_ARGS_FILE:-}"

function main() {
  exec 5>&2
  if [ -n "${HOOK_ARGS_FILE}" ]; then
    printf '%s\n' "${@:-}" > "${HOOK_ARGS_FILE}"
  fi
  printf '%b' "${HOOK_STDOUT}"
  if [ -n "${HOOK_STDERR}" ]; then
    printf '%s\n' "${HOOK_STDERR}" >&5
  fi
  exit "${HOOK_EXIT}"
}

main "${@:-}"
