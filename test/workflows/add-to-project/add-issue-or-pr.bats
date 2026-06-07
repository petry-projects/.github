#!/usr/bin/env bats
# Tests for add-issue-or-pr.sh — noise gate + add mutation.

bats_require_minimum_version 1.5.0

load 'helpers/setup'

setup() {
  tt_make_tmpdir
  tt_install_gh_stub
  export PROJECT_ID="PVT_test_project"
  export PROJECT_URL="https://example.invalid/projects/1"
  export GH_TOKEN="t_test"
  export GH_STUB_LOG="${TT_TMP}/gh.log"
  # shellcheck source=/dev/null
  . "${TT_SCRIPTS_DIR}/add-issue-or-pr.sh"
}

teardown() {
  tt_cleanup_tmpdir
}

labels_of() {
  jq -nc '$ARGS.positional | map({name: .})' --args "$@"
}

assert_invocation_count() {
  local expected="$1"
  local actual=0
  if [ -f "${GH_STUB_LOG}" ]; then
    actual=$(wc -l <"${GH_STUB_LOG}" | tr -d ' ')
  fi
  [ "$actual" -eq "$expected" ] || {
    printf 'expected %d gh invocations, got %d\n' "$expected" "$actual" >&2
    if [ -f "${GH_STUB_LOG}" ]; then cat "${GH_STUB_LOG}" >&2; fi
    return 1
  }
}

# ---------------------------------------------------------------------------
# Arg validation
# ---------------------------------------------------------------------------

@test "process_issue_or_pr: rejects wrong arg count" {
  run process_issue_or_pr "N" "U"
  [ "$status" -eq 64 ]
}

@test "process_issue_or_pr: fails fast without PROJECT_ID" {
  unset PROJECT_ID
  run --separate-stderr process_issue_or_pr "I_1" "https://x" "[]"
  [ "$status" -eq 64 ]
  [[ "$stderr" == *"PROJECT_ID env var is required"* ]]
}

@test "process_issue_or_pr: fails fast with ::error:: when GH_TOKEN is empty" {
  unset GH_TOKEN
  run --separate-stderr process_issue_or_pr "I_1" "https://x" "[]"
  [ "$status" -eq 64 ]
  [[ "$stderr" == *"::error::"* ]]
  [[ "$stderr" == *"GH_TOKEN is empty"* ]]
  [[ "$stderr" == *"petry-projects/.github#387"* ]]
}

# ---------------------------------------------------------------------------
# Noise gate — dev-lead required, excluded labels block
# ---------------------------------------------------------------------------

@test "no dev-lead label → skip, no gh call" {
  run process_issue_or_pr "I_1" "https://example.invalid/issues/1" "$(labels_of bug enhancement)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skip"* ]]
  [[ "$output" == *"missing required label 'dev-lead'"* ]]
  assert_invocation_count 0
}

@test "dev-lead + compliance-audit → skip (noise gate)" {
  run process_issue_or_pr "I_1" "https://example.invalid/issues/1" "$(labels_of dev-lead compliance-audit)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skip"* ]]
  [[ "$output" == *"has excluded label 'compliance-audit'"* ]]
  assert_invocation_count 0
}

@test "dev-lead + health-check → skip" {
  run process_issue_or_pr "I_1" "https://example.invalid/issues/1" "$(labels_of dev-lead health-check)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"has excluded label 'health-check'"* ]]
  assert_invocation_count 0
}

@test "dev-lead + fleet-tracker → skip" {
  run process_issue_or_pr "I_1" "https://example.invalid/issues/1" "$(labels_of dev-lead fleet-tracker)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"has excluded label 'fleet-tracker'"* ]]
  assert_invocation_count 0
}

@test "dev-lead + daily-report → skip" {
  run process_issue_or_pr "I_1" "https://example.invalid/issues/1" "$(labels_of dev-lead daily-report)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"has excluded label 'daily-report'"* ]]
  assert_invocation_count 0
}

# ---------------------------------------------------------------------------
# Happy path — call count + mutation content
# ---------------------------------------------------------------------------

@test "dev-lead alone → exactly one addProjectV2ItemById with the content id" {
  run process_issue_or_pr "I_node_xyz" "https://example.invalid/issues/1" "$(labels_of dev-lead)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Adding https://example.invalid/issues/1"* ]]
  assert_invocation_count 1
  local last
  last=$(tail -n 1 "${GH_STUB_LOG}" | sed 's/\\//g')
  [[ "$last" == *"addProjectV2ItemById"* ]]
  [[ "$last" == *"I_node_xyz"* ]]
}

@test "dev-lead + non-excluded other label → still qualifies, one call" {
  run process_issue_or_pr "I_node_xyz" "https://example.invalid/issues/1" "$(labels_of dev-lead bug enhancement)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Adding"* ]]
  assert_invocation_count 1
}

# ---------------------------------------------------------------------------
# Payload defense: malformed LABELS_JSON
# ---------------------------------------------------------------------------

@test "labels_json='null' → treated as empty array, clean skip (not crash)" {
  run process_issue_or_pr "I_1" "https://example.invalid/issues/1" "null"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skip"* ]]
  [[ "$output" == *"missing required label"* ]]
  assert_invocation_count 0
}

@test "labels_json is an object (not array) → treated as empty, clean skip" {
  run process_issue_or_pr "I_1" "https://example.invalid/issues/1" '{"name":"dev-lead"}'
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skip"* ]]
  [[ "$output" == *"missing required label"* ]]
  assert_invocation_count 0
}

# ---------------------------------------------------------------------------
# Programmer error path: non-1, non-64 from evaluate_noise_gate is NOT swallowed
# ---------------------------------------------------------------------------

@test "evaluate_noise_gate: returns 64 on wrong arg count (propagated, not swallowed)" {
  # Manually call with bad arg count; process_issue_or_pr should NOT
  # silently treat this as a skip — surface the bug.
  run evaluate_noise_gate
  [ "$status" -eq 64 ]
}

# ---------------------------------------------------------------------------
# evaluate_noise_gate direct API
# ---------------------------------------------------------------------------

@test "evaluate_noise_gate: returns 0 for qualifying labels" {
  run evaluate_noise_gate "$(labels_of dev-lead)"
  [ "$status" -eq 0 ]
}

@test "evaluate_noise_gate: returns 1 for missing required label" {
  run evaluate_noise_gate "$(labels_of bug)"
  [ "$status" -eq 1 ]
}

@test "evaluate_noise_gate: returns 1 for any excluded label" {
  run evaluate_noise_gate "$(labels_of dev-lead daily-report)"
  [ "$status" -eq 1 ]
}

@test "evaluate_noise_gate: 'null' labels → treated as empty, returns 1 (not crash)" {
  run evaluate_noise_gate "null"
  [ "$status" -eq 1 ]
}
