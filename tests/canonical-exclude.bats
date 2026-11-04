#!/usr/bin/env bats
# tests/canonical-exclude.bats
# A consumer's .canonical-exclude lists canonical scripts it never runs:
# verify-canonical and governance-refresh skip them, and audit Rule 5 accepts
# their canonical targets pointing at a missing file. Scripts not listed keep
# every check.
#
# Each test builds a throwaway consumer under BATS_TEST_TMPDIR whose
# .standards is a symlink to this repo and whose scripts/ holds byte-identical
# copies of every canonical script, minus the excluded publishers.

bats_require_minimum_version 1.5.0

readonly EXCLUDED='scripts/release/npm-publish.sh'

setup() {
  STANDARDS="$(cd "${BATS_TEST_DIRNAME}/.." && pwd -P)"
  CONSUMER="${BATS_TEST_TMPDIR}/consumer"
  mkdir -p "${CONSUMER}"
  cd "${CONSUMER}"
  git init --quiet
  ln -s "${STANDARDS}" .standards
  printf 'include .standards/templates/Makefile.canonical\n' > Makefile
  copy_canonical_scripts
  printf '# not published here\n%s\n\n' "${EXCLUDED}" > .canonical-exclude
  rm "${EXCLUDED}"
}

copy_canonical_scripts() {
  local f
  while IFS= read -r f; do
    mkdir -p "$(dirname "${f}")"
    cp -p "${STANDARDS}/${f}" "${f}"
  done < <(cd "${STANDARDS}" && find scripts -type f \( -path 'scripts/hooks/*' -o -name '*.sh' ! -name '*.local.sh' \))
}

@test "verify-canonical skips an excluded script the consumer does not carry" {
  run bash scripts/ci/verify-canonical-scripts.sh "${CONSUMER}"
  [ "${status}" -eq 0 ]
  [[ "${output}" != *'npm-publish.sh'* ]] || false
}

@test "verify-canonical still fails on a missing script that is not excluded" {
  rm scripts/release/pypi-publish.sh
  run bash scripts/ci/verify-canonical-scripts.sh "${CONSUMER}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'FAIL  scripts/release/pypi-publish.sh'* ]] || false
}

@test "governance-refresh does not restore an excluded script" {
  run bash scripts/governance-refresh.sh
  [ "${status}" -eq 0 ]
  [ ! -e "${EXCLUDED}" ]
}

@test "audit Rule 5 accepts the excluded script's canonical target" {
  run bash scripts/ci/audit-make-targets.sh
  [[ "${output}" != *"Rule 5: target 'release-npm'"* ]] || false
}

@test "audit Rule 5 still flags a missing script that is not excluded" {
  rm scripts/release/pypi-publish.sh
  run bash scripts/ci/audit-make-targets.sh
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"Rule 5: target 'release-pypi'"* ]] || false
}
