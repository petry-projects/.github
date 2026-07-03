#!/usr/bin/env bats
# Regression tests pinning the #580 fix: the detection-based
# scripts/apply-rulesets.sh must NOT inject a `Dev-Lead Agent / dev-lead`
# required status check, so its generated `code-quality` set agrees with the
# codified standards/rulesets/code-quality.json (which deliberately omits it,
# per #579 — Dev-Lead Agent is per-PR review, not a merge gate).
#
# These source the script's pure functions directly (guarded main block), so
# they exercise detect_required_checks / build_ruleset_json in isolation.

bats_require_minimum_version 1.5.0

load 'helpers/setup'

setup() {
  tt_make_tmpdir
  tt_install_gh_stub
  # detect_required_checks + build_ruleset_json are defined below the
  # BASH_SOURCE guard, so sourcing does not run main.
  source "$TT_SCRIPT"
}

teardown() {
  tt_cleanup_tmpdir
}

@test "detect_required_checks omits Dev-Lead Agent even when dev-lead.yml is present" {
  GH_STUB_WORKFLOWS="agent-shield.yml dependency-audit.yml dev-lead.yml" \
  GH_STUB_CODEQL_STATE="configured" \
    run detect_required_checks "some-repo"

  [ "$status" -eq 0 ]
  [[ "$output" != *"Dev-Lead Agent / dev-lead"* ]]
}

@test "detect_required_checks still emits the codified contexts" {
  GH_STUB_WORKFLOWS="agent-shield.yml dependency-audit.yml dev-lead.yml" \
  GH_STUB_CODEQL_STATE="configured" \
    run detect_required_checks "some-repo"

  [ "$status" -eq 0 ]
  [[ "$output" == *"CodeQL"* ]]
  [[ "$output" == *"agent-shield / AgentShield"* ]]
  [[ "$output" == *"dependency-audit / Detect ecosystems"* ]]
}

@test "detect_required_checks agrees with the codified code-quality.json context set" {
  # The generated set (for a repo carrying the codified workflows) must be a
  # superset-free match of the checked-in source of truth: every context the
  # detector emits for these workflows is present in code-quality.json, and it
  # adds nothing the codified file omits.
  GH_STUB_WORKFLOWS="agent-shield.yml dependency-audit.yml dev-lead.yml" \
  GH_STUB_CODEQL_STATE="configured" \
    run detect_required_checks "some-repo"
  [ "$status" -eq 0 ]

  codified="$(jq -r '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context' \
    "${TT_REPO_ROOT}/standards/rulesets/code-quality.json")"

  while IFS= read -r ctx; do
    [ -z "$ctx" ] && continue
    grep -qxF "$ctx" <<< "$codified" || {
      echo "detector emitted non-codified context: '$ctx'" >&2
      false
    }
  done <<< "$output"
}

@test "build_ruleset_json injects no contexts beyond those passed" {
  run build_ruleset_json "code-quality" "CodeQL" "agent-shield / AgentShield"
  [ "$status" -eq 0 ]

  contexts="$(echo "$output" | jq -r '.rules[] | select(.type=="required_status_checks") | .parameters.required_status_checks[].context')"
  [[ "$contexts" == *"CodeQL"* ]]
  [[ "$contexts" == *"agent-shield / AgentShield"* ]]
  [[ "$contexts" != *"Dev-Lead Agent / dev-lead"* ]]
}
