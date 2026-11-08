#!/usr/bin/env bats
# tests/ensure-container.bats
# Every canonical make target that runs in a tool image ensures its container runtime first: `make
# ensure-container` installs Apple container when it is missing and starts its system when it is stopped.
# A commit's hook uses no network: it fails when the runtime is missing or stopped, and starts nothing.

setup() {
  STANDARDS="$(cd "${BATS_TEST_DIRNAME}/.." && pwd -P)"
  SCRIPT="${STANDARDS}/scripts/ci/ensure-container.sh"
  LIB="${STANDARDS}/scripts/lib/container-system.sh"
  STUBS="${BATS_TEST_TMPDIR}/bin"
  CALLS="${BATS_TEST_TMPDIR}/calls"
  export CALLS STUBS
  export FAKE_OS='Darwin'
  unset KEELCORE_DEV_IMAGE
  mkdir -p "${STUBS}"
  : > "${CALLS}"
  stub uname 'if [ "${1}" = "-s" ]; then echo "${FAKE_OS}"; else echo arm64; fi'
  stub curl 'echo "curl $*" >> "${CALLS}"; exit 7'
  PATH="${STUBS}:$(path_without_container)"
}

# path_without_container: PATH minus any directory holding a real container, so no test can reach it.
path_without_container() {
  local dir kept=''
  while IFS= read -r dir; do
    [ -x "${dir}/container" ] || kept="${kept:+${kept}:}${dir}"
  done < <(tr ':' '\n' <<< "${PATH}")
  printf '%s' "${kept}"
}

stub() {
  printf '#!/usr/bin/env bash\n%s\n' "${2}" > "${STUBS}/${1}"
  chmod +x "${STUBS}/${1}"
}

# have_container: a container CLI whose system runs once ${STUBS}/running exists.
have_container() {
  stub container 'echo "container $*" >> "${CALLS}"
case "$*" in
  "system status") [ -f "${STUBS}/running" ] ;;
  "system start --enable-kernel-install") touch "${STUBS}/running" ;;
  "--version") echo "container CLI version 9.9.9" ;;
esac'
}

# hook_check: the commit hook's runtime check, as scripts/run-pre-commit.sh calls it.
hook_check() {
  run bash -c "log() { printf '%s\n' \"\${1}\"; }; source '${LIB}'; require_container_system"
}

@test "make: every canonical target that runs in a tool image ensures the container runtime first" {
  run awk '
    /^[a-zA-Z0-9_-]+:/ { header = $0; name = $1 }
    /scripts\/dev\/run\.sh/ && header !~ /\|.*ensure-container/ { print name }
  ' "${STANDARDS}/templates/Makefile.canonical"
  [ "${status}" -eq 0 ]
  [ -z "${output}" ] || { printf 'targets without | ensure-container:\n%s\n' "${output}"; return 1; }
}

@test "make: ensure-container runs scripts/ci/ensure-container.sh" {
  run make -n -f "${STANDARDS}/templates/Makefile.canonical" ensure-container
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'bash scripts/ci/ensure-container.sh'* ]] || false
}

@test "ensure-container: a stopped system is started, with its kernel" {
  have_container
  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ] || { echo "${output}"; return 1; }
  grep -qx 'container system start --enable-kernel-install' "${CALLS}"
}

@test "ensure-container: a running system is left as it is, with nothing fetched" {
  have_container
  touch "${STUBS}/running"
  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ] || { echo "${output}"; return 1; }
  ! grep -q '^container system start' "${CALLS}"
  ! grep -q '^curl' "${CALLS}"
}

@test "ensure-container: a missing container is installed by setup-apple-container" {
  run bash "${SCRIPT}"
  [ "${status}" -ne 0 ]
  grep -q '^curl .*api.github.com/repos/apple/container/releases/latest' "${CALLS}"
}

@test "ensure-container: a Linux host needs no Apple container" {
  have_container
  export FAKE_OS='Linux'
  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ] || { echo "${output}"; return 1; }
  ! grep -q '^container' "${CALLS}"
  ! grep -q '^curl' "${CALLS}"
}

@test "ensure-container: inside a tool image there is nothing to ensure" {
  have_container
  KEELCORE_DEV_IMAGE='ghcr.io/keelcore/x-dev:ctx-abc' run bash "${SCRIPT}"
  [ "${status}" -eq 0 ] || { echo "${output}"; return 1; }
  ! grep -q '^container' "${CALLS}"
}

@test "hook: a stopped system fails the check, and nothing is started or fetched" {
  have_container
  hook_check
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'make ensure-container'* ]] || false
  ! grep -q '^container system start' "${CALLS}"
  ! grep -q '^curl' "${CALLS}"
}

@test "hook: a missing container fails the check, and nothing is installed" {
  hook_check
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'make setup-apple-container'* ]] || false
  ! grep -q '^curl' "${CALLS}"
}

@test "hook: a running system passes the check" {
  have_container
  touch "${STUBS}/running"
  hook_check
  [ "${status}" -eq 0 ] || { echo "${output}"; return 1; }
}

@test "hook: run-pre-commit.sh checks the runtime before its first tool-image run" {
  local check first
  check="$(grep -n '^  require_container_system$' "${STANDARDS}/scripts/run-pre-commit.sh" | head -1 | cut -d: -f1)"
  first="$(grep -n 'scripts/dev/run.sh' "${STANDARDS}/scripts/run-pre-commit.sh" | grep -v '^[0-9]*:#' | head -1 | cut -d: -f1)"
  [ -n "${check}" ]
  [ "${check}" -lt "${first}" ]
}
