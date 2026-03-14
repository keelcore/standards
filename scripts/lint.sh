1#!/usr/bin/env bash
# scripts/lint.sh
# Top-level lint entry point. Runs all linters for this repository.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

function main() {
  exec 5>&1
  log 'Running all linters...'
  run_markdown_lint
  run_shellcheck
  run_adr_check
  run_governance_check
  run_rfc_check
  log '✅ All linters passed'
}

function run_markdown_lint() {
  log 'Running Markdown lint...'
  bash scripts/lint/markdown.sh
}

function run_shellcheck() {
  log 'Running shellcheck...'
  bash scripts/lint/shellcheck.sh
}

function run_adr_check() {
  log 'Checking ADR metadata...'
  bash scripts/check/adr-metadata.sh
}

function run_governance_check() {
  log 'Checking governance metadata...'
  bash scripts/check/governance-metadata.sh
}

function run_rfc_check() {
  log 'Checking RFC metadata...'
  bash scripts/check/rfc-metadata.sh
}

function log() {
  local msg
  msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a '/tmp/lint.log' >&5
}

main "${@:-}"
