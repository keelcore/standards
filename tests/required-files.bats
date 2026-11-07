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
