#!/usr/bin/env bats
# Tests for pr_auto_review_sweep_candidates in
# .github/scripts/pr-auto-review/lib/sweep.sh
#
# The catch-up sweep (issue #868) enumerates open standards-sync PRs and
# re-invokes the ready-check → dispatch path for the ones that went green
# without a fresh event. pr_auto_review_sweep_candidates is the pure,
# side-effect-free selection core: given the PR list the sweep workflow fetched
# (`gh search prs --json url,isDraft`), it emits ALL non-draft candidate PR URLs
# in input order. The back-pressure cap (MAX_PER_RUN dispatches per cycle) is
# enforced at the dispatch stage in sweep-dispatch.sh — not here — so non-ready
# older PRs cannot consume all candidate slots and starve newer ready PRs.
#
# The per-PR readiness decision itself is NOT re-implemented here: the sweep
# reuses pr_auto_review_ready, so the #680 cancelled/superseded-non-required
# tolerance is inherited verbatim (see ready.bats / ready-check.bats).

load 'helpers/setup'

setup() {
  # shellcheck source=/dev/null
  . "${TT_SCRIPTS_DIR}/lib/sweep.sh"
}

# Three open PRs, the middle one a draft.
LIST='[
  {"url":"https://github.com/petry-projects/repo-a/pull/1","isDraft":false},
  {"url":"https://github.com/petry-projects/repo-b/pull/2","isDraft":true},
  {"url":"https://github.com/petry-projects/repo-c/pull/3","isDraft":false}
]'

# ── draft exclusion ──────────────────────────────────────────────────────────

@test "candidates: drafts are excluded, non-drafts kept in input order" {
  run pr_auto_review_sweep_candidates <<<"$LIST"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "https://github.com/petry-projects/repo-a/pull/1" ]
  [ "${lines[1]}" = "https://github.com/petry-projects/repo-c/pull/3" ]
  [ "${#lines[@]}" -eq 2 ]
}

# ── no candidate-stage cap (cap is at dispatch stage) ────────────────────────

@test "candidates: all non-draft PRs emitted — no cap at candidate stage" {
  # The back-pressure cap (MAX_PER_RUN) lives in sweep-dispatch.sh, not here.
  # A five-PR list with one draft should yield four candidates, not a smaller
  # capped slice, so non-ready older PRs cannot starve newer ready ones.
  big_list='[
    {"url":"https://github.com/petry-projects/repo-a/pull/1","isDraft":false},
    {"url":"https://github.com/petry-projects/repo-b/pull/2","isDraft":true},
    {"url":"https://github.com/petry-projects/repo-c/pull/3","isDraft":false},
    {"url":"https://github.com/petry-projects/repo-d/pull/4","isDraft":false},
    {"url":"https://github.com/petry-projects/repo-e/pull/5","isDraft":false}
  ]'
  run pr_auto_review_sweep_candidates <<<"$big_list"
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 4 ]
  [ "${lines[0]}" = "https://github.com/petry-projects/repo-a/pull/1" ]
  [ "${lines[3]}" = "https://github.com/petry-projects/repo-e/pull/5" ]
}

# ── empty / malformed input ──────────────────────────────────────────────────

@test "candidates: empty PR list emits nothing" {
  run pr_auto_review_sweep_candidates <<<'[]'
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 0 ]
}

@test "candidates: empty stdin emits nothing" {
  run pr_auto_review_sweep_candidates < /dev/null
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 0 ]
}

@test "candidates: non-array API error body emits nothing" {
  run pr_auto_review_sweep_candidates <<<'{"message":"Not Found"}'
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 0 ]
}

@test "candidates: an object missing isDraft is treated as non-draft" {
  run pr_auto_review_sweep_candidates <<<'[{"url":"https://github.com/petry-projects/repo-a/pull/7"}]'
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [ "${lines[0]}" = "https://github.com/petry-projects/repo-a/pull/7" ]
}

@test "candidates: all drafts → nothing" {
  run pr_auto_review_sweep_candidates <<<'[{"url":"https://github.com/petry-projects/repo-a/pull/1","isDraft":true}]'
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 0 ]
}
