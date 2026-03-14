#!/usr/bin/env bash
# scripts/lint/shellcheck.sh
# Runs shellcheck against all bash scripts in the repository.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

function main() {
  exec 5>&1
  validate_env
  lint
}

function validate_env() {
  log 'Checking for shellcheck...'
  if ! command -v shellcheck > /dev/null 2>&1; then
    log '❌ shellcheck not found; install via: apt-get install shellcheck / brew install shellcheck'
    exit 1
  fi
  log '✅ shellcheck available'
}

function lint() {
  log 'Running shellcheck on all scripts...'
  local rc
  rc=0
  find scripts -name '*.sh' -print0 \
    | xargs -0 shellcheck --shell=bash --severity=warning \
    || rc="${?}"
  if [ "${rc}" -ne 0 ]; then
    log "❌ shellcheck failed (exit ${rc})"
    exit "${rc}"
  fi
  log '✅ All scripts passed shellcheck'
}

function log() {
  local msg
  msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a '/tmp/shellcheck.log' >&5
}

main "${@:-}"
