#!/usr/bin/env bash
# scripts/lint/markdown.sh
# Lints all GIT-TRACKED Markdown files using markdownlint-cli2.
# Tracked-files scope means gitignored content (.scratch/, build outputs,
# vendored caches) is automatically excluded — it isn't part of the repo.
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
  local -a files=()
  local f
  while IFS= read -r f; do
    files+=("${f}")
  done < <(git ls-files '*.md')
  if [ "${#files[@]}" -eq 0 ]; then
    log 'ℹ️  No tracked .md files to lint'
    return 0
  fi
  if command -v markdownlint-cli2 > /dev/null 2>&1; then
    markdownlint-cli2 "${files[@]}"
  else
    npx --yes markdownlint-cli2 "${files[@]}"
  fi
}

function log() {
  local msg
  msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a '/tmp/markdown-lint.log' >&5
}

main "${@:-}"
