#!/usr/bin/env bats
# tests/pypi-layout.bats
# The wheel installs its data inside the distribution's own package, keelcore_standards/, never at the top
# of site-packages: pyproject.toml maps governance/ and containers/dev/image.ref there with force-include.

setup() {
  PYPROJECT="${BATS_TEST_DIRNAME}/../pyproject.toml"
}

# wheel_section NAME: the lines of [tool.hatch.build.targets.wheel<NAME>] in pyproject.toml.
wheel_section() {
  awk -v want="[tool.hatch.build.targets.wheel${1}]" '/^\[/ { on = ($0 == want); next } on' "${PYPROJECT}"
}

@test "pyproject.toml: the wheel maps governance/ and the dev image pin under keelcore_standards/" {
  run wheel_section '.force-include'
  [[ "${output}" == *'"governance" = "keelcore_standards/governance"'* ]] || false
  [[ "${output}" == *'"containers/dev/image.ref" = "keelcore_standards/containers/dev/image.ref"'* ]] || false
}

@test "pyproject.toml: the wheel puts nothing at the top of site-packages" {
  run wheel_section ''
  [[ "${output}" != *'include'*'governance/'* ]] || false
}
