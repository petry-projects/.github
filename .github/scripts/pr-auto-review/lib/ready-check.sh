#!/usr/bin/env bash
# Ready-check decision logic for the pr-auto-review reusable workflow.
#
# These are pure, side-effect-free functions so they can be unit-tested with
# bats (see test/workflows/pr-auto-review/ready-check.bats). The reusable
# workflow sources this file and uses the predicate to decide whether a PR's
# CI checks satisfy the passing-gate before dispatching the review agent.
#
# Contract: see .github/scripts/pr-auto-review/README.md
# Pins issue #680.

# pr_auto_review_required_contexts
#   Reads a branch-rules JSON array on stdin (the response of
#   `GET /repos/{owner}/{repo}/rules/branches/{branch}`) and emits a compact
#   JSON array of the required status-check context names. Emits `[]` when
#   there is no required_status_checks rule or the input is not an array
#   (e.g. a `{"message": "Not Found"}` error body).
pr_auto_review_required_contexts() {
  jq -c '
    if type == "array" then
      [ .[]
        | select(.type == "required_status_checks")
        | .parameters?.required_status_checks?[]?
        | .context
        | select(type == "string")
      ]
    else
      []
    end
  '
}

# pr_auto_review_checks_ready REQUIRED_JSON SELF_NAME
#   Reads a checks JSON array on stdin (the response of
#   `gh pr checks --json bucket,name`; each element has .name and .bucket) and
#   decides whether the passing-gate is satisfied. Prints a one-line reason to
#   stdout. Returns 0 (ready) or 1 (not ready).
#
#   REQUIRED_JSON  JSON array of required status-check context names (may be []).
#   SELF_NAME      name of this workflow's own check run, excluded from the gate
#                  so an in-progress run does not block itself (may be "").
#
#   A check "matches" a required context when their names are equal, or when the
#   check name ends with " / <context>" (GitHub renders Actions checks as
#   "<workflow> / <job>" while rulesets store the bare job name), or the reverse.
#
#   Decision:
#     * REQUIRED_JSON non-empty → gate on the required contexts only. Not ready
#       if any required context has no matching check reported yet, or a matching
#       check is not in the "pass"/"skipping" bucket. Non-required contexts
#       (including cancelled advisory runs) are ignored entirely — issue #680.
#     * REQUIRED_JSON empty → fallback (option B): ignore the required set and
#       block only when a non-self check is failing or pending; "cancel",
#       "skipping" and "pass" are treated as non-blocking.
pr_auto_review_checks_ready() {
  local required_json="${1:-[]}" self_name="$2" decision reason
  local result
  result=$(jq -r \
    --argjson required "$required_json" \
    --arg self "$self_name" '
      def matches($ctx):
        .name as $n
        | ($n | type == "string") and (
            ($n == $ctx)
            or ($n | endswith(" / " + $ctx))
            or ($ctx | endswith(" / " + $n))
          );

      (map(select(.name != $self))) as $checks
      | if ($required | length) == 0 then
          ([ $checks[] | select(.bucket == "fail" or .bucket == "pending") ]) as $blocking
          | if ($blocking | length) > 0 then
              "not-ready\t\($blocking | length) non-passing check(s) and no required set — skipping"
            else
              "ready\tno required set; no failing or pending checks"
            end
        else
          ([ $required[] as $ctx
             | { ctx: $ctx, runs: [ $checks[] | select(matches($ctx)) ] } ]) as $req
          | ([ $req[] | select(.runs | length == 0) | .ctx ]) as $missing
          | ([ $req[] | .runs[] | select(.bucket != "pass" and .bucket != "skipping") ]) as $notpassing
          | if ($missing | length) > 0 then
              "not-ready\trequired check(s) not reported yet: \($missing | join(", "))"
            elif ($notpassing | length) > 0 then
              "not-ready\t\($notpassing | length) required check(s) not yet passing — skipping"
            else
              "ready\tall \($req | length) required check(s) passing"
            end
        end
    ')
  decision="${result%%$'\t'*}"
  reason="${result#*$'\t'}"
  echo "$reason"
  [[ "$decision" == "ready" ]]
}

# pr_auto_review_ready STATE IS_DRAFT CHECKS_JSON REQUIRED_JSON SELF_NAME \
#                      REVIEW_DECISION UNRESOLVED_COUNT
#   Unified, pure readiness core for the pr-auto-review reusable workflow. Given
#   the PR facts gathered by the workflow's I/O glue, it evaluates all four
#   readiness criteria in gate order and PRINTS the decision class on stdout —
#   one of the classes Layer 2 decision-telemetry consumes:
#     skip-draft, skip-checks-pending, skip-changes-requested,
#     skip-unresolved-threads, dispatched
#   Returns 0 iff the PR is ready to dispatch (class == dispatched), else 1.
#
#   The workflow does the I/O (gh / GraphQL) and echoes the returned class to
#   `$GITHUB_OUTPUT`; this function makes no external calls.
#
#   STATE             PR state, e.g. OPEN / CLOSED / MERGED (gh: .state).
#   IS_DRAFT          "true" when the PR is a draft (gh: .isDraft).
#   CHECKS_JSON       `gh pr checks --json bucket,name` payload (may be "" / []).
#   REQUIRED_JSON     required status-check contexts (from
#                     pr_auto_review_required_contexts; may be []).
#   SELF_NAME         this workflow's own check-run name, excluded from the gate.
#   REVIEW_DECISION   effective review decision (gh: .reviewDecision; may be "").
#   UNRESOLVED_COUNT  number of unresolved review threads (may be "" → 0).
#
#   Criteria are evaluated in order, so an earlier skip wins over a later one
#   (e.g. a draft PR that also has CHANGES_REQUESTED reports skip-draft). The
#   required-checks gate (#2) is delegated verbatim to pr_auto_review_checks_ready
#   so the required-vs-non-required behaviour (issue #680) is unchanged.
pr_auto_review_ready() {
  local state="$1" is_draft="$2" checks_json="${3:-[]}" required_json="${4:-[]}" \
        self_name="$5" review_decision="$6" unresolved_count="${7:-0}"

  # 1. PR must be open and not a draft.
  if [ "$state" != "OPEN" ] || [ "$is_draft" = "true" ]; then
    echo "skip-draft"
    return 1
  fi

  # 2. All REQUIRED CI checks must be completed and passing. No checks reported
  #    at all is treated as still-pending. The required-vs-non-required gate is
  #    delegated to pr_auto_review_checks_ready (issue #680, unchanged).
  [ -z "$checks_json" ] && checks_json="[]"
  local total
  total=$(printf '%s' "$checks_json" | jq 'length')
  if [ "$total" -eq 0 ] \
     || ! printf '%s' "$checks_json" \
          | pr_auto_review_checks_ready "$required_json" "$self_name" >/dev/null; then
    echo "skip-checks-pending"
    return 1
  fi

  # 3. Effective review decision must not be CHANGES_REQUESTED.
  if [ "$review_decision" = "CHANGES_REQUESTED" ]; then
    echo "skip-changes-requested"
    return 1
  fi

  # 4. No unresolved review threads.
  [ -z "$unresolved_count" ] && unresolved_count="0"
  if [ "$unresolved_count" -gt 0 ]; then
    echo "skip-unresolved-threads"
    return 1
  fi

  echo "dispatched"
  return 0
}
