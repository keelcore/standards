#!/usr/bin/env bats
# tests/dev-image-published.bats
# A tool image is built once per build context and pulled everywhere else:
#   - run.sh uses the image its context names, on this machine or published, and builds locally
#     only when that context is unpublished;
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

@test "dev_published_ref: a published context resolves to its name" {
  fake_registry 1
  published
  [ "${status}" -eq 0 ]
  [ "${output}" = 'ghcr.io/keelcore/x-dev:ctx-abc' ]
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

# standards_ref_with PUBLISHED: publish.sh's standards_ref, with its context published or not.
standards_ref_with() {
  fake_registry "${1}"
  sed -n '/^function standards_ref()/,/^}/p' "${STANDARDS}/scripts/dev/publish.sh" > "${WORK}/standards_ref.sh"
  mkdir -p "${WORK}/s/.standards/containers/dev"
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

@test "publish.sh: builds on the published .standards image of its context" {
  standards_ref_with 1
  [ "${status}" -eq 0 ]
  [ "${output}" = 'ghcr.io/keelcore/x-dev:ctx-abc' ]
}

@test "publish.sh: an unpublished .standards context stops the publish, and says so" {
  standards_ref_with 0
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'ctx-abc'* ]]
  [[ "${output}" == *'not published'* ]]
}

# dev_image_with PUBLISHED [LOCAL]: run.sh's dev_image with the registry answering PUBLISHED, and the
# image on this machine when LOCAL=1; prints the reference and whether it built.
dev_image_with() {
  sed -n '/^function dev_image()/,/^}/p' "${STANDARDS}/scripts/dev/run.sh" > "${WORK}/dev_image.sh"
  run bash -c "
    log() { :; }
    runtime() { printf docker; }
    docker() { [ '${2:-0}' = 1 ] && [ \"\${3}\" = 'ghcr.io/keelcore/x-dev:ctx-abc' ]; }
    dev_containerfile() { printf 'containers/x/Containerfile'; }
    dev_base_ref() { :; }
    dev_tree_hash() { printf abc; }
    dev_pin_ref() { printf ghcr.io/keelcore/x-dev:ctx-abc; }
    dev_repository() { printf 'ghcr.io/keelcore/x-dev'; }
    dev_repo_name() { printf x; }
    dev_published_ref() { echo published-asked >> '${WORK}/asked'; [ '${1}' = 1 ]; }
    build_image() { printf 'BUILT ' >&2; }
    source '${WORK}/dev_image.sh'
    mkdir -p '${WORK}/repo/containers/x'
    : > '${WORK}/repo/containers/x/Containerfile'
    dev_image '${WORK}/repo' x 2>&1
  "
}

@test "run.sh: a published context is used, without building" {
  dev_image_with 1
  [ "${status}" -eq 0 ]
  [ "${output}" = 'ghcr.io/keelcore/x-dev:ctx-abc' ]
}

@test "run.sh: an image already on this machine is used, without asking the registry" {
  dev_image_with 0 1
  [ "${status}" -eq 0 ]
  [ "${output}" = 'ghcr.io/keelcore/x-dev:ctx-abc' ]
  [ ! -e "${WORK}/asked" ]
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

# ref_repo: a repository at WORK/r with a published dev image, and a runtime
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
  PIN="$(bash -c "source '${STANDARDS}/scripts/lib/dev-image.sh'; dev_pin_ref . dev")"
  printf '#!/usr/bin/env bash\ncase "$*" in\n  *token*) printf "{\\"token\\":\\"T\\"}" ;;\n  *) printf "docker-content-digest: %s\\r\\n" ;;\nesac\n' "${DIGEST}" > "${WORK}/fake/curl"
  chmod +x "${WORK}/fake/curl"
}

@test "run.sh --image-ref: names the image, with nothing fetched or built" {
  ref_repo
  PATH="${WORK}/fake:${PATH}" run --separate-stderr bash "${STANDARDS}/scripts/dev/run.sh" --image-ref
  [ "${status}" -eq 0 ]
  [ "${output}" = "${PIN}" ]
  [ -z "$(grep -E " pull |^build|^image pull" "${WORK}/calls" 2> /dev/null)" ]
}

@test "run.sh --image-ref: an unpublished context names its local tag, unbuilt" {
  ref_repo
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
  grep -qE "^image pull( --progress plain)? ${PIN}\$" "${WORK}/calls"
  : > "${WORK}/calls"
  touch "${WORK}/found"
  PATH="${WORK}/fake:${PATH}" run bash "${STANDARDS}/scripts/dev/run.sh" --fetch-image
  [ "${status}" -eq 0 ]
  [ -z "$(grep ' pull ' "${WORK}/calls")" ]
}

# on_host OS: uname reports OS, so run.sh picks that host's runtime.
on_host() {
  printf '#!/usr/bin/env bash\nif [ "${1:-}" = "-s" ]; then echo %s; else echo arm64; fi\n' "${1}" > "${WORK}/fake/uname"
  chmod +x "${WORK}/fake/uname"
}

@test "run.sh --fetch-image: Apple container prints progress without a terminal" {
  ref_repo
  on_host Darwin
  PATH="${WORK}/fake:${PATH}" run bash "${STANDARDS}/scripts/dev/run.sh" --fetch-image
  [ "${status}" -eq 0 ]
  grep -qxF "image pull --progress plain ${PIN}" "${WORK}/calls"
}

@test "run.sh --fetch-image: docker pull takes no progress flag" {
  ref_repo
  on_host Linux
  PATH="${WORK}/fake:${PATH}" run bash "${STANDARDS}/scripts/dev/run.sh" --fetch-image
  [ "${status}" -eq 0 ]
  grep -qxF "image pull ${PIN}" "${WORK}/calls"
}

# slow_runtime SECONDS: the fake runtime takes SECONDS to build or pull, printing a build step first.
slow_runtime() {
  for tool in container docker; do
    printf '#!/usr/bin/env bash\necho "$*" >> "%s/calls"\ncase "${1} ${2:-}" in\n  "image inspect") exit 1 ;;\n  "build -f"|"image pull") echo "#7 [linux/arm64 stage-1 3/9] RUN bash scripts/ci/setup-x.sh"; echo "#7 0.020 Installing x"; sleep %s ;;\nesac\n' \
      "${WORK}" "${1}" > "${WORK}/fake/${tool}"
    chmod +x "${WORK}/fake/${tool}"
  done
}

@test "run.sh: a long build prints progress at the interval, with its step" {
  ref_repo
  printf '#!/usr/bin/env bash\nexit 22\n' > "${WORK}/fake/curl"
  slow_runtime 3
  KEELCORE_DEV_PROGRESS_SECONDS=1 PATH="${WORK}/fake:${PATH}" run bash "${STANDARDS}/scripts/dev/run.sh" --fetch-image
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'⏳'*'building'*'step 3/9: Installing x'* ]]
}

@test "run.sh: a build that passes its time limit is stopped and fails, saying so" {
  ref_repo
  printf '#!/usr/bin/env bash\nexit 22\n' > "${WORK}/fake/curl"
  slow_runtime 60
  local -r started="${SECONDS}"
  KEELCORE_DEV_BUILD_TIMEOUT=2 PATH="${WORK}/fake:${PATH}" run bash "${STANDARDS}/scripts/dev/run.sh" --fetch-image
  [ "${status}" -ne 0 ]
  [ $(( SECONDS - started )) -lt 20 ]
  [[ "${output}" == *'time limit'* ]]
}

@test "run.sh: a pull that passes its time limit is stopped and fails, saying so" {
  ref_repo
  slow_runtime 60
  local -r started="${SECONDS}"
  KEELCORE_DEV_PULL_TIMEOUT=2 PATH="${WORK}/fake:${PATH}" run bash "${STANDARDS}/scripts/dev/run.sh" --fetch-image
  [ "${status}" -ne 0 ]
  [ $(( SECONDS - started )) -lt 20 ]
  [[ "${output}" == *'time limit'* ]]
}

@test "setup scripts: every download retries and gives up on a stalled connection" {
  local file line
  for file in "${STANDARDS}"/scripts/ci/setup-*.sh; do
    while IFS= read -r line; do
      # An options array stands for its definition in the same file.
      [[ "${line}" != *'CURL_RETRY'* ]] || line="$(grep -E '^readonly CURL_RETRY=' "${file}")"
      [[ "${line}" == *'--retry'* ]] || { echo "no retry: ${file}: ${line}"; false; }
      [[ "${line}" == *'--connect-timeout'* ]] || { echo "no connect timeout: ${file}: ${line}"; false; }
      [[ "${line}" == *'--speed-time'* && "${line}" == *'--speed-limit'* ]] || { echo "no stall limit: ${file}: ${line}"; false; }
    done < <(grep -E '^\s*[^#]*\bcurl ' "${file}")
  done
}

@test "run.sh: a builder that does not answer stops the run at its time limit, saying so" {
  ref_repo
  printf '#!/usr/bin/env bash\nexit 22\n' > "${WORK}/fake/curl"
  printf '#!/usr/bin/env bash\ncase "${1} ${2:-}" in\n  "image inspect") exit 1 ;;\n  "builder status") sleep 60 ;;\nesac\n' > "${WORK}/fake/container"
  chmod +x "${WORK}/fake/container"
  printf '#!/usr/bin/env bash\nif [ "${1:-}" = "-s" ]; then echo Darwin; else echo arm64; fi\n' > "${WORK}/fake/uname"
  chmod +x "${WORK}/fake/uname"
  local -r started="${SECONDS}"
  KEELCORE_DEV_BUILDER_TIMEOUT=2 PATH="${WORK}/fake:${PATH}" run bash "${STANDARDS}/scripts/dev/run.sh" --fetch-image
  [ "${status}" -ne 0 ]
  [ $(( SECONDS - started )) -lt 20 ]
  [[ "${output}" == *'time limit'* ]]
}

@test "scripts: every network call has a connect timeout and a stall or total limit" {
  local line
  while IFS= read -r line; do
    [[ "${line}" == *'CURL_RETRY'* ]] && continue
    [[ "${line}" == *'--connect-timeout'* || "${line}" == *'--max-time'* ]] || { echo "unbounded: ${line}"; false; }
    [[ "${line}" == *'--speed-time'* || "${line}" == *'--max-time'* ]] || { echo "no stall limit: ${line}"; false; }
  done < <(cd "${STANDARDS}" && grep -rnE '^\s*[^#]*\bcurl (-|--)' scripts --include='*.sh' | grep -v 'curl()' )
}
