#!/usr/bin/env bats
# tests/dev-commit-offline.bats
# A git commit never fetches and never stops for a missing image, so a new image can bootstrap:
# inside a hook, run.sh uses the pinned tool image when it is on the machine and otherwise skips
# that check, saying so. scripts/dev/pull-dev-image.sh fetches the image outside any commit.

bats_require_minimum_version 1.5.0

setup() {
  STANDARDS="$(cd "${BATS_TEST_DIRNAME}/.." && pwd -P)"
  WORK="${BATS_TEST_TMPDIR}"
  CALLS="${WORK}/calls"
  REF='ghcr.io/keelcore/x-dev:ctx-abc'
  : > "${CALLS}"
  mkdir -p "${WORK}/repo/containers/x"
  : > "${WORK}/repo/containers/x/Containerfile"
  printf '%s\n' "${REF}" > "${WORK}/repo/containers/x/image.ref"
}

# hook_image_with PRESENT: dev_image inside a hook. PRESENT is what is on the machine: a reference, or
# 0 for nothing.
# Every way of reaching the registry or building records itself in CALLS.
hook_image_with() {
  sed -n '/^function dev_image()/,/^}/p;/^function hook_image()/,/^}/p' "${STANDARDS}/scripts/dev/run.sh" \
    > "${WORK}/dev_image.sh"
  run bash -c "
    export KEELCORE_DEV_IN_HOOK=1
    log() { printf '%s\n' \"\${1}\" >&2; }
    runtime() { printf docker; }
    docker() { echo \"docker \$*\" >> '${CALLS}'; [ \"\${3}\" = '${1}' ]; }
    curl() { echo curl >> '${CALLS}'; }
    dev_containerfile() { printf 'containers/x/Containerfile'; }
    dev_base_ref() { :; }
    dev_tree_hash() { printf abc; }
    dev_pin_ref() { printf ghcr.io/keelcore/x-dev:ctx-abc; }
    dev_repository() { printf ghcr.io/keelcore/x-dev; }
    dev_repo_name() { printf x; }
    dev_published_ref() { echo dev_published_ref >> '${CALLS}'; return 1; }
    build_image() { echo build_image >> '${CALLS}'; }
    source '${WORK}/dev_image.sh'
    dev_image '${WORK}/repo' x
  "
}

only_local_inspect() {
  [ -z "$(grep -vF 'image inspect' "${CALLS}")" ]
}

@test "hook: the image this context names, on this machine, is used, with nothing fetched or built" {
  hook_image_with "${REF}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"${REF}" ]] || false
  only_local_inspect
}

@test "hook: an absent image is reported with the fetch command, and nothing is fetched" {
  hook_image_with 0
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'make pull-dev-image'* ]] || false
  only_local_inspect
}

@test "hook: an image built locally for this tree is used" {
  hook_image_with 'keelcore-x-x:ctx-abc'
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'keelcore-x-x:ctx-abc' ]] || false
  [ -z "$(grep -E ' (pull|build) |^curl|^build_image' "${CALLS}")" ]
}

# run_sh_in_hook: scripts/dev/run.sh as a commit's hook runs it, in a repository at WORK/repo whose
# dev image is absent. The command records itself if it runs.
run_sh_in_hook() {
  mkdir -p "${WORK}/bin" "${WORK}/repo/containers/dev"
  printf 'FROM scratch\n' > "${WORK}/repo/containers/dev/Containerfile"
  for tool in container docker curl; do
    printf '#!/usr/bin/env bash\necho "%s $*" >> "%s"\nexit 1\n' "${tool}" "${CALLS}" > "${WORK}/bin/${tool}"
    chmod +x "${WORK}/bin/${tool}"
  done
  cd "${WORK}/repo"
  git init --quiet
  KEELCORE_DEV_IN_HOOK=1 KEELCORE_DEV_IMAGE= PATH="${WORK}/bin:${PATH}" run bash "${STANDARDS}/scripts/dev/run.sh" touch "${WORK}/ran"
}

@test "commit: an absent image lets the commit proceed, skipping the check visibly, fetching nothing" {
  printf '%s\n' "${REF}" > "${WORK}/image.ref"
  mkdir -p "${WORK}/repo/containers/dev"
  cp "${WORK}/image.ref" "${WORK}/repo/containers/dev/image.ref"
  run_sh_in_hook
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'skipped'* ]] || false
  [ ! -e "${WORK}/ran" ]
  ! grep -qE ' (pull|build) |^curl ' "${CALLS}"
}

@test "commit: a new image with no ref yet lets the commit proceed, skipping the check visibly" {
  run_sh_in_hook
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'skipped'* ]] || false
  [ ! -e "${WORK}/ran" ]
  ! grep -qE ' (pull|build) |^curl ' "${CALLS}"
}

@test "make pull-dev-image: pulls the pinned dev image outside any commit" {
  mkdir -p "${WORK}/bin" "${WORK}/repo/containers/dev"
  printf '%s\n' "${REF}" > "${WORK}/repo/containers/dev/image.ref"
  for tool in container docker; do
    printf '#!/usr/bin/env bash\necho "pull-tool $*" >> "%s"\n' "${CALLS}" > "${WORK}/bin/${tool}"
    chmod +x "${WORK}/bin/${tool}"
  done
  cd "${WORK}/repo"
  PATH="${WORK}/bin:${PATH}" run bash "${STANDARDS}/scripts/dev/pull-dev-image.sh"
  [ "${status}" -eq 0 ]
  grep -qE "^pull-tool image pull( --progress plain)? ${REF}\$" "${CALLS}"
  grep -qxF "$(printf '\tbash scripts/dev/pull-dev-image.sh')" "${STANDARDS}/templates/Makefile.canonical"
}
