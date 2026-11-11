#!/usr/bin/env bats
# tests/required-files.bats
# Every repository carries a security policy, code owners and dependency updates: templates here,
# and an audit rule that they exist.

setup() {
  load helpers-consumer
  consumer_setup
  printf 'include .standards/templates/Makefile.canonical\n' > Makefile
  mkdir -p .github
}

@test "the templates exist" {
  local f
  for f in SECURITY.md CODEOWNERS dependabot.yml; do
    [ -s "${STANDARDS}/templates/${f}" ]
  done
}

@test "audit: names each missing file, and passes when they exist" {
  run bash scripts/ci/audit.sh
  [[ "${output}" == *'Rule 7'*'SECURITY.md'* ]] || false
  [[ "${output}" == *'.github/CODEOWNERS'* ]] || false
  [[ "${output}" == *'.github/dependabot.yml'* ]] || false
  touch SECURITY.md .github/CODEOWNERS .github/dependabot.yml
  run bash scripts/ci/audit.sh
  [[ "${output}" != *'Rule 7'* ]]
}

@test "audit: SECURITY.md may live in .github" {
  touch .github/SECURITY.md .github/CODEOWNERS .github/dependabot.yml
  run bash scripts/ci/audit.sh
  [[ "${output}" != *'Rule 7'* ]]
}

@test "this repository carries them" {
  [ -f "${STANDARDS}/SECURITY.md" ]
  [ -f "${STANDARDS}/.github/CODEOWNERS" ]
  [ -f "${STANDARDS}/.github/dependabot.yml" ]
}

@test "SECURITY.md and its template link the private reporting route" {
  local f
  for f in "${BATS_TEST_DIRNAME}/../SECURITY.md" "${BATS_TEST_DIRNAME}/../templates/SECURITY.md"; do
    grep -qE '\]\([^)]*security/advisories/new\)' "${f}" || { echo "${f}: no advisory link"; return 1; }
    grep -qE '\]\(https://docs\.github\.com/[^)]+\)' "${f}" || { echo "${f}: no documentation link"; return 1; }
  done
  grep -qE '\(https://github\.com/keelcore/standards/security/advisories/new\)' "${BATS_TEST_DIRNAME}/../SECURITY.md"
  grep -qE '\(mailto:[^)]+\)' "${BATS_TEST_DIRNAME}/../SECURITY.md"
}

@test "osv-scanner.toml sits next to the lockfile it covers, and every entry expires" {
  local f n=0
  while IFS= read -r f; do
    n=$(( n + 1 ))
    jq -e '[.packages | keys[] | select(startswith("node_modules/"))] | length > 0' "$(dirname "${f}")/package-lock.json" > /dev/null \
      || { echo "${f}: no lockfile with dependencies beside it"; return 1; }
    awk '/^\[\[IgnoredVulns\]\]/ { if (n && !(u && r)) bad = 1; n++; u = r = 0; next }
      /^ignoreUntil[[:space:]]*=/ { u = 1 } /^reason[[:space:]]*=/ { r = 1 }
      END { if (n && !(u && r)) bad = 1; exit !(n > 0 && !bad) }' "${f}" \
      || { echo "${f}: an entry without ignoreUntil or reason"; return 1; }
  done < <(cd "${BATS_TEST_DIRNAME}/.." && git ls-files -co --exclude-standard '*osv-scanner.toml' | sed "s#^#${BATS_TEST_DIRNAME}/../#")
  [ "${n}" -gt 0 ]
}

# dependabot_entries FILE: one line per updates entry, "<ecosystem>\t<cooldown days>\t<group patterns>".
dependabot_entries() {
  awk '
    function flush() { if (eco != "") printf "%s\t%s\t%s\n", eco, days, pats }
    /^  - package-ecosystem:/ { flush(); eco = $3; gsub(/"/, "", eco); days = "-"; pats = ""; next }
    /^ +default-days:/ { days = $2 }
    /^ +- "?github\/codeql-action/ { p = $2; gsub(/"/, "", p); pats = pats p }
    END { flush() }
  ' "${1}"
}

@test "dependabot.yml and its template: every ecosystem waits out the update-pins cooldown; codeql-action moves as one" {
  local f eco days pats
  for f in "${STANDARDS}/.github/dependabot.yml" "${STANDARDS}/templates/dependabot.yml"; do
    run dependabot_entries "${f}"
    [ -n "${output}" ] || { echo "${f}: no updates"; return 1; }
    while IFS=$'\t' read -r eco days pats; do
      [ "${days}" = '14' ] || { echo "${f}: ${eco} cooldown is ${days}, not 14 days"; return 1; }
      [ "${eco}" != 'github-actions' ] || [ "${pats}" = 'github/codeql-action*' ] \
        || { echo "${f}: github-actions does not group github/codeql-action*"; return 1; }
    done <<< "${output}"
  done
}
