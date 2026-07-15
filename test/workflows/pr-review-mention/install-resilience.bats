#!/usr/bin/env bats
# Regression guard for the flaky "Install bats, shellcheck, jq, and yq" step in
# .github/workflows/pr-review-mention-tests.yml.
#
# Pins issue #739: the suite intermittently fails (~14% of runs) because the
# pinned mikefarah/yq is fetched from GitHub Releases — which redirects to
# objects.githubusercontent.com — with a bare `curl` that aborts on the first
# transient network/5xx blip. AGENTS.md requires unit tests be deterministic;
# the one unavoidable network fetch must therefore retry with backoff. These
# tests assert every GitHub-Releases download in the workflow carries bounded
# curl retries, so a future edit can't silently reintroduce a bare download.

load 'helpers/setup'

TESTS_WORKFLOW="${TT_REPO_ROOT}/.github/workflows/pr-review-mention-tests.yml"

@test "install: the tests workflow exists" {
  [ -f "$TESTS_WORKFLOW" ]
}

@test "install: every curl download uses bounded retries with backoff" {
  [ -f "$TESTS_WORKFLOW" ]
  mapfile -t curls < <(grep -E '^[[:space:]]*curl ' "$TESTS_WORKFLOW")
  # yq binary, checksums, checksums_hashes_order — three fetches, all resilient.
  [ "${#curls[@]}" -ge 3 ]
  for line in "${curls[@]}"; do
    # A finite retry budget (not unbounded) so a truly-down mirror still fails fast.
    [[ "$line" == *"--retry "* ]]
    # Retry on connection refused, which curl otherwise treats as non-transient.
    [[ "$line" == *"--retry-connrefused"* ]]
    # Retry on transient HTTP 5xx too, not just connection-level errors.
    [[ "$line" == *"--retry-all-errors"* ]]
  done
}
