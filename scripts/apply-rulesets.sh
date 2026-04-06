#!/usr/bin/env bash
# apply-rulesets.sh — Create or update required repository rulesets
#
# Creates the `code-quality` (required status checks) ruleset for a repository,
# following the standard in standards/github-settings.md.
#
# Usage:
#   GH_TOKEN=<admin-token> bash scripts/apply-rulesets.sh <repo>
#   GH_TOKEN=<admin-token> bash scripts/apply-rulesets.sh <repo> --dry-run
#
# Examples:
#   bash scripts/apply-rulesets.sh .github
#   bash scripts/apply-rulesets.sh my-service
#
# Environment:
#   GH_TOKEN   — GitHub token with administration:write scope (required)
#   DRY_RUN    — Set to "true" to print the API payload without applying
#
# Requirements: gh CLI (https://cli.github.com/) and jq

set -euo pipefail

ORG="petry-projects"
REPO="${1:?Usage: $0 <repo>}"
DRY_RUN="${DRY_RUN:-false}"

if [[ "${2:-}" == "--dry-run" ]]; then
  DRY_RUN="true"
fi

info()  { echo "[INFO]  $*" >&2; }
ok()    { echo "[OK]    $*" >&2; }
warn()  { echo "[WARN]  $*" >&2; }

# ---------------------------------------------------------------------------
# Check if a workflow file exists in the repo
# ---------------------------------------------------------------------------
workflow_exists() {
  gh api "repos/$ORG/$REPO/contents/.github/workflows/$1" --jq '.name' >/dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Fetch workflow content (decoded) by filename
# ---------------------------------------------------------------------------
get_workflow_content() {
  gh api "repos/$ORG/$REPO/contents/.github/workflows/$1" --jq '.content' 2>/dev/null \
    | base64 -d 2>/dev/null || true
}

# ---------------------------------------------------------------------------
# Extract workflow display name from YAML content
# ---------------------------------------------------------------------------
workflow_display_name() {
  echo "$1" | grep -m1 '^name:' | sed 's/^name:[[:space:]]*//' | tr -d '"'"'"
}

# ---------------------------------------------------------------------------
# Extract job display names from CI workflow (all jobs that have a name: field)
# ---------------------------------------------------------------------------
ci_job_names() {
  local content="$1"
  echo "$content" | awk '
    /^jobs:/        { in_jobs=1; next }
    !in_jobs        { next }
    /^  [a-zA-Z_-]+:/ {
      # New job — grab the job id, reset pending name
      match($0, /^  ([a-zA-Z_-]+):/, m)
      pending_id = m[1]
      pending_name = pending_id
      in_job = 1
      next
    }
    in_job && /^    name:/ {
      val = $0
      gsub(/^[[:space:]]*name:[[:space:]]*/, "", val)
      gsub(/^["'"'"']|["'"'"']$/, "", val)
      pending_name = val
      print pending_name
      in_job = 0  # only first name: per job
    }
  '
}

# ---------------------------------------------------------------------------
# Build required status check list for this repo
# ---------------------------------------------------------------------------
build_required_checks() {
  local -a checks=()

  # SonarCloud — the GitHub App integration posts checks as "SonarCloud",
  # separate from the GitHub Actions workflow job.
  if workflow_exists "sonarcloud.yml"; then
    checks+=("SonarCloud")
    info "Adding check: SonarCloud"
  fi

  # CodeQL — check run name: "<workflow_name> / <job_name>"
  if workflow_exists "codeql.yml"; then
    local codeql_content wf_name
    codeql_content=$(get_workflow_content "codeql.yml")
    wf_name=$(workflow_display_name "$codeql_content")
    # CodeQL jobs are typically named "Analyze" or "Analyze (<language>)"
    local analyze_names
    analyze_names=$(echo "$codeql_content" | awk '
      /^jobs:/ { in_jobs=1; next }
      !in_jobs { next }
      in_jobs && /^  analyze/ { in_job=1; next }
      in_job && /^    name:/ {
        gsub(/^[[:space:]]*name:[[:space:]]*/,""); gsub(/^["'"'"']|["'"'"']$/,""); print; exit
      }
      in_job && /^  [a-zA-Z]/ { exit }
    ')
    if [ -n "$analyze_names" ]; then
      local check_name="${wf_name} / ${analyze_names}"
      checks+=("$check_name")
      info "Adding check: $check_name"
    else
      checks+=("CodeQL / Analyze")
      info "Adding check: CodeQL / Analyze (fallback)"
    fi
  fi

  # Claude Code — job id is "claude"; GitHub Actions check name is
  # "<workflow_name> / <job_display_name>"
  if workflow_exists "claude.yml"; then
    local claude_content wf_name job_name
    claude_content=$(get_workflow_content "claude.yml")
    wf_name=$(workflow_display_name "$claude_content")
    # The "claude" job in claude.yml has no explicit name: — falls back to job id
    job_name=$(echo "$claude_content" | awk '
      /^jobs:/ { in_jobs=1; next }
      !in_jobs { next }
      in_jobs && /^  claude:/ { in_job=1; next }
      in_job && /^    name:/ {
        gsub(/^[[:space:]]*name:[[:space:]]*/,""); gsub(/^["'"'"']|["'"'"']$/,""); print; exit
      }
      in_job && /^  [a-zA-Z]/ { exit }
    ')
    local check_name="${wf_name} / ${job_name:-claude}"
    checks+=("$check_name")
    info "Adding check: $check_name"
  fi

  # CI pipeline — all named jobs in ci.yml
  if workflow_exists "ci.yml"; then
    local ci_content wf_name
    ci_content=$(get_workflow_content "ci.yml")
    wf_name=$(workflow_display_name "$ci_content")
    local job_names
    job_names=$(ci_job_names "$ci_content")
    while IFS= read -r jname; do
      [ -n "$jname" ] || continue
      local check_name="${wf_name} / ${jname}"
      checks+=("$check_name")
      info "Adding check: $check_name"
    done <<< "$job_names"
  fi

  # Export result
  REQUIRED_CHECKS=("${checks[@]+"${checks[@]}"}")
}

# ---------------------------------------------------------------------------
# Get existing ruleset ID by name (empty string if not found)
# ---------------------------------------------------------------------------
get_ruleset_id() {
  gh api "repos/$ORG/$REPO/rulesets" \
    --jq ".[] | select(.name == \"$1\") | .id" 2>/dev/null | head -1 || true
}

# ---------------------------------------------------------------------------
# Create or update the code-quality ruleset
# ---------------------------------------------------------------------------
apply_code_quality_ruleset() {
  build_required_checks

  if [ "${#REQUIRED_CHECKS[@]}" -eq 0 ]; then
    warn "No required checks detected for $ORG/$REPO — skipping code-quality ruleset"
    return 0
  fi

  # Build JSON array of required status check objects
  local checks_json
  checks_json=$(printf '%s\n' "${REQUIRED_CHECKS[@]}" | jq -R '{context: .}' | jq -s '.')

  local payload
  payload=$(jq -n \
    --arg name "code-quality" \
    --argjson checks "$checks_json" \
    '{
      name: $name,
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
    }')

  if [ "$DRY_RUN" = "true" ]; then
    info "DRY RUN — would apply:"
    echo "$payload" | jq '.'
    return 0
  fi

  local existing_id
  existing_id=$(get_ruleset_id "code-quality")

  if [ -n "$existing_id" ]; then
    info "Updating existing 'code-quality' ruleset (id: $existing_id) in $ORG/$REPO..."
    gh api --method PUT "repos/$ORG/$REPO/rulesets/$existing_id" \
      --input <(echo "$payload") --jq '.name' >/dev/null
    ok "Updated 'code-quality' ruleset in $ORG/$REPO"
  else
    info "Creating 'code-quality' ruleset in $ORG/$REPO..."
    gh api --method POST "repos/$ORG/$REPO/rulesets" \
      --input <(echo "$payload") --jq '.name' >/dev/null
    ok "Created 'code-quality' ruleset in $ORG/$REPO"
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  info "Applying rulesets for $ORG/$REPO (dry_run=$DRY_RUN)"
  apply_code_quality_ruleset
}

main "$@"
