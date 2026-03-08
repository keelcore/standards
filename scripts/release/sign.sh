#!/usr/bin/env bash
# scripts/release/sign.sh
# Signs release artifacts using Sigstore/cosign keyless signing.
# Produces .sig and .bundle files alongside each artifact.
#
# Usage: scripts/release/sign.sh <artifact-path> [<artifact-path> ...]
#
# Requires:
#   - cosign on PATH (installed in CI via the cosign installer action)
#   - OIDC identity token available (GitHub Actions: id-token: write permission)

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

function main() {
  exec 5>&1
  validate_env "${@:-}"
  sign_artifacts "${@:-}"
  generate_checksums "${@:-}"
}

function validate_env() {
  log 'Validating environment...'
  if ! command -v cosign > /dev/null 2>&1; then
    log '❌ cosign not found on PATH'
    exit 1
  fi
  if [ "${#}" -eq 0 ]; then
    log '❌ No artifact paths provided'
    log '   Usage: sign.sh <artifact> [<artifact> ...]'
    exit 1
  fi
  log '✅ Environment valid'
}

function sign_artifacts() {
  local artifact
  for artifact in "${@}"; do
    if [ ! -f "${artifact}" ]; then
      log "❌ Artifact not found: ${artifact}"
      exit 1
    fi
    sign_artifact "${artifact}"
  done
}

function sign_artifact() {
  local -r artifact="${1}"
  log "Signing ${artifact}..."
  cosign sign-blob \
    --yes \
    --bundle "${artifact}.bundle" \
    "${artifact}"
  log "✅ Signed: ${artifact}.bundle"
}

function generate_checksums() {
  log 'Generating SHA256SUMS...'
  local artifact
  for artifact in "${@}"; do
    sha256sum "${artifact}"
  done > SHA256SUMS
  log '✅ SHA256SUMS written'
  log 'Signing SHA256SUMS...'
  cosign sign-blob \
    --yes \
    --bundle 'SHA256SUMS.bundle' \
    SHA256SUMS
  log '✅ SHA256SUMS.bundle written'
}

function log() {
  local msg
  msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a '/tmp/sign.log' >&5
}

main "${@:-}"