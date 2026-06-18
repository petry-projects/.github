#!/usr/bin/env bash
# deploy-standard-workflows.sh — Deploy org-standard workflow stubs to all repos.
#
# Reads canonical stubs from standards/workflows/ and deploys them into every
# repo in the petry-projects org by opening a pull request per repo (via the
# shared scripts/lib/standards-deploy.sh primitive). Only workflows that have a
# template in standards/workflows/ AND appear in the DEPLOYABLE_WORKFLOWS list
# below are eligible — tech-stack-specific workflows (ci.yml, sonarcloud.yml)
# must be set up manually.
#
# Deployment is PR-based, never a direct push to the default branch: a direct
# Contents-API push is rejected (HTTP 409) on repos whose ruleset enforces
# required status checks, and bypasses review/CI on the repos where it would
# succeed. Opening a PR works uniformly on protected and unprotected repos and
# leaves an auditable, CI-gated record. The PRs are labeled `standards-sync` and
# left for the normal review/auto-merge pipeline — this script never merges and
# never uses --admin. See petry-projects/.github#478.
#
# Usage:
#   deploy-standard-workflows.sh [options]
#
# Options:
#   --dry-run              Print planned actions without opening any PRs.
#   --workflow <name.yml>  Deploy only this workflow (default: all deployable).
#   --repo <name>          Target a single repo instead of all org repos.
#   --force                Re-deploy even if the file looks correct (re-syncs).
#
# Requirements:
#   GH_TOKEN (or gh auth login) with repo scope (branch + PR creation).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=scripts/lib/standards-deploy.sh
source "$SCRIPT_DIR/lib/standards-deploy.sh"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
ORG="petry-projects"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STANDARDS_DIR="$REPO_ROOT/standards/workflows"

# Branch prefix + label for the PRs this script opens.
SYNC_BRANCH_PREFIX="standards-sync"
SYNC_LABEL="standards-sync"

# Repos exempt from blanket standard-workflow deployment.
#   .github         — self-host source of truth; its own callers use local refs
#                     (e.g. add-to-project.yml pins ./.github/...), which a
#                     channel-pinned stub must never overwrite.
#   .github-private — self-manages its workflow fleet (dev-lead runs inline, etc).
# A repo here may still opt into a *specific* workflow via SKIP_OVERRIDES below.
SKIP_REPOS=(".github" ".github-private")

# Per-workflow opt-ins for otherwise-skipped repos. Keyed by workflow filename;
# value is a space-separated list of SKIP_REPOS that should still receive it.
# .github-private participates in the org Initiatives board, so it receives the
# add-to-project.yml caller (the org board is a single shared target — the stub
# is identical for every repo) while staying exempt from all other stubs.
declare -A SKIP_OVERRIDES=(
  ["add-to-project.yml"]=".github-private"
)

# Workflows deployable from standards/workflows/<name> verbatim.
# Excludes ci.yml, sonarcloud.yml (tech-stack-specific) and
# feature-ideation.yml (requires repo-specific project_context input).
DEPLOYABLE_WORKFLOWS=(
  pr-review-mention.yml
  dev-lead.yml
  agent-shield.yml
  auto-rebase.yml
  dependabot-automerge.yml
  dependabot-rebase.yml
  dependency-audit.yml
  add-to-project.yml
)

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
DRY_RUN=false
TARGET_WORKFLOW=""
TARGET_REPO=""
FORCE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)   DRY_RUN=true; shift ;;
    --force)     FORCE=true;   shift ;;
    --workflow)  TARGET_WORKFLOW="$2"; shift 2 ;;
    --repo)      TARGET_REPO="$2";     shift 2 ;;
    -h|--help)
      sed -n '2,29p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "[deploy] $*"; }
skip() { echo "[deploy] SKIP  $*"; }
dry()  { echo "[deploy] DRY   $*"; }
ok()   { echo "[deploy] OK    $*"; }
err()  { echo "[deploy] ERROR $*" >&2; }

is_skipped_repo() {
  local repo="$1" s
  for s in "${SKIP_REPOS[@]}"; do
    [[ "$repo" == "$s" ]] && return 0
  done
  return 1
}

# True if a normally-skipped repo has opted into this specific workflow via
# SKIP_OVERRIDES — lets a self-managed repo receive one stub while staying
# exempt from the rest.
repo_opts_into() {
  local repo="$1" workflow="$2"
  local opt_in="${SKIP_OVERRIDES[$workflow]:-}"
  [[ -z "$opt_in" ]] && return 1

  # Split the space-separated opt-in list into an array (read -r -a avoids the
  # pathname expansion an unquoted expansion would be subject to).
  local -a allowed_repos
  read -r -a allowed_repos <<< "$opt_in"
  local r
  for r in "${allowed_repos[@]}"; do
    [[ "$repo" == "$r" ]] && return 0
  done
  return 1
}

# Fetch a file from the repo API in one call; outputs "sha<TAB>decoded-content".
# Returns empty string on 404.
fetch_existing() {
  local repo="$1" path="$2"
  local raw
  raw=$(gh api "repos/$ORG/$repo/contents/$path" 2>/dev/null) || { echo ""; return; }
  local sha encoded decoded
  sha=$(echo "$raw" | jq -r '.sha // empty')
  encoded=$(echo "$raw" | jq -r '.content // empty')
  decoded=$(echo "$encoded" | base64 -d 2>/dev/null || echo "")
  printf '%s\t%s' "$sha" "$decoded"
}

# True if the existing decoded content already has the canonical uses: reference
# for this workflow (extracted from the template itself, so it tracks version bumps).
is_already_compliant() {
  local existing_content="$1" template="$2"
  local expected_uses
  expected_uses=$(grep -E '^[[:space:]]*uses:' "$template" | head -1 | sed 's/^[[:space:]]*uses:[[:space:]]*//' | tr -d '\r')
  [[ -z "$expected_uses" ]] && return 1
  echo "$existing_content" | grep -qF "$expected_uses"
}

# Build the PR body for a stub deployment.
pr_body_for() {
  local workflow="$1"
  printf 'Syncs the org-standard `%s` workflow stub from `%s/.github` (`standards/workflows/%s`), deployed verbatim.\n\nOpened by `scripts/deploy-standard-workflows.sh`; the stub is a thin caller and all behaviour lives in the reusable. See `standards/ci-standards.md`.\n\nThis PR is labeled `%s` and left for the normal review/auto-merge pipeline — the deploy script never merges directly.\n' \
    "$workflow" "$ORG" "$workflow" "$SYNC_LABEL"
}

# ---------------------------------------------------------------------------
# Main deploy logic for a single workflow in a single repo
# ---------------------------------------------------------------------------
deploy_workflow_to_repo() {
  local repo="$1" workflow="$2"
  local template="$STANDARDS_DIR/$workflow"
  local target_path=".github/workflows/$workflow"

  if [[ ! -f "$template" ]]; then
    err "No template at $template — skipping $workflow for $repo"
    return
  fi

  local raw existing_sha existing_content
  raw=$(fetch_existing "$repo" "$target_path")
  existing_sha="${raw%%$'\t'*}"
  existing_content="${raw#*$'\t'}"

  if [[ -n "$existing_sha" ]] && [[ "$FORCE" == "false" ]] && is_already_compliant "$existing_content" "$template"; then
    skip "$repo/$target_path already compliant"
    return
  fi

  local branch="${SYNC_BRANCH_PREFIX}/${workflow%.yml}"
  local title="chore: sync org-standard ${workflow} stub from ${ORG}/.github"

  if [[ "$DRY_RUN" == "true" ]]; then
    if [[ -n "$existing_sha" ]]; then
      dry "Would open PR to update $repo/$target_path (branch $branch)"
    else
      dry "Would open PR to create $repo/$target_path (branch $branch)"
    fi
    return
  fi

  local outcome
  outcome=$(sd_deploy_via_pr "$ORG/$repo" "$target_path" "$template" \
    "$branch" "$SYNC_LABEL" "$title" "$(pr_body_for "$workflow")") || true

  case "$outcome" in
    "OPENED "*)       ok   "$repo/$target_path — opened ${outcome#OPENED }" ;;
    "SKIP_PR_OPEN "*) skip "$repo/$target_path — PR #${outcome#SKIP_PR_OPEN } already open" ;;
    "FAILED "*)       err  "$repo/$target_path — ${outcome#FAILED }" ;;
    *)                err  "$repo/$target_path — unexpected outcome: ${outcome:-<none>}" ;;
  esac
}

# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------
[[ "$DRY_RUN" == "true" ]] && log "DRY RUN — no PRs will be opened"

# Resolve target repos using pagination (handles orgs with >100 repos).
declare -a REPOS
if [[ -n "$TARGET_REPO" ]]; then
  REPOS=("$TARGET_REPO")
else
  mapfile -t REPOS < <(gh repo list "$ORG" --limit 500 --no-archived --json name -q '.[].name')
fi

# Resolve target workflows
declare -a WORKFLOWS
if [[ -n "$TARGET_WORKFLOW" ]]; then
  WORKFLOWS=("$TARGET_WORKFLOW")
else
  WORKFLOWS=("${DEPLOYABLE_WORKFLOWS[@]}")
fi

log "Deploying ${#WORKFLOWS[@]} workflow(s) to ${#REPOS[@]} repo(s)"

for repo in "${REPOS[@]}"; do
  # Fully-exempt repos (no per-workflow opt-in) skip with a single log line
  # instead of one per workflow.
  if is_skipped_repo "$repo"; then
    opts_in_any=false
    for w in "${WORKFLOWS[@]}"; do
      if repo_opts_into "$repo" "$w"; then
        opts_in_any=true
        break
      fi
    done
    if [[ "$opts_in_any" == "false" ]]; then
      skip "$repo (exempt)"
      continue
    fi
  fi

  for workflow in "${WORKFLOWS[@]}"; do
    if is_skipped_repo "$repo" && ! repo_opts_into "$repo" "$workflow"; then
      skip "$repo/$workflow (exempt)"
      continue
    fi
    deploy_workflow_to_repo "$repo" "$workflow"
  done
done

log "Done."
