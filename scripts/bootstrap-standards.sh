#!/usr/bin/env bash
# bootstrap-standards.sh
# Reproduce every file that originates from .standards — AI adapters,
# canonical scripts, and repo config — so a clean clone reaches the same
# state with one command.  No file content is embedded inline.
#
# Run locally:  bash scripts/bootstrap-standards.sh

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
  install_tools
  create_adapters
  copy_canonical_scripts
  copy_markdownlint_config
  chmod_scripts
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
  ln -sf .standards/adapters/claude/CLAUDE.md CLAUDE.md
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
  cp "${src}/audit-make-targets.sh"  "${dst}/audit-make-targets.sh"
  cp "${src}/dco-check.sh"           "${dst}/dco-check.sh"
  cp "${src}/pr-policy.sh"           "${dst}/pr-policy.sh"
  cp "${src}/secret-scan.sh"         "${dst}/secret-scan.sh"
  cp "${src}/setup-markdownlint.sh"  "${dst}/setup-markdownlint.sh"
  cp "${src}/setup-shellcheck.sh"    "${dst}/setup-shellcheck.sh"
  cp "${src}/setup-syft.sh"          "${dst}/setup-syft.sh"
}

function copy_support_scripts() {
  local -r src='.standards/scripts'
  cp "${src}/format.sh"               scripts/format.sh
  cp "${src}/git_precommit.sh"        scripts/git_precommit.sh
  cp "${src}/lib/paths.sh"            scripts/lib/paths.sh
  cp "${src}/lint/md.sh"              scripts/lint/md.sh
  cp "${src}/lint/newlines.sh"        scripts/lint/newlines.sh
  cp "${src}/lint/shellcheck.sh"      scripts/lint/shellcheck.sh
  cp "${src}/test/coverage-delta.sh"  scripts/test/coverage-delta.sh
  cp "${src}/test/coverage.sh"        scripts/test/coverage.sh
}

function copy_canonical_scripts() {
  log '📋 Copying canonical scripts...'
  mkdir -p scripts/ci scripts/lib scripts/lint scripts/test
  copy_ci_scripts
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
