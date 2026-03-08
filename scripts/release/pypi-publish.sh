#!/usr/bin/env bash
# scripts/release/pypi-publish.sh
# Builds the keelcore-standards wheel and publishes to PyPI.
# Requires PYPI_TOKEN to be set in the environment.

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
  install_tooling
  build
  publish
}

function validate_env() {
  log 'Validating environment...'
  if [ -z "${PYPI_TOKEN:-}" ]; then
    log '❌ PYPI_TOKEN is not set'
    exit 1
  fi
  if [ ! -f 'pyproject.toml' ]; then
    log '❌ pyproject.toml not found; run from the repository root'
    exit 1
  fi
  log '✅ Environment valid'
}

function install_tooling() {
  log 'Installing hatch and twine...'
  pip install --quiet hatch twine
  log '✅ Tooling installed'
}

function build() {
  log 'Building wheel...'
  hatch build
  log '✅ Wheel built'
}

function publish() {
  log 'Publishing to PyPI...'
  # PYPI_TOKEN is passed via environment variable, not as a positional argument,
  # to prevent the secret from appearing in process listings or log output.
  TWINE_USERNAME='__token__' \
  TWINE_PASSWORD="${PYPI_TOKEN}" \
    twine upload --non-interactive dist/*
  log '✅ Published to PyPI'
}

function log() {
  local msg
  msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a '/tmp/pypi-publish.log' >&5
}

main "${@:-}"