#!/usr/bin/env bash
# governance-refresh.sh
# Reconciles a consumer repo with its `.standards` canonical source of truth.
#
# Two reconciliation passes:
#
#   1. Canonical-script sync: walks .standards/scripts/ (excluding standards-
#      only paths: bootstrap-standards.sh, release/, verify/), copies any
#      missing or content-divergent script into the consumer's matching path.
#      `.standards` always wins — consumer hand-edits are overwritten on
#      every refresh.
#
#   2. Makefile target injection: for each canonical script now present in
#      the consumer's scripts/, if .standards/templates/Makefile defines a
#      target whose recipe invokes that script AND consumer Makefile has no
#      such target, lift the target block from templates/Makefile and append
#      to consumer Makefile under a marker comment.
#
# Idempotent: re-running converges; second run produces no diff.
#
# Usage:
#   bash governance-refresh.sh [--dry-run]
#
#   --dry-run : compute and report pending changes; touch no files; exit 1
#               if any change is pending, exit 0 if nothing pending.
#
# Env overrides (testing only — production reads paths from git):
#   GOVREFRESH_STANDARDS_ROOT  defaults to ${REPO_ROOT}/.standards
#   GOVREFRESH_REPO_ROOT       defaults to `git rev-parse --show-toplevel`

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

declare REPO_ROOT
REPO_ROOT="${GOVREFRESH_REPO_ROOT:-$(git rev-parse --show-toplevel)}"
declare -r REPO_ROOT

declare STANDARDS_ROOT
STANDARDS_ROOT="${GOVREFRESH_STANDARDS_ROOT:-${REPO_ROOT}/.standards}"
declare -r STANDARDS_ROOT

declare -r TEMPLATES_MAKEFILE="${STANDARDS_ROOT}/templates/Makefile"
declare -r CONSUMER_MAKEFILE="${REPO_ROOT}/Makefile"

declare DRY_RUN=0

function main() {
  exec 5>&1
  parse_args "${@:-}"
  validate_env
  log "🔄 governance-refresh: REPO_ROOT=${REPO_ROOT}"

  local script_changes target_injections
  script_changes="$(compute_script_changes)"
  target_injections="$(compute_target_injections)"

  report_changes "${script_changes}" "${target_injections}"

  if [ "${DRY_RUN}" -eq 1 ]; then
    if [ -n "${script_changes}" ] || [ -n "${target_injections}" ]; then
      log "⚠️  dry-run: changes pending. Run 'make governance-refresh' to apply."
      exit 1
    fi
    log "✅ dry-run: nothing to refresh"
    exit 0
  fi

  apply_script_changes "${script_changes}"
  apply_target_injections "${target_injections}"
  log "✅ governance-refresh complete"
}

function parse_args() {
  local arg
  for arg in "${@:-}"; do
    case "${arg:-}" in
      ''|--) ;;
      --dry-run) DRY_RUN=1 ;;
      *)
        log "❌ unknown argument: ${arg}"
        exit 2
        ;;
    esac
  done
}

function validate_env() {
  if [ ! -d "${STANDARDS_ROOT}/scripts" ]; then
    log "❌ STANDARDS_ROOT missing scripts/ dir: ${STANDARDS_ROOT}"
    exit 2
  fi
  if [ ! -f "${TEMPLATES_MAKEFILE}" ]; then
    log "❌ STANDARDS_ROOT missing templates/Makefile: ${TEMPLATES_MAKEFILE}"
    exit 2
  fi
  if [ ! -f "${CONSUMER_MAKEFILE}" ]; then
    log "❌ REPO_ROOT missing Makefile: ${CONSUMER_MAKEFILE}"
    exit 2
  fi
}

# List shipping canonical scripts as paths relative to ${STANDARDS_ROOT}.
# Excludes standards-only paths and the refresh script itself.
#   - Top-level standards-only files (exact match): bootstrap-standards.sh,
#     governance-refresh.sh.
#   - Standards-only directory trees (prefix match): scripts/release/,
#     scripts/verify/.
function canonical_scripts() {
  find "${STANDARDS_ROOT}/scripts" -name '*.sh' -type f \
    | sed "s|^${STANDARDS_ROOT}/||" \
    | grep -v -E '^scripts/(bootstrap-standards|governance-refresh)\.sh$' \
    | grep -v -E '^scripts/(release|verify)/' \
    | sort
}

# Emit pending script changes as lines of the form:
#   NEW <rel-path>
#   MOD <rel-path>
# (no output when consumer already matches .standards)
function compute_script_changes() {
  local rel src_sum dst_sum
  while IFS= read -r rel; do
    [ -z "${rel}" ] && continue
    if [ ! -f "${REPO_ROOT}/${rel}" ]; then
      printf 'NEW %s\n' "${rel}"
      continue
    fi
    src_sum="$(sha256sum "${STANDARDS_ROOT}/${rel}" | awk '{print $1}')"
    dst_sum="$(sha256sum "${REPO_ROOT}/${rel}" | awk '{print $1}')"
    if [ "${src_sum}" != "${dst_sum}" ]; then
      printf 'MOD %s\n' "${rel}"
    fi
  done < <(canonical_scripts)
}

# Emit pending target injections as lines of the form:
#   INJECT <target_name> <script_rel_path>
# For each canonical script in consumer/scripts/ that is NOT invoked by any
# target in consumer/Makefile, look up the target in templates/Makefile that
# invokes it; emit if a templates-side target is defined.
function compute_target_injections() {
  local rel target
  while IFS= read -r rel; do
    [ -z "${rel}" ] && continue
    # The script must be (or will become) present in consumer after Pass 1.
    # For dry-run we project Pass 1 has succeeded; for live mode it has.
    if consumer_invokes_script "${rel}"; then
      continue
    fi
    target="$(find_target_for_script "${rel}")"
    if [ -n "${target}" ]; then
      printf 'INJECT %s %s\n' "${target}" "${rel}"
    fi
  done < <(canonical_scripts)
}

function consumer_invokes_script() {
  local -r rel="${1}"
  grep -qF "bash ${rel}" "${CONSUMER_MAKEFILE}"
}

# Find the target in templates/Makefile whose recipe invokes the given
# script. Returns empty if no template target invokes it.
function find_target_for_script() {
  local -r rel="${1}"
  local lineno
  lineno="$(grep -nF "bash ${rel}" "${TEMPLATES_MAKEFILE}" | head -1 | cut -d: -f1)"
  if [ -z "${lineno}" ]; then
    return 0
  fi
  awk -v ln="${lineno}" '
    NR<=ln && /^[a-zA-Z_][a-zA-Z0-9_.-]*[[:space:]]*:/ { last=$0 }
    END { if (last) { sub(/[[:space:]]*:.*$/, "", last); print last } }
  ' "${TEMPLATES_MAKEFILE}"
}

function report_changes() {
  local -r script_changes="${1}"
  local -r target_injections="${2}"
  if [ -z "${script_changes}" ] && [ -z "${target_injections}" ]; then
    log "  nothing pending"
    return 0
  fi
  if [ -n "${script_changes}" ]; then
    log "  scripts:"
    while IFS= read -r line; do
      [ -n "${line}" ] && log "    ${line}"
    done <<< "${script_changes}"
  fi
  if [ -n "${target_injections}" ]; then
    log "  Makefile targets to inject:"
    while IFS= read -r line; do
      [ -n "${line}" ] && log "    ${line}"
    done <<< "${target_injections}"
  fi
}

function apply_script_changes() {
  local -r changes="${1}"
  [ -z "${changes}" ] && return 0
  local kind rel dst_dir
  while IFS=' ' read -r kind rel; do
    [ -z "${rel}" ] && continue
    dst_dir="${REPO_ROOT}/$(dirname "${rel}")"
    mkdir -p "${dst_dir}"
    cp "${STANDARDS_ROOT}/${rel}" "${REPO_ROOT}/${rel}"
    chmod +x "${REPO_ROOT}/${rel}"
  done <<< "${changes}"
}

function apply_target_injections() {
  local -r injections="${1}"
  [ -z "${injections}" ] && return 0
  {
    printf '\n## --- governance-refresh injected from .standards/templates/Makefile ---\n'
    local kind target rel
    while IFS=' ' read -r kind target rel; do
      [ -z "${target}" ] && continue
      printf '\n'
      extract_target_block "${target}"
    done <<< "${injections}"
  } >> "${CONSUMER_MAKEFILE}"
}

# Print the target's block from templates/Makefile: from `^target:` through
# the line before the next blank line. Recipe lines are TAB-indented per Make.
function extract_target_block() {
  local -r target="${1}"
  awk -v t="^${target}[[:space:]]*:" '
    $0 ~ t { in_block=1 }
    in_block && /^$/ { in_block=0; next }
    in_block { print }
  ' "${TEMPLATES_MAKEFILE}"
}

function log() {
  local msg
  msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a '/tmp/governance_refresh.log' >&5
}

main "${@:-}"
