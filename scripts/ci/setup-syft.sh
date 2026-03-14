#!/usr/bin/env bash
# setup-syft.sh
# Install syft SBOM tool on a CI runner.
# No-op if syft is already present.
#
# Installs the latest syft release to /usr/local/bin via the official installer.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

function main() {
  exec 5>&1
  validate_args "${@:-}"
  install_syft
}

function log() {
  local -r msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a '/tmp/setup_syft.log' >&5
}

function validate_args() {
  if [ "${#}" -gt 1 ] || [ -n "${1:-}" ]; then
    log '❌ Error: Unexpected argument'
    exit 1
  fi
}

function install_syft() {
  if command -v syft > /dev/null 2>&1; then
    log "✅ syft already installed ($(syft version 2>/dev/null | head -1 || echo 'unknown version'))"
    return 0
  fi
  log '⚓ Installing syft...'
  curl -sSfL https://raw.githubusercontent.com/anchore/syft/main/install.sh | sh -s -- -b /usr/local/bin
  log '✅ syft installed'
}

main "${@:-}"
