#!/usr/bin/env bats
# tests/tool-image-hooks.bats
# The tool-image scripts inside a git hook: a consumer's pre-commit hook runs with git's hook
# environment (GIT_INDEX_FILE=.git/index, relative to the consumer). Hashing the build context of the
# .standards submodule must give the same result as outside the hook, and the hook is recorded so
# run.sh never builds there. Also: audit Rule 6 (no runtime installs) and check-clean-tree.

bats_require_minimum_version 1.5.0

setup() {
  STANDARDS="$(cd "${BATS_TEST_DIRNAME}/.." && pwd -P)"
  WORK="${BATS_TEST_TMPDIR}"
  export GIT_CONFIG_GLOBAL="${WORK}/gitconfig"
  git config --global user.name t
  git config --global user.email t@example.invalid
  git config --global commit.gpgsign false
  git config --global protocol.file.allow always
}

# standards_repo: a minimal .standards with a dev image context.
standards_repo() {
  mkdir -p "${WORK}/std/containers/dev" "${WORK}/std/scripts/ci"
  (
    cd "${WORK}/std"
    git init --quiet
    printf 'FROM scratch\nCOPY scripts/ci/setup-x.sh /x\n' > containers/dev/Containerfile
    printf '#!/usr/bin/env bash\n' > scripts/ci/setup-x.sh
    git add --all && git commit --quiet -m std
  )
}

# consumer_repo: a repository with the standards repo as its .standards submodule.
consumer_repo() {
  mkdir -p "${WORK}/consumer"
  (
    cd "${WORK}/consumer"
    git init --quiet
    git submodule add --quiet "${WORK}/std" .standards
    git commit --quiet -m consumer
  )
}

# hash_in DIR: the dev context hash of DIR/.standards, computed from DIR.
hash_in() {
  (cd "${1}" && bash -c "source '${STANDARDS}/scripts/lib/dev-image.sh'; dev_context_hash .standards dev")
}

@test "hook: GIT_INDEX_FILE from the consumer leaves the submodule's context hash unchanged" {
  standards_repo
  consumer_repo
  local plain hooked
  plain="$(hash_in "${WORK}/consumer")"
  hooked="$(cd "${WORK}/consumer" && GIT_INDEX_FILE=.git/index bash -c \
    "source '${STANDARDS}/scripts/lib/dev-image.sh'; dev_context_hash .standards dev")"
  [ -n "${plain}" ]
  [ "${hooked}" = "${plain}" ]
}

@test "hook: the versioned pre-commit hook records the hook context for run.sh" {
  mkdir -p "${WORK}/hooked/scripts/hooks"
  cp "${STANDARDS}/scripts/hooks/pre-commit" "${WORK}/hooked/scripts/hooks/"
  printf 'printf "%%s" "${KEELCORE_DEV_IN_HOOK:-none}"\n' > "${WORK}/hooked/scripts/run-pre-commit.sh"
  cd "${WORK}/hooked"
  git init --quiet
  run env -u KEELCORE_DEV_IN_HOOK bash scripts/hooks/pre-commit
  [ "${output}" = 1 ]
}

@test "hook: dev-image.sh drops the hook's GIT_INDEX_FILE, unless its caller imported it, and infers no hook" {
  run bash -c "export GIT_INDEX_FILE=.git/index; source '${STANDARDS}/scripts/lib/dev-image.sh'; \
    printf '%s|%s' \"\${GIT_INDEX_FILE:-unset}\" \"\${KEELCORE_DEV_IN_HOOK:-none}\""
  [ "${output}" = 'unset|none' ]
  run bash -c "declare -rx GIT_INDEX_FILE=/x/index; source '${STANDARDS}/scripts/lib/dev-image.sh'; \
    printf '%s' \"\${GIT_INDEX_FILE}\""
  [ "${status}" -eq 0 ]
  [ "${output}" = /x/index ]
}

# audit_fixture: a repository whose workflows the Rule 6 functions read.
audit_fixture() {
  mkdir -p "${WORK}/audit/.github/workflows"
  printf 'jobs:\n  lint:\n    steps:\n      - run: make lint\n  k8s:\n    steps:\n      - run: make setup-helm\n  codeql:\n    steps:\n      - uses: actions/setup-go@0000000000000000000000000000000000000000  # v5\n' \
    > "${WORK}/audit/.github/workflows/ci.yml"
  sed -n '/^function check_runtime_installs/,/^}/p; /^function runtime_install_steps/,/^}/p' \
    "${STANDARDS}/scripts/ci/audit.sh" > "${WORK}/rule6.sh"
}

# rule6 DIR: run audit Rule 6 against DIR.
rule6() {
  run bash -c "REPO_ROOT='${1}'; WORKFLOWS_DIR='${1}/.github/workflows'; log() { printf '%s\n' \"\$1\"; }; \
    source '${WORK}/rule6.sh'; check_runtime_installs"
}

@test "audit Rule 6: setup actions and setup targets in workflows are findings" {
  audit_fixture
  rule6 "${WORK}/audit"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'.github/workflows/ci.yml:k8s: run: make setup-helm'* ]] || false
  [[ "${output}" == *'.github/workflows/ci.yml:codeql: uses: actions/setup-go'* ]] || false
  [[ "${output}" != *':lint:'* ]] || false
}

@test "audit Rule 6: a job listed in .runtime-install-exceptions passes" {
  audit_fixture
  printf '.github/workflows/ci.yml:k8s  helm drives the kind cluster on the runner\n.github/workflows/ci.yml:codeql  # autobuild needs Go on the runner\n' \
    > "${WORK}/audit/.runtime-install-exceptions"
  rule6 "${WORK}/audit"
  [ "${status}" -eq 0 ]
}

@test "check-clean-tree: a clean checkout passes; a changed or new file fails and is named" {
  standards_repo
  cd "${WORK}/std"
  run bash "${STANDARDS}/scripts/ci/check-clean-tree.sh"
  [ "${status}" -eq 0 ]
  printf 'x\n' >> containers/dev/Containerfile
  printf 'new\n' > stray.txt
  run bash "${STANDARDS}/scripts/ci/check-clean-tree.sh"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'containers/dev/Containerfile'* ]] || false
  [[ "${output}" == *'stray.txt'* ]] || false
}
