#!/usr/bin/env bats
# tests/helm-tools.bats
# Helm lint, schema validation and policy scan run on every repo-owned chart, with arguments, renders
# and allowed controls from config; a repo with no chart has nothing to do.

setup() {
  load helpers-consumer
  consumer_setup
  stub helm
  stub kubeconform
  stub kubescape 'for (( i = 1; i <= $#; i++ )); do [ "${!i}" != --output ] || { j=$((i+1)); cp "${KUBESCAPE_RESULT}" "${!j}"; }; done'
  KUBESCAPE_RESULT="${BATS_TEST_TMPDIR}/result.json"
  export KUBESCAPE_RESULT
  printf '{"summaryDetails":{"controls":{"C-1":{"status":"failed"},"C-2":{"status":"passed"}}}}' > "${KUBESCAPE_RESULT}"
}

@test "no chart: all three have nothing to do" {
  local s
  for s in lint-helm lint-helm-validate lint-helm-policy; do
    run bash "scripts/lint/${s}.sh"
    [ "${status}" -eq 0 ]
  done
  [ -z "$(cat "${CALLS}")" ]
}

@test "lint-helm.sh: lints every chart, with config's arguments; a vendored chart does not count" {
  track chart/a/Chart.yaml other/Chart.yaml vendor/x/Chart.yaml
  mkdir config
  printf -- '--set\nmode=sidecar\n' > config/helm-args.local.txt
  run bash scripts/lint/lint-helm.sh
  [ "${status}" -eq 0 ]
  [ "$(calls_of helm | wc -l)" -eq 2 ]
  calls_of helm | grep -q 'lint chart/a --set mode=sidecar'
}

@test "lint-helm-validate.sh: the Kubernetes version comes from config" {
  track c/Chart.yaml
  mkdir config
  printf '1.31.0\n' > config/kubeconform.local.txt
  run bash scripts/lint/lint-helm-validate.sh
  [ "${status}" -eq 0 ]
  calls_of kubeconform | grep -q -- '-kubernetes-version 1.31.0'
}

@test "lint-helm-policy.sh: a failed control outside the allowed list fails" {
  track c/Chart.yaml
  run bash scripts/lint/lint-helm-policy.sh
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'C-1'* ]]
}

@test "lint-helm-policy.sh: each configured render has its own arguments and allowed controls" {
  track c/Chart.yaml
  mkdir config
  printf 'library\t--set mode=library\tC-1 C-9\nsidecar\t-f v.yaml\tC-1\n' > config/helm-policy.local.txt
  run bash scripts/lint/lint-helm-policy.sh
  [ "${status}" -eq 0 ]
  calls_of helm | grep -q -- '--set mode=library'
  calls_of helm | grep -q -- '-f v.yaml'
  printf 'library\t--set mode=library\tC-9\n' > config/helm-policy.local.txt
  run bash scripts/lint/lint-helm-policy.sh
  [ "${status}" -ne 0 ]
}

@test "the tool image installs the Helm tools, and the canonical targets run them" {
  local tool target
  for tool in helm kubeconform kubescape; do
    grep -q "scripts/ci/setup-${tool}.sh" "${STANDARDS}/containers/dev/Containerfile"
  done
  for target in lint-helm lint-helm-validate lint-helm-policy setup-helm setup-kubeconform setup-kubescape; do
    grep -qE "^${target}:" "${STANDARDS}/templates/Makefile.canonical"
  done
}
