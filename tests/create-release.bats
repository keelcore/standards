#!/usr/bin/env bats
# tests/create-release.bats
# Integration tests for the canonical scripts/release/create-release.sh driver
# and the keelcore/standards CHANGELOG hook (create-release.local.sh).
#
# Every test runs in a throwaway repo under BATS_TEST_TMPDIR: a work clone, a
# local bare remote, an isolated git config (GIT_CONFIG_GLOBAL) and a throwaway
# SSH signing key. Nothing touches a real remote, the developer's git config or
# the standards repo's own tags. Approval answers come from a file via
# CREATE_RELEASE_TTY.

bats_require_minimum_version 1.5.0

setup() {
  STANDARDS="$(cd "${BATS_TEST_DIRNAME}/.." && pwd -P)"
  DRIVER="${STANDARDS}/scripts/release/create-release.sh"
  STD_HOOK="${STANDARDS}/scripts/release/create-release.local.sh"
  FIXTURE_HOOK="${STANDARDS}/tests/fixtures/create-release/hook.sh"
  T="${BATS_TEST_TMPDIR}"
  export GIT_CONFIG_GLOBAL="${T}/gitconfig"
  export GIT_CONFIG_NOSYSTEM=1
  export CREATE_RELEASE_TTY="${T}/answer"
  export HOOK_ARGS_FILE="${T}/hook_args"
  printf 'y\n' > "${CREATE_RELEASE_TTY}"
  configure_git
  init_repos
}

configure_git() {
  ssh-keygen -q -t ed25519 -N '' -C 'release-test' -f "${T}/signing_key"
  printf 'tester@example.invalid %s\n' "$(cat "${T}/signing_key.pub")" > "${T}/allowed_signers"
  git config --global user.name 'Release Tester'
  git config --global user.email 'tester@example.invalid'
  git config --global init.defaultBranch main
  git config --global gpg.format ssh
  git config --global user.signingkey "${T}/signing_key"
  git config --global gpg.ssh.allowedSignersFile "${T}/allowed_signers"
}

init_repos() {
  git init --quiet --bare "${T}/remote.git"
  git init --quiet "${T}/work"
  cd "${T}/work"
  git remote add origin "${T}/remote.git"
  commit_file README.md 'initial'
  git push --quiet -u origin main
}

commit_file() {
  printf '%s\n' "${2}" >> "${1}"
  git add "${1}"
  git commit --quiet -m "${2}"
}

commit_and_push() {
  commit_file "${1}" "${2}"
  git push --quiet
}

tag_and_push() {
  git tag -a "${1}" -m "${1}"
  git push --quiet origin "${1}"
}

install_hook() {
  mkdir -p scripts/release
  cp "${1}" scripts/release/create-release.local.sh
  git add scripts/release/create-release.local.sh
  git commit --quiet -m 'add release hook'
  git push --quiet
}

# A release-ready repo: hook installed, tagged at <tag>, one commit after it.
ready_at() {
  install_hook "${FIXTURE_HOOK}"
  tag_and_push "${1}"
  commit_and_push CHANGES 'change after tag'
}

tag_count() {
  git tag -l | wc -l | tr -d ' '
}

remote_has_tag() {
  [ -n "$(git ls-remote --tags origin "refs/tags/${1}")" ]
}

remote_lacks_tag() {
  [ -z "$(git ls-remote --tags origin "refs/tags/${1}")" ]
}

# ---------------------------------------------------------------------------
# Default (no hook) and hook resolution
# ---------------------------------------------------------------------------

@test "no hook: patch bump with the default subject" {
  tag_and_push v0.1.0
  commit_and_push CHANGES 'change after tag'
  run bash "${DRIVER}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'defaulting to a patch bump'* ]] || false
  [ "$(git tag -l --format='%(contents:subject)' v0.1.1)" = 'patch: release v0.1.1' ]
}

@test "no hook in the released repo: the standards repo's own hook is not used" {
  tag_and_push v1.0.0
  commit_and_push CHANGES 'change after tag'
  run bash "${DRIVER}" --dry-run
  [ "${status}" -eq 0 ]
  [[ "${output}" != *'CHANGELOG'* ]] || false
  [[ "${output}" == *'v1.0.0  ->  v1.0.1'* ]] || false
}

@test "hook is resolved from the git toplevel when run from a subdirectory" {
  ready_at v1.2.3
  mkdir -p deep/dir
  cd deep/dir
  HOOK_STDOUT='minor\nsub\n' run bash "${DRIVER}" --dry-run
  [ "${status}" -eq 0 ]
  [ "$(cat "${HOOK_ARGS_FILE}")" = 'v1.2.3' ]
  [[ "${output}" == *'v1.2.3  ->  v1.3.0'* ]] || false
}

# ---------------------------------------------------------------------------
# Tagging
# ---------------------------------------------------------------------------

@test "creates a signed annotated tag and pushes only that tag" {
  ready_at v1.2.3
  git tag local-only HEAD~2
  HOOK_STDOUT='minor\nadded 2 widgets\n' HOOK_STDERR='Widgets added: a b' run bash "${DRIVER}"
  [ "${status}" -eq 0 ]
  [ "$(git cat-file -t v1.3.0)" = 'tag' ]
  git tag -v v1.3.0
  remote_has_tag v1.3.0
  remote_lacks_tag local-only
}

@test "tag message carries the hook subject and findings" {
  ready_at v1.2.3
  HOOK_STDOUT='minor\nadded 2 widgets\n' HOOK_STDERR='Widgets added: a b' run bash "${DRIVER}"
  [ "${status}" -eq 0 ]
  [ "$(git tag -l --format='%(contents:subject)' v1.3.0)" = 'minor: added 2 widgets' ]
  run git tag -l --format='%(contents:body)' v1.3.0
  [[ "${output}" == *'Widgets added: a b'* ]] || false
  [[ "${output}" == *'Previous:    v1.2.3'* ]] || false
  [[ "${output}" == *'Generated-by: scripts/release/create-release.sh'* ]] || false
}

@test "declining at the prompt creates no tag" {
  ready_at v1.2.3
  printf 'n\n' > "${CREATE_RELEASE_TTY}"
  run bash "${DRIVER}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'Release cancelled.'* ]] || false
  [ "$(tag_count)" -eq 1 ]
}

@test "dry run prints the tag message and creates or pushes nothing" {
  ready_at v1.2.3
  HOOK_STDOUT='patch\nfix\n' run bash "${DRIVER}" --dry-run
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'Tag message (dry run):'* ]] || false
  [[ "${output}" == *'patch: fix'* ]] || false
  [[ "${output}" == *'no tag created, nothing pushed'* ]] || false
  [ "$(tag_count)" -eq 1 ]
  remote_lacks_tag v1.2.4
}

# ---------------------------------------------------------------------------
# Bump computation
# ---------------------------------------------------------------------------

@test "post-1.0: hook major bump passes through" {
  ready_at v1.2.3
  HOOK_STDOUT='major\nremoved 1 field\n' run bash "${DRIVER}" --dry-run
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'v1.2.3  ->  v2.0.0'* ]] || false
  [[ "${output}" == *'Tag subject: major: removed 1 field'$'\n'* ]] || false
}

@test "pre-1.0: major is demoted to minor and the subject says so" {
  ready_at v0.4.2
  HOOK_STDOUT='major\nremoved 1 field\n' run bash "${DRIVER}" --dry-run
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'v0.4.2  ->  v0.5.0'* ]] || false
  [[ "${output}" == *'Tag subject: minor: removed 1 field (pre-1.0 demotion)'* ]] || false
}

@test "pre-1.0: minor is demoted to patch and the subject says so" {
  ready_at v0.4.2
  HOOK_STDOUT='minor\nadded 1 field\n' run bash "${DRIVER}" --dry-run
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'v0.4.2  ->  v0.4.3'* ]] || false
  [[ "${output}" == *'Tag subject: patch: added 1 field (pre-1.0 demotion)'* ]] || false
}

@test "pre-1.0: patch with commits since the tag stays patch without a note" {
  ready_at v0.4.2
  HOOK_STDOUT='patch\ntidy\n' run bash "${DRIVER}" --dry-run
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'v0.4.2  ->  v0.4.3'* ]] || false
  [[ "${output}" == *'Tag subject: patch: tidy'$'\n'* ]] || false
}

@test "pre-1.0: no commits since the tag means nothing to release" {
  install_hook "${FIXTURE_HOOK}"
  tag_and_push v0.4.2
  HOOK_STDOUT='patch\ntidy\n' run bash "${DRIVER}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'nothing to release'* ]] || false
  [ "$(tag_count)" -eq 1 ]
}

@test "no tags at all: refuses with first-tag guidance" {
  run bash "${DRIVER}" --dry-run
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'no tags found'* ]] || false
}

# ---------------------------------------------------------------------------
# --force matrix (governance/ci.md "--force Override Rules")
# ---------------------------------------------------------------------------

# force_row <hook-bump> <force-version> <expected-status>
force_row() {
  HOOK_STDOUT="${1}\\nsubject\\n" run bash "${DRIVER}" --dry-run --force "${2}"
  if [ "${status}" -ne "${3}" ]; then
    printf 'hook=%s force=%s: expected status %s, got %s\n%s\n' "${1}" "${2}" "${3}" "${status}" "${output}"
    return 1
  fi
}

@test "--force pre-1.0: only 0.x.y or v1.0.0, and greater than current" {
  ready_at v0.4.2
  force_row patch v0.4.3 0
  force_row patch v0.9.0 0
  force_row patch v1.0.0 0
  force_row patch v1.1.0 1
  force_row patch v2.0.0 1
  force_row patch v0.4.2 1
  force_row patch v0.4.1 1
}

@test "--force post-1.0: single-step patch or minor; major only when computed" {
  ready_at v1.2.3
  force_row minor v1.2.4 0
  force_row minor v1.3.0 0
  force_row minor v1.2.5 1
  force_row minor v1.4.0 1
  force_row minor v2.0.0 1
  force_row minor v1.2.3 1
  force_row major v2.0.0 0
  force_row major v3.0.0 1
  force_row major v1.3.0 0
}

@test "--force version appears in the tag" {
  ready_at v1.2.3
  HOOK_STDOUT='patch\nfix\n' run bash "${DRIVER}" --force v1.3.0
  [ "${status}" -eq 0 ]
  remote_has_tag v1.3.0
}

@test "argument validation rejects malformed input" {
  ready_at v1.2.3
  run bash "${DRIVER}" --bogus
  [ "${status}" -eq 1 ]
  run bash "${DRIVER}" --force
  [ "${status}" -eq 1 ]
  run bash "${DRIVER}" --force 1.2.4
  [ "${status}" -eq 1 ]
  run bash "${DRIVER}" --force v1.2
  [ "${status}" -eq 1 ]
  [ "$(tag_count)" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Preconditions
# ---------------------------------------------------------------------------

@test "refuses off main" {
  ready_at v1.2.3
  git checkout --quiet -b feature
  run bash "${DRIVER}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'must be on main branch'* ]] || false
  [ "$(tag_count)" -eq 1 ]
}

@test "refuses with a dirty tree" {
  ready_at v1.2.3
  printf 'dirty\n' >> README.md
  run bash "${DRIVER}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'working tree is not clean'* ]] || false
  [ "$(tag_count)" -eq 1 ]
}

@test "refuses when behind the upstream" {
  ready_at v1.2.3
  git clone --quiet "${T}/remote.git" "${T}/other"
  (cd "${T}/other" && commit_and_push OTHER 'elsewhere')
  run bash "${DRIVER}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'differs from upstream'* ]] || false
  [ "$(tag_count)" -eq 1 ]
}

@test "refuses with no upstream" {
  ready_at v1.2.3
  git branch --quiet --unset-upstream
  run bash "${DRIVER}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'no upstream configured'* ]] || false
  [ "$(tag_count)" -eq 1 ]
}

@test "dry run reports a failed precondition as a warning and continues" {
  ready_at v1.2.3
  printf 'dirty\n' >> README.md
  HOOK_STDOUT='patch\nfix\n' run bash "${DRIVER}" --dry-run
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'working tree is not clean'* ]] || false
  [[ "${output}" == *'Dry run: continuing'* ]] || false
  [[ "${output}" == *'v1.2.3  ->  v1.2.4'* ]] || false
  [ "$(tag_count)" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Hook failures
# ---------------------------------------------------------------------------

@test "a failing hook aborts and shows its findings" {
  ready_at v1.2.3
  HOOK_EXIT=3 HOOK_STDERR='schema unreadable' run bash "${DRIVER}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'schema unreadable'* ]] || false
  [[ "${output}" == *'release aborted'* ]] || false
  [ "$(tag_count)" -eq 1 ]
}

@test "an unknown bump level from the hook aborts" {
  ready_at v1.2.3
  HOOK_STDOUT='huge\nsubject\n' run bash "${DRIVER}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *"printed bump 'huge'"* ]] || false
  [ "$(tag_count)" -eq 1 ]
}

@test "extra hook output lines abort" {
  ready_at v1.2.3
  HOOK_STDOUT='minor\nsubject\nstray\n' run bash "${DRIVER}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'printed 3 lines'* ]] || false
  [ "$(tag_count)" -eq 1 ]
}

# ---------------------------------------------------------------------------
# keelcore/standards CHANGELOG hook
# ---------------------------------------------------------------------------

# changelog <unreleased-body> [released-body]
changelog() {
  printf '# Changelog\n\n## [Unreleased]\n\n%b\n## [0.1.0] - 2026-01-01\n\n%b\n' "${1}" "${2:-### Added\n\n- old\n}" > CHANGELOG.md
}

@test "CHANGELOG hook: Removed means major" {
  changelog '### Added\n\n- a\n- b\n\n### Removed\n\n- c\n'
  run --separate-stderr bash "${STD_HOOK}" v0.1.0
  [ "${status}" -eq 0 ]
  [ "${output}" = $'major\nCHANGELOG: 1 removed, 2 added' ]
  [[ "${stderr}" == *'[Unreleased] since v0.1.0'* ]] || false
}

@test "CHANGELOG hook: Added or Changed means minor" {
  changelog '### Added\n\n- a\n'
  run --separate-stderr bash "${STD_HOOK}" v0.1.0
  [ "${status}" -eq 0 ]
  [ "${output}" = $'minor\nCHANGELOG: 1 added' ]
  changelog '### Changed\n\n- a\n\n### Fixed\n\n- b\n'
  run --separate-stderr bash "${STD_HOOK}" v0.1.0
  [ "${status}" -eq 0 ]
  [ "${output}" = $'minor\nCHANGELOG: 1 changed, 1 fixed' ]
}

@test "CHANGELOG hook: only Fixed or Security means patch" {
  changelog '### Fixed\n\n- a\n\n### Security\n\n- b\n'
  run --separate-stderr bash "${STD_HOOK}" v0.1.0
  [ "${status}" -eq 0 ]
  [ "${output}" = $'patch\nCHANGELOG: 1 fixed, 1 security' ]
}

@test "CHANGELOG hook: empty [Unreleased] fails; released sections are ignored" {
  changelog '' '### Removed\n\n- old\n'
  run --separate-stderr bash "${STD_HOOK}" v0.1.0
  [ "${status}" -eq 1 ]
  [[ "${stderr}" == *'nothing to release'* ]] || false
}

@test "CHANGELOG hook: requires the previous tag argument" {
  changelog '### Added\n\n- a\n'
  run --separate-stderr bash "${STD_HOOK}"
  [ "${status}" -eq 1 ]
}

@test "CHANGELOG hook drives the driver end to end" {
  install_hook "${STD_HOOK}"
  tag_and_push v0.9.8
  changelog '### Added\n\n- a\n\n### Removed\n\n- b\n'
  git add CHANGELOG.md
  git commit --quiet -m 'changelog'
  git push --quiet
  run bash "${DRIVER}"
  [ "${status}" -eq 0 ]
  [ "$(git tag -l --format='%(contents:subject)' v0.10.0)" = 'minor: CHANGELOG: 1 removed, 1 added (pre-1.0 demotion)' ]
  remote_has_tag v0.10.0
}

# ---------------------------------------------------------------------------
# Pins: stale pins block the release; --allow-stale-pins authorizes it and is
# audit-logged (tag trailers + <git-dir>/release-audit.log)
# ---------------------------------------------------------------------------

# pins_doc: generate docs/current_pins.md, the record the release gate reads.
pins_doc() {
  mkdir -p docs
  bash "$(dirname "${DRIVER}")/update-pins.sh" --discover-only --pins-md docs/current_pins.md > /dev/null 5>&1
}

# stale_pin: commit a workflow pinning actions/checkout at v4.2.2, with offline
# release metadata (UPDATE_PINS_FIXTURES) making v4.4.0 the eligible candidate.
stale_pin() {
  local -r now=2000000000 fix="${T}/pin-fixtures"
  mkdir -p "${fix}" .github/workflows
  printf 'jobs:\n  x:\n    steps:\n      - uses: actions/checkout@%s  # v4.2.2\n' \
    '11bd71901bbe5b1630ceea73d27597364c9af683' > .github/workflows/ci.yml
  jq -n --arg old "$(jq -rn --argjson t $(( now - 400 * 86400 )) '$t | todate')" \
    --arg new "$(jq -rn --argjson t $(( now - 30 * 86400 )) '$t | todate')" '[
      {tag_name: "v4.2.2", draft: false, prerelease: false, published_at: $old},
      {tag_name: "v4.4.0", draft: false, prerelease: false, published_at: $new}]' \
    > "${fix}/$(printf '%s' 'https://api.github.com/repos/actions/checkout/releases?per_page=100' | tr -c 'A-Za-z0-9._-' '_')"
  export UPDATE_PINS_FIXTURES="${fix}" UPDATE_PINS_NOW="${now}"
  git add .github
  pins_doc
  git add docs
  commit_and_push .github/workflows/ci.yml 'pin checkout'
}

@test "pins: a stale pin blocks the release and nothing is tagged" {
  ready_at v1.2.3
  stale_pin
  run bash "${DRIVER}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'action actions/checkout v4.2.2 -> v4.4.0: missed security fixes'* ]] || false
  [[ "${output}" == *'Release blocked by stale pins'* ]] || false
  [ "$(tag_count)" -eq 1 ]
  remote_lacks_tag v1.2.4
}

@test "pins: --allow-stale-pins tags, recording reason, identity, time and pins in the tag and the audit log" {
  ready_at v1.2.3
  stale_pin
  run bash "${DRIVER}" --allow-stale-pins 'checkout v4.4.0 waits on a runner image fix'
  [ "${status}" -eq 0 ]
  remote_has_tag v1.2.4
  run git tag -l --format='%(contents:body)' v1.2.4
  [[ "${output}" == *'Pins: 1 pins: 1 stale'* ]] || false
  [[ "${output}" == *'Pins-Override: checkout v4.4.0 waits on a runner image fix'* ]] || false
  [[ "${output}" == *'Pins-Override-By: Release Tester <tester@example.invalid>'* ]] || false
  [[ "${output}" =~ Pins-Override-At:\ [0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:]{8}Z ]] || false
  [[ "${output}" == *'Pins-Stale: action actions/checkout v4.2.2 -> v4.4.0'* ]] || false
  run jq -r '[.event, .tag, .reason, .stale[0].pin, .stale[0].candidate] | join("|")' "$(git rev-parse --git-dir)/release-audit.log"
  [ "${output}" = 'allow-stale-pins|v1.2.4|checkout v4.4.0 waits on a runner image fix|actions/checkout|v4.4.0' ]
}

@test "pins: --allow-stale-pins without a reason is rejected" {
  ready_at v1.2.3
  run bash "${DRIVER}" --allow-stale-pins
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'--allow-stale-pins needs a reason'* ]] || false
  run bash "${DRIVER}" --allow-stale-pins --dry-run
  [ "${status}" -eq 1 ]
}

@test "pins: a dry run with stale pins warns and tags nothing" {
  ready_at v1.2.3
  stale_pin
  run bash "${DRIVER}" --dry-run
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'(dry run) This release would be blocked by stale pins.'* ]] || false
  [ "$(tag_count)" -eq 1 ]
}

# devimage_pin PUBLISHED: commit a tool image whose image.ref pins another build context, with
# offline registry metadata (UPDATE_PINS_FIXTURES); PUBLISHED=1 also publishes the tree's context.
devimage_pin() {
  local -r fix="${T}/pin-fixtures" lib='source scripts/lib/dev-image.sh'
  mkdir -p "${fix}" scripts/lib containers/dev
  cp "${STANDARDS}/scripts/lib/dev-image.sh" scripts/lib/dev-image.sh
  printf 'FROM scratch\n' > containers/dev/Containerfile
  local repo tree
  repo="$(bash -c "${lib}; dev_repository . dev")"
  printf '%s:ctx-0000000000000000@sha256:%064d\n' "${repo}" 0 > containers/dev/image.ref
  git add scripts/lib containers
  commit_and_push containers/dev/image.ref 'tool image'
  tree="ctx-$(bash -c "${lib}; dev_context_hash . dev")"
  printf 'sha256:%064d' 0 > "${fix}/$(printf 'digest:%s:ctx-0000000000000000' "${repo}" | tr -c 'A-Za-z0-9._-' '_')"
  [ "${1}" = '1' ] && printf 'sha256:%064d' 1 > "${fix}/$(printf 'digest:%s:%s' "${repo}" "${tree}" | tr -c 'A-Za-z0-9._-' '_')"
  export UPDATE_PINS_FIXTURES="${fix}" UPDATE_PINS_NOW=2000000000
  pins_doc
  git add docs
  commit_and_push docs/current_pins.md 'pins'
}

@test "pins: an unpublished tool-image context is a hold and does not block the release" {
  ready_at v1.2.3
  devimage_pin 0
  run bash "${DRIVER}"
  [ "${status}" -eq 0 ]
  remote_has_tag v1.2.4
  run git tag -l --format='%(contents:body)' v1.2.4
  [[ "${output}" == *'1 hold'* ]] || false
  [[ "${output}" != *'Pins-Override'* ]] || false
}

@test "pins: a published, unpinned tool-image context is stale and does not block the release" {
  ready_at v1.2.3
  devimage_pin 1
  run bash "${DRIVER}"
  [ "${status}" -eq 0 ]
  remote_has_tag v1.2.4
  run git tag -l --format='%(contents:body)' v1.2.4
  [[ "${output}" == *'1 stale'* ]] || false
  [[ "${output}" != *'Pins-Override'* ]] || false
}

@test "pins: the gate reads the committed record and queries no registry" {
  ready_at v1.2.3
  stale_pin
  unset UPDATE_PINS_FIXTURES
  local -r bin="${T}/no-network"
  mkdir -p "${bin}"
  printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s/network-calls"\nexit 7\n' "${T}" > "${bin}/curl"
  chmod +x "${bin}/curl"
  PATH="${bin}:${PATH}" run bash "${DRIVER}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'Release blocked by stale pins'* ]] || false
  [ ! -e "${T}/network-calls" ]
}

# TOCTOU: a pin that was current when checked and committed still releases, whatever upstream
# published since; the next update-pins run reports it.
@test "pins: a release published after the check does not block a commit that was current" {
  ready_at v1.2.3
  stale_pin
  sed -i.bak -E 's/^(\| action \| [^|]+\| [^|]+\| )stale( \| )[^|]+/\1current\2- /' docs/current_pins.md
  rm -f docs/current_pins.md.bak
  git add docs
  commit_and_push docs/current_pins.md 'pins checked'
  run bash "${DRIVER}"
  [ "${status}" -eq 0 ]
  remote_has_tag v1.2.4
}

@test "pins: a record out of step with the tree blocks the release" {
  ready_at v1.2.3
  stale_pin
  sed -i.bak 's/# v4.2.2/# v4.2.1/' .github/workflows/ci.yml
  rm -f .github/workflows/ci.yml.bak
  git add .github
  commit_and_push .github/workflows/ci.yml 'moved the pin'
  run bash "${DRIVER}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'does not match the pins in the tree'* ]] || false
  ! remote_has_tag v1.2.4
}

@test "pins: pins with no record block the release" {
  ready_at v1.2.3
  stale_pin
  git rm --quiet docs/current_pins.md
  git commit --quiet -m 'no record'
  git push --quiet
  run bash "${DRIVER}"
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'make pins-doc'* ]] || false
}

@test "pins: with no stale pins the tag records the pin summary and no override" {
  ready_at v1.2.3
  run bash "${DRIVER}"
  [ "${status}" -eq 0 ]
  run git tag -l --format='%(contents:body)' v1.2.4
  [[ "${output}" == *'Pins: 0 pins'* ]] || false
  [[ "${output}" != *'Pins-Override'* ]] || false
  [ ! -e "$(git rev-parse --git-dir)/release-audit.log" ]
}

# ---------------------------------------------------------------------------
# CHANGELOG cut: the release commit the tag points at
# ---------------------------------------------------------------------------

@test "no [Unreleased] entries: no release commit; the tag points at the approved HEAD" {
  ready_at v1.2.3
  local -r head="$(git rev-parse HEAD)"
  HOOK_STDOUT='patch\nfix\n' run bash "${DRIVER}"
  [ "${status}" -eq 0 ]
  [ "$(git rev-parse HEAD)" = "${head}" ]
  [ "$(git rev-parse 'v1.2.4^{commit}')" = "${head}" ]
}


@test "CHANGELOG hook: entries the previous tag already had do not count" {
  changelog '### Added\n\n- shipped in v0.1.0\n'
  git add CHANGELOG.md && git commit --quiet -m 'changelog' && git push --quiet
  tag_and_push v0.1.0
  changelog '### Added\n\n- shipped in v0.1.0\n\n### Fixed\n\n- new fix\n'
  run --separate-stderr bash "${STD_HOOK}" v0.1.0
  [ "${status}" -eq 0 ]
  [ "${output}" = $'patch\nCHANGELOG: 1 fixed' ]
}

@test "the release changes nothing in the repository: the tag points at the approved HEAD" {
  install_hook "${FIXTURE_HOOK}"
  tag_and_push v1.2.3
  printf '# Changelog\n\n## [Unreleased]\n\n### Added\n\n- a\n' > CHANGELOG.md
  git add CHANGELOG.md && git commit --quiet -m 'entries' && git push --quiet
  local head before
  head="$(git rev-parse HEAD)"
  before="$(cat CHANGELOG.md)"
  HOOK_STDOUT='minor\nsub\n' run bash "${DRIVER}"
  [ "${status}" -eq 0 ]
  [ "$(git rev-parse HEAD)" = "${head}" ]
  [ "$(git rev-parse 'v1.3.0^{commit}')" = "${head}" ]
  [ "$(git ls-remote origin refs/heads/main | cut -f1)" = "${head}" ]
  [ "$(cat CHANGELOG.md)" = "${before}" ]
  [ -z "$(git status --porcelain)" ]
}
