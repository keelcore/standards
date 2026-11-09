#!/usr/bin/env bash
# scripts/release/publish-npm.sh
# Publishes @keelcore/standards to the npm registry.
# Version is derived from the git tag (release_tag, scripts/lib/release-tag.sh: INPUT_TAG, else the pushed tag).
# Uses OIDC trusted publishing — no token required in CI.
# Project hook: publish-npm.local.sh runs first, when present, with this script's arguments
# (scripts/lib/local-hook.sh: the same path, in the repository this runs in).

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

# shellcheck source=../lib/local-hook.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/local-hook.sh"
# shellcheck source=../lib/release-tag.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/release-tag.sh"


function main() {
  exec 5>&1
  run_local_hook "${BASH_SOURCE[0]}" "${@:-}"
  validate_env
  local tag version
  tag="$(release_tag)"
  version="${tag#v}"
  log "Publishing @keelcore/standards@${version}..."
  npm version "${version}" --no-git-tag-version
  # Publish the packed tarball itself, kept in target/dist/ for the release's SBOM, checksums
  # and signature.
  mkdir -p target/dist
  local tarball
  tarball="$(npm pack --pack-destination target/dist | tail -1)"
  npm publish "target/dist/${tarball}" --access public
  log '✅ Published to npm'
}

function validate_env() {
  log 'Validating environment...'
  if [ ! -f 'package.json' ]; then
    log '❌ package.json not found; run from the repository root'
    exit 1
  fi
  log '✅ Environment valid'
}

function log() {
  local msg
  msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a '/tmp/npm-publish.log' >&5
}

main "${@:-}"
