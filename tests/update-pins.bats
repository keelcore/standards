#!/usr/bin/env bats
# tests/update-pins.bats
# update-pins.sh discovery: every pin kind is found and resolved, eligibility
# (prerelease, cooldown, Go patch cooldown, major / 0.x minor report-only) is
# applied, unpinned inputs are reported, the project hook adds pins and holds,
# and the working tree is left untouched.
#
# Each test builds a throwaway consumer under BATS_TEST_TMPDIR. Every remote
# read comes from UPDATE_PINS_FIXTURES, keyed the way the driver keys URLs, and
# UPDATE_PINS_NOW fixes the clock.

bats_require_minimum_version 1.5.0

readonly NOW=2000000000
readonly DAY=86400
readonly SHA_CHECKOUT='11bd71901bbe5b1630ceea73d27597364c9af683'
readonly DIGEST="sha256:$(printf 'a%.0s' {1..64})"

setup() {
  STANDARDS="$(cd "${BATS_TEST_DIRNAME}/.." && pwd -P)"
  CONSUMER="${BATS_TEST_TMPDIR}/consumer"
  FIX="${BATS_TEST_TMPDIR}/fixtures"
  mkdir -p "${CONSUMER}/scripts/release" "${CONSUMER}/scripts/lib" "${CONSUMER}/scripts/ci" \
    "${CONSUMER}/.github/workflows" "${FIX}"
  cd "${CONSUMER}"
  git init --quiet
  cp -p "${STANDARDS}/scripts/release/update-pins.sh" scripts/release/
  cp -p "${STANDARDS}/scripts/lib/paths.sh" scripts/lib/
  write_consumer
  write_fixtures
  git add --all
  export UPDATE_PINS_FIXTURES="${FIX}" UPDATE_PINS_NOW="${NOW}"
}

# iso DAYS_AGO: ISO-8601 UTC timestamp DAYS_AGO before NOW.
iso() {
  jq -rn --argjson t "$(( NOW - ${1} * DAY ))" '$t | todate'
}

# fixture URL CONTENT: the response the driver gets for URL.
fixture() {
  printf '%s' "${2}" > "${FIX}/$(printf '%s' "${1}" | tr -c 'A-Za-z0-9._-' '_')"
}

write_consumer() {
  printf 'jobs:\n  x:\n    steps:\n      - uses: actions/checkout@%s  # v4.2.2\n' "${SHA_CHECKOUT}" \
    > .github/workflows/ci.yml
  printf '#!/usr/bin/env bash\nreadonly FOO_VERSION=%s\nurl="https://github.com/acme/foo/releases/download/v${FOO_VERSION}/foo"\n' \
    "'1.2.0'" > scripts/ci/setup-foo.sh
  printf '#!/usr/bin/env bash\nreadonly TOOL_MODULE=%s\nreadonly TOOL_VERSION=%s\n' \
    "'example.com/bar/cmd/bar'" "'v1.0.0'" > scripts/ci/setup-bar.sh
  printf '#!/usr/bin/env bash\ngo install example.com/baz@latest\n' > scripts/ci/setup-baz.sh
  printf 'module example.com/consumer\n\ngo 1.27\n\ntoolchain go1.27.3\n\nrequire (\n\texample.com/lib v0.3.0\n\texample.com/ind v1.0.0 // indirect\n)\n' \
    > go.mod
  printf 'FROM alpine:3.22@%s AS base\nRUN apk add --no-cache curl\nFROM ubuntu:24.04\n' "${DIGEST}" > Dockerfile
}

write_fixtures() {
  fixture 'https://api.github.com/repos/actions/checkout/releases?per_page=100' "$(jq -n \
    --arg old "$(iso 400)" --arg new "$(iso 30)" --arg pre "$(iso 20)" '[
      {tag_name: "v4.2.2", draft: false, prerelease: false, published_at: $old},
      {tag_name: "v4.4.0", draft: false, prerelease: false, published_at: $new},
      {tag_name: "v4.5.0", draft: false, prerelease: true,  published_at: $pre},
      {tag_name: "v7.0.0", draft: false, prerelease: false, published_at: $new}]')"
  fixture 'https://api.github.com/repos/acme/foo/releases?per_page=100' "$(jq -n \
    --arg old "$(iso 400)" --arg fresh "$(iso 5)" '[
      {tag_name: "v1.2.0", draft: false, prerelease: false, published_at: $old},
      {tag_name: "v1.3.0", draft: false, prerelease: false, published_at: $fresh}]')"
  fixture 'https://proxy.golang.org/example.com/bar/@v/list' $'v1.0.0\nv1.1.0\n'
  fixture 'https://proxy.golang.org/example.com/bar/@v/v1.1.0.info' "{\"Time\":\"$(iso 20)\"}"
  fixture 'https://proxy.golang.org/example.com/lib/@v/list' $'v0.3.0\nv0.4.0\n'
  fixture 'https://proxy.golang.org/example.com/lib/@v/v0.4.0.info' "{\"Time\":\"$(iso 20)\"}"
  fixture 'https://proxy.golang.org/golang.org/toolchain/@v/list' \
    $'v0.0.1-go1.27.3.linux-amd64\nv0.0.1-go1.27.5.linux-amd64\nv0.0.1-go1.28rc1.linux-amd64\n'
  fixture 'https://proxy.golang.org/golang.org/toolchain/@v/v0.0.1-go1.27.5.linux-amd64.info' \
    "{\"Time\":\"$(iso 3)\"}"
  fixture 'digest:alpine:3.22' "${DIGEST}"
}

pins() {
  run bash scripts/release/update-pins.sh
  [ "${status}" -eq 0 ]
}

# row PIN: the report row for PIN.
row() {
  grep -E "^[a-z]+ +${1} " <<< "${output}"
}

@test "action: newest eligible release in the current major; prerelease skipped; new major report-only" {
  pins
  [[ "$(row 'actions/checkout')" == *'v4.4.0'*'stale'*'major v7.0.0 available (report-only)'* ]] || false
}

@test "tool: a release inside the 14-day cooldown is not a candidate yet" {
  pins
  [[ "$(row 'FOO')" == *'v1.3.0'*'cooldown'* ]] || false
}

@test "gotool: module root found from the command path; eligible release is stale" {
  pins
  [[ "$(row 'example.com/bar/cmd/bar')" == *'v1.1.0'*'stale'* ]] || false
}

@test "gomod: direct requirement only; a 0.x minor bump is report-only" {
  pins
  [[ "$(row 'example.com/lib')" == *'major'*'v0.4.0'* ]] || false
  [ -z "$(row 'example.com/ind')" ]
}

@test "toolchain: a Go patch release is eligible after 2 days; release candidates skipped" {
  pins
  [[ "$(row 'go')" == *'go1.27.5'*'3d'*'stale'* ]] || false
}

@test "image: digest still current for its tag" {
  pins
  [[ "$(row 'alpine:3.22')" == *'current'* ]] || false
}

@test "unpinned: @latest, apk without version, FROM without digest" {
  pins
  [[ "$(row 'example.com/baz@latest')" == *'unpinned'* ]] || false
  [[ "$(row 'apk:curl')" == *'unpinned'* ]] || false
  [[ "$(row 'ubuntu:24.04')" == *'unpinned'* ]] || false
}

@test "hook: pins replace a generic record at the same location; holds carry their reason" {
  cat > scripts/release/update-pins.local.sh <<'EOF'
#!/usr/bin/env bash
case "${1}" in
  pins)  printf 'tool\tFOO\tscripts/ci/setup-foo.sh:2\t1.2.0\tgithub:acme/foo-mirror\n' ;;
  holds) printf '%s\t%s\n' '^ubuntu:' 'base image chosen by the platform team' ;;
esac
EOF
  fixture 'https://api.github.com/repos/acme/foo-mirror/releases?per_page=100' "$(jq -n --arg t "$(iso 30)" \
    '[{tag_name: "v1.2.5", draft: false, prerelease: false, published_at: $t}]')"
  git add --all
  pins
  [[ "$(row 'FOO')" == *'v1.2.5'*'stale'* ]] || false
  [ "$(grep -c '^tool  *FOO ' <<< "${output}")" -eq 1 ]
  [[ "$(row 'ubuntu:24.04')" == *'hold'*'base image chosen by the platform team'* ]] || false
}

@test "summary counts every status; the working tree is untouched" {
  local before
  before="$(git status --porcelain; git diff --cached)"
  pins
  [[ "${output}" == *'update-pins (discovery) — '*' pins: '* ]] || false
  [ "$(git status --porcelain; git diff --cached)" = "${before}" ]
}

@test "a failed lookup is unresolved, never current" {
  rm "${FIX}/$(printf '%s' 'https://api.github.com/repos/acme/foo/releases?per_page=100' | tr -c 'A-Za-z0-9._-' '_')"
  rm "${FIX}/$(printf '%s' 'https://proxy.golang.org/example.com/lib/@v/list' | tr -c 'A-Za-z0-9._-' '_')"
  pins
  [[ "$(row 'FOO')" == *'unresolved'*'lookup failed'* ]] || false
  [[ "$(row 'example.com/lib')" == *'unresolved'*'lookup failed'* ]] || false
}
