#!/usr/bin/env bats
# tests/update-pins-verify-targets.bats
# update-pins.sh verify_targets: which make targets verify each kind of pin.

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export REPO_ROOT
}

# update-pins verifies every pin locally except what runs only on GitHub: an image pin (and
# any kind without a specific target) gets the project's combined run, which builds and runs
# what uses it; the Go toolchain is tested in the tool image on every host; only a runner
# label is left to CI. scripts/release/update-pins.sh verify_targets.
@test "update-pins verify_targets: local verification for every pin but runner labels" {
  local -r fn="${BATS_TEST_TMPDIR}/verify_targets.sh"
  sed -n '/^function verify_targets()/,/^}/p' "${REPO_ROOT}/scripts/release/update-pins.sh" > "${fn}"
  local kind want got
  for kind in image:COMBINED toolchain:test tool:COMBINED gotool:COMBINED npm:COMBINED \
    python:COMBINED pypi:COMBINED other:COMBINED runner:verify-on-ci action:audit gomod:test; do
    want="${kind#*:}"
    got="$(bash -c "
      LOCAL_HOOK=/nonexistent PLATFORM=Darwin
      make_target_for() { :; }
      has_target() { return 1; }
      combined_targets() { printf COMBINED; }
      source '${fn}'
      verify_targets '${kind%%:*}' name 'some/file:1'")"
    [ "${got}" = "${want}" ] || { echo "${kind%%:*}: '${got}', want '${want}'"; return 1; }
  done
}
