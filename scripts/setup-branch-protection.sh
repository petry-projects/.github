#!/usr/bin/env bash
# setup-branch-protection.sh — Configure pr-quality and code-quality rulesets
#
# Creates (or updates) the two standard rulesets on the .github and
# bmad-bgreat-suite repositories per standards/github-settings.md.
#
# Usage:
#   GH_TOKEN=<admin-pat> bash scripts/setup-branch-protection.sh
#   bash scripts/setup-branch-protection.sh --dry-run
#
# Requirements:
#   - gh CLI installed and authenticated (or GH_TOKEN set)
#   - Token must have admin access to both repos (repo + administration scope)
#   - jq installed
#
# Standard: https://github.com/petry-projects/.github/blob/main/standards/github-settings.md#repository-rulesets

set -euo pipefail

ORG="petry-projects"
DRY_RUN="${DRY_RUN:-false}"

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN="true" ;;
    *) echo "Unknown argument: $arg" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()    { echo "[INFO]  $*"; }
success() { echo "[OK]    $*"; }
dry()     { echo "[DRY]   $*"; }
error()   { echo "[ERROR] $*" >&2; }

gh_api() {
  if [ "$DRY_RUN" = "true" ]; then
    dry "gh api $*"
    return 0
  fi
  gh api "$@"
}

# Build a JSON array of status check objects from a list of check names.
# Usage: build_checks_json "Check One" "Check Two" ...
build_checks_json() {
  local json="["
  local first=true
  for check in "$@"; do
    if [ "$first" = "true" ]; then
      first=false
    else
      json+=","
    fi
    json+="{\"context\":$(jq -n --arg c "$check" '$c')}"
  done
  json+="]"
  echo "$json"
}

# ---------------------------------------------------------------------------
# pr-quality ruleset
# ---------------------------------------------------------------------------
# Enforces: 1 required review, stale review dismissal, code owner review,
# last-push approval, thread resolution, squash-only, no force-push, no deletion.
# Standard: standards/github-settings.md#pr-quality--standard-ruleset-all-repositories
# ---------------------------------------------------------------------------
apply_pr_quality_ruleset() {
  local repo="$1"
  local full_repo="$ORG/$repo"

  info "Applying pr-quality ruleset to $full_repo..."

  local payload
  payload=$(cat <<'PAYLOAD'
{
  "name": "pr-quality",
  "target": "branch",
  "enforcement": "active",
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
  ],
  "bypass_actors": []
}
PAYLOAD
)

  local existing_id
  existing_id=$(gh api "repos/$full_repo/rulesets" \
    --jq '.[] | select(.name == "pr-quality") | .id' 2>/dev/null || echo "")

  if [ -n "$existing_id" ]; then
    info "  Found existing pr-quality ruleset (ID: $existing_id) — updating..."
    gh_api --method PUT "repos/$full_repo/rulesets/$existing_id" \
      --input - <<< "$payload" > /dev/null
  else
    info "  No existing pr-quality ruleset — creating..."
    gh_api --method POST "repos/$full_repo/rulesets" \
      --input - <<< "$payload" > /dev/null
  fi

  success "pr-quality ruleset applied to $full_repo"
}

# ---------------------------------------------------------------------------
# code-quality ruleset
# ---------------------------------------------------------------------------
# Enforces: all required status checks must pass, strict branch-up-to-date policy.
# Standard: standards/github-settings.md#code-quality--required-checks-ruleset-all-repositories
# ---------------------------------------------------------------------------
apply_code_quality_ruleset() {
  local repo="$1"
  shift
  local full_repo="$ORG/$repo"
  local checks=("$@")

  info "Applying code-quality ruleset to $full_repo..."
  info "  Required checks: ${checks[*]}"

  local checks_json
  checks_json=$(build_checks_json "${checks[@]}")

  local payload
  payload=$(jq -n \
    --argjson checks "$checks_json" \
    '{
      "name": "code-quality",
      "target": "branch",
      "enforcement": "active",
      "conditions": {
        "ref_name": {
          "include": ["~DEFAULT_BRANCH"],
          "exclude": []
        }
      },
      "rules": [
        {
          "type": "required_status_checks",
          "parameters": {
            "required_status_checks": $checks,
            "strict_required_status_checks_policy": true
          }
        }
      ],
      "bypass_actors": []
    }')

  local existing_id
  existing_id=$(gh api "repos/$full_repo/rulesets" \
    --jq '.[] | select(.name == "code-quality") | .id' 2>/dev/null || echo "")

  if [ -n "$existing_id" ]; then
    info "  Found existing code-quality ruleset (ID: $existing_id) — updating..."
    gh_api --method PUT "repos/$full_repo/rulesets/$existing_id" \
      --input - <<< "$payload" > /dev/null
  else
    info "  No existing code-quality ruleset — creating..."
    gh_api --method POST "repos/$full_repo/rulesets" \
      --input - <<< "$payload" > /dev/null
  fi

  success "code-quality ruleset applied to $full_repo"
}

# ---------------------------------------------------------------------------
# Repo: petry-projects/.github
# ---------------------------------------------------------------------------
configure_dotgithub() {
  local repo=".github"
  echo ""
  echo "=== $ORG/$repo ==="

  apply_pr_quality_ruleset "$repo"

  # Check names match the job names in .github/workflows/ci.yml and sibling workflows.
  # Verify: https://github.com/petry-projects/.github/actions
  apply_code_quality_ruleset "$repo" \
    "Lint" \
    "ShellCheck" \
    "Agent Security Scan" \
    "SonarCloud" \
    "claude"
}

# ---------------------------------------------------------------------------
# Repo: petry-projects/bmad-bgreat-suite
# ---------------------------------------------------------------------------
configure_bmad() {
  local repo="bmad-bgreat-suite"
  echo ""
  echo "=== $ORG/$repo ==="

  apply_pr_quality_ruleset "$repo"

  # NOTE: Verify these check names match the actual workflow job names in
  # petry-projects/bmad-bgreat-suite before running in production.
  # Adjust if the repo uses different names (e.g., "build-and-test", "TypeScript").
  # Reference: https://github.com/petry-projects/bmad-bgreat-suite/actions
  apply_code_quality_ruleset "$repo" \
    "SonarCloud" \
    "Analyze" \
    "claude"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  echo "Branch Protection Setup"
  echo "========================"
  echo "Org:     $ORG"
  echo "Dry run: $DRY_RUN"
  echo ""

  # Sanity-check dependencies
  if ! command -v gh &>/dev/null; then
    error "gh CLI not found — install from https://cli.github.com"
    exit 1
  fi
  if ! command -v jq &>/dev/null; then
    error "jq not found — install from https://stedolan.github.io/jq"
    exit 1
  fi

  if [ "$DRY_RUN" != "true" ]; then
    if ! gh auth status &>/dev/null; then
      error "gh CLI not authenticated — run: gh auth login"
      exit 1
    fi
    info "Authenticated as: $(gh api user --jq '.login' 2>/dev/null || echo 'unknown')"
  fi

  configure_dotgithub
  configure_bmad

  echo ""
  echo "========================"
  if [ "$DRY_RUN" = "true" ]; then
    echo "Dry run complete — no changes made."
  else
    echo "Setup complete!"
    echo ""
    echo "Verify rulesets in GitHub UI:"
    echo "  https://github.com/$ORG/.github/settings/rules"
    echo "  https://github.com/$ORG/bmad-bgreat-suite/settings/rules"
  fi
}

main "$@"
