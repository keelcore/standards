#!/usr/bin/env bats
# tests/run-sync-back.bats
# scripts/dev/run.sh snapshots of a worktree or submodule: each run has its own, and a writable run
# copies back only what its command changed, never replacing newer work in the tree.

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export REPO_ROOT
}

# snap_and_dir: a snapshot holding a.txt and b.txt as committed-and-indexed, and a matching tree.
snap_and_dir() {
  WORK="${BATS_TEST_TMPDIR}"
  mkdir -p "${WORK}/snap" "${WORK}/dir"
  printf 'old\n' > "${WORK}/snap/a.txt"
  printf 'old\n' > "${WORK}/snap/b.txt"
  git -C "${WORK}/snap" init --quiet
  git -C "${WORK}/snap" add -A
  cp "${WORK}/snap/a.txt" "${WORK}/snap/b.txt" "${WORK}/dir/"
}

sync_back_run() {
  sed -n '/^function sync_back()/,/^}/p' "${REPO_ROOT}/scripts/dev/run.sh" > "${WORK}/sync_back.sh"
  run bash -c "set -o errexit -o pipefail; log() { printf '%s\n' \"\$1\"; }; source '${WORK}/sync_back.sh'; sync_back '${WORK}/snap' '${WORK}/dir'"
}

@test "sync_back: copies what the command changed, and a file it created" {
  snap_and_dir
  printf 'new\n' > "${WORK}/snap/a.txt"
  printf 'made\n' > "${WORK}/snap/made.txt"
  sync_back_run
  [ "${status}" -eq 0 ]
  [ "$(cat "${WORK}/dir/a.txt")" = 'new' ]
  [ "$(cat "${WORK}/dir/made.txt")" = 'made' ]
}

@test "sync_back: a file the command did not change is left alone, whatever the tree holds" {
  snap_and_dir
  printf 'my edit\n' > "${WORK}/dir/b.txt"
  sync_back_run
  [ "${status}" -eq 0 ]
  [ "$(cat "${WORK}/dir/b.txt")" = 'my edit' ]
}

@test "sync_back: a file edited in the tree since the snapshot keeps the edit, and says so" {
  snap_and_dir
  printf 'formatted\n' > "${WORK}/snap/a.txt"
  printf 'my edit\n' > "${WORK}/dir/a.txt"
  sync_back_run
  [ "${status}" -eq 0 ]
  [ "$(cat "${WORK}/dir/a.txt")" = 'my edit' ]
  [[ "${output}" == *'a.txt'*'kept'* ]]
}

@test "sync_back: passes over a submodule entry" {
  snap_and_dir
  mkdir -p "${WORK}/snap/sub" "${WORK}/dir/sub"
  git -C "${WORK}/snap" update-index --add --cacheinfo "160000,$(printf '%040d' 1),sub"
  sync_back_run
  [ "${status}" -eq 0 ]
}

@test "sync_back: replaces a file without writing into it, so a running script survives" {
  snap_and_dir
  printf 'new\n' > "${WORK}/snap/a.txt"
  local -r before="$(ls -i "${WORK}/dir/a.txt" | awk '{print $1}')"
  sync_back_run
  [ "$(ls -i "${WORK}/dir/a.txt" | awk '{print $1}')" != "${before}" ]
}

# worktree_run ARGS...: run.sh in a git worktree, whose .git is a file, with a fake runtime that runs
# the command in the mounted snapshot.
worktree_run() {
  WORK="${BATS_TEST_TMPDIR}"
  REPO_NAME="runsnap-$$-${RANDOM}"
  REPO="${WORK}/${REPO_NAME}"
  mkdir -p "${WORK}/bin" "${REPO}/containers/dev"
  cat > "${WORK}/bin/docker" <<'FAKE'
#!/usr/bin/env bash
[ "${1}" = 'run' ] || exit 0
while [ "${#}" -gt 0 ]; do
  case "${1}" in
    -v) case "${2}" in *:/work:*) mount="${2%%:*}" ;; esac; shift 2 ;;
    -w | -e | -m) shift 2 ;;
    ghcr.io/*) shift; break ;;
    *) shift ;;
  esac
done
cd "${mount}" && "$@"
FAKE
  chmod +x "${WORK}/bin/docker"
  cp "${WORK}/bin/docker" "${WORK}/bin/container"
  printf 'FROM scratch\n' > "${REPO}/containers/dev/Containerfile"
  printf 'a\n' > "${REPO}/a.txt"
  git -C "${REPO}" init --quiet
  git -C "${REPO}" add -A
  git -C "${REPO}" -c user.name=t -c user.email=t@example.invalid commit --quiet -m x
  git -C "${REPO}" worktree add --quiet --detach "${WORK}/wt" HEAD
  cd "${WORK}/wt"
  printf 'edited\n' > a.txt
  local hash
  hash="$(bash -c "source '${REPO_ROOT}/scripts/lib/dev-image.sh'; dev_context_hash . dev")"
  printf 'ghcr.io/keelcore/x-dev:ctx-%s@sha256:0\n' "${hash}" > containers/dev/image.ref
  PATH="${WORK}/bin:${PATH}"
}

@test "run.sh: a writable run in a worktree keeps unrelated edits and removes its snapshot" {
  worktree_run
  printf 'mine\n' > mine.txt
  run bash "${REPO_ROOT}/scripts/dev/run.sh" --writable sh -c 'printf done > out.txt'
  [ "${status}" -eq 0 ]
  [ "$(cat a.txt)" = 'edited' ]
  [ "$(cat mine.txt)" = 'mine' ]
  [ "$(cat out.txt)" = 'done' ]
  [ -z "$(ls -d "/tmp/keelcore-dev-snapshot/${REPO_NAME}-"* 2> /dev/null)" ]
}

@test "run.sh: a run starting during a writable run does not revert the tree" {
  worktree_run
  bash "${REPO_ROOT}/scripts/dev/run.sh" --writable sh -c "touch '${WORK}/started'; until [ -f '${WORK}/go' ]; do sleep 0.1; done; printf done > out.txt" &
  local -r first="${!}"
  until [ -f "${WORK}/started" ]; do sleep 0.1; done
  run bash "${REPO_ROOT}/scripts/dev/run.sh" sh -c 'true'
  [ "${status}" -eq 0 ]
  touch "${WORK}/go"
  wait "${first}"
  [ "$(cat a.txt)" = 'edited' ]
  [ "$(cat out.txt)" = 'done' ]
}
