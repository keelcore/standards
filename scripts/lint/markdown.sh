#!/usr/bin/env bash
# scripts/lint/markdown.sh
# Lints all Markdown files in the repository using markdownlint-cli2.
# Requires markdownlint-cli2 to be available on PATH (npm install or npx).

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
  log 'Checking for markdownlint-cli2...'
  if ! command -v markdownlint-cli2 > /dev/null 2>&1; then
    if command -v npx > /dev/null 2>&1; then
      log 'markdownlint-cli2 not on PATH; will use npx'
    else
      log '❌ Neither markdownlint-cli2 nor npx found; run: npm install'
      exit 1
    fi
  fi
  log '✅ Tool available'
}

function lint() {
  log 'Linting Markdown files...'
  local rc
  rc=0
  run_linter || rc="${?}"
  if [ "${rc}" -ne 0 ]; then
    log "❌ Markdown lint failed (exit ${rc})"
    exit "${rc}"
  fi
  log '✅ All Markdown files passed'
}

function run_linter() {
  if command -v markdownlint-cli2 > /dev/null 2>&1; then
    markdownlint-cli2 '**/*.md' '#node_modules'
  else
    npx --yes markdownlint-cli2 '**/*.md' '#node_modules'
  fi
}

function log() {
  local msg
  msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a '/tmp/markdown-lint.log' >&5
}

main "${@:-}"
