#!/usr/bin/env bats
# tests/dev-image-published.bats
# A tool image is built once per build context and pulled everywhere else:
#   - run.sh uses the published ctx-<hash> image from the registry when image.ref pins
#     another context, and builds locally only when that context is unpublished;
#   - CI publishes the context once (the reusable dev-image workflow, called first by
#     ci.yml), and every tool job waits for it instead of building it itself.

bats_require_minimum_version 1.5.0

setup() {
  STANDARDS="$(cd "${BATS_TEST_DIRNAME}/.." && pwd -P)"
  WORK="${BATS_TEST_TMPDIR}"
  mkdir -p "${WORK}/bin"
  DIGEST="sha256:$(printf '%064d' 7)"
}

# fake_registry PUBLISHED: a curl on PATH that answers like ghcr.io for
# ghcr.io/keelcore/x-dev: a pull token, and the manifest of ctx-abc when PUBLISHED=1.
fake_registry() {
  cat > "${WORK}/bin/curl" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *'ghcr.io/token?scope=repository:keelcore/x-dev:pull'*) printf '{"token":"T"}' ;;
  *'ghcr.io/v2/keelcore/x-dev/manifests/ctx-abc'*)
    [ "${1}" = 1 ] || exit 22
    printf 'HTTP/2 200\r\ndocker-content-digest: ${DIGEST}\r\ncontent-type: application/vnd.oci.image.index.v1+json\r\n\r\n' ;;
  *) exit 22 ;;
esac
EOF
  chmod +x "${WORK}/bin/curl"
}

published() {
  run bash -c "PATH='${WORK}/bin':\"\${PATH}\"; source '${STANDARDS}/scripts/lib/dev-image.sh'; dev_published_ref ghcr.io/keelcore/x-dev abc"
}

@test "dev_published_ref: a published context resolves to its digest" {
  fake_registry 1
  published
  [ "${status}" -eq 0 ]
  [ "${output}" = "ghcr.io/keelcore/x-dev:ctx-abc@${DIGEST}" ]
}

@test "dev_published_ref: an unpublished context, or no registry, is not found" {
  fake_registry 0
  published
  [ "${status}" -ne 0 ]
  [ -z "${output}" ]
  printf '#!/usr/bin/env bash\nexit 7\n' > "${WORK}/bin/curl"
  published
  [ "${status}" -ne 0 ]
}

# resolve_with PIN: dev_resolve_ref for context abc of a directory whose image.ref holds PIN.
resolve_with() {
  mkdir -p "${WORK}/x/containers/dev"
  printf '%s\n' "${1}" > "${WORK}/x/containers/dev/image.ref"
  run bash -c "
    PATH='${WORK}/bin':\"\${PATH}\"
    source '${STANDARDS}/scripts/lib/dev-image.sh'
    dev_repository() { printf ghcr.io/keelcore/x-dev; }
    dev_resolve_ref '${WORK}/x' dev abc"
}

@test "dev_resolve_ref: a matching pin wins, without asking the registry" {
  printf '#!/usr/bin/env bash\nexit 7\n' > "${WORK}/bin/curl"
  chmod +x "${WORK}/bin/curl"
  resolve_with "ghcr.io/keelcore/x-dev:ctx-abc@${DIGEST}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "ghcr.io/keelcore/x-dev:ctx-abc@${DIGEST}" ]
}

@test "dev_resolve_ref: a stale pin resolves to the published image of the context" {
  fake_registry 1
  resolve_with "ghcr.io/keelcore/x-dev:ctx-old@${DIGEST}"
  [ "${status}" -eq 0 ]
  [ "${output}" = "ghcr.io/keelcore/x-dev:ctx-abc@${DIGEST}" ]
}

@test "dev_resolve_ref: a stale pin and an unpublished context is not found" {
  fake_registry 0
  resolve_with "ghcr.io/keelcore/x-dev:ctx-old@${DIGEST}"
  [ "${status}" -ne 0 ]
  [ -z "${output}" ]
}

# standards_ref_with PUBLISHED: publish.sh's standards_ref, with .standards pinning another context.
standards_ref_with() {
  fake_registry "${1}"
  sed -n '/^function standards_ref()/,/^}/p' "${STANDARDS}/scripts/dev/publish.sh" > "${WORK}/standards_ref.sh"
  mkdir -p "${WORK}/s/.standards/containers/dev"
  printf 'ghcr.io/keelcore/x-dev:ctx-old@%s\n' "${DIGEST}" > "${WORK}/s/.standards/containers/dev/image.ref"
  run bash -c "
    PATH='${WORK}/bin':\"\${PATH}\"
    cd '${WORK}/s'
    log() { printf '%s\n' \"\${1}\" >&2; }
    source '${STANDARDS}/scripts/lib/dev-image.sh'
    dev_repository() { printf ghcr.io/keelcore/x-dev; }
    dev_context_hash() { printf abc; }
    source '${WORK}/standards_ref.sh'
    standards_ref"
}

@test "publish.sh: a stale .standards pin builds on the published image of its context" {
  standards_ref_with 1
  [ "${status}" -eq 0 ]
  [ "${output}" = "ghcr.io/keelcore/x-dev:ctx-abc@${DIGEST}" ]
}

@test "publish.sh: an unpublished .standards context stops the publish, and says so" {
  standards_ref_with 0
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'ctx-abc'* ]]
  [[ "${output}" == *'not published'* ]]
}

# dev_image_with PUBLISHED: run.sh's dev_image for a context image.ref does not pin,
# with the registry answering PUBLISHED; prints the reference and whether it built.
dev_image_with() {
  sed -n '/^function dev_image()/,/^}/p' "${STANDARDS}/scripts/dev/run.sh" > "${WORK}/dev_image.sh"
  run bash -c "
    log() { :; }
    runtime() { printf docker; }
    docker() { return 1; }
    dev_containerfile() { printf 'containers/x/Containerfile'; }
    dev_has_base() { return 1; }
    dev_context_hash() { printf abc; }
    dev_pinned_ref() { return 1; }
    dev_ref_file() { printf 'containers/x/image.ref'; }
    dev_repository() { printf 'ghcr.io/keelcore/x-dev'; }
    dev_repo_name() { printf x; }
    dev_published_ref() { [ '${1}' = 1 ] && printf 'ghcr.io/keelcore/x-dev:ctx-abc@${DIGEST}'; }
    dev_resolve_ref() { dev_pinned_ref "\$1" "\$2" "\$3" || dev_published_ref x abc; }
    build_image() { printf 'BUILT ' >&2; }
    source '${WORK}/dev_image.sh'
    mkdir -p '${WORK}/repo/containers/x'
    : > '${WORK}/repo/containers/x/Containerfile'
    printf 'ghcr.io/keelcore/x-dev:ctx-old@${DIGEST}\n' > '${WORK}/repo/containers/x/image.ref'
    dev_image '${WORK}/repo' x 2>&1
  "
}

@test "run.sh: a stale pin uses the published image for the tree's context, without building" {
  dev_image_with 1
  [ "${status}" -eq 0 ]
  [ "${output}" = "ghcr.io/keelcore/x-dev:ctx-abc@${DIGEST}" ]
}

@test "run.sh: an unpublished context is built locally" {
  dev_image_with 0
  [ "${status}" -eq 0 ]
  [ "${output}" = 'BUILT keelcore-x-x:ctx-abc' ]
}

# on_block FILE: the workflow's top-level `on:` block.
on_block() {
  awk '/^on:/ { on = 1; next } on && /^[^ #]/ { exit } on' "${1}"
}

@test "dev-image workflow: reusable, never triggered by a push, with its own concurrency group" {
  local -r wf="${STANDARDS}/.github/workflows/dev-image.yml"
  on_block "${wf}" | grep -q '^  workflow_call:'
  on_block "${wf}" | grep -q '^  workflow_dispatch:'
  ! on_block "${wf}" | grep -q '^  push:'
  grep -q '^  group: dev-image-' "${wf}"
}

# job_block FILE JOB: the lines of one job in a workflow.
job_block() {
  awk -v job="  ${2}:" '$0 == job { on = 1; next } on && /^  [a-z][a-z0-9_-]*:$/ { exit } on' "${1}"
}

@test "ci workflow: publishes the tool image first; every tool job needs it" {
  local -r wf="${STANDARDS}/.github/workflows/ci.yml"
  job_block "${wf}" dev-image | grep -q 'uses: ./.github/workflows/dev-image.yml'
  local job
  for job in $(awk '/^  [a-z][a-z0-9_-]*:$/ { sub(/:$/, ""); print $1 }' "${wf}"); do
    [ "${job}" = dev-image ] && continue
    if job_block "${wf}" "${job}" | grep -q 'run: make '; then
      job_block "${wf}" "${job}" | grep -Eq 'needs: (dev-image|\[.*dev-image.*\])' \
        || { echo "job ${job} runs tool targets without needs: dev-image"; return 1; }
    fi
  done
}

# ref_repo: a repository at WORK/r with a dev image whose pin matches its context, and a runtime
# that records every call: "image inspect" succeeds once FOUND exists.
ref_repo() {
  mkdir -p "${WORK}/r/containers/dev" "${WORK}/fake"
  printf 'FROM scratch\n' > "${WORK}/r/containers/dev/Containerfile"
  for tool in container docker; do
    printf '#!/usr/bin/env bash\necho "$*" >> "%s/calls"\n[ "${2}" != inspect ] || [ -f "%s/found" ]\n' "${WORK}" "${WORK}" \
      > "${WORK}/fake/${tool}"
    chmod +x "${WORK}/fake/${tool}"
  done
  cd "${WORK}/r"
  git init --quiet
  git add -A
  local hash
  hash="$(bash -c "source '${STANDARDS}/scripts/lib/dev-image.sh'; dev_context_hash . dev")"
  PIN="ghcr.io/keelcore/x-dev:ctx-${hash}@${DIGEST}"
  printf '%s\n' "${PIN}" > containers/dev/image.ref
}

@test "run.sh --image-ref: names the image, with nothing fetched or built" {
  ref_repo
  PATH="${WORK}/fake:${PATH}" run --separate-stderr bash "${STANDARDS}/scripts/dev/run.sh" --image-ref
  [ "${status}" -eq 0 ]
  [ "${output}" = "${PIN}" ]
  [ ! -e "${WORK}/calls" ]
}

@test "run.sh --image-ref: an unpublished context names its local tag, unbuilt" {
  ref_repo
  printf 'ghcr.io/keelcore/x-dev:ctx-old@%s\n' "${DIGEST}" > containers/dev/image.ref
  printf '#!/usr/bin/env bash\nexit 22\n' > "${WORK}/fake/curl"
  chmod +x "${WORK}/fake/curl"
  PATH="${WORK}/fake:${PATH}" run --separate-stderr bash "${STANDARDS}/scripts/dev/run.sh" --image-ref
  [ "${status}" -eq 0 ]
  [[ "${output}" == keelcore-dev-*:ctx-* ]]
  [ -z "$(grep -E ' build|^build' "${WORK}/calls" 2> /dev/null)" ]
}

@test "run.sh --fetch-image: pulls an absent image; a present one is left alone" {
  ref_repo
  PATH="${WORK}/fake:${PATH}" run bash "${STANDARDS}/scripts/dev/run.sh" --fetch-image
  [ "${status}" -eq 0 ]
  grep -qxF "image pull ${PIN}" "${WORK}/calls"
  : > "${WORK}/calls"
  touch "${WORK}/found"
  PATH="${WORK}/fake:${PATH}" run bash "${STANDARDS}/scripts/dev/run.sh" --fetch-image
  [ "${status}" -eq 0 ]
  [ -z "$(grep ' pull ' "${WORK}/calls")" ]
}
