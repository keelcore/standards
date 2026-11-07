#!/usr/bin/env bats
# tests/target-names.bats
# Make targets are verb-first (<verb>-<object>[-<qualifier>]): audit Rule 8 enforces it, and a renamed
# canonical target tells its caller the new name and fails.

setup() {
  load helpers-consumer
  consumer_setup
  printf 'include .standards/templates/Makefile.canonical\n' > Makefile
  mkdir -p .github
  touch SECURITY.md .github/CODEOWNERS .github/dependabot.yml
}

audit_output() {
  run bash scripts/ci/audit-make-targets.sh
}

@test "every canonical target follows the convention" {
  audit_output
  [[ "${output}" != *'Rule 8'* ]]
}

@test "audit: a noun-first target fails and is named" {
  printf 'include .standards/templates/Makefile.canonical\n\nwidget-build:\n\t@true\n' > Makefile
  audit_output
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'Rule 8'*'widget-build'* ]]
}

@test "audit: a verb from the list passes, and a project hook -local is the target's name" {
  printf 'include .standards/templates/Makefile.canonical\n\nbuild-widget:\n\t@true\n\nupdate-pins-local:\n\t@true\n' > Makefile
  audit_output
  [[ "${output}" != *'Rule 8'* ]]
}

@test "audit: a single word that is not an aggregate fails" {
  printf 'include .standards/templates/Makefile.canonical\n\nwidget:\n\t@true\n' > Makefile
  audit_output
  [[ "${output}" == *'Rule 8'*'widget'* ]]
}

@test "a renamed target prints the new name and fails" {
  run make --no-print-directory -f Makefile release-sign
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'sign-release'* ]]
  run make --no-print-directory -f Makefile unit-test
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'test-unit'* ]]
}

@test "renamed-target.sh: names the replacement, and always fails" {
  run bash scripts/ci/renamed-target.sh sign-release
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'make sign-release'* ]]
  run bash scripts/ci/renamed-target.sh
  [ "${status}" -ne 0 ]
}

@test "test runs the Go runner, the project's unit hook and the integration entry point" {
  local -r got="$(make -n -f Makefile test 2> /dev/null)"
  [[ "${got}" == *'scripts/test/ci.sh'* ]]
  [[ "${got}" == *'scripts/unit-test.sh'* ]]
  [[ "${got}" == *'scripts/integration-test.sh'* ]]
}
