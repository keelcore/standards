#!/usr/bin/env bash
# scripts/release/pypi-publish.sh
# Builds the keelcore-standards wheel and sdist for PyPI.
# Version is derived from the git tag (GITHUB_REF_NAME or INPUT_TAG).
# Upload is handled by pypa/gh-action-pypi-publish (Trusted Publisher / OIDC)
# in CI, or manually via twine locally.

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
  local tag version
  tag="$(resolve_tag)"
  version="${tag#v}"
  log "Building keelcore-standards==${version}..."
  hatch version "${version}"
  build
}

function resolve_tag() {
  if [ -n "${GITHUB_REF_NAME:-}" ]; then
    printf '%s' "${GITHUB_REF_NAME}"
  elif [ -n "${INPUT_TAG:-}" ]; then
    printf '%s' "${INPUT_TAG}"
  else
    log '❌ Cannot resolve tag: GITHUB_REF_NAME and INPUT_TAG are both unset'
    exit 1
  fi
}

function validate_env() {
  log 'Validating environment...'
  if [ ! -f 'pyproject.toml' ]; then
    log '❌ pyproject.toml not found; run from the repository root'
    exit 1
  fi
  log '✅ Environment valid'
}

function install_tooling() {
  log 'Installing hatch...'
  if [ -n "${CI:-}" ]; then
    pip install --quiet hatch
  else
    command -v hatch >/dev/null 2>&1 || pipx install hatch
  fi
  log '✅ Tooling installed'
}

function build() {
  log 'Building wheel and sdist...'
  hatch build
  log '✅ Artifacts built'
}

function log() {
  local msg
  msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a '/tmp/pypi-publish.log' >&5
}

main "${@:-}"
