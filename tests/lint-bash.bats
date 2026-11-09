#!/usr/bin/env bats
# tests/lint-bash.bats
# lint-bash.sh also checks BATS files: a [[ … ]] that is a test's own statement, but not its last, must end
# with `|| false`, because bash does not always fail a test on a false [[ … ]] there.

setup() {
  load helpers-consumer
  consumer_setup
  printf '#!/usr/bin/env bash\necho ok\n' > tool.sh
  mkdir -p tests
  git add tool.sh
}

@test "lint-bash.sh: a mid-test [[ … ]] without || false fails, naming file and line" {
  printf '@test "x" {\n  run true\n  [[ "${output}" == a ]]\n  [ "${status}" -eq 0 ]\n}\n' > tests/bad.bats
  git add tests/bad.bats
  run bash scripts/lint/lint-bash.sh
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'tests/bad.bats:3'* ]] || false
}

@test "lint-bash.sh: a last-statement [[ … ]], one with || false, and heredoc text all pass" {
  printf '@test "y" {\n  [[ a == a ]] || false\n  cat <<EOF\n  [[ not code ]]\nEOF\n  if [[ a == a ]]; then :; fi\n  [[ a == a ]]\n}\n' > tests/good.bats
  git add tests/good.bats
  run bash scripts/lint/lint-bash.sh
  [ "${status}" -eq 0 ] || { echo "${output}"; return 1; }
}

# R37 (governance/bash.md): every environment variable a file reads is imported once, at file scope before
# `function main`, as declare -rx NAME="${NAME:-<default>}".

# script FILE LINE...: FILE holding a header and LINE..., tracked.
script() {
  local -r file="${1}"
  shift
  mkdir -p "$(dirname "${file}")"
  printf '%s\n' '#!/usr/bin/env bash' "# ${file}" "$@" > "${file}"
  git add -f "${file}"
}

lint() {
  run bash scripts/lint/lint-bash.sh
}

# fails_on FILE:LINE NAME: lint failed, naming FILE:LINE and NAME.
fails_on() {
  [ "${status}" -ne 0 ] || { printf 'passed:\n%s\n' "${output}"; return 1; }
  [[ "${output}" == *"${1}: ${2}"* ]] || { printf 'not named %s: %s:\n%s\n' "${1}" "${2}" "${output}"; return 1; }
}

passes() {
  [ "${status}" -eq 0 ] || { printf '%s\n' "${output}"; return 1; }
}

@test "R37: an inline read inside a function fails, naming file, line and name, and the line to write" {
  script a.sh 'function main() {' '  [ -n "${SOME_INPUT:-}" ] && printf yes' '}'
  lint
  fails_on a.sh:4 SOME_INPUT
  [[ "${output}" == *'declare -rx SOME_INPUT="${SOME_INPUT:-'* ]] || false
}

@test "R37: an unbraced \$FOO read fails" {
  script a.sh 'function main() {' '  printf "%s" "$FOO"' '}'
  lint
  fails_on a.sh:4 FOO
}

@test "R37: a renamed import fails, naming the environment variable" {
  local form
  for form in 'readonly X="${FOO:-1}"' 'declare -r X="${FOO:-1}"' 'X="${FOO:-1}"' 'declare -rx X="${FOO:-1}"'; do
    script a.sh "${form}" 'function main() {' '  printf "%s" "${X}"' '}'
    lint
    fails_on a.sh:3 FOO || { printf 'form: %s\n' "${form}"; return 1; }
  done
}

@test "R37: an import inside a function, or after function main, fails" {
  script a.sh 'function main() {' '  declare -rx FOO="${FOO:-}"' '}'
  script b.sh 'function main() {' '  printf "%s" "${BAR}"' '}' 'declare -rx BAR="${BAR:-}"' 'main'
  lint
  fails_on a.sh:4 FOO
  fails_on b.sh:6 BAR
}

@test "R37: one name imported twice in a file, or by a script and a library it sources, fails" {
  script a.sh 'declare -rx FOO="${FOO:-}"' 'declare -rx FOO="${FOO:-}"'
  script scripts/lib/fix.sh 'declare -rx BAR="${BAR:-}"'
  script scripts/b.sh 'source "$(dirname "${BASH_SOURCE[0]}")/lib/fix.sh"' 'declare -rx BAR="${BAR:-}"'
  lint
  fails_on a.sh:4 FOO
  fails_on scripts/b.sh:4 BAR
}

@test "R37: conforming imports, assigned names, a library's names, shell names and quoted programs pass" {
  script scripts/lib/fix.sh '# Environment: LIB_INPUT (default empty).' 'declare -rx LIB_INPUT="${LIB_INPUT:-}"' \
    'declare -r LIB_CONST=1' 'function lib_const() { printf "%s" "${LIB_CONST}"; }'
  script scripts/a.sh '# Environment: FOO (default 1), BAR (default empty).' \
    'source "$(dirname "${BASH_SOURCE[0]}")/lib/fix.sh"' 'declare -rx FOO="${FOO:-1}"' 'declare -rx BAR="${BAR:-}"' \
    'declare -r MINE=x' 'function main() {' '  local OUT' '  OUT="${FOO}${BAR}${MINE}${LIB_INPUT}${LIB_CONST}"' '  printf "%s" "${OUT}"' \
    '  printf "%s %s %s %s\n" "${PATH}" "${HOME}" "${BASH_SOURCE[0]}" "${PIPESTATUS[0]}"' \
    "  awk '{ print \$NAME, ENVIRON[\"HOME\"] }' /dev/null" "  jq -n '\$ENV.PROBE' > /dev/null" \
    "  printf '%s' \"\\\$ESCAPED\"" '  # ${NOT_IN_A_COMMENT}' '}'
  script tests/helper.bash '# Environment: HELPER_INPUT (default empty).' 'declare -rx HELPER_INPUT="${HELPER_INPUT:-}"' \
    'helper() { printf "%s %s" "${HELPER_INPUT}" "${BATS_TEST_TMPDIR}"; }'
  lint
  passes
}

@test "R37: a multi-line single-quoted program is not shell" {
  script a.sh 'function main() {' "  awk '" '    { print $UNSHELL }' '    END { print ${ALSO_NOT} }' "  ' /dev/null" '}'
  lint
  passes
}

@test "R37: *.bats files are not scanned" {
  script tests/x.bats '@test "x" {' '  [ -n "${FOO_FROM_BATS:-}" ]' '}'
  lint
  passes
}

@test "R37: an imported name the header does not list fails; a default the header does not give fails" {
  script a.sh 'declare -rx FOO="${FOO:-}"'
  script b.sh '# Environment: BAR (default 5).' 'declare -rx BAR="${BAR:-7}"'
  lint
  fails_on a.sh:3 FOO
  fails_on b.sh:4 BAR
}

@test "sourcing uses source, not .: a . that sources a file fails" {
  script scripts/lib/fix.sh 'function fix() { :; }'
  script scripts/a.sh '. "$(dirname "${BASH_SOURCE[0]}")/lib/fix.sh"'
  lint
  fails_on scripts/a.sh:3 .
}

@test "R37: a library's sibling sourced by a relative path is part of the chain" {
  script scripts/lib/inner.sh '# Environment: INNER (default empty).' 'declare -rx INNER="${INNER:-}"'
  script scripts/lib/outer.sh 'source "$(dirname "${BASH_SOURCE[0]}")/inner.sh"'
  script scripts/a.sh 'source "$(dirname "${BASH_SOURCE[0]}")/lib/outer.sh"' 'printf "%s" "${INNER}"'
  script scripts/b.sh '# Environment: INNER (default empty).' 'source "$(dirname "${BASH_SOURCE[0]}")/lib/outer.sh"' \
    'declare -rx INNER="${INNER:-}"'
  lint
  [ "${status}" -ne 0 ]
  [[ "${output}" != *'scripts/a.sh'* ]] || false
  fails_on scripts/b.sh:5 INNER
}

@test "R37: a lowercase local that starts with _ is not a read" {
  script a.sh 'function main() {' '  local _sibling=x' '  printf "%s" "${_sibling}"' '}'
  lint
  passes
}

@test "R37: single quotes inside \$( ) inside double quotes are single quotes" {
  script a.sh 'function main() {' "  printf '%s' \"\$(awk '{ print \$NF }' /dev/null)\"" '}'
  script b.sh 'function main() {' "  printf '%s' \"\$(printf '%s' x) \${AFTER_SUBST}\"" '}'
  lint
  [[ "${output}" != *'a.sh'* ]] || false
  fails_on b.sh:4 AFTER_SUBST
}

@test "R37: the header may follow the default with ; or ," {
  script a.sh '# Environment: FOO (default 1; the count), BAR (default empty, unless set).' \
    'declare -rx FOO="${FOO:-1}"' 'declare -rx BAR="${BAR:-}"'
  lint
  passes
}

@test "R37: assigning an imported name fails, in the file or in a file that sources the import" {
  script a.sh '# Environment: FOO (default empty).' 'declare -rx FOO="${FOO:-}"' 'function main() {' '  FOO=x' '}'
  script scripts/lib/fix.sh '# Environment: BAR (default empty).' 'declare -rx BAR="${BAR:-}"'
  script scripts/b.sh 'source "$(dirname "${BASH_SOURCE[0]}")/lib/fix.sh"' 'export BAR=y'
  lint
  fails_on a.sh:6 FOO
  fails_on scripts/b.sh:4 BAR
}

@test "R37: a library with imports sourced twice in one chain fails" {
  script scripts/lib/inner.sh '# Environment: INNER (default empty).' 'declare -rx INNER="${INNER:-}"'
  script scripts/lib/outer.sh 'source "$(dirname "${BASH_SOURCE[0]}")/inner.sh"'
  script scripts/a.sh 'source "$(dirname "${BASH_SOURCE[0]}")/lib/outer.sh"' \
    'source "$(dirname "${BASH_SOURCE[0]}")/lib/inner.sh"'
  lint
  fails_on scripts/a.sh:1 scripts/lib/inner.sh
}

@test "R37: two reads on one line are both reported" {
  script a.sh 'function main() {' '  printf "%s %s" "${FIRST_IN:-1}" "${SECOND_IN:-2}"' '}'
  lint
  fails_on a.sh:4 FIRST_IN
  fails_on a.sh:4 SECOND_IN
}
