#!/usr/bin/env bash
# pr-auto-review catch-up sweep — orchestrator.
#
# The event-driven pr-auto-review reusable workflow reviews a PR when its
# triggering event fires. A dropped/missed event (or a PR that went green with no
# event in flight) can leave a mergeable PR un-reviewed. This sweep periodically
# re-scans open PRs and dispatches the review agent for the ones the event path
# missed.
#
# This is the thin gh I/O glue; every decision lives in the pure, unit-tested
# cores it sources — lib/ready-check.sh (per-PR readiness) and lib/sweep.sh
# (candidate selection). It implements the four robustness properties of #872:
#
#   1. cap on the number DISPATCHED (ready), not candidates considered
#      → readiness is evaluated first, then pr_auto_review_sweep_plan caps on
#        the ready ones, so a run of older non-ready PRs cannot starve newer
#        ready ones.
#   2. full pagination of the labeled-PR search
#      → the /search/issues call is paged while pr_auto_review_sweep_page_full
#        reports a full page; pages are merged with pr_auto_review_sweep_merge_pages.
#   3. a failed search surfaces an error, is not treated as "nothing to do"
#      → a non-zero gh exit OR a payload pr_auto_review_sweep_valid_search rejects
#        aborts the run instead of yielding an empty candidate set.
#   4. a malformed payload is guarded, does not abort mid-jq
#      → pr_auto_review_sweep_extract catches a jq parse failure and returns
#        non-zero, which this script surfaces explicitly.
#
# Configuration (all via environment):
#   REPO             owner/repo to sweep (default: $GITHUB_REPOSITORY)
#   SWEEP_LABEL      only sweep PRs carrying this label (default: auto-review;
#                    set empty to sweep every open PR)
#   MAX_PER_RUN      max review agents to DISPATCH per run (default: 10)
#   SWEEP_PER_PAGE   search page size, max 100 (default: 100)
#   SWEEP_MAX_PAGES  page ceiling — REST search caps at 1000 results (default: 10)
#   DISPATCH_REPO    repo receiving the repository_dispatch (default:
#                    petry-projects/.github-private)
#   DISPATCH_EVENT   repository_dispatch event_type (default: pr-review-mention)
#   DRY_RUN          when "true", log the plan but do not dispatch (default: false)
#
# Requires: GH_TOKEN with repo scope (for search, pr view/checks, GraphQL, and
# the dispatch).
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/lib/ready-check.sh"
# shellcheck source=/dev/null
. "${SCRIPT_DIR}/lib/sweep.sh"

REPO="${REPO:-${GITHUB_REPOSITORY:-}}"
SWEEP_LABEL="${SWEEP_LABEL-auto-review}"
MAX_PER_RUN="${MAX_PER_RUN:-10}"
SWEEP_PER_PAGE="${SWEEP_PER_PAGE:-100}"
SWEEP_MAX_PAGES="${SWEEP_MAX_PAGES:-10}"
DISPATCH_REPO="${DISPATCH_REPO:-petry-projects/.github-private}"
DISPATCH_EVENT="${DISPATCH_EVENT:-pr-review-mention}"
DRY_RUN="${DRY_RUN:-false}"

if [ -z "$REPO" ]; then
  echo "::error::sweep: REPO (or GITHUB_REPOSITORY) is required" >&2
  exit 2
fi

# ── Gather one PR's readiness facts via gh (fail-closed) ──────────────────────
# Mirrors the reusable workflow's fact-gathering and prints them as one JSON
# object. Called as a plain top-level assignment in the loop below, so under
# `set -e` a gh/network failure aborts the whole sweep — the sweep never scores a
# PR ready on incomplete data. The pure readiness decision is made by the caller.
sweep_pr_facts() {
  local num="$1" pr_meta state is_draft review_decision base_branch
  local checks required_json rules_json threads_json blocking gql

  pr_meta=$(gh pr view "$num" --repo "$REPO" \
    --json state,isDraft,number,reviewDecision,baseRefName)
  state=$(printf '%s' "$pr_meta" | jq -r '.state')
  is_draft=$(printf '%s' "$pr_meta" | jq -r '.isDraft')
  review_decision=$(printf '%s' "$pr_meta" | jq -r '.reviewDecision // ""')
  base_branch=$(printf '%s' "$pr_meta" | jq -r '.baseRefName')

  # gh pr checks exits non-zero when checks are failing/pending but still writes
  # the JSON payload; || true keeps that output under set -e.
  checks=$(gh pr checks "$num" --repo "$REPO" --json bucket,name 2>/dev/null || true)
  [ -z "$checks" ] && checks="[]"

  if rules_json=$(gh api "/repos/${REPO}/rules/branches/${base_branch}" 2>/dev/null); then
    required_json=$(printf '%s' "$rules_json" | pr_auto_review_required_contexts 2>/dev/null || echo "[]")
  else
    required_json="[]"
  fi
  [ -z "$required_json" ] && required_json="[]"

  # shellcheck disable=SC2016  # $owner/$repo/$number are GraphQL variable refs
  gql='query($owner:String!,$repo:String!,$number:Int!){repository(owner:$owner,name:$repo){pullRequest(number:$number){reviewThreads(first:100){nodes{isResolved isOutdated}}}}}'
  threads_json=$(gh api graphql \
    -f "query=$gql" \
    -f owner="${REPO%%/*}" \
    -f repo="${REPO##*/}" \
    -F number="$num")
  blocking=$(printf '%s' "$threads_json" | pr_auto_review_blocking_thread_count)

  jq -cn \
    --arg state "$state" \
    --arg isDraft "$is_draft" \
    --argjson checks "$checks" \
    --argjson required "$required_json" \
    --arg reviewDecision "$review_decision" \
    --arg blocking "$blocking" \
    '{state:$state, isDraft:$isDraft, checks:$checks, required:$required, reviewDecision:$reviewDecision, blocking:$blocking}'
}

# ── 1. Paginated, surfaced, guarded candidate search (#872 findings 2,3,4) ────
query="repo:${REPO} is:pr is:open"
[ -n "$SWEEP_LABEL" ] && query="${query} label:\"${SWEEP_LABEL}\""

pages_file="$(mktemp)"
trap 'rm -f "$pages_file"' EXIT

page=1
while [ "$page" -le "$SWEEP_MAX_PAGES" ]; do
  # Fail-closed on the transport: a non-zero gh exit is surfaced, never treated
  # as an empty result set (#872 finding 3).
  if ! response=$(gh api -X GET /search/issues \
        --raw-field q="$query" \
        -F per_page="$SWEEP_PER_PAGE" \
        -F page="$page" 2>/dev/null); then
    echo "::error::sweep: search API call failed on page ${page} — aborting rather than treating as 'nothing to do'" >&2
    exit 1
  fi

  # Unwrap .items defensively; a malformed response yields "" and is rejected below.
  items=$(printf '%s' "$response" | jq -c '.items' 2>/dev/null || true)

  # Distinguish a valid (possibly empty) result from a failed/garbage one (#872 finding 3).
  if ! printf '%s' "$items" | pr_auto_review_sweep_valid_search; then
    echo "::error::sweep: search returned an invalid payload on page ${page} — aborting" >&2
    exit 1
  fi

  # Guarded parse: a jq failure here returns non-zero instead of aborting mid-pipe (#872 finding 4).
  if ! page_candidates=$(printf '%s' "$items" | pr_auto_review_sweep_extract); then
    echo "::error::sweep: could not parse search results on page ${page} — aborting" >&2
    exit 1
  fi
  printf '%s\n' "$page_candidates" >> "$pages_file"

  page_count=$(printf '%s' "$items" | jq 'length')
  # Stop when the page was short; keep paging while it was full (#872 finding 2).
  pr_auto_review_sweep_page_full "$page_count" "$SWEEP_PER_PAGE" || break
  page=$((page + 1))
done

# Merge pages (dedupe) and order oldest-first so the longest-waiting ready PR
# drains first and is never perpetually starved (#872 ordering).
candidates=$(pr_auto_review_sweep_merge_pages < "$pages_file" | pr_auto_review_sweep_order)
candidate_count=$(printf '%s' "$candidates" | jq 'length')
echo "sweep: ${candidate_count} open candidate PR(s) in ${REPO}${SWEEP_LABEL:+ with label \"$SWEEP_LABEL\"}"

# ── 2. Evaluate readiness, THEN cap on dispatched (#872 finding 1) ────────────
# Build a {number,ready} verdict list in candidate order. Readiness is checked
# for every candidate BEFORE the cap is applied, so non-ready PRs consume no
# dispatch slot and cannot starve ready ones.
verdicts='[]'
while IFS= read -r num; do
  [ -z "$num" ] && continue
  # Plain assignment: a gh failure inside aborts the sweep under set -e (fail-closed).
  facts=$(sweep_pr_facts "$num")
  # Field extraction is pure jq (no gh), so these assignments cannot mask an error.
  f_state=$(printf '%s' "$facts" | jq -r '.state')
  f_draft=$(printf '%s' "$facts" | jq -r '.isDraft')
  f_checks=$(printf '%s' "$facts" | jq -c '.checks')
  f_required=$(printf '%s' "$facts" | jq -c '.required')
  f_review=$(printf '%s' "$facts" | jq -r '.reviewDecision')
  f_blocking=$(printf '%s' "$facts" | jq -r '.blocking')
  # Pure decision — safe to test in `if` (SELF_CHECK empty: the sweep is not a
  # check run on the PR).
  if decision=$(pr_auto_review_ready "$f_state" "$f_draft" "$f_checks" \
        "$f_required" "" "$f_review" "$f_blocking"); then
    ready=true
  else
    ready=false
  fi
  echo "sweep: PR #${num} → ${decision}"
  verdicts=$(printf '%s' "$verdicts" | jq -c --argjson n "$num" --argjson r "$ready" '. + [{number:$n, ready:$r}]')
done < <(printf '%s' "$candidates" | jq -r '.[].number')

mapfile -t to_dispatch < <(printf '%s' "$verdicts" | pr_auto_review_sweep_plan "$MAX_PER_RUN")
echo "sweep: dispatching ${#to_dispatch[@]} of up to ${MAX_PER_RUN} slot(s)"

# ── 3. Dispatch the review agent for the planned PRs ──────────────────────────
for pr in "${to_dispatch[@]}"; do
  [ -z "$pr" ] && continue
  pr_url="https://github.com/${REPO}/pull/${pr}"
  if [ "$DRY_RUN" = "true" ]; then
    echo "::notice::[dry-run] would dispatch auto-review for ${pr_url}"
    continue
  fi
  gh api \
    --method POST \
    --header "Accept: application/vnd.github+json" \
    "/repos/${DISPATCH_REPO}/dispatches" \
    --field event_type="$DISPATCH_EVENT" \
    --field "client_payload[pr_url]=${pr_url}"
  echo "::notice::sweep dispatched auto-review for ${pr_url}"
done
