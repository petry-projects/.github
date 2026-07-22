#!/usr/bin/env bats
# Tests for the pure catch-up-sweep decision core in
# .github/scripts/pr-auto-review/lib/sweep.sh
#
# The catch-up sweep re-evaluates open PRs the event-driven pr-auto-review path
# may have missed and dispatches the review agent for the ready ones. These
# functions are the pure, side-effect-free core (mirroring lib/ready-check.sh),
# so the four robustness properties from issue #872 are unit-testable without a
# live gh:
#
#   1. cap on the number DISPATCHED (ready), not candidates considered
#      → pr_auto_review_sweep_plan            (anti-starvation)
#   2. full pagination of the labeled-PR search
#      → pr_auto_review_sweep_page_full / pr_auto_review_sweep_merge_pages
#   3. a failed search surfaces an error, is not treated as "nothing to do"
#      → pr_auto_review_sweep_valid_search
#   4. a malformed payload is guarded and does not abort the whole run
#      → pr_auto_review_sweep_extract
#
#   plus deterministic oldest-first ordering so ready PRs are not starved
#      → pr_auto_review_sweep_order

load 'helpers/setup'

setup() {
  # shellcheck source=/dev/null
  . "${TT_SCRIPTS_DIR}/lib/sweep.sh"
  # Export so `bash -c` subshells used to drive stdin/pipes see the functions.
  export -f pr_auto_review_sweep_valid_search pr_auto_review_sweep_extract \
    pr_auto_review_sweep_page_full pr_auto_review_sweep_merge_pages \
    pr_auto_review_sweep_order pr_auto_review_sweep_plan
}

# ── #872 finding 1: cap on DISPATCHED, not candidates considered ──────────────

# The starvation bug: MAX_PER_RUN applied to candidates BEFORE readiness means a
# run of older non-ready PRs consumes every slot and starves newer ready ones.
# The fix caps on the count dispatched, so non-ready candidates consume no slot.
@test "plan: older non-ready candidates do not consume dispatch slots (anti-starvation)" {
  input='[{"number":10,"ready":false},{"number":11,"ready":false},{"number":20,"ready":true},{"number":21,"ready":true}]'
  run bash -c 'printf "%s" '"'$input'"' | pr_auto_review_sweep_plan 2'
  [ "$status" -eq 0 ]
  # Both ready PRs dispatch even though 2 non-ready ones preceded them.
  [ "${lines[0]}" = "20" ]
  [ "${lines[1]}" = "21" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "plan: dispatches at most MAX ready PRs" {
  input='[{"number":1,"ready":true},{"number":2,"ready":true},{"number":3,"ready":true},{"number":4,"ready":true}]'
  run bash -c 'printf "%s" '"'$input'"' | pr_auto_review_sweep_plan 2'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "1" ]
  [ "${lines[1]}" = "2" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "plan: fewer ready than MAX dispatches all ready" {
  input='[{"number":1,"ready":false},{"number":2,"ready":true},{"number":3,"ready":false}]'
  run bash -c 'printf "%s" '"'$input'"' | pr_auto_review_sweep_plan 5'
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "2" ]
  [ "${#lines[@]}" -eq 1 ]
}

@test "plan: no ready candidates dispatches nothing" {
  input='[{"number":1,"ready":false},{"number":2,"ready":false}]'
  run bash -c 'printf "%s" '"'$input'"' | pr_auto_review_sweep_plan 3'
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "plan: MAX of 0 dispatches nothing" {
  input='[{"number":1,"ready":true},{"number":2,"ready":true}]'
  run bash -c 'printf "%s" '"'$input'"' | pr_auto_review_sweep_plan 0'
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

@test "plan: empty candidate array dispatches nothing" {
  run bash -c 'printf "[]" | pr_auto_review_sweep_plan 5'
  [ "$status" -eq 0 ]
  [ "$output" = "" ]
}

# ── #872 finding 5 (ordering): oldest-first so ready PRs are not starved ──────

@test "order: sorts candidates oldest updatedAt first" {
  input='[{"number":2,"updatedAt":"2026-07-20T00:00:00Z"},{"number":1,"updatedAt":"2026-07-18T00:00:00Z"},{"number":3,"updatedAt":"2026-07-22T00:00:00Z"}]'
  run bash -c 'printf "%s" '"'$input'"' | pr_auto_review_sweep_order | jq -c "[.[].number]"'
  [ "$status" -eq 0 ]
  [ "$output" = "[1,2,3]" ]
}

@test "order: ties on updatedAt break by number ascending" {
  input='[{"number":9,"updatedAt":"2026-07-20T00:00:00Z"},{"number":4,"updatedAt":"2026-07-20T00:00:00Z"}]'
  run bash -c 'printf "%s" '"'$input'"' | pr_auto_review_sweep_order | jq -c "[.[].number]"'
  [ "$status" -eq 0 ]
  [ "$output" = "[4,9]" ]
}

# ── #872 finding 2: full pagination (no 100-item cliff) ───────────────────────

@test "page_full: a full page signals more pages may exist (exit 0)" {
  run pr_auto_review_sweep_page_full 100 100
  [ "$status" -eq 0 ]
}

@test "page_full: a short page signals the last page (exit 1)" {
  run pr_auto_review_sweep_page_full 37 100
  [ "$status" -eq 1 ]
}

@test "page_full: an empty page signals the last page (exit 1)" {
  run pr_auto_review_sweep_page_full 0 100
  [ "$status" -eq 1 ]
}

@test "merge_pages: concatenated pages merge and dedupe by number" {
  page1='[{"number":1,"updatedAt":"2026-07-18T00:00:00Z"},{"number":2,"updatedAt":"2026-07-19T00:00:00Z"}]'
  page2='[{"number":2,"updatedAt":"2026-07-19T00:00:00Z"},{"number":3,"updatedAt":"2026-07-20T00:00:00Z"}]'
  run bash -c 'printf "%s\n%s" '"'$page1'"' '"'$page2'"' | pr_auto_review_sweep_merge_pages | jq -c "[.[].number]"'
  [ "$status" -eq 0 ]
  [ "$output" = "[1,2,3]" ]
}

@test "merge_pages: a single page passes through unchanged in count" {
  page='[{"number":5,"updatedAt":"2026-07-18T00:00:00Z"}]'
  run bash -c 'printf "%s" '"'$page'"' | pr_auto_review_sweep_merge_pages | jq "length"'
  [ "$status" -eq 0 ]
  [ "$output" = "1" ]
}

# ── #872 finding 3: a failed search surfaces, not silently empty ──────────────

@test "valid_search: a valid (even empty) JSON array is accepted" {
  run bash -c 'printf "[]" | pr_auto_review_sweep_valid_search'
  [ "$status" -eq 0 ]
  run bash -c 'printf "%s" "[{\"number\":1}]" | pr_auto_review_sweep_valid_search'
  [ "$status" -eq 0 ]
}

@test "valid_search: an API error object is rejected (surface, do not no-op)" {
  run bash -c 'printf "%s" "{\"message\":\"Bad credentials\"}" | pr_auto_review_sweep_valid_search'
  [ "$status" -ne 0 ]
}

@test "valid_search: an empty string is rejected" {
  run bash -c 'printf "" | pr_auto_review_sweep_valid_search'
  [ "$status" -ne 0 ]
}

@test "valid_search: malformed JSON is rejected" {
  run bash -c 'printf "%s" "{not json" | pr_auto_review_sweep_valid_search'
  [ "$status" -ne 0 ]
}

# ── #872 finding 4: a malformed payload is guarded, does not abort the run ────

@test "extract: a well-formed search payload yields number+updatedAt candidates" {
  payload='[{"number":7,"updatedAt":"2026-07-20T00:00:00Z","title":"x","author":{"login":"a"}}]'
  run bash -c 'printf "%s" '"'$payload'"' | pr_auto_review_sweep_extract'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].number == 7 and .[0].updatedAt == "2026-07-20T00:00:00Z"'
}

@test "extract: accepts the REST search field name updated_at" {
  payload='[{"number":8,"updated_at":"2026-07-19T00:00:00Z","title":"y"}]'
  run bash -c 'printf "%s" '"'$payload'"' | pr_auto_review_sweep_extract'
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.[0].number == 8 and .[0].updatedAt == "2026-07-19T00:00:00Z"'
}

@test "extract: a malformed payload returns non-zero instead of aborting" {
  run bash -c 'printf "%s" "{oops" | pr_auto_review_sweep_extract'
  [ "$status" -ne 0 ]
}

@test "extract: a non-array payload returns non-zero" {
  run bash -c 'printf "%s" "{\"message\":\"Not Found\"}" | pr_auto_review_sweep_extract'
  [ "$status" -ne 0 ]
}

# The guard's purpose: even under `set -e`, a malformed payload must be catchable
# so the caller can continue rather than have the whole sweep aborted by jq.
@test "extract: guarded call under set -e lets the caller continue past a bad payload" {
  run bash -c '
    set -euo pipefail
    . "'"${TT_SCRIPTS_DIR}"'/lib/sweep.sh"
    if printf "%s" "{bad" | pr_auto_review_sweep_extract >/dev/null 2>&1; then
      echo "unexpected-success"
    else
      echo "handled-and-continued"
    fi
  '
  [ "$status" -eq 0 ]
  [ "$output" = "handled-and-continued" ]
}
