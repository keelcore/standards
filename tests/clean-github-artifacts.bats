#!/usr/bin/env bats
# tests/clean-github-artifacts.bats
# scripts/release/clean-github-artifacts.sh against stubs of gh, curl and git that serve the API from
# tests/fixtures/clean-github-artifacts, in a throwaway repository WORK (a .git directory). The tag v1.0.0 is at
# TAG (2222…); HEAD is either the tag or one commit past it (1111…); OLD (9999…) published the stale artifacts. A
# GET lists only what the run has not deleted yet, so the script's own verification sees its deletions.

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export REPO_ROOT
}

setup() {
  WORK="${BATS_TEST_TMPDIR}/work"
  STATE="${BATS_TEST_TMPDIR}/state"
  FIXTURES="${REPO_ROOT}/tests/fixtures/clean-github-artifacts"
  export WORK STATE FIXTURES
  mkdir -p "${WORK}/scripts/release" "${WORK}/scripts/lib" "${WORK}/.git" "${WORK}/bin" "${WORK}/containers/dev" \
    "${STATE}"
  cp "${REPO_ROOT}/scripts/release/clean-github-artifacts.sh" "${WORK}/scripts/release/"
  cp "${REPO_ROOT}/scripts/lib/local-hook.sh" "${WORK}/scripts/lib/"
  printf 'ghcr.io/keelcore/keel-dev:ctx-aaaa\n' > "${WORK}/containers/dev/image.ref"
  stub_tools
  : > "${STATE}/calls"
  export PATH="${WORK}/bin:${PATH}"
  export TMPDIR="${BATS_TEST_TMPDIR}/tmp"
  mkdir -p "${TMPDIR}"
  export GITHUB_TOKEN=token GITHUB_CLEAN_BACKOFF=0
  export STUB_TAG_SHA=2222222222222222222222222222222222222222
  export STUB_HEAD=1111111111111111111111111111111111111111
  export STUB_SCOPES='repo, read:packages, delete:packages, workflow'
  unset GITROOT GITHUB_CLEAN_CONFIRM FAIL_ON RATE_LIMIT_ONCE STUB_ANCESTOR
  cd "${WORK}"
}

# stub_tools writes the fake commands. Every call lands in STATE/calls; FAIL_ON makes a call matching its
# regex fail, and RATE_LIMIT_ONCE ("METHOD ENDPOINT") makes the first such gh call hit a rate limit.
stub_tools() {
  cat > "${WORK}/bin/stub-lib" <<'LIB'
record() { printf '%s\n' "$*" >> "${STATE}/calls"; }
fails() { [ -n "${FAIL_ON:-}" ] && [[ "$*" =~ ${FAIL_ON} ]]; }
LIB
  cat > "${WORK}/bin/gh" <<'GH'
#!/usr/bin/env bash
source "${WORK}/bin/stub-lib"
record "gh $*"
case "${1} ${2:-}" in
  'auth token') printf 'token\n'; exit 0 ;;
  'repo view') pwd > "${STATE}/pwd"; jq -r "${*: -1}" "${FIXTURES}/repo-view.json"; exit 0 ;;
esac
shift
method=GET include='' q='.' ep=''
while [ "$#" -gt 0 ]; do
  case "${1}" in
    -X) method="${2}"; shift 2 ;;
    -i) include=1; shift ;;
    --paginate) shift ;;
    --jq | -q) q="${2}"; shift 2 ;;
    -f) shift 2 ;;
    *) ep="${1}"; shift ;;
  esac
done
if fails "gh ${method} ${ep}"; then
  printf 'gh-failed %s\n' "${ep}" >> "${STATE}/failed"
  printf 'gh: Server Error (HTTP 500)\n' >&2
  exit 1
fi
if [ "${method} ${ep}" = "${RATE_LIMIT_ONCE:-}" ] && [ ! -e "${STATE}/limited" ]; then
  : > "${STATE}/limited"
  printf 'gh: API rate limit exceeded (HTTP 429)\n' >&2
  exit 1
fi
[ "${method}" = 'GET' ] || exit 0
path="${ep%%\?*}"
key="$(sed -E 's/[?&]per_page=100//; s/[/?&=:]/_/g' <<< "${ep}")"
file="${FIXTURES}/${key}.json"
if [[ "${ep}" == */attestations/* ]] && grep -q "^gh api -X DELETE .*/${ep##*/}\$" "${STATE}/calls"; then
  file=''
fi
if [ ! -f "${file}" ]; then
  if [[ "${ep}" == *'packages?package_type='* ]]; then
    file="${FIXTURES}/empty.json"
  else
    printf '{"message":"Not Found","status":"404"}'
    printf 'gh: Not Found (HTTP 404)\n' >&2
    exit 1
  fi
fi
touch "${STATE}/failed"
deleted="$(sed -nE "s#^gh api -X DELETE (${path}/.+)\$#\1#p" "${STATE}/calls" \
  | grep -vxF -f <(sed -n 's/^gh-failed //p' "${STATE}/failed") | sed 's#.*/##' | jq -R . | jq -sc .)"
[ -z "${include}" ] || printf 'HTTP/2.0 200 OK\r\nX-Oauth-Scopes: %s\r\n\r\n' "${STUB_SCOPES}"
jq -c --argjson d "${deleted}" -f "${FIXTURES}/drop-deleted.jq" "${file}" | jq -rc "${q}"
GH
  cat > "${WORK}/bin/curl" <<'CURL'
#!/usr/bin/env bash
source "${WORK}/bin/stub-lib"
url="${*: -1}"
record "curl ${url}"
if fails "curl ${url}"; then exit 22; fi
case "${url}" in
  https://ghcr.io/token*) printf '{"token":"registry"}\n' ;;
  https://ghcr.io/v2/*)
    kind="$(sed -E 's#.*/(manifests|referrers)/.*#\1#' <<< "${url}")"
    pkg="$(sed -E 's#https://ghcr.io/v2/keelcore/(.*)/(manifests|referrers)/.*#\1#' <<< "${url}")"
    file="${FIXTURES}/${kind}-${pkg}-$(tr ':' '_' <<< "${url##*/}").json"
    if [ -f "${file}" ]; then
      cat "${file}"
    elif [ "${kind}" = 'manifests' ]; then
      printf '{"schemaVersion":2}\n'
    else
      exit 22
    fi
    ;;
  *) exit 22 ;;
esac
CURL
  cat > "${WORK}/bin/git" <<'GIT'
#!/usr/bin/env bash
source "${WORK}/bin/stub-lib"
record "git $*"
case "$*" in
  'rev-parse HEAD') printf '%s\n' "${STUB_HEAD}" ;;
  'tag --points-at HEAD'*) [ "${STUB_HEAD}" != "${STUB_TAG_SHA}" ] || printf 'v1.0.0\n' ;;
  'describe --tags --abbrev=0') printf 'v1.0.0\n' ;;
  'rev-list -n 1 v1.0.0') printf '%s\n' "${STUB_TAG_SHA}" ;;
  'ls-remote origin refs/heads/main') printf '%s\trefs/heads/main\n' "${STUB_HEAD}" ;;
  'ls-remote --exit-code origin refs/tags/v1.0.0') printf '%s\trefs/tags/v1.0.0\n' "${STUB_TAG_SHA}" ;;
  'ls-remote --tags origin') printf '%s\trefs/tags/v0.9.0\n%s\trefs/tags/v1.0.0\n' 9999 "${STUB_TAG_SHA}" ;;
  'merge-base --is-ancestor'*) exit "${STUB_ANCESTOR:-0}" ;;
  'ls-files'*) find . -name '*image.ref' | sed 's#^\./##' ;;
  *) exit 1 ;;
esac
GIT
  chmod +x "${WORK}/bin/gh" "${WORK}/bin/curl" "${WORK}/bin/git"
}

# deletes: every mutating API call, in order.
deletes() { grep -E '^gh api -X (DELETE|POST) ' "${STATE}/calls" || true; }

clean() { run bash scripts/release/clean-github-artifacts.sh "$@" < /dev/null; }

# clean_from DIR: the script run from DIR.
clean_from() {
  run bash -c 'cd "${1}" && bash "${2}" < /dev/null' _ "${1}" "${WORK}/scripts/release/clean-github-artifacts.sh"
}

# expected_deletes: what a confirmed run past the tag deletes, in the script's order.
expected_deletes() {
  printf '%s\n' \
    'gh api -X POST repos/keelcore/keel/deployments/32/statuses -f state=inactive' \
    'gh api -X DELETE repos/keelcore/keel/deployments/32' \
    'gh api -X DELETE repos/keelcore/keel/releases/42' \
    'gh api -X DELETE repos/keelcore/keel/releases/43' \
    'gh api -X DELETE orgs/keelcore/packages/container/keel/versions/111' \
    'gh api -X DELETE orgs/keelcore/packages/container/keel/versions/112' \
    'gh api -X DELETE orgs/keelcore/packages/container/keel/versions/113' \
    'gh api -X DELETE orgs/keelcore/packages/container/keel-old' \
    'gh api -X DELETE orgs/keelcore/packages/container/keel-dev/versions/302' \
    'gh api -X DELETE orgs/keelcore/attestations/digest/sha256:idx0' \
    'gh api -X DELETE orgs/keelcore/attestations/digest/sha256:a0' \
    'gh api -X DELETE repos/keelcore/keel/actions/artifacts/12' \
    'gh api -X DELETE repos/keelcore/keel/actions/caches/22' \
    'gh api -X DELETE repos/keelcore/keel/actions/caches/24' \
    'gh api -X DELETE repos/keelcore/keel/actions/runs/2'
}

@test "clean-github-artifacts.sh: an argument is rejected" {
  clean now
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'Unexpected argument'* ]] || false
  [ -z "$(deletes)" ]
}

@test "clean-github-artifacts.sh: without a terminal it inventories, prints the table and deletes nothing" {
  clean
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'| runs | 3 | 2 | 1 |'* ]] || false
  [[ "${output}" == *'| releases | 3 | 1 | 2 |'* ]] || false
  [[ "${output}" == *'| caches | 4 | 2 | 2 |'* ]] || false
  [[ "${output}" == *'| packages | 13 | 8 | 5 |'* ]] || false
  [[ "${output}" == *'dry run'* ]] || false
  [[ "${output}" == *'Left in place: 0 code-scanning analyses'* ]] || false
  [[ "${output}" != *'Not Found'* ]] || false
  [ -z "$(deletes)" ]
}

@test "clean-github-artifacts.sh: a wrong confirmation deletes nothing" {
  GITHUB_CLEAN_CONFIRM=keelcore/other clean
  [ "${status}" -eq 0 ]
  [ -z "$(deletes)" ]
}

@test "clean-github-artifacts.sh: HEAD past the tag keeps what HEAD and the tag published, deletes the rest, and verifies" {
  GITHUB_CLEAN_CONFIRM=keelcore/keel clean
  [ "${status}" -eq 0 ]
  diff <(expected_deletes) <(deletes)
  [[ "${output}" == *'✅ verified'* ]] || false
}

@test "clean-github-artifacts.sh: HEAD at the tag deletes the runs of every other commit" {
  STUB_HEAD="${STUB_TAG_SHA}" GITHUB_CLEAN_CONFIRM=keelcore/keel clean
  [ "${status}" -eq 0 ]
  deletes | grep -qx 'gh api -X DELETE repos/keelcore/keel/actions/runs/1'
  deletes | grep -qx 'gh api -X DELETE repos/keelcore/keel/actions/runs/2'
  ! deletes | grep -q 'actions/runs/3$'
}

@test "clean-github-artifacts.sh: git refs are never written" {
  GITHUB_CLEAN_CONFIRM=keelcore/keel clean
  [ "${status}" -eq 0 ]
  [ -z "$(grep -E '^git (push|tag -d|tag --delete|update-ref|fetch)' "${STATE}/calls" || true)" ]
  [ -z "$(grep -E 'git/refs' "${STATE}/calls" || true)" ]
}

@test "clean-github-artifacts.sh: a token without delete:packages stops before the inventory" {
  STUB_SCOPES='repo, read:packages' GITHUB_CLEAN_CONFIRM=keelcore/keel clean
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'delete:packages'* ]] || false
  [ -z "$(deletes)" ]
}

@test "clean-github-artifacts.sh: HEAD missing from the default branch stops" {
  STUB_ANCESTOR=1 GITHUB_CLEAN_CONFIRM=keelcore/keel clean
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'not on origin/main'* ]] || false
  [ -z "$(deletes)" ]
}

@test "clean-github-artifacts.sh: an unreadable manifest of a kept image stops before deleting" {
  FAIL_ON='manifests/sha256:idx1' GITHUB_CLEAN_CONFIRM=keelcore/keel clean
  [ "${status}" -ne 0 ]
  [ -z "$(deletes)" ]
}

@test "clean-github-artifacts.sh: a failed deletion is reported, the rest still run, and the run fails" {
  FAIL_ON='gh DELETE repos/keelcore/keel/actions/caches/22' GITHUB_CLEAN_CONFIRM=keelcore/keel clean
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'repos/keelcore/keel/actions/caches/22'* ]] || false
  deletes | grep -qx 'gh api -X DELETE repos/keelcore/keel/actions/runs/2'
}

@test "clean-github-artifacts.sh: a rate-limited deletion is retried" {
  RATE_LIMIT_ONCE='DELETE repos/keelcore/keel/releases/42' GITHUB_CLEAN_CONFIRM=keelcore/keel clean
  [ "${status}" -eq 0 ]
  [ "$(deletes | grep -cx 'gh api -X DELETE repos/keelcore/keel/releases/42')" -eq 2 ]
}

@test "clean-github-artifacts.sh: run from a subdirectory, it works on the repository whose .git directory is above" {
  mkdir -p "${WORK}/docs/deep"
  clean_from "${WORK}/docs/deep"
  [ "${status}" -eq 0 ]
  [ "$(cat "${STATE}/pwd")" = "${WORK}" ]
}

@test "clean-github-artifacts.sh: a .git file (a submodule) is passed over for the .git directory above it" {
  mkdir -p "${WORK}/.standards/scripts"
  printf 'gitdir: ../.git/modules/.standards\n' > "${WORK}/.standards/.git"
  clean_from "${WORK}/.standards/scripts"
  [ "${status}" -eq 0 ]
  [ "$(cat "${STATE}/pwd")" = "${WORK}" ]
}

@test "clean-github-artifacts.sh: GITROOT names the repository, wherever it runs from" {
  mkdir -p "${BATS_TEST_TMPDIR}/elsewhere"
  GITROOT="${WORK}" clean_from "${BATS_TEST_TMPDIR}/elsewhere"
  [ "${status}" -eq 0 ]
  [ "$(cat "${STATE}/pwd")" = "${WORK}" ]
}

@test "clean-github-artifacts.sh: with no .git directory at or above it, and no GITROOT, it stops" {
  mkdir -p "${BATS_TEST_TMPDIR}/elsewhere"
  clean_from "${BATS_TEST_TMPDIR}/elsewhere"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'GITROOT'* ]] || false
  [ ! -e "${STATE}/pwd" ]
}
