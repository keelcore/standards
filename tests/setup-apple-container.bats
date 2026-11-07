#!/usr/bin/env bats
# tests/setup-apple-container.bats
# scripts/ci/setup-apple-container.sh installs the signed installer package of Apple's latest
# GitHub release, and changes nothing when that version is already installed.

readonly LATEST='9.9.9'
readonly DIGEST='b6739caf3d47ca53a78f1a7edf32521420a75c7941838c3cefa75f30b80f5a97'

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SCRIPT="${REPO_ROOT}/scripts/ci/setup-apple-container.sh"
  STUBS="${BATS_TEST_TMPDIR}/usr/bin"
  CALLS="${BATS_TEST_TMPDIR}/calls"
  INSTALLED="${BATS_TEST_TMPDIR}/installed"
  RELEASE="${BATS_TEST_TMPDIR}/release.json"
  export TMPDIR="${BATS_TEST_TMPDIR}/work"
  export CALLS INSTALLED RELEASE LATEST
  export FAKE_OS='Darwin' FAKE_ARCH='arm64' FAKE_SHA_RC='0' FAKE_API_RC='0'
  export FAKE_SIGNER='Developer ID Installer: Apple Inc. - Containerization (UPBK2H6LZM)'
  export FAKE_NOTARY='trusted by the Apple notary service'
  mkdir -p "${STUBS}" "${TMPDIR}"
  : > "${CALLS}"
  release_json "sha256:${DIGEST}" "container-${LATEST}-installer-signed.pkg"
  stub uname 'if [ "${1}" = "-s" ]; then echo "${FAKE_OS}"; else echo "${FAKE_ARCH}"; fi'
  stub curl 'case "$*" in
  *api.github.com/repos/apple/container/releases/latest*) cat "${RELEASE}"; exit "${FAKE_API_RC}" ;;
esac
echo "curl $*" >> "${CALLS}"
while [ "${#}" -gt 1 ]; do [ "${1}" = "-o" ] && touch "${2}"; shift; done'
  stub shasum 'echo "shasum $* $(cat)" >> "${CALLS}"; exit "${FAKE_SHA_RC}"'
  stub pkgutil 'printf "   Status: signed by a developer certificate issued by Apple for distribution\n   Notarization: %s\n    1. %s\n" "${FAKE_NOTARY}" "${FAKE_SIGNER}"'
  stub id 'echo 1000'
  stub sudo 'echo "sudo $*" >> "${CALLS}"; exec "$@"'
  stub installer 'echo "installer $*" >> "${CALLS}"; echo "${FAKE_INSTALLS:-${LATEST}}" > "${INSTALLED}"; [ -z "${FAKE_CLI:-}" ] || cp "${FAKE_CLI}" "$(dirname "$0")/container"'
  PATH="${STUBS}:$(path_without_container)"
}

# path_without_container: PATH minus any directory holding a real container, so no test can reach it.
path_without_container() {
  local dir kept=''
  while IFS= read -r dir; do
    [ -x "${dir}/container" ] || kept="${kept:+${kept}:}${dir}"
  done < <(tr ':' '\n' <<< "${PATH}")
  printf '%s' "${kept}"
}

stub() {
  printf '#!/usr/bin/env bash\n%s\n' "${2}" > "${STUBS}/${1}"
  chmod +x "${STUBS}/${1}"
}

# release_json DIGEST ASSET: the latest release, publishing ASSET next to the unsigned package.
release_json() {
  printf '{"tag_name":"%s","assets":[{"name":"container-installer-unsigned.pkg","digest":"sha256:0000","browser_download_url":"https://github.com/apple/container/releases/download/%s/container-installer-unsigned.pkg"},{"name":"%s","digest":"%s","browser_download_url":"https://github.com/apple/container/releases/download/%s/%s"}]}\n' \
    "${LATEST}" "${LATEST}" "${2}" "${1}" "${LATEST}" "${2}" > "${RELEASE}"
}

# have_container VERSION [DIR]: a container CLI at VERSION, in DIR (default: the stub directory). Its system
# is running once ${STUBS}/running exists: system start creates it (unless FAKE_START_RC fails it), system stop
# removes it, and system status reports it.
have_container() {
  local -r dir="${2:-${STUBS}}"
  mkdir -p "${dir}"
  echo "${1}" > "${INSTALLED}"
  cat > "${dir}/container" <<STUB
#!/usr/bin/env bash
case "\${1}" in
  --version) echo "container CLI version \$(cat "${INSTALLED}") (build: release, commit: abc)" ;;
  *)
    echo "container \$*" >> "${CALLS}"
    case "\$*" in
      'system status') [ -f "${STUBS}/running" ] ;;
      'system start --enable-kernel-install') [ "\${FAKE_START_RC:-0}" = 0 ] || exit "\${FAKE_START_RC}"; touch "${STUBS}/running" ;;
      'system stop') rm -f "${STUBS}/running" ;;
    esac ;;
esac
STUB
  chmod +x "${dir}/container"
}

# nothing_replaced: no download, no install, and the running system is left running.
nothing_replaced() {
  ! grep -qE '^(curl|sudo|installer|shasum|container system stop)' "${CALLS}"
}

# started_with_kernel_after_install: the system starts, with its kernel, on the new version.
started_with_kernel_after_install() {
  local start
  start="$(grep -nx 'container system start --enable-kernel-install' "${CALLS}" | cut -d: -f1)"
  [ "${start}" -gt "$(grep -n '^installer ' "${CALLS}" | cut -d: -f1)" ]
}

@test "setup-apple-container: the latest release already installed and running changes nothing" {
  have_container "${LATEST}"
  touch "${STUBS}/running"
  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"${LATEST} already installed"* ]] || false
  nothing_replaced
  ! grep -q '^container system start' "${CALLS}"
}

@test "setup-apple-container: the latest release installed but stopped is started, with its kernel" {
  have_container "${LATEST}"
  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  nothing_replaced
  grep -qx 'container system start --enable-kernel-install' "${CALLS}"
}

@test "setup-apple-container: a fresh install fetches the latest signed package and runs the installer as root" {
  have_container "${LATEST}" "${BATS_TEST_TMPDIR}/after"
  FAKE_CLI="${BATS_TEST_TMPDIR}/after/container" run bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  grep -qF "https://github.com/apple/container/releases/download/${LATEST}/container-${LATEST}-installer-signed.pkg" "${CALLS}"
  grep -qE 'curl .*--retry 5 --retry-delay 10 --retry-all-errors' "${CALLS}"
  grep -qF "shasum -a 256 --check --quiet ${DIGEST}  " "${CALLS}"
  grep -qE '^sudo installer -pkg .*installer-signed\.pkg -target /$' "${CALLS}"
  [ -z "$(grep '^container system stop' "${CALLS}")" ]
  started_with_kernel_after_install
}

@test "setup-apple-container: another version is stopped first, then replaced" {
  have_container '0.0.1'
  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  [ "$(grep -nE '^container system stop' "${CALLS}" | cut -d: -f1)" -lt "$(grep -n '^installer ' "${CALLS}" | cut -d: -f1)" ]
  [[ "${output}" == *"${LATEST} installed"* ]] || false
  started_with_kernel_after_install
}

@test "setup-apple-container: a second run after installing changes nothing" {
  have_container '0.0.1'
  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  : > "${CALLS}"
  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  nothing_replaced
}

@test "setup-apple-container: a failed start, or kernel install, fails the run" {
  have_container "${LATEST}"
  FAKE_START_RC='1' run bash "${SCRIPT}"
  [ "${status}" -ne 0 ]
}

@test "setup-apple-container: a Homebrew install is refused, untouched" {
  have_container '0.0.1' "${BATS_TEST_TMPDIR}/opt/homebrew/bin"
  PATH="${BATS_TEST_TMPDIR}/opt/homebrew/bin:${PATH}" run bash "${SCRIPT}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"brew uninstall container"* ]] || false
  [ ! -s "${CALLS}" ]
}

@test "setup-apple-container: an unreachable release API stops with nothing changed" {
  have_container '0.0.1'
  FAKE_API_RC='22' run bash "${SCRIPT}"
  [ "${status}" -ne 0 ]
  [ ! -s "${CALLS}" ]
}

@test "setup-apple-container: a release without the signed package stops with nothing changed" {
  have_container '0.0.1'
  release_json "sha256:${DIGEST}" 'container-other.pkg'
  run bash "${SCRIPT}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"container-${LATEST}-installer-signed.pkg"* ]] || false
  [ ! -s "${CALLS}" ]
}

@test "setup-apple-container: a release without a SHA-256 digest stops with nothing changed" {
  have_container '0.0.1'
  release_json 'null' "container-${LATEST}-installer-signed.pkg"
  run bash "${SCRIPT}"
  [ "${status}" -ne 0 ]
  [ ! -s "${CALLS}" ]
}

@test "setup-apple-container: a checksum mismatch stops before the installer and removes the package" {
  have_container '0.0.1'
  FAKE_SHA_RC='1' run bash "${SCRIPT}"
  [ "${status}" -ne 0 ]
  [ -z "$(grep '^installer ' "${CALLS}")" ]
  [ -z "$(ls -A "${TMPDIR}")" ]
}

@test "setup-apple-container: another signer stops before the installer" {
  have_container '0.0.1'
  FAKE_SIGNER='Developer ID Installer: Someone Else (AAAAAAAAAA)' run bash "${SCRIPT}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"signature"* ]] || false
  [ -z "$(grep '^installer ' "${CALLS}")" ]
}

@test "setup-apple-container: a package without notarization stops before the installer" {
  have_container '0.0.1'
  FAKE_NOTARY='none' run bash "${SCRIPT}"
  [ "${status}" -ne 0 ]
  [ -z "$(grep '^installer ' "${CALLS}")" ]
}

@test "setup-apple-container: the installed version must be the latest afterwards" {
  have_container '0.0.1'
  FAKE_INSTALLS='0.0.2' run bash "${SCRIPT}"
  [ "${status}" -ne 0 ]
  [[ "${output}" == *"0.0.2"* ]]
}

@test "setup-apple-container: runs only on macOS on Apple silicon" {
  FAKE_OS='Linux' run bash "${SCRIPT}"
  [ "${status}" -ne 0 ]
  [ ! -s "${CALLS}" ]
  FAKE_ARCH='x86_64' run bash "${SCRIPT}"
  [ "${status}" -ne 0 ]
  [ ! -s "${CALLS}" ]
}

@test "setup-apple-container: make target runs on the host" {
  grep -qxF "$(printf '\tbash scripts/ci/setup-apple-container.sh')" "${REPO_ROOT}/templates/Makefile.canonical"
}
