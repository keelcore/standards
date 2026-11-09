#!/usr/bin/env bats
# tests/release-tag.bats
# release_tag (scripts/lib/release-tag.sh), the one tag resolver of the canonical release scripts: INPUT_TAG
# when set (a manual run names its tag), else GITHUB_REF_NAME on a tag push; never a branch name.

bats_require_minimum_version 1.5.0

setup() {
  STANDARDS="$(cd "${BATS_TEST_DIRNAME}/.." && pwd -P)"
}

# tag_with VAR=VALUE...: release_tag with only those variables set.
tag_with() {
  run env -u INPUT_TAG -u GITHUB_REF_NAME -u GITHUB_REF_TYPE "$@" \
    bash -c "source '${STANDARDS}/scripts/lib/release-tag.sh' && release_tag"
}

@test "release_tag: a manual run's INPUT_TAG, though the run is on a branch" {
  tag_with GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main INPUT_TAG=v1.2.3
  [ "${status}" -eq 0 ]
  [ "${output}" = 'v1.2.3' ]
}

@test "release_tag: the tag of a tag push" {
  tag_with GITHUB_REF_TYPE=tag GITHUB_REF_NAME=v1.2.3
  [ "${status}" -eq 0 ]
  [ "${output}" = 'v1.2.3' ]
}

@test "release_tag: a branch run without INPUT_TAG fails, naming both variables, never the branch" {
  tag_with GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'INPUT_TAG'* ]] || false
  [[ "${output}" == *'GITHUB_REF_NAME'* ]] || false
  [[ "${output}" != 'main' ]] || false
}

@test "release_tag: nothing set fails" {
  tag_with
  [ "${status}" -ne 0 ]
}

@test "every canonical release script that resolves a tag uses release_tag" {
  cd "${STANDARDS}"
  local f bad=''
  for f in scripts/release/publish-go.sh scripts/release/publish-npm.sh scripts/release/wait-for-publish.sh; do
    grep -q 'source .*lib/release-tag.sh' "${f}" || bad+="${f}: does not source release-tag.sh"$'\n'
    ! grep -n 'resolve_tag' "${f}" > /dev/null || bad+="${f}: resolves the tag itself"$'\n'
  done
  ! git grep -n 'GITHUB_REF_NAME\|INPUT_TAG' -- 'scripts/release/*.sh' | grep -v '^scripts/release/wait-for-ci.sh:' \
    | grep -v ':#' > "${BATS_TEST_TMPDIR}/reads" || bad+="$(cat "${BATS_TEST_TMPDIR}/reads")"$'\n'
  [ -z "${bad}" ] || { printf '%s' "${bad}"; return 1; }
}

@test "publish.yml sets no GITHUB_* variable: GitHub ignores the assignment" {
  ! grep -nE '^ +GITHUB_[A-Z_]+:' "${STANDARDS}/.github/workflows/publish.yml"
}
