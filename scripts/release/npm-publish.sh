#!/usr/bin/env bash
# scripts/release/npm-publish.sh
# Publishes @keelcore/standards to the npm registry.
# Requires NODE_AUTH_TOKEN to be set in the environment.

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
  publish
}

function validate_env() {
  log 'Validating environment...'
  if [ -z "${NODE_AUTH_TOKEN:-}" ]; then
    log '❌ NODE_AUTH_TOKEN is not set'
    exit 1
  fi
  if [ ! -f 'package.json' ]; then
    log '❌ package.json not found; run from the repository root'
    exit 1
  fi
  log '✅ Environment valid'
}

function publish() {
  log 'Publishing to npm...'
  npm publish --access public
  log '✅ Published to npm'
}

function log() {
  local msg
  msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a '/tmp/npm-publish.log' >&5
}

main "${@:-}"