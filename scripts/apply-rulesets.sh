#!/usr/bin/env bash
# apply-rulesets.sh — Apply standard repository rulesets to org repositories
#
# Creates or updates the standard rulesets defined in:
#   standards/github-settings.md#repository-rulesets
#
# Rulesets managed:
#   pr-quality    — PR review requirements and merge method enforcement
#
# Usage:
#   ./scripts/apply-rulesets.sh [repo1 repo2 ...]
#   ./scripts/apply-rulesets.sh          # applies to ALL non-archived org repos
#   REPO=.github ./scripts/apply-rulesets.sh   # env var override for single repo
#
# Environment variables:
#   GH_TOKEN   — GitHub token with admin:repo scope (required)
#   ORG        — GitHub org (default: petry-projects)
#   DRY_RUN    — set to "true" to print API payloads without applying (default: false)
#   REPO       — single repo name (short form, no org prefix); overrides positional args

set -euo pipefail

ORG="${ORG:-petry-projects}"
DRY_RUN="${DRY_RUN:-false}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()  { echo "[INFO]  $*" >&2; }
warn()  { echo "[WARN]  $*" >&2; }
error() { echo "[ERROR] $*" >&2; }

# Upsert a ruleset: create if missing, update (PATCH) if already present.
# Args: <repo> <ruleset-name> <json-payload>
upsert_ruleset() {
  local repo="$1" name="$2" payload="$3"
  local full_repo="$ORG/$repo"

  # Look up existing rulesets for this repo
  local existing_id
  existing_id=$(gh api "repos/$full_repo/rulesets" \
    --jq --arg name "$name" '.[] | select(.name == $name) | .id' 2>/dev/null || echo "")

  if [ "$DRY_RUN" = "true" ]; then
    if [ -n "$existing_id" ]; then
      info "[DRY RUN] Would PATCH ruleset '$name' (id=$existing_id) on $full_repo"
    else
      info "[DRY RUN] Would POST new ruleset '$name' on $full_repo"
    fi
    echo "$payload" | jq . >&2
    return 0
  fi

  if [ -n "$existing_id" ]; then
    info "Updating existing ruleset '$name' (id=$existing_id) on $full_repo …"
    gh api --method PUT "repos/$full_repo/rulesets/$existing_id" \
      --input - <<< "$payload" > /dev/null
    info "  Updated '$name' on $full_repo"
  else
    info "Creating ruleset '$name' on $full_repo …"
    gh api --method POST "repos/$full_repo/rulesets" \
      --input - <<< "$payload" > /dev/null
    info "  Created '$name' on $full_repo"
  fi
}

# ---------------------------------------------------------------------------
# Bypass actors
# ---------------------------------------------------------------------------
# The dependabot-automerge-petry GitHub App (app_id: 3167543) must be able to
# bypass the pr-quality ruleset so Dependabot auto-merges can proceed without
# a human approving every patch update.
#
# actor_type values for bypass_actors:
#   "Integration"   — a GitHub App (use the app installation ID, not app_id)
#   "OrganizationAdmin" — org admins
#   "RepositoryRole"    — built-in repo role (e.g., "admin")
#
# bypass_mode values: "always" | "pull_request"
# ---------------------------------------------------------------------------
build_bypass_actors() {
  # Return a JSON array of bypass actor objects.
  # We grant the org admin role an "always" bypass so admins can unblock
  # emergency situations without going through the PR flow.
  # The dependabot-automerge app needs "pull_request" bypass to merge
  # its own auto-approved PRs.
  #
  # Note: Installation IDs are org-specific. The installation ID for the
  # dependabot-automerge-petry app is looked up dynamically so this script
  # remains portable if the installation changes.
  local install_id
  install_id=$(gh api "orgs/$ORG/installations" \
    --jq '.installations[] | select(.app_slug == "dependabot-automerge-petry") | .id' \
    2>/dev/null | head -1 || echo "")

  local actors='[
    {
      "actor_id": 1,
      "actor_type": "OrganizationAdmin",
      "bypass_mode": "always"
    }
  ]'

  if [ -n "$install_id" ] && [ "$install_id" != "null" ]; then
    actors=$(echo "$actors" | jq \
      --argjson id "$install_id" \
      '. += [{"actor_id": $id, "actor_type": "Integration", "bypass_mode": "pull_request"}]')
    info "  Added dependabot-automerge-petry (installation $install_id) as bypass actor"
  else
    warn "  Could not find dependabot-automerge-petry installation — skipping bypass actor"
  fi

  echo "$actors"
}

# ---------------------------------------------------------------------------
# pr-quality ruleset
# Standard reference:
#   standards/github-settings.md#pr-quality--standard-ruleset-all-repositories
# ---------------------------------------------------------------------------
apply_pr_quality() {
  local repo="$1"
  local bypass_actors
  bypass_actors=$(build_bypass_actors)

  local payload
  payload=$(jq -n \
    --argjson bypass_actors "$bypass_actors" \
    '{
      "name": "pr-quality",
      "target": "branch",
      "enforcement": "active",
      "bypass_actors": $bypass_actors,
      "conditions": {
        "ref_name": {
          "include": ["~DEFAULT_BRANCH"],
          "exclude": []
        }
      },
      "rules": [
        {
          "type": "deletion"
        },
        {
          "type": "non_fast_forward"
        },
        {
          "type": "pull_request",
          "parameters": {
            "required_approving_review_count": 1,
            "dismiss_stale_reviews_on_push": true,
            "require_code_owner_review": true,
            "require_last_push_approval": true,
            "required_review_thread_resolution": true,
            "allowed_merge_methods": ["squash"]
          }
        }
      ]
    }')

  upsert_ruleset "$repo" "pr-quality" "$payload"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  if [ -z "${GH_TOKEN:-}" ]; then
    error "GH_TOKEN is not set. Export a token with repo admin scope."
    exit 1
  fi

  local repos=()

  # Priority: env var > positional args > all org repos
  if [ -n "${REPO:-}" ]; then
    repos=("$REPO")
  elif [ "$#" -gt 0 ]; then
    repos=("$@")
  else
    info "No repos specified — fetching all non-archived repos for $ORG …"
    mapfile -t repos < <(gh repo list "$ORG" --no-archived --json name -q '.[].name' --limit 500)
  fi

  if [ "${#repos[@]}" -eq 0 ]; then
    warn "No repositories found in $ORG — check GH_TOKEN permissions"
    exit 1
  fi

  info "Applying standard rulesets to ${#repos[@]} repo(s): ${repos[*]}"
  [ "$DRY_RUN" = "true" ] && info "DRY RUN — no changes will be applied"

  local ok=0 failed=0
  for repo in "${repos[@]}"; do
    echo ""
    info "=== $ORG/$repo ==="
    if apply_pr_quality "$repo"; then
      ok=$((ok + 1))
    else
      warn "Failed to apply rulesets to $repo"
      failed=$((failed + 1))
    fi
  done

  echo ""
  info "Done. Success: $ok  Failed: $failed"
  [ "$failed" -eq 0 ] || exit 1
}

main "$@"
