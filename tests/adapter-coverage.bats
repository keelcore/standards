#!/usr/bin/env bats
# tests/adapter-coverage.bats
# The Claude adapter, which every consumer's CLAUDE.md links to, brings every governance document into scope:
# lint-adapters.local.sh fails on a governance/**/*.md file the adapter does not link, and on a link to a
# governance file that does not exist. make lint runs it.

setup() {
  STANDARDS="$(cd "${BATS_TEST_DIRNAME}/.." && pwd -P)"
  SCRIPT="${STANDARDS}/scripts/lint/lint-adapters.local.sh"
  FIX="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${FIX}/governance/ai" "${FIX}/adapters/claude"
  local f
  for f in arb.md release-policy.md coding.md ai/conduct.md; do
    printf '# %s\n' "${f}" > "${FIX}/governance/${f}"
  done
}

# adapter FILE...: a fixture adapter linking each governance FILE in the adapter's own style.
adapter() {
  local f
  {
    printf '# Engineering Standards\n'
    for f in "$@"; do
      printf '\n## %s\n\nSee [.standards/governance/%s](.standards/governance/%s).\n' "${f}" "${f}" "${f}"
    done
  } > "${FIX}/adapters/claude/CLAUDE.md"
}

check() {
  run bash -c "cd '${FIX}' && bash '${SCRIPT}'"
}

@test "lint-adapters: this repository's adapter links every governance document" {
  run bash -c "cd '${STANDARDS}' && bash '${SCRIPT}'"
  [ "${status}" -eq 0 ] || { printf '%s\n' "${output}"; return 1; }
}

@test "lint-adapters: an adapter linking every governance document passes" {
  adapter arb.md release-policy.md coding.md ai/conduct.md
  check
  [ "${status}" -eq 0 ] || { printf '%s\n' "${output}"; return 1; }
}

@test "lint-adapters: an adapter missing arb.md fails, naming it" {
  adapter release-policy.md coding.md ai/conduct.md
  check
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'governance/arb.md'* ]] || false
}

@test "lint-adapters: an adapter missing release-policy.md fails, naming it" {
  adapter arb.md coding.md ai/conduct.md
  check
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'governance/release-policy.md'* ]] || false
}

@test "lint-adapters: an adapter missing a nested document fails, naming it" {
  adapter arb.md release-policy.md coding.md
  check
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'governance/ai/conduct.md'* ]] || false
}

@test "lint-adapters: an adapter linking a governance file that does not exist fails, naming it" {
  adapter arb.md release-policy.md coding.md ai/conduct.md gone.md
  check
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'governance/gone.md'* ]] || false
}

@test "make: lint runs the adapter check" {
  run make -n -C "${STANDARDS}" lint
  [ "${status}" -eq 0 ] || { printf '%s\n' "${output}"; return 1; }
  [[ "${output}" == *'scripts/lint/lint-adapters.local.sh'* ]] || false
}
