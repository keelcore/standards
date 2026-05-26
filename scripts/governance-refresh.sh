#!/usr/bin/env bash
# governance-refresh.sh
# Reconciles a consumer repo with its `.standards` canonical source of truth.
#
# Three reconciliation passes — `.standards` always wins. Consumer hand-edits
# to any canonical artifact are overwritten on every refresh:
#
#   1. Canonical-script sync: walks .standards/scripts/ (excluding standards-
#      only paths: bootstrap-standards.sh, release/, verify/), copies any
#      missing or content-divergent script into the consumer's matching path.
#
#   2. Makefile target injection: for each canonical script now present in
#      the consumer's scripts/, if .standards/templates/Makefile.canonical
#      defines a target whose recipe invokes that script AND consumer
#      Makefile has no such target, lift the target block from
#      Makefile.canonical and append to consumer Makefile under a marker
#      comment.
#
#   3. Makefile target drift fix: for each target defined in BOTH the
#      canonical template and the consumer Makefile whose active recipe
#      lines differ, replace the consumer's target block with the canonical
#      one in place. Symmetric with pass 1 — canonical wins on shared
#      target names. Consumer-only targets (not in the canonical template)
#      are untouched.
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

declare -r TEMPLATES_MAKEFILE="${STANDARDS_ROOT}/templates/Makefile.canonical"
declare -r CONSUMER_MAKEFILE="${REPO_ROOT}/Makefile"

declare DRY_RUN=0
# Set by detect_consumer:
#   IS_CONSUMER  — STANDARDS_ROOT is a directory nested under REPO_ROOT
#                  (the consumer-repo layout, regardless of whether it
#                  came from a submodule or a symlink/test harness).
#   IS_SUBMODULE — `.standards` is a real git submodule (narrower; needed
#                  for the git-pull / git-stage operations).
declare IS_CONSUMER=0
declare IS_SUBMODULE=0

# Absolute path of THIS running script, captured before any re-exec. Used
# by reexec_from_canonical_if_stale to detect whether `make governance-
# refresh` invoked the consumer's local (potentially stale) copy at
# scripts/governance-refresh.sh instead of the canonical copy at
# .standards/scripts/governance-refresh.sh.
declare SELF_PATH
SELF_PATH="$(realpath -- "${BASH_SOURCE[0]}" 2>/dev/null || echo "${BASH_SOURCE[0]}")"
declare -r SELF_PATH

function main() {
  exec 5>&1
  parse_args "${@:-}"
  detect_consumer
  validate_env
  maybe_pull_submodule
  reexec_from_canonical_if_stale "${@:-}"
  ensure_consumer_migrated
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
      exit 1
    fi
    log "✅ dry-run: nothing to refresh"
    exit 0
  fi

  apply_script_changes "${script_changes}"
  apply_target_injections "${target_injections}"
  apply_target_drifts "${target_drifts}"
  verify_no_remaining_drifts
  maybe_stage_submodule
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
    if [ "${IS_SUBMODULE}" -eq 1 ]; then
      log "❌ .standards submodule not initialized at ${STANDARDS_ROOT}"
      log '   Run: git submodule update --init --recursive'
      exit 2
    fi
    log 'ℹ️  governance-refresh: no .standards submodule (running in the standards repo itself); nothing to refresh.'
    exit 0
  fi
  if [ ! -f "${TEMPLATES_MAKEFILE}" ]; then
    log "❌ STANDARDS_ROOT missing templates/Makefile.canonical: ${TEMPLATES_MAKEFILE}"
    exit 2
  fi
  if [ ! -f "${CONSUMER_MAKEFILE}" ]; then
    log "❌ REPO_ROOT missing Makefile: ${CONSUMER_MAKEFILE}"
    exit 2
  fi
}

# Distinguishes (1) "are we consumer-shaped" — STANDARDS_ROOT is a real
# directory nested under REPO_ROOT — from (2) "is .standards a real git
# submodule" — the narrower predicate needed by the git-pull / git-stage
# operations. The standards repo itself has neither and stays at 0/0.
function detect_consumer() {
  case "${STANDARDS_ROOT}" in
    "${REPO_ROOT}/"*)
      if [ -d "${STANDARDS_ROOT}" ] && [ "${STANDARDS_ROOT}" != "${REPO_ROOT}" ]; then
        IS_CONSUMER=1
      fi
      ;;
  esac
  if git -C "${REPO_ROOT}" submodule status .standards 2>/dev/null \
      | grep -q .; then
    IS_SUBMODULE=1
  fi
}

# If the consumer Makefile predates the canonical-include era (no
# `include .standards/templates/Makefile.canonical` directive), auto-run
# migrate-makefile.sh before continuing the refresh — governance-refresh
# is the one-stop reconciliation entry point; the operator should never
# have to chain it with a manual prerequisite.
#
# Dry-run mode does NOT migrate: it reports the pending migration and
# exits 1 so the CI governance gate fails until 'make governance-refresh'
# is run for real.
#
# Scope: fires only when STANDARDS_ROOT is a directory NESTED inside
# REPO_ROOT (the consumer-repo layout). The standards repo itself, and
# test harnesses that point STANDARDS_ROOT at an out-of-tree path, are
# exempt.
function ensure_consumer_migrated() {
  [ "${STANDARDS_ROOT}" = "${REPO_ROOT}" ] && return 0
  case "${STANDARDS_ROOT}" in
    "${REPO_ROOT}/"*) ;;
    *) return 0 ;;
  esac
  if grep -qE '^[[:space:]]*-?include[[:space:]]+\.standards/(templates/Makefile\.canonical|Makefile)\b' \
      "${CONSUMER_MAKEFILE}"; then
    return 0
  fi
  if [ "${DRY_RUN}" -eq 1 ]; then
    log "🛠  Consumer Makefile is unmigrated — would invoke migrate-makefile.sh"
    log "⚠️  dry-run: migration pending. Run 'make governance-refresh' to apply."
    exit 1
  fi
  log "🛠  Consumer Makefile is unmigrated — invoking migrate-makefile.sh"
  MIGRATE_REPO_ROOT="${REPO_ROOT}" \
    bash "${STANDARDS_ROOT}/scripts/migrate-makefile.sh"
}

# Advance the `.standards` submodule to its tracked-branch tip. Skipped in
# dry-run mode: the CI governance gate runs --dry-run and must evaluate
# against the pinned submodule pointer, not whatever upstream looks like
# right now — otherwise the gate becomes flaky. Also skipped after a
# re-exec (already pulled in the parent invocation).
function maybe_pull_submodule() {
  [ "${GOVREFRESH_REEXEC:-0}" = "1" ] && return 0
  [ "${IS_SUBMODULE}" -eq 1 ] || return 0
  [ "${DRY_RUN}" -eq 1 ] && return 0
  log "📡 Pulling latest .standards submodule..."
  git -C "${REPO_ROOT}" submodule update --remote .standards
}

# When `make governance-refresh` invokes the consumer's LOCAL copy at
# scripts/governance-refresh.sh, that copy may be older than the canonical
# at .standards/scripts/governance-refresh.sh — the running process was
# loaded into bash memory before maybe_pull_submodule fetched the fresh
# canonical, so it would otherwise execute stale logic for the remainder
# of the run (and self-update only on disk, helping the NEXT invocation
# instead of this one). Re-exec into the canonical so the current run uses
# the latest code.
#
# Loop guard: `GOVREFRESH_REEXEC=1` is exported before exec so the child
# process skips this check (and skips maybe_pull_submodule, since the
# parent already pulled).
#
# Skipped when already running the canonical (realpath match), when the
# canonical is content-identical to self (sha match), when not a consumer
# (no .standards submodule), or when the canonical is missing.
function reexec_from_canonical_if_stale() {
  [ "${GOVREFRESH_REEXEC:-0}" = "1" ] && return 0
  [ "${IS_CONSUMER}" -eq 1 ] || return 0
  local canonical="${STANDARDS_ROOT}/scripts/governance-refresh.sh"
  [ -f "${canonical}" ] || return 0
  local canonical_real
  canonical_real="$(realpath -- "${canonical}" 2>/dev/null || echo "${canonical}")"
  [ "${SELF_PATH}" = "${canonical_real}" ] && return 0
  local self_sum canonical_sum
  self_sum="$(sha256sum "${SELF_PATH}" | awk '{print $1}')"
  canonical_sum="$(sha256sum "${canonical_real}" | awk '{print $1}')"
  [ "${self_sum}" = "${canonical_sum}" ] && return 0
  log "🔁 Local scripts/governance-refresh.sh differs from canonical; re-exec"
  log "   from ${canonical_real}"
  export GOVREFRESH_REEXEC=1
  exec bash "${canonical_real}" "${@}"
}

# Stage the (possibly advanced) submodule pointer so the consumer's index
# is ready to commit. No-op if the pointer did not move.
function maybe_stage_submodule() {
  [ "${IS_SUBMODULE}" -eq 1 ] || return 0
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
# target in consumer/Makefile, look up the target in Makefile.canonical
# that invokes it; emit if a canonical target is defined.
#
# Short-circuit when the consumer Makefile already has the canonical-include
# directive: the included file provides every canonical target, so injecting
# them into the consumer body would only duplicate them. Worse, if the
# consumer's drifted recipe happens to invoke the script via the
# `.standards/scripts/` path instead of `scripts/`, `consumer_invokes_script`
# would miss it and pass 2 would emit a duplicate target — `active_recipe_of`
# then concatenates both bodies and the drift becomes self-perpetuating.
function compute_target_injections() {
  if has_include_directive; then
    return 0
  fi
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

# True iff CONSUMER_MAKEFILE contains an `include` directive pointing at the
# canonical template (current or legacy form). Mirrors migrate-makefile.sh's
# idempotency check.
function has_include_directive() {
  grep -qE '^[[:space:]]*-?include[[:space:]]+\.standards/(templates/Makefile\.canonical|Makefile)\b' \
    "${CONSUMER_MAKEFILE}"
}

function consumer_invokes_script() {
  local -r rel="${1}"
  grep -qF "bash ${rel}" "${CONSUMER_MAKEFILE}"
}

# Emit pending target drifts as lines of the form:
#   DRIFT <target_name>
# For each target name defined in BOTH Makefile.canonical and consumer
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

# Names of all targets defined in Makefile.canonical.
function template_target_names() {
  awk '
    /^[a-zA-Z_][a-zA-Z0-9_.-]*[[:space:]]*:/ &&
      !/^[a-zA-Z_][a-zA-Z0-9_.-]*[[:space:]]*[?:+]?=/ {
        sub(/[[:space:]]*:.*$/, "")
        print
    }
  ' "${TEMPLATES_MAKEFILE}" | sort -u
}

# Active recipe lines for the named target — the substantive command lines,
# stripped of decoration so drift detection compares "what gets run", not
# how it's announced. For each TAB-indented body line:
#   * strip leading TABs and recipe modifiers (`@`, `-`)
#   * strip a trailing inline `# comment` and any trailing whitespace
#   * drop empty lines, full-line `#` comments, and `@?echo` announcements
# Per Rule 4's "active recipe" definition.
function active_recipe_of() {
  local -r makefile="${1}"
  local -r target="${2}"
  awk -v t="^${target}[[:space:]]*:" '
    $0 ~ t { in_block=1; next }
    /^[a-zA-Z_]/ { in_block=0 }
    in_block && /^\t/ {
      body=$0
      sub(/^\t+/, "", body)
      sub(/^[@-]+/, "", body)
      sub(/[[:space:]]+#.*$/, "", body)
      sub(/[[:space:]]+$/, "", body)
      if (body == "") next
      if (body ~ /^#/) next
      if (body ~ /^echo([[:space:]]|$)/) next
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

# Find the target in Makefile.canonical whose recipe invokes the given
# script. Returns empty if no canonical target invokes it.
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
    log "  Makefile targets to overwrite (consumer recipe differs from"
    log "  .standards/templates/Makefile.canonical — canonical wins):"
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
    printf '\n## --- governance-refresh injected from .standards/templates/Makefile.canonical ---\n'
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

# Print the target's block from Makefile.canonical: from `^target:` through
# the line before the next blank line. Recipe lines are TAB-indented per Make.
function extract_target_block() {
  local -r target="${1}"
  awk -v t="^${target}[[:space:]]*:" '
    $0 ~ t { in_block=1 }
    in_block && /^$/ { in_block=0; next }
    in_block { print }
  ' "${TEMPLATES_MAKEFILE}"
}

# Rewrite the consumer Makefile in place, replacing each drifted target's
# block (from `^target:` through the line before the next blank line) with
# the canonical block from Makefile.canonical. Atomic: writes to a temp file
# and renames into place on success. No-op when the drift list is empty.
function apply_target_drifts() {
  local -r drifts="${1}"
  [ -z "${drifts}" ] && return 0
  local blocks_file targets_file tmp_out
  blocks_file="$(mktemp -t govrefresh-blocks.XXXXXX)"
  targets_file="$(mktemp -t govrefresh-targets.XXXXXX)"
  tmp_out="$(mktemp -t govrefresh-makefile.XXXXXX)"
  local kind target
  while IFS=' ' read -r kind target; do
    [ -z "${target}" ] && continue
    if [ "${kind}" != "DRIFT" ]; then
      log "❌ apply_target_drifts: unexpected kind '${kind}' for ${target}"
      exit 3
    fi
    printf '%s\n' "${target}" >> "${targets_file}"
    {
      printf '<<<BEGIN %s>>>\n' "${target}"
      extract_target_block "${target}"
      printf '<<<END %s>>>\n' "${target}"
    } >> "${blocks_file}"
  done <<< "${drifts}"

  awk -v blocks_file="${blocks_file}" -v targets_file="${targets_file}" '
    BEGIN {
      while ((getline ln < targets_file) > 0) {
        if (ln != "") drifted[ln] = 1
      }
      close(targets_file)
      cur = ""
      while ((getline ln < blocks_file) > 0) {
        if (substr(ln, 1, 9) == "<<<BEGIN ") {
          cur = substr(ln, 10)
          sub(/>>>$/, "", cur)
          blocks[cur] = ""
          continue
        }
        if (substr(ln, 1, 7) == "<<<END ") {
          cur = ""
          continue
        }
        if (cur != "") {
          blocks[cur] = blocks[cur] (blocks[cur] == "" ? "" : "\n") ln
        }
      }
      close(blocks_file)
      skipping = 0
    }
    /^[a-zA-Z_][a-zA-Z0-9_.-]*[[:space:]]*:/ &&
    !/^[a-zA-Z_][a-zA-Z0-9_.-]*[[:space:]]*[?:+]?=/ {
      tname = $0
      sub(/[[:space:]]*:.*$/, "", tname)
      if (tname in drifted) {
        print blocks[tname]
        skipping = 1
        next
      }
      skipping = 0
    }
    skipping && /^$/ { skipping = 0; print ""; next }
    skipping { next }
    { print }
  ' "${CONSUMER_MAKEFILE}" > "${tmp_out}"

  mv "${tmp_out}" "${CONSUMER_MAKEFILE}"
  rm -f "${blocks_file}" "${targets_file}"
}

# Post-apply assertion: re-run drift detection against the (now-rewritten)
# consumer Makefile. Any drift left over here means apply_target_drifts
# did not fully resolve the recipes — typically because the consumer
# Makefile defines the same target twice (so active_recipe_of concatenates
# both copies) or because something in the consumer's layout escapes the
# block-replacement state machine. Fail LOUDLY rather than letting the
# operator think it worked.
function verify_no_remaining_drifts() {
  local remaining
  remaining="$(compute_target_drifts)"
  [ -z "${remaining}" ] && return 0
  log ""
  log "❌ post-apply drift remains — apply_target_drifts did NOT resolve these"
  log "   target(s). Likely causes: duplicate target definitions in the"
  log "   consumer Makefile, or a recipe layout the replacement state machine"
  log "   doesn't recognize."
  local kind target c_active t_active count
  while IFS=' ' read -r kind target; do
    [ -z "${target}" ] && continue
    log ""
    log "   --- ${target} ---"
    count="$(grep -cE "^${target}[[:space:]]*:" "${CONSUMER_MAKEFILE}" || true)"
    log "   target definitions in consumer Makefile: ${count} (expect 1)"
    t_active="$(active_recipe_of "${TEMPLATES_MAKEFILE}" "${target}")"
    c_active="$(active_recipe_of "${CONSUMER_MAKEFILE}" "${target}")"
    log "   canonical active recipe:"
    while IFS= read -r line; do log "     | ${line}"; done <<< "${t_active}"
    log "   consumer active recipe (post-apply):"
    while IFS= read -r line; do log "     | ${line}"; done <<< "${c_active}"
  done <<< "${remaining}"
  exit 5
}

function log() {
  local msg
  msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a '/tmp/governance_refresh.log' >&5
}

main "${@:-}"
