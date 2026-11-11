#!/usr/bin/env bats
# tests/sign-image.bats
# scripts/release/sign-image.sh gives every published image index the same treatment, each step skipped when
# this repository's workflows already did it: a keyless cosign signature, an SPDX SBOM attestation and SLSA
# build provenance, both in the registry beside the image, and the provenance bundle in GitHub's attestation
# store too.

bats_require_minimum_version 1.5.0

setup() {
  STANDARDS="$(cd "${BATS_TEST_DIRNAME}/.." && pwd -P)"
  WORK="${BATS_TEST_TMPDIR}"
  R="${WORK}/widget"
  mkdir -p "${R}/scripts/release" "${R}/scripts/lib" "${WORK}/bin" "${WORK}/state"
  cp "${STANDARDS}/scripts/release/sign-image.sh" "${R}/scripts/release/"
  cp "${STANDARDS}"/scripts/lib/*.sh "${R}/scripts/lib/"
  cd "${R}"
  HEX="$(printf 'e%.0s' {1..64})"
  REF="ghcr.io/keelcore/widget-certs@sha256:${HEX}"
  : > "${WORK}/calls"
  fakes
  mkdir -p "${WORK}/docker-config"
  printf '{}' > "${WORK}/docker-config/config.json"
  export WORK DOCKER_CONFIG="${WORK}/docker-config" PATH="${WORK}/bin:${PATH}"
  export GITHUB_REPOSITORY=keelcore/widget GITHUB_TOKEN=t GITHUB_ACTOR=a
  export GITHUB_SERVER_URL=https://github.com GITHUB_API_URL=https://api.github.com
  export GITHUB_WORKFLOW_REF='keelcore/widget/.github/workflows/ci.yml@refs/heads/main'
  export GITHUB_SHA=0123456789abcdef0123456789abcdef01234567 GITHUB_REF=refs/heads/main GITHUB_EVENT_NAME=push
  export GITHUB_REPOSITORY_ID=11 GITHUB_REPOSITORY_OWNER_ID=22 GITHUB_RUN_ID=33 GITHUB_RUN_ATTEMPT=1
  export RUNNER_ENVIRONMENT=github-hosted
}

# fakes: cosign verify passes once state/signed exists, verify-attestation once state/<type> exists, and
# attest keeps each predicate it is given; generate-sbom writes the SBOM it is asked for; curl answers as
# GHCR (the provenance bundle under the sha256-<digest> tag) and the GitHub attestations API (state/github
# holds one attestation), keeping what is posted.
fakes() {
  cat > "${WORK}/bin/cosign" <<'EOF'
#!/usr/bin/env bash
echo "cosign $*" >> "${WORK}/calls"
sub="${1}" type='' predicate=''
while [ "${#}" -gt 0 ]; do
  case "${1}" in --type) type="${2}"; shift ;; --predicate) predicate="${2}"; shift ;; esac
  shift
done
key="$(printf '%s' "${type}" | tr -c 'A-Za-z0-9' '_')"
case "${sub}" in
  verify) [ -e "${WORK}/state/signed" ] ;;
  verify-attestation) [ -e "${WORK}/state/${key}" ] ;;
  attest) cp "${predicate}" "${WORK}/predicate-${key}.json" ;;
esac
EOF
  cat > scripts/release/generate-sbom.sh <<'EOF'
#!/usr/bin/env bash
echo "generate-sbom $*" >> "${WORK}/calls"
mkdir -p "${2}" && printf '{}' > "${2}/${4}.spdx.json"
EOF
  cat > "${WORK}/bin/curl" <<EOF
#!/usr/bin/env bash
url="\${*: -1}"
echo "curl \${url}" >> "${WORK}/calls"
prev=''
for a in "\$@"; do
  [ "\${prev}" = --data-binary ] && cp "\${a#@}" "${WORK}/posted.json"
  prev="\${a}"
done
case "\${url}" in
  'https://ghcr.io/token?scope=repository:keelcore/widget-certs:pull') printf '{"token":"T"}' ;;
  'https://ghcr.io/v2/keelcore/widget-certs/manifests/sha256-${HEX}')
    printf '{"manifests":[{"digest":"sha256:sig","annotations":{"dev.sigstore.bundle.predicateType":"https://sigstore.dev/cosign/sign/v1"}},{"digest":"sha256:prov","annotations":{"dev.sigstore.bundle.predicateType":"https://slsa.dev/provenance/v1"}}]}' ;;
  'https://ghcr.io/v2/keelcore/widget-certs/manifests/sha256:prov') printf '{"layers":[{"digest":"sha256:bundle"}]}' ;;
  'https://ghcr.io/v2/keelcore/widget-certs/blobs/sha256:bundle')
    printf '{"mediaType":"application/vnd.dev.sigstore.bundle.v0.3+json","dsseEnvelope":{}}' ;;
  'https://api.github.com/repos/keelcore/widget/attestations/sha256:${HEX}?predicate_type=provenance')
    if [ -e "${WORK}/state/github" ]; then printf '{"attestations":[{"bundle":{}}]}'; else printf '{"attestations":[]}'; fi ;;
  'https://api.github.com/repos/keelcore/widget/attestations') printf '{"id":1}' ;;
  *) exit 22 ;;
esac
EOF
  chmod +x "${WORK}/bin/cosign" "${WORK}/bin/curl" scripts/release/generate-sbom.sh
}

readonly SPDX_KEY='https___spdx_dev_Document'
readonly SLSA_KEY='https___slsa_dev_provenance_v1'

done_already() {
  touch "${WORK}/state/signed" "${WORK}/state/${SPDX_KEY}" "${WORK}/state/${SLSA_KEY}" "${WORK}/state/github"
}

@test "sign-image.sh: a new index is signed, with its SBOM and provenance in the registry and in GitHub's store" {
  run bash scripts/release/sign-image.sh "${REF}" ctx-abc
  [ "${status}" -eq 0 ]
  grep -qxF "cosign sign --yes ${REF}" "${WORK}/calls"
  grep -qE "^generate-sbom --out-dir [^ ]+ --name widget-certs --version ctx-abc ${REF}$" "${WORK}/calls"
  grep -qE "^cosign attest --yes --type https://spdx\.dev/Document --predicate [^ ]+/widget-certs\.spdx\.json ${REF}$" "${WORK}/calls"
  grep -qE "^cosign attest --yes --type https://slsa\.dev/provenance/v1 --predicate [^ ]+ ${REF}$" "${WORK}/calls"
  # The bundle GHCR holds is the one posted to GitHub.
  [ "$(jq -r '.bundle.mediaType' "${WORK}/posted.json")" = 'application/vnd.dev.sigstore.bundle.v0.3+json' ]
}

@test "sign-image.sh: the provenance names the workflow, its commit and its run, as GitHub's own does" {
  run bash scripts/release/sign-image.sh "${REF}" ctx-abc
  [ "${status}" -eq 0 ]
  local -r p="${WORK}/predicate-${SLSA_KEY}.json"
  [ "$(jq -r '.buildDefinition.buildType' "${p}")" = 'https://actions.github.io/buildtypes/workflow/v1' ]
  [ "$(jq -r '.buildDefinition.externalParameters.workflow.repository' "${p}")" = 'https://github.com/keelcore/widget' ]
  [ "$(jq -r '.buildDefinition.externalParameters.workflow.path' "${p}")" = '.github/workflows/ci.yml' ]
  [ "$(jq -r '.buildDefinition.externalParameters.workflow.ref' "${p}")" = 'refs/heads/main' ]
  [ "$(jq -r '.buildDefinition.internalParameters.github.event_name' "${p}")" = 'push' ]
  [ "$(jq -r '.buildDefinition.internalParameters.github.runner_environment' "${p}")" = 'github-hosted' ]
  [ "$(jq -r '.buildDefinition.resolvedDependencies[0].uri' "${p}")" = 'git+https://github.com/keelcore/widget@refs/heads/main' ]
  [ "$(jq -r '.buildDefinition.resolvedDependencies[0].digest.gitCommit' "${p}")" = "${GITHUB_SHA}" ]
  [ "$(jq -r '.runDetails.builder.id' "${p}")" = 'https://github.com/keelcore/widget/.github/workflows/ci.yml@refs/heads/main' ]
  [ "$(jq -r '.runDetails.metadata.invocationId' "${p}")" = 'https://github.com/keelcore/widget/actions/runs/33/attempts/1' ]
}

@test "sign-image.sh: an index that has everything is left alone" {
  done_already
  run bash scripts/release/sign-image.sh "${REF}" ctx-abc
  [ "${status}" -eq 0 ]
  [ -z "$(grep -E '^cosign (sign|attest) |^generate-sbom ' "${WORK}/calls")" ]
  [ ! -e "${WORK}/posted.json" ]
}

@test "sign-image.sh: provenance missing only from GitHub's store is posted from the registry, not attested again" {
  done_already
  rm "${WORK}/state/github"
  run bash scripts/release/sign-image.sh "${REF}" ctx-abc
  [ "${status}" -eq 0 ]
  [ -z "$(grep -E '^cosign (sign|attest) ' "${WORK}/calls")" ]
  [ "$(jq -r '.bundle.mediaType' "${WORK}/posted.json")" = 'application/vnd.dev.sigstore.bundle.v0.3+json' ]
}

@test "sign-image.sh: outside a GitHub Actions run it fails before signing, naming what is missing" {
  unset GITHUB_WORKFLOW_REF
  run bash scripts/release/sign-image.sh "${REF}" ctx-abc
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'GITHUB_WORKFLOW_REF'* ]] || false
  [ -z "$(grep -E '^cosign (sign|attest) ' "${WORK}/calls")" ]
}

@test "sign-image.sh: a reference that is not REPOSITORY@sha256:DIGEST is refused" {
  run bash scripts/release/sign-image.sh ghcr.io/keelcore/widget-certs:ctx-abc
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'Usage: sign-image.sh REPOSITORY@sha256:DIGEST'* ]] || false
}
