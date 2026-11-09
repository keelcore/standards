#!/usr/bin/env bats
# tests/run-env.bats
# scripts/dev/run.sh passes into the tool image every environment variable the script it runs imports
# (governance/bash.md R37), transitively through the files it sources, its project hook and the scripts it
# runs by path, when set; plus the GitHub Actions globals and TZ. Names only, in an --env-file: no value
# reaches the runtime's arguments or the file.

bats_require_minimum_version 1.5.0

setup() {
  STANDARDS="$(cd "${BATS_TEST_DIRNAME}/.." && pwd -P)"
  WORK="${BATS_TEST_TMPDIR}"
  REPO="${WORK}/repo"
  mkdir -p "${WORK}/bin" "${REPO}/containers/dev" "${REPO}/scripts/lib" "${REPO}/scripts/dev"
  # The fake runtime records its arguments, one per line, and the env file it is given.
  cat > "${WORK}/bin/docker" << 'FAKE'
#!/usr/bin/env bash
[ "${1}" = 'run' ] || exit 0
printf '%s\n' "$@" > "${RUN_ARGS}"
while [ "${#}" -gt 0 ]; do
  [ "${1}" = '--env-file' ] && cp "${2}" "${RUN_ENV}" && stat -c '%a' "${2}" > "${RUN_ENV}.mode" && printf '%s' "${2}" > "${RUN_ENV}.path"
  shift
done
FAKE
  chmod +x "${WORK}/bin/docker"
  cp "${WORK}/bin/docker" "${WORK}/bin/container"
  export RUN_ARGS="${WORK}/args" RUN_ENV="${WORK}/env"
  cd "${REPO}"
  git init --quiet
  cp "${STANDARDS}/scripts/dev/run.sh" scripts/dev/
  cp "${STANDARDS}/scripts/lib/"*.sh scripts/lib/
  printf 'FROM scratch\n' > containers/dev/Containerfile
  local hash
  hash="$(bash -c "source scripts/lib/dev-image.sh; dev_context_hash . dev")"
  printf 'ghcr.io/keelcore/x-dev:ctx-%s@sha256:0\n' "${hash}" > containers/dev/image.ref
  # The chain: a script importing FOO, a library it sources importing BAR, its hook importing BAZ, and
  # a script it runs by path importing QUX; GH_TOKEN, and a mismatched import.
  printf '%s\n' '#!/usr/bin/env bash' 'declare -rx BAR="${BAR:-}"' > scripts/lib/fix.sh
  printf '%s\n' '#!/usr/bin/env bash' 'source "$(dirname "${BASH_SOURCE[0]}")/../lib/fix.sh"' \
    'declare -rx FOO="${FOO:-}"' 'declare -rx GH_TOKEN="${GH_TOKEN:-}"' 'declare -rx ALIAS="${OTHER:-}"' \
    'bash scripts/dev/c.sh' > scripts/dev/a.sh
  printf '%s\n' '#!/usr/bin/env bash' 'declare -rx BAZ="${BAZ:-}"' > scripts/dev/a.local.sh
  printf '%s\n' '#!/usr/bin/env bash' 'declare -rx QUX="${QUX:-}"' > scripts/dev/c.sh
  PATH="${WORK}/bin:${PATH}"
}

# run_env ARG...: run.sh ARG... outside any tool image, with only TZ and PATH from the caller.
run_env() {
  run env -i PATH="${PATH}" HOME="${HOME}" RUN_ARGS="${RUN_ARGS}" RUN_ENV="${RUN_ENV}" TZ=UTC "$@"
}

@test "run.sh: each name the chain imports is passed by name when set; an unset one is not" {
  run_env FOO=1 BAR=2 BAZ=3 QUX=4 PROBE_UNLISTED=5 bash scripts/dev/run.sh bash scripts/dev/a.sh
  [ "${status}" -eq 0 ] || { printf '%s\n' "${output}"; return 1; }
  local n
  for n in FOO BAR BAZ QUX TZ; do grep -qx "${n}" "${RUN_ENV}" || { printf 'missing %s\n' "${n}"; return 1; }; done
  ! grep -q 'PROBE_UNLISTED' "${RUN_ENV}"
  ! grep -qx 'GH_TOKEN' "${RUN_ENV}"
}

@test "run.sh: a script given by its path, not through bash, is read the same way" {
  run_env FOO=1 bash scripts/dev/run.sh scripts/dev/a.sh
  [ "${status}" -eq 0 ]
  grep -qx FOO "${RUN_ENV}"
}

@test "run.sh: the GitHub Actions globals and CI are passed" {
  run_env CI=true GITHUB_REF_NAME=main RUNNER_OS=Linux ACTIONS_ID_TOKEN_REQUEST_URL=u \
    bash scripts/dev/run.sh bash scripts/dev/a.sh
  local n
  for n in CI GITHUB_REF_NAME RUNNER_OS ACTIONS_ID_TOKEN_REQUEST_URL; do
    grep -qx "${n}" "${RUN_ENV}" || { printf 'missing %s\n' "${n}"; return 1; }
  done
}

@test "run.sh: a token is passed by name; its value is in neither the arguments nor the env file" {
  run_env GH_TOKEN=s3cret bash scripts/dev/run.sh bash scripts/dev/a.sh
  grep -qx GH_TOKEN "${RUN_ENV}"
  ! grep -q s3cret "${RUN_ARGS}" "${RUN_ENV}"
}

@test "run.sh: the env file is private and removed after the run" {
  run_env FOO=1 bash scripts/dev/run.sh bash scripts/dev/a.sh
  [ "$(cat "${RUN_ENV}.mode")" = 600 ]
  [ ! -e "$(cat "${RUN_ENV}.path")" ]
}

@test "run.sh: a command that runs no script gets the Actions globals and TZ only" {
  run_env FOO=1 CI=true bash scripts/dev/run.sh true
  [ "${status}" -eq 0 ]
  grep -qx CI "${RUN_ENV}"
  grep -qx TZ "${RUN_ENV}"
  ! grep -qx FOO "${RUN_ENV}"
}

@test "run.sh: a mismatched import (declare -rx A=\"\${B:-}\") is not passed" {
  run_env ALIAS=1 OTHER=2 bash scripts/dev/run.sh bash scripts/dev/a.sh
  [ -f "${RUN_ENV}" ]
  ! grep -qx ALIAS "${RUN_ENV}"
  ! grep -qx OTHER "${RUN_ENV}"
}

@test "run.sh: a library in the chain that is missing fails, naming it, and runs nothing" {
  printf '%s\n' '#!/usr/bin/env bash' 'source "$(dirname "${BASH_SOURCE[0]}")/../lib/gone.sh"' > scripts/dev/b.sh
  run_env bash scripts/dev/run.sh bash scripts/dev/b.sh
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'scripts/lib/gone.sh'* ]] || false
  [ ! -e "${RUN_ARGS}" ]
}

@test "run.sh holds no PASS_ENV; nothing names KEELCORE_DEV_ENV" {
  ! grep -n 'PASS_ENV' "${STANDARDS}/scripts/dev/run.sh"
  ! git -C "${STANDARDS}" grep -n 'KEELCORE_DEV_ENV' -- scripts templates .github
}
