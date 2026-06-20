#!/usr/bin/env bats
# Tests for .github/scripts/pr-review-mention/resolve-pr-url.sh
#
# Pins the fix for issue #500 (Bug 1): the dispatcher must resolve the PR URL
# by event name (not assume issue_comment) and must guard against an empty
# value before calling `gh api`, so a `review_requested` event reliably
# dispatches and `handle-mention` never fails on an empty URL.

load 'helpers/setup'

setup() {
  tt_make_tmpdir
  tt_install_gh_stub
  RESOLVER="${TT_SCRIPTS_DIR}/resolve-pr-url.sh"
  GH_STUB_LOG="${TT_TMP}/gh.log"
  export GH_STUB_LOG
}

teardown() {
  tt_cleanup_tmpdir
}

@test "pull_request (review_requested) resolves pull_request.html_url without gh" {
  run env EVENT_NAME="pull_request" \
    PR_HTML_URL="https://github.com/owner/repo/pull/399" \
    ISSUE_PR_API_URL="" \
    "$RESOLVER"
  [ "$status" -eq 0 ]
  [ "$output" = "https://github.com/owner/repo/pull/399" ]
  # The review_requested path must NOT shell out to gh api.
  [ ! -s "$GH_STUB_LOG" ]
}

@test "pull_request_review_comment resolves pull_request.html_url without gh" {
  run env EVENT_NAME="pull_request_review_comment" \
    PR_HTML_URL="https://github.com/owner/repo/pull/42" \
    ISSUE_PR_API_URL="" \
    "$RESOLVER"
  [ "$status" -eq 0 ]
  [ "$output" = "https://github.com/owner/repo/pull/42" ]
  [ ! -s "$GH_STUB_LOG" ]
}

@test "issue_comment resolves html_url via gh api on the issue pull_request url" {
  export GH_STUB_STDOUT="https://github.com/owner/repo/pull/7"
  run env EVENT_NAME="issue_comment" \
    PR_HTML_URL="" \
    ISSUE_PR_API_URL="https://api.github.com/repos/owner/repo/pulls/7" \
    GH_STUB_STDOUT="$GH_STUB_STDOUT" \
    GH_STUB_LOG="$GH_STUB_LOG" \
    "$RESOLVER"
  [ "$status" -eq 0 ]
  [ "$output" = "https://github.com/owner/repo/pull/7" ]
  # gh must have been called against the issue's pull_request API url.
  grep -q "api .*api.github.com/repos/owner/repo/pulls/7" "$GH_STUB_LOG"
}

@test "issue_comment with empty pull_request url fails and never calls gh api" {
  run env EVENT_NAME="issue_comment" \
    PR_HTML_URL="" \
    ISSUE_PR_API_URL="" \
    GH_STUB_LOG="$GH_STUB_LOG" \
    "$RESOLVER"
  [ "$status" -ne 0 ]
  # The guard must trip before any gh invocation (no `gh api ""`).
  [ ! -s "$GH_STUB_LOG" ]
}

@test "pull_request with empty html_url fails fast with a guard message" {
  run env EVENT_NAME="pull_request" \
    PR_HTML_URL="" \
    ISSUE_PR_API_URL="" \
    "$RESOLVER"
  [ "$status" -ne 0 ]
  [[ "$output" == *"resolve-pr-url"* ]]
}

@test "unsupported event name fails fast" {
  run env EVENT_NAME="push" \
    PR_HTML_URL="" \
    ISSUE_PR_API_URL="" \
    "$RESOLVER"
  [ "$status" -ne 0 ]
}
