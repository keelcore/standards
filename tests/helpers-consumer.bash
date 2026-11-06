#!/usr/bin/env bash
# tests/helpers-consumer.bash: a throwaway consumer of the canonical scripts, with stubbed tools.

# consumer_setup: a git repo holding the canonical scripts and a .standards symlink; WORK, CALLS, a
# bin/ on PATH. stub NAME [BODY] writes a tool that records its call, its directory, and runs BODY.
consumer_setup() {
  STANDARDS="$(cd "${BATS_TEST_DIRNAME}/.." && pwd -P)"
  WORK="${BATS_TEST_TMPDIR}/work"
  CALLS="${BATS_TEST_TMPDIR}/calls"
  export WORK CALLS STANDARDS
  mkdir -p "${WORK}/bin"
  : > "${CALLS}"
  cd "${WORK}"
  git init --quiet
  git config user.email t@example.com
  git config user.name t
  cp -R "${STANDARDS}/scripts" scripts
  ln -s "${STANDARDS}" .standards
  printf 'bin/\n.standards\nscripts/\n' > .gitignore
  export PATH="${WORK}/bin:${PATH}"
}

stub() {
  {
    printf '#!/usr/bin/env bash\nprintf "%%s|%%s\\n" "$(basename "$0")" "$*" >> "%s"\n' "${CALLS}"
    printf '%s\n' "${2:-}"
  } > "${WORK}/bin/${1}"
  chmod +x "${WORK}/bin/${1}"
}

track() {
  local f
  for f in "$@"; do
    mkdir -p "$(dirname "${f}")"
    [ -e "${f}" ] || printf 'x\n' > "${f}"
    git add -f "${f}"
  done
}

calls_of() { grep -F "${1}|" "${CALLS}" || true; }
