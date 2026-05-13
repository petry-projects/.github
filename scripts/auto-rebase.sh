#!/usr/bin/env bash
# auto-rebase.sh — conflict-handling helpers for the auto-rebase workflow.
# Called from .github/workflows/auto-rebase-reusable.yml.
#
# All functions read REPO from the environment and accept explicit arguments
# for the values that vary per PR, making them unit-testable.
#
# Required env: GH_TOKEN, REPO
set -euo pipefail

# Post the "blocked by workflows permission" comment (idempotent).
# Returns 0 whether it posts or skips.
handle_permissions_block() {
  local pr_number="$1"
  local base_branch="$2"

  local sentinel="<!-- auto-rebase-blocked -->"
  local already_posted
  already_posted=$(gh pr view "$pr_number" --repo "$REPO" \
    --json comments --jq "[.comments[] | select(.body | contains(\"$sentinel\"))] | length")
  if [[ "$already_posted" -gt 0 ]]; then
    echo "  Skipping — blocked comment already posted"
    return 0
  fi

  echo "  Posting manual-rebase request (workflows permission missing)"
  local body="$sentinel"
  body+=$'\n'"**Auto-rebase blocked** — the base branch contains \`.github/workflows/\` changes"
  body+=" that require the \`workflows\` permission to merge into this branch,"
  body+=" but the auto-rebase workflow's token does not have that permission."
  body+=$'\n\n'"Please rebase this branch manually:"
  body+=$'\n'"\`\`\`"$'\n'"git fetch origin"
  body+=$'\n'"git rebase origin/$base_branch"
  body+=$'\n'"git push --force-with-lease"$'\n'"\`\`\`"
  gh pr comment "$pr_number" --repo "$REPO" --body "$body"
}

# Post a SHA-keyed conflict sentinel comment and fire a repository_dispatch
# event to trigger the claude-rebase job. Idempotent: skips if a comment with
# this exact sentinel (tied to the current base-branch HEAD SHA) already exists,
# so a new merge to the base branch resets the gate and allows Claude another attempt.
handle_conflict() {
  local pr_number="$1"
  local head_ref="$2"
  local base_branch="$3"

  # First 8 chars of the base branch HEAD SHA — changes with every merge.
  local base_sha
  base_sha=$(gh api "repos/$REPO/branches/$base_branch" --jq '.commit.sha' | cut -c1-8)

  # Sentinel is SHA-keyed so a new main commit resets idempotency for that PR.
  local sentinel="<!-- auto-rebase-conflict:$base_sha -->"
  local already_posted
  already_posted=$(gh pr view "$pr_number" --repo "$REPO" \
    --json comments --jq "[.comments[] | select(.body | contains(\"$sentinel\"))] | length")
  if [[ "$already_posted" -gt 0 ]]; then
    echo "  Skipping — conflict for $base_branch@$base_sha already dispatched"
    return 0
  fi

  echo "  Posting conflict comment and dispatching claude-rebase for $base_branch@$base_sha"
  local body="$sentinel"
  body+=$'\n'"**Auto-rebase failed — merge conflict** — this branch conflicts"
  body+=" with \`$base_branch\` and cannot be updated via the merge strategy."
  body+=$'\n\n'"Claude has been dispatched to attempt an agentic rebase with conflict resolution."
  body+=" If Claude's rebase also fails, resolve manually:"
  body+=$'\n'"\`\`\`"$'\n'"git fetch origin"
  body+=$'\n'"git rebase origin/$base_branch"
  body+=$'\n'"# resolve conflicts per file, then for each commit:"
  body+=$'\n'"git add <resolved-files>"$'\n'"git rebase --continue"$'\n'"git push --force-with-lease"$'\n'"\`\`\`"
  gh pr comment "$pr_number" --repo "$REPO" --body "$body"

  # repository_dispatch is one of two event types that GITHUB_TOKEN IS allowed
  # to trigger new workflow runs for (the other being workflow_dispatch).
  gh api "repos/$REPO/dispatches" \
    -X POST \
    -f event_type=claude-rebase \
    -F "client_payload[pr_number]=$pr_number" \
    -F "client_payload[head_ref]=$head_ref" \
    -F "client_payload[base_branch]=$base_branch"
}
