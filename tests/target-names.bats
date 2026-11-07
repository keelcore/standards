#!/usr/bin/env bats
# tests/target-names.bats
# Make targets and scripts are verb-first (<verb>-<object>[-<qualifier>]): audit Rules 8 and 9 enforce
# it, and the old names are gone.

setup() {
  load helpers-consumer
  consumer_setup
  printf 'include .standards/templates/Makefile.canonical\n' > Makefile
  mkdir -p .github
  touch SECURITY.md .github/CODEOWNERS .github/dependabot.yml
}

audit_output() {
  run bash scripts/ci/audit.sh
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

@test "old target names are gone" {
  run make --no-print-directory -f Makefile release-sign
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'No rule'* ]] || false
  [ ! -e "${STANDARDS}/scripts/ci/renamed-target.sh" ]
}

@test "every canonical script is named after its target" {
  audit_output
  [[ "${output}" != *'Rule 9'* ]]
}

@test "audit: a script named noun-first fails and is named" {
  printf '#!/usr/bin/env bash\n' > scripts/ci/widget-check.sh
  printf 'include .standards/templates/Makefile.canonical\n\ncheck-widget:\n\tbash scripts/ci/widget-check.sh\n' > Makefile
  audit_output
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'Rule 9'*'widget-check'* ]]
}

@test "test runs the Go runner, the project's unit hook and the integration entry point" {
  local -r got="$(make -n -f Makefile test 2> /dev/null)"
  [[ "${got}" == *'scripts/test/test-unit-go.sh'* ]] || false
  [[ "${got}" == *'scripts/test-unit-local.sh'* ]] || false
  [[ "${got}" == *'scripts/test-integration.sh'* ]]
}
