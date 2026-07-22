#!/usr/bin/env bash
# sweep-dispatch.sh — catch-up sweep for the pr-auto-review ready-check (#868).
#
# Why this exists (Epic #850 / #857 fleet convergence): the event-driven
# ready-check (pr-auto-review-reusable.yml) has no catch-up. When a bulk
# standards-sync convergence opens many PRs at once, the ready-check fires while
# CI is still mid-flight ("N of M checks not yet passing — skipping") and, once
# everything goes green, no further event re-evaluates it — the PR sits BLOCKED
# with all required checks green and no code-owner approval, indefinitely.
#
# This scheduled/manual sweep enumerates the open standards-sync PRs org-wide
# and, for each one that satisfies the SAME readiness gate as the event path
# (delegated verbatim to pr_auto_review_ready — so the #680 cancelled/superseded
# -non-required tolerance is inherited), re-invokes the dispatch → review-agent
# path. It is the missing catch-up for the missed-event case and removes the
# need for manual `gh run rerun` nudges. Periodic re-evaluation is also the
# debounce: a PR skipped during a transient required re-run is re-swept next
# cycle, so no clean "fresh event + all green" window has to be caught.
#
# Back-pressure (donpetry-bot token/capacity, acceptance criterion): at most
# MAX_PER_RUN PRs are dispatched per run so a 10-PR burst drains at a throttled
# rate over a few cycles instead of firing every dispatch at once. The cap is
# applied at the dispatch stage so non-ready older PRs cannot consume all slots
# and starve newer ready PRs.
#
# Idempotent: dispatching an already-approved / already-merged PR is a no-op on
# the review-agent side. Honours DRY_RUN=1 (logs intended dispatches, mutates
# nothing).
#
# Env:
#   GH_TOKEN         classic PAT with repo scope — API reads + dispatch (required)
#   SEARCH_OWNER     org to scan for open PRs           (default: petry-projects)
#   SEARCH_LIMIT     gh search prs --limit cap          (default: 1000)
#   SWEEP_LABEL      PR label to sweep                  (default: standards-sync)
#   MAX_PER_RUN      max PRs to dispatch per run        (default: 8)
#   DISPATCH_REPO    repository_dispatch target repo    (default: petry-projects/.github-private)
#   DRY_RUN          "1" → log intended dispatches only
set -euo pipefail

_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=.github/scripts/pr-auto-review/lib/ready-check.sh
. "${_dir}/lib/ready-check.sh"
# shellcheck source=.github/scripts/pr-auto-review/lib/sweep.sh
. "${_dir}/lib/sweep.sh"

SEARCH_OWNER="${SEARCH_OWNER:-petry-projects}"
SEARCH_LIMIT="${SEARCH_LIMIT:-1000}"
SWEEP_LABEL="${SWEEP_LABEL:-standards-sync}"
MAX_PER_RUN="${MAX_PER_RUN:-8}"
DISPATCH_REPO="${DISPATCH_REPO:-petry-projects/.github-private}"
DRY_RUN="${DRY_RUN:-0}"

# ── Enumerate open, non-draft PRs carrying the sweep label, org-wide ──────────
# `gh search prs` spans every repo the token can see in one call, so the sweep
# runs centrally without an App token or a per-repo installation walk.
# Oldest-first (created asc) so back-pressure drains fairly: each capped run
# takes the oldest waiting PRs, and a merged PR leaves the set so the next-oldest
# advances next cycle — no PR is starved by newer arrivals under best-match order.
# SEARCH_LIMIT defaults to 1000 (the GitHub Search API per-query maximum); raise
# it with pagination if the org ever exceeds that.
if ! PR_LIST=$(gh search prs \
  --owner "$SEARCH_OWNER" \
  --label "$SWEEP_LABEL" \
  --state open \
  --sort created \
  --order asc \
  --limit "$SEARCH_LIMIT" \
  --json url,isDraft); then
  echo "::error::gh search prs failed — sweep aborted (check token permissions and rate limits)"
  exit 1
fi
if [ -z "${PR_LIST:-}" ]; then
  PR_LIST="[]"
fi

# Selection (pure, unit-tested): drops drafts. Back-pressure cap is at dispatch stage.
mapfile -t CANDIDATES < <(printf '%s' "$PR_LIST" | pr_auto_review_sweep_candidates)

if ! total_open=$(printf '%s' "$PR_LIST" | jq 'if type == "array" then length else 0 end' 2>/dev/null); then
  echo "::error::PR_LIST was not valid JSON — aborting sweep"
  exit 1
fi
[ "$DRY_RUN" = "1" ] && dry_note=" (DRY_RUN)" || dry_note=""
echo "Sweep: ${total_open} open '${SWEEP_LABEL}' PR(s) in ${SEARCH_OWNER}; evaluating ${#CANDIDATES[@]} this run (MAX_PER_RUN=${MAX_PER_RUN})${dry_note}."

if [ "${#CANDIDATES[@]}" -eq 0 ]; then
  echo "No candidate PRs to evaluate — nothing to do."
  exit 0
fi

# evaluate_pr PR_URL
#   Gathers the same PR facts the event-path glue gathers and returns the
#   pr_auto_review_ready decision class on stdout; exit 0 iff ready to dispatch.
#   Mirrors the "Check PR readiness criteria" step of pr-auto-review-reusable.yml
#   (there is no self-check to exclude in a sweep — the sweep is not a PR check).
evaluate_pr() {
  local pr_url="$1" repo pr_meta state is_draft pr_number review_decision base_branch
  local checks required_json rules_json threads_json blocking_thread_count
  repo=$(printf '%s' "$pr_url" | sed 's|https://github.com/||; s|/pull/.*||')

  pr_meta=$(gh pr view "$pr_url" --json state,isDraft,number,reviewDecision,baseRefName)
  state=$(printf '%s' "$pr_meta" | jq -r '.state')
  is_draft=$(printf '%s' "$pr_meta" | jq -r '.isDraft')
  pr_number=$(printf '%s' "$pr_meta" | jq -r '.number')
  review_decision=$(printf '%s' "$pr_meta" | jq -r '.reviewDecision // ""')
  base_branch=$(printf '%s' "$pr_meta" | jq -r '.baseRefName')

  checks=$(gh pr checks "$pr_url" --json bucket,name 2>/dev/null || true)
  if [ -z "${checks}" ]; then checks="[]"; fi

  if rules_json=$(gh api "/repos/${repo}/rules/branches/${base_branch}" 2>/dev/null); then
    required_json=$(printf '%s' "$rules_json" | pr_auto_review_required_contexts 2>/dev/null || echo "[]")
  else
    required_json="[]"
  fi
  if [ -z "${required_json}" ]; then required_json="[]"; fi

  # shellcheck disable=SC2016  # $owner/$repo/$number are GraphQL variable refs, not shell vars
  local gql='query($owner:String!,$repo:String!,$number:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$number){reviewThreads(first:100){nodes{isResolved isOutdated}}}}}'
  threads_json=$(gh api graphql \
    -f "query=$gql" \
    -f owner="${repo%%/*}" \
    -f repo="${repo##*/}" \
    -F number="${pr_number}")
  blocking_thread_count=$(printf '%s' "$threads_json" | pr_auto_review_blocking_thread_count)

  pr_auto_review_ready \
    "$state" "$is_draft" "$checks" "$required_json" \
    "" "$review_decision" "$blocking_thread_count"
}

dispatched=0
dispatch_failures=0
for pr_url in "${CANDIDATES[@]}"; do
  [ -z "$pr_url" ] && continue
  [ "$dispatched" -ge "$MAX_PER_RUN" ] && break
  echo "::group::${pr_url}"
  if decision=$(evaluate_pr "$pr_url"); then
    if [ "$DRY_RUN" = "1" ]; then
      echo "[dry-run] would dispatch review agent for ${pr_url} (decision=${decision})"
      dispatched=$((dispatched + 1))
    else
      if gh api \
        --method POST \
        --header "Accept: application/vnd.github+json" \
        "/repos/${DISPATCH_REPO}/dispatches" \
        --field event_type=pr-review-mention \
        --field "client_payload[pr_url]=${pr_url}"; then
        echo "::notice::Sweep dispatched auto-review for ${pr_url}"
        dispatched=$((dispatched + 1))
      else
        echo "::error::Dispatch failed for ${pr_url}"
        dispatch_failures=$((dispatch_failures + 1))
      fi
    fi
  else
    echo "Not ready (decision=${decision}) — skipping ${pr_url}"
  fi
  echo "::endgroup::"
done

echo "Sweep complete — dispatched ${dispatched} of ${#CANDIDATES[@]} evaluated PR(s)."
if [ "$dispatch_failures" -gt 0 ]; then
  echo "::warning::${dispatch_failures} dispatch failure(s) this run."
  exit 1
fi
