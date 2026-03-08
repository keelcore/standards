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

function main() {
  exec 5>&1
  log 'Formatting repository...'
  format_json
  log '✅ Formatting complete'
}

function format_json() {
  log 'Formatting JSON files...'
  if command -v node > /dev/null 2>&1; then
    find . -name '*.json' \
      -not -path './node_modules/*' \
      -not -path './.git/*' \
      -exec node -e "
        const fs = require('fs');
        const f = process.argv[1];
        const obj = JSON.parse(fs.readFileSync(f,'utf8'));
        fs.writeFileSync(f, JSON.stringify(obj, null, 2) + '\n');
      " {} \;
    log '✅ JSON formatted'
  else
    log 'node not available; skipping JSON formatting'
  fi
}

function log() {
  local msg
  msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a '/tmp/format.log' >&5
}

main "${@:-}"