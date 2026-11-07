#!/usr/bin/env bats
# tests/setup-tools-in-image.bats
# These tools install in the dev image (Linux). On a Mac the setup script says so and installs
# nothing: make runs it through scripts/dev/run.sh.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  STUBS="${BATS_TEST_TMPDIR}/bin"
  CALLS="${BATS_TEST_TMPDIR}/calls"
  export CALLS
  mkdir -p "${STUBS}"
  printf '#!/usr/bin/env bash\nif [ "${1}" = "-s" ]; then echo Darwin; else echo arm64; fi\n' > "${STUBS}/uname"
  printf '#!/usr/bin/env bash\necho "brew $*" >> "${CALLS}"\n' > "${STUBS}/brew"
  chmod +x "${STUBS}/uname" "${STUBS}/brew"
}

@test "setup scripts: on a Mac each one points to the dev image and never uses Homebrew" {
  local tool
  for tool in grype helm kubeconform kubescape zizmor; do
    PATH="${STUBS}:${PATH}" run bash "${REPO_ROOT}/scripts/ci/setup-${tool}.sh"
    [ ! -e "${CALLS}" ]
    [ -z "$(grep brew "${REPO_ROOT}/scripts/ci/setup-${tool}.sh")" ]
    [ "${status}" -eq 0 ] || [[ "${output}" == *'dev image'* ]]
  done
}
