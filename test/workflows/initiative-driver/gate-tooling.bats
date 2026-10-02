#!/usr/bin/env bats
# Tests for the agent-rate-limit gate wiring of the canonical caller stub
# standards/workflows/initiative-driver.yml (issue #1232).
#
# The Phase-4 stub (#640) fetched the gate tooling at the moving tag `v1`, which
# predates scripts/agent-rate-limit-gate.sh — the gate was silently inert. The
# tooling checkout must be pinned to an immutable commit SHA, a missing gate
# script must be reported loudly (not swallowed), and the header must describe
# what the stub actually does.

TT_REPO_ROOT="$(cd -- "$(dirname -- "${BATS_TEST_DIRNAME}")/../.." && pwd)"
STUB="${TT_REPO_ROOT}/standards/workflows/initiative-driver.yml"
LIVE="${TT_REPO_ROOT}/.github/workflows/initiative-driver.yml"

CHECKOUT_STEP='Checkout agent-rate-limit gate tooling'
GATE_STEP='Agent rate-limit admission gate (enforcing)'

@test "stub: gate tooling checkout is pinned to a full commit SHA" {
  run yq -r ".jobs.dispatch.steps[] | select(.name == \"${CHECKOUT_STEP}\") | .with.ref" "$STUB"
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9a-f]{40}$ ]]
}

@test "stub: gate tooling checkout still targets petry-projects/.github" {
  run yq -r ".jobs.dispatch.steps[] | select(.name == \"${CHECKOUT_STEP}\") | .with.repository" "$STUB"
  [ "$status" -eq 0 ]
  [ "$output" = 'petry-projects/.github' ]
}

@test "stub: gate step detects a missing gate script and reports an ::error::" {
  run yq -r ".jobs.dispatch.steps[] | select(.name == \"${GATE_STEP}\") | .run" "$STUB"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE '\[ -f "?\$\{?ARL_GATE_SCRIPT\}?"? \]'
  echo "$output" | grep -q '::error::'
  echo "$output" | grep -q 'GITHUB_STEP_SUMMARY'
}

@test "stub: gate invocation is not masked by '|| true'" {
  run yq -r ".jobs.dispatch.steps[] | select(.name == \"${GATE_STEP}\") | .run" "$STUB"
  [ "$status" -eq 0 ]
  ! echo "$output" | grep -qF '|| true'
}

@test "stub: missing gate script exits non-zero (step marked failed, job continues)" {
  run yq -r ".jobs.dispatch.steps[] | select(.name == \"${GATE_STEP}\") | .run" "$STUB"
  [ "$status" -eq 0 ]
  local script="$output"
  local tmp
  tmp="$(mktemp -d)"
  run env -C "$tmp" GITHUB_STEP_SUMMARY="$tmp/summary" GITHUB_OUTPUT="$tmp/out" \
    ARL_ACTOR=a ARL_TRACKING_REPO=o/r ARL_TRACKING_ISSUE= bash -c "$script"
  [ "$status" -ne 0 ]
  [[ "$output" == *"::error::"* ]]
  grep -q 'agent-rate-limit-gate.sh' "$tmp/summary"
  # No defer is emitted — the dispatch step's fail-open guard still dispatches.
  ! grep -q 'decision=defer' "$tmp/out" 2>/dev/null
  rm -rf "$tmp"

  run yq -r ".jobs.dispatch.steps[] | select(.name == \"${GATE_STEP}\") | .\"continue-on-error\"" "$STUB"
  [ "$output" = 'true' ]
}

@test "stub: header no longer claims the gate runs AHEAD of the concurrency group" {
  ! grep -qiE 'AHEAD of the cancel-in-progress' "$STUB"
}

@test "stub: adoption step names the canonical GH_PAT_DON_PETRY secret" {
  run grep -nE '^#   3\..*GH_PAT_DON_PETRY' "$STUB"
  [ "$status" -eq 0 ]
}

@test "live copy matches the standard verbatim" {
  run diff "$STUB" "$LIVE"
  [ "$status" -eq 0 ]
}
