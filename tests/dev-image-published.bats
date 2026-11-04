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
