#!/usr/bin/env bash
# scripts/dev/run.sh
# Run a command in one of the repository's tool images with the repository
# mounted read-only. Every make target that runs a tool goes through here, locally and in
# CI, so the tool versions are the ones baked into the image.
#
# Usage: run.sh [--image NAME] [--writable] COMMAND [ARG...]   (from the repository root)
#
# Images: containers/NAME/Containerfile (default NAME: dev).
#
# Mounts: the repository read-only, except target/ (outputs: builds, coverage,
# reports), which is writable. --writable mounts the whole repository writable,
# for the targets whose job is editing tracked files (format, coverage baseline).
#
# Image: the digest-pinned reference in containers/NAME/image.ref when it was
# built from the current build context (the files the Containerfile COPYs);
# otherwise keelcore-NAME-<repo>:ctx-<context hash>, built locally from
# containers/NAME/Containerfile on first use. A Containerfile with
# `ARG BASE_DEV_IMAGE` gets the .standards dev image as that argument.
# Runtime: Apple `container` on macOS, docker on Linux.
# Inside the image (KEELCORE_DEV_IMAGE set) the command runs directly.

# bash configuration:
# 1) Exit script if you try to use an uninitialized variable.
set -o nounset

# 2) Exit script if a statement returns a non-true return value.
set -o errexit

# 3) Use the error status of the first failure, rather than that of the last item in a pipeline.
set -o pipefail

# shellcheck source=../lib/dev-image.sh
source "$(dirname "${BASH_SOURCE[0]}")/../lib/dev-image.sh"

# Environment passed into the container: CI context, PR metadata, coverage settings, the
# GitHub OIDC token request (keyless signing, trusted publishing), plus any names a project
# lists in KEELCORE_DEV_ENV.
readonly PASS_ENV="TZ CI GITHUB_ACTIONS GITHUB_TOKEN GITHUB_REPOSITORY GITHUB_EVENT_NAME GITHUB_EVENT_PATH
  GITHUB_REF GITHUB_REF_NAME GITHUB_SHA GITHUB_BASE_REF GITHUB_HEAD_REF GITHUB_OUTPUT GITHUB_STEP_SUMMARY
  PR_TITLE PR_BODY PR_AUTHOR BASE_SHA HEAD_SHA COVERAGE_DIR COVERAGE_THRESHOLD COVERAGE_BASE_FILE COVERAGE_PR_FILE
  GO_COVERAGE_IGNORE_REGEX CARGO_COVERAGE_FEATURES CARGO_COVERAGE_IGNORE_REGEX
  ACTIONS_ID_TOKEN_REQUEST_URL ACTIONS_ID_TOKEN_REQUEST_TOKEN ${KEELCORE_DEV_ENV:-}"

function main() {
  local mode='ro' name='dev'
  while [ "${#}" -gt 0 ]; do
    case "${1}" in
      --writable) mode='rw'; shift ;;
      --image) name="${2:-}"; shift 2 ;;
      *) break ;;
    esac
  done
  validate_args "$@"
  if [ -n "${KEELCORE_DEV_IMAGE:-}" ]; then
    exec "$@"
  fi
  local image
  image="$(dev_image . "${name}")" || exit 1
  run_in "${image}" "${mode}" "$@"
}

function log() {
  local -r msg="${1:-}"
  printf '%s\n' "${msg}" | tee -a '/tmp/keelcore_dev_run.log' >&2
}

function validate_args() {
  if [ "${#}" -eq 0 ] || [ -z "${1:-}" ]; then
    log '❌ Usage: scripts/dev/run.sh COMMAND [ARG...]'
    exit 1
  fi
}

function runtime() {
  if [ "$(uname -s)" = 'Darwin' ]; then printf 'container'; else printf 'docker'; fi
}

# dev_image DIR NAME: the reference for DIR's NAME image — the pinned image.ref when it
# matches the current build context, else a local build of that context.
function dev_image() {
  local -r dir="${1}" name="${2}"
  local -r cf="$(dev_containerfile "${name}")"
  [ -f "${dir}/${cf}" ] || { log "❌ ${dir}/${cf} not found"; exit 1; }
  local base='' hash ref tag
  if dev_has_base "${dir}" "${name}"; then
    base="$(dev_image "${dir}/.standards" dev)" || return 1
  fi
  hash="$(dev_context_hash "${dir}" "${name}" "${base}")"
  if ref="$(dev_pinned_ref "${dir}" "${name}" "${hash}")"; then
    printf '%s' "${ref}"
    return 0
  fi
  if [ -s "${dir}/$(dev_ref_file "${name}")" ]; then
    log "ℹ️  ${dir}/$(dev_ref_file "${name}") pins another build context; building ctx-${hash} locally"
  fi
  tag="keelcore-${name}-$(dev_repo_name "${dir}"):ctx-${hash}"
  if ! "$(runtime)" image inspect "${tag}" > /dev/null 2>&1; then
    build_image "${dir}" "${cf}" "${tag}" "${base}" || { log "❌ building ${tag} failed"; exit 1; }
  fi
  printf '%s' "${tag}"
}

function build_image() {
  local -r dir="${1}" cf="${2}" tag="${3}" base="${4}"
  local -a args=(build -f "${dir}/${cf}" -t "${tag}")
  [ -z "${base}" ] || args+=(--build-arg "BASE_DEV_IMAGE=${base}")
  log "🔨 Building image ${tag}..."
  "$(runtime)" "${args[@]}" "${dir}" >&2
}

# run_in IMAGE MODE COMMAND...: COMMAND in IMAGE, the outermost repository mounted at /work
# (MODE ro or rw; a submodule's git directory lives in its superproject) with this
# repository's target/ writable, working directory the same relative path as here.
function run_in() {
  local -r image="${1}" mode="${2}"
  shift 2
  local outer here rel name
  here="$(git rev-parse --show-toplevel)"
  outer="$(git rev-parse --show-superproject-working-tree)"
  outer="${outer:-${here}}"
  rel="${PWD#"${outer}"}"
  mkdir -p "${here}/target"
  local -a args=(run --rm -i -v "${outer}:/work:${mode}" -w "/work${rel}")
  [ "${mode}" = 'ro' ] && args+=(-v "${here}/target:/work${here#"${outer}"}/target")
  [ -t 1 ] && args+=(-t)
  for name in ${PASS_ENV}; do
    [ -n "${!name:-}" ] && args+=(-e "${name}=${!name}")
  done
  # GitHub Actions file commands: the event payload (read) and the output / summary files (append).
  local file fmode mounted=" "
  for name in GITHUB_EVENT_PATH GITHUB_OUTPUT GITHUB_STEP_SUMMARY; do
    file="${!name:-}"
    [ -n "${file}" ] && [ -e "${file}" ] || continue
    case "${mounted}" in *" $(dirname "${file}") "*) continue ;; esac
    mounted+="$(dirname "${file}") "
    fmode='rw'
    [ "${name}" = 'GITHUB_EVENT_PATH' ] && fmode='ro'
    args+=(-v "$(dirname "${file}"):$(dirname "${file}"):${fmode}")
  done
  exec "$(runtime)" "${args[@]}" "${image}" "$@"
}

main "$@"
