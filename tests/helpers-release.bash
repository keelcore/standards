#!/usr/bin/env bash
# tests/helpers-release.bash: stubbed tools for the release script tests.
# Environment: WORK (default empty): the test's scratch directory; the test sets it before it loads this file.

declare -rx WORK="${WORK:-}"

# stub_cosign: a cosign in ${WORK}/bin (on PATH) that records the file it is asked to verify, its last
# argument, in ${WORK}/cosign.log, and succeeds.
stub_cosign() {
  cat > "${WORK}/bin/cosign" <<STUB
#!/usr/bin/env bash
printf '%s\n' "\${@: -1}" >> "${WORK}/cosign.log"
STUB
  chmod +x "${WORK}/bin/cosign"
}
