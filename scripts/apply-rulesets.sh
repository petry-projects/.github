#!/usr/bin/env bash
# apply-rulesets.sh — Apply standard repository rulesets to petry-projects repos
#
# Companion script to compliance-audit.sh. Applies the rulesets defined in:
#   standards/github-settings.md#repository-rulesets
#
# Usage:
#   # Apply to a specific repo:
#   GH_TOKEN=<admin-token> ./scripts/apply-rulesets.sh <repo-name>
#
#   # Apply to all non-archived org repos:
#   GH_TOKEN=<admin-token> ./scripts/apply-rulesets.sh --all
#
#   # Dry run (show what would be applied):
#   DRY_RUN=true GH_TOKEN=<admin-token> ./scripts/apply-rulesets.sh <repo-name>
#
# Requirements:
#   - GH_TOKEN must have admin:org scope (or be an org admin)
#   - gh CLI and jq must be installed

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
  echo "  GH_TOKEN   GitHub token with admin:org scope (required)"
  echo "  DRY_RUN    Set to 'true' to preview changes without applying (default: false)"
  exit 1
}

# ---------------------------------------------------------------------------
# Ruleset payloads
# ---------------------------------------------------------------------------

# pr-quality ruleset per standards/github-settings.md#pr-quality--standard-ruleset-all-repositories
#
# Settings:
#   - Target: default branch
#   - Enforcement: active
#   - Required approving reviews: 1
#   - Dismiss stale reviews on push: Yes
#   - Required review thread resolution: Yes
#   - Require code owner review: Yes
#   - Require last push approval: Yes
#   - Allowed merge methods: Squash only (via required_linear_history)
#   - Allow force pushes: No
#   - Allow deletions: No
pr_quality_payload() {
  jq -n '{
    name: "pr-quality",
    target: "branch",
    enforcement: "active",
    conditions: {
      ref_name: {
        include: ["~DEFAULT_BRANCH"],
        exclude: []
      }
    },
    rules: [
      {
        type: "deletion"
      },
      {
        type: "non_fast_forward"
      },
      {
        type: "required_linear_history"
      },
      {
        type: "pull_request",
        parameters: {
          required_approving_review_count: 1,
          dismiss_stale_reviews_on_push: true,
          require_code_owner_review: true,
          require_last_push_approval: true,
          required_review_thread_resolution: true
        }
      }
    ],
    bypass_actors: [
      {
        actor_id: 1,
        actor_type: "OrganizationAdmin",
        bypass_mode: "always"
      }
    ]
  }'
}

# ---------------------------------------------------------------------------
# Apply functions
# ---------------------------------------------------------------------------

apply_pr_quality_ruleset() {
  local repo="$1"
  info "Applying pr-quality ruleset to $ORG/$repo ..."

  # Check if the ruleset already exists
  local existing_id
  existing_id=$(gh api "repos/$ORG/$repo/rulesets" \
    --jq '.[] | select(.name == "pr-quality") | .id' 2>/dev/null || echo "")

  local payload
  payload=$(pr_quality_payload)

  if [ "$DRY_RUN" = "true" ]; then
    if [ -n "$existing_id" ]; then
      skip "DRY_RUN=true — would update existing pr-quality ruleset (id: $existing_id) on $ORG/$repo"
    else
      skip "DRY_RUN=true — would create pr-quality ruleset on $ORG/$repo"
    fi
    echo "$payload" | jq .
    return 0
  fi

  if [ -n "$existing_id" ]; then
    info "Updating existing pr-quality ruleset (id: $existing_id) on $ORG/$repo"
    echo "$payload" | gh api -X PUT "repos/$ORG/$repo/rulesets/$existing_id" --input - > /dev/null
    ok "pr-quality ruleset updated on $ORG/$repo"
  else
    info "Creating pr-quality ruleset on $ORG/$repo"
    echo "$payload" | gh api -X POST "repos/$ORG/$repo/rulesets" --input - > /dev/null
    ok "pr-quality ruleset created on $ORG/$repo"
  fi
}

apply_rulesets() {
  local repo="$1"
  info "Processing $ORG/$repo ..."
  apply_pr_quality_ruleset "$repo"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if [ $# -eq 0 ]; then
  usage
fi

if [ -z "${GH_TOKEN:-}" ]; then
  err "GH_TOKEN is required — provide a personal access token or GitHub App token with admin:org scope"
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
    apply_rulesets "$repo" || failed=$((failed + 1))
  done

  if [ "$failed" -gt 0 ]; then
    err "$failed repo(s) failed — check output above for details"
    exit 1
  fi

  ok "All repos processed successfully"
else
  apply_rulesets "$1"
fi
