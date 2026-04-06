#!/usr/bin/env bash
# setup-branch-protection.sh — Create or update branch protection rulesets
# for petry-projects repos that are missing them.
#
# Applies the rulesets defined in:
#   standards/github-settings.md#repository-rulesets
#
# Usage:
#   # Apply to a specific repo:
#   GH_TOKEN=<admin-token> ./scripts/setup-branch-protection.sh <repo-name>
#
#   # Apply to all unprotected repos (.github and bmad-bgreat-suite):
#   GH_TOKEN=<admin-token> ./scripts/setup-branch-protection.sh --default
#
#   # Dry run (show what would be changed without applying):
#   DRY_RUN=true GH_TOKEN=<admin-token> ./scripts/setup-branch-protection.sh <repo-name>
#
# Requirements:
#   - GH_TOKEN must have admin:repo scope (or be an org admin)
#   - gh CLI must be installed
#   - jq must be installed

set -euo pipefail

ORG="petry-projects"
DRY_RUN="${DRY_RUN:-false}"

info()  { echo "[INFO]  $*"; }
ok()    { echo "[OK]    $*"; }
warn()  { echo "[WARN]  $*"; }
err()   { echo "[ERROR] $*" >&2; }
skip()  { echo "[SKIP]  $*"; }

usage() {
  echo "Usage: $0 <repo-name>"
  echo "       $0 --default"
  echo ""
  echo "Options:"
  echo "  <repo-name>   Apply rulesets to a specific repository"
  echo "  --default     Apply rulesets to .github and bmad-bgreat-suite"
  echo ""
  echo "Environment variables:"
  echo "  GH_TOKEN   GitHub token with admin:repo scope (required)"
  echo "  DRY_RUN    Set to 'true' to preview without applying (default: false)"
  exit 1
}

# ---------------------------------------------------------------------------
# Per-repo required status checks
# These must match the actual job names defined in the repo's CI workflows.
# Returns a JSON array of {"context": "<name>", "integration_id": null} objects.
# ---------------------------------------------------------------------------
get_required_checks_json() {
  local repo="$1"
  case "$repo" in
    ".github")
      jq -n '[
        {"context": "Lint",                "integration_id": null},
        {"context": "ShellCheck",          "integration_id": null},
        {"context": "Agent Security Scan", "integration_id": null},
        {"context": "SonarCloud",          "integration_id": null},
        {"context": "claude",              "integration_id": null}
      ]'
      ;;
    "bmad-bgreat-suite")
      jq -n '[
        {"context": "SonarCloud", "integration_id": null},
        {"context": "Analyze",    "integration_id": null},
        {"context": "claude",     "integration_id": null}
      ]'
      ;;
    *)
      warn "No specific check configuration for $repo — using defaults (SonarCloud, claude)"
      warn "Verify check names against $repo's workflow job names before enabling enforcement"
      jq -n '[
        {"context": "SonarCloud", "integration_id": null},
        {"context": "claude",     "integration_id": null}
      ]'
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Upsert a ruleset: create if absent, update if found.
# Returns the ruleset ID.
# ---------------------------------------------------------------------------
upsert_ruleset() {
  local repo="$1"
  local name="$2"
  local payload="$3"

  # Check if ruleset already exists
  local existing_id
  existing_id=$(gh api "repos/$ORG/$repo/rulesets" \
    --jq ".[] | select(.name == \"$name\") | .id" 2>/dev/null || echo "")

  if [ "$DRY_RUN" = "true" ]; then
    if [ -n "$existing_id" ]; then
      skip "DRY_RUN — would update ruleset '$name' (id=$existing_id) on $ORG/$repo"
    else
      skip "DRY_RUN — would create ruleset '$name' on $ORG/$repo"
    fi
    return 0
  fi

  if [ -n "$existing_id" ]; then
    info "Updating existing ruleset '$name' (id=$existing_id) on $ORG/$repo ..."
    echo "$payload" | gh api -X PUT "repos/$ORG/$repo/rulesets/$existing_id" \
      --input - > /dev/null
    ok "Updated ruleset '$name' on $ORG/$repo"
  else
    info "Creating ruleset '$name' on $ORG/$repo ..."
    echo "$payload" | gh api -X POST "repos/$ORG/$repo/rulesets" \
      --input - > /dev/null
    ok "Created ruleset '$name' on $ORG/$repo"
  fi
}

# ---------------------------------------------------------------------------
# Build the pr-quality ruleset payload
# ---------------------------------------------------------------------------
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
        type: "pull_request",
        parameters: {
          required_approving_review_count: 1,
          dismiss_stale_reviews_on_push: true,
          require_code_owner_review: true,
          require_last_push_approval: true,
          required_review_thread_resolution: true
        }
      },
      {
        type: "required_linear_history"
      },
      {
        type: "non_fast_forward"
      },
      {
        type: "deletion"
      }
    ],
    bypass_actors: []
  }'
}

# ---------------------------------------------------------------------------
# Build the code-quality ruleset payload for a given repo
# ---------------------------------------------------------------------------
code_quality_payload() {
  local repo="$1"
  local checks_json
  checks_json=$(get_required_checks_json "$repo")

  jq -n \
    --argjson checks "$checks_json" \
    '{
      name: "code-quality",
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
          type: "required_status_checks",
          parameters: {
            strict_required_status_checks_policy: true,
            required_status_checks: $checks
          }
        }
      ],
      bypass_actors: []
    }'
}

# ---------------------------------------------------------------------------
# Apply both rulesets to a repo
# ---------------------------------------------------------------------------
apply_rulesets() {
  local repo="$1"
  info "Setting up branch protection rulesets on $ORG/$repo ..."

  # pr-quality
  local pr_payload
  pr_payload=$(pr_quality_payload)
  upsert_ruleset "$repo" "pr-quality" "$pr_payload"

  # code-quality
  local cq_payload
  cq_payload=$(code_quality_payload "$repo")
  upsert_ruleset "$repo" "code-quality" "$cq_payload"

  if [ "$DRY_RUN" != "true" ]; then
    ok "Branch protection rulesets applied to $ORG/$repo"
    info "Verify in: https://github.com/$ORG/$repo/settings/rules"
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
if [ $# -eq 0 ]; then
  usage
fi

if [ -z "${GH_TOKEN:-}" ]; then
  err "GH_TOKEN is required — provide a token with admin:repo scope"
  exit 1
fi

export GH_TOKEN

case "$1" in
  --default)
    info "Applying rulesets to .github and bmad-bgreat-suite ..."
    apply_rulesets ".github"
    apply_rulesets "bmad-bgreat-suite"
    ok "Done"
    ;;
  --help|-h)
    usage
    ;;
  *)
    apply_rulesets "$1"
    ;;
esac
