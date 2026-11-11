#!/usr/bin/env bats
# tests/release-dev-image.bats
# Release bundles name the dev image that built them: the Helm chart, the npm and PyPI packages, and
# the release assets.

setup() {
  STANDARDS="$(cd "${BATS_TEST_DIRNAME}/.." && pwd -P)"
  WORK="${BATS_TEST_TMPDIR}/work"
  mkdir -p "${WORK}/bin" "${WORK}/containers/dev" "${WORK}/charts/widget" "${WORK}/scripts/release" "${WORK}/scripts/lib" "${WORK}/config"
  export WORK
  cp "${STANDARDS}/scripts/release/push-helm-chart.sh" "${WORK}/scripts/release/"
  cp "${STANDARDS}/scripts/lib/"*.sh "${WORK}/scripts/lib/"
  cd "${WORK}"
  git init --quiet
  printf 'ghcr.io/acme/widget-dev:ctx-abc\n' > containers/dev/image.ref
  printf 'acme/widget\n' > config/release-repo.local.txt
  printf 'apiVersion: v2\nname: widget\nversion: 0.0.0\n' > charts/widget/Chart.yaml
  # helm records the Chart.yaml it packages; cosign and the registry do nothing.
  cat > bin/helm <<'HELM'
#!/usr/bin/env bash
case "${1}" in
  package) cat "${2}/Chart.yaml" > "${WORK}/packaged.yaml"; touch "dist/widget-${4}.tgz" ;;
esac
HELM
  printf '#!/usr/bin/env bash\nexit 0\n' > bin/cosign
  printf '#!/usr/bin/env bash\nexit 0\n' > scripts/release/run-cosign.sh
  chmod +x bin/helm bin/cosign
  export PATH="${WORK}/bin:${PATH}" GITHUB_TOKEN=token GITHUB_ACTOR=actor
}

push() {
  printf 'x' > tagged && git add -A && git -c user.name=t -c user.email=t@example.invalid commit --quiet -m x \
    && git -c user.name=t -c user.email=t@example.invalid tag -a v1.2.3 -m v
  run bash scripts/release/push-helm-chart.sh
}

@test "push-helm-chart.sh: the chart carries the dev image name; the tree's Chart.yaml is unchanged" {
  push
  [ "${status}" -eq 0 ]
  grep -qF 'io.keelcore.dev-image: ghcr.io/acme/widget-dev:ctx-abc' packaged.yaml
  [ -z "$(git status --short charts)" ]
}

@test "push-helm-chart.sh: an existing annotations block is kept and added to" {
  printf 'annotations:\n  other: value\n' >> charts/widget/Chart.yaml
  push
  [ "${status}" -eq 0 ]
  grep -qF 'other: value' packaged.yaml
  grep -qF 'io.keelcore.dev-image: ghcr.io/acme/widget-dev:ctx-abc' packaged.yaml
  [ "$(grep -c '^annotations:' packaged.yaml)" -eq 1 ]
}

@test "packages: npm and PyPI ship the dev image name" {
  jq -e '.files | index("containers/dev/image.ref")' "${STANDARDS}/package.json" > /dev/null
  [ "$(grep -c 'containers/dev/image.ref' "${STANDARDS}/pyproject.toml")" -ge 2 ]
}

@test "generate-release-checksums.sh: the dev image name ships in dist, covered by the checksums" {
  cp "${STANDARDS}/scripts/release/generate-release-checksums.sh" scripts/release/
  cp "${STANDARDS}/config/release-binaries.txt" config/ 2> /dev/null || true
  mkdir -p dist
  printf 'bin\n' > dist/widget-linux-amd64
  run bash scripts/release/generate-release-checksums.sh
  [ "${status}" -eq 0 ]
  [ "$(cat dist/dev-image.txt)" = 'ghcr.io/acme/widget-dev:ctx-abc' ]
  grep -q 'dist/dev-image.txt' dist/SHA256SUMS
}

@test "build-release-assets.sh: the dev image name at the tag is a release asset" {
  sed -n '/^function copy_dev_image()/,/^}/p' "${STANDARDS}/scripts/release/build-release-assets.sh" > copy.sh
  printf 'x' > tagged && git add -A && git -c user.name=t -c user.email=t@example.invalid commit --quiet -m x
  git -c user.name=t -c user.email=t@example.invalid tag -a v1.2.3 -m v
  printf 'ghcr.io/acme/widget-dev:ctx-later\n' > containers/dev/image.ref
  mkdir -p out
  run bash -c "source ./copy.sh; copy_dev_image v1.2.3 out"
  [ "${status}" -eq 0 ]
  [ "$(cat out/dev-image.txt)" = 'ghcr.io/acme/widget-dev:ctx-abc' ]
}

# list_tool_images: a listed certs image and a containers/pypi image beside the dev image.
list_tool_images() {
  mkdir -p scripts/certs containers/pypi
  printf 'certs\tscripts/certs/Dockerfile.certs\tscripts/certs\n' > config/tool-images.local.txt
  printf 'FROM scratch\n' > scripts/certs/Dockerfile.certs
  printf 'ghcr.io/acme/widget-certs:ctx-def\n' > scripts/certs/Dockerfile.certs.image.ref
  printf 'ghcr.io/acme/widget-pypi:ctx-123\n' > containers/pypi/image.ref
}

@test "generate-release-checksums.sh: dev-image.txt names every tool image, the dev image first" {
  list_tool_images
  cp "${STANDARDS}/scripts/release/generate-release-checksums.sh" scripts/release/
  cp "${STANDARDS}/config/release-binaries.txt" config/ 2> /dev/null || true
  mkdir -p dist
  printf 'bin\n' > dist/widget-linux-amd64
  run bash scripts/release/generate-release-checksums.sh
  [ "${status}" -eq 0 ]
  [ "$(cat dist/dev-image.txt)" = "$(printf 'ghcr.io/acme/widget-dev:ctx-abc\nghcr.io/acme/widget-pypi:ctx-123\nghcr.io/acme/widget-certs:ctx-def')" ]
  grep -q 'dist/dev-image.txt' dist/SHA256SUMS
}

@test "build-release-assets.sh: dev-image.txt names every tool image at the tag; each name's file is listed" {
  list_tool_images
  sed -n '/^function copy_dev_image()/,/^}/p' "${STANDARDS}/scripts/release/build-release-assets.sh" > copy.sh
  git add -A && git -c user.name=t -c user.email=t@example.invalid commit --quiet -m x
  git -c user.name=t -c user.email=t@example.invalid tag -a v1.2.3 -m v
  printf 'ghcr.io/acme/widget-certs:ctx-later\n' > scripts/certs/Dockerfile.certs.image.ref
  mkdir -p out
  run bash -c "source ./copy.sh; copy_dev_image v1.2.3 out"
  [ "${status}" -eq 0 ]
  [ "${output}" = "$(printf 'containers/dev/image.ref\ncontainers/pypi/image.ref\nscripts/certs/Dockerfile.certs.image.ref')" ]
  [ "$(cat out/dev-image.txt)" = "$(printf 'ghcr.io/acme/widget-dev:ctx-abc\nghcr.io/acme/widget-pypi:ctx-123\nghcr.io/acme/widget-certs:ctx-def')" ]
}

@test "build-release-assets.sh: a listed image's build-environment tools come from its own build file" {
  sed -n '/^function image_tools()/,/^}/p; /^function tag_file()/,/^}/p' \
    "${STANDARDS}/scripts/release/build-release-assets.sh" > tools.sh
  mkdir -p scripts/certs scripts/ci
  printf 'FROM scratch\nCOPY scripts/ci/setup-foo.sh /s\n' > scripts/certs/Dockerfile.certs
  printf "readonly FOO_VERSION='1.2.0'\nurl=https://github.com/acme/foo/releases/download/v\${FOO_VERSION}/foo\n" \
    > scripts/ci/setup-foo.sh
  git add -A && git -c user.name=t -c user.email=t@example.invalid commit --quiet -m x
  git -c user.name=t -c user.email=t@example.invalid tag -a v1.2.3 -m v
  run bash -c "source ./tools.sh; image_tools v1.2.3 scripts/certs/Dockerfile.certs"
  [ "${status}" -eq 0 ]
  [[ "${output}" == "foo"$'\t'"1.2.0"$'\t'"pkg:github/acme/foo@v1.2.0"* ]] || false
}
