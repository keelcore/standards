#!/usr/bin/env bats
# tests/wait-ci.bats
# scripts/release/wait-for-ci.sh: waits for the GitHub Actions runs on a commit to finish, with
# progress, then fails if any is red. A tag's workflow runs it first, so a red commit is never published.

setup() {
  REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/.." && pwd)"
  SCRIPT="${REPO_ROOT}/scripts/release/wait-for-ci.sh"
  T="${BATS_TEST_TMPDIR}"
  export GITHUB_REPOSITORY='acme/widget' CI_WAIT_SECONDS=0 T
  unset GITHUB_RUN_ID GITHUB_REF_TYPE GITHUB_REF_NAME
  mkdir -p "${T}/bin"
  : > "${T}/calls"
  # gh answers with answers/1, answers/2, ... in turn, then repeats the last; an answer of
  # "fail" exits 1.
  mkdir -p "${T}/answers"
  cat > "${T}/bin/gh" <<'GH'
#!/usr/bin/env bash
echo "gh $*" >> "${T}/calls"
n="$(wc -l < "${T}/calls" | tr -d ' ')"
[ -f "${T}/answers/${n}" ] || n="$(ls "${T}/answers" | sort -n | tail -1)"
[ "$(cat "${T}/answers/${n}")" != 'fail' ] || exit 1
cat "${T}/answers/${n}"
GH
  chmod +x "${T}/bin/gh"
  PATH="${T}/bin:${PATH}"
}

# run_json ID NAME STATUS CONCLUSION [HEAD_BRANCH]
run_json() {
  printf '{"id":%s,"name":"%s","status":"%s","conclusion":%s,"head_branch":"%s"}' \
    "${1}" "${2}" "${3}" "${4}" "${5:-main}"
}

# answer N RUN...: the Nth reply lists these runs.
answer() {
  local -r n="${1}"
  shift
  local IFS=','
  printf '{"workflow_runs":[%s]}\n' "$*" > "${T}/answers/${n}"
}

calls() {
  wc -l < "${T}/calls" | tr -d ' '
}

@test "waits, with progress, until every run has finished, then passes" {
  answer 1 "$(run_json 1 CI in_progress null)" "$(run_json 2 CodeQL queued null)"
  answer 2 "$(run_json 1 CI completed '"success"')" "$(run_json 2 CodeQL in_progress null)"
  answer 3 "$(run_json 1 CI completed '"success"')" "$(run_json 2 CodeQL completed '"success"')"
  run bash "${SCRIPT}" abc123
  [ "${status}" -eq 0 ]
  [ "$(calls)" -eq 3 ]
  [[ "${output}" == *'⏳'*'0 of 2 finished'*'CI'*'CodeQL'* ]]
  [[ "${output}" == *'⏳'*'1 of 2 finished'*'CodeQL'* ]]
  [[ "${output}" == *'✅'*'abc123'* ]]
  grep -qF 'repos/acme/widget/actions/runs?head_sha=abc123' "${T}/calls"
}

@test "a red run fails only after every run has finished, naming it" {
  answer 1 "$(run_json 1 CI completed '"failure"')" "$(run_json 2 CodeQL in_progress null)"
  answer 2 "$(run_json 1 CI completed '"failure"')" "$(run_json 2 CodeQL completed '"success"')"
  run bash "${SCRIPT}" abc123
  [ "${status}" -eq 1 ]
  [ "$(calls)" -eq 2 ]
  [[ "${output}" == *'❌'*'CI'* ]]
  [[ "${output}" != *'❌'*'CodeQL'* ]]
}

@test "skipped and neutral runs pass; a cancelled run is red" {
  answer 1 "$(run_json 1 A completed '"skipped"')" "$(run_json 2 B completed '"neutral"')"
  run bash "${SCRIPT}" abc123
  [ "${status}" -eq 0 ]
  answer 1 "$(run_json 1 A completed '"cancelled"')"
  run bash "${SCRIPT}" abc123
  [ "${status}" -eq 1 ]
}

@test "a run that registers a moment after the push is waited for" {
  answer 1
  answer 2 "$(run_json 1 CI completed '"success"')"
  run bash "${SCRIPT}" abc123
  [ "${status}" -eq 0 ]
}

@test "a commit that never gets a run fails" {
  answer 1
  run bash "${SCRIPT}" abc123
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'no CI results'* ]]
}

@test "a brief read failure is retried; persistent failure fails" {
  printf 'fail' > "${T}/answers/1"
  answer 2 "$(run_json 1 CI completed '"success"')"
  run bash "${SCRIPT}" abc123
  [ "${status}" -eq 0 ]
  rm "${T}/answers/2"
  : > "${T}/calls"
  run bash "${SCRIPT}" abc123
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'could not read CI results'* ]]
}

@test "in a tag's workflow: its own run and the tag's other runs are not waited for" {
  export GITHUB_RUN_ID=9 GITHUB_REF_TYPE=tag GITHUB_REF_NAME=v1.2.3
  answer 1 "$(run_json 9 Publish in_progress null v1.2.3)" "$(run_json 10 Release in_progress null v1.2.3)" \
    "$(run_json 1 CI completed '"success"')"
  run bash "${SCRIPT}" abc123
  [ "${status}" -eq 0 ]
  [ "$(calls)" -eq 1 ]
}

@test "in a tag's workflow: a red run on the commit fails it" {
  export GITHUB_RUN_ID=9 GITHUB_REF_TYPE=tag GITHUB_REF_NAME=v1.2.3
  answer 1 "$(run_json 9 Publish in_progress null v1.2.3)" "$(run_json 1 CI completed '"failure"')"
  run bash "${SCRIPT}" abc123
  [ "${status}" -eq 1 ]
  [[ "${output}" == *'❌'*'CI'* ]]
}

@test "the commit defaults to HEAD, and the make target runs the script" {
  git -C "${T}" init --quiet
  git -C "${T}" -c user.name=t -c user.email=t@example.invalid commit --quiet --allow-empty -m x
  answer 1 "$(run_json 1 CI completed '"success"')"
  cd "${T}"
  run bash "${SCRIPT}"
  [ "${status}" -eq 0 ]
  grep -qF "head_sha=$(git rev-parse HEAD)" "${T}/calls"
  grep -qxF "$(printf '\tbash scripts/release/wait-for-ci.sh')" "${REPO_ROOT}/templates/Makefile.canonical"
}
