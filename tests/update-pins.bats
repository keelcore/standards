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

@test "consumer: a pin in a canonical file is held by .standards; an edited copy is the consumer's own" {
  mkdir -p .standards/scripts/ci
  cp -p scripts/ci/setup-foo.sh .standards/scripts/ci/setup-foo.sh
  commit
  pins
  [[ "$(row 'FOO')" == *'hold'*'held by .standards (canonical scripts/ci/setup-foo.sh)'* ]] || false
  printf '# local edit\n' >> scripts/ci/setup-foo.sh
  commit
  pins
  [[ "$(row 'FOO')" == *'v1.3.0'*'cooldown'* ]] || false
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

@test "verify: an interrupted run stops its verifications and removes every worktree" {
  checkout_fixture
  # The action's verification target outlives the interrupt unless the driver stops it.
  perl -0pi -e 's/lint-workflows:\n\t\@true\n/lint-workflows:\n\t\@sleep 37.5\n/' Makefile
  commit
  bash scripts/release/update-pins.sh > "${BATS_TEST_TMPDIR}/run.log" 2>&1 &
  local pid="${!}" i
  for (( i = 0; i < 100; i++ )); do
    pgrep -f 'sleep 37.5' > /dev/null && break
    sleep 0.2
  done
  pgrep -f 'sleep 37.5' > /dev/null
  kill -TERM "${pid}"
  wait "${pid}" || true
  ! pgrep -f 'sleep 37.5' > /dev/null
  [ "$(git worktree list | wc -l | tr -d ' ')" -eq 1 ]
  grep -q 'interrupted' "${BATS_TEST_TMPDIR}/run.log"
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

@test "runner: an exact image label is a pin; a newer image is report-only; -latest floats" {
  printf 'jobs:\n  a:\n    runs-on: ubuntu-24.04\n  b:\n    runs-on: ${{ matrix.os }}\n    strategy:\n      matrix:\n        include:\n          - os: macos-26\n  c:\n    runs-on: windows-latest\n' \
    > .github/workflows/runners.yml
  fixture 'https://raw.githubusercontent.com/actions/runner-images/main/README.md' \
    $'| x | `ubuntu-24.04` |\n| y | `ubuntu-26.04` |\n| z | `ubuntu-26.04-arm` |\n| m | `macos-26` |\n'
  commit
  pins
  [[ "$(row 'ubuntu-24.04')" == *'ubuntu-26.04'*'major'*'(report-only)'* ]] || false
  [[ "$(row 'macos-26')" == *'current'* ]] || false
  [[ "$(row 'windows-latest')" == *'unpinned'*'floats (runner image)'* ]] || false
}

@test "python: newest eligible patch in the pinned minor; a minor-only pin floats" {
  printf '3.12.15\n' > .python-version
  mkdir -p sub && printf '3.12\n' > sub/.python-version
  fixture 'https://api.github.com/repos/actions/python-versions/releases?per_page=100' "$(jq -n \
    --arg old "$(iso 30)" --arg fresh "$(iso 3)" '[
      {tag_name: "3.12.16-100", draft: false, prerelease: false, published_at: $old},
      {tag_name: "3.12.17-101", draft: false, prerelease: false, published_at: $fresh},
      {tag_name: "3.13.9-102", draft: false, prerelease: false, published_at: $old}]')"
  commit
  pins
  [[ "$(grep -F '(.python-version:1)' <<< "${output}")" == *'3.12.16'*'stale'* ]] || false
  [[ "$(grep -F '(sub/.python-version:1)' <<< "${output}")" == *'unpinned'*'minor only'* ]] || false
}

@test "pypi: hash-locked requirement and exact build-system requirement; pip without hashes floats" {
  printf 'build==1.0.0 \\\n    --hash=sha256:%s\n' "${FOO_OLD_HEX}" > requirements-build.txt
  printf '[build-system]\nrequires = ["hatchling==1.0.0"]\n' > pyproject.toml
  printf '#!/usr/bin/env bash\npip install --quiet hatch\n' > scripts/ci/setup-py.sh
  fixture 'https://pypi.org/pypi/build/json' "$(jq -n --arg old "$(iso 300)" --arg new "$(iso 20)" '{releases: {
    "1.0.0": [{upload_time_iso_8601: $old, yanked: false}],
    "1.1.0": [{upload_time_iso_8601: $new, yanked: false}],
    "1.2.0rc1": [{upload_time_iso_8601: $new, yanked: false}]}}')"
  fixture 'https://pypi.org/pypi/hatchling/json' "$(jq -n --arg old "$(iso 300)" '{releases: {
    "1.0.0": [{upload_time_iso_8601: $old, yanked: false}]}}')"
  commit
  pins
  [[ "$(row 'build')" == *'1.1.0'*'stale'* ]] || false
  [[ "$(row 'hatchling')" == *'current'* ]] || false
  [[ "$(row 'pip:hatch')" == *'unpinned'* ]] || false
}

@test "npmlock: exact dependency beside a lockfile is a pin; a range and npx without a version float" {
  mkdir -p tools/lint
  printf '{\n  "dependencies": {\n    "lintcli": "1.0.0"\n  }\n}\n' > tools/lint/package.json
  printf '{}\n' > tools/lint/package-lock.json
  printf '{\n  "devDependencies": {\n    "loose": "^2.0.0"\n  }\n}\n' > package.json
  printf '#!/usr/bin/env bash\nnpx --yes some-cli .\n' > scripts/ci/setup-npx.sh
  fixture 'https://registry.npmjs.org/lintcli' "$(jq -n --arg old "$(iso 300)" --arg new "$(iso 20)" \
    '{time: {"1.0.0": $old, "1.0.1": $new}}')"
  commit
  pins
  [[ "$(row 'lintcli')" == *'1.0.1'*'stale'* ]] || false
  [[ "$(row 'npm:loose')" == *'unpinned'* ]] || false
  [[ "$(row 'npx:some-cli')" == *'unpinned'* ]] || false
}

@test "tool: a release tag cloned with git resolves against its GitHub repo" {
  printf '#!/usr/bin/env bash\nreadonly QUX_VERSION=%s\nreadonly QUX_COMMIT=%s\ngit clone --branch "v${QUX_VERSION}" https://github.com/acme/qux.git\n' \
    "'1.0.0'" "'${SHA_CHECKOUT}'" > scripts/ci/setup-qux.sh
  fixture 'https://api.github.com/repos/acme/qux/releases?per_page=100' "$(jq -n \
    --arg old "$(iso 300)" --arg new "$(iso 20)" '[
      {tag_name: "v1.0.0", draft: false, prerelease: false, published_at: $old},
      {tag_name: "v1.1.0", draft: false, prerelease: false, published_at: $new}]')"
  commit
  pins
  [[ "$(row 'QUX')" == *'v1.1.0'*'stale'* ]] || false
}

@test "verify --apply on Linux: a cloned tool's commit follows its version" {
  printf '#!/usr/bin/env bash\nreadonly QUX_VERSION=%s\nreadonly QUX_COMMIT=%s\ngit clone --branch "v${QUX_VERSION}" https://github.com/acme/qux.git\n' \
    "'1.0.0'" "'${SHA_CHECKOUT}'" > scripts/ci/setup-qux.sh
  printf 'setup-qux:\n\t@true scripts/ci/setup-qux.sh\n' >> Makefile
  fixture 'https://api.github.com/repos/acme/qux/releases?per_page=100' "$(jq -n \
    --arg old "$(iso 300)" --arg new "$(iso 20)" '[
      {tag_name: "v1.0.0", draft: false, prerelease: false, published_at: $old},
      {tag_name: "v1.1.0", draft: false, prerelease: false, published_at: $new}]')"
  fixture 'https://api.github.com/repos/acme/qux/releases/tags/1.0.0' '{"assets": []}'
  fixture 'https://api.github.com/repos/acme/qux/releases/tags/v1.1.0' '{"assets": []}'
  fixture 'https://api.github.com/repos/acme/qux/commits/v1.1.0' "{\"sha\":\"${SHA_CHECKOUT_NEW}\"}"
  checkout_fixture
  commit
  export UPDATE_PINS_PLATFORM=Linux
  verify --apply
  [[ "$(result 'QUX')" == *'pass'*'make setup-qux'* ]] || false
  grep -q "QUX_VERSION='1.1.0'" scripts/ci/setup-qux.sh
  grep -q "QUX_COMMIT='${SHA_CHECKOUT_NEW}'" scripts/ci/setup-qux.sh
}

@test "verify --apply: a pypi pin's hashes follow its version" {
  printf 'build==1.0.0 \\\n    --hash=sha256:%s \\\n    --hash=sha256:%s\nother==2.0.0 \\\n    --hash=sha256:%s\n' \
    "${FOO_OLD_HEX}" "${FOO_OLD_HEX}" "${FOO_OLD_HEX}" > requirements-build.txt
  # The project hook verifies pypi pins locally with lint.
  printf '#!/usr/bin/env bash\ncase "${1}" in\n  verify) [ "${2}" = pypi ] && printf lint ;;\n  apply) exit 3 ;;\nesac\nexit 0\n' \
    > scripts/release/update-pins.local.sh
  fixture 'https://pypi.org/pypi/build/json' "$(jq -n --arg old "$(iso 300)" --arg new "$(iso 20)" '{releases: {
    "1.0.0": [{upload_time_iso_8601: $old, yanked: false}],
    "1.1.0": [{upload_time_iso_8601: $new, yanked: false}]}}')"
  fixture 'https://pypi.org/pypi/other/json' "$(jq -n --arg old "$(iso 300)" '{releases: {
    "2.0.0": [{upload_time_iso_8601: $old, yanked: false}]}}')"
  fixture 'https://pypi.org/pypi/build/1.1.0/json' "$(jq -n --arg a "${FOO_NEW_HEX}" --arg b "${DIGEST#sha256:}" \
    '{urls: [{digests: {sha256: $a}}, {digests: {sha256: $b}}]}')"
  checkout_fixture
  commit
  verify --apply
  [[ "$(result 'build')" == *'pass'*'make lint'* ]] || false
  grep -q '^build==1.1.0 \\$' requirements-build.txt
  grep -q "sha256:${FOO_NEW_HEX}" requirements-build.txt
  grep -q "sha256:${DIGEST#sha256:}" requirements-build.txt
  [ "$(grep -c "sha256:${FOO_OLD_HEX}" requirements-build.txt)" -eq 1 ]
  grep -q '^other==2.0.0 \\$' requirements-build.txt
}

@test "unpinned: build-time packages float until the tool image is pinned by digest" {
  mkdir -p containers/dev containers/other
  printf 'FROM scratch\nRUN apt-get install -y jq\n' > containers/dev/Containerfile
  printf 'example.invalid/x-dev:ctx-1@%s\n' "${DIGEST}" > containers/dev/image.ref
  printf 'FROM scratch\nRUN apt-get install -y xz-utils\n' > containers/other/Containerfile
  commit
  pins
  [ -z "$(row 'apt:jq')" ]
  [[ "$(row 'apt:xz-utils')" == *'unpinned'* ]] || false
}

@test "verify --apply: a Node pin moves the node base image with it" {
  printf '22.1.0\n' > .nvmrc
  printf 'FROM node:22.1.0-slim@%s AS node\n' "${DIGEST}" > Containerfile.node
  fixture 'https://nodejs.org/dist/index.json' "$(jq -n --arg old "$(iso 300 | cut -c1-10)" --arg new "$(iso 30 | cut -c1-10)" '[
    {version: "v22.1.0", date: $old, lts: "Jod"},
    {version: "v22.1.1", date: $new, lts: "Jod"}]')"
  fixture 'digest:node:22.1.0-slim' "${DIGEST}"
  fixture 'digest:node:22.1.1-slim' "sha256:${FOO_NEW_HEX}"
  checkout_fixture
  commit
  verify --apply
  [[ "$(result 'node')" == *'pass'*'make lint'* ]] || false
  grep -qx '22.1.1' .nvmrc
  grep -qF "FROM node:22.1.1-slim@sha256:${FOO_NEW_HEX} AS node" Containerfile.node
}

@test "--pins-md: every pin and floating input as a Markdown table" {
  run bash scripts/release/update-pins.sh --discover-only --pins-md current_pins.md
  [ "${status}" -eq 0 ]
  grep -qx '# Current pins' current_pins.md
  grep -qx '| Kind | Pin | Pinned | Status | Candidate | Pinned in |' current_pins.md
  grep -qF '| action | `actions/checkout` | `v4.2.2` | stale | `v4.4.0` | `.github/workflows/ci.yml:4` |' current_pins.md
  grep -qF '| unpinned | `apk:curl` |' current_pins.md
}
