#!/usr/bin/env bats
# Regression guard for the flaky "Lint GitHub Actions" step in
# .github/workflows/ci.yml.
#
# Pins issue #894: ci.yml intermittently fails (~14% of runs) because the pinned
# rhysd/actionlint binary is fetched from GitHub Releases — which redirects to
# objects.githubusercontent.com — with a bare `curl` that aborts on the first
# transient network/5xx blip. This is the same failure mode fixed for
# pr-review-mention-tests.yml under #739. AGENTS.md requires CI to be reliable;
# the one unavoidable network fetch must therefore retry on transient errors.
# These tests assert every download in ci.yml carries bounded curl retries, so a
# future edit can't silently reintroduce a bare download.

load 'helpers/setup'

@test "install: the ci workflow exists" {
  [ -f "$TT_WORKFLOW" ]
}

@test "install: every curl download in ci.yml uses bounded retries" {
  [ -f "$TT_WORKFLOW" ]

  # Parse the workflow joining backslash-continued lines so that a curl command
  # split across multiple lines is treated as a single logical invocation.
  # This avoids false failures when flags appear on continuation lines, and
  # avoids false passes when a bare `curl` is split from its flags.
  local curls=()
  local current=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    if [[ "$line" == *'\\' ]]; then
      current+="${line%\\} "
    else
      current+="$line"
      if [[ "$current" == *curl* ]] && ! [[ "$current" =~ ^[[:space:]]*'#' ]]; then
        curls+=("$current")
      fi
      current=""
    fi
  done < "$TT_WORKFLOW"

  # At least one curl invocation must be present so the test remains meaningful.
  [ "${#curls[@]}" -ge 1 ]
  for cmd in "${curls[@]}"; do
    # A finite retry budget (not unbounded) so a truly-down mirror still fails fast.
    [[ "$cmd" == *"--retry "* ]]
    # Retry on connection refused, which curl otherwise treats as non-transient.
    [[ "$cmd" == *"--retry-connrefused"* ]]
    # Retry on transient HTTP 5xx too, not just connection-level errors.
    [[ "$cmd" == *"--retry-all-errors"* ]]
  done
}
