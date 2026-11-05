#!/usr/bin/env bats
# tests/run-sync-back.bats
# scripts/dev/run.sh sync_back.

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export REPO_ROOT
}

# sync_back: a writable run in a snapshot (a worktree or submodule mount) copies changed
# files back; a submodule entry in the snapshot is a directory, not a file, and is left to
# its own snapshot. scripts/dev/run.sh.
@test "run.sh sync_back copies changed files back and passes over submodule entries" {
  local -r work="${BATS_TEST_TMPDIR}" fn="${BATS_TEST_TMPDIR}/sync_back.sh"
  sed -n '/^function sync_back()/,/^}/p' "${REPO_ROOT}/scripts/dev/run.sh" > "${fn}"
  mkdir -p "${work}/snap/sub" "${work}/dir/sub"
  (
    cd "${work}/snap"
    git init --quiet
    printf 'new\n' > changed.txt
    git add changed.txt
    git update-index --add --cacheinfo "160000,$(printf '%040d' 1),sub"
  )
  printf 'old\n' > "${work}/dir/changed.txt"
  run bash -c "set -o errexit -o pipefail; log() { :; }; source '${fn}'; sync_back '${work}/snap' '${work}/dir'"
  [ "${status}" -eq 0 ]
  [ "$(cat "${work}/dir/changed.txt")" = 'new' ]
}
