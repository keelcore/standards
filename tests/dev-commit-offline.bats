#!/usr/bin/env bats
# tests/dev-commit-offline.bats
# A git commit never fetches and never stops for a missing image, so a new image can bootstrap:
# inside a hook, run.sh uses the pinned tool image when it is on the machine and otherwise skips
# that check, saying so. scripts/dev/pull.sh fetches the image outside any commit.

bats_require_minimum_version 1.5.0

setup() {
  STANDARDS="$(cd "${BATS_TEST_DIRNAME}/.." && pwd -P)"
  WORK="${BATS_TEST_TMPDIR}"
  CALLS="${WORK}/calls"
  REF="ghcr.io/keelcore/x-dev:ctx-old@sha256:$(printf '%064d' 7)"
  : > "${CALLS}"
  mkdir -p "${WORK}/repo/containers/x"
  : > "${WORK}/repo/containers/x/Containerfile"
  printf '%s\n' "${REF}" > "${WORK}/repo/containers/x/image.ref"
}

# hook_image_with PRESENT [PINNED_MATCHES] : dev_image inside a hook. PRESENT lists what is on the machine
# (a reference, or 1 for anything, 0 for nothing); the pin matches the tree unless PINNED_MATCHES=0.
# Every way of reaching the registry or building records itself in CALLS.
hook_image_with() {
  sed -n '/^function dev_image()/,/^}/p;/^function hook_image()/,/^}/p' "${STANDARDS}/scripts/dev/run.sh" \
    > "${WORK}/dev_image.sh"
  run bash -c "
    export KEELCORE_DEV_IN_HOOK=1
    log() { printf '%s\n' \"\${1}\" >&2; }
    runtime() { printf docker; }
    docker() { echo \"docker \$*\" >> '${CALLS}'; [ '${1}' = 1 ] || [ \"\${3}\" = '${1}' ]; }
    curl() { echo curl >> '${CALLS}'; }
    dev_containerfile() { printf 'containers/x/Containerfile'; }
    dev_has_base() { return 1; }
    dev_context_hash() { printf abc; }
    dev_pinned_ref() { [ '${2:-1}' = 1 ] && head -1 '${WORK}/repo/containers/x/image.ref'; }
    dev_ref_file() { printf 'containers/x/image.ref'; }
    dev_repo_name() { printf x; }
    dev_resolve_ref() { echo dev_resolve_ref >> '${CALLS}'; return 1; }
    build_image() { echo build_image >> '${CALLS}'; }
    source '${WORK}/dev_image.sh'
    dev_image '${WORK}/repo' x
  "
}

only_local_inspect() {
  [ -z "$(grep -vF 'image inspect' "${CALLS}")" ]
}

@test "hook: the pinned image on this machine is used, with nothing fetched or built" {
  hook_image_with 1
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"${REF}" ]]
  only_local_inspect
}

@test "hook: an absent image is reported with the fetch command, and nothing is fetched" {
  hook_image_with 0
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'make pull-dev-image'* ]]
  only_local_inspect
}

@test "hook: a stale pin's image is not used: its tools may not match this tree" {
  hook_image_with "${REF}" 0
  [ "${status}" -ne 0 ]
  [ -z "$(grep -E ' (pull|build) |^curl|^build_image' "${CALLS}")" ]
}

@test "hook: an image built locally for this tree is used" {
  hook_image_with 'keelcore-x-x:ctx-abc' 0
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'keelcore-x-x:ctx-abc' ]]
  [ -z "$(grep -E ' (pull|build) |^curl|^build_image' "${CALLS}")" ]
}

@test "hook: no pin is reported, with nothing fetched or built" {
  rm "${WORK}/repo/containers/x/image.ref"
  hook_image_with 0
  [ "${status}" -ne 0 ]
  [ -z "$(grep -E " (pull|build) |^curl|^build_image" "${CALLS}")" ]
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
  GIT_INDEX_FILE=x KEELCORE_DEV_IMAGE= PATH="${WORK}/bin:${PATH}" run bash "${STANDARDS}/scripts/dev/run.sh" touch "${WORK}/ran"
}

@test "commit: an absent image lets the commit proceed, skipping the check visibly, fetching nothing" {
  printf '%s\n' "${REF}" > "${WORK}/image.ref"
  mkdir -p "${WORK}/repo/containers/dev"
  cp "${WORK}/image.ref" "${WORK}/repo/containers/dev/image.ref"
  run_sh_in_hook
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'skipped'* ]]
  [ ! -e "${WORK}/ran" ]
  ! grep -qE ' (pull|build) |^curl ' "${CALLS}"
}

@test "commit: no pin (a new image) lets the commit proceed, skipping the check visibly" {
  run_sh_in_hook
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'skipped'* ]]
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
  PATH="${WORK}/bin:${PATH}" run bash "${STANDARDS}/scripts/dev/pull.sh"
  [ "${status}" -eq 0 ]
  grep -qE "^pull-tool image pull( --progress plain)? ${REF}\$" "${CALLS}"
  grep -qxF "$(printf '\tbash scripts/dev/pull.sh')" "${STANDARDS}/templates/Makefile.canonical"
}
