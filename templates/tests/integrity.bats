#!/usr/bin/env bats
# tests/integrity.bats
# Project-specific integrity tests for the built artifact.
# Per .standards/governance/testing.md: integrity tests run against the BUILT
# artifact (binary, image, package), not source. Skips when the artifact is
# missing so a fresh checkout produces a SKIP rather than a hard failure.
#
# Created by bootstrap-standards.sh template — REPLACE the BIN path and the
# example assertions with what makes sense for your project. Common patterns:
#   - Go:      BIN="${REPO_ROOT}/bin/<name>"
#   - Rust:    BIN="${REPO_ROOT}/target/release/<name>"
#   - Node:    BIN="${REPO_ROOT}/dist/<name>.js"
#   - Image:   skip + use a separate scripts/test/integrity-image.sh
# Replace assertions with smoke checks of the binary's documented surface
# (--help banner contents, version string, refusing unknown flags cleanly).

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}" && git rev-parse --show-toplevel)"
  # TODO: point BIN at your built artifact:
  BIN="${REPO_ROOT}/PATH/TO/YOUR/BINARY"
  if [ ! -x "${BIN}" ]; then
    skip "Built artifact not found at ${BIN}; build first (e.g. 'make release')"
  fi
}

@test "binary exists and is executable" {
  [ -x "${BIN}" ]
}

@test "binary accepts --help and exits cleanly" {
  run "${BIN}" --help
  [ "${status}" -eq 0 ]
}

@test "unknown flag produces a clean failure (no panic / stack trace)" {
  run "${BIN}" --not-a-real-flag-please
  [ "${status}" -ne 0 ]
  # Guard against language-specific stack traces leaking through:
  [[ "${output}" != *"panicked at"* ]]            # Rust
  [[ "${output}" != *"goroutine"* ]]              # Go runtime panic
  [[ "${output}" != *"Traceback (most recent"* ]] # Python (should not appear)
}
