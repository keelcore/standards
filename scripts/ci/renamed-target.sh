#!/usr/bin/env bash
# scripts/ci/renamed-target.sh NEW
# A renamed make target: says what replaced it, and fails, so a caller is fixed rather than silently
# running the wrong thing.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

function main() {
  exec 5>&1
  validate_args "${@:-}"
  log "❌ This target was renamed: run make ${1}"
  exit 1
}

function log() {
  local -r msg="${1:-}"
  printf '%s\n' "${msg}" >&5
}

function validate_args() {
  if [ "${#}" -ne 1 ] || [ -z "${1:-}" ]; then
    log '❌ Usage: renamed-target.sh NEW_TARGET'
    exit 1
  fi
}

main "${@:-}"
