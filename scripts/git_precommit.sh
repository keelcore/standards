#!/usr/bin/env bash
# scripts/git_precommit.sh
# Pre-commit hook entry point. Runs format then lint against staged changes.
# Install: ln -sf ../../scripts/git_precommit.sh .git/hooks/pre-commit

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

function main() {
  exec 5>&1
  log 'Pre-commit: format + lint'
  bash scripts/format.sh
  bash scripts/lint.sh
  log '✅ Pre-commit checks passed'
}

function log() {
  local msg
  msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a '/tmp/git-precommit.log' >&5
}

main "${@:-}"
