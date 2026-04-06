#!/usr/bin/env bash
# apply-repo-settings.sh — Apply standard repository settings to org repos
#
# Applies the settings defined in standards/github-settings.md to one or all
# repositories in the petry-projects org. Useful for remediating compliance
# findings from the weekly audit.
#
# Usage:
#   GH_TOKEN=<token> bash scripts/apply-repo-settings.sh [repo-name]
#
#   If repo-name is omitted, applies to all non-archived repos in the org.
#
# Required token scopes: repo (or public_repo for public repos)
#
# Environment variables:
#   GH_TOKEN    — GitHub token with repo write scope (required)
#   DRY_RUN     — set to "true" to preview changes without applying (default: false)

set -euo pipefail

ORG="petry-projects"
DRY_RUN="${DRY_RUN:-false}"
TARGET_REPO="${1:-}"

info() { echo "[INFO] $*" >&2; }
warn() { echo "[WARN] $*" >&2; }
success() { echo "[OK]   $*" >&2; }

apply_settings() {
  local repo="$1"
  local full_repo="$ORG/$repo"

  info "Applying standard settings to $full_repo ..."

  # Verify repo exists and is accessible
  if ! gh api "repos/$full_repo" --jq '.name' > /dev/null 2>&1; then
    warn "Cannot access $full_repo — skipping (check token permissions)"
    return 1
  fi

  # Read current settings
  local current
  current=$(gh api "repos/$full_repo" --jq '{
    has_wiki: .has_wiki,
    allow_auto_merge: .allow_auto_merge,
    delete_branch_on_merge: .delete_branch_on_merge
  }' 2>/dev/null || echo "{}")

  local has_wiki allow_auto_merge delete_branch_on_merge
  has_wiki=$(echo "$current" | jq -r '.has_wiki')
  allow_auto_merge=$(echo "$current" | jq -r '.allow_auto_merge')
  delete_branch_on_merge=$(echo "$current" | jq -r '.delete_branch_on_merge')

  local changes=()
  local payload="{}"

  # has_wiki: must be false
  if [ "$has_wiki" != "false" ]; then
    changes+=("has_wiki: $has_wiki → false")
    payload=$(echo "$payload" | jq '. + {"has_wiki": false}')
  fi

  # allow_auto_merge: must be true
  if [ "$allow_auto_merge" != "true" ]; then
    changes+=("allow_auto_merge: $allow_auto_merge → true")
    payload=$(echo "$payload" | jq '. + {"allow_auto_merge": true}')
  fi

  # delete_branch_on_merge: must be true
  if [ "$delete_branch_on_merge" != "true" ]; then
    changes+=("delete_branch_on_merge: $delete_branch_on_merge → true")
    payload=$(echo "$payload" | jq '. + {"delete_branch_on_merge": true}')
  fi

  if [ ${#changes[@]} -eq 0 ]; then
    success "$full_repo — already compliant, no changes needed"
    return 0
  fi

  info "Changes to apply to $full_repo:"
  for change in "${changes[@]}"; do
    info "  - $change"
  done

  if [ "$DRY_RUN" = "true" ]; then
    info "DRY_RUN=true — skipping API call for $full_repo"
    return 0
  fi

  # Apply the settings patch
  if gh api "repos/$full_repo" \
    --method PATCH \
    --input <(echo "$payload") \
    --jq '.full_name' > /dev/null 2>&1; then
    success "$full_repo — settings applied: ${changes[*]}"
  else
    warn "$full_repo — failed to apply settings (check token permissions)"
    return 1
  fi
}

main() {
  if [ -z "${GH_TOKEN:-}" ]; then
    echo "ERROR: GH_TOKEN is required" >&2
    echo "Usage: GH_TOKEN=<token> bash scripts/apply-repo-settings.sh [repo-name]" >&2
    exit 1
  fi

  info "Org: $ORG"
  info "Dry run: $DRY_RUN"

  if [ -n "$TARGET_REPO" ]; then
    # Strip org prefix if provided
    TARGET_REPO="${TARGET_REPO#"$ORG/"}"
    info "Target: $TARGET_REPO"
    apply_settings "$TARGET_REPO"
  else
    info "Target: all non-archived repos"
    local repos
    repos=$(gh repo list "$ORG" --no-archived --json name -q '.[].name' --limit 500)

    if [ -z "$repos" ]; then
      warn "No repositories found in $ORG — check GH_TOKEN permissions"
      exit 1
    fi

    local ok=0 failed=0
    for repo in $repos; do
      if apply_settings "$repo"; then
        ok=$((ok + 1))
      else
        failed=$((failed + 1))
      fi
    done

    info "Done — $ok repo(s) processed, $failed failed"
    [ "$failed" -gt 0 ] && exit 1
  fi
}

main "$@"
