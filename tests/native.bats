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
