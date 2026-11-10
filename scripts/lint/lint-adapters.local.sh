#!/usr/bin/env bash
# lint-adapters.local.sh
# keelcore/standards only: check that the Claude adapter (adapters/claude/CLAUDE.md), which every consumer's
# CLAUDE.md links to, links every governance/**/*.md document, and links no governance file that does not
# exist. Project-owned, never canonical: verify-canonical and refresh-governance skip *.local.sh.
# Exits 1 naming each unlinked document and each dangling link.
#
# Run locally:  make lint-adapters-local

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

readonly ADAPTER='adapters/claude/CLAUDE.md'

function main() {
  exec 5>&1
  validate_args "${@:-}"
  check_adapter
}

function log() {
  local -r msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a '/tmp/lint_adapters.log' >&5
}

function validate_args() {
  if [ "${#}" -gt 1 ] || [ -n "${1:-}" ]; then
    log '❌ Error: Unexpected argument'
    exit 1
  fi
}

# governance_docs: every governance/**/*.md, sorted.
function governance_docs() {
  find governance -type f -name '*.md' | sort
}

# linked_docs: every governance file the adapter links, as a repository path, sorted.
function linked_docs() {
  grep -oE '\]\(\.standards/governance/[^)]+\)' "${ADAPTER}" | sed -e 's/^](\.standards\///' -e 's/)$//' | sort -u
}

function check_adapter() {
  local failed=0 f
  while IFS= read -r f; do
    log "❌ ${ADAPTER} does not link ${f}"
    failed=1
  done < <(comm -23 <(governance_docs) <(linked_docs))
  while IFS= read -r f; do
    log "❌ ${ADAPTER} links ${f}, which does not exist"
    failed=1
  done < <(comm -13 <(governance_docs) <(linked_docs))
  if [ "${failed}" -ne 0 ]; then
    log "Link each governance document from ${ADAPTER}: See [.standards/governance/X.md](.standards/governance/X.md)."
    exit 1
  fi
  log '✅ Adapter links every governance document'
}

main "${@:-}"
