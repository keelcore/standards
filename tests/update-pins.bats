#!/usr/bin/env bats
# tests/update-pins.bats
# update-pins.sh discovery: every pin kind is found and resolved, eligibility
# (prerelease, cooldown, Go patch cooldown, major report-only unless named by --major) is
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
      {tag_name: "v4.5.0", draft: false, prerelease: true,  published_at: $pre}]')"
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

@test "action: newest eligible release; prerelease skipped" {
  pins
  [[ "$(row 'actions/checkout')" == *'v4.4.0'*'stale'* ]] || false
}

@test "tool: a release inside the 14-day cooldown is not a candidate yet" {
  pins
  [[ "$(row 'FOO')" == *'v1.3.0'*'cooldown'* ]] || false
}

@test "gotool: module root found from the command path; eligible release is stale" {
  pins
  [[ "$(row 'example.com/bar/cmd/bar')" == *'v1.1.0'*'stale'* ]] || false
}

@test "gomod: direct requirement only; a 0.x minor bump is an ordinary update" {
  pins
  [[ "$(row 'example.com/lib')" == *'v0.4.0'*'stale'* ]] || false
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

@test "the report is sorted by status: what needs action first" {
  pins
  local -r order='stale unresolved unpinned major hold cooldown current'
  local got want s
  got="$(grep -E '^[a-z]+ +[^ ]+ ' <<< "${output}" | cut -c93-102 | tr -d ' ' | uniq)"
  want=''
  for s in ${order}; do
    grep -qx "${s}" <<< "${got}" && want+="${s}"$'\n'
  done
  [ "${got}"$'\n' = "${want}" ] || { printf 'got:\n%s\nwant:\n%s\n' "${got}" "${want}"; false; }
  [ "$(wc -l <<< "${got}")" -gt 2 ]
}

@test "setup-helm.sh names its upstream, so update-pins can resolve the pin" {
  grep -q 'github.com/helm/helm/releases/download' "${STANDARDS}/scripts/ci/setup-helm.sh"
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
  [[ "$(result 'go')" == *'make test'* ]] || false
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

@test "verify: a running pin prints elapsed time, its image step and its latest log line" {
  checkout_fixture
  perl -0pi -e 's/lint-workflows:\n\t\@true\n/lint-workflows:\n\t\@echo "#33 [linux\/arm64 stage-1 26\/45] RUN x"; echo "downloading things"; sleep 3\n/' Makefile
  commit
  UPDATE_PINS_PROGRESS_SECONDS=1 verify
  grep -qE '^⏳ [0-9]+m[0-9]{2}s action actions/checkout: image step 26/45: downloading things$' <<< "${output}"
}

@test "verify: each pin prints its result and elapsed time when it finishes" {
  checkout_fixture
  verify
  grep -qE '^✅ action actions/checkout pass [0-9]+m[0-9]{2}s$' <<< "${output}"
  grep -qE '^❌ gotool example.com/bar/cmd/bar fail [0-9]+m[0-9]{2}s$' <<< "${output}"
}

@test "verify: the combined run prints progress too" {
  checkout_fixture
  perl -0pi -e 's/audit:\n\t\@true\n/audit:\n\t\@echo "testing things"; sleep 3\n/' Makefile
  commit
  UPDATE_PINS_PROGRESS_SECONDS=1 verify
  grep -qE '^⏳ [0-9]+m[0-9]{2}s combined: testing things$' <<< "${output}"
}

@test "verify: progress stops when the run ends" {
  checkout_fixture
  export TMPDIR="${BATS_TEST_TMPDIR}"
  UPDATE_PINS_PROGRESS_SECONDS=1 bash scripts/release/update-pins.sh > "${BATS_TEST_TMPDIR}/run.log" 2>&1 || true
  local -r before="$(wc -c < "${BATS_TEST_TMPDIR}/run.log")"
  sleep 3
  [ "$(wc -c < "${BATS_TEST_TMPDIR}/run.log")" -eq "${before}" ]
  ! ls -d "${TMPDIR}"/update-pins.*.running 2> /dev/null
}

@test "verify: progress stops when the run is interrupted" {
  checkout_fixture
  export TMPDIR="${BATS_TEST_TMPDIR}"
  perl -0pi -e 's/lint-workflows:\n\t\@true\n/lint-workflows:\n\t\@sleep 38.5\n/' Makefile
  commit
  UPDATE_PINS_PROGRESS_SECONDS=1 bash scripts/release/update-pins.sh > "${BATS_TEST_TMPDIR}/run.log" 2>&1 &
  local pid="${!}" i
  for (( i = 0; i < 100; i++ )); do
    pgrep -f 'sleep 38.5' > /dev/null && break
    sleep 0.2
  done
  kill -TERM "${pid}"
  wait "${pid}" || true
  local -r before="$(wc -c < "${BATS_TEST_TMPDIR}/run.log")"
  sleep 3
  [ "$(wc -c < "${BATS_TEST_TMPDIR}/run.log")" -eq "${before}" ]
  ! ls -d "${TMPDIR}"/update-pins.*.running 2> /dev/null
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
  grep -q 'toolchain go1.27.5' go.mod
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
  [[ "$(row 'ubuntu-24.04')" == *'ubuntu-26.04'*'stale'* ]] || false
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

@test "--check-pins-doc: a table matching the tree passes; a changed pin fails and is named" {
  mkdir -p docs
  bash scripts/release/update-pins.sh --discover-only --pins-md docs/current_pins.md > /dev/null
  run bash scripts/release/update-pins.sh --check-pins-doc docs/current_pins.md
  [ "${status}" -eq 0 ]
  [[ "${output}" == *'matches the pins in the tree'* ]] || false
  sed -i.bak "s/FOO_VERSION='1.2.0'/FOO_VERSION='1.2.1'/" scripts/ci/setup-foo.sh && rm -f scripts/ci/setup-foo.sh.bak
  run bash scripts/release/update-pins.sh --check-pins-doc docs/current_pins.md
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'only in docs/current_pins.md: tool'*'FOO'*'1.2.0'* ]] || false
  [[ "${output}" == *'only in the tree: tool'*'FOO'*'1.2.1'* ]] || false
}

@test "verify --apply: docs/current_pins.md is rewritten with the pins it wrote" {
  checkout_fixture
  mkdir -p docs
  bash scripts/release/update-pins.sh --discover-only --pins-md docs/current_pins.md > /dev/null
  grep -qF '| action | `actions/checkout` | `v4.2.2` |' docs/current_pins.md
  commit
  verify --apply
  grep -qF '| action | `actions/checkout` | `v4.4.0` |' docs/current_pins.md
  run bash scripts/release/update-pins.sh --check-pins-doc docs/current_pins.md
  [ "${status}" -eq 0 ]
}

# zed_pin CURRENT VERSION:AGE_DAYS...: a tool pin at CURRENT whose releases are these.
zed_pin() {
  local -r current="${1}"
  shift
  printf '#!/usr/bin/env bash\nreadonly ZED_VERSION=%s\nurl="https://github.com/acme/zed/releases/download/v${ZED_VERSION}/zed"\n' \
    "'${current}'" > scripts/ci/setup-zed.sh
  printf 'setup-zed:\n\t@true scripts/ci/setup-zed.sh\n' >> Makefile
  local spec json='[]'
  for spec in "$@"; do
    json="$(jq --arg v "${spec%%:*}" --arg t "$(iso "${spec##*:}")" \
      '. + [{tag_name: $v, draft: false, prerelease: false, published_at: $t}]' <<< "${json}")"
  done
  fixture 'https://api.github.com/repos/acme/zed/releases?per_page=100' "${json}"
  commit
}

@test "0.x: a minor bump is an ordinary update; the cooldown still applies" {
  zed_pin '0.6.7' 'v0.6.7:400' 'v0.8.0:30' 'v0.9.0:5'
  pins
  [[ "$(row 'ZED')" == *'v0.8.0'*'stale'* ]] || false
}

@test "0.x: 1.0.0 is a major update, report-only" {
  zed_pin '0.6.7' 'v0.6.7:400' 'v1.0.0:30'
  pins
  [[ "$(row 'ZED')" == *'v1.0.0'*'major'*'report-only'* ]] || false
}

@test "--major: a named pin moves to its newest major" {
  zed_pin '1.2.0' 'v1.2.0:400' 'v2.0.0:60' 'v3.1.0:30'
  run bash scripts/release/update-pins.sh --discover-only --major ZED
  [ "${status}" -eq 0 ]
  [[ "$(row 'ZED')" == *'v3.1.0'*'stale'* ]] || false
}

@test "--major: the cooldown still applies: the newest major past it is chosen" {
  zed_pin '1.2.0' 'v1.2.0:400' 'v2.0.0:60' 'v3.1.0:5'
  run bash scripts/release/update-pins.sh --discover-only --major ZED
  [ "${status}" -eq 0 ]
  [[ "$(row 'ZED')" == *'v2.0.0'*'stale'* ]] || false
}

@test "--major: a major only inside the cooldown stays reported as cooldown" {
  zed_pin '1.2.0' 'v1.2.0:400' 'v2.0.0:5'
  run bash scripts/release/update-pins.sh --discover-only --major ZED
  [ "${status}" -eq 0 ]
  [[ "$(row 'ZED')" == *'v2.0.0'*'cooldown'* ]] || false
}

@test "--major --apply: the named pin is verified and written" {
  checkout_fixture
  zed_pin '1.2.0' 'v1.2.0:400' 'v2.0.0:30'
  fixture 'https://api.github.com/repos/acme/zed/releases/tags/1.2.0' '{"assets": []}'
  fixture 'https://api.github.com/repos/acme/zed/releases/tags/v2.0.0' '{"assets": []}'
  verify --apply --major ZED
  grep -q "readonly ZED_VERSION='2.0.0'" scripts/ci/setup-zed.sh
  [[ "$(result 'ZED')" == *'pass'*'make setup-zed'* ]] || false
}

@test "--major: an unknown name stops the run, before anything is verified" {
  checkout_fixture
  verify --major NOPE
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'NOPE'*'not a pin'* ]] || false
  [[ "${output}" != *'verifying in'* ]] || false
}

@test "--major: a pin with no newer major stops the run, before anything is verified" {
  zed_pin '1.2.0' 'v1.2.0:400' 'v1.3.0:30'
  verify --major ZED
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'ZED'*'no newer major'* ]] || false
  [[ "${output}" != *'verifying in'* ]] || false
}

@test "--major: a held pin stops the run, and says why" {
  zed_pin '1.2.0' 'v1.2.0:400' 'v2.0.0:30'
  mkdir -p .standards/scripts/ci
  cp -p scripts/ci/setup-zed.sh .standards/scripts/ci/setup-zed.sh
  commit
  verify --major ZED
  [ "${status}" -ne 0 ]
  [[ "${output}" == *'ZED'*'held'* ]] || false
}

@test "GitHub Actions: a new runner image is written, with CI left to verify it" {
  printf 'jobs:\n  a:\n    runs-on: ubuntu-24.04\n' > .github/workflows/runner.yml
  fixture 'https://raw.githubusercontent.com/actions/runner-images/main/README.md' \
    $'| x | `ubuntu-24.04` |\n| y | `ubuntu-26.04` |\n'
  checkout_fixture
  commit
  verify --apply
  [[ "$(result 'ubuntu-24.04')" == *'verify-on-ci'* ]] || false
  grep -q 'runs-on: ubuntu-26.04' .github/workflows/runner.yml
}

@test "brew: a real install is reported; a hint in a log message is not" {
  printf '#!/usr/bin/env bash\nbrew install realtool\nlog "  For macOS: brew install hintone"\nlog %s\n' \
    "'For macOS: brew install hinttwo'" > scripts/ci/setup-brewy.sh
  commit
  pins
  [[ "${output}" == *'brew:realtool'* ]] || false
  [[ "${output}" != *'hintone'* ]] || false
  [[ "${output}" != *'hinttwo'* ]] || false
}

@test "make update-pins: MAJOR passes each name to --major" {
  run make -n -f "${STANDARDS}/templates/Makefile.canonical" update-pins MAJOR='GRYPE actions/checkout'
  [[ "${output}" == *"--major 'GRYPE' --major 'actions/checkout'"* ]] || false
}

# checkout_major AGE: actions/checkout has a v7.0.0 published AGE days ago.
checkout_major() {
  fixture 'https://api.github.com/repos/actions/checkout/releases?per_page=100' "$(jq -n \
    --arg old "$(iso 400)" --arg new "$(iso 30)" --arg major "$(iso "${1}")" '[
      {tag_name: "v4.2.2", draft: false, prerelease: false, published_at: $old},
      {tag_name: "v4.4.0", draft: false, prerelease: false, published_at: $new},
      {tag_name: "v7.0.0", draft: false, prerelease: false, published_at: $major}]')"
}

@test "GitHub Actions: a new major of an action is an ordinary update, with no --major" {
  checkout_major 30
  pins
  [[ "$(row 'actions/checkout')" == *'v7.0.0'*'stale'* ]] || false
}

@test "GitHub Actions: the cooldown still applies to an action's new major" {
  checkout_major 5
  pins
  [[ "$(row 'actions/checkout')" == *'v4.4.0'*'stale'* ]] || false
}

@test "GitHub Actions --apply: an action's new major is written after the local checks" {
  checkout_major 30
  fixture 'https://api.github.com/repos/actions/checkout/commits/v7.0.0' "{\"sha\":\"${SHA_CHECKOUT_NEW}\"}"
  verify --apply
  grep -q "actions/checkout@${SHA_CHECKOUT_NEW}  # v7.0.0" .github/workflows/ci.yml
}

# fake_run_sh: a run.sh naming the image a pin needs: "shared", or "zed-2" once the ZED pin is applied.
# Fetches record themselves in FETCHES, and each pin's check records itself there too.
fake_run_sh() {
  mkdir -p scripts/dev
  cat > scripts/dev/run.sh <<'RUN'
#!/usr/bin/env bash
image() {
  if grep -q "ZED_VERSION='2.1" scripts/ci/setup-zed.sh 2> /dev/null; then echo zed-2; else echo shared; fi
}
case "${1}" in
  --image-ref) image ;;
  --fetch-image)
    echo "fetch $(image)" >> "${FETCHES}"
    sleep 1
    [ ! -f "${FETCHES}.fail" ] ;;
esac
RUN
  export FETCHES="${BATS_TEST_TMPDIR}/fetches"
  perl -0pi -e 's/lint-workflows:\n\t\@true\n/lint-workflows:\n\t\@echo check >> "\$(FETCHES)"\n/' Makefile
  commit
}

@test "images: pins needing one image fetch it once, and every fetch ends before any check starts" {
  checkout_fixture
  fake_run_sh
  verify
  [ "$(grep -c '^fetch shared$' "${FETCHES}")" -eq 1 ]
  [ "$(sed -n 1p "${FETCHES}")" = 'fetch shared' ]
  grep -q '^check$' "${FETCHES}"
  [[ "${output}" == *'📥'*'1 image'* ]] || false
  [ "$(git worktree list | wc -l | tr -d ' ')" -eq 1 ]
}

@test "images: distinct images are each fetched once, before any check" {
  checkout_fixture
  zed_pin '2.0.0' 'v2.0.0:400' 'v2.1.0:30'
  fixture 'https://api.github.com/repos/acme/zed/releases/tags/2.0.0' '{"assets": []}'
  fixture 'https://api.github.com/repos/acme/zed/releases/tags/v2.1.0' '{"assets": []}'
  fake_run_sh
  verify
  [ "$(grep -c '^fetch shared$' "${FETCHES}")" -eq 1 ]
  [ "$(grep -c '^fetch zed-2$' "${FETCHES}")" -eq 1 ]
  [ -z "$(sed -n '1,2p' "${FETCHES}" | grep check)" ]
}

@test "images: a failed fetch is reported, and the checks still run" {
  checkout_fixture
  fake_run_sh
  touch "${FETCHES}.fail"
  verify
  [[ "${output}" == *'❌'*'shared'* ]] || false
  grep -q '^check$' "${FETCHES}"
}

@test "images: a repository without run.sh fetches nothing, and verifies as before" {
  checkout_fixture
  verify
  [[ "${output}" != *'📥'* ]] || false
  [[ "$(result 'actions/checkout')" == *'pass'* ]] || false
}
