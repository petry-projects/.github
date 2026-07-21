#!/usr/bin/env bats
# Tests for pr_auto_review_blocking_thread_count in
# .github/scripts/pr-auto-review/lib/ready-check.sh
#
# Pins issue #806: dev-lead's fix-review cycle addresses an advisory finding in a
# follow-up commit but frequently never marks the corresponding review thread
# resolved, so the PR stalls REVIEW_REQUIRED on the unresolved-threads gate even
# though the code is fixed and CI is green.
#
# Consumer-side, defense-in-depth: a review thread that is unresolved but
# OUTDATED (its anchored diff position no longer exists at HEAD — line changed /
# file moved) no longer blocks auto-dispatch. GitHub sets reviewThread.isOutdated
# for exactly this case, so a fixed-but-unresolved finding stops blocking without
# the producer having to resolve the thread.
#
# The function reads the `gh api graphql` reviewThreads response on stdin (each
# node exposing .isResolved and .isOutdated) and prints the count of *blocking*
# threads — unresolved AND not outdated.

load 'helpers/setup'

setup() {
  # shellcheck source=/dev/null
  . "${TT_SCRIPTS_DIR}/lib/ready-check.sh"
}

# Build a GraphQL-shaped response from a raw nodes array, matching the shape the
# reusable workflow passes: .data.repository.pullRequest.reviewThreads.nodes
resp() {
  printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":%s}}}}}' "$1"
}

# ── empty / trivial ──────────────────────────────────────────────────────────

@test "blocking count: no threads → 0" {
  run pr_auto_review_blocking_thread_count <<<"$(resp '[]')"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "blocking count: all resolved → 0" {
  run pr_auto_review_blocking_thread_count <<<"$(resp '[{"isResolved":true,"isOutdated":false},{"isResolved":true,"isOutdated":true}]')"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

# ── the blocking case: still applies to HEAD ─────────────────────────────────

@test "blocking count: unresolved and NOT outdated → 1 (still blocks)" {
  run pr_auto_review_blocking_thread_count <<<"$(resp '[{"isResolved":false,"isOutdated":false}]')"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

# ── the #806 fix: addressed-in-code makes the thread outdated ─────────────────

@test "blocking count: unresolved but OUTDATED → 0 (fixed-in-code, non-blocking)" {
  run pr_auto_review_blocking_thread_count <<<"$(resp '[{"isResolved":false,"isOutdated":true}]')"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "blocking count: the #805 scenario — three fixed advisory threads all outdated → 0" {
  # Copilot dep-check + two Gemini temp-file findings, each fixed in a follow-up
  # commit that changed the anchored line, so all three threads are outdated.
  run pr_auto_review_blocking_thread_count <<<"$(resp '[
    {"isResolved":false,"isOutdated":true},
    {"isResolved":false,"isOutdated":true},
    {"isResolved":false,"isOutdated":true}
  ]')"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

# ── mixed sets: only unresolved-and-current threads count ─────────────────────

@test "blocking count: mixed set counts only unresolved-and-current threads" {
  # resolved(current), resolved(outdated), unresolved+outdated, unresolved+current
  run pr_auto_review_blocking_thread_count <<<"$(resp '[
    {"isResolved":true,"isOutdated":false},
    {"isResolved":true,"isOutdated":true},
    {"isResolved":false,"isOutdated":true},
    {"isResolved":false,"isOutdated":false}
  ]')"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "blocking count: several unresolved-and-current threads → their count" {
  run pr_auto_review_blocking_thread_count <<<"$(resp '[
    {"isResolved":false,"isOutdated":false},
    {"isResolved":false,"isOutdated":false},
    {"isResolved":false,"isOutdated":true}
  ]')"
  [ "$status" -eq 0 ]
  [ "$output" = "2" ]
}

# ── fail-safe: missing / null isOutdated on an unresolved thread still blocks ─

@test "blocking count: unresolved thread with null isOutdated → 1 (fail safe: still blocks)" {
  run pr_auto_review_blocking_thread_count <<<"$(resp '[{"isResolved":false,"isOutdated":null}]')"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

@test "blocking count: unresolved thread with absent isOutdated → 1 (fail safe: still blocks)" {
  run pr_auto_review_blocking_thread_count <<<"$(resp '[{"isResolved":false}]')"
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

# ── robustness: error / malformed bodies default to 0 ────────────────────────

@test "blocking count: GraphQL error body (no data) → 0" {
  run pr_auto_review_blocking_thread_count <<<'{"errors":[{"message":"Could not resolve to a Repository"}]}'
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}

@test "blocking count: null nodes → 0" {
  run pr_auto_review_blocking_thread_count <<<"$(resp 'null')"
  [ "$status" -eq 0 ]
  [ "$output" = "0" ]
}
