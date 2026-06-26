#!/usr/bin/env bats
# Unit tests for scripts/lib/ring-pins.sh — the canary-ring pin model shared by
# compliance-audit.sh (check_centralized_workflow_stubs) and
# deploy-standard-workflows.sh (is_already_compliant). The lib has no `main`, so
# it is sourced directly and its pure helpers are exercised in-process.

setup() {
  REPO_ROOT="$(cd -- "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  # shellcheck source=/dev/null
  source "${REPO_ROOT}/scripts/lib/ring-pins.sh"
}

@test "ring_tier_for_repo maps each tier" {
  [ "$(ring_tier_for_repo .github-private)" = "next" ]
  [ "$(ring_tier_for_repo .github)" = "ring0" ]
  [ "$(ring_tier_for_repo TalkTerm)" = "ring1" ]
  [ "$(ring_tier_for_repo bmad-bgreat-suite)" = "ring1" ]
  [ "$(ring_tier_for_repo markets)" = "stable" ]
  [ "$(ring_tier_for_repo anything-else)" = "stable" ]
}

@test "ring_is_ring_reusable recognises the ring set (incl. dev-lead)" {
  ring_is_ring_reusable auto-rebase
  ring_is_ring_reusable pr-review-mention
  ring_is_ring_reusable dev-lead
  ! ring_is_ring_reusable feature-ideation
  ! ring_is_ring_reusable add-to-project
}

@test "ring_canonical_ref is the repo's tier channel" {
  [ "$(ring_canonical_ref agent-shield TalkTerm)" = "agent-shield/ring1" ]
  [ "$(ring_canonical_ref agent-shield markets)" = "agent-shield/stable" ]
  [ "$(ring_canonical_ref dev-lead .github-private)" = "dev-lead/next" ]
}

@test "ring_accepted_refs: canonical first, then the ring-channel grace" {
  run ring_accepted_refs auto-rebase TalkTerm
  [ "${lines[0]}" = "auto-rebase/ring1" ]                 # canonical = tier channel
  printf '%s\n' "${lines[@]}" | grep -qx "auto-rebase/stable"  # higher tier accepted
  # the pre-ring @v1/@v2 grace was dropped in #870 — migration complete
  ! printf '%s\n' "${lines[@]}" | grep -qx "v1"
  ! printf '%s\n' "${lines[@]}" | grep -qx "v2"
}

@test "ring_legacy_csv excludes the canonical and comma-joins the ring channels" {
  run ring_legacy_csv auto-rebase markets
  [[ "$output" == *"auto-rebase/next"* ]]
  [[ "$output" == *"auto-rebase/ring1"* ]]
  [[ "$output" != *"auto-rebase/stable"* ]]
  # no pre-ring grace
  [[ "$output" != *"v1"* ]]
  [[ "$output" != *"v2"* ]]
}
