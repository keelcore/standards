#!/usr/bin/env bats
# tests/release-assets.bats
# release-assets.sh fetches what the registries published. A registry serves a new version's
# parts at different moments, so every fetch of them waits.

setup() {
  STANDARDS="$(cd "${BATS_TEST_DIRNAME}/.." && pwd -P)"
  WORK="${BATS_TEST_TMPDIR}/work"
  mkdir -p "${WORK}/bin" "${WORK}/out"
  COUNTS="${BATS_TEST_TMPDIR}/counts"
  mkdir -p "${COUNTS}"
  export COUNTS
  printf 'tarball' > "${WORK}/payload"
  INTEGRITY="sha512-$(openssl dgst -sha512 -binary "${WORK}/payload" | base64 | tr -d '\n')"
  export INTEGRITY WORK
  cat > "${WORK}/bin/curl" <<'STUB'
#!/usr/bin/env bash
url="${*: -1}"; out=''
args=("$@")
for (( i = 0; i < ${#args[@]}; i++ )); do
  if [ "${args[i]}" = '-o' ]; then out="${args[i+1]}"; url="${args[i+2]:-${url}}"; fi
done
case "${*}" in
  *attestations*)
    n="$(cat "${COUNTS}/attest" 2> /dev/null || printf 0)"
    printf '%s' "$(( n + 1 ))" > "${COUNTS}/attest"
    [ "${n}" -ge "${ATTEST_404S:-0}" ] || { printf 'curl: (22) 404\n' >&2; exit 22; }
    body='{"attestations":[]}'
    ;;
  *.tgz*)
    n="$(cat "${COUNTS}/tarball" 2> /dev/null || printf 0)"
    printf '%s' "$(( n + 1 ))" > "${COUNTS}/tarball"
    [ "${n}" -ge "${TARBALL_404S:-0}" ] || { printf 'curl: (22) 404\n' >&2; exit 22; }
    body="$(cat "${WORK}/payload")"
    ;;
  *) body="{\"dist\":{\"tarball\":\"https://r/p-1.2.3.tgz\",\"integrity\":\"${INTEGRITY}\",\"attestations\":{\"url\":\"https://r/attestations/p\"}}}" ;;
esac
if [ -n "${out}" ]; then printf '%s' "${body}" > "${out}"; else printf '%s' "${body}"; fi
STUB
  chmod +x "${WORK}/bin/curl"
  export PATH="${WORK}/bin:${PATH}"
  sed -n '/^function retry_fetch()/,/^}/p;/^function fetch_npm()/,/^}/p' "${STANDARDS}/scripts/release/release-assets.sh" \
    > "${WORK}/fn.sh"
}

fetch() {
  bash -c "set -o nounset -o errexit -o pipefail
    readonly FETCH_TRIES=5 FETCH_DELAY=0
    log() { printf '%s\n' \"\${1}\" >&2; }
    tag_file() { printf '{\"name\":\"@acme/p\"}'; }
    source '${WORK}/fn.sh'
    fetch_npm v1.2.3 '${WORK}/out'"
}

@test "fetch_npm: waits for the attestations, which appear after the version" {
  export ATTEST_404S=2
  run fetch
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'✅ npm @acme/p@1.2.3'* ]]
  grep -q 'attestations' "${WORK}/out/p-1.2.3.tgz.npm-attestations.json"
  [ "$(cat "${COUNTS}/attest")" -eq 3 ]
}

@test "fetch_npm: waits for the tarball, which can appear after the metadata" {
  export TARBALL_404S=2
  run fetch
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'✅ npm @acme/p@1.2.3'* ]]
  [ "$(cat "${COUNTS}/tarball")" -eq 3 ]
  [ "$(cat "${WORK}/out/p-1.2.3.tgz")" = 'tarball' ]
}

@test "fetch_npm: a tarball that never appears fails, and names it" {
  export TARBALL_404S=99
  run fetch
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'p-1.2.3.tgz not available yet'* ]]
  [[ "${output}" == *'tarball not found'* ]]
}

@test "fetch_npm: attestations that never appear fail, and say so" {
  export ATTEST_404S=99
  run fetch
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'attestations'*'not found'* ]]
}
