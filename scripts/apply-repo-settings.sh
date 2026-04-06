#!/usr/bin/env bash
# apply-repo-settings.sh — Apply standard repository settings to petry-projects repos
#
# Companion script to compliance-audit.sh. Applies the settings defined in:
#   standards/github-settings.md#repository-settings--standard-defaults
#
# Usage:
#   # Apply to a specific repo:
#   GH_TOKEN=<admin-token> ./scripts/apply-repo-settings.sh <repo-name>
#
#   # Apply to all non-archived org repos:
#   GH_TOKEN=<admin-token> ./scripts/apply-repo-settings.sh --all
#
#   # Dry run (show what would be changed):
#   DRY_RUN=true GH_TOKEN=<admin-token> ./scripts/apply-repo-settings.sh <repo-name>
#
# Requirements:
#   - GH_TOKEN must have admin:repo scope (or be an admin of the org)
#   - gh CLI must be installed

set -euo pipefail

ORG="petry-projects"
DRY_RUN="${DRY_RUN:-false}"

info()  { echo "[INFO]  $*"; }
ok()    { echo "[OK]    $*"; }
err()   { echo "[ERROR] $*" >&2; }
skip()  { echo "[SKIP]  $*"; }

usage() {
  echo "Usage: $0 <repo-name>"
  echo "       $0 --all"
  echo ""
  echo "Environment variables:"
  echo "  GH_TOKEN   GitHub token with admin:repo scope (required)"
  echo "  DRY_RUN    Set to 'true' to preview changes without applying (default: false)"
  exit 1
}

apply_settings() {
  local repo="$1"
  info "Applying standard settings to $ORG/$repo ..."

  # Fetch current settings
  local current
  current=$(gh api "repos/$ORG/$repo" --jq '{
    allow_auto_merge: .allow_auto_merge,
    delete_branch_on_merge: .delete_branch_on_merge,
    allow_squash_merge: .allow_squash_merge,
    allow_merge_commit: .allow_merge_commit,
    allow_rebase_merge: .allow_rebase_merge,
    squash_merge_commit_title: .squash_merge_commit_title,
    squash_merge_commit_message: .squash_merge_commit_message
  }' 2>/dev/null || echo "{}")

  if [ "$current" = "{}" ]; then
    err "Could not fetch settings for $ORG/$repo — check token permissions and repo name"
    return 1
  fi

  # Standard settings from standards/github-settings.md#merge-settings
  declare -A EXPECTED=(
    [allow_auto_merge]="true"
    [delete_branch_on_merge]="true"
    [allow_squash_merge]="true"
    [allow_merge_commit]="true"
    [allow_rebase_merge]="true"
  )

  local needs_patch=false
  local patch_args=()

  for key in "${!EXPECTED[@]}"; do
    local actual
    actual=$(echo "$current" | jq -r ".$key // \"null\"")
    local expected="${EXPECTED[$key]}"

    if [ "$actual" != "$expected" ]; then
      info "  $key: $actual → $expected"
      needs_patch=true
      patch_args+=(-F "$key=$expected")
    else
      ok "  $key: already $actual"
    fi
  done

  # Check string settings separately (jq -f flag for strings)
  local squash_title
  squash_title=$(echo "$current" | jq -r '.squash_merge_commit_title // "null"')
  if [ "$squash_title" != "PR_TITLE" ]; then
    info "  squash_merge_commit_title: $squash_title → PR_TITLE"
    needs_patch=true
    patch_args+=(-f squash_merge_commit_title=PR_TITLE)
  else
    ok "  squash_merge_commit_title: already PR_TITLE"
  fi

  local squash_msg
  squash_msg=$(echo "$current" | jq -r '.squash_merge_commit_message // "null"')
  if [ "$squash_msg" != "COMMIT_MESSAGES" ]; then
    info "  squash_merge_commit_message: $squash_msg → COMMIT_MESSAGES"
    needs_patch=true
    patch_args+=(-f squash_merge_commit_message=COMMIT_MESSAGES)
  else
    ok "  squash_merge_commit_message: already COMMIT_MESSAGES"
  fi

  if [ "$needs_patch" = false ]; then
    ok "$ORG/$repo is already fully compliant — no changes needed"
    return 0
  fi

  if [ "$DRY_RUN" = "true" ]; then
    skip "DRY_RUN=true — skipping PATCH for $ORG/$repo"
    return 0
  fi

  gh api -X PATCH "repos/$ORG/$repo" "${patch_args[@]}" > /dev/null
  ok "$ORG/$repo settings updated successfully"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if [ $# -eq 0 ]; then
  usage
fi

if [ -z "${GH_TOKEN:-}" ]; then
  err "GH_TOKEN is required — provide a personal access token or GitHub App token with admin:repo scope"
  exit 1
fi

export GH_TOKEN

if [ "$1" = "--all" ]; then
  info "Fetching all non-archived repos in $ORG ..."
  repos=$(gh repo list "$ORG" --no-archived --json name -q '.[].name' --limit 500)

  if [ -z "$repos" ]; then
    err "No repositories found in $ORG — check GH_TOKEN permissions"
    exit 1
  fi

  failed=0
  for repo in $repos; do
    apply_settings "$repo" || failed=$((failed + 1))
  done

  if [ "$failed" -gt 0 ]; then
    err "$failed repo(s) failed — check output above for details"
    exit 1
  fi

  ok "All repos processed successfully"
else
  apply_settings "$1"
fi
