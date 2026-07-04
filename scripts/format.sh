#!/usr/bin/env bash
# scripts/format.sh
# Top-level format entry point. Runs all formatters for this repository.
# Markdown files are linted but not auto-formatted; fix violations manually.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

# shellcheck source=lib/node-path.sh
. "$(dirname "${BASH_SOURCE[0]}")/lib/node-path.sh"

function main() {
  exec 5>&1
  log 'Formatting repository...'
  format_json
  log '✅ Formatting complete'
}

function format_json() {
  log 'Formatting JSON files...'
  if ! node_path_ensure; then
    log 'node not found on PATH or at standard install locations; skipping JSON formatting'
    return 0
  fi
  # Scope to superproject-tracked JSON via `git ls-files` (like the other lint
  # scripts). This skips git submodules (e.g. vendors/, .standards/) and
  # gitignored trees (node_modules/), which legitimately contain JSONC configs
  # (tsconfig, pyright, svelte) and deliberately-invalid fixtures the strict
  # JSON.parse formatter cannot read. A file that fails to parse is reported and
  # skipped, never fatal — one unparseable file must not abort the format pass
  # (and GNU find's -exec would otherwise fail the whole run under errexit).
  local json_file
  while IFS= read -r json_file; do
    [ -f "${json_file}" ] || continue
    if ! node -e "
      const fs = require('fs');
      const f = process.argv[1];
      const obj = JSON.parse(fs.readFileSync(f,'utf8'));
      fs.writeFileSync(f, JSON.stringify(obj, null, 2) + '\n');
    " "${json_file}" 2>/dev/null; then
      log "  ⚠️  skipped (not plain JSON): ${json_file}"
    fi
  done < <(git ls-files '*.json')
  log "✅ JSON formatted (node: $(command -v node))"
}

function log() {
  local msg
  msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a '/tmp/format.log' >&5
}

main "${@:-}"
