#!/usr/bin/env bats
# tests/lint-suppressions.bats
# lint-suppressions.sh fails on a lint-suppression directive in any
# repo-owned file, whatever its type, and leaves vendored trees (top-level
# vendor/, nested vendor/ listed in .nolint) alone. Markdown is scanned only for
# markdownlint's comment directive.
#
# Each test builds a throwaway consumer under BATS_TEST_TMPDIR holding the
# script and its scripts/lib dependency. Fixture directives are assembled at
# runtime (directive) so this file carries none itself.

bats_require_minimum_version 1.5.0

setup() {
  STANDARDS="$(cd "${BATS_TEST_DIRNAME}/.." && pwd -P)"
  CONSUMER="${BATS_TEST_TMPDIR}/consumer"
  mkdir -p "${CONSUMER}/scripts/lint" "${CONSUMER}/scripts/lib"
  cd "${CONSUMER}"
  git init --quiet
  cp -p "${STANDARDS}/scripts/lint/lint-suppressions.sh" scripts/lint/
  cp -p "${STANDARDS}/scripts/lib/paths.sh" scripts/lib/
  cp -p "${STANDARDS}/scripts/lib/local-hook.sh" scripts/lib/
  printf 'package main\n\nfunc main() {}\n' > main.go
}

# directive PREFIX WORD: PREFIX immediately followed by WORD.
directive() {
  printf '%s%s' "${1}" "${2}"
}

scan() {
  git add --all
  run bash scripts/lint/lint-suppressions.sh
}

@test "clean source passes" {
  scan
  [ "${status}" -eq 0 ]
}

@test "golangci-lint directive in Go fails" {
  printf 'package main\n\nfunc f() {} %s:gosec\n' "$(directive '//' 'nolint')" > f.go
  scan
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'f.go:3:'* ]] || false
}

@test "staticcheck and gosec directives in Go fail" {
  printf 'package main\n\n%s SA1019 reason\nfunc f() {}\n' "$(directive '//lint:' 'ignore')" > a.go
  printf 'package main\n\nfunc g() {} // %s\n' "$(directive '#' 'nosec')" > b.go
  scan
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'a.go:3:'* ]] || false
  [[ "${output}" == *'b.go:3:'* ]] || false
}

@test "shellcheck disable in shell fails" {
  printf '#!/usr/bin/env bash\n# %s=SC2086\necho $1\n' "$(directive 'shellcheck ' 'disable')" > s.sh
  scan
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'s.sh:2:'* ]] || false
}

@test "a directive in a file type the scanner has no glob for still fails" {
  printf 'x = 1  # %s\n' "$(directive '' 'noqa')" > tool.py
  printf 'steps:\n  # %s rule:line-length\n' "$(directive 'yamllint ' 'disable')" > ci.yml
  printf '// %s no-console\n' "$(directive 'eslint-' 'disable-next-line')" > app.newlang
  scan
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'tool.py:1:'* ]] || false
  [[ "${output}" == *'ci.yml:2:'* ]] || false
  [[ "${output}" == *'app.newlang:1:'* ]] || false
}

@test "markdownlint directive in markdown fails" {
  printf '# Doc\n\n<!-- %s MD013 -->\n' "$(directive 'markdownlint-' 'disable')" > doc.md
  scan
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'doc.md:3:'* ]] || false
}

@test "markdown prose quoting a code directive passes" {
  printf '# Doc\n\nNever write `%s` in source.\n' "$(directive '//' 'nolint')" > doc.md
  scan
  [ "${status}" -eq 0 ]
}

@test "directives in top-level vendor/ are ignored" {
  mkdir -p vendor/example.com/x
  printf 'package x\n\nfunc F() {} %s\n' "$(directive '//' 'nolint')" > vendor/example.com/x/x.go
  scan
  [ "${status}" -eq 0 ]
}

@test "directives in a nested vendor/ listed in .nolint are ignored" {
  mkdir -p tools/mock/vendor/example.com/x
  printf 'package x\n\nfunc F() {} %s\n' "$(directive '//' 'nolint')" > tools/mock/vendor/example.com/x/x.go
  printf '^tools/mock/vendor/\n' > .nolint
  scan
  [ "${status}" -eq 0 ]
}
