#!/usr/bin/env bash
# scripts/dev/publish.sh
# Publish the repository's tool images (containers/*/Containerfile) to the
# registry, tagged by build context, and pin them by digest.
#
# Usage:
#   publish.sh push ARCH   (CI, docker) build each image natively for ARCH (amd64 | arm64)
#                          and push <repository>:ctx-<hash>-ARCH; skipped when the
#                          multi-arch ctx-<hash> tag already exists
#   publish.sh merge       (CI, docker) join the per-arch images into the multi-arch
#                          <repository>:ctx-<hash> index and sign it keyless (cosign, in
#                          the dev image)
#   publish.sh ref         write containers/NAME/image.ref: the published
#                          ctx-<hash> index of the current build context, by digest
#
# Env: GITHUB_TOKEN and GITHUB_ACTOR (registry login for push and merge; GitHub Actions sets
# GITHUB_ACTOR).

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

# shellcheck source=../lib/dev-image.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/dev-image.sh"

function main() {
  exec 5>&1
  validate_args "${@:-}"
  case "${1}" in
    push) registry_login; for_each_image push_image "${2}" ;;
    merge) registry_login; for_each_image merge_image ;;
    ref) for_each_image write_ref ;;
  esac
}

function log() {
  local -r msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a '/tmp/keelcore_dev_publish.log' >&5
}

function validate_args() {
  case "${1:-}:${2:-}" in
    push:amd64 | push:arm64 | merge: | ref:) ;;
    *)
      log '❌ Usage: publish.sh push amd64|arm64 | merge | ref'
      exit 1
      ;;
  esac
}

function registry_login() {
  printf '%s' "${GITHUB_TOKEN:?GITHUB_TOKEN is required}" \
    | docker login "$(dev_registry | cut -d/ -f1)" -u "${GITHUB_ACTOR:?GITHUB_ACTOR is required}" --password-stdin
}

# for_each_image FN [ARG...]: FN NAME HASH ARG... for every image; images that build on the
# .standards dev image come after the others.
function for_each_image() {
  local -r fn="${1}"
  shift
  local cf name base hash
  for cf in containers/*/Containerfile; do
    name="$(basename "$(dirname "${cf}")")"
    dev_has_base . "${name}" && continue
    hash="$(dev_context_hash . "${name}")"
    "${fn}" "${name}" "${hash}" '' "$@"
  done
  for cf in containers/*/Containerfile; do
    name="$(basename "$(dirname "${cf}")")"
    dev_has_base . "${name}" || continue
    base="$(standards_ref)"
    hash="$(dev_context_hash . "${name}" "${base}")"
    "${fn}" "${name}" "${hash}" "${base}" "$@"
  done
}

# standards_ref: the pinned .standards dev image an image builds on.
function standards_ref() {
  local hash
  hash="$(dev_context_hash .standards dev)"
  dev_pinned_ref .standards dev "${hash}" \
    || { log "❌ .standards/$(dev_ref_file dev) does not pin its current build context (ctx-${hash})"; exit 1; }
}

function published() {
  docker manifest inspect "${1}" > /dev/null 2>&1
}

function push_image() {
  local -r name="${1}" hash="${2}" base="${3}" arch="${4}"
  local -r tag="$(dev_repository . "${name}"):ctx-${hash}"
  if published "${tag}"; then
    log "✅ ${tag} already published"
    return 0
  fi
  local -a args=(build --platform "linux/${arch}" -f "$(dev_containerfile "${name}")" -t "${tag}-${arch}")
  [ -z "${base}" ] || args+=(--build-arg "BASE_DEV_IMAGE=${base}")
  log "🔨 ${tag}-${arch}"
  docker "${args[@]}" .
  docker push "${tag}-${arch}"
}

function merge_image() {
  local -r name="${1}" hash="${2}"
  local -r tag="$(dev_repository . "${name}"):ctx-${hash}"
  if published "${tag}"; then
    log "✅ ${tag} already published"
    return 0
  fi
  docker buildx imagetools create -t "${tag}" "${tag}-amd64" "${tag}-arm64"
  local digest
  digest="$(docker buildx imagetools inspect "${tag}" --format '{{json .Manifest}}' | jq -r '.digest')"
  [[ "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]] || { log "❌ no digest for ${tag}"; exit 1; }
  KEELCORE_DEV_ENV='GITHUB_ACTOR' bash scripts/dev/run.sh bash scripts/dev/sign-image.sh "${tag%:*}@${digest}"
  log "✅ ${tag}@${digest}"
  [ -z "${GITHUB_STEP_SUMMARY:-}" ] || printf '`%s`: `%s@%s`\n' "$(dev_ref_file "${name}")" "${tag}" "${digest}" \
    >> "${GITHUB_STEP_SUMMARY}"
}

# write_ref NAME HASH: pin the published ctx-HASH index by digest (registry metadata only).
function write_ref() {
  local -r name="${1}" hash="${2}"
  local -r repository="$(dev_repository . "${name}")"
  local -r host="${repository%%/*}" path="${repository#*/}"
  local token digest
  token="$(curl -fsSL "https://${host}/token?scope=repository:${path}:pull" | jq -r '.token')"
  digest="$(curl -fsSI -H "Authorization: Bearer ${token}" \
    -H 'Accept: application/vnd.oci.image.index.v1+json' \
    -H 'Accept: application/vnd.docker.distribution.manifest.list.v2+json' \
    "https://${host}/v2/${path}/manifests/ctx-${hash}" \
    | tr -d '\r' | awk -F': ' 'tolower($1) == "docker-content-digest" { print $2 }')" \
    || { log "❌ ${repository}:ctx-${hash} is not published yet (run the dev-image workflow)"; exit 1; }
  [[ "${digest}" =~ ^sha256:[0-9a-f]{64}$ ]] || { log "❌ no digest for ${repository}:ctx-${hash}"; exit 1; }
  printf '%s:ctx-%s@%s\n' "${repository}" "${hash}" "${digest}" > "$(dev_ref_file "${name}")"
  log "✅ $(dev_ref_file "${name}"): ${repository}:ctx-${hash}@${digest}"
}

main "${@:-}"
