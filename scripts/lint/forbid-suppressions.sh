#!/usr/bin/env bash
# scripts/lint/forbid-suppressions.sh
# Fail if any tracked file contains a lint-suppression directive (shellcheck
# disable, markdownlint disable/capture). Per feedback_never_bypass_lint:
# refactor code so the warning no longer applies; never silence the linter.
#
# Allowed (NOT a disable — just a hint that tells the linter where to look):
#   # shellcheck source=<path>     (e.g., source=./lib/common.sh)
#
# Excluded from the scan:
#   - this script (would self-match on the FORBIDDEN_PATTERNS strings)
#   - .standards/ submodule (canonical, governed separately)
#   - documentation that describes the rule (memory/, docs/)

set -o nounset
set -o errexit
set -o pipefail

declare REPO_ROOT
REPO_ROOT="$(git rev-parse --show-toplevel)"

declare SELF_REL
SELF_REL="$(realpath "${BASH_SOURCE[0]}")"
SELF_REL="${SELF_REL#"${REPO_ROOT}"/}"

declare -ar FORBIDDEN_PATTERNS=(
  'shellcheck +disable='
  '<!-- *markdownlint-disable'
  '<!-- *markdownlint-capture'
)

function main() {
  exec 5>&1
  local rc=0
  for pat in "${FORBIDDEN_PATTERNS[@]}"; do
    if scan_pattern "${pat}"; then
      :
    else
      rc=1
    fi
  done
  if [ "${rc}" -eq 0 ]; then
    log '✅ no lint-suppression directives in tracked files'
  fi
  exit "${rc}"
}

function scan_pattern() {
  local -r pat="${1}"
  local matches
  matches="$( git -C "${REPO_ROOT}" ls-files \
              | git_grep_filter "${pat}" \
              || true )"
  if [ -z "${matches}" ]; then
    return 0
  fi
  log "❌ forbidden suppression matches '${pat}':"
  printf '%s\n' "${matches}" | sed 's/^/   /' >&5
  log '   → refactor to fix the lint issue at the source (feedback_never_bypass_lint)'
  return 1
}

# Filter tracked file list to those that actually match the pattern, excluding
# this script and any path under .standards/ (canonical) or memory/ (docs).
function git_grep_filter() {
  local -r pat="${1}"
  local f
  while IFS= read -r f; do
    [ -z "${f}" ] && continue
    [ "${f}" = "${SELF_REL}" ] && continue
    case "${f}" in
      .standards/*) continue ;;
    esac
    # Match the pattern; use grep -lE on the single file.
    if grep -lE "${pat}" "${REPO_ROOT}/${f}" >/dev/null 2>&1; then
      printf '%s\n' "${f}"
    fi
  done
}

function log() {
  printf '%s\n' "${1:-}" >&5
}

main "${@:-}"
