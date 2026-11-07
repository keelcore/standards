#!/usr/bin/env bats
# tests/vuln.bats
# scripts/lint/lint-vuln.sh: govulncheck in every repo-owned Go module; nothing in a repo without Go.

setup() {
  STANDARDS="$(cd "${BATS_TEST_DIRNAME}/.." && pwd -P)"
  WORK="${BATS_TEST_TMPDIR}/work"
  mkdir -p "${WORK}/scripts/lint" "${WORK}/scripts/lib" "${WORK}/bin"
  cp "${STANDARDS}/scripts/lint/lint-vuln.sh" "${WORK}/scripts/lint/"
  cp "${STANDARDS}/scripts/lib/paths.sh" "${WORK}/scripts/lib/"
  CALLS="${BATS_TEST_TMPDIR}/calls"
  export CALLS
  cat > "${WORK}/bin/govulncheck" <<'STUB'
#!/usr/bin/env bash
printf '%s %s\n' "$(basename "${PWD}")" "$*" >> "${CALLS}"
[ -z "${VULN_FAIL_IN:-}" ] || [ "$(basename "${PWD}")" != "${VULN_FAIL_IN}" ] || exit 3
STUB
  chmod +x "${WORK}/bin/govulncheck"
  export PATH="${WORK}/bin:${PATH}"
  cd "${WORK}"
  git init --quiet
  git config user.email t@example.com
  git config user.name t
}

track_modules() {
  local dir
  for dir in "$@"; do
    mkdir -p "${dir}"
    printf 'module x\n' > "${dir}/go.mod"
    git add "${dir}/go.mod"
  done
}

@test "lint-vuln.sh: a repo with no Go module has nothing to check" {
  run bash scripts/lint/lint-vuln.sh
  [ "${status}" -eq 0 ]
  [ ! -f "${CALLS}" ]
}

@test "lint-vuln.sh: every repo-owned module is checked" {
  track_modules . nested
  run bash scripts/lint/lint-vuln.sh
  [ "${status}" -eq 0 ]
  [ "$(grep -c ' ./...$' "${CALLS}")" -eq 2 ]
  grep -q '^nested ' "${CALLS}"
}

@test "lint-vuln.sh: a vendored module is not checked" {
  track_modules . vendor/dep
  run bash scripts/lint/lint-vuln.sh
  [ "${status}" -eq 0 ]
  [ "$(wc -l < "${CALLS}")" -eq 1 ]
}

@test "lint-vuln.sh: a reachable vulnerability fails, in any module" {
  track_modules . nested
  export VULN_FAIL_IN=nested
  run bash scripts/lint/lint-vuln.sh
  [ "${status}" -ne 0 ]
}

@test "the tool image installs govulncheck, and the canonical targets run it" {
  grep -q 'scripts/ci/setup-govulncheck.sh' "${STANDARDS}/containers/dev/Containerfile"
  grep -qE '^lint-vuln:' "${STANDARDS}/templates/Makefile.canonical"
  grep -qE '^setup-govulncheck:' "${STANDARDS}/templates/Makefile.canonical"
  grep -qx '.PHONY: lint-vuln' "${STANDARDS}/templates/Makefile.canonical"
}

@test "setup-govulncheck.sh: installs only while the tool image is built" {
  cp "${STANDARDS}/scripts/ci/setup-govulncheck.sh" "${WORK}/"
  rm -f "${WORK}/bin/govulncheck"
  printf '#!/usr/bin/env bash\nexit 0\n' > "${WORK}/bin/go"
  chmod +x "${WORK}/bin/go"
  run env -u KEELCORE_IMAGE_BUILD bash setup-govulncheck.sh
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'not in this tool image'* ]]
  KEELCORE_IMAGE_BUILD=1 run bash setup-govulncheck.sh
  [ "${status}" -eq 0 ]
}
