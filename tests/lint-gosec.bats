#!/usr/bin/env bats
# tests/lint-gosec.bats
# lint-gosec.sh scans the repository's own Go modules (never .standards/ or another submodule), accepts the
# findings reviewed as false positives one site at a time (config/gosec-sites.local.txt), and fails on every
# other finding and on a listed site gosec no longer reports.

setup() {
  load helpers-consumer
  consumer_setup
  printf 'module example.com/m\n\ngo 1.22\n' > go.mod
  printf 'package main\n\nfunc main() {\n\tx := riskyCall()\n\t_ = x\n}\n' > main.go
  git add go.mod main.go
  # gosec stub: prints the issue list in GOSEC_ISSUES (gosec's JSON report).
  stub gosec 'printf "{\"Issues\": %s}\n" "${GOSEC_ISSUES:-[]}"'
  mkdir -p config
}

issue() { printf '{"rule_id":"%s","file":"%s/%s","line":"%s","details":"d"}' "${1}" "${WORK}" "${2}" "${3}"; }

@test "lint-gosec.sh: scans with JSON output, skipping .standards and vendor, with the excluded rules" {
  printf 'G304\n' > config/gosec.local.txt
  run bash scripts/lint/lint-gosec.sh
  [ "${status}" -eq 0 ] || { echo "${output}"; return 1; }
  calls_of gosec | grep -q -- '-fmt=json'
  calls_of gosec | grep -q -- '-exclude-dir=.standards'
  calls_of gosec | grep -q -- '-exclude-dir=vendor'
  calls_of gosec | grep -q -- '-exclude=G304'
}

@test "lint-gosec.sh: a listed site passes; the same rule elsewhere in the file fails, naming it" {
  printf 'G104\tmain.go\tx := riskyCall()\treviewed\n' > config/gosec-sites.local.txt
  GOSEC_ISSUES="[$(issue G104 main.go 4)]" run bash scripts/lint/lint-gosec.sh
  [ "${status}" -eq 0 ] || { echo "${output}"; return 1; }
  GOSEC_ISSUES="[$(issue G104 main.go 4),$(issue G104 main.go 5)]" run bash scripts/lint/lint-gosec.sh
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'G104 main.go:5'* ]] || false
}

@test "lint-gosec.sh: a listed site gosec no longer reports fails, naming the entry" {
  printf 'G104\tmain.go\tx := riskyCall()\treviewed\n' > config/gosec-sites.local.txt
  run bash scripts/lint/lint-gosec.sh
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'stale site'*'G104'*'main.go'* ]] || false
}

@test "lint-gosec.sh: an unlisted finding fails, naming rule, file and line" {
  GOSEC_ISSUES="[$(issue G402 main.go 4)]" run bash scripts/lint/lint-gosec.sh
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'G402 main.go:4'* ]] || false
}
