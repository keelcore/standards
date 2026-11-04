#!/usr/bin/env bats
# tests/install-hooks.bats
# make install-hooks: core.hooksPath scripts/hooks resolves from the root of whichever working
# tree commits, so a clone, a worktree and a submodule checkout each run their own versioned
# scripts/hooks/pre-commit, which runs that tree's scripts/git_precommit.sh.

bats_require_minimum_version 1.5.0

setup() {
  STANDARDS="$(cd "${BATS_TEST_DIRNAME}/.." && pwd -P)"
  WORK="$(cd "${BATS_TEST_TMPDIR}" && pwd -P)"
  export GIT_CONFIG_GLOBAL="${WORK}/gitconfig"
  git config --global user.name t
  git config --global user.email t@example.invalid
  git config --global commit.gpgsign false
  git config --global protocol.file.allow always
  export HOOK_LOG="${WORK}/hook.log"
}

# hooked_repo DIR: a repository with the real hook and installer, and a git_precommit.sh that
# records the tree it ran in.
hooked_repo() {
  mkdir -p "${1}/scripts/hooks"
  cp "${STANDARDS}/scripts/hooks/pre-commit" "${1}/scripts/hooks/pre-commit"
  cp "${STANDARDS}/scripts/install-hooks.sh" "${1}/scripts/install-hooks.sh"
  printf '#!/usr/bin/env bash\ngit rev-parse --show-toplevel >> "${HOOK_LOG}"\n' > "${1}/scripts/git_precommit.sh"
  (cd "${1}" && git init --quiet && git add --all && git commit --quiet --no-verify -m init)
}

# commit_in DIR: commit a new file in DIR with hooks enabled.
commit_in() {
  (cd "${1}" && printf 'x\n' > "change-${RANDOM}" && git add --all && git commit --quiet -m change)
}

@test "install-hooks: sets core.hooksPath to scripts/hooks" {
  hooked_repo "${WORK}/repo"
  cd "${WORK}/repo"
  run bash scripts/install-hooks.sh
  [ "${status}" -eq 0 ]
  [ "$(git config --get core.hooksPath)" = 'scripts/hooks' ]
}

@test "install-hooks: a clone and its worktree each run their own tree's hook" {
  hooked_repo "${WORK}/repo"
  (cd "${WORK}/repo" && bash scripts/install-hooks.sh && git worktree add --quiet "${WORK}/wt")
  commit_in "${WORK}/repo"
  commit_in "${WORK}/wt"
  [ "$(cat "${HOOK_LOG}")" = "$(printf '%s\n%s' "${WORK}/repo" "${WORK}/wt")" ]
}

@test "install-hooks: a submodule checkout runs its own hook" {
  hooked_repo "${WORK}/std"
  mkdir -p "${WORK}/consumer"
  (cd "${WORK}/consumer" && git init --quiet && git submodule add --quiet "${WORK}/std" .standards \
    && git commit --quiet -m consumer)
  (cd "${WORK}/consumer/.standards" && bash scripts/install-hooks.sh)
  commit_in "${WORK}/consumer/.standards"
  [ "$(cat "${HOOK_LOG}")" = "${WORK}/consumer/.standards" ]
}
