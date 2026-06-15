#!/usr/bin/env bash
# Eligibility predicates for the auto-rebase reusable workflow.
#
# These are pure, side-effect-free functions so they can be unit-tested with
# bats (see test/workflows/auto-rebase/eligibility.bats). The reusable
# workflow sources this file and uses the predicate to decide which behind
# PRs to update-branch, instead of fanning out to every behind PR.
#
# Contract: see .github/scripts/auto-rebase/README.md

# auto_rebase_has_current_approval
#   Reads a GitHub pull-request reviews JSON array on stdin (the response of
#   `GET /repos/{repo}/pulls/{n}/reviews`, oldest-first) and returns 0 if the
#   PR currently has at least one APPROVED review, else 1.
#
#   "Current" means the reviewer's most recent decision review wins: a later
#   CHANGES_REQUESTED or DISMISSED cancels an earlier APPROVED, while
#   COMMENTED/PENDING reviews do not change a reviewer's stance. We check the
#   real review states here rather than reviewDecision, which is null on repos
#   without required reviews (issue #465 implementer note).
auto_rebase_has_current_approval() {
  local result
  result=$(jq -r '
    reduce (.[] | select(.state == "APPROVED" or .state == "CHANGES_REQUESTED" or .state == "DISMISSED")) as $r ({}; .[$r.user.login] = $r.state)
    | any(. == "APPROVED")
  ')
  [[ "$result" == "true" ]]
}

# auto_rebase_has_ready_label LABEL
#   Reads a PR labels JSON array on stdin (objects with a .name field) and
#   returns 0 if a label named LABEL is present, else 1.
auto_rebase_has_ready_label() {
  local label="$1" present
  present=$(jq -r --arg L "$label" 'any(.[]; .name == $L)')
  [[ "$present" == "true" ]]
}

# auto_rebase_pr_eligible MODE IS_DRAFT IS_APPROVED HAS_LABEL
#   Decides whether a behind PR should be updated, given its draft/approval/
#   label state. IS_DRAFT, IS_APPROVED and HAS_LABEL are the strings "true"
#   or "false". Returns 0 (eligible), 1 (not eligible), or 2 (unknown mode).
#
#   Modes (the tunable `eligibility` workflow input):
#     review-ready  non-draft AND (approved OR carries the ready label).
#                   The default — restricts fan-out to review-ready PRs.
#     all           every behind PR, including drafts. Escape hatch that
#                   restores the original unrestricted fan-out behavior.
auto_rebase_pr_eligible() {
  local mode="$1" is_draft="$2" is_approved="$3" has_label="$4"
  case "$mode" in
    all)
      return 0
      ;;
    review-ready)
      [[ "$is_draft" == "true" ]] && return 1
      if [[ "$is_approved" == "true" || "$has_label" == "true" ]]; then
        return 0
      fi
      return 1
      ;;
    *)
      echo "auto_rebase_pr_eligible: unknown eligibility mode '$mode'" >&2
      return 2
      ;;
  esac
}
