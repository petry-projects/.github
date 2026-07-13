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
  # channel-ified in #606 (Story B of the shim-identity epic #604)
  ring_is_ring_reusable feature-ideation
  ring_is_ring_reusable pr-auto-review
  ! ring_is_ring_reusable add-to-project
}

@test "ring_canonical_ref: feature-ideation and pr-auto-review resolve to tier channels (#606)" {
  [ "$(ring_canonical_ref feature-ideation markets)" = "feature-ideation/stable" ]
  [ "$(ring_canonical_ref feature-ideation TalkTerm)" = "feature-ideation/ring1" ]
  [ "$(ring_canonical_ref pr-auto-review markets)" = "pr-auto-review/stable" ]
  [ "$(ring_canonical_ref pr-auto-review TalkTerm)" = "pr-auto-review/ring1" ]
}

@test "ring_canonical_ref is the repo's tier channel" {
  [ "$(ring_canonical_ref agent-shield TalkTerm)" = "agent-shield/ring1" ]
  [ "$(ring_canonical_ref agent-shield markets)" = "agent-shield/stable" ]
  [ "$(ring_canonical_ref dev-lead .github-private)" = "dev-lead/next" ]
}

@test "ring_canonical_ref: major-aware form yields <agent>/v<major>-<tier> (#657 F3)" {
  # A major argument opts the ref into the major-scoped channel line; the tier
  # is still the repo's ring tier.
  [ "$(ring_canonical_ref agent-shield markets 2)" = "agent-shield/v2-stable" ]
  [ "$(ring_canonical_ref agent-shield TalkTerm 2)" = "agent-shield/v2-ring1" ]
  [ "$(ring_canonical_ref dev-lead .github-private 5)" = "dev-lead/v5-next" ]
  # No major argument is backward-compatible: the legacy bare-tier ref.
  [ "$(ring_canonical_ref agent-shield markets)" = "agent-shield/stable" ]
}

@test "ring_pinned_major: extracts M from v<M>-<tier>, empty for bare tier (#657 F3)" {
  [ "$(ring_pinned_major agent-shield/v3-stable)" = "3" ]
  [ "$(ring_pinned_major agent-shield/v12-ring1)" = "12" ]
  # Bare-tier (legacy/unmajored) refs carry no major.
  [ -z "$(ring_pinned_major agent-shield/stable)" ]
  [ -z "$(ring_pinned_major agent-shield/ring0)" ]
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
