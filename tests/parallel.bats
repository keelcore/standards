#!/usr/bin/env bats
# tests/parallel.bats
# scripts/lib/parallel.sh and the concurrent sign-release.sh, in a throwaway tree. A concurrency test uses
# a barrier: every job waits until all of them have started, which only concurrent jobs reach.

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export REPO_ROOT
}

setup() {
  WORK="${BATS_TEST_TMPDIR}/work"
  STATE="${BATS_TEST_TMPDIR}/state"
  export WORK STATE
  mkdir -p "${WORK}/scripts/release" "${WORK}/scripts/lib" "${WORK}/dist" "${WORK}/bin" "${STATE}/started"
  cp "${REPO_ROOT}/scripts/release/sign-release.sh" "${WORK}/scripts/release/"
  cp "${REPO_ROOT}/scripts/lib/parallel.sh" "${WORK}/scripts/lib/"
  cp "${REPO_ROOT}/scripts/lib/local-hook.sh" "${WORK}/scripts/lib/"
  cat > "${WORK}/bin/stub-lib" <<'LIB'
record() { printf '%s\n' "$*" >> "${STATE}/calls"; }
maybe_fail() { if [ -n "${FAIL_ON:-}" ] && [[ "$*" =~ ${FAIL_ON} ]]; then exit 1; fi; }
barrier() {
  : > "${STATE}/started/${1//[^A-Za-z0-9._-]/_}"
  local waited=0
  until [ "$(find "${STATE}/started" -type f | wc -l)" -ge "${2}" ]; do
    sleep 0.1
    waited=$(( waited + 1 ))
    [ "${waited}" -lt $(( BARRIER_TIMEOUT * 10 )) ] || { printf 'barrier timed out\n' >&2; exit 1; }
  done
}
LIB
  : > "${STATE}/calls"
  export PATH="${WORK}/bin:${PATH}"
  export BARRIER_TIMEOUT=30
  local flavor arch
  for flavor in max min fips; do
    for arch in amd64 arm64; do
      printf 'binary' > "${WORK}/dist/keel-${flavor}-linux-${arch}"
    done
  done
  cd "${WORK}"
}

call_count() { grep -cE "${1}" "${STATE}/calls" || true; }

# --- run_parallel ------------------------------------------------------------------------------

# A file sourcing the library, with one job function per test.
parallel_script() {
  cat > "${WORK}/job.sh" <<SCRIPT
#!/usr/bin/env bash
set -o nounset
set -o errexit
set -o pipefail
exec 5>&1
source scripts/lib/parallel.sh
${1}
SCRIPT
}

@test "run_parallel: jobs run concurrently" {
  parallel_script '
source bin/stub-lib
job() { barrier "${1}" 3; }
run_parallel job a b c
'
  run bash job.sh
  [ "${status}" -eq 0 ]
}

@test "run_parallel: each job gets its item, then the shared arguments" {
  parallel_script '
job() { printf "%s:%s:%s\n" "${1}" "${2}" "${3}"; }
run_parallel job a b -- x y
'
  run bash job.sh
  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = 'a:x:y' ]
  [ "${lines[1]}" = 'b:x:y' ]
}

@test "run_parallel: a failed job fails the call, after the others finish" {
  parallel_script '
job() {
  if [ "${1}" = bad ]; then exit 3; fi
  sleep 1
  printf "finished %s\n" "${1}"
}
run_parallel job bad good
printf "not reached\n"
'
  run bash job.sh
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'finished good'* ]]
  [[ "${output}" != *'not reached'* ]]
}

@test "run_parallel: a failing command stops its own job (errexit holds inside a job)" {
  parallel_script '
job() { false; printf "kept going\n"; }
run_parallel job a
'
  run bash job.sh
  [ "${status}" -ne 0 ]
  [[ "${output}" != *'kept going'* ]]
}

@test "run_parallel: output stays grouped by job, in the order given" {
  parallel_script '
job() {
  if [ "${1}" = a ]; then sleep 1; fi
  printf "%s one\n" "${1}"
  printf "%s two\n" "${1}" >&5
  printf "%s three\n" "${1}" >&2
}
run_parallel job a b
'
  run bash job.sh
  [ "${status}" -eq 0 ]
  [ "${lines[0]}" = 'a one' ]
  [ "${lines[1]}" = 'a two' ]
  [ "${lines[2]}" = 'a three' ]
  [ "${lines[3]}" = 'b one' ]
}

@test "run_parallel: calls nest" {
  parallel_script '
source bin/stub-lib
inner() { barrier "${1}" 4; }
outer() { run_parallel inner "${1}1" "${1}2"; }
run_parallel outer a b
'
  run bash job.sh
  [ "${status}" -eq 0 ]
}

# --- sign-release.sh -----------------------------------------------------------------------------------

stub_cosign() {
  cat > "${WORK}/bin/cosign" <<'COSIGN'
#!/usr/bin/env bash
source "${WORK}/bin/stub-lib"
record "cosign $*"
printf '%s\n' "${HOME}" >> "${STATE}/homes"
maybe_fail "cosign $*"
[ -z "${SIGN_BARRIER:-}" ] || [[ "${*: -1}" == *SHA256SUMS ]] || barrier "${*: -1}" "${SIGN_BARRIER}"
bundle=''
while [ "${#}" -gt 0 ]; do
  if [ "${1}" = '--bundle' ]; then bundle="${2}"; fi
  shift
done
: > "${bundle}"
COSIGN
  chmod +x "${WORK}/bin/cosign"
  rm -f dist/*.bundle dist/SHA256SUMS
}

@test "sign-release.sh: artifacts sign concurrently" {
  stub_cosign
  export SIGN_BARRIER=6
  run bash scripts/release/sign-release.sh --sums-dir dist dist/keel-*
  [ "${status}" -eq 0 ]
}

@test "sign-release.sh: concurrent signatures never share cosign's cache directory" {
  stub_cosign
  run bash scripts/release/sign-release.sh --sums-dir dist dist/keel-*
  [ "${status}" -eq 0 ]
  # Six concurrent signatures, each alone; SHA256SUMS signs afterwards, by itself, in the real HOME.
  [ "$(sort -u "${STATE}/homes" | wc -l)" -eq 7 ]
  [ "$(grep -cx "${HOME}" "${STATE}/homes")" -eq 1 ]
}

@test "sign-release.sh: SHA256SUMS covers every artifact and is signed last" {
  stub_cosign
  run bash scripts/release/sign-release.sh --sums-dir dist dist/keel-*
  [ "${status}" -eq 0 ]
  [ "$(wc -l < dist/SHA256SUMS)" -eq 6 ]
  [ -f dist/SHA256SUMS.bundle ]
  [ -f dist/keel-min-linux-arm64.bundle ]
  tail -1 "${STATE}/calls" | grep -q 'dist/SHA256SUMS$'
}

@test "sign-release.sh: a failed signature fails the step, and SHA256SUMS is not signed" {
  stub_cosign
  export FAIL_ON='cosign .*dist/keel-fips-linux-amd64$'
  run bash scripts/release/sign-release.sh --sums-dir dist dist/keel-*
  [ "${status}" -ne 0 ]
  [ ! -f dist/SHA256SUMS.bundle ]
}

@test "sign-release.sh: a missing artifact fails before anything is signed" {
  stub_cosign
  run bash scripts/release/sign-release.sh --sums-dir dist dist/keel-min-linux-amd64 dist/nope
  [ "${status}" -ne 0 ]
  [ "$(call_count '^cosign ')" -eq 0 ]
}
