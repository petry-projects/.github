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

assert_no_gh_calls() {
  if [ -s "${GH_STUB_LOG}" ]; then
    printf 'expected no gh calls; got:\n%s\n' "$(cat "${GH_STUB_LOG}")" >&2
    return 1
  fi
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
  run process_issue_or_pr "I_1" "https://x" "[]"
  [ "$status" -eq 64 ]
}

# ---------------------------------------------------------------------------
# Noise gate — dev-lead required, excluded labels block
# ---------------------------------------------------------------------------

@test "no dev-lead label → skip, no gh call" {
  run process_issue_or_pr "I_1" "https://example.invalid/issues/1" "$(labels_of bug enhancement)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skip"* ]]
  [[ "$output" == *"missing required label 'dev-lead'"* ]]
  assert_no_gh_calls
}

@test "dev-lead + compliance-audit → skip (noise gate)" {
  run process_issue_or_pr "I_1" "https://example.invalid/issues/1" "$(labels_of dev-lead compliance-audit)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skip"* ]]
  [[ "$output" == *"has excluded label 'compliance-audit'"* ]]
  assert_no_gh_calls
}

@test "dev-lead + health-check → skip" {
  run process_issue_or_pr "I_1" "https://example.invalid/issues/1" "$(labels_of dev-lead health-check)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"has excluded label 'health-check'"* ]]
}

@test "dev-lead + fleet-tracker → skip" {
  run process_issue_or_pr "I_1" "https://example.invalid/issues/1" "$(labels_of dev-lead fleet-tracker)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"has excluded label 'fleet-tracker'"* ]]
}

@test "dev-lead + daily-report → skip" {
  run process_issue_or_pr "I_1" "https://example.invalid/issues/1" "$(labels_of dev-lead daily-report)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"has excluded label 'daily-report'"* ]]
}

# ---------------------------------------------------------------------------
# Happy path
# ---------------------------------------------------------------------------

@test "dev-lead alone → calls addProjectV2ItemById with the content id" {
  run process_issue_or_pr "I_node_xyz" "https://example.invalid/issues/1" "$(labels_of dev-lead)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Adding https://example.invalid/issues/1"* ]]
  local last
  last=$(tail -n 1 "${GH_STUB_LOG}")
  [[ "$last" == *"addProjectV2ItemById"* ]]
  [[ "$last" == *"I_node_xyz"* ]]
}

@test "dev-lead + non-excluded other label → still qualifies" {
  run process_issue_or_pr "I_node_xyz" "https://example.invalid/issues/1" "$(labels_of dev-lead bug enhancement)"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Adding"* ]]
  local last
  last=$(tail -n 1 "${GH_STUB_LOG}")
  [[ "$last" == *"addProjectV2ItemById"* ]]
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
