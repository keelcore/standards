#!/usr/bin/env bats
# tests/dev-image-pin.bats
# containers/NAME/image.ref names the image built from a commit: repository:ctx-<hash>, the hash taken
# from what the commit holds, and written by the pre-commit hook with no network and no image.

setup() {
  STANDARDS="$(cd "${BATS_TEST_DIRNAME}/.." && pwd -P)"
  WORK="${BATS_TEST_TMPDIR}/standards"
  export GIT_CONFIG_GLOBAL="${BATS_TEST_TMPDIR}/gitconfig"
  git config --global user.name t
  git config --global user.email t@example.invalid
  git config --global commit.gpgsign false
  git config --global init.defaultBranch main
  mkdir -p "${WORK}/containers/dev" "${WORK}/scripts/ci" "${WORK}/scripts/dev" "${WORK}/scripts/lib" "${WORK}/.git-hooks"
  cd "${WORK}"
  git init --quiet
  cp "${STANDARDS}/scripts/dev/update-dev-image-ref.sh" scripts/dev/
  cp "${STANDARDS}/scripts/lib/dev-image.sh" scripts/lib/
  cp "${STANDARDS}/scripts/lib/progress.sh" scripts/lib/
  printf 'FROM scratch\nCOPY scripts/ci/setup-x.sh /x\n' > containers/dev/Containerfile
  printf 'one\n' > scripts/ci/setup-x.sh
  printf '#!/usr/bin/env bash\nexec bash scripts/dev/update-dev-image-ref.sh\n' > .git-hooks/pre-commit
  chmod +x .git-hooks/pre-commit
  git config core.hooksPath .git-hooks
  git add -A
  # Nothing here may reach the network.
  mkdir -p "${BATS_TEST_TMPDIR}/bin"
  printf '#!/usr/bin/env bash\necho "curl $*" >> "%s/curl.calls"\nexit 1\n' "${BATS_TEST_TMPDIR}" > "${BATS_TEST_TMPDIR}/bin/curl"
  chmod +x "${BATS_TEST_TMPDIR}/bin/curl"
  PATH="${BATS_TEST_TMPDIR}/bin:${PATH}"
}

# committed_ref: containers/dev/image.ref as committed at HEAD.
committed_ref() {
  git show HEAD:containers/dev/image.ref
}

# context_of: the expected reference for what the index holds now.
expected_ref() {
  local hash
  hash="$(bash -c "DEV_CONTEXT_STAGED=1; source scripts/lib/dev-image.sh; dev_context_hash . dev")"
  printf 'ghcr.io/keelcore/standards-dev:ctx-%s' "${hash}"
}

@test "a commit carries the name of its own image, with no digest and no network" {
  local -r want="$(expected_ref)"
  git commit --quiet -m first
  [ "$(committed_ref)" = "${want}" ]
  [ ! -e "${BATS_TEST_TMPDIR}/curl.calls" ]
}

@test "changing a tool moves the name in the same commit" {
  git commit --quiet -m first
  local -r before="$(committed_ref)"
  printf 'two\n' > scripts/ci/setup-x.sh
  git add scripts/ci/setup-x.sh
  git commit --quiet -m second
  [ "$(committed_ref)" != "${before}" ]
  [ "$(committed_ref)" = "$(expected_ref)" ]
}

@test "the name follows what is staged, not unstaged edits" {
  git commit --quiet -m first
  local -r before="$(committed_ref)"
  printf 'unstaged\n' > scripts/ci/setup-x.sh
  printf 'other\n' > other.txt
  git add other.txt
  git commit --quiet -m second
  [ "$(committed_ref)" = "${before}" ]
}

@test "a commit that changes no context writes nothing new" {
  git commit --quiet -m first
  printf 'other\n' > other.txt
  git add other.txt
  git commit --quiet -m second
  [ -z "$(git diff --name-only HEAD~1 HEAD -- containers)" ]
}

@test "a partial commit stages the name into the commit being made" {
  git commit --quiet -m first
  printf 'two\n' > scripts/ci/setup-x.sh
  printf 'other\n' > other.txt
  git add other.txt
  git commit --quiet -m second scripts/ci/setup-x.sh
  [ "$(committed_ref)" = "$(git show HEAD:containers/dev/image.ref)" ]
  [ -z "$(git show HEAD --name-only --format= | grep other.txt)" ]
  git show HEAD --name-only --format= | grep -qx 'containers/dev/image.ref'
}

@test "the hash does not depend on image.ref" {
  local -r before="$(expected_ref)"
  printf 'anything\n' > containers/dev/image.ref
  git add containers/dev/image.ref
  [ "$(expected_ref)" = "${before}" ]
}

@test "a Containerfile not yet staged writes nothing" {
  mkdir -p containers/new
  printf 'FROM scratch\n' > containers/new/Containerfile
  git commit --quiet -m first
  [ ! -e containers/new/image.ref ]
}

@test "make update-dev-image-ref runs the same script" {
  grep -qxF "$(printf '\tbash scripts/dev/update-dev-image-ref.sh')" "${STANDARDS}/templates/Makefile.canonical"
}
