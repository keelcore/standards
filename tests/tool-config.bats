#!/usr/bin/env bats
# tests/tool-config.bats
# Tool settings: the default in .standards/config, a config/<name>.local.txt in the consumer. Lists
# merge: a line adds, and a -line removes. A local file is the repository's own.

setup() {
  load helpers-consumer
  consumer_setup
  source scripts/lib/tool-config.sh
}

@test "config_list: the default alone" {
  run config_list go-licenses
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'Apache-2.0'* ]]
}

@test "config_list: a local line adds, and a -line removes" {
  mkdir config
  printf '# ours\nWTFPL\n-MIT\n\n' > config/go-licenses.local.txt
  run config_list go-licenses
  [[ "${output}" == *'WTFPL'* ]]
  [[ "${output}" == *'Apache-2.0'* ]]
  [[ "${output}" != *'MIT'* ]]
  [[ "${output}" != *'#'* ]]
}

@test "config_list: no default and no local is empty, and not an error" {
  run config_list no-such-tool
  [ "${status}" -eq 0 ]
  [ -z "${output}" ]
}

@test "config_list: the standards repo reads its own config directory" {
  rm .standards
  mkdir config
  printf 'A\n' > config/x.txt
  run config_list x
  [ "${output}" = 'A' ]
}

@test "config_replace: the local file replaces the default whole" {
  mkdir config
  run config_replace kubeconform
  [[ "${output}" == *'1.28.0'* ]]
  printf '1.30.0\n' > config/kubeconform.local.txt
  run config_replace kubeconform
  [ "${output}" = '1.30.0' ]
}

@test "project_name: config, else the Go module's last part" {
  printf 'module github.com/acme/widget\n' > go.mod
  run project_name
  [ "${output}" = 'widget' ]
  mkdir config
  printf 'gadget\n' > config/project-name.local.txt
  run project_name
  [ "${output}" = 'gadget' ]
}
