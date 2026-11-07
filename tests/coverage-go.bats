#!/usr/bin/env bats
# tests/coverage-go.bats
# scripts/test/coverage-go.sh with nothing to report: no coverage data, or only ignored files.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  WORK="${BATS_TEST_TMPDIR}/repo"
  mkdir -p "${WORK}" "${BATS_TEST_TMPDIR}/bin"
  cd "${WORK}"
  git init --quiet
  printf 'module example.com/x\n\ngo 1.27\n' > go.mod
  git add go.mod
  # The profile `go test -coverprofile` writes, from PROFILE_LINES.
  cat > "${BATS_TEST_TMPDIR}/bin/go" <<'GO'
#!/usr/bin/env bash
for arg in "$@"; do
  case "${arg}" in
    -coverprofile=*) printf 'mode: set\n%s' "${PROFILE_LINES:-}" > "${arg#-coverprofile=}" ;;
  esac
done
GO
  chmod +x "${BATS_TEST_TMPDIR}/bin/go"
  PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
}

@test "no coverage data: succeeds, reports one count of 0 files" {
  PROFILE_LINES='' run bash "${REPO_ROOT}/scripts/test/coverage-go.sh"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'(0 files)'* ]]
}

@test "only ignored files: succeeds, reports one count of 0 files" {
  PROFILE_LINES=$'example.com/x/cmd/x/main.go:1.1,2.2 1 1\n' run bash "${REPO_ROOT}/scripts/test/coverage-go.sh"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'(0 files)'* ]]
}

@test "a covered file: is counted" {
  PROFILE_LINES=$'example.com/x/lib.go:1.1,2.2 1 1\n' run bash "${REPO_ROOT}/scripts/test/coverage-go.sh"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'(1 files)'* ]]
}
