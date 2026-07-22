#!/usr/bin/env bash
# Pure decision core for the pr-auto-review catch-up sweep.
#
# The event-driven pr-auto-review reusable workflow dispatches a review agent for
# a single PR when its triggering event (CI green, review submitted, …) fires. A
# missed or dropped event, or a PR that went green while no event was in flight,
# can leave a mergeable PR un-reviewed. The catch-up sweep periodically re-scans
# open PRs and dispatches the review agent for the ones the event path missed.
#
# These functions are pure and side-effect-free (like lib/ready-check.sh) so the
# sweep's robustness properties (issue #872) are unit-testable without a live gh:
#
#   * pr_auto_review_sweep_plan      — cap on the number DISPATCHED (ready), not
#                                      candidates considered, so a run of older
#                                      non-ready PRs cannot starve newer ready
#                                      ones. (#872 finding 1)
#   * pr_auto_review_sweep_order     — deterministic oldest-first ordering so the
#                                      longest-waiting ready PR drains first and
#                                      is not perpetually starved. (#872 ordering)
#   * pr_auto_review_sweep_page_full — pagination predicate: a full page means
#                                      more may exist. (#872 finding 2)
#   * pr_auto_review_sweep_merge_pages — merge + dedupe accumulated pages so PRs
#                                      beyond page 1 are swept. (#872 finding 2)
#   * pr_auto_review_sweep_valid_search — a failed search is surfaced, not
#                                      treated as an empty result. (#872 finding 3)
#   * pr_auto_review_sweep_extract   — guarded parse: a malformed payload returns
#                                      non-zero instead of aborting the run under
#                                      set -e. (#872 finding 4)
#
# Contract: see .github/scripts/pr-auto-review/README.md.
# The orchestrator that supplies the gh I/O is sweep.sh alongside this file.

# pr_auto_review_sweep_valid_search
#   Reads a search payload on stdin and validates it is a well-formed JSON array
#   (the shape `gh search prs --json …` / a REST search `.items` returns). Exit 0
#   when valid — INCLUDING a legitimately empty `[]`. Exit 1 with a message on
#   stderr otherwise: an empty string, malformed JSON, or a non-array such as an
#   API error object (`{"message":"Bad credentials"}`).
#
#   Why (#872 finding 3): an unchecked `gh search` failure yields an empty set,
#   which the sweep would read as "nothing to do" and silently skip every PR. The
#   caller pairs this with gh's own exit status so a transport/API failure is
#   surfaced as an error instead of a no-op.
pr_auto_review_sweep_valid_search() {
  local payload
  payload=$(cat)
  if [ -z "$payload" ]; then
    echo "sweep: empty search payload (search likely failed)" >&2
    return 1
  fi
  if ! printf '%s' "$payload" | jq -e 'type == "array"' >/dev/null 2>&1; then
    echo "sweep: search payload is not a JSON array (search likely failed)" >&2
    return 1
  fi
}

# pr_auto_review_sweep_extract
#   Reads a raw search payload on stdin and emits a compact, normalized candidate
#   array `[{ "number": N, "updatedAt": "…" }]` on stdout. Returns 0 on success.
#
#   Guarded (#872 finding 4): a malformed or non-array payload makes jq fail; the
#   failure is caught and turned into a non-zero RETURN with an empty stdout,
#   rather than propagating as an uncaught jq error that would abort the whole
#   sweep under `set -euo pipefail`. The caller checks the return value and can
#   surface the bad payload without losing the candidates it already parsed.
pr_auto_review_sweep_extract() {
  local payload out
  payload=$(cat)
  if ! out=$(printf '%s' "$payload" | jq -c '
      if type == "array" then
        [ .[] | { number: .number, updatedAt: (.updatedAt // .updated_at) } ]
      else
        error("not an array")
      end
    ' 2>/dev/null); then
    echo "sweep: could not parse search payload — skipping it" >&2
    return 1
  fi
  printf '%s\n' "$out"
}

# pr_auto_review_sweep_page_full COUNT PER_PAGE
#   Pagination predicate. Exit 0 when the page was full (COUNT >= PER_PAGE), so
#   another page may exist and should be fetched; exit 1 when the page was short
#   or empty (the last page).
#
#   Why (#872 finding 2): the labeled-PR search was hard-limited to one page of
#   100, so PRs beyond page 1 were never swept. The orchestrator loops fetching
#   pages while this predicate is true.
pr_auto_review_sweep_page_full() {
  local count="${1:-0}" per_page="${2:-100}"
  [ "$count" -ge "$per_page" ]
}

# pr_auto_review_sweep_merge_pages
#   Reads one-or-more candidate JSON arrays concatenated on stdin (one per page)
#   and emits a single compact array on stdout, deduped by `.number` (a PR can
#   appear on two pages if the underlying set shifts between fetches). (#872
#   finding 2)
pr_auto_review_sweep_merge_pages() {
  jq -sc 'add // [] | unique_by(.number)'
}

# pr_auto_review_sweep_order
#   Reads a candidate JSON array on stdin and emits it sorted oldest-first by
#   `updatedAt`, ties broken by `.number` ascending, on stdout.
#
#   Why (#872 ordering): when more PRs are ready than a single run's dispatch cap
#   allows, draining the longest-waiting (oldest) ready PR first guarantees no
#   ready PR is perpetually starved across successive runs (FIFO fairness).
pr_auto_review_sweep_order() {
  jq -c 'sort_by(.updatedAt, .number)'
}

# pr_auto_review_sweep_plan MAX_PER_RUN
#   Reads an ORDERED candidate JSON array on stdin, each element
#   `{ "number": N, "ready": true|false }`, and prints the PR numbers to dispatch
#   — one per line — walking candidates in order and emitting a ready one until
#   MAX_PER_RUN of them have been emitted. Non-ready candidates are skipped and
#   consume NO slot. Exit 0.
#
#   Why (#872 finding 1): the cap must apply to the number DISPATCHED (ready), not
#   to candidates considered. Capping on candidates lets a leading run of older
#   non-ready PRs consume every slot and starve the ready ones behind them; gating
#   on dispatched count means readiness is checked first and only ready PRs count
#   against the cap.
pr_auto_review_sweep_plan() {
  local max="${1:-0}"
  jq -r --argjson max "$max" '
    [ .[] | select(.ready == true) | .number ] | .[0:$max] | .[]
  '
}
