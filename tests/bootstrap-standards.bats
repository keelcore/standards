#!/usr/bin/env bats
# tests/bootstrap-standards.bats
# bootstrap-standards.sh sets up a new repository from its .standards submodule alone: .standards at the
# latest release tag, the canonical scripts copied, no tools installed on the host, adapters and the
# pre-commit hook created.

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
  # A new repository with only .standards, at the head of its default branch.
  mkdir -p "${T}/new"
  cd "${T}/new"
  git init --quiet
  git submodule add --quiet "${T}/std" .standards
  git commit --quiet -m standards
}

# tool_setup_hooks: project hooks for the host tool installers; each records that it ran.
tool_setup_hooks() {
  local tool
  mkdir -p scripts/ci
  for tool in shellcheck markdownlint syft; do
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" %s >> "%s/installs"\n' "${tool}" "${T}" > "scripts/ci/setup-${tool}.local.sh"
  done
  git add scripts
  git commit --quiet -m 'tool setup hooks'
}

bootstrap() {
  run bash .standards/scripts/bootstrap-standards.sh
}

@test "bootstrap: a new repository is bootstrapped from .standards alone" {
  bootstrap
  [ "${status}" -eq 0 ] || { echo "${output}"; return 1; }
  [[ "${output}" == *'Bootstrap complete'* ]] || false
  [ -f scripts/refresh-governance.sh ]
  [ -f scripts/lib/local-hook.sh ]
  [ -f scripts/lib/canonical-files.sh ]
}

@test "bootstrap: .standards is mounted at its latest release tag" {
  bootstrap
  [ "${status}" -eq 0 ] || { echo "${output}"; return 1; }
  [ "$(git -C .standards describe --tags --exact-match)" = 'v9.0.0' ]
  [ ! -e .standards/after-release.txt ]
}

@test "bootstrap: no tools are installed on the host" {
  tool_setup_hooks
  bootstrap
  [ "${status}" -eq 0 ] || { echo "${output}"; return 1; }
  [ ! -e "${T}/installs" ]
}

@test "bootstrap: the adapters and the pre-commit hook are created" {
  bootstrap
  [ "${status}" -eq 0 ] || { echo "${output}"; return 1; }
  [ "$(readlink CLAUDE.md)" = '.standards/adapters/claude/CLAUDE.md' ]
  [ -L .github/copilot-instructions.md ]
  [ "$(git config core.hooksPath)" = 'scripts/hooks' ]
}

@test "bootstrap: CLAUDE.md links every governance document, by a path that resolves from the repository root" {
  bootstrap
  [ "${status}" -eq 0 ] || { echo "${output}"; return 1; }
  [ "$(readlink CLAUDE.md)" = '.standards/adapters/claude/CLAUDE.md' ]
  local f link missing=''
  while IFS= read -r f; do
    grep -qF "](${f})" CLAUDE.md || missing="${missing} ${f}"
  done < <(find .standards/governance -type f -name '*.md' | sort)
  [ -z "${missing}" ] || { printf 'not linked:%s\n' "${missing}"; return 1; }
  while IFS= read -r link; do
    [ -e "${link}" ] || { printf 'does not resolve: %s\n' "${link}"; return 1; }
  done < <(grep -oE '\]\(\.standards/[^)]+\)' CLAUDE.md | sed -e 's/^](//' -e 's/)$//')
}
