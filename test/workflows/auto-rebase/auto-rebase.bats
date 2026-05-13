#!/usr/bin/env bats
# Unit tests for scripts/auto-rebase.sh
#
# Tests the two public functions:
#   handle_permissions_block  — posts a "blocked" comment idempotently
#   handle_conflict           — posts a SHA-keyed sentinel comment and fires
#                               repository_dispatch idempotently

load 'helpers/setup'

setup() {
  ar_make_tmpdir
  export REPO="petry-projects/test-repo"
  export GH_TOKEN="fake-token"
}

teardown() {
  ar_cleanup_tmpdir
}

# ─── handle_permissions_block ───────────────────────────────────────────────

@test "handle_permissions_block: posts blocked comment when no sentinel exists" {
  ar_install_gh_stub "0"   # gh pr view → count=0 (sentinel absent)
  source "$AR_SCRIPT"

  run handle_permissions_block "42" "main"

  [ "$status" -eq 0 ]
  ar_assert_gh_called "pr comment"
  ar_assert_gh_called "auto-rebase-blocked"
}

@test "handle_permissions_block: skips comment when sentinel already present" {
  ar_install_gh_stub "1"   # gh pr view → count=1 (sentinel present)
  source "$AR_SCRIPT"

  run handle_permissions_block "42" "main"

  [ "$status" -eq 0 ]
  ar_assert_gh_not_called "pr comment"
  [[ "$output" == *"already posted"* ]]
}

@test "handle_permissions_block: comment body contains git rebase instructions" {
  ar_install_gh_stub "0"
  source "$AR_SCRIPT"

  handle_permissions_block "7" "main"

  ar_assert_gh_called "git rebase origin"
}

# ─── handle_conflict ────────────────────────────────────────────────────────

# Helper: set up multi-response stub for handle_conflict.
# The stub returns pre-jq-processed values (as real gh would after applying --jq).
# Calls in order:
#   1. gh api repos/.../branches/BASE --jq .commit.sha  → raw SHA string
#   2. gh pr view ... --jq "[...] | length"             → sentinel count
#   3. gh pr comment (if not skipped)                   → (empty)
#   4. gh api .../dispatches                            → (empty)
_setup_conflict_stub() {
  local sha="$1"           # raw SHA string (as gh --jq '.commit.sha' would return)
  local sentinel_count="$2"  # "0" or "1"
  AR_GH_RESPONSES=("$sha" "$sentinel_count" "" "")
  ar_install_multi_gh_stub
}

@test "handle_conflict: posts comment and dispatches when sentinel absent" {
  _setup_conflict_stub "abc12345def67890" "0"
  source "$AR_SCRIPT"

  run handle_conflict "99" "feat/my-branch" "main"

  [ "$status" -eq 0 ]
  ar_assert_gh_called "pr comment"
  ar_assert_gh_called "dispatches"
  ar_assert_gh_called "claude-rebase"
}

@test "handle_conflict: sentinel contains first-8 chars of base SHA" {
  _setup_conflict_stub "deadbeef12345678" "0"
  source "$AR_SCRIPT"

  handle_conflict "5" "feat/x" "main"

  # The sentinel <!-- auto-rebase-conflict:deadbeef --> must appear in the comment call
  ar_assert_gh_called "auto-rebase-conflict:deadbeef"
}

@test "handle_conflict: skips when SHA-keyed sentinel already present" {
  _setup_conflict_stub "abc12345def67890" "1"
  source "$AR_SCRIPT"

  run handle_conflict "99" "feat/my-branch" "main"

  [ "$status" -eq 0 ]
  ar_assert_gh_not_called "pr comment"
  ar_assert_gh_not_called "dispatches"
  [[ "$output" == *"already dispatched"* ]]
}

@test "handle_conflict: dispatches with pr_number in payload" {
  _setup_conflict_stub "abc12345def67890" "0"
  source "$AR_SCRIPT"

  handle_conflict "123" "feat/branch" "main"

  ar_assert_gh_called "pr_number"
  ar_assert_gh_called "123"
}

@test "handle_conflict: dispatches with head_ref in payload" {
  _setup_conflict_stub "abc12345def67890" "0"
  source "$AR_SCRIPT"

  handle_conflict "5" "feat/my-feature" "main"

  ar_assert_gh_called "head_ref"
  ar_assert_gh_called "feat/my-feature"
}

@test "handle_conflict: dispatches with base_branch in payload" {
  _setup_conflict_stub "abc12345def67890" "0"
  source "$AR_SCRIPT"

  handle_conflict "5" "feat/x" "develop"

  ar_assert_gh_called "base_branch"
  ar_assert_gh_called "develop"
}

@test "handle_conflict: different SHA → different sentinel, allows new dispatch" {
  # Simulate two sequential runs: different base SHA each time → both dispatch
  _setup_conflict_stub "aaaaaaa1bbbbbbbb" "0"
  source "$AR_SCRIPT"
  handle_conflict "7" "feat/x" "main"
  local first_count
  first_count=$(ar_gh_call_count "dispatches")

  # Second call with a different SHA — reset tmp dir so logs are clean
  ar_cleanup_tmpdir
  ar_make_tmpdir
  _setup_conflict_stub "bbbbbbb1cccccccc" "0"
  handle_conflict "7" "feat/x" "main"
  local second_count
  second_count=$(ar_gh_call_count "dispatches")

  [ "$first_count" -eq 1 ]
  [ "$second_count" -eq 1 ]
}

@test "handle_conflict: comment body contains manual fallback instructions" {
  _setup_conflict_stub "abc12345def67890" "0"
  source "$AR_SCRIPT"

  handle_conflict "5" "feat/x" "main"

  ar_assert_gh_called "git rebase"
  ar_assert_gh_called "force-with-lease"
}

@test "handle_conflict: event_type is claude-rebase" {
  _setup_conflict_stub "abc12345def67890" "0"
  source "$AR_SCRIPT"

  handle_conflict "5" "feat/x" "main"

  ar_assert_gh_called "event_type"
  ar_assert_gh_called "claude-rebase"
}
