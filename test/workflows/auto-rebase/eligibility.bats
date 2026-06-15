#!/usr/bin/env bats
# Tests for .github/scripts/auto-rebase/lib/eligibility.sh
#
# Pins issue #465: auto-rebase must update a behind PR only when it is
# non-draft AND (has a current APPROVED review OR carries the ready label),
# with the predicate selectable via a tunable mode.

load 'helpers/setup'

setup() {
  # shellcheck source=/dev/null
  . "${TT_SCRIPTS_DIR}/lib/eligibility.sh"
}

# ── auto_rebase_has_current_approval ─────────────────────────────────────────

@test "has_current_approval: single APPROVED review counts as approved" {
  run auto_rebase_has_current_approval <<'JSON'
[{"user":{"login":"alice"},"state":"APPROVED","submitted_at":"2026-06-01T00:00:00Z"}]
JSON
  [ "$status" -eq 0 ]
}

@test "has_current_approval: no reviews is not approved" {
  run auto_rebase_has_current_approval <<'JSON'
[]
JSON
  [ "$status" -ne 0 ]
}

@test "has_current_approval: only COMMENTED reviews are not approved" {
  run auto_rebase_has_current_approval <<'JSON'
[{"user":{"login":"alice"},"state":"COMMENTED","submitted_at":"2026-06-01T00:00:00Z"}]
JSON
  [ "$status" -ne 0 ]
}

@test "has_current_approval: reviewer who approved then requested changes is not approved" {
  run auto_rebase_has_current_approval <<'JSON'
[
  {"user":{"login":"alice"},"state":"APPROVED","submitted_at":"2026-06-01T00:00:00Z"},
  {"user":{"login":"alice"},"state":"CHANGES_REQUESTED","submitted_at":"2026-06-02T00:00:00Z"}
]
JSON
  [ "$status" -ne 0 ]
}

@test "has_current_approval: reviewer who requested changes then approved is approved" {
  run auto_rebase_has_current_approval <<'JSON'
[
  {"user":{"login":"alice"},"state":"CHANGES_REQUESTED","submitted_at":"2026-06-01T00:00:00Z"},
  {"user":{"login":"alice"},"state":"APPROVED","submitted_at":"2026-06-02T00:00:00Z"}
]
JSON
  [ "$status" -eq 0 ]
}

@test "has_current_approval: a later COMMENTED review does not cancel an approval" {
  run auto_rebase_has_current_approval <<'JSON'
[
  {"user":{"login":"alice"},"state":"APPROVED","submitted_at":"2026-06-01T00:00:00Z"},
  {"user":{"login":"alice"},"state":"COMMENTED","submitted_at":"2026-06-03T00:00:00Z"}
]
JSON
  [ "$status" -eq 0 ]
}

@test "has_current_approval: a dismissed approval is not approved" {
  run auto_rebase_has_current_approval <<'JSON'
[
  {"user":{"login":"alice"},"state":"APPROVED","submitted_at":"2026-06-01T00:00:00Z"},
  {"user":{"login":"alice"},"state":"DISMISSED","submitted_at":"2026-06-02T00:00:00Z"}
]
JSON
  [ "$status" -ne 0 ]
}

@test "has_current_approval: one approver among several reviewers counts" {
  run auto_rebase_has_current_approval <<'JSON'
[
  {"user":{"login":"alice"},"state":"CHANGES_REQUESTED","submitted_at":"2026-06-01T00:00:00Z"},
  {"user":{"login":"bob"},"state":"APPROVED","submitted_at":"2026-06-02T00:00:00Z"}
]
JSON
  [ "$status" -eq 0 ]
}

# ── auto_rebase_has_ready_label ──────────────────────────────────────────────

@test "has_ready_label: label present" {
  run auto_rebase_has_ready_label "auto-rebase:ready" <<'JSON'
[{"name":"enhancement"},{"name":"auto-rebase:ready"}]
JSON
  [ "$status" -eq 0 ]
}

@test "has_ready_label: label absent" {
  run auto_rebase_has_ready_label "auto-rebase:ready" <<'JSON'
[{"name":"enhancement"}]
JSON
  [ "$status" -ne 0 ]
}

@test "has_ready_label: empty labels array" {
  run auto_rebase_has_ready_label "auto-rebase:ready" <<'JSON'
[]
JSON
  [ "$status" -ne 0 ]
}

# ── auto_rebase_pr_eligible ──────────────────────────────────────────────────

@test "pr_eligible review-ready: non-draft + approved is eligible" {
  run auto_rebase_pr_eligible review-ready false true false
  [ "$status" -eq 0 ]
}

@test "pr_eligible review-ready: non-draft + ready label is eligible" {
  run auto_rebase_pr_eligible review-ready false false true
  [ "$status" -eq 0 ]
}

@test "pr_eligible review-ready: non-draft but neither approved nor labelled is ineligible" {
  run auto_rebase_pr_eligible review-ready false false false
  [ "$status" -eq 1 ]
}

@test "pr_eligible review-ready: draft is ineligible even when approved" {
  run auto_rebase_pr_eligible review-ready true true true
  [ "$status" -eq 1 ]
}

@test "pr_eligible all: always eligible (legacy fan-out escape hatch)" {
  run auto_rebase_pr_eligible all false false false
  [ "$status" -eq 0 ]
}

@test "pr_eligible all: eligible even for drafts (preserves prior behavior)" {
  run auto_rebase_pr_eligible all true false false
  [ "$status" -eq 0 ]
}

@test "pr_eligible: unknown mode errors out (exit 2)" {
  run auto_rebase_pr_eligible bogus-mode false true false
  [ "$status" -eq 2 ]
}
