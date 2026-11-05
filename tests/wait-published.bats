#!/usr/bin/env bats
# tests/wait-published.bats
# wait-published.sh returns only once the registry serves everything of the version the job just
# published; the release job, which needs the publish jobs, reads metadata after that.

setup() {
  STANDARDS="$(cd "${BATS_TEST_DIRNAME}/.." && pwd -P)"
  WORK="${BATS_TEST_TMPDIR}/work"
  STATE="${BATS_TEST_TMPDIR}/state"
  export WORK STATE
  mkdir -p "${WORK}/scripts/release" "${WORK}/bin" "${WORK}/target/dist" "${STATE}"
  cp "${STANDARDS}/scripts/release/wait-published.sh" "${WORK}/scripts/release/"
  cat > "${WORK}/bin/curl" <<'STUB'
#!/usr/bin/env bash
url="${*: -1}"
printf '%s\n' "${url}" >> "${STATE}/calls"
key="$(printf '%s' "${url}" | tr -c 'A-Za-z0-9' '_')"
n="$(cat "${STATE}/${key}" 2> /dev/null || printf 0)"
printf '%s' "$(( n + 1 ))" > "${STATE}/${key}"
missing="${MISSING_UNTIL:-}"
if [ -n "${missing}" ] && [[ "${url}" == *"${missing%%=*}"* ]] && [ "${n}" -lt "${missing##*=}" ]; then
  exit 22
fi
case "${url}" in
  https://registry.npmjs.org/*/1.2.3)
    printf '{"dist":{"tarball":"https://r/p-1.2.3.tgz","attestations":{"url":"https://r/attest/p"}}}' ;;
  https://pypi.org/pypi/*/json)
    if [ "${PYPI_ONE_FILE_UNTIL:-0}" -gt "${n}" ]; then
      printf '{"urls":[{"filename":"p-1.2.3.tar.gz","url":"https://f/p-1.2.3.tar.gz"}]}'
    else
      printf '{"urls":[{"filename":"p-1.2.3.tar.gz","url":"https://f/p-1.2.3.tar.gz"},{"filename":"p-1.2.3-py3-none-any.whl","url":"https://f/p.whl"}]}'
    fi ;;
esac
STUB
  chmod +x "${WORK}/bin/curl"
  export PATH="${WORK}/bin:${PATH}"
  export WAIT_INTERVAL=0 GITHUB_REF_NAME=v1.2.3
  cd "${WORK}"
  printf '{"name":"@acme/p"}\n' > package.json
  printf '[project]\nname = "acme-p"\n' > pyproject.toml
  printf 'module example.com/p\n\ngo 1.22\n' > go.mod
  : > target/dist/p-1.2.3.tar.gz
  : > target/dist/p-1.2.3-py3-none-any.whl
}

calls_to() { grep -c -F "${1}" "${STATE}/calls"; }

@test "npm: returns once the version, tarball and attestations are all served" {
  run bash scripts/release/wait-published.sh npm
  [ "${status}" -eq 0 ]
  [ "$(calls_to 'registry.npmjs.org/@acme%2fp/1.2.3')" -ge 1 ]
  [ "$(calls_to 'https://r/p-1.2.3.tgz')" -eq 1 ]
  [ "$(calls_to 'https://r/attest/p')" -eq 1 ]
}

@test "npm: keeps waiting, with no attempt limit, for the version" {
  export MISSING_UNTIL='registry.npmjs.org=200'
  run bash scripts/release/wait-published.sh npm
  [ "${status}" -eq 0 ]
  [ "$(calls_to 'registry.npmjs.org')" -gt 200 ]
}

@test "npm: keeps waiting for the tarball after the version appears" {
  export MISSING_UNTIL='p-1.2.3.tgz=5'
  run bash scripts/release/wait-published.sh npm
  [ "${status}" -eq 0 ]
  [ "$(calls_to 'https://r/p-1.2.3.tgz')" -eq 6 ]
}

@test "npm: keeps waiting for the attestations after the tarball appears" {
  export MISSING_UNTIL='attest/p=5'
  run bash scripts/release/wait-published.sh npm
  [ "${status}" -eq 0 ]
  [ "$(calls_to 'https://r/attest/p')" -eq 6 ]
}

@test "pypi: waits until every file this job built is listed, then for each file and its provenance" {
  export PYPI_ONE_FILE_UNTIL=4
  run bash scripts/release/wait-published.sh pypi
  [ "${status}" -eq 0 ]
  [ "$(calls_to 'https://pypi.org/pypi/acme-p/1.2.3/json')" -ge 5 ]
  [ "$(calls_to 'https://f/p.whl')" -eq 1 ]
  [ "$(calls_to 'https://f/p-1.2.3.tar.gz')" -eq 1 ]
  [ "$(calls_to 'integrity/acme-p/1.2.3/p-1.2.3.tar.gz/provenance')" -eq 1 ]
  [ "$(calls_to 'integrity/acme-p/1.2.3/p-1.2.3-py3-none-any.whl/provenance')" -eq 1 ]
}

@test "go: waits for the module zip and the checksum database record" {
  export MISSING_UNTIL='sum.golang.org=5'
  run bash scripts/release/wait-published.sh go
  [ "${status}" -eq 0 ]
  [ "$(calls_to 'https://proxy.golang.org/example.com/p/@v/v1.2.3.zip')" -eq 1 ]
  [ "$(calls_to 'https://sum.golang.org/lookup/example.com/p@v1.2.3')" -eq 6 ]
}

@test "an unknown registry fails at once" {
  run bash scripts/release/wait-published.sh nope
  [ "${status}" -ne 0 ]
}

@test "publish.yml: every publish job waits for its registry, and the release job needs them all" {
  local -r wf="${STANDARDS}/.github/workflows/publish.yml"
  local registry
  for registry in npm pypi go; do
    grep -qE "run: make release-wait-published ARGS=\"?${registry}\"?$" "${wf}"
  done
  grep -q 'needs: \[publish-npm, publish-pypi, publish-go\]' "${wf}"
}

@test "publish.yml: the PyPI wait comes after the upload" {
  local -r wf="${STANDARDS}/.github/workflows/publish.yml"
  local upload wait
  upload="$(grep -n 'gh-action-pypi-publish' "${wf}" | cut -d: -f1)"
  wait="$(grep -n 'release-wait-published ARGS="\?pypi' "${wf}" | cut -d: -f1)"
  [ "${upload}" -lt "${wait}" ]
}
