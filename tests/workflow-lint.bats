#!/usr/bin/env bats
# tests/workflow-lint.bats
# actionlint and zizmor run on a repository's workflows, offline without a token; part of make lint.

setup() {
  load helpers-consumer
  consumer_setup
  stub actionlint
  stub zizmor
  unset GH_TOKEN
}

@test "workflows.sh: no workflows, nothing to do" {
  run bash scripts/lint/workflows.sh
  [ "${status}" -eq 0 ]
  [ -z "$(calls_of actionlint)" ]
}

@test "workflows.sh: runs both tools; offline without a token, online with one" {
  mkdir -p .github/workflows
  printf 'x\n' > .github/workflows/a.yml
  run bash scripts/lint/workflows.sh
  [ "${status}" -eq 0 ]
  calls_of actionlint | grep -q .
  calls_of zizmor | grep -q -- '--offline'
  : > "${CALLS}"
  GH_TOKEN=t run bash scripts/lint/workflows.sh
  ! calls_of zizmor | grep -q -- '--offline'
}

@test "workflows.sh: uses config/zizmor.local.yml when the repository has one" {
  mkdir -p .github/workflows config
  printf 'x\n' > .github/workflows/a.yml
  printf 'rules: {}\n' > config/zizmor.local.yml
  run bash scripts/lint/workflows.sh
  calls_of zizmor | grep -q -- '--config config/zizmor.local.yml'
}

@test "workflows.sh: a finding fails" {
  mkdir -p .github/workflows
  printf 'x\n' > .github/workflows/a.yml
  stub zizmor 'exit 13'
  run bash scripts/lint/workflows.sh
  [ "${status}" -ne 0 ]
}

@test "make lint includes lint-workflows, and the tool image has both tools" {
  grep -qE '^lint:.* lint-workflows' "${STANDARDS}/templates/Makefile.canonical"
  grep -q 'scripts/ci/setup-actionlint.sh' "${STANDARDS}/containers/dev/Containerfile"
  grep -q 'scripts/ci/setup-zizmor.sh' "${STANDARDS}/containers/dev/Containerfile"
}
