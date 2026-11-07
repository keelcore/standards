#!/usr/bin/env bats
# tests/refresh-governance.bats
# make refresh-governance moves a consumer's .standards to the latest release tag, never past it,
# and carries the consumer over renamed canonical scripts: the old copies go, its hooks follow.

setup() {
  STANDARDS="$(cd "${BATS_TEST_DIRNAME}/.." && pwd -P)"
  T="${BATS_TEST_TMPDIR}"
  export GIT_CONFIG_GLOBAL="${T}/gitconfig"
  git config --global user.name t
  git config --global user.email t@example.invalid
  git config --global commit.gpgsign false
  git config --global tag.gpgsign false
  git config --global init.defaultBranch main
  git config --global protocol.file.allow always
  # The standards repository as this tree holds it: released as v9.0.0, then a commit after it.
  mkdir -p "${T}/std"
  (cd "${STANDARDS}" && git ls-files -co --exclude-standard -z | tar --null -T - -cf -) | tar -xf - -C "${T}/std"
  git -C "${T}/std" init --quiet
  git -C "${T}/std" add -A
  git -C "${T}/std" commit --quiet -m release
  git -C "${T}/std" tag -a v9.0.0 -m v9.0.0
  printf 'after\n' > "${T}/std/after-release.txt"
  git -C "${T}/std" add -A
  git -C "${T}/std" commit --quiet -m 'not released'
  # A consumer whose .standards tracks main.
  mkdir -p "${T}/consumer"
  cd "${T}/consumer"
  git init --quiet
  git submodule add --quiet "${T}/std" .standards
  printf 'include .standards/templates/Makefile.canonical\n' > Makefile
  git add -A
  git commit --quiet -m consumer
}

refresh() {
  run bash .standards/scripts/refresh-governance.sh
}

@test "refresh: .standards moves to the latest release tag, not past it" {
  refresh
  [ "${status}" -eq 0 ]
  [ "$(git -C .standards describe --tags --exact-match)" = 'v9.0.0' ]
  [ ! -e .standards/after-release.txt ]
  [ "$(git ls-files -s .standards | cut -d' ' -f2)" = "$(git -C "${T}/std" rev-parse 'v9.0.0^{commit}')" ]
}

@test "refresh: a renamed canonical script's old copy goes, and the consumer's hook follows it" {
  mkdir -p scripts/ci
  printf 'old\n' > scripts/ci/dco-check.sh
  printf '#!/usr/bin/env bash\necho mine\n' > scripts/integration-test.local.sh
  git add -A
  git commit --quiet -m old
  refresh
  [ "${status}" -eq 0 ]
  [ ! -e scripts/ci/dco-check.sh ]
  [ -f scripts/ci/check-dco.sh ]
  [ ! -e scripts/integration-test.local.sh ]
  [ "$(cat scripts/test-integration.local.sh)" = "$(printf '#!/usr/bin/env bash\necho mine')" ]
  git diff --cached -M --name-status | grep -qE '^R[0-9]*	scripts/integration-test.local.sh	scripts/test-integration.local.sh$'
}

@test "refresh: a renamed canonical script the consumer tracks moves with git mv" {
  mkdir -p scripts/ci
  printf 'old\n' > scripts/ci/dco-check.sh
  git add -A
  git commit --quiet -m old
  refresh
  [ "${status}" -eq 0 ] || { echo "${output}"; return 1; }
  git diff --cached -M --name-status | grep -qE '^R[0-9]*	scripts/ci/dco-check.sh	scripts/ci/check-dco.sh$'
}

@test "refresh: an old copy with staged edits, beside its new name, is removed" {
  mkdir -p scripts/ci
  printf 'old\n' > scripts/ci/dco-check.sh
  cp .standards/scripts/ci/check-dco.sh scripts/ci/check-dco.sh
  git add -A
  git commit --quiet -m old
  printf 'staged edit\n' > scripts/ci/dco-check.sh
  git add scripts/ci/dco-check.sh
  printf 'unstaged edit\n' > scripts/ci/dco-check.sh
  refresh
  [ "${status}" -eq 0 ] || { echo "${output}"; return 1; }
  [ ! -e scripts/ci/dco-check.sh ]
  ! git ls-files --error-unmatch scripts/ci/dco-check.sh > /dev/null 2>&1
}

@test "refresh: a canonical script removed from .standards is removed from the consumer" {
  local -r gone="$(grep -vE '^[[:space:]]*(#|$)' .standards/templates/removed-scripts.txt | head -1)"
  [ -n "${gone}" ]
  mkdir -p "$(dirname "${gone}")"
  printf 'gone\n' > "${gone}"
  git add -A
  git commit --quiet -m gone
  refresh
  [ "${status}" -eq 0 ] || { echo "${output}"; return 1; }
  [ ! -e "${gone}" ]
  ! git ls-files --error-unmatch "${gone}" > /dev/null 2>&1
}

@test "refresh: references to a renamed script are rewritten, except in .standards, vendor/ and released notes" {
  mkdir -p docs vendor/x
  printf 'Run `bash scripts/ci/dco-check.sh` (or ./scripts/ci/dco-check.sh).\n' > docs/howto.md
  printf 'see scripts/ci/dco-check.sh\n' > vendor/x/notes.md
  printf '# Changelog\n\n## [Unreleased]\n\n- scripts/ci/dco-check.sh now X\n\n## [1.0.0] - 2026-01-01\n\n- scripts/ci/dco-check.sh added\n' > CHANGELOG.md
  git add -A
  git commit --quiet -m refs
  refresh
  [ "${status}" -eq 0 ] || { echo "${output}"; return 1; }
  [ "$(cat docs/howto.md)" = 'Run `bash scripts/ci/check-dco.sh` (or ./scripts/ci/check-dco.sh).' ]
  grep -qx 'see scripts/ci/dco-check.sh' vendor/x/notes.md
  grep -qx -- '- scripts/ci/check-dco.sh now X' CHANGELOG.md
  grep -qx -- '- scripts/ci/dco-check.sh added' CHANGELOG.md
}
