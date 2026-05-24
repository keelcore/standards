#!/usr/bin/env bash
# bootstrap-standards.sh
# Reproduce every file that originates from .standards — AI adapters,
# canonical scripts, and repo config — so a clean clone reaches the same
# state with one command.  No file content is embedded inline.
#
# Safe to re-run. Non-greenfield handling:
#   - If CLAUDE.md exists and is NOT the canonical symlink, move it to
#     .local-claude.md so its content survives, then symlink the adapter.
#     If .local-claude.md already exists, warn and leave CLAUDE.md alone.
#   - Existing scripts at canonical paths are overwritten by cp; project-
#     specific scripts living alongside them (e.g. fetch-data.sh) are not
#     touched.
#   - The Makefile is NEVER overwritten; canonical targets must be MERGED
#     into existing project Makefiles by the operator after bootstrap.
#
# Run locally:  bash .standards/scripts/bootstrap-standards.sh

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
  init_submodule
  copy_canonical_scripts
  copy_markdownlint_config
  chmod_scripts
  install_tools
  create_adapters
  log '✅ Bootstrap complete'
}

function log() {
  local -r msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a '/tmp/bootstrap_standards.log' >&5
}

function validate_args() {
  if [ "${#}" -gt 0 ] && [ -n "${1:-}" ]; then
    log '❌ Usage: bootstrap-standards.sh'
    exit 1
  fi
}

function init_submodule() {
  log '📦 Initializing .standards submodule...'
  git submodule add git@github.com:keelcore/standards .standards || true
  git submodule update --init --recursive
}

function install_tools() {
  log '🔧 Installing tools...'
  bash scripts/ci/setup-shellcheck.sh
  bash scripts/ci/setup-markdownlint.sh
  bash scripts/ci/setup-syft.sh
}

function create_claude_adapter() {
  local -r canonical_target='.standards/adapters/claude/CLAUDE.md'
  if [ -L CLAUDE.md ]; then
    log '  ✅ CLAUDE.md already a symlink; refreshing target'
    ln -sf "${canonical_target}" CLAUDE.md
    return 0
  fi
  if [ -f CLAUDE.md ]; then
    if [ -f .local-claude.md ]; then
      log '  ⚠️  CLAUDE.md and .local-claude.md both exist; leaving CLAUDE.md'
      log '     untouched. Reconcile manually before re-running bootstrap.'
      return 0
    fi
    log '  ↪ Existing CLAUDE.md found; moving to .local-claude.md'
    log '    (canonical adapter @-includes .local-claude.md, so content survives)'
    mv CLAUDE.md .local-claude.md
  fi
  ln -sf "${canonical_target}" CLAUDE.md
  log '  ✅ CLAUDE.md → .standards/adapters/claude/CLAUDE.md'
}

function create_copilot_adapter() {
  mkdir -p .github
  ln -sf ../.standards/adapters/copilot/copilot-instructions.md \
    .github/copilot-instructions.md
  log '  ✅ .github/copilot-instructions.md symlinked'
}

function create_cursor_rules() {
  mkdir -p .cursor/rules
  local f
  for f in .standards/adapters/cursor/*.mdc; do
    local dest
    dest=".cursor/rules/$(basename "${f}")"
    sed 's|@../../governance/|@../../.standards/governance/|g' "${f}" > "${dest}"
  done
  log '  ✅ .cursor/rules/*.mdc copied and path-adjusted'
}

function create_adapters() {
  log '🔗 Creating AI adapters...'
  create_claude_adapter
  create_copilot_adapter
  create_cursor_rules
}

function copy_ci_scripts() {
  local -r src='.standards/scripts/ci'
  local -r dst='scripts/ci'
  cp "${src}/audit-make-targets.sh"        "${dst}/audit-make-targets.sh"
  cp "${src}/dco-check.sh"                 "${dst}/dco-check.sh"
  cp "${src}/pr-policy.sh"                 "${dst}/pr-policy.sh"
  cp "${src}/secret-scan.sh"               "${dst}/secret-scan.sh"
  cp "${src}/setup-markdownlint.sh"        "${dst}/setup-markdownlint.sh"
  cp "${src}/setup-shellcheck.sh"          "${dst}/setup-shellcheck.sh"
  cp "${src}/setup-syft.sh"                "${dst}/setup-syft.sh"
  cp "${src}/verify-canonical-scripts.sh"  "${dst}/verify-canonical-scripts.sh"
}

function copy_check_scripts() {
  local -r src='.standards/scripts/check'
  local -r dst='scripts/check'
  cp "${src}/adr-metadata.sh"         "${dst}/adr-metadata.sh"
  cp "${src}/governance-metadata.sh"  "${dst}/governance-metadata.sh"
  cp "${src}/rfc-metadata.sh"         "${dst}/rfc-metadata.sh"
}

function copy_support_scripts() {
  local -r src='.standards/scripts'
  cp "${src}/format.sh"               scripts/format.sh
  cp "${src}/lint.sh"                 scripts/lint.sh
  cp "${src}/git_precommit.sh"        scripts/git_precommit.sh
  cp "${src}/check-legal-drift.sh"    scripts/check-legal-drift.sh
  cp "${src}/lib/paths.sh"            scripts/lib/paths.sh
  cp "${src}/lint/markdown.sh"        scripts/lint/markdown.sh
  cp "${src}/lint/newlines.sh"        scripts/lint/newlines.sh
  cp "${src}/lint/shellcheck.sh"      scripts/lint/shellcheck.sh
  cp "${src}/test/coverage-delta.sh"  scripts/test/coverage-delta.sh
  cp "${src}/test/coverage.sh"        scripts/test/coverage.sh
}

function copy_canonical_scripts() {
  log '📋 Copying canonical scripts...'
  mkdir -p scripts/ci scripts/check scripts/lib scripts/lint scripts/test
  copy_ci_scripts
  copy_check_scripts
  copy_support_scripts
}

function copy_markdownlint_config() {
  log '📄 Copying markdownlint config...'
  cp .standards/.markdownlint.json .markdownlint.json
}

function chmod_scripts() {
  log '🔒 Setting script permissions...'
  find scripts -name '*.sh' -exec chmod +x '{}' ';'
}

main "${@:-}"
