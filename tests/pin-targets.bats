#!/usr/bin/env bats
# tests/pin-targets.bats
# A tool pin is verified by installing it and, when the project has a scan target for that tool, by scanning
# with it: a scanner bump that changes findings fails before it is applied (scripts/lib/pin-targets.sh).

setup() {
  cd "${BATS_TEST_TMPDIR}"
  source "${BATS_TEST_DIRNAME}/../scripts/lib/pin-targets.sh"
}

@test "setup_verify_targets: the setup target, then lint-<tool> when the project has it" {
  printf 'setup-gosec:\n\t@true\nlint-gosec:\n\t@true\n' > Makefile
  run setup_verify_targets setup-gosec
  [ "${output}" = 'setup-gosec lint-gosec' ]
}

@test "setup_verify_targets: only the setup target when there is no scan target" {
  printf 'setup-cosign:\n\t@true\n' > Makefile
  run setup_verify_targets setup-cosign
  [ "${output}" = 'setup-cosign' ]
}
