#!/usr/bin/env bash
# integration-test.local.sh
# keelcore/standards integration tests, delegated to by the canonical
# scripts/integration-test.sh (`make integration-test`). Runs every BATS suite
# under tests/. Project-owned, never canonical: verify-canonical and
# governance-refresh skip *.local.sh, so consumers never receive this file.

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
  log '🧪 Running BATS suites in tests/'
  bats --recursive tests
  log '✅ BATS suites passed'
}

function log() {
  local -r msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a '/tmp/integration-test-local.log' >&5
}

function validate_args() {
  if [ "${#}" -gt 1 ] || [ -n "${1:-}" ]; then
    log '❌ Error: Unexpected argument'
    exit 1
  fi
}

main "${@:-}"
