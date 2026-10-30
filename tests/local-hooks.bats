#!/usr/bin/env bats
# tests/local-hooks.bats
# *.local.sh hooks are owned by the repo that holds them: verify-canonical and
# governance-refresh must neither compare nor sync them, even though the
# standards repo keeps hooks of its own under scripts/.
#
# Each test builds a throwaway consumer under BATS_TEST_TMPDIR whose
# .standards is a symlink to this repo and whose scripts/ holds byte-identical
# copies of every canonical script.

bats_require_minimum_version 1.5.0

setup() {
  STANDARDS="$(cd "${BATS_TEST_DIRNAME}/.." && pwd -P)"
  CONSUMER="${BATS_TEST_TMPDIR}/consumer"
  mkdir -p "${CONSUMER}"
  cd "${CONSUMER}"
  git init --quiet
  ln -s "${STANDARDS}" .standards
  printf 'include .standards/templates/Makefile.canonical\n' > Makefile
  copy_canonical_scripts
}

copy_canonical_scripts() {
  local f
  while IFS= read -r f; do
    mkdir -p "$(dirname "${f}")"
    cp -p "${STANDARDS}/${f}" "${f}"
  done < <(cd "${STANDARDS}" && find scripts -name '*.sh' ! -name '*.local.sh' -type f)
}

consumer_hook() {
  mkdir -p scripts/release
  cp "${STANDARDS}/tests/fixtures/create-release/hook.sh" scripts/release/create-release.local.sh
}

@test "the standards repo carries hooks of its own (precondition)" {
  [ -f "${STANDARDS}/scripts/release/create-release.local.sh" ]
  [ -f "${STANDARDS}/scripts/integration-test.local.sh" ]
}

@test "verify-canonical passes when the consumer's hook differs from the standards hook" {
  consumer_hook
  run bash scripts/ci/verify-canonical-scripts.sh "${CONSUMER}"
  [ "${status}" -eq 0 ]
  [[ "${output}" != *'.local.sh'* ]] || false
}

@test "verify-canonical passes when the consumer has no hooks" {
  run bash scripts/ci/verify-canonical-scripts.sh "${CONSUMER}"
  [ "${status}" -eq 0 ]
  [[ "${output}" != *'.local.sh'* ]] || false
}

@test "governance-refresh neither overwrites nor adds hooks" {
  consumer_hook
  run bash scripts/governance-refresh.sh --dry-run
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'nothing to refresh'* ]] || false
  [[ "${output}" != *'.local.sh'* ]] || false
  run bash scripts/governance-refresh.sh
  [ "${status}" -eq 0 ]
  cmp "${STANDARDS}/tests/fixtures/create-release/hook.sh" scripts/release/create-release.local.sh
  [ ! -e scripts/integration-test.local.sh ]
}
