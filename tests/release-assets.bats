#!/usr/bin/env bats
# tests/release-assets.bats
# build-release-assets.sh fetches what the registries published. A registry serves a new version's
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
  sed -n '/^function retry_fetch()/,/^}/p;/^function fetch_npm()/,/^}/p' "${STANDARDS}/scripts/release/build-release-assets.sh" \
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

@test "stage_provenance: each GitHub build attestation's DSSE envelope lands in <file>.intoto.jsonl" {
  source "${STANDARDS}/scripts/lib/scorecard-assets.sh"
  local -r d="${WORK}/rel"
  mkdir -p "${d}"
  printf '{"attestations":[{"bundle":{"dsseEnvelope":{"payloadType":"application/vnd.in-toto+json","payload":"a"}}},{"bundle":{"dsseEnvelope":{"payloadType":"application/vnd.in-toto+json","payload":"b"}}}]}' \
    > "${d}/p.whl.github-attestations.json"
  printf '{"attestations":[]}' > "${d}/q.tgz.github-attestations.json"
  run stage_provenance "${d}"
  [ "${status}" -eq 0 ]
  [ "$(wc -l < "${d}/p.whl.intoto.jsonl" | tr -d ' ')" -eq 2 ]
  [ "$(jq -sr '.[1].payload' "${d}/p.whl.intoto.jsonl")" = 'b' ]
  [ ! -e "${d}/q.tgz.intoto.jsonl" ]
}

@test "stage_sigstore_copies: every cosign bundle is also published as <file>.sigstore.json" {
  source "${STANDARDS}/scripts/lib/scorecard-assets.sh"
  local -r d="${WORK}/rel"
  mkdir -p "${d}"
  printf 'b1' > "${d}/p.whl.bundle"
  printf 'b2' > "${d}/SHA256SUMS.bundle"
  run stage_sigstore_copies "${d}"
  [ "${status}" -eq 0 ]
  cmp -s "${d}/p.whl.bundle" "${d}/p.whl.sigstore.json"
  cmp -s "${d}/SHA256SUMS.bundle" "${d}/SHA256SUMS.sigstore.json"
}

@test "verify-release-blobs.sh: a .sigstore.json copy of a bundle is not itself a release file" {
  local -r d="${WORK}/rel"
  mkdir -p "${d}"
  printf 'x' > "${d}/a.txt"
  printf 'sig' > "${d}/a.txt.bundle"
  cp "${d}/a.txt.bundle" "${d}/a.txt.sigstore.json"
  (cd "${d}" && sha256sum a.txt > SHA256SUMS)
  printf 'sig' > "${d}/SHA256SUMS.bundle"
  cp "${d}/SHA256SUMS.bundle" "${d}/SHA256SUMS.sigstore.json"
  load helpers-release
  stub_cosign
  GITHUB_REPOSITORY=o/r run bash "${STANDARDS}/scripts/release/verify-release-blobs.sh" "${d}"
  [ "${status}" -eq 0 ] || { echo "${output}"; return 1; }
  ! grep -q 'sigstore.json' "${WORK}/cosign.log"
}
