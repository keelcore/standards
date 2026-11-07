#!/usr/bin/env bats
# tests/canonical-workflows.bats
# Scorecard and CodeQL reach consumers as byte-identical workflow files, checked and synced like the
# canonical scripts; CodeQL analyzes the languages the repository holds.

bats_require_minimum_version 1.5.0

setup() {
  STANDARDS="$(cd "${BATS_TEST_DIRNAME}/.." && pwd -P)"
  CONSUMER="${BATS_TEST_TMPDIR}/consumer"
  mkdir -p "${CONSUMER}/.github/workflows"
  cd "${CONSUMER}"
  git init --quiet
  git config user.email t@example.com
  git config user.name t
  ln -s "${STANDARDS}" .standards
  printf 'include .standards/templates/Makefile.canonical\n' > Makefile
  local rel
  while IFS= read -r rel; do
    mkdir -p "$(dirname "${rel}")"
    cp "${STANDARDS}/${rel}" "${rel}"
  done < <(cd "${STANDARDS}" && find scripts -type f \( -path 'scripts/hooks/*' -o -name '*.sh' ! -name '*.local.sh' \))
  cp "${STANDARDS}/.github/workflows/scorecard.yml" "${STANDARDS}/.github/workflows/codeql.yml" .github/workflows/
}

@test "verify-canonical: identical workflows pass" {
  run bash scripts/ci/verify-canonical.sh "${CONSUMER}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'PASS  .github/workflows/scorecard.yml'* ]]
  [[ "${output}" == *'PASS  .github/workflows/codeql.yml'* ]]
}

@test "verify-canonical: an edited or missing workflow fails" {
  printf '# edited\n' >> .github/workflows/codeql.yml
  rm .github/workflows/scorecard.yml
  run bash scripts/ci/verify-canonical.sh "${CONSUMER}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'FAIL  .github/workflows/codeql.yml'* ]]
  [[ "${output}" == *'FAIL  .github/workflows/scorecard.yml'* ]]
}

@test "verify-canonical: an excluded workflow is skipped" {
  rm .github/workflows/scorecard.yml
  printf '.github/workflows/scorecard.yml\n' > .canonical-exclude
  run bash scripts/ci/verify-canonical.sh "${CONSUMER}"
  [ "${status}" -eq 0 ]
}

@test "refresh-governance lists the workflows as canonical" {
  run grep -n '.github/workflows/scorecard.yml' "${STANDARDS}/scripts/lib/canonical-files.sh"
  [ "${status}" -eq 0 ]
  grep -q 'canonical-files.sh' "${STANDARDS}/scripts/refresh-governance.sh"
  grep -q 'canonical-files.sh' "${STANDARDS}/scripts/ci/verify-canonical.sh"
}

# Scorecard verifies its own workflow before publishing results.
@test "scorecard.yml meets Scorecard's publishing restrictions" {
  local -r wf="${STANDARDS}/.github/workflows/scorecard.yml"
  ! grep -qE '^(env|defaults):' "${wf}"
  ! grep -qE '^    (env|defaults|container|services):' "${wf}"
  ! grep -q 'workflow_call' "${wf}"
  grep -q 'publish_results: true' "${wf}"
  [ "$(grep -E '^ +- uses:' "${wf}" | sed -E 's/.*uses: ([^@]+)@.*/\1/' | sort -u | paste -sd, -)" \
    = 'actions/checkout,github/codeql-action/upload-sarif,ossf/scorecard-action' ]
}

@test "codeql.yml: analyzes the detected languages, and nothing when there are none" {
  local -r wf="${STANDARDS}/.github/workflows/codeql.yml"
  grep -q 'run: make detect-codeql-languages' "${wf}"
  grep -q 'language: ${{ fromJSON(needs.languages.outputs.languages) }}' "${wf}"
  grep -q "if: \${{ needs.languages.outputs.languages != '\[\]' }}" "${wf}"
}

languages() { GITHUB_OUTPUT="${BATS_TEST_TMPDIR}/out" bash scripts/ci/detect-codeql-languages.sh > /dev/null; cat "${BATS_TEST_TMPDIR}/out"; }

track() {
  local f
  for f in "$@"; do
    mkdir -p "$(dirname "${f}")"
    : > "${f}"
    git add "${f}"
  done
}

@test "detect-codeql-languages.sh: no code in a CodeQL language is an empty list" {
  git rm --quiet --cached -r . 2> /dev/null || true
  track build.sh README.md
  run languages
  [ "${output}" = 'languages=[]' ]
}

@test "detect-codeql-languages.sh: detects Go and JavaScript or TypeScript from tracked files" {
  track pkg/a.go
  run languages
  [ "${output}" = 'languages=["go"]' ]
  track web/b.ts
  rm -f "${BATS_TEST_TMPDIR}/out"
  run languages
  [ "${output}" = 'languages=["go","javascript-typescript"]' ]
}

@test "detect-codeql-languages.sh: vendored code does not count" {
  track vendor/dep/a.go
  run languages
  [ "${output}" = 'languages=[]' ]
}

@test "detect-codeql-languages.sh: config/codeql.local.txt replaces the detection" {
  track pkg/a.go
  mkdir config
  printf '# ours\nrust\n\ngo\n' > config/codeql.local.txt
  run languages
  [ "${output}" = 'languages=["rust","go"]' ]
}
