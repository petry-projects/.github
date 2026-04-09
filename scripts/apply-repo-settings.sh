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
#   - Bash 4+ (uses associative arrays — macOS ships Bash 3.2; use GitHub Actions or brew install bash)
#   - GH_TOKEN must have admin:repo scope (or be an admin of the org)
#   - gh CLI must be installed

set -euo pipefail

if [ "${BASH_VERSINFO[0]}" -lt 4 ]; then
  echo "[ERROR] Bash 4+ required (associative arrays). Found: $BASH_VERSION" >&2
  echo "        On macOS: brew install bash, then run with /opt/homebrew/bin/bash" >&2
  exit 1
fi

ORG="petry-projects"
DRY_RUN="${DRY_RUN:-false}"

info()  { echo "[INFO]  $*"; }
ok()    { echo "[OK]    $*"; }
err()   { echo "[ERROR] $*" >&2; }
skip()  { echo "[SKIP]  $*"; }

# Source the shared push-protection library — provides
# pp_apply_security_and_analysis() and the PP_REQUIRED_SA_SETTINGS list.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/push-protection.sh
. "$SCRIPT_DIR/lib/push-protection.sh"

usage() {
  echo "Usage: $0 <repo-name>"
  echo "       $0 --all"
  echo ""
  echo "Environment variables:"
  echo "  GH_TOKEN   GitHub token with admin:repo scope (required)"
  echo "  DRY_RUN    Set to 'true' to preview changes without applying (default: false)"
  exit 1
}

apply_labels() {
  local repo="$1"
  info "Applying standard labels to $ORG/$repo ..."

  # Format: "name|color|description" — matches standards/github-settings.md#labels--standard-set
  local label_configs=(
    "security|d93f0b|Security-related PRs and issues"
    "dependencies|0075ca|Dependency update PRs"
    "scorecard|d93f0b|OpenSSF Scorecard findings"
    "bug|d73a4a|Bug reports"
    "enhancement|a2eeef|Feature requests"
    "documentation|0075ca|Documentation changes"
    "in-progress|fbca04|An agent is actively working this issue"
  )

  for config in "${label_configs[@]}"; do
    IFS='|' read -r name color description <<< "$config"
    if [ "$DRY_RUN" = "true" ]; then
      skip "DRY_RUN=true — would create/update label '$name' (#$color) in $ORG/$repo"
    else
      gh label create "$name" \
        --repo "$ORG/$repo" \
        --description "$description" \
        --color "$color" \
        --force 2>/dev/null && ok "  label '$name' applied" || err "  failed to apply label '$name'"
    fi
  done
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
    has_discussions: .has_discussions,
    has_issues: .has_issues,
    squash_merge_commit_title: .squash_merge_commit_title,
    squash_merge_commit_message: .squash_merge_commit_message
  }' 2>/dev/null || echo "{}")

  if [ "$current" = "{}" ]; then
    err "Could not fetch settings for $ORG/$repo — check token permissions and repo name"
    return 1
  fi

  # Standard settings from standards/github-settings.md#repository-settings--standard-defaults
  declare -A EXPECTED=(
    [allow_auto_merge]="true"
    [delete_branch_on_merge]="true"
    [allow_squash_merge]="true"
    [allow_merge_commit]="true"
    [allow_rebase_merge]="true"
    [has_discussions]="true"
    [has_issues]="true"
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
# apply_codeql_default_setup — enable GitHub-managed CodeQL default setup
#
# Per standards/ci-standards.md#2-codeql-analysis-github-managed-default-setup,
# CodeQL is configured via the code-scanning/default-setup endpoint, not a
# per-repo workflow file. Languages are auto-detected from the default branch.
#
# Idempotent: if state is already "configured", we no-op. If "not-configured",
# we PATCH to enable. The API rejects updates on repos without code scanning
# capability (e.g. private repos without GHAS); we surface that as a warning.
# ---------------------------------------------------------------------------
apply_codeql_default_setup() {
  local repo="$1"
  info "Configuring CodeQL default setup for $ORG/$repo ..."

  local current_state
  current_state=$(gh api "repos/$ORG/$repo/code-scanning/default-setup" --jq '.state' 2>/dev/null || echo "")

  if [ "$current_state" = "configured" ]; then
    ok "  CodeQL default setup already configured"
    return 0
  fi

  if [ "$DRY_RUN" = "true" ]; then
    skip "DRY_RUN=true — would enable CodeQL default setup (current state: ${current_state:-unknown})"
    return 0
  fi

  if gh api -X PATCH "repos/$ORG/$repo/code-scanning/default-setup" \
       -F state=configured \
       -F query_suite=default > /dev/null 2>&1; then
    ok "  CodeQL default setup enabled"
  else
    err "  Failed to enable CodeQL default setup — repo may lack code scanning capability (private without GHAS, archived, or empty default branch). Manual review required."
    return 1
  fi
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
    apply_labels "$repo"
    pp_apply_security_and_analysis "$repo" || failed=$((failed + 1))
    apply_codeql_default_setup "$repo" || failed=$((failed + 1))
  done

  if [ "$failed" -gt 0 ]; then
    err "$failed repo(s) failed — check output above for details"
    exit 1
  fi

  ok "All repos processed successfully"
else
  apply_settings "$1"
  apply_labels "$1"
  pp_apply_security_and_analysis "$1"
  apply_codeql_default_setup "$1"
fi
