#!/usr/bin/env bats
# tests/release-images.bats
# The image release, its self-verification, the upload and the chart, in a throwaway tree against
# stubs of docker, git, gh and the dev image. A concurrency test uses a barrier: every job waits
# until all of them have started, which only concurrent jobs reach.

setup_file() {
  REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
  export REPO_ROOT
}

setup() {
  WORK="${BATS_TEST_TMPDIR}/work"
  STATE="${BATS_TEST_TMPDIR}/state"
  export WORK STATE
  mkdir -p "${WORK}/scripts/release" "${WORK}/scripts/lib" "${WORK}/scripts/dev" "${WORK}/scripts/build" \
    "${WORK}/dist" "${WORK}/bin" "${STATE}/started"
  cp "${REPO_ROOT}"/scripts/release/*.sh "${WORK}/scripts/release/"
  cp "${REPO_ROOT}"/scripts/lib/*.sh "${WORK}/scripts/lib/"
  mkdir -p "${WORK}/config"
  printf 'module github.com/keelcore/keel\n' > "${WORK}/go.mod"
  printf 'keelcore/keel\n' > "${WORK}/config/release-repo.local.txt"
  printf 'max\t\nmin\t-min\nfips\t-fips\n' > "${WORK}/config/release-images.local.txt"
  printf 'Dockerfile.release\n' > "${WORK}/config/release-dockerfile.local.txt"
  mkdir -p "${WORK}/charts/keel"
  printf 'name: keel\nversion: 0.0.0\n' > "${WORK}/charts/keel/Chart.yaml"
  stub_tools
  : > "${STATE}/calls"
  export PATH="${WORK}/bin:${PATH}"
  unset GITHUB_REPOSITORY # the workflow context would win over the fixture's config
  export GITHUB_TOKEN=token GITHUB_ACTOR=actor GH_TOKEN=token
  export GITHUB_OUTPUT="${STATE}/output"
  export BARRIER_TIMEOUT=30
  local flavor arch
  for flavor in max min fips; do
    for arch in amd64 arm64; do
      printf 'binary' > "${WORK}/dist/keel-${flavor}-linux-${arch}"
      printf 'bundle' > "${WORK}/dist/keel-${flavor}-linux-${arch}.bundle"
    done
  done
  printf 'sums' > "${WORK}/dist/SHA256SUMS"
  printf 'bundle' > "${WORK}/dist/SHA256SUMS.bundle"
  printf '{}' > "${WORK}/dist/keel.openvex.json"
  cd "${WORK}"
}

# stub_tools writes the fake commands. Every call lands in STATE/calls. barrier NAME COUNT waits
# until COUNT distinct names have started. FAIL_ON makes a call matching its regex fail.
stub_tools() {
  cat > "${WORK}/bin/stub-lib" <<'LIB'
record() { printf '%s\n' "$*" >> "${STATE}/calls"; }
maybe_fail() { if [ -n "${FAIL_ON:-}" ] && [[ "$*" =~ ${FAIL_ON} ]]; then exit 1; fi; }
barrier() {
  : > "${STATE}/started/${1//[^A-Za-z0-9._-]/_}"
  local waited=0
  until [ "$(find "${STATE}/started" -type f | wc -l)" -ge "${2}" ]; do
    sleep 0.1
    waited=$(( waited + 1 ))
    [ "${waited}" -lt $(( BARRIER_TIMEOUT * 10 )) ] || { printf 'barrier timed out\n' >&2; exit 1; }
  done
}
LIB
  cat > "${WORK}/bin/git" <<'GIT'
#!/usr/bin/env bash
case "${1}" in
  describe) printf 'v1.2.3\n' ;;
  ls-files) printf 'charts/keel/Chart.yaml\n' ;;
  log) printf '1700000000\n' ;;
  rev-parse) printf 'abc123\n' ;;
esac
GIT
  cat > "${WORK}/bin/docker" <<'DOCKER'
#!/usr/bin/env bash
source "${WORK}/bin/stub-lib"
record "docker $*"
maybe_fail "docker $*"
case "${1}" in
  build)
    [ -z "${DOCKER_BUILD_BARRIER:-}" ] || barrier "build-$(sed -E 's/.*--tag ([^ ]+).*/\1/' <<< "$*")" "${DOCKER_BUILD_BARRIER}"
    ;;
  inspect)
    ref="${*: -1}"
    printf 'ghcr.io/keelcore/keel@sha256:%s\n' "${ref##*:}"
    ;;
  save) : > "${3}" ;;
  buildx)
    case "${3}" in
      inspect)
        if [ "${5:-}" = '--raw' ]; then
          printf '{"manifests":[{"platform":{"os":"linux"},"digest":"sha256:a"},{"platform":{"os":"linux"},"digest":"sha256:b"}]}\n'
        else
          case "${4}" in
            *-min) printf '{"digest":"sha256:min"}\n' ;;
            *-fips) printf '{"digest":"sha256:fips"}\n' ;;
            *) printf '{"digest":"sha256:max"}\n' ;;
          esac
        fi
        ;;
    esac
    ;;
esac
DOCKER
  cat > "${WORK}/bin/gh" <<'GH'
#!/usr/bin/env bash
source "${WORK}/bin/stub-lib"
record "gh $*"
maybe_fail "gh $*"
GH
  cat > "${WORK}/scripts/dev/run.sh" <<'RUN'
#!/usr/bin/env bash
source "${WORK}/bin/stub-lib"
record "dev GRYPE_DB_AUTO_UPDATE=${GRYPE_DB_AUTO_UPDATE:-} $*"
maybe_fail "dev $*"
if [ -n "${VERIFY_BARRIER:-}" ] && [[ "$*" =~ cosign\.sh\ verify\ .*@sha256:(max|min|fips)$ ]]; then
  barrier "verify-${BASH_REMATCH[1]}" "${VERIFY_BARRIER}"
fi
if [ -n "${BLOB_BARRIER:-}" ] && [[ "$*" =~ verify-blob ]]; then
  barrier "blob-${*##*/}" "${BLOB_BARRIER}"
fi
RUN
  chmod +x "${WORK}/bin/git" "${WORK}/bin/docker" "${WORK}/bin/gh" "${WORK}/scripts/dev/run.sh" \
    "${WORK}/scripts/release/docker.sh"
}

calls() { grep -E "${1}" "${STATE}/calls"; }
call_count() { grep -cE "${1}" "${STATE}/calls" || true; }

# --- docker.sh ---------------------------------------------------------------------------------

@test "docker.sh: all six images build concurrently" {
  export DOCKER_BUILD_BARRIER=6
  run ./scripts/release/docker.sh
  [ "${status}" -eq 0 ]
}

@test "docker.sh: each index holds its amd64 and arm64 images, in that order" {
  run ./scripts/release/docker.sh
  [ "${status}" -eq 0 ]
  calls 'imagetools create --tag ghcr.io/keelcore/keel:v1.2.3 ghcr.io/keelcore/keel@sha256:v1.2.3-amd64 ghcr.io/keelcore/keel@sha256:v1.2.3-arm64$'
  calls 'imagetools create --tag ghcr.io/keelcore/keel:v1.2.3-min ghcr.io/keelcore/keel@sha256:v1.2.3-min-amd64 ghcr.io/keelcore/keel@sha256:v1.2.3-min-arm64$'
  calls 'imagetools create --tag ghcr.io/keelcore/keel:v1.2.3-fips ghcr.io/keelcore/keel@sha256:v1.2.3-fips-amd64 ghcr.io/keelcore/keel@sha256:v1.2.3-fips-arm64$'
}

@test "docker.sh: records each flavor's index digest for the workflow" {
  run ./scripts/release/docker.sh
  [ "${status}" -eq 0 ]
  grep -qx 'max_digest=sha256:max' "${GITHUB_OUTPUT}"
  grep -qx 'min_digest=sha256:min' "${GITHUB_OUTPUT}"
  grep -qx 'fips_digest=sha256:fips' "${GITHUB_OUTPUT}"
}

@test "docker.sh: each image is signed and attested, by digest" {
  run ./scripts/release/docker.sh
  [ "${status}" -eq 0 ]
  [ "$(call_count 'cosign\.sh sign --yes ')" -eq 9 ]
  [ "$(call_count 'cosign\.sh attest --yes --predicate .*spdx\.json')" -eq 6 ]
  [ "$(call_count 'cosign\.sh attest --yes --predicate .*openvex')" -eq 3 ]
}

@test "docker.sh: the grype database is fetched once, before any scan, and scans leave it alone" {
  run ./scripts/release/docker.sh
  [ "${status}" -eq 0 ]
  [ "$(call_count 'grype db update')" -eq 1 ]
  local update first_scan
  update="$(grep -n 'grype db update' "${STATE}/calls" | head -1 | cut -d: -f1)"
  first_scan="$(grep -n 'grype sbom:' "${STATE}/calls" | head -1 | cut -d: -f1)"
  [ "${update}" -lt "${first_scan}" ]
  [ "$(call_count 'GRYPE_DB_AUTO_UPDATE=false grype sbom:')" -eq 6 ]
}

@test "docker.sh: a scan finding fails the release before that image is pushed" {
  export FAIL_ON='grype sbom:dist/sbom-min-arm64'
  run ./scripts/release/docker.sh
  [ "${status}" -ne 0 ]
  [ "$(call_count 'docker push .*-min-arm64$')" -eq 0 ]
  [ "$(call_count 'imagetools create --tag ghcr.io/keelcore/keel:v1.2.3-min ')" -eq 0 ]
}

@test "docker.sh: a failed push fails the release" {
  export FAIL_ON='docker push .*-fips-amd64$'
  run ./scripts/release/docker.sh
  [ "${status}" -ne 0 ]
  [ "$(call_count 'imagetools create --tag ghcr.io/keelcore/keel:v1.2.3-fips ')" -eq 0 ]
}

@test "docker.sh: a failure in max leaves the aliases where they were" {
  export FAIL_ON='grype sbom:dist/sbom-max-amd64'
  run ./scripts/release/docker.sh
  [ "${status}" -ne 0 ]
  [ "$(call_count 'imagetools create --tag ghcr.io/keelcore/keel:(v1|v1\.2|latest) ')" -eq 0 ]
}

@test "docker.sh: aliases move after the max index is signed" {
  run ./scripts/release/docker.sh
  [ "${status}" -eq 0 ]
  local signed alias
  signed="$(grep -n 'cosign\.sh sign --yes ghcr.io/keelcore/keel@sha256:max$' "${STATE}/calls" | head -1 | cut -d: -f1)"
  alias="$(grep -n 'imagetools create --tag ghcr.io/keelcore/keel:latest' "${STATE}/calls" | head -1 | cut -d: -f1)"
  [ -n "${signed}" ]
  [ "${signed}" -lt "${alias}" ]
}

# --- verify-release.sh -------------------------------------------------------------------------

verify_env() {
  export MAX_DIGEST=sha256:max MIN_DIGEST=sha256:min FIPS_DIGEST=sha256:fips
}

@test "verify-release.sh: the three indexes verify concurrently" {
  verify_env
  export VERIFY_BARRIER=3
  run bash scripts/release/verify-release.sh
  [ "${status}" -eq 0 ]
}

@test "verify-release.sh: the blobs verify concurrently" {
  verify_env
  export BLOB_BARRIER=7
  run bash scripts/release/verify-release.sh
  [ "${status}" -eq 0 ]
}

@test "verify-release.sh: checks every index, arch image, alias, blob and the chart" {
  verify_env
  run bash scripts/release/verify-release.sh
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'Release v1.2.3 verified'* ]]
  [ "$(call_count 'cosign\.sh verify-attestation .*--type openvex ')" -eq 3 ]
  [ "$(call_count 'gh attestation verify oci://')" -eq 3 ]
  [ "$(call_count 'cosign\.sh verify-attestation .*spdx\.dev')" -eq 6 ]
  [ "$(call_count 'cosign\.sh verify-blob ')" -eq 7 ]
  [ "$(call_count 'gh attestation verify dist/')" -eq 6 ]
  [ "$(call_count 'imagetools inspect ghcr.io/keelcore/keel:(v1|v1\.2|latest) ')" -eq 3 ]
  [ "$(call_count 'cosign\.sh verify .*charts/keel:1\.2\.3$')" -eq 1 ]
}

@test "verify-release.sh: gh attestation verify never runs concurrently: its cache is not safe for that" {
  verify_env
  cat > "${WORK}/bin/gh" <<'GH'
#!/usr/bin/env bash
source "${WORK}/bin/stub-lib"
record "gh $*"
if ! mkdir "${STATE}/gh-running" 2> /dev/null; then
  printf 'overlap\n' >> "${STATE}/gh-overlaps"
fi
sleep 0.2
rmdir "${STATE}/gh-running" 2> /dev/null || true
GH
  run bash scripts/release/verify-release.sh
  [ "${status}" -eq 0 ]
  [ "$(call_count '^gh attestation verify')" -eq 9 ]
  [ ! -f "${STATE}/gh-overlaps" ]
}

@test "verify-release.sh: one failed check fails the whole verification" {
  verify_env
  local check
  for check in 'cosign\.sh verify .*@sha256:fips$' 'gh attestation verify dist/keel-min-linux-arm64 ' \
    'cosign\.sh verify .*charts/keel' 'imagetools inspect ghcr.io/keelcore/keel:latest '; do
    export FAIL_ON="${check}"
    run bash scripts/release/verify-release.sh
    [ "${status}" -ne 0 ] || { printf 'passed with %s failing\n' "${check}" >&3; false; }
    [[ "${output}" != *'Release v1.2.3 verified'* ]]
  done
}

@test "verify-release.sh: an alias on the wrong digest fails" {
  export MAX_DIGEST=sha256:other MIN_DIGEST=sha256:min FIPS_DIGEST=sha256:fips
  run bash scripts/release/verify-release.sh
  [ "${status}" -ne 0 ]
}

# --- upload.sh ---------------------------------------------------------------------------------

stub_release_gh() {
  cat > "${WORK}/bin/gh" <<'GH'
#!/usr/bin/env bash
source "${WORK}/bin/stub-lib"
record "gh $*"
maybe_fail "gh $*"
if [ -n "${UPLOAD_BARRIER:-}" ] && [ "${2:-}" = upload ]; then
  barrier "$(basename "${4}")" "${UPLOAD_BARRIER}"
fi
GH
  export RELEASE_TAG=v1.2.3
}

@test "upload.sh: assets upload concurrently, one call per asset" {
  stub_release_gh
  export UPLOAD_BARRIER=8
  run bash scripts/release/upload.sh
  [ "${status}" -eq 0 ]
  [ "$(call_count '^gh release upload v1\.2\.3 [^ ]+ --clobber$')" -ge 8 ]
}

@test "upload.sh: a failed asset fails the step" {
  stub_release_gh
  export FAIL_ON='gh release upload v1\.2\.3 dist/SHA256SUMS '
  run bash scripts/release/upload.sh
  [ "${status}" -ne 0 ]
}

@test "upload.sh: PROVENANCE_BUNDLE may name the directory an artifact downloaded into" {
  stub_release_gh
  mkdir provenance
  printf '{"dsseEnvelope":{"payload":"x"}}\n' > provenance/whatever.jsonl
  export PROVENANCE_BUNDLE=provenance
  run bash scripts/release/upload.sh
  [ "${status}" -eq 0 ]
  grep -q '"payload":"x"' dist/keel.intoto.jsonl
}

@test "upload.sh --publish: the image SBOMs attach concurrently, and publishing comes last" {
  stub_release_gh
  local flavor arch
  for flavor in max min fips; do
    for arch in amd64 arm64; do
      printf '{}' > "dist/sbom-${flavor}-${arch}.spdx.json"
    done
  done
  export UPLOAD_BARRIER=6
  run bash scripts/release/upload.sh --publish
  [ "${status}" -eq 0 ]
  tail -1 "${STATE}/calls" | grep -q 'gh release edit v1\.2\.3 --draft=false --latest'
}

@test "upload.sh --publish: a failed SBOM upload leaves the release a draft" {
  stub_release_gh
  local flavor arch
  for flavor in max min fips; do
    for arch in amd64 arm64; do
      printf '{}' > "dist/sbom-${flavor}-${arch}.spdx.json"
    done
  done
  export FAIL_ON='gh release upload v1\.2\.3 dist/sbom-min-arm64'
  run bash scripts/release/upload.sh --publish
  [ "${status}" -ne 0 ]
  [ "$(call_count 'gh release edit')" -eq 0 ]
}


# --- another project ---------------------------------------------------------------------------

@test "docker.sh: a repository with no configured images has nothing to do" {
  rm config/release-images.local.txt
  run ./scripts/release/docker.sh
  [ "${status}" -eq 0 ]
  [ "$(call_count 'docker build')" -eq 0 ]
}

@test "docker.sh: runs the project's hook before building" {
  printf 'printf "hook\\n" >> "%s/calls"\n' "${STATE}" > scripts/release/docker.local.sh
  run ./scripts/release/docker.sh
  [ "${status}" -eq 0 ]
  [ "$(grep -n '^hook$' "${STATE}/calls" | cut -d: -f1)" -lt "$(grep -n 'docker build' "${STATE}/calls" | head -1 | cut -d: -f1)" ]
}

@test "docker.sh: images, binaries and the OpenVEX document follow the project" {
  printf 'module github.com/acme/widget\n' > go.mod
  printf 'acme/widget\n' > config/release-repo.local.txt
  printf 'std\t\n' > config/release-images.local.txt
  printf '{}' > dist/widget.openvex.json
  local arch
  for arch in amd64 arm64; do
    printf 'b' > "dist/widget-std-linux-${arch}"
  done
  run ./scripts/release/docker.sh
  [ "${status}" -eq 0 ]
  calls 'docker build .*--tag ghcr.io/acme/widget:v1.2.3-amd64'
  calls 'imagetools create --tag ghcr.io/acme/widget:latest'
  calls 'attest .*widget.openvex.json'
  grep -qx 'std_digest=.*' "${GITHUB_OUTPUT}"
}

@test "verify-release.sh: the identity and refs follow the repository" {
  printf 'acme/widget\n' > config/release-repo.local.txt
  printf 'module github.com/acme/widget\n' > go.mod
  printf 'std\t\n' > config/release-images.local.txt
  : > dist/widget-std-linux-amd64
  : > dist/widget-std-linux-amd64.bundle
  rm -f dist/keel-*
  export STD_DIGEST=sha256:max
  run bash scripts/release/verify-release.sh
  [ "${status}" -eq 0 ]
  grep -qF 'github\.com/acme/widget/\.github/workflows/release' "${STATE}/calls"
  calls 'gh attestation verify oci://ghcr.io/acme/widget@sha256:max --repo acme/widget'
}

@test "docker.sh: images carry the name of the dev image that built them" {
  mkdir -p containers/dev
  printf 'ghcr.io/keelcore/keel-dev:ctx-abc\n' > containers/dev/image.ref
  run ./scripts/release/docker.sh
  [ "${status}" -eq 0 ]
  calls 'docker build .*--label io\.keelcore\.dev-image=ghcr\.io/keelcore/keel-dev:ctx-abc'
}
