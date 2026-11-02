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
readonly FOO_OLD_HEX="$(printf 'b%.0s' {1..64})"
readonly FOO_NEW_HEX="$(printf 'c%.0s' {1..64})"
readonly SHA_CHECKOUT_NEW='22bd71901bbe5b1630ceea73d27597364c9af683'

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
  commit
  export UPDATE_PINS_FIXTURES="${FIX}" UPDATE_PINS_NOW="${NOW}" UPDATE_PINS_PLATFORM='Darwin'
}

# commit: the worktree verification checks out HEAD.
commit() {
  git add --all
  git -c commit.gpgsign=false -c user.name=t -c user.email=t@example.invalid commit --quiet -m fixture
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
  printf '#!/usr/bin/env bash\nreadonly FOO_VERSION=%s\nreadonly FOO_SHA256=%s\nurl="https://github.com/acme/foo/releases/download/v${FOO_VERSION}/foo"\n' \
    "'1.2.0'" "'${FOO_OLD_HEX}'" > scripts/ci/setup-foo.sh
  # setup-bar fails at v1.1.0: the stale bar pin cannot pass verification.
  printf '#!/usr/bin/env bash\nreadonly TOOL_MODULE=%s\nreadonly TOOL_VERSION=%s\n[ "${TOOL_VERSION}" != v1.1.0 ]\n' \
    "'example.com/bar/cmd/bar'" "'v1.0.0'" > scripts/ci/setup-bar.sh
  # test fails while .fail-combined exists: the combined-run gate.
  printf 'lint-workflows:\n\t@true\nsetup-bar:\n\tbash scripts/ci/setup-bar.sh\nsetup-foo:\n\t@true scripts/ci/setup-foo.sh\nlint:\n\t@true\naudit:\n\t@true\ntest:\n\t@[ ! -f .fail-combined ]\n' \
    > Makefile
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
  run bash scripts/release/update-pins.sh --discover-only
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
  commit
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

# ── verification ─────────────────────────────────────────────────────────────

# verify ARGS...: run the full verification (worktree, per-pin, combined).
verify() {
  run bash scripts/release/update-pins.sh "$@"
}

# result PIN: the verification row for PIN.
result() {
  grep -E "^[a-z]+ +${1} +[^ ]+ +[^ ]+ +(pass|fail|verify-on-ci) " <<< "${output}"
}

checkout_fixture() {
  fixture 'https://api.github.com/repos/actions/checkout/commits/v4.4.0' "{\"sha\":\"${SHA_CHECKOUT_NEW}\"}"
}

@test "verify: a failing pin does not stop the others; each kind maps to its targets" {
  checkout_fixture
  verify
  [ "${status}" -eq 1 ]
  [[ "$(result 'actions/checkout')" == *'pass'*'make lint-workflows'* ]] || false
  [[ "$(result 'example.com/bar/cmd/bar')" == *'fail'*'make setup-bar'* ]] || false
  [[ "$(result 'go')" == *'verify-on-ci'* ]] || false
  [[ "${output}" == *'combined: pass'* ]] || false
  [[ "${output}" == *'Consequences of staying on a stale pin:'* ]] || false
}

@test "verify: the working tree is untouched and the worktree is removed" {
  checkout_fixture
  local before
  before="$(git status --porcelain; git diff)"
  verify
  [ "$(git status --porcelain; git diff)" = "${before}" ]
  [ "$(git worktree list | wc -l | tr -d ' ')" -eq 1 ]
}

@test "verify --apply: writes only passing pins, after the combined run passes" {
  checkout_fixture
  verify --apply
  grep -q "actions/checkout@${SHA_CHECKOUT_NEW}  # v4.4.0" .github/workflows/ci.yml
  grep -q "TOOL_VERSION='v1.0.0'" scripts/ci/setup-bar.sh
  grep -q 'toolchain go1.27.3' go.mod
}

@test "verify --apply: a failing combined run writes nothing" {
  checkout_fixture
  touch .fail-combined
  commit
  verify --apply
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'combined: fail'* ]] || false
  [[ "${output}" == *'nothing written'* ]] || false
  grep -q "actions/checkout@${SHA_CHECKOUT}  # v4.2.2" .github/workflows/ci.yml
}

@test "verify --apply on Linux: a release tool's checksum follows its version" {
  fixture 'https://api.github.com/repos/acme/foo/releases?per_page=100' "$(jq -n \
    --arg old "$(iso 400)" --arg new "$(iso 30)" '[
      {tag_name: "v1.2.0", draft: false, prerelease: false, published_at: $old},
      {tag_name: "v1.3.0", draft: false, prerelease: false, published_at: $new}]')"
  fixture 'https://api.github.com/repos/acme/foo/releases/tags/1.2.0' "$(jq -n --arg h "sha256:${FOO_OLD_HEX}" \
    '{assets: [{name: "foo_1.2.0_linux_amd64.tar.gz", digest: $h}]}')"
  fixture 'https://api.github.com/repos/acme/foo/releases/tags/v1.3.0' "$(jq -n --arg h "sha256:${FOO_NEW_HEX}" \
    '{assets: [{name: "foo_1.3.0_linux_amd64.tar.gz", digest: $h}]}')"
  checkout_fixture
  export UPDATE_PINS_PLATFORM=Linux
  verify --apply
  [[ "$(result 'FOO')" == *'pass'*'make setup-foo'* ]] || false
  grep -q "FOO_VERSION='1.3.0'" scripts/ci/setup-foo.sh
  grep -q "FOO_SHA256='${FOO_NEW_HEX}'" scripts/ci/setup-foo.sh
}

# ── Dependabot union ─────────────────────────────────────────────────────────

# dependabot ...: a GitHub remote, plus the open PRs and alerts it reports.
dependabot() {
  git remote add origin https://github.com/acme/consumer.git
  fixture 'https://api.github.com/repos/acme/consumer/pulls?state=open&per_page=100' "$(jq -n '[
    {number: 7, user: {login: "dependabot[bot]"}, title: "chore(ci): bump actions/checkout from 4.2.2 to 4.5.0"},
    {number: 8, user: {login: "dependabot[bot]"}, title: "Bump alpine from 3.22 to 3.23"},
    {number: 9, user: {login: "someone"}, title: "Bump example.com/lib from 0.3.0 to 9.9.9"}]')"
  fixture 'https://api.github.com/repos/acme/consumer/dependabot/alerts?state=open&per_page=100' "$(jq -n '[
    {number: 3, dependency: {package: {name: "example.com/cur"}},
     security_vulnerability: {first_patched_version: {identifier: "1.0.1"}}}]')"
  printf 'require example.com/cur v1.0.0\n' >> go.mod
  fixture 'https://proxy.golang.org/example.com/cur/@v/list' $'v1.0.0\n'
  commit
}

@test "dependabot: a newer PR candidate wins and SOURCE is both" {
  dependabot
  pins
  [[ "$(row 'actions/checkout')" == *'v4.5.0'*'stale'*'both'*'update-pins: v4.4.0, dependabot: v4.5.0 (PR #7)'* ]] || false
}

@test "dependabot: an alert makes a current pin stale with SOURCE dependabot" {
  dependabot
  pins
  [[ "$(row 'example.com/cur')" == *'v1.0.1'*'stale'*'dependabot'*'dependabot alert #3'* ]] || false
}

@test "dependabot: an image tag suggestion is a note only; non-Dependabot PRs are ignored" {
  dependabot
  pins
  [[ "$(row 'alpine:3.22')" == *'current'*'(dependabot: 3.23, PR #8)'* ]] || false
  [[ "$(row 'example.com/lib')" != *'9.9.9'* ]] || false
}
