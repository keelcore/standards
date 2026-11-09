#!/usr/bin/env bash
# tests/helpers-dev-image.bash: a repository with a tool image context, a fake container runtime and a fake
# registry, for run.sh's image choice.
# Environment: WORK (default empty): the test's scratch directory; the test sets it before it loads this file.

declare -rx WORK="${WORK:-}"

# local_build_repo: ${WORK}/r holds containers/dev/Containerfile; on this machine only the local build of its
# context (keelcore-dev-*:ctx-*) is present, never the pinned name. Every runtime and curl call is recorded in
# ${WORK}/calls and ${WORK}/curl-calls; the registry publishes nothing.
local_build_repo() {
  mkdir -p "${WORK}/r/containers/dev" "${WORK}/fake"
  printf 'FROM scratch\n' > "${WORK}/r/containers/dev/Containerfile"
  local tool
  for tool in container docker; do
    cat > "${WORK}/fake/${tool}" <<STUB
#!/usr/bin/env bash
echo "\$*" >> "${WORK}/calls"
if [ "\${2:-}" = inspect ]; then [[ "\${3:-}" == keelcore-dev-*:ctx-* ]]; fi
STUB
    chmod +x "${WORK}/fake/${tool}"
  done
  printf '#!/usr/bin/env bash\necho "$*" >> "%s/curl-calls"\nexit 22\n' "${WORK}" > "${WORK}/fake/curl"
  chmod +x "${WORK}/fake/curl"
  cd "${WORK}/r"
  git init --quiet
  git add -A
}
