#!/usr/bin/env bats
# Contract tests for standards/agent-rate-limits.json — the machine-readable
# single source of truth for per-agent-type rate limits, circuit breakers, and
# the org-wide Claude token-budget breaker (#638, Phase 2 of epic #636).
#
# Context (ADR docs/initiatives/agent-rate-limits-adr.md, #637):
# GitHub exposes no native per-workflow rate limiter and no run-count budget
# (ADR §2/§4), so the limits live as source-side shared config consumed later by
# the Phase 3 gate library and the Phase 4-5 wiring. This story delivers ONLY the
# data file: it is INERT on merge, no workflow reads it (AC #3), and every number
# is a proposal pending human sign-off (ADR §6/§7), mirroring the pr-limits
# sign-off gate.
#
# These tests validate the contract every future consumer relies on: the file
# parses as JSON, all required keys exist, per-agent numeric limits are positive
# integers, each agent carries a circuit breaker, the token-budget block records
# the 5-hour session threshold (default 90%) and the Claude-priority flag, only
# account-wide windows are pause-worthy, and — per the post-ADR clarification —
# there is NO percentage resume mark and the windows are never called "rolling".

bats_require_minimum_version 1.5.0

CONFIG="$(cd "$BATS_TEST_DIRNAME/.." && pwd)/standards/agent-rate-limits.json"

# The four in-scope agent types fixed by the ADR (§3).
AGENT_TYPES=(dev-lead compliance-audit feature-ideation initiative-driver)

@test "config file exists" {
  [ -f "$CONFIG" ]
}

@test "config parses as valid JSON" {
  run jq -e . "$CONFIG"
  [ "$status" -eq 0 ]
}

@test "status records the config is provisional / pending human sign-off" {
  # Unlike pr-limits (already signed off), these numbers are NOT yet signed off
  # (ADR §6/§7). A regression to signed-off without a human gate must fail CI.
  run jq -er '.status' "$CONFIG"
  [ "$status" -eq 0 ]
  [ "$output" = "provisional" ]
}

@test "an inline _note documents the numbers are pending sign-off" {
  run jq -er '._note' "$CONFIG"
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "the _note records the config is inert (no consumer wired yet)" {
  # AC #3: inert on merge. Assert the sign-off/inert intent is written down so a
  # reader knows nothing enforces these values yet.
  run jq -er '._note | ascii_downcase | test("inert|sign-off|sign off")' "$CONFIG"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "_schema_version is a positive integer" {
  run jq -er '._schema_version' "$CONFIG"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
  [ "$output" -gt 0 ]
}

@test "all required top-level keys exist" {
  for key in status _note _schema_version agent_types org_wide exempt_actors exempt_labels; do
    run jq -e "has(\"$key\")" "$CONFIG"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
  done
}

@test "agent_types contains exactly the four ADR in-scope types" {
  run jq -er '.agent_types | keys_unsorted | sort | join(",")' "$CONFIG"
  [ "$status" -eq 0 ]
  [ "$output" = "compliance-audit,dev-lead,feature-ideation,initiative-driver" ]
}

@test "each agent type carries all five ADR control dimensions" {
  for agent in "${AGENT_TYPES[@]}"; do
    for key in max_concurrent_runs max_runtime_minutes cooldown_minutes daily_run_budget circuit_breaker; do
      run jq -e ".agent_types[\"$agent\"] | has(\"$key\")" "$CONFIG"
      [ "$status" -eq 0 ]
      [ "$output" = "true" ]
    done
  done
}

@test "per-agent concurrency, runtime and daily budget are positive integers" {
  for agent in "${AGENT_TYPES[@]}"; do
    for key in max_concurrent_runs max_runtime_minutes daily_run_budget; do
      run jq -er ".agent_types[\"$agent\"].$key" "$CONFIG"
      [ "$status" -eq 0 ]
      [[ "$output" =~ ^[0-9]+$ ]]
      [ "$output" -gt 0 ]
    done
  done
}

@test "per-agent cooldown is a non-negative integer (0 = n/a for weekly-cron agents)" {
  # Cooldown is 'n/a' for the weekly-cron agents (ADR §6) and is encoded as 0
  # rather than a faked positive value. It must still be a real non-negative int.
  for agent in "${AGENT_TYPES[@]}"; do
    run jq -er ".agent_types[\"$agent\"].cooldown_minutes" "$CONFIG"
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]+$ ]]
    [ "$output" -ge 0 ]
  done
}

@test "each agent circuit breaker has a positive threshold and backoff" {
  for agent in "${AGENT_TYPES[@]}"; do
    for key in consecutive_failure_threshold backoff_minutes; do
      run jq -er ".agent_types[\"$agent\"].circuit_breaker.$key" "$CONFIG"
      [ "$status" -eq 0 ]
      [[ "$output" =~ ^[0-9]+$ ]]
      [ "$output" -gt 0 ]
    done
  done
}

@test "daily_run_budget is present as the per-agent cost bound (AC #7)" {
  # The epic's cost cap traces to this concrete key; assert it exists per agent
  # so the traceability the standard doc claims is real in the config.
  for agent in "${AGENT_TYPES[@]}"; do
    run jq -e ".agent_types[\"$agent\"] | has(\"daily_run_budget\")" "$CONFIG"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
  done
}

@test "org_wide.token_budget block exists" {
  run jq -e '.org_wide | has("token_budget")' "$CONFIG"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "the 5-hour session pause threshold is within (0,100]" {
  run jq -er '.org_wide.token_budget.limits.session.pause_threshold_pct' "$CONFIG"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]+$ ]]
  [ "$output" -gt 0 ]
  [ "$output" -le 100 ]
}

@test "the session threshold default is 90 (ADR §7 / AC #2)" {
  run jq -er '.org_wide.token_budget.limits.session.pause_threshold_pct' "$CONFIG"
  [ "$status" -eq 0 ]
  [ "$output" = "90" ]
}

@test "claude_priority flag is boolean true (AC #2)" {
  run jq -er '.org_wide.token_budget.claude_priority' "$CONFIG"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "the session (5h) and weekly_all (7d) windows are pause-worthy" {
  for kind in session weekly_all; do
    run jq -er ".org_wide.token_budget.limits.$kind.pause_worthy" "$CONFIG"
    [ "$status" -eq 0 ]
    [ "$output" = "true" ]
  done
}

@test "weekly_scoped (per-model) is NOT pause-worthy (ADR §2.5 / post-ADR #4)" {
  # `jq -r` (not `-e`): a legitimate `false` value must not flip the exit code.
  run jq -r '.org_wide.token_budget.limits.weekly_scoped.pause_worthy' "$CONFIG"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "weekly_all reserve_pct_per_day, if present, defaults to 2 and is a positive int" {
  # Optional glide-path key; when present it must be the inert default of 2
  # (post-ADR clarification #3). `//empty` skips the check when absent.
  run jq -er '.org_wide.token_budget.limits.weekly_all.reserve_pct_per_day // empty' "$CONFIG"
  [ "$status" -eq 0 ]
  if [ -n "$output" ]; then
    [[ "$output" =~ ^[0-9]+$ ]]
    [ "$output" -gt 0 ]
    [ "$output" = "2" ]
  fi
}

@test "there is NO percentage resume mark anywhere (post-ADR clarification #2)" {
  # An 80% resume/hysteresis mark was REMOVED, not re-tuned: under a fixed window
  # a downward percentage dip cannot occur, making such a mark unreachable. Guard
  # that no resume_pct / resume_threshold / hysteresis key is re-introduced.
  # `jq` (not `-e`): a boolean `false` result is the passing case here.
  run jq '[paths | .[-1]] | map(tostring | ascii_downcase)
          | any(test("resume_pct|resume_threshold|resume_mark|hysteresis"))' "$CONFIG"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "the token-budget windows are never described as 'rolling' (post-ADR #1)" {
  # The session (5h) and weekly_all (7d) SUBSCRIPTION windows are FIXED
  # (authoritative resets_at), not rolling/sliding — guard that vocabulary in the
  # token_budget subtree. (The per-agent daily_run_budget IS a rolling 24h window
  # per ADR §5, a different mechanism, so the guard is scoped, not file-wide.)
  run jq -r '[.org_wide.token_budget | .. | strings] | join(" ") | ascii_downcase | test("rolling")' "$CONFIG"
  [ "$status" -eq 0 ]
  [ "$output" = "false" ]
}

@test "exempt_actors is a non-empty array" {
  run jq -er '.exempt_actors | type' "$CONFIG"
  [ "$status" -eq 0 ]
  [ "$output" = "array" ]
  run jq -er '.exempt_actors | length' "$CONFIG"
  [ "$status" -eq 0 ]
  [ "$output" -gt 0 ]
}

@test "dependabot[bot] is present in the exempt-actor list (reused from pr-limits)" {
  run jq -e '.exempt_actors | index("dependabot[bot]") != null' "$CONFIG"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "org-leads break-glass actor is present in the exempt-actor list" {
  run jq -e '.exempt_actors | index("@petry-projects/org-leads") != null' "$CONFIG"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "security is present in the exempt-label list" {
  run jq -e '.exempt_labels | index("security") != null' "$CONFIG"
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}
