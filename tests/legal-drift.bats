#!/usr/bin/env bats
# tests/legal-drift.bats
# check-legal-drift.sh and ensure-legal-notices.sh read the pairs a repository lists in
# config/legal-copies.local.txt (SOURCE<TAB>COPY): check fails on a copy that is missing or differs
# from its source and changes nothing; ensure writes each copy from its source. No list, nothing to do.
#
# Each test builds a throwaway consumer under BATS_TEST_TMPDIR holding the two scripts and their
# libraries, and runs them with CI and GITHUB_STEP_SUMMARY unset unless the test sets them.

bats_require_minimum_version 1.5.0

setup() {
  STANDARDS="$(cd "${BATS_TEST_DIRNAME}/.." && pwd -P)"
  CONSUMER="${BATS_TEST_TMPDIR}/consumer"
  mkdir -p "${CONSUMER}/scripts/lib" "${CONSUMER}/config"
  cd "${CONSUMER}"
  git init --quiet
  cp -p "${STANDARDS}/scripts/check-legal-drift.sh" "${STANDARDS}/scripts/ensure-legal-notices.sh" scripts/
  cp -p "${STANDARDS}/scripts/lib/local-hook.sh" "${STANDARDS}/scripts/lib/legal-copies.sh" scripts/lib/
  printf 'license text\n' > LICENSE
  printf 'trademark text\n' > TRADEMARK.md
}

# list LINE...: config/legal-copies.local.txt holding LINE..., one per line.
list() {
  printf '%s\n' "$@" > config/legal-copies.local.txt
}

check() {
  run env -u CI -u GITHUB_STEP_SUMMARY "$@" bash scripts/check-legal-drift.sh
}

ensure() {
  run env -u CI -u GITHUB_STEP_SUMMARY bash scripts/ensure-legal-notices.sh
}

@test "check: no list passes, saying there is nothing to check" {
  check
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'nothing to check'* ]] || false
}

@test "check: a listed copy identical to its source passes" {
  mkdir -p pkg/cli
  cp LICENSE pkg/cli/LICENSE
  list $'LICENSE\tpkg/cli/LICENSE'
  check
  [ "${status}" -eq 0 ]
}

@test "check: a copy that differs fails, naming both files and the fix, and changes nothing" {
  mkdir -p pkg/cli
  printf 'old text\n' > pkg/cli/LICENSE
  list $'LICENSE\tpkg/cli/LICENSE'
  check
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'LICENSE'*'pkg/cli/LICENSE'* ]] || false
  [[ "${output}" == *'make ensure-legal-notices'* ]] || false
  [ "$(cat pkg/cli/LICENSE)" = 'old text' ]
}

@test "check: a missing copy fails, naming it" {
  list $'TRADEMARK.md\tpkg/cli/TRADEMARK.md'
  check
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'pkg/cli/TRADEMARK.md'* ]] || false
  [ ! -e pkg/cli/TRADEMARK.md ]
}

@test "check: a missing source fails, naming it" {
  list $'NOTICE\tpkg/cli/NOTICE'
  check
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'NOTICE'*'missing'* ]] || false
}

@test "check: every bad pair is reported, not just the first" {
  list $'LICENSE\ta/LICENSE' $'TRADEMARK.md\tb/TRADEMARK.md'
  check
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'a/LICENSE'* ]] || false
  [[ "${output}" == *'b/TRADEMARK.md'* ]] || false
}

@test "check: under CI=true the failure says to sync locally and goes to the step summary" {
  list $'LICENSE\tpkg/cli/LICENSE'
  check CI=true GITHUB_STEP_SUMMARY="${BATS_TEST_TMPDIR}/summary"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'locally'* ]] || false
  grep -q 'pkg/cli/LICENSE' "${BATS_TEST_TMPDIR}/summary"
}

@test "check: the list skips blank lines and comments" {
  cp LICENSE COPY
  list '# legal copies' '' $'LICENSE\tCOPY'
  check
  [ "${status}" -eq 0 ]
}

@test "list: a malformed line fails, naming the file and line" {
  local line
  for line in 'LICENSE pkg/LICENSE' $'LICENSE\t' $'\tpkg/LICENSE' $'LICENSE\ta\tb' \
    $'/etc/LICENSE\tpkg/LICENSE' $'LICENSE\t../LICENSE' $'LICENSE\tLICENSE'; do
    list '# header' "${line}"
    check
    [ "${status}" -eq 1 ] || { printf 'accepted: %q\n' "${line}"; return 1; }
    [[ "${output}" == *'config/legal-copies.local.txt:2:'* ]] || { printf 'unnamed: %q\n' "${line}"; return 1; }
    ensure
    [ "${status}" -eq 1 ] || { printf 'ensure accepted: %q\n' "${line}"; return 1; }
  done
}

@test "ensure: no list passes, writing nothing" {
  ensure
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'nothing to'* ]] || false
  [ -z "$(git status --porcelain -- pkg)" ]
}

@test "ensure: writes a missing copy and its directory, and fixes one that differs" {
  mkdir -p b
  printf 'old text\n' > b/TRADEMARK.md
  list $'LICENSE\ta/x/LICENSE' $'TRADEMARK.md\tb/TRADEMARK.md'
  ensure
  [ "${status}" -eq 0 ]
  cmp LICENSE a/x/LICENSE
  cmp TRADEMARK.md b/TRADEMARK.md
  [[ "${output}" == *'a/x/LICENSE'* ]] || false
  [[ "${output}" == *'b/TRADEMARK.md'* ]] || false
  check
  [ "${status}" -eq 0 ]
  ensure
  [ "${status}" -eq 0 ]
  [[ "${output}" != *'a/x/LICENSE'* ]] || false
}

@test "ensure: leaves a matching copy untouched" {
  cp -p LICENSE COPY
  touch -t 202001010000 COPY
  list $'LICENSE\tCOPY'
  ensure
  [ "${status}" -eq 0 ]
  [ "$(find COPY -newer LICENSE)" = '' ]
  [[ "${output}" != *'COPY'* ]] || false
}

@test "ensure: a missing source fails and writes no copy" {
  list $'LICENSE\ta/LICENSE' $'NOTICE\tb/NOTICE'
  ensure
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'NOTICE'*'missing'* ]] || false
  [ ! -e a/LICENSE ]
  [ ! -e b/NOTICE ]
}

@test "neither script names a repository's paths" {
  ! grep -n 'clisupport\|keel' "${STANDARDS}/scripts/check-legal-drift.sh" \
    "${STANDARDS}/scripts/ensure-legal-notices.sh" "${STANDARDS}/scripts/lib/legal-copies.sh"
}

@test "make audit runs check-legal-drift; ensure-legal-notices writes the tree" {
  run make -n -f "${STANDARDS}/templates/Makefile.canonical" audit
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'scripts/check-legal-drift.sh'* ]] || false
  run make -n -f "${STANDARDS}/templates/Makefile.canonical" ensure-legal-notices
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'run.sh --writable bash scripts/ensure-legal-notices.sh'* ]] || false
}

@test "the commit hook runs check-legal-drift" {
  grep -q '^  bash scripts/dev/run.sh bash scripts/check-legal-drift.sh$' "${STANDARDS}/scripts/run-pre-commit.sh"
}
