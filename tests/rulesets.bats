#!/usr/bin/env bats
# tests/rulesets.bats
# Branch protection for main, kept as code in .github/rulesets/: nobody deletes or rewrites main, and only
# a repository admin pushes to it without a pull request.

setup() {
  RULESETS="${BATS_TEST_DIRNAME}/../.github/rulesets"
}

@test "main history: no deletion and no force-push, with no one exempt" {
  local -r f="${RULESETS}/main-history.json"
  jq -e '.target == "branch" and .enforcement == "active"' "${f}"
  jq -e '.conditions.ref_name.include == ["~DEFAULT_BRANCH"]' "${f}"
  jq -e '(.bypass_actors // []) == []' "${f}"
  jq -e '[.rules[].type] | sort == ["deletion", "non_fast_forward"]' "${f}"
}

@test "main pull requests: everyone but a repository admin goes through a reviewed pull request" {
  local -r f="${RULESETS}/main-pull-requests.json"
  jq -e '.target == "branch" and .enforcement == "active"' "${f}"
  jq -e '.conditions.ref_name.include == ["~DEFAULT_BRANCH"]' "${f}"
  jq -e '.bypass_actors == [{"actor_id": 5, "actor_type": "RepositoryRole", "bypass_mode": "always"}]' "${f}"
  jq -e '[.rules[].type] == ["pull_request"]' "${f}"
  jq -e '.rules[0].parameters.required_approving_review_count >= 1' "${f}"
}
