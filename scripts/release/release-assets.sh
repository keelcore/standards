#!/usr/bin/env bash
# scripts/release/release-assets.sh
# Assemble every asset of the GitHub Release for TAG in DIR, from what the
# registries serve for that version (so the SBOMs, checksums and signatures cover
# exactly what was published, and the step reruns for any tag):
#   - the npm tarball (package.json), checked against the registry's integrity hash
#   - the wheel and sdist (pyproject.toml), each checked against PyPI's sha256
#   - the Go module zip (go.mod), checked against the Go checksum database (go mod download)
#   - one SBOM per published artifact (scripts/release/sbom.sh): name, version, contents
#   - one build-environment SBOM per tool image the release was built in (TAG's
#     containers/*/image.ref, by digest)
#   - current_pins.md: every pinned input of TAG (its docs/current_pins.md)
#   - SHA256SUMS over all of the above, and a keyless cosign bundle per file
#     (scripts/release/sign.sh)
#
# Usage: release-assets.sh TAG DIR   (in the dev image: make release-assets TAG=vX.Y.Z)
# Env: ACTIONS_ID_TOKEN_REQUEST_URL / _TOKEN (keyless signing in GitHub Actions).

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

# A newly published version can take minutes to appear in a registry.
readonly FETCH_TRIES=30
readonly FETCH_DELAY=30

function main() {
  validate_args "${@:-}"
  local -r tag="${1}" dir="${2}" root="${PWD}"
  local -r version="${tag#v}"
  local name license
  name="$(project_name "${tag}")"
  license="$(project_license "${tag}")"
  mkdir -p "${dir}"
  local -a artifacts=()
  local f
  while IFS= read -r f; do
    [ -n "${f}" ] && artifacts+=("${f}")
  done < <(fetch_npm "${tag}" "${dir}"; fetch_pypi "${tag}" "${dir}"; fetch_go_module "${tag}" "${dir}")
  [ "${#artifacts[@]}" -gt 0 ] || { log "❌ no published artifacts found for ${tag}"; exit 1; }
  bash scripts/release/sbom.sh --out-dir "${dir}" --name "${name}" --version "${version}" \
    --license "${license}" "${artifacts[@]}"
  local -a images=()
  while IFS= read -r f; do
    [ -n "${f}" ] && images+=("$(git show "${tag}:${f}")")
  done < <(git ls-tree -r --name-only "${tag}" -- containers | grep -E '/image\.ref$' || true)
  if [ "${#images[@]}" -gt 0 ]; then
    bash scripts/release/sbom.sh --out-dir "${dir}" --name "${name}-build-environment" --version "${version}" \
      "${images[@]}"
  fi
  if git cat-file -e "${tag}:docs/current_pins.md" 2> /dev/null; then
    git show "${tag}:docs/current_pins.md" > "${dir}/current_pins.md"
  fi
  local -a files=()
  for f in "${dir}"/*; do
    [ -f "${f}" ] || continue
    case "$(basename "${f}")" in
      *.bundle | SHA256SUMS*) continue ;;
    esac
    files+=("$(basename "${f}")")
  done
  (cd "${dir}" && bash "${root}/scripts/release/sign.sh" --sums-dir . "${files[@]}")
  log "✅ release assets for ${tag}: $(find "${dir}" -maxdepth 1 -type f | wc -l | tr -d ' ') files in ${dir}"
}

# log MSG: to stderr (stdout carries the fetched artifact paths).
function log() {
  local -r msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a '/tmp/release_assets.log' >&2
}

function validate_args() {
  if [ "${#}" -ne 2 ] || [[ ! "${1:-}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    log '❌ Usage: release-assets.sh vX.Y.Z DIR'
    exit 1
  fi
  git rev-parse --verify --quiet "refs/tags/${1}" > /dev/null || { log "❌ tag ${1} not found"; exit 1; }
}

# tag_file TAG PATH: PATH's content at TAG (empty when it does not exist there).
function tag_file() {
  git show "${1}:${2}" 2> /dev/null || true
}

# project_name TAG: the published package name (package.json, else pyproject.toml, else the repo).
function project_name() {
  local -r tag="${1}"
  local pkg
  pkg="$(tag_file "${tag}" package.json)"
  if [ -n "${pkg}" ]; then
    jq -r '.name | sub("^@"; "") | gsub("/"; "-")' <<< "${pkg}"
  elif [ -n "$(tag_file "${tag}" pyproject.toml)" ]; then
    tag_file "${tag}" pyproject.toml | sed -nE 's/^name = "([^"]+)"$/\1/p' | head -1
  else
    basename "$(git rev-parse --show-toplevel)"
  fi
}

# project_license TAG: the SPDX license the project declares (package.json, else pyproject.toml).
function project_license() {
  local -r tag="${1}"
  local pkg
  pkg="$(tag_file "${tag}" package.json)"
  if [ -n "${pkg}" ]; then
    jq -r '.license // empty' <<< "${pkg}"
  else
    tag_file "${tag}" pyproject.toml | sed -nE 's/^license = \{ text = "([^"]+)" \}$/\1/p' | head -1
  fi
}

# retry_fetch URL: the response body, retried while the registry does not have it yet.
function retry_fetch() {
  local -r url="${1}"
  local i
  for (( i = 1; i <= FETCH_TRIES; i++ )); do
    curl -fsSL "${url}" && return 0
    log "⏳ ${url} not available yet (${i}/${FETCH_TRIES})"
    sleep "${FETCH_DELAY}"
  done
  return 1
}

# fetch_npm TAG DIR: the npm tarball for TAG's version, checked against the registry's
# integrity hash; prints its path.
function fetch_npm() {
  local -r tag="${1}" dir="${2}"
  local pkg name meta url integrity file
  pkg="$(tag_file "${tag}" package.json)"
  [ -n "${pkg}" ] || return 0
  name="$(jq -r '.name' <<< "${pkg}")"
  meta="$(retry_fetch "https://registry.npmjs.org/${name/\//%2f}/${tag#v}")" \
    || { log "❌ npm ${name}@${tag#v} not found"; exit 1; }
  url="$(jq -r '.dist.tarball' <<< "${meta}")"
  integrity="$(jq -r '.dist.integrity' <<< "${meta}")"
  file="${dir}/$(basename "${url}")"
  curl -fsSL "${url}" -o "${file}"
  [ "sha512-$(openssl dgst -sha512 -binary "${file}" | base64 | tr -d '\n')" = "${integrity}" ] \
    || { log "❌ ${file}: integrity mismatch with the npm registry"; exit 1; }
  log "✅ npm ${name}@${tag#v}"
  printf '%s\n' "${file}"
}

# fetch_pypi TAG DIR: every file PyPI serves for TAG's version, each checked against its
# published sha256; prints their paths.
function fetch_pypi() {
  local -r tag="${1}" dir="${2}"
  local name meta fn url sha
  [ -n "$(tag_file "${tag}" pyproject.toml)" ] || return 0
  name="$(tag_file "${tag}" pyproject.toml | sed -nE 's/^name = "([^"]+)"$/\1/p' | head -1)"
  meta="$(retry_fetch "https://pypi.org/pypi/${name}/${tag#v}/json")" \
    || { log "❌ PyPI ${name} ${tag#v} not found"; exit 1; }
  while IFS=$'\t' read -r fn url sha; do
    [ -n "${fn}" ] || continue
    curl -fsSL "${url}" -o "${dir}/${fn}"
    printf '%s  %s\n' "${sha}" "${dir}/${fn}" | sha256sum --check --quiet \
      || { log "❌ ${fn}: sha256 mismatch with PyPI"; exit 1; }
    log "✅ PyPI ${fn}"
    printf '%s\n' "${dir}/${fn}"
  done < <(jq -r '.urls[] | [.filename, .url, .digests.sha256] | @tsv' <<< "${meta}")
}

# fetch_go_module TAG DIR: the module zip for TAG, as `go get` downloads and verifies it (the Go
# proxy, checked against the checksum database); prints its path.
function fetch_go_module() {
  local -r tag="${1}" dir="${2}"
  local gomod module tmp zip i
  gomod="$(tag_file "${tag}" go.mod)"
  [ -n "${gomod}" ] || return 0
  module="$(awk '$1 == "module" { print $2; exit }' <<< "${gomod}")"
  tmp="$(mktemp -d)"
  for (( i = 1; i <= FETCH_TRIES; i++ )); do
    zip="$(cd "${tmp}" && GOMODCACHE="${tmp}/mod" GOFLAGS=-modcacherw go mod download -json "${module}@${tag}" \
      2> /dev/null | jq -r '.Zip // empty')" && [ -n "${zip}" ] && break
    log "⏳ Go proxy ${module}@${tag} not available yet (${i}/${FETCH_TRIES})"
    sleep "${FETCH_DELAY}"
  done
  [ -n "${zip:-}" ] || { log "❌ Go proxy ${module}@${tag} not found"; exit 1; }
  cp "${zip}" "${dir}/$(basename "${module}")-${tag}.zip"
  rm -rf "${tmp}"
  log "✅ Go module ${module}@${tag} (checksum database verified)"
  printf '%s\n' "${dir}/$(basename "${module}")-${tag}.zip"
}

main "${@:-}"
