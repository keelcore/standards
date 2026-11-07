#!/usr/bin/env bats
# tests/required-files.bats
# Every repository carries a security policy, code owners and dependency updates: templates here,
# and an audit rule that they exist.

setup() {
  load helpers-consumer
  consumer_setup
  printf 'include .standards/templates/Makefile.canonical\n' > Makefile
  mkdir -p .github
}

@test "the templates exist" {
  local f
  for f in SECURITY.md CODEOWNERS dependabot.yml; do
    [ -s "${STANDARDS}/templates/${f}" ]
  done
}

@test "audit: names each missing file, and passes when they exist" {
  run bash scripts/ci/audit.sh
  [[ "${output}" == *'Rule 7'*'SECURITY.md'* ]]
  [[ "${output}" == *'.github/CODEOWNERS'* ]]
  [[ "${output}" == *'.github/dependabot.yml'* ]]
  touch SECURITY.md .github/CODEOWNERS .github/dependabot.yml
  run bash scripts/ci/audit.sh
  [[ "${output}" != *'Rule 7'* ]]
}

@test "audit: SECURITY.md may live in .github" {
  touch .github/SECURITY.md .github/CODEOWNERS .github/dependabot.yml
  run bash scripts/ci/audit.sh
  [[ "${output}" != *'Rule 7'* ]]
}

@test "this repository carries them" {
  [ -f "${STANDARDS}/SECURITY.md" ]
  [ -f "${STANDARDS}/.github/CODEOWNERS" ]
  [ -f "${STANDARDS}/.github/dependabot.yml" ]
}

@test "SECURITY.md and its template link the private reporting route" {
  local f
  for f in "${BATS_TEST_DIRNAME}/../SECURITY.md" "${BATS_TEST_DIRNAME}/../templates/SECURITY.md"; do
    grep -qE '\]\([^)]*security/advisories/new\)' "${f}" || { echo "${f}: no advisory link"; return 1; }
    grep -qE '\]\(https://docs\.github\.com/[^)]+\)' "${f}" || { echo "${f}: no documentation link"; return 1; }
  done
  grep -qE '\(https://github\.com/keelcore/standards/security/advisories/new\)' "${BATS_TEST_DIRNAME}/../SECURITY.md"
  grep -qE '\(mailto:[^)]+\)' "${BATS_TEST_DIRNAME}/../SECURITY.md"
}
