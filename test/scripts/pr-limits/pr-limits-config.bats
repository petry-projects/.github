#!/usr/bin/env bats
# Tests for standards/pr-limits.json — the machine-readable single source of
# truth for the PR-limit caps and exempt-actor list (#507).
#
# Context (#507, ADR docs/initiatives/pull-request-limits-adr.md):
# GitHub exposes no native "max open PRs" repo/org/ruleset surface (ADR §2–§3),
# so the limit lives as source-side shared config consumed by the Phase 2b
# admission gate (#507b) and the Phase 3 apply path (#508). This story delivers
# only the data file. Per ADR §6 every number is provisional pending human
# sign-off; per ADR §7.4 dependabot[bot] is exempt (it stays governed solely by
# its own ecosystem open-pull-requests-limit, so the new cap counts only
# non-Dependabot automation).
#
# These tests validate the contract every consumer relies on: the file parses
# as JSON, the org-wide cap is a positive integer, all required keys exist, the
# numbers are flagged provisional, and dependabot[bot] is on the exempt list.

bats_require_minimum_version 1.5.0

CONFIG="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)/standards/pr-limits.json"

@test "config file exists" {
  [ -f "$CONFIG" ]
}

@test "config parses as valid JSON" {
  run jq -e . "$CONFIG"
  [ "$status" -eq 0 ]
}

@test "status field marks the values provisional (pending human sign-off)" {
  run jq -er '.status' "$CONFIG"
  [ "$status" -eq 0 ]
  [ "$output" = "provisional" ]
}

@test "an inline _note documents that the numbers are not yet confirmed" {
  run jq -er '._note' "$CONFIG"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "org-wide automation open-PR cap is a positive integer" {
  run jq -er '.org_wide.automation_open_pr_cap' "$CONFIG"
  [ "$status" -eq 0 ]
  # integer (no decimal point) and strictly greater than zero
  [[ "$output" =~ ^[0-9]+$ ]]
  [ "$output" -gt 0 ]
}

@test "all required top-level keys exist" {
  for key in status _note _schema_version org_wide per_source_caps exempt_actors exempt_labels; do
    run jq -e "has(\"$key\")" "$CONFIG"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
  done
}

@test "per-source sub-caps cover dev-lead, claude, and initiative-driver" {
  for src in dev-lead claude initiative-driver; do
    run jq -e ".per_source_caps | has(\"$src\")" "$CONFIG"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
  done
}

@test "each per-source sub-cap is a positive integer" {
  run jq -er '.per_source_caps | to_entries[] | .value' "$CONFIG"
  [ "$status" -eq 0 ]
  while read -r v; do
    [[ "$v" =~ ^[0-9]+$ ]]
    [ "$v" -gt 0 ]
  done <<< "$output"
}

@test "exempt_actors is a non-empty array" {
  run jq -er '.exempt_actors | type' "$CONFIG"
  [ "$status" -eq 0 ]
  [ "$output" = "array" ]
  run jq -er '.exempt_actors | length' "$CONFIG"
  [ "$status" -eq 0 ]
  [ "$output" -gt 0 ]
}

@test "dependabot[bot] is present in the exempt-actor list (ADR §7.4)" {
  run jq -e '.exempt_actors | index("dependabot[bot]") != null' "$CONFIG"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "security is present in the exempt-label list (ADR §6/§7.4)" {
  # Guards the ADR safety property that urgent security/hotfix PRs are never
  # throttled by the cap; a regression dropping this label must fail CI.
  run jq -e '.exempt_labels | index("security") != null' "$CONFIG"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "_schema_version is a positive integer" {
  run jq -er '._schema_version' "$CONFIG"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
  [ "$output" -gt 0 ]
}
