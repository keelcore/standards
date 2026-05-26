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
# Flipped to 1 by detect_consumer when REPO_ROOT contains a `.standards`
# submodule (i.e., we are NOT the standards repo itself). Effectively
# immutable after detect_consumer runs.
declare IS_CONSUMER=0

function main() {
  exec 5>&1
  parse_args "${@:-}"
  detect_consumer
  validate_env
  maybe_pull_submodule
  log "🔄 governance-refresh: REPO_ROOT=${REPO_ROOT}"

  local script_changes target_injections target_drifts
  script_changes="$(compute_script_changes)"
  target_injections="$(compute_target_injections)"
  target_drifts="$(compute_target_drifts)"

  report_changes "${script_changes}" "${target_injections}" "${target_drifts}"

  if [ "${DRY_RUN}" -eq 1 ]; then
    if [ -n "${script_changes}" ] || [ -n "${target_injections}" ] \
        || [ -n "${target_drifts}" ]; then
      log "⚠️  dry-run: changes pending. Run 'make governance-refresh' to apply."
      log "    (target drifts require HUMAN resolution — they are NOT auto-fixed.)"
      exit 1
    fi
    log "✅ dry-run: nothing to refresh"
    exit 0
  fi

  apply_script_changes "${script_changes}"
  apply_target_injections "${target_injections}"
  maybe_stage_submodule
  if [ -n "${target_drifts}" ]; then
    log "⚠️  target drift detected but NOT auto-fixed (recipes for shared"
    log "    target names differ between consumer Makefile and"
    log "    .standards/templates/Makefile). Reconcile manually."
  fi
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
    if [ "${IS_CONSUMER}" -eq 1 ]; then
      log "❌ .standards submodule not initialized at ${STANDARDS_ROOT}"
      log '   Run: git submodule update --init --recursive'
      exit 2
    fi
    log 'ℹ️  governance-refresh: no .standards submodule (running in the standards repo itself); nothing to refresh.'
    exit 0
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

# Sets IS_CONSUMER=1 iff REPO_ROOT contains a `.standards` submodule. The
# standards repo itself has no `.standards/`, so it stays 0. A test harness
# that points GOVREFRESH_STANDARDS_ROOT at a local path also stays 0 (no
# submodule entry to advance).
function detect_consumer() {
  if git -C "${REPO_ROOT}" submodule status .standards 2>/dev/null \
      | grep -q .; then
    IS_CONSUMER=1
  fi
}

# Advance the `.standards` submodule to its tracked-branch tip. Skipped in
# dry-run mode: the CI governance gate runs --dry-run and must evaluate
# against the pinned submodule pointer, not whatever upstream looks like
# right now — otherwise the gate becomes flaky.
function maybe_pull_submodule() {
  [ "${IS_CONSUMER}" -eq 1 ] || return 0
  [ "${DRY_RUN}" -eq 1 ] && return 0
  log "📡 Pulling latest .standards submodule..."
  git -C "${REPO_ROOT}" submodule update --remote .standards
}

# Stage the (possibly advanced) submodule pointer so the consumer's index
# is ready to commit. No-op if the pointer did not move.
function maybe_stage_submodule() {
  [ "${IS_CONSUMER}" -eq 1 ] || return 0
  [ "${DRY_RUN}" -eq 1 ] && return 0
  log "📌 Staging .standards submodule pointer..."
  git -C "${REPO_ROOT}" add .standards
}

# List shipping canonical scripts as paths relative to ${STANDARDS_ROOT}.
# Excludes standards-only paths. The refresh script itself IS shipped so it
# can self-update on subsequent runs.
#   - Top-level standards-only files (exact match): bootstrap-standards.sh
#     (consumers `curl` it once; they do not keep a local copy).
#   - Standards-only directory trees (prefix match): scripts/release/,
#     scripts/verify/.
function canonical_scripts() {
  find "${STANDARDS_ROOT}/scripts" -name '*.sh' -type f \
    | sed "s|^${STANDARDS_ROOT}/||" \
    | grep -v -E '^scripts/bootstrap-standards\.sh$' \
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

# Emit pending target drifts as lines of the form:
#   DRIFT <target_name>
# For each target name defined in BOTH templates/Makefile and consumer
# Makefile, compare the active recipe lines (ignoring blank, comment, and
# @echo lines per Rule 4's "active" definition). Normalize `.standards/`
# prefix so cross-context invocations of standards-only scripts (e.g.
# governance-refresh) don't false-positive.
function compute_target_drifts() {
  local target t_active c_active t_norm c_norm
  while IFS= read -r target; do
    [ -z "${target}" ] && continue
    # Skip targets unique to one Makefile — those are caught by Rule 2
    # (consumer-only) or the injection pass (templates-only).
    if ! grep -qE "^${target}[[:space:]]*:" "${CONSUMER_MAKEFILE}"; then
      continue
    fi
    t_active="$(active_recipe_of "${TEMPLATES_MAKEFILE}" "${target}")"
    c_active="$(active_recipe_of "${CONSUMER_MAKEFILE}" "${target}")"
    # Skip when EITHER side has no active recipe:
    #   - templates empty: provides a stub for the consumer to fill in
    #     (e.g. `build:` in the docs-only standards repo where consumer
    #     supplies a real `bash scripts/build.sh`). Expected customization.
    #   - consumer empty: aggregator with only prerequisites — not a
    #     substantive override.
    #   - both empty: nothing to drift on.
    # Drift is flagged ONLY when BOTH sides invoke a script and the
    # invocations differ (after `.standards/` prefix normalization).
    if [ -z "${t_active}" ] || [ -z "${c_active}" ]; then
      continue
    fi
    t_norm="$(normalize_recipe "${t_active}")"
    c_norm="$(normalize_recipe "${c_active}")"
    if [ "${t_norm}" != "${c_norm}" ]; then
      printf 'DRIFT %s\n' "${target}"
    fi
  done < <(template_target_names)
}

# Names of all targets defined in templates/Makefile.
function template_target_names() {
  awk '
    /^[a-zA-Z_][a-zA-Z0-9_.-]*[[:space:]]*:/ &&
      !/^[a-zA-Z_][a-zA-Z0-9_.-]*[[:space:]]*[?:+]?=/ {
        sub(/[[:space:]]*:.*$/, "")
        print
    }
  ' "${TEMPLATES_MAKEFILE}" | sort -u
}

# Active recipe lines for the named target — TAB-indented lines that aren't
# blank, comment, or @echo. Strips leading @/- modifiers (per Rule 4).
function active_recipe_of() {
  local -r makefile="${1}"
  local -r target="${2}"
  awk -v t="^${target}[[:space:]]*:" '
    $0 ~ t { in_block=1; next }
    /^[a-zA-Z_]/ { in_block=0 }
    in_block && /^\t/ {
      body=$0
      sub(/^\t+/, "", body)
      if (body == "") next
      if (body ~ /^#/) next
      if (body ~ /^@?-?echo([[:space:]]|$)/) next
      sub(/^[@-]+/, "", body)
      print body
    }
  ' "${makefile}"
}

# Normalize a recipe for drift comparison:
#   - collapse multiple whitespace to single space
#   - strip an optional `.standards/` prefix on a scripts/ path so
#     cross-context invocations (consumer Makefile invokes the .standards
#     submodule path; templates invokes the script via the relative path)
#     compare equal.
function normalize_recipe() {
  local -r raw="${1}"
  printf '%s\n' "${raw}" \
    | sed -E 's| \.standards/scripts/| scripts/|g; s|[[:space:]]+| |g'
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
  local -r target_drifts="${3:-}"
  if [ -z "${script_changes}" ] && [ -z "${target_injections}" ] \
      && [ -z "${target_drifts}" ]; then
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
  if [ -n "${target_drifts}" ]; then
    log "  Makefile target recipe drift (active lines differ between"
    log "  consumer Makefile and .standards/templates/Makefile):"
    while IFS= read -r line; do
      [ -n "${line}" ] && log "    ${line}"
    done <<< "${target_drifts}"
  fi
}

function apply_script_changes() {
  local -r changes="${1}"
  [ -z "${changes}" ] && return 0
  local kind rel dst_dir
  while IFS=' ' read -r kind rel; do
    [ -z "${rel}" ] && continue
    case "${kind}" in
      NEW|MOD) ;;
      *)
        log "❌ apply_script_changes: unexpected kind '${kind}' for ${rel}"
        exit 3
        ;;
    esac
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
      if [ "${kind}" != "INJECT" ]; then
        log "❌ apply_target_injections: unexpected kind '${kind}' for ${target}"
        exit 3
      fi
      printf '\n# Injected because canonical script %s has no consumer target.\n' "${rel}"
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
