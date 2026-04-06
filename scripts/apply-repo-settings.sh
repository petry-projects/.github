#!/usr/bin/env bash
# apply-repo-settings.sh — Apply standard repository settings to petry-projects repos
#
# Usage:
#   ./scripts/apply-repo-settings.sh [repo-name]
#
# If no repo is given, applies settings to all non-archived repos in the org.
# Settings are sourced from: standards/github-settings.md
#
# Environment variables:
#   GH_TOKEN  — GitHub token with repo admin scope (required)
#
# Example:
#   GH_TOKEN=ghp_... ./scripts/apply-repo-settings.sh .github

set -euo pipefail

ORG="petry-projects"

info()  { echo "[INFO] $*" >&2; }
warn()  { echo "[WARN] $*" >&2; }
err()   { echo "[ERROR] $*" >&2; }

# ---------------------------------------------------------------------------
# Apply standard settings to a single repository
# Returns 0 on success, 1 on failure
# ---------------------------------------------------------------------------
apply_settings() {
  local repo="$1"
  local full_repo="$ORG/$repo"

  info "Applying settings to $full_repo"

  # Standard settings from standards/github-settings.md#merge-settings
  if gh api --method PATCH "/repos/$full_repo" \
      -f allow_auto_merge=true \
      -f delete_branch_on_merge=true \
      -f allow_squash_merge=true \
      -f allow_merge_commit=true \
      -f allow_rebase_merge=true \
      -f squash_merge_commit_title=PR_TITLE \
      -f squash_merge_commit_message=COMMIT_MESSAGES \
      --jq '"  allow_auto_merge=\(.allow_auto_merge), delete_branch_on_merge=\(.delete_branch_on_merge)"' \
      2>/dev/null; then
    info "  Settings applied successfully to $repo"
    return 0
  else
    warn "  Failed to apply settings to $repo (check GH_TOKEN has admin:repo scope)"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  if [ -z "${GH_TOKEN:-}" ]; then
    err "GH_TOKEN environment variable is required"
    exit 1
  fi

  local target="${1:-}"

  if [ -n "$target" ]; then
    apply_settings "$target"
    return
  fi

  info "No repo specified — applying settings to all non-archived repos in $ORG"
  local repos
  repos=$(gh repo list "$ORG" --no-archived --json name -q '.[].name' --limit 500)

  if [ -z "$repos" ]; then
    warn "No repositories found in $ORG — check GH_TOKEN permissions"
    exit 1
  fi

  local success=0
  local failed=0

  for repo in $repos; do
    if apply_settings "$repo"; then
      success=$((success + 1))
    else
      failed=$((failed + 1))
    fi
  done

  info "Done. Applied: $success, Failed: $failed"
}

main "$@"
