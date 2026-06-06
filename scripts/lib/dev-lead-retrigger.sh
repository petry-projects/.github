#!/usr/bin/env bash
# dev-lead-retrigger.sh — shared helpers for re-engaging the dev-lead agent on a
# compliance issue by cycling its trigger label.
#
# Sourced by:
#   scripts/compliance-audit.sh      — weekly audit; re-triggers findings that
#                                      persist across runs (issue still open).
#   scripts/compliance-retrigger.sh  — daily sweep; re-triggers stale issues.
#
# Why a shared lib?
#   Both entry points need the same two primitives, and both depend on how
#   dev-lead names its branches (dev-lead/issue-<number>-<timestamp>, see
#   scripts/dev-lead-fix-issue.sh in the agent repo). Keeping that convention in
#   one place stops the two callers from drifting apart.
#
# These functions are pure helpers: they take all inputs as arguments and call
# `gh api` directly, so they do not depend on the sourcing script's own wrappers
# or globals.

# dl_dev_lead_active <org> <repo> <issue>
# Returns 0 (true) if dev-lead is ALREADY working this issue — either an open PR
# exists on a dev-lead/issue-<number>-* branch, or the issue carries the
# `in-progress` label. In that case the caller must NOT cycle the trigger label,
# to avoid interrupting or duplicating active work.
dl_dev_lead_active() {
  local org="$1" repo="$2" issue="$3"

  # Match the dev-lead branch exactly: "dev-lead/issue-<n>-<timestamp>".
  # Require the trailing "-" so issue 1 does not match branch "issue-12-...".
  local pr_count
  pr_count=$(gh api "repos/$org/$repo/pulls?state=open" \
    --jq "[.[] | select(.head.ref | type == \"string\" and startswith(\"dev-lead/issue-${issue}-\"))] | length" \
    2>/dev/null || echo "0")
  [ "${pr_count:-0}" -gt 0 ] && return 0

  # An agent currently mid-run marks the issue `in-progress` before it pushes a
  # PR — respect that window too.
  local in_progress
  in_progress=$(gh api "repos/$org/$repo/issues/$issue" \
    --jq '.labels[].name | select(. == "in-progress")' \
    2>/dev/null || echo "")
  [ -n "$in_progress" ] && return 0

  return 1
}

# dl_cycle_trigger_label <org> <repo> <issue> <label> [dry_run]
# Remove then re-add <label> so GitHub emits a fresh issues:labeled event,
# re-engaging dev-lead. dev-lead fires once per label application, so a
# persistent finding whose label is already present needs the label cycled to be
# picked up again. Returns non-zero if the re-add fails (the caller can fall
# back to ensuring the label is at least present).
dl_cycle_trigger_label() {
  local org="$1" repo="$2" issue="$3" label="$4" dry_run="${5:-false}"

  if [ "$dry_run" = "true" ]; then
    echo "[dry-run] would cycle '$label' on $org/$repo#$issue" >&2
    return 0
  fi

  gh api -X DELETE "repos/$org/$repo/issues/$issue/labels/$label" >/dev/null 2>&1 || true
  # Let GitHub register the removal before re-adding so the add is not coalesced
  # with the delete (which would emit no labeled event).
  sleep 1
  gh api -X POST "repos/$org/$repo/issues/$issue/labels" \
    --field "labels[]=$label" >/dev/null 2>&1 || return 1
}
