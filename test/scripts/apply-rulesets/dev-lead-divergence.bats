#!/usr/bin/env bats
# Tests for detect_required_checks() in scripts/apply-rulesets.sh — specifically
# the #580 debt: the detection-based builder must NOT inject a non-codified
# `Dev-Lead Agent / dev-lead` required status check.
#
# Per #579, the Dev-Lead Agent is a per-PR review, not a merge gate — requiring
# it deadlocks workflow-touching PRs. The codified source of truth
# (standards/rulesets/code-quality.json) deliberately omits it, so the
# detection-based copy must agree and not add it back.
#
# The suite sources the script (guarded main block) and stubs `gh` so the pure
# workflow-detection logic can run without live API calls. It asserts that even
# when dev-lead.yml is present in a repo, the Dev-Lead context is not emitted,
# while the genuinely-codified centralized checks still are (no over-removal).

bats_require_minimum_version 1.5.0

setup() {
  SCRIPT="${BATS_TEST_DIRNAME}/../../../scripts/apply-rulesets.sh"
  [ -f "$SCRIPT" ] || { echo "script not found: $SCRIPT" >&2; return 1; }

  # Sourcing the script must not run main / usage (requires the BASH_SOURCE
  # guard added for #580). GH_TOKEN is unset in the test env; the guard keeps
  # the top-level token check from aborting the source.
  # shellcheck source=/dev/null
  source "$SCRIPT"
}

# ---------------------------------------------------------------------------
# gh stub — answers the three API shapes detect_required_checks() issues:
#   1. contents/.github/workflows          → newline list of workflow names
#   2. contents/.github/workflows/<file>   → base64 of the file's `.content`
#   3. code-scanning/default-setup         → the default-setup state string
#
# MOCK_WORKFLOWS (array) and MOCK_CODEQL_STATE (string) parameterize each test.
# ---------------------------------------------------------------------------
gh() {
  local path="${2:-}"
  case "$path" in
    */contents/.github/workflows)
      printf '%s\n' "${MOCK_WORKFLOWS[@]}"
      ;;
    */contents/.github/workflows/sonarcloud.yml)
      # No top-level `name:` → workflow_name() returns empty → detection uses
      # the bare `SonarCloud` fallback, matching the codified code-quality.json.
      printf 'on: push\njobs:\n  scan: {}\n' | base64
      ;;
    */contents/.github/workflows/ci.yml)
      printf 'name: CI\njobs:\n  build:\n    name: build\n' | base64
      ;;
    */code-scanning/default-setup)
      printf '%s\n' "${MOCK_CODEQL_STATE:-configured}"
      ;;
    *)
      return 1
      ;;
  esac
}

# ---------------------------------------------------------------------------
# The divergence guard: dev-lead.yml present must NOT add the Dev-Lead context.
# ---------------------------------------------------------------------------

@test "dev-lead.yml present does NOT inject 'Dev-Lead Agent / dev-lead'" {
  MOCK_WORKFLOWS=("agent-shield.yml" "dependency-audit.yml" "dev-lead.yml")
  MOCK_CODEQL_STATE="configured"
  run detect_required_checks "somerepo"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Dev-Lead Agent / dev-lead"* ]]
}

@test "dev-lead.yml as the only workflow yields no Dev-Lead context" {
  MOCK_WORKFLOWS=("dev-lead.yml")
  MOCK_CODEQL_STATE="configured"
  run detect_required_checks "somerepo"
  [ "$status" -eq 0 ]
  [[ "$output" != *"Dev-Lead"* ]]
}

# ---------------------------------------------------------------------------
# No over-removal: the genuinely-codified centralized checks still appear.
# ---------------------------------------------------------------------------

@test "codified centralized checks are still emitted" {
  MOCK_WORKFLOWS=("agent-shield.yml" "dependency-audit.yml" "dev-lead.yml")
  MOCK_CODEQL_STATE="configured"
  run detect_required_checks "somerepo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"agent-shield / AgentShield"* ]]
  [[ "$output" == *"dependency-audit / Detect ecosystems"* ]]
  [[ "$output" == *"CodeQL"* ]]
}

@test "detected set matches the codified code-quality contexts for these workflows" {
  # With sonarcloud + agent-shield + dependency-audit + configured CodeQL, the
  # detection output must equal the codified standards/rulesets/code-quality.json
  # context set (order-independent) — no extra Dev-Lead injection.
  MOCK_WORKFLOWS=("sonarcloud.yml" "agent-shield.yml" "dependency-audit.yml" "dev-lead.yml")
  MOCK_CODEQL_STATE="configured"
  run detect_required_checks "somerepo"
  [ "$status" -eq 0 ]

  detected=$(printf '%s\n' "$output" | sort)
  codified=$(jq -r '.rules[] | select(.type=="required_status_checks")
    | .parameters.required_status_checks[].context' \
    "${BATS_TEST_DIRNAME}/../../../standards/rulesets/code-quality.json" | sort)
  [ "$detected" = "$codified" ]
}
