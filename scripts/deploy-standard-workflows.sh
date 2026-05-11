#!/usr/bin/env bash
# deploy-standard-workflows.sh — Push org-standard workflow stubs to all repos.
#
# Reads canonical stubs from standards/workflows/ and upserts them into every
# repo in the petry-projects org via the GitHub Contents API.  Only workflows
# that have a template in standards/workflows/ AND appear in the
# DEPLOYABLE_WORKFLOWS list below are eligible for deployment — tech-stack-
# specific workflows (ci.yml, sonarcloud.yml) must be set up manually.
#
# Usage:
#   deploy-standard-workflows.sh [options]
#
# Options:
#   --dry-run              Print planned actions without making any changes.
#   --workflow <name.yml>  Deploy only this workflow (default: all deployable).
#   --repo <name>          Target a single repo instead of all org repos.
#   --force                Re-deploy even if the file looks correct (re-syncs).
#
# Requirements:
#   GH_TOKEN (or gh auth login) with repo scope.

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
ORG="petry-projects"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
STANDARDS_DIR="$REPO_ROOT/standards/workflows"

# Repos to never touch.
SKIP_REPOS=(".github" ".github-private")

# Workflows deployable from standards/workflows/<name> verbatim.
# Excludes ci.yml, sonarcloud.yml (tech-stack-specific) and
# feature-ideation.yml (requires repo-specific project_context input).
DEPLOYABLE_WORKFLOWS=(
  pr-review-mention.yml
  agent-shield.yml
  auto-rebase.yml
  claude.yml
  dependabot-automerge.yml
  dependabot-rebase.yml
  dependency-audit.yml
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
      sed -n '2,25p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()  { echo "[deploy] $*"; }
info() { echo "[deploy] INFO  $*"; }
skip() { echo "[deploy] SKIP  $*"; }
dry()  { echo "[deploy] DRY   $*"; }
ok()   { echo "[deploy] OK    $*"; }
err()  { echo "[deploy] ERROR $*" >&2; }

is_skipped_repo() {
  local repo="$1"
  local s
  for s in "${SKIP_REPOS[@]}"; do
    [[ "$repo" == "$s" ]] && return 0
  done
  return 1
}

# Returns the file's current SHA from the API, or empty string if absent.
get_file_sha() {
  local repo="$1" path="$2"
  gh api "repos/$ORG/$repo/contents/$path" --jq '.sha' 2>/dev/null || echo ""
}

# Returns the decoded content of a file from the API, or empty string if absent.
get_file_content() {
  local repo="$1" path="$2"
  gh api "repos/$ORG/$repo/contents/$path" --jq '.content' 2>/dev/null \
    | base64 -d 2>/dev/null || echo ""
}

# True if the file already contains the expected @v1 reusable reference.
is_already_compliant() {
  local content="$1" workflow="$2"
  local reusable="${workflow%.yml}-reusable"
  local expected="petry-projects/\\.github/\\.github/workflows/${reusable}\\.yml@v1"
  echo "$content" | grep -qE "^[[:space:]]*uses:[[:space:]]*${expected}([[:space:]]|$)"
}

# Upsert a file via the GitHub Contents API.
upsert_file() {
  local repo="$1" path="$2" template_path="$3" sha="$4"
  local encoded
  encoded=$(base64 -w 0 "$template_path")

  local commit_msg="chore: sync org-standard ${path##*/} stub from petry-projects/.github"

  if [[ -n "$sha" ]]; then
    gh api "repos/$ORG/$repo/contents/$path" \
      --method PUT \
      --field message="$commit_msg" \
      --field "content=$encoded" \
      --field "sha=$sha" \
      --silent
  else
    gh api "repos/$ORG/$repo/contents/$path" \
      --method PUT \
      --field message="$commit_msg" \
      --field "content=$encoded" \
      --silent
  fi
}

# ---------------------------------------------------------------------------
# Main deploy logic for a single workflow in a single repo
# ---------------------------------------------------------------------------
deploy_workflow_to_repo() {
  local repo="$1" workflow="$2"
  local template="$STANDARDS_DIR/$workflow"
  local target_path=".github/workflows/$workflow"

  if [[ ! -f "$template" ]]; then
    err "No template found at $template — skipping $workflow for $repo"
    return
  fi

  local existing_content existing_sha
  existing_sha=$(get_file_sha "$repo" "$target_path")
  existing_content=""
  if [[ -n "$existing_sha" ]]; then
    existing_content=$(get_file_content "$repo" "$target_path")
  fi

  if [[ -n "$existing_sha" ]] && [[ "$FORCE" == "false" ]] && is_already_compliant "$existing_content" "$workflow"; then
    skip "$repo/$target_path already compliant"
    return
  fi

  if [[ "$DRY_RUN" == "true" ]]; then
    if [[ -n "$existing_sha" ]]; then
      dry "Would update $repo/$target_path (non-compliant stub → @v1)"
    else
      dry "Would create $repo/$target_path"
    fi
    return
  fi

  if upsert_file "$repo" "$target_path" "$template" "$existing_sha"; then
    if [[ -n "$existing_sha" ]]; then
      ok "Updated $repo/$target_path"
    else
      ok "Created $repo/$target_path"
    fi
  else
    err "Failed to upsert $repo/$target_path"
  fi
}

# ---------------------------------------------------------------------------
# Entrypoint
# ---------------------------------------------------------------------------
[[ "$DRY_RUN" == "true" ]] && log "DRY RUN — no files will be written"

# Resolve target repos
declare -a REPOS
if [[ -n "$TARGET_REPO" ]]; then
  REPOS=("$TARGET_REPO")
else
  mapfile -t REPOS < <(gh repo list "$ORG" --limit 200 --json name -q '.[].name')
fi

# Resolve target workflows
declare -a WORKFLOWS
if [[ -n "$TARGET_WORKFLOW" ]]; then
  WORKFLOWS=("$TARGET_WORKFLOW")
else
  WORKFLOWS=("${DEPLOYABLE_WORKFLOWS[@]}")
fi

log "Deploying ${#WORKFLOWS[@]} workflow(s) to ${#REPOS[@]} repo(s)"

UPDATED=0 CREATED=0 SKIPPED=0 ERRORS=0

for repo in "${REPOS[@]}"; do
  if is_skipped_repo "$repo"; then
    skip "$repo (exempt)"
    continue
  fi

  for workflow in "${WORKFLOWS[@]}"; do
    deploy_workflow_to_repo "$repo" "$workflow"
  done
done

log "Done."
