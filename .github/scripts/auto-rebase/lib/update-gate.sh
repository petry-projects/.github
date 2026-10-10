#!/usr/bin/env bash
# Update gate for the auto-rebase reusable workflow (issue #1272).
#
# Pure decision (no external calls, no sleeps): decides whether a PR that is
# BEHIND its base should actually be updated.
# Being merely behind blocks nothing unless one of these holds:
#
#   1. the base branch's effective rules require branches to be up to date
#      (strict required status checks — from rulesets or classic protection);
#   2. the PR is in, or is being added to, a merge queue;
#   3. the PR carries the maintainer opt-in label (`ready_label` input).
#
# A conflicting PR is still attempted so the reusable's existing conflict
# notice → dev-lead recovery path fires. Anything that cannot be read fails
# safe to the pre-gate behaviour (update) and says so.
#
# Facts are gathered by lib/gate-facts.sh (the I/O glue).
#
# Tested by test/workflows/auto-rebase/update-gate.bats.
# Contract: see .github/scripts/auto-rebase/README.md

# auto_rebase_gate_decide STRICT IN_QUEUE HAS_LABEL MERGEABLE LABEL
#   Pure decision. Prints the reason and returns:
#     0  update (a blocking condition applies, the PR conflicts, or the gate
#        could not be evaluated — fail safe to the pre-gate behaviour)
#     1  skip (none applied)
#     3  undecided: nothing else applies and mergeability is not yet computed
auto_rebase_gate_decide() {
  local strict="$1" in_queue="$2" has_label="$3" mergeable="$4" label="$5"

  if [[ "$strict" == "true" ]]; then
    echo "base branch rules require branches to be up to date"
    return 0
  fi
  if [[ "$in_queue" == "true" ]]; then
    echo "PR is in or being added to a merge queue"
    return 0
  fi
  if [[ "$has_label" == "true" ]]; then
    echo "label '${label}' present"
    return 0
  fi
  if [[ "$strict" != "false" ]]; then
    echo "could not evaluate (base branch rules unreadable) — updating as before"
    return 0
  fi
  if [[ "$in_queue" != "false" || "$has_label" != "false" ]]; then
    echo "could not evaluate (PR merge-queue/label state unreadable) — updating as before"
    return 0
  fi
  case "$mergeable" in
    CONFLICTING)
      echo "merge conflict — attempting so the conflict notice is posted"
      return 0
      ;;
    MERGEABLE)
      echo "none applied (strict up-to-date not required, not in a merge queue, no '${label:-<none>}' label)"
      return 1
      ;;
    *)
      echo "mergeability not yet computed"
      return 3
      ;;
  esac
}
