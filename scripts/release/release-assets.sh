#!/usr/bin/env bash
# scripts/release/release-assets.sh
# Assemble every asset of the GitHub Release for TAG in DIR, which already holds
# the published package files (the npm tarball, the wheel and sdist):
#   - the Go module zip, as the Go proxy serves it (when the repository is a Go module)
#   - one SBOM per published artifact (scripts/release/sbom.sh): name, version, contents
#   - one build-environment SBOM per tool image the release was built and tested in
#     (containers/*/image.ref, by digest)
#   - current_pins.md: every pinned input of this release (make pins-doc)
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

function main() {
  exec 5>&1
  validate_args "${@:-}"
  local -r tag="${1}" dir="${2}" root="${PWD}"
  local -r version="${tag#v}" name="$(project_name)"
  mkdir -p "${dir}"
  fetch_go_module "${tag}" "${dir}"
  local -a artifacts=()
  local f
  for f in "${dir}"/*; do
    [ -f "${f}" ] || continue
    case "$(basename "${f}")" in
      *.spdx.json | *.bundle | SHA256SUMS* | current_pins.md) continue ;;
    esac
    artifacts+=("${f}")
  done
  [ "${#artifacts[@]}" -gt 0 ] || { log "❌ no published artifacts in ${dir}"; exit 1; }
  bash scripts/release/sbom.sh --out-dir "${dir}" --name "${name}" --version "${version}" \
    --license "$(project_license)" "${artifacts[@]}"
  local -a images=()
  for f in containers/*/image.ref; do
    [ -f "${f}" ] && images+=("$(cat "${f}")")
  done
  if [ "${#images[@]}" -gt 0 ]; then
    bash scripts/release/sbom.sh --out-dir "${dir}" --name "${name}-build-environment" --version "${version}" \
      "${images[@]}"
  fi
  [ ! -f docs/current_pins.md ] || cp docs/current_pins.md "${dir}/current_pins.md"
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

function log() {
  local -r msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a '/tmp/release_assets.log' >&5
}

function validate_args() {
  if [ "${#}" -ne 2 ] || [[ ! "${1:-}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    log '❌ Usage: release-assets.sh vX.Y.Z DIR'
    exit 1
  fi
}

# project_name: the published package name (package.json, else pyproject.toml, else the repo).
function project_name() {
  if [ -f package.json ]; then
    jq -r '.name | sub("^@"; "") | gsub("/"; "-")' package.json
  elif [ -f pyproject.toml ]; then
    sed -nE 's/^name = "([^"]+)"$/\1/p' pyproject.toml | head -1
  else
    basename "$(git rev-parse --show-toplevel)"
  fi
}

# project_license: the SPDX license the project declares (package.json, else pyproject.toml).
function project_license() {
  if [ -f package.json ]; then
    jq -r '.license // empty' package.json
  elif [ -f pyproject.toml ]; then
    sed -nE 's/^license = \{ text = "([^"]+)" \}$/\1/p' pyproject.toml | head -1
  fi
}

# fetch_go_module TAG DIR: the module zip the Go proxy serves for TAG (what `go get` downloads).
function fetch_go_module() {
  local -r tag="${1}" dir="${2}"
  [ -f go.mod ] || return 0
  local module
  module="$(awk '$1 == "module" { print $2; exit }' go.mod)"
  curl -fsSL --retry 5 --retry-all-errors --retry-delay 5 \
    "https://proxy.golang.org/${module}/@v/${tag}.zip" -o "${dir}/$(basename "${module}")-${tag}.zip"
}

main "${@:-}"
