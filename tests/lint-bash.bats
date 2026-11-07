#!/usr/bin/env bats
# tests/lint-bash.bats
# lint-bash.sh also checks BATS files: a [[ … ]] that is a test's own statement, but not its last, must end
# with `|| false`, because bash does not always fail a test on a false [[ … ]] there.

setup() {
  load helpers-consumer
  consumer_setup
  printf '#!/usr/bin/env bash\necho ok\n' > tool.sh
  mkdir -p tests
  git add tool.sh
}

@test "lint-bash.sh: a mid-test [[ … ]] without || false fails, naming file and line" {
  printf '@test "x" {\n  run true\n  [[ "${output}" == a ]]\n  [ "${status}" -eq 0 ]\n}\n' > tests/bad.bats
  git add tests/bad.bats
  run bash scripts/lint/lint-bash.sh
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'tests/bad.bats:3'* ]] || false
}

@test "lint-bash.sh: a last-statement [[ … ]], one with || false, and heredoc text all pass" {
  printf '@test "y" {\n  [[ a == a ]] || false\n  cat <<EOF\n  [[ not code ]]\nEOF\n  if [[ a == a ]]; then :; fi\n  [[ a == a ]]\n}\n' > tests/good.bats
  git add tests/good.bats
  run bash scripts/lint/lint-bash.sh
  [ "${status}" -eq 0 ] || { echo "${output}"; return 1; }
}
