#!/usr/bin/env bats
# tests/go-tools.bats
# gosec, go-licenses and fuzzing run in every repo-owned Go module; a repo without the trait has
# nothing to do. Rule and license lists come from config.

setup() {
  load helpers-consumer
  consumer_setup
}

@test "lint-gosec.sh: no Go module, nothing to do" {
  stub gosec
  run bash scripts/lint/lint-gosec.sh
  [ "${status}" -eq 0 ]
  [ -z "$(calls_of gosec)" ]
}

@test "lint-gosec.sh: every module, without vendored ones; a finding fails" {
  track go.mod nested/go.mod vendor/d/go.mod
  stub gosec
  run bash scripts/lint/lint-gosec.sh
  [ "${status}" -eq 0 ]
  [ "$(calls_of gosec | wc -l)" -eq 2 ]
  stub gosec 'exit 1'
  run bash scripts/lint/lint-gosec.sh
  [ "${status}" -ne 0 ]
}

@test "lint-gosec.sh: excluded rules come from config" {
  track go.mod
  mkdir config
  printf 'G304\nG999\n' > config/gosec.local.txt
  stub gosec
  run bash scripts/lint/lint-gosec.sh
  calls_of gosec | grep -q -- '-exclude=G304,G999'
}

@test "lint-licenses.sh: the allow list comes from config" {
  track go.mod
  mkdir config
  printf 'WTFPL\n-ISC\n' > config/go-licenses.local.txt
  stub go-licenses
  run bash scripts/lint/lint-licenses.sh
  [ "${status}" -eq 0 ]
  local -r got="$(calls_of go-licenses)"
  [[ "${got}" == *'WTFPL'* ]] || false
  [[ "${got}" == *'Apache-2.0'* ]] || false
  [[ "${got}" != *'ISC'* ]]
}

@test "lint-licenses.sh: a module's own packages are not its dependencies" {
  printf 'module example.com/widget\n' > go.mod
  track go.mod
  stub go-licenses
  run bash scripts/lint/lint-licenses.sh
  [ "${status}" -eq 0 ]
  calls_of go-licenses | grep -q -- '--ignore=example.com/widget'
}

@test "lint-licenses.sh: no Go module, nothing to do" {
  stub go-licenses
  run bash scripts/lint/lint-licenses.sh
  [ "${status}" -eq 0 ]
  [ -z "$(calls_of go-licenses)" ]
}

@test "test-fuzz.sh: no fuzz targets, nothing to do" {
  track go.mod pkg/a_test.go
  stub go
  run bash scripts/test/test-fuzz.sh
  [ "${status}" -eq 0 ]
  [ -z "$(calls_of go)" ]
}

@test "test-fuzz.sh: each target of each package; vendored targets do not count" {
  track go.mod
  mkdir -p pkg/a vendor/x
  printf 'package a\nfunc FuzzOne(f *F) {}\nfunc FuzzTwo(f *F) {}\n' > pkg/a/a_test.go
  printf 'package x\nfunc FuzzVendored(f *F) {}\n' > vendor/x/x_test.go
  track pkg/a/a_test.go vendor/x/x_test.go
  stub go
  run bash scripts/test/test-fuzz.sh
  [ "${status}" -eq 0 ]
  [ "$(calls_of go | wc -l)" -eq 2 ]
  calls_of go | grep -q '\^FuzzOne\$'
  ! calls_of go | grep -q 'FuzzVendored'
}

@test "test-unit-go.sh: no Go module, nothing to do" {
  stub gotestsum
  run bash scripts/test/test-unit-go.sh
  [ "${status}" -eq 0 ]
  [ -z "$(calls_of gotestsum)" ]
}

@test "generate-coverage-profile.sh: the package filters come from config" {
  track go.mod
  mkdir config
  printf '/examples/\n' > config/go-test-exclude.local.txt
  printf '/pkg/\n' > config/go-coverpkg.local.txt
  stub go 'case "${1}" in
  list) printf "m/pkg/a\nm/cmd/b\nm/examples/c\n" ;;
  test) for a in "$@"; do case "${a}" in -coverprofile=*) printf "mode: atomic\n" > "${a#-coverprofile=}" ;; esac; done; cat > /dev/null ;;
  tool) printf "total: 100.0%%\n" ;;
esac'
  run bash scripts/test/generate-coverage-profile.sh target-coverage.txt
  [ "${status}" -eq 0 ]
  calls_of go | grep -q -- '-coverpkg=m/pkg/a'
}

@test "the tool image installs the moved Go tools, and the canonical targets run them" {
  local tool target
  for tool in gosec go-licenses gotestsum; do
    grep -q "scripts/ci/setup-${tool}.sh" "${STANDARDS}/containers/dev/Containerfile"
  done
  for target in lint-gosec lint-licenses test-fuzz test-unit generate-coverage-profile setup-gosec setup-go-licenses setup-gotestsum; do
    grep -qE "^${target}:" "${STANDARDS}/templates/Makefile.canonical"
    grep -qx ".PHONY: ${target}" "${STANDARDS}/templates/Makefile.canonical"
  done
}
