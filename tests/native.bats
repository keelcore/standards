#!/usr/bin/env bats
# tests/native.bats
# Native platforms: test binaries cross-built in the tool image, run on the native runner. What else
# a project builds and runs is its own hook.

setup() {
  load helpers-consumer
  consumer_setup
  track go.mod
}

@test "build-native.sh: rejects a platform it does not build" {
  run bash scripts/test/build-native.sh plan9 amd64
  [ "${status}" -ne 0 ]
}

@test "build-native.sh: runs the project's hook with the platform" {
  stub go 'case "${1}" in list) case "$*" in *"-f"*"{{.Dir}}"*) printf "%s/p\n" "${PWD}" ;; *"-f"*) printf "a_test.go" ;; *) printf "m/p\n" ;; esac ;; test) for ((i=1;i<=$#;i++)); do [ "${!i}" != -o ] || { j=$((i+1)); : > "${!j}"; }; done ;; esac'
  mkdir -p scripts/test
  printf 'printf "%%s\\n" "$*" > "%s/hook"\n' "${BATS_TEST_TMPDIR}" > scripts/test/build-native.local.sh
  run bash scripts/test/build-native.sh windows amd64
  [ "${status}" -eq 0 ]
  [ "$(cat "${BATS_TEST_TMPDIR}/hook")" = 'windows amd64 target/native/windows-amd64 .exe' ]
  grep -q '^p	tests/p.exe$' target/native/windows-amd64/tests.tsv
}

# go_stub DIR...: a go whose `go list ./...` prints m, m/a, ... (one per DIR, `.` the module root), whose
# `go list -f {{.Dir}} PKG` prints DIR's absolute path (or DIR itself when absolute), and whose
# `go test -c -o OUT` writes OUT.
go_stub() {
  local pkgs='' dirs='' d
  for d in "$@"; do
    case "${d}" in
      .) pkgs+='m\n' dirs+=' m) printf "%s\n" "${PWD}" ;;' ;;
      /*) pkgs+="m/${d##*/}\\n" dirs+=" m/${d##*/}) printf \"%s\\n\" \"${d}\" ;;" ;;
      *) pkgs+="m/${d}\\n" dirs+=" m/${d}) printf \"%s/${d}\\n\" \"\${PWD}\" ;;" ;;
    esac
  done
  stub go 'case "${1}" in list) case "$*" in *"{{.Dir}}"*) case "${@: -1}" in'"${dirs}"' esac ;; *"-f"*) printf "a_test.go" ;; *) printf "'"${pkgs}"'" ;; esac ;; test) for ((i=1;i<=$#;i++)); do [ "${!i}" != -o ] || { j=$((i+1)); : > "${!j}"; }; done ;; esac'
}

@test "build-native.sh: the module root package is recorded as ., not its absolute path" {
  go_stub .
  run bash scripts/test/build-native.sh windows amd64
  [ "${status}" -eq 0 ]
  [ "$(cat target/native/windows-amd64/tests.tsv)" = $'.\ttests/_root.exe' ]
  [ -f target/native/windows-amd64/tests/_root.exe ]
}

@test "build-native.sh: a root package and a subpackage get two distinct binaries" {
  go_stub . root
  run bash scripts/test/build-native.sh darwin arm64
  [ "${status}" -eq 0 ]
  [ "$(cat target/native/darwin-arm64/tests.tsv)" = $'.\ttests/_root\nroot\ttests/root' ]
}

@test "build-native.sh: a package outside the repository fails, naming it" {
  go_stub /elsewhere/q
  run bash scripts/test/build-native.sh windows amd64
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'/elsewhere/q'* ]] || false
}

@test "test-native.sh: a . row runs from the repository root" {
  local -r d=target/native/x
  mkdir -p "${d}/tests"
  printf '.\ttests/_root\n' > "${d}/tests.tsv"
  printf '#!/usr/bin/env bash\npwd -P > "%s/cwd"\nprintf -- "--- PASS: T (0s)\\n"\n' "${BATS_TEST_TMPDIR}" > "${d}/tests/_root"
  run bash scripts/test/test-native.sh "${d}"
  [ "${status}" -eq 0 ]
  [ "$(cat "${BATS_TEST_TMPDIR}/cwd")" = "$(pwd -P)" ]
  [[ "${output}" == *'Tests: 1 of 1 passed, 0 skipped'* ]]
}

@test "build-native.sh in the tool image: a real module's tests.tsv holds no absolute path" {
  [ -x /usr/local/bin/bats ] && command -v go > /dev/null || skip 'needs the tool image (go, /usr/local/bin/bats)'
  export GOCACHE="${BATS_TEST_TMPDIR}/gocache" GOFLAGS=-mod=mod
  rm -f go.mod
  go mod init example.com/fx > /dev/null 2>&1
  mkdir -p sub
  printf 'package fx\n\nimport "testing"\n\nfunc TestRoot(t *testing.T) {}\n' > fx_test.go
  printf 'package sub\n\nimport "testing"\n\nfunc TestSub(t *testing.T) {}\n' > sub/sub_test.go
  run bash scripts/test/build-native.sh windows amd64
  [ "${status}" -eq 0 ]
  local -r tsv=target/native/windows-amd64/tests.tsv
  [ "$(cat "${tsv}")" = $'.\ttests/_root.exe\nsub\ttests/sub.exe' ]
  ! grep -q $'^/\|\t/' "${tsv}"
  [ -s target/native/windows-amd64/tests/_root.exe ]
  [ -s target/native/windows-amd64/tests/sub.exe ]
}

@test "test-native.sh: reports N of N, and a failing package fails" {
  local -r d=target/native/x
  mkdir -p "${d}/tests" p q
  printf 'p\ttests/p\nq\ttests/q\n' > "${d}/tests.tsv"
  printf '#!/usr/bin/env bash\nprintf -- "--- PASS: T (0s)\\n"\n' > "${d}/tests/p"
  printf '#!/usr/bin/env bash\nprintf -- "--- FAIL: T (0s)\\n"; exit 1\n' > "${d}/tests/q"
  run bash scripts/test/test-native.sh "${d}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'Tests: 1 of 2 passed, 0 skipped'* ]]
}

@test "test-native-integrity.sh: runs the project's hook, with bats on PATH" {
  local -r d=target/native/x
  mkdir -p "${d}/bats/bin" "${d}/bats/libexec/bats-core" "${d}/bin" scripts/test
  : > "${d}/bats/bin/bats"
  printf 'command -v bats > "%s/where"\n' "${BATS_TEST_TMPDIR}" > scripts/test/test-native-integrity.local.sh
  run bash scripts/test/test-native-integrity.sh "${d}"
  [ "${status}" -eq 0 ]
  [[ "$(cat "${BATS_TEST_TMPDIR}/where")" == *"${d}/bats/bin/bats" ]]
}
