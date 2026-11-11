#!/usr/bin/env bats
# tests/tool-images.bats
# A tool image is identified by its build file, wherever it lives: config/tool-images.local.txt lists
# the images not built from containers/NAME/Containerfile (NAME, build file, context dir), and each is
# named, built, published, signed and attested like a containers/NAME image, its name written beside
# its build file as <BUILD FILE>.image.ref.

bats_require_minimum_version 1.5.0

setup() {
  STANDARDS="$(cd "${BATS_TEST_DIRNAME}/.." && pwd -P)"
  WORK="${BATS_TEST_TMPDIR}"
  R="${WORK}/widget"
  # Inside a tool image run.sh names the repository it mounted; these tests name their own.
  unset KEELCORE_DEV_REPO
  export GIT_CONFIG_GLOBAL="${WORK}/gitconfig"
  git config --global user.name t
  git config --global user.email t@example.invalid
  git config --global commit.gpgsign false
  git config --global init.defaultBranch main
  mkdir -p "${R}/containers/dev" "${R}/scripts/dev" "${R}/scripts/lib" "${R}/scripts/ci" "${R}/scripts/release" \
    "${R}/scripts/certs" "${R}/config" "${R}/.git-hooks" "${WORK}/bin"
  cd "${R}"
  git init --quiet
  cp "${STANDARDS}"/scripts/dev/*.sh scripts/dev/
  cp "${STANDARDS}"/scripts/lib/*.sh scripts/lib/
  printf 'FROM scratch\nCOPY scripts/ci/setup-x.sh /x\n' > containers/dev/Containerfile
  printf 'one\n' > scripts/ci/setup-x.sh
  printf 'FROM scratch\nCOPY roots.pem /roots.pem\nRUN apk add ca-certificates\n' > scripts/certs/Dockerfile.certs
  printf 'root\n' > scripts/certs/roots.pem
  printf 'certs\tscripts/certs/Dockerfile.certs\tscripts/certs\n' > config/tool-images.local.txt
  printf '#!/usr/bin/env bash\nexec bash scripts/dev/update-dev-image-ref.sh\n' > .git-hooks/pre-commit
  chmod +x .git-hooks/pre-commit
  git config core.hooksPath .git-hooks
  git add -A
  # No registry: every curl call is recorded and fails.
  printf '#!/usr/bin/env bash\necho "curl $*" >> "%s/curl.calls"\nexit 22\n' "${WORK}" > "${WORK}/bin/curl"
  chmod +x "${WORK}/bin/curl"
  PATH="${WORK}/bin:${PATH}"
}

tool_images() {
  run --separate-stderr bash -c 'source scripts/lib/dev-image.sh; tool_images'
}

certs_ref() {
  git show HEAD:scripts/certs/Dockerfile.certs.image.ref
}

# fake_runtime: container and docker that record every call in WORK/calls; nothing is on this machine.
fake_runtime() {
  local tool
  for tool in container docker; do
    printf '#!/usr/bin/env bash\necho "$*" >> "%s/calls"\n[ "${2:-}" != inspect ]\n' "${WORK}" > "${WORK}/bin/${tool}"
    chmod +x "${WORK}/bin/${tool}"
  done
}

# --- the list -------------------------------------------------------------------------------------

@test "tool_images: containers/NAME images, then each listed image, its name beside its build file" {
  tool_images
  [ "${status}" -eq 0 ]
  [ "${#lines[@]}" -eq 2 ]
  [ "${lines[0]}" = "$(printf 'dev\tcontainers/dev/Containerfile\t.\tcontainers/dev/image.ref')" ]
  [ "${lines[1]}" = "$(printf 'certs\tscripts/certs/Dockerfile.certs\tscripts/certs\tscripts/certs/Dockerfile.certs.image.ref')" ]
}

@test "tool_images: a repository without the list has its containers/NAME images only" {
  rm config/tool-images.local.txt
  tool_images
  [ "${status}" -eq 0 ]
  [ "${output}" = "$(printf 'dev\tcontainers/dev/Containerfile\t.\tcontainers/dev/image.ref')" ]
}

@test "tool_images: comments and blank lines are skipped" {
  printf '# tool images\n\ncerts\tscripts/certs/Dockerfile.certs\tscripts/certs  # CA roots\n' > config/tool-images.local.txt
  tool_images
  [ "${status}" -eq 0 ]
  [ "${lines[1]}" = "$(printf 'certs\tscripts/certs/Dockerfile.certs\tscripts/certs\tscripts/certs/Dockerfile.certs.image.ref')" ]
}

@test "tool_images: a malformed line, a bad or repeated name, or a containers/NAME name fails, naming the line" {
  local line
  for line in 'certs\tscripts/certs/Dockerfile.certs' 'Bad_Name\tscripts/certs/Dockerfile.certs\tscripts/certs' \
    'dev\tscripts/certs/Dockerfile.certs\tscripts/certs'; do
    printf "${line}\n" > config/tool-images.local.txt
    tool_images
    [ "${status}" -ne 0 ]
    [[ "${stderr}" == *'config/tool-images.local.txt:1'* ]] || false
  done
  printf 'certs\tscripts/certs/Dockerfile.certs\tscripts/certs\ncerts\tscripts/certs/Dockerfile.x\tscripts/certs\n' \
    > config/tool-images.local.txt
  tool_images
  [ "${status}" -ne 0 ]
  [[ "${stderr}" == *'config/tool-images.local.txt:2'* ]] || false
}

# --- naming (the pre-commit hook) -----------------------------------------------------------------

@test "pre-commit: a commit names each listed image beside its build file, from the staged files, with no network" {
  git commit --quiet -m first
  [[ "$(certs_ref)" =~ ^ghcr\.io/keelcore/widget-certs:ctx-[0-9a-f]{16}$ ]] || false
  [[ "$(git show HEAD:containers/dev/image.ref)" =~ ^ghcr\.io/keelcore/widget-dev:ctx-[0-9a-f]{16}$ ]] || false
  [ ! -e "${WORK}/curl.calls" ]
}

@test "pre-commit: a listed image's name follows the staged files of its context dir, and only those" {
  git commit --quiet -m first
  local -r before="$(certs_ref)"
  printf 'root\n' > roots.pem
  git add roots.pem
  git commit --quiet -m 'same name, outside the context'
  [ "$(certs_ref)" = "${before}" ]
  printf 'unstaged\n' > scripts/certs/roots.pem
  git commit --quiet --allow-empty -m 'unstaged edit'
  [ "$(certs_ref)" = "${before}" ]
  git add scripts/certs/roots.pem
  git commit --quiet -m 'staged edit'
  [ "$(certs_ref)" != "${before}" ]
}

@test "pre-commit: build files sharing a folder each get their own name" {
  printf 'FROM scratch\nRUN apk add openssl\n' > scripts/certs/Dockerfile.tools
  printf 'tools\tscripts/certs/Dockerfile.tools\tscripts/certs\n' >> config/tool-images.local.txt
  git add -A
  git commit --quiet -m first
  [[ "$(git show HEAD:scripts/certs/Dockerfile.tools.image.ref)" =~ ^ghcr\.io/keelcore/widget-tools:ctx- ]] || false
  [ "$(git show HEAD:scripts/certs/Dockerfile.tools.image.ref | cut -d: -f2)" != "$(certs_ref | cut -d: -f2)" ]
}

@test "pre-commit: a listed build file not yet staged writes nothing" {
  printf 'later\tscripts/later/Dockerfile\tscripts/later\n' >> config/tool-images.local.txt
  git add config/tool-images.local.txt
  git commit --quiet -m first
  [ ! -e scripts/later/Dockerfile.image.ref ]
}

# --- use ------------------------------------------------------------------------------------------

@test "run.sh: an unpublished listed image is built from its build file, in its context dir" {
  fake_runtime
  run bash scripts/dev/run.sh --image certs --fetch-image
  [ "${status}" -eq 0 ]
  grep -E '^build -f \./scripts/certs/Dockerfile\.certs -t keelcore-certs-widget:ctx-[0-9a-f]{16} .*\./scripts/certs$' "${WORK}/calls"
}

@test "dev_tool_image: a script gets a listed image's reference, the image fetched first" {
  fake_runtime
  run --separate-stderr bash -c 'source scripts/lib/dev-image.sh; dev_tool_image certs'
  [ "${status}" -eq 0 ]
  [[ "${output}" =~ ^keelcore-certs-widget:ctx-[0-9a-f]{16}$ ]] || false
  grep -qE '^build -f \./scripts/certs/Dockerfile\.certs ' "${WORK}/calls"
}

# --- publish --------------------------------------------------------------------------------------

@test "publish.sh push: each image is built for the arch from its build file, in its context dir" {
  fake_runtime
  GITHUB_TOKEN=t GITHUB_ACTOR=a run bash scripts/dev/publish.sh push amd64
  [ "${status}" -eq 0 ]
  grep -E '^build --platform linux/amd64 -f containers/dev/Containerfile -t ghcr\.io/keelcore/widget-dev:ctx-[0-9a-f]{16}-amd64 \.$' "${WORK}/calls"
  grep -E '^build --platform linux/amd64 -f scripts/certs/Dockerfile\.certs -t ghcr\.io/keelcore/widget-certs:ctx-[0-9a-f]{16}-amd64 scripts/certs$' "${WORK}/calls"
  grep -E '^push ghcr\.io/keelcore/widget-certs:ctx-[0-9a-f]{16}-amd64$' "${WORK}/calls"
}

# merge_fakes: docker publishes every index at DIGEST, over an amd64 image (A), an arm64 image (B) and a
# build attestation manifest (platform unknown); run.sh records.
merge_fakes() {
  HEX="$(printf 'd%.0s' {1..64})"
  A="$(printf 'a%.0s' {1..64})"
  B="$(printf 'b%.0s' {1..64})"
  cat > "${WORK}/bin/docker" <<EOF2
#!/usr/bin/env bash
echo "\$*" >> "${WORK}/calls"
case "\$*" in
  'manifest inspect '*) exit 1 ;;
  'buildx imagetools inspect '*' --raw') printf '{"manifests":[{"platform":{"os":"linux"},"digest":"sha256:${A}"},{"platform":{"os":"linux"},"digest":"sha256:${B}"},{"platform":{"os":"unknown"},"digest":"sha256:${HEX}"}]}\n' ;;
  'buildx imagetools inspect '*) printf '{"digest":"sha256:${HEX}"}\n' ;;
esac
EOF2
  printf '#!/usr/bin/env bash\necho "run.sh $*" >> "%s/calls"\n' "${WORK}" > scripts/dev/run.sh
  chmod +x "${WORK}/bin/docker"
}

@test "publish.sh merge: every index gets the canonical signature, SBOM and provenance, in the dev image" {
  merge_fakes
  GITHUB_TOKEN=t GITHUB_ACTOR=a run bash scripts/dev/publish.sh merge
  [ "${status}" -eq 0 ]
  grep -qE "^run\.sh bash scripts/release/sign-image\.sh ghcr\.io/keelcore/widget-dev@sha256:${HEX} ctx-[0-9a-f]{16}$" "${WORK}/calls"
  grep -qE "^run\.sh bash scripts/release/sign-image\.sh ghcr\.io/keelcore/widget-certs@sha256:${HEX} ctx-[0-9a-f]{16}$" "${WORK}/calls"
}

@test "publish.sh merge: each arch image behind an index gets the canonical treatment too; the attestation manifest does not" {
  merge_fakes
  GITHUB_TOKEN=t GITHUB_ACTOR=a run bash scripts/dev/publish.sh merge
  [ "${status}" -eq 0 ]
  local image digest
  for image in widget-dev widget-certs; do
    for digest in "${A}" "${B}"; do
      grep -qE "^run\\.sh bash scripts/release/sign-image\\.sh ghcr\\.io/keelcore/${image}@sha256:${digest} ctx-[0-9a-f]{16}$" "${WORK}/calls"
    done
  done
  [ "$(grep -cE "^run\\.sh bash scripts/release/sign-image\\.sh " "${WORK}/calls")" -eq 6 ]
}

# job_block FILE JOB: the lines of one job in a workflow.
job_block() {
  awk -v job="  ${2}:" '$0 == job { on = 1; next } on && /^  [a-z][a-z0-9_-]*:$/ { exit } on' "${1}"
}

@test "dev-image workflow: the merge job may sign and attest (OIDC, GitHub's store); the script does it, not an action" {
  local -r wf="${STANDARDS}/.github/workflows/dev-image.yml"
  local merge
  merge="$(job_block "${wf}" merge)"
  grep -q 'attestations: write' <<< "${merge}"
  grep -q 'id-token: write' <<< "${merge}"
  [[ "${merge}" != *attest-build-provenance* ]] || false
  job_block "${STANDARDS}/.github/workflows/ci.yml" dev-image | grep -q 'attestations: write'
}

@test "publish.sh merge: a dev-image run that reads stdin (docker run -i) does not end the list of images" {
  merge_fakes
  printf '#!/usr/bin/env bash\nwhile IFS= read -r -t 1 _; do :; done || true\necho "run.sh $*" >> "%s/calls"\n' "${WORK}" > scripts/dev/run.sh
  GITHUB_TOKEN=t GITHUB_ACTOR=a run bash scripts/dev/publish.sh merge
  [ "${status}" -eq 0 ]
  grep -qE "^run\.sh bash scripts/release/sign-image\.sh ghcr\.io/keelcore/widget-certs@sha256:${HEX} ctx-[0-9a-f]{16}$" "${WORK}/calls"
}
