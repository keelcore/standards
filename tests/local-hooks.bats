#!/usr/bin/env bats
# tests/local-hooks.bats
# Every canonical script has a project hook: <script>.local.sh beside it, when present, runs first with the
# script's arguments (scripts/lib/local-hook.sh), and audit Rule 10 enforces that every canonical script has one.

setup() {
  load helpers-consumer
  consumer_setup
  printf 'include .standards/templates/Makefile.canonical\n' > Makefile
  mkdir -p .github
  touch SECURITY.md .github/CODEOWNERS .github/dependabot.yml
}

@test "run_local_hook: runs the hook beside the script with its arguments; none is no-op" {
  mkdir -p "${WORK}/s"
  printf 'printf "%%s|" "$@" > "%s/ran"\n' "${WORK}" > "${WORK}/s/thing.local.sh"
  source "${STANDARDS}/scripts/lib/local-hook.sh"
  run run_local_hook "${WORK}/s/thing.sh" a 'b c'
  [ "${status}" -eq 0 ]
  [ "$(cat "${WORK}/ran")" = 'a|b c|' ]
  run run_local_hook "${WORK}/s/other.sh" x
  [ "${status}" -eq 0 ]
}

@test "run_local_hook: a failing hook fails the caller" {
  mkdir -p "${WORK}/s"
  printf 'exit 3\n' > "${WORK}/s/thing.local.sh"
  source "${STANDARDS}/scripts/lib/local-hook.sh"
  run run_local_hook "${WORK}/s/thing.sh"
  [ "${status}" -eq 3 ]
}

@test "a canonical script runs its project hook first, with its arguments" {
  printf 'printf "hook:%%s\\n" "$*"\n' > scripts/lint/lint-newlines.local.sh
  run bash scripts/lint/lint-newlines.sh
  [[ "${lines[0]}" == 'hook:'* ]] || { echo "${output}"; return 1; }
}

@test "a failing project hook stops the canonical script" {
  printf 'echo hook-failed; exit 4\n' > scripts/lint/lint-newlines.local.sh
  run bash scripts/lint/lint-newlines.sh
  [ "${status}" -eq 4 ]
  [[ "${output}" != *'Newlines OK'* ]]
}

@test "every canonical script has its project hook" {
  run bash scripts/ci/audit.sh
  [[ "${output}" != *'Rule 10'* ]] || { echo "${output}" | grep 'Rule 10'; return 1; }
}

@test "audit: a canonical script without its project hook fails and is named" {
  grep -v 'run_local_hook' scripts/lint/lint-newlines.sh > scripts/lint/lint-newlines.sh.new
  mv scripts/lint/lint-newlines.sh.new scripts/lint/lint-newlines.sh
  run bash scripts/ci/audit.sh
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'Rule 10'*'scripts/lint/lint-newlines.sh'* ]] || false
}

@test "run from .standards/, a canonical script runs the consumer's hook (the git toplevel), not one in .standards" {
  printf 'printf "consumer-hook\\n"\n' > scripts/lint/lint-newlines.local.sh
  run bash .standards/scripts/lint/lint-newlines.sh
  [[ "${lines[0]}" == 'consumer-hook' ]] || { echo "${output}"; return 1; }
}
