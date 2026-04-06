#!/usr/bin/env bash
# apply-repo-settings.sh — Apply standard repository settings to a petry-projects repo
#
# Usage:
#   ./scripts/apply-repo-settings.sh <repo>          # apply to one repo
#   ./scripts/apply-repo-settings.sh --all           # apply to all non-archived repos
#
# Environment variables:
#   GH_TOKEN   — GitHub token with repo admin scope (required)
#   DRY_RUN    — set to "true" to print changes without applying (default: false)
#
# Standard settings applied:
#   delete_branch_on_merge: true   (auto-delete head branches after merge)
#   allow_auto_merge:       true   (required for Dependabot auto-merge workflow)
#   has_wiki:               false  (documentation lives in the repo)
#   has_issues:             true   (issue tracking must be enabled)
#
# Reference: standards/github-settings.md#repository-settings--standard-defaults

set -euo pipefail

ORG="petry-projects"
DRY_RUN="${DRY_RUN:-false}"

usage() {
  echo "Usage: $0 <repo-name>  OR  $0 --all" >&2
  echo "  GH_TOKEN must be set to a token with repo admin scope." >&2
  exit 1
}

apply_settings() {
  local repo="$1"

  echo "[INFO] Checking $ORG/$repo ..."

  # Fetch current settings
  local current
  current=$(gh api "repos/$ORG/$repo" --jq '{
    delete_branch_on_merge: .delete_branch_on_merge,
    allow_auto_merge: .allow_auto_merge,
    has_wiki: .has_wiki,
    has_issues: .has_issues
  }' 2>/dev/null || echo "{}")

  if [ "$current" = "{}" ]; then
    echo "[WARN] Could not fetch settings for $ORG/$repo — skipping" >&2
    return
  fi

  local delete_branch allow_auto_merge has_wiki has_issues
  delete_branch=$(echo "$current" | jq -r '.delete_branch_on_merge // "null"')
  allow_auto_merge=$(echo "$current" | jq -r '.allow_auto_merge // "null"')
  has_wiki=$(echo "$current" | jq -r '.has_wiki // "null"')
  has_issues=$(echo "$current" | jq -r '.has_issues // "null"')

  local needs_update=false
  local update_args=()

  if [ "$delete_branch" != "true" ]; then
    echo "[INFO]   delete_branch_on_merge: $delete_branch → true"
    update_args+=(-F delete_branch_on_merge=true)
    needs_update=true
  fi

  if [ "$allow_auto_merge" != "true" ]; then
    echo "[INFO]   allow_auto_merge: $allow_auto_merge → true"
    update_args+=(-F allow_auto_merge=true)
    needs_update=true
  fi

  if [ "$has_wiki" != "false" ]; then
    echo "[INFO]   has_wiki: $has_wiki → false"
    update_args+=(-F has_wiki=false)
    needs_update=true
  fi

  if [ "$has_issues" != "true" ]; then
    echo "[INFO]   has_issues: $has_issues → true"
    update_args+=(-F has_issues=true)
    needs_update=true
  fi

  if [ "$needs_update" = "false" ]; then
    echo "[INFO]   All standard settings already applied — no changes needed."
    return
  fi

  if [ "$DRY_RUN" = "true" ]; then
    echo "[DRY RUN] Would apply ${#update_args[@]} change(s) to $ORG/$repo"
    return
  fi

  gh api --method PATCH "repos/$ORG/$repo" "${update_args[@]}" --jq '.full_name' > /dev/null
  echo "[OK]   Applied settings to $ORG/$repo"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if [ $# -eq 0 ]; then
  usage
fi

if [ "$1" = "--all" ]; then
  echo "[INFO] Applying standard settings to all non-archived repos in $ORG ..."
  repos=$(gh repo list "$ORG" --no-archived --json name -q '.[].name' --limit 500)
  for repo in $repos; do
    apply_settings "$repo"
  done
else
  # Strip org prefix if provided (e.g., "petry-projects/.github" → ".github")
  repo="${1#"$ORG/"}"
  apply_settings "$repo"
fi

echo "[INFO] Done."
