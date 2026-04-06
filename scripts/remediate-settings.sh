#!/usr/bin/env bash
# remediate-settings.sh — Fix repository settings compliance issues
#
# Iterates over all petry-projects repositories and applies the standard
# settings defined in standards/github-settings.md.
#
# Usage:
#   ./scripts/remediate-settings.sh [--dry-run] [--repo <repo>]
#
# Options:
#   --dry-run     Print what would be changed without making changes
#   --repo <repo> Only remediate the specified repository
#
# Environment variables:
#   GH_TOKEN  — GitHub token with repo admin scope (required)

set -euo pipefail

ORG="petry-projects"
DRY_RUN=false
TARGET_REPO=""

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --repo)
      if [[ -z "${2:-}" ]]; then
        echo "Error: --repo requires a repository name argument" >&2
        exit 1
      fi
      TARGET_REPO="$2"
      shift 2
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Usage: $0 [--dry-run] [--repo <repo>]" >&2
      exit 1
      ;;
  esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()    { echo "[INFO]  $*"; }
changed() { echo "[FIXED] $*"; }
skipped() { echo "[SKIP]  $*"; }
dry()     { echo "[DRY]   $*"; }

gh_api() {
  gh api "$@" 2>/dev/null
}

patch_setting() {
  local repo="$1" field="$2" value="$3" description="$4"

  if [ "$DRY_RUN" = true ]; then
    dry "$repo: would set $field=$value ($description)"
    return
  fi

  gh api --method PATCH "repos/$ORG/$repo" -f "$field=$value" > /dev/null \
    && changed "$repo: $field=$value — $description" \
    || echo "[ERROR] $repo: failed to set $field=$value" >&2
}

# ---------------------------------------------------------------------------
# Remediate a single repository
# ---------------------------------------------------------------------------
remediate_repo() {
  local repo="$1"
  info "Checking $repo ..."

  local settings
  settings=$(gh_api "repos/$ORG/$repo" --jq '{
    has_discussions: .has_discussions,
    has_wiki: .has_wiki,
    has_issues: .has_issues,
    allow_auto_merge: .allow_auto_merge,
    delete_branch_on_merge: .delete_branch_on_merge
  }' 2>/dev/null || echo "{}")

  if [ "$settings" = "{}" ]; then
    echo "[ERROR] $repo: could not fetch settings (check token permissions)" >&2
    return
  fi

  # has_discussions should be true
  local has_discussions
  has_discussions=$(echo "$settings" | jq -r '.has_discussions')
  if [ "$has_discussions" != "true" ]; then
    patch_setting "$repo" "has_discussions" "true" "enable discussions for community engagement"
  else
    skipped "$repo: has_discussions already true"
  fi

  # has_wiki should be false
  local has_wiki
  has_wiki=$(echo "$settings" | jq -r '.has_wiki')
  if [ "$has_wiki" != "false" ]; then
    patch_setting "$repo" "has_wiki" "false" "disable wiki — documentation lives in the repo"
  else
    skipped "$repo: has_wiki already false"
  fi

  # has_issues should be true
  local has_issues
  has_issues=$(echo "$settings" | jq -r '.has_issues')
  if [ "$has_issues" != "true" ]; then
    patch_setting "$repo" "has_issues" "true" "enable issue tracking"
  else
    skipped "$repo: has_issues already true"
  fi

  # allow_auto_merge should be true
  local allow_auto_merge
  allow_auto_merge=$(echo "$settings" | jq -r '.allow_auto_merge')
  if [ "$allow_auto_merge" != "true" ]; then
    patch_setting "$repo" "allow_auto_merge" "true" "enable auto-merge for Dependabot workflow"
  else
    skipped "$repo: allow_auto_merge already true"
  fi

  # delete_branch_on_merge should be true
  local delete_branch_on_merge
  delete_branch_on_merge=$(echo "$settings" | jq -r '.delete_branch_on_merge')
  if [ "$delete_branch_on_merge" != "true" ]; then
    patch_setting "$repo" "delete_branch_on_merge" "true" "auto-delete head branches on merge"
  else
    skipped "$repo: delete_branch_on_merge already true"
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  if [ -n "$TARGET_REPO" ]; then
    remediate_repo "$TARGET_REPO"
    return
  fi

  info "Fetching all repositories for $ORG ..."
  local repos
  repos=$(gh api "orgs/$ORG/repos" --paginate --jq '.[].name' 2>/dev/null)

  if [ -z "$repos" ]; then
    echo "[ERROR] No repositories found or insufficient permissions." >&2
    exit 1
  fi

  while IFS= read -r repo; do
    remediate_repo "$repo"
  done <<< "$repos"

  info "Done."
}

main
