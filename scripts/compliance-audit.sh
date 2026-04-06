#!/usr/bin/env bash
# compliance-audit.sh — Weekly org-wide compliance audit
#
# Checks every petry-projects repository against the standards defined in:
#   standards/ci-standards.md
#   standards/dependabot-policy.md
#   standards/github-settings.md
#
# Outputs:
#   $REPORT_DIR/findings.json   — machine-readable findings
#   $REPORT_DIR/summary.md      — human-readable report
#
# Environment variables:
#   GH_TOKEN        — GitHub token with repo/org scope (required)
#   REPORT_DIR      — directory for output files (default: mktemp -d)
#   DRY_RUN         — set to "true" to skip issue creation (default: false)
#   CREATE_ISSUES   — set to "false" to skip issue creation (default: true)

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
ORG="petry-projects"
AUDIT_LABEL="compliance-audit"
AUDIT_LABEL_COLOR="7057ff"
AUDIT_LABEL_DESC="Automated compliance audit finding"
REPORT_DIR="${REPORT_DIR:-$(mktemp -d)}"
DRY_RUN="${DRY_RUN:-false}"
CREATE_ISSUES="${CREATE_ISSUES:-true}"

FINDINGS_FILE="$REPORT_DIR/findings.json"
SUMMARY_FILE="$REPORT_DIR/summary.md"

REQUIRED_WORKFLOWS=(ci.yml codeql.yml sonarcloud.yml claude.yml dependabot-automerge.yml dependency-audit.yml agent-shield.yml)

# Format: "name:color:description" (color without leading #)
REQUIRED_LABEL_CONFIGS=(
  "security:d93f0b:Security-related PRs and issues"
  "dependencies:0075ca:Dependency update PRs"
  "scorecard:d93f0b:OpenSSF Scorecard findings"
  "bug:d73a4a:Bug reports"
  "enhancement:a2eeef:Feature requests"
  "documentation:0075ca:Documentation changes"
)

REQUIRED_LABELS=(security dependencies scorecard bug enhancement documentation)

REQUIRED_SETTINGS_BOOL=(
  "allow_auto_merge:true:Allow auto-merge must be enabled for Dependabot workflow"
  "delete_branch_on_merge:true:Automatically delete head branches must be enabled"
  "has_wiki:false:Wiki should be disabled — documentation lives in the repo"
  "has_issues:true:Issue tracking must be enabled"
)

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
findings_count=0

add_finding() {
  local repo="$1" category="$2" check="$3" severity="$4" detail="$5" standard_ref="${6:-}"

  findings_count=$((findings_count + 1))
  local finding
  finding=$(jq -n \
    --arg repo "$repo" \
    --arg category "$category" \
    --arg check "$check" \
    --arg severity "$severity" \
    --arg detail "$detail" \
    --arg standard_ref "$standard_ref" \
    '{repo:$repo,category:$category,check:$check,severity:$severity,detail:$detail,standard_ref:$standard_ref}')

  jq --argjson f "$finding" '. += [$f]' "$FINDINGS_FILE" > "$FINDINGS_FILE.tmp"
  mv "$FINDINGS_FILE.tmp" "$FINDINGS_FILE"
}

log() { echo "::group::$*" >&2; }
log_end() { echo "::endgroup::" >&2; }
info() { echo "[INFO] $*" >&2; }
warn() { echo "::warning::$*" >&2; }

# Retry wrapper for gh api calls (handles rate limits)
gh_api() {
  local retries=3
  for i in $(seq 1 $retries); do
    if gh api "$@" 2>/dev/null; then
      return 0
    fi
    if [ "$i" -lt "$retries" ]; then
      sleep $((i * 2))
    else
      info "gh api $1 failed after $retries retries" >&2
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# Ecosystem detection
# ---------------------------------------------------------------------------
detect_ecosystems() {
  local repo="$1"
  ECOSYSTEMS=()

  # Check for common ecosystem markers via the repo tree
  local tree
  tree=$(gh_api "repos/$ORG/$repo/git/trees/HEAD?recursive=1" --jq '.tree[].path' 2>/dev/null || echo "")

  if echo "$tree" | grep -qE '(^|/)package\.json$'; then
    ECOSYSTEMS+=("npm")
  fi
  if echo "$tree" | grep -qE '(^|/)pnpm-lock\.yaml$'; then
    # Override npm with pnpm if lock file present, or add pnpm directly
    if [[ " ${ECOSYSTEMS[*]} " == *" npm "* ]]; then
      ECOSYSTEMS=("${ECOSYSTEMS[@]/npm/pnpm}")
    else
      ECOSYSTEMS+=("pnpm")
    fi
  fi
  if echo "$tree" | grep -qE '(^|/)go\.mod$'; then
    ECOSYSTEMS+=("go")
  fi
  if echo "$tree" | grep -qE '(^|/)Cargo\.toml$'; then
    ECOSYSTEMS+=("rust")
  fi
  if echo "$tree" | grep -qE '(^|/)(pyproject\.toml|requirements\.txt)$'; then
    ECOSYSTEMS+=("python")
  fi
  if echo "$tree" | grep -qE '\.tf$'; then
    ECOSYSTEMS+=("terraform")
  fi
  if echo "$tree" | grep -qE '\.github/workflows/.*\.yml$'; then
    ECOSYSTEMS+=("github-actions")
  fi
}

# ---------------------------------------------------------------------------
# Check: Required workflows exist
# ---------------------------------------------------------------------------
check_required_workflows() {
  local repo="$1"

  for wf in "${REQUIRED_WORKFLOWS[@]}"; do
    if ! gh_api "repos/$ORG/$repo/contents/.github/workflows/$wf" --jq '.name' > /dev/null 2>&1; then
      add_finding "$repo" "ci-workflows" "missing-$wf" "error" \
        "Required workflow \`$wf\` is missing" \
        "standards/ci-standards.md#required-workflows"
    fi
  done
}

# ---------------------------------------------------------------------------
# Check: Action SHA pinning
# ---------------------------------------------------------------------------
check_action_pinning() {
  local repo="$1"

  # List workflow files
  local workflows
  workflows=$(gh_api "repos/$ORG/$repo/contents/.github/workflows" --jq '.[].name' 2>/dev/null || echo "")

  for wf in $workflows; do
    [[ "$wf" != *.yml && "$wf" != *.yaml ]] && continue

    local content
    content=$(gh_api "repos/$ORG/$repo/contents/.github/workflows/$wf" --jq '.content' 2>/dev/null || echo "")
    [ -z "$content" ] && continue

    local decoded
    decoded=$(echo "$content" | base64 -d 2>/dev/null || echo "")
    [ -z "$decoded" ] && continue

    # Find uses: directives that are NOT SHA-pinned
    # SHA-pinned: uses: owner/action@<40+ hex chars>
    # Exclude docker:// and ./ references
    local unpinned
    unpinned=$(echo "$decoded" | grep -E '^\s*-?\s*uses:\s+[^#]*@' | grep -vE '@[0-9a-f]{40}' | grep -vE '(docker://|\.\/)' || true)

    if [ -n "$unpinned" ]; then
      local count
      count=$(echo "$unpinned" | wc -l | tr -d ' ')
      local examples
      examples=$(echo "$unpinned" | head -3 | sed 's/^[[:space:]]*//' | paste -sd ', ' -)
      add_finding "$repo" "action-pinning" "unpinned-actions-$wf" "error" \
        "Workflow \`$wf\` has $count action(s) not pinned to SHA: $examples" \
        "standards/ci-standards.md#action-pinning-policy"
    fi
  done
}

# ---------------------------------------------------------------------------
# Check: Dependabot configuration
# ---------------------------------------------------------------------------
check_dependabot_config() {
  local repo="$1"

  local content
  content=$(gh_api "repos/$ORG/$repo/contents/.github/dependabot.yml" --jq '.content' 2>/dev/null || echo "")

  if [ -z "$content" ]; then
    add_finding "$repo" "dependabot" "missing-config" "error" \
      "Missing \`.github/dependabot.yml\` configuration file" \
      "standards/dependabot-policy.md"
    return
  fi

  local decoded
  decoded=$(echo "$content" | base64 -d 2>/dev/null || echo "")

  # Check github-actions ecosystem entry exists
  if ! echo "$decoded" | grep -q 'package-ecosystem:.*"github-actions"'; then
    add_finding "$repo" "dependabot" "missing-github-actions-ecosystem" "error" \
      "Dependabot config missing \`github-actions\` ecosystem entry" \
      "standards/dependabot-policy.md#github-actions-all-repos"
  fi

  # Check that app ecosystem entries use open-pull-requests-limit: 0
  # Extract ecosystem blocks and check limits
  for eco in npm pip gomod cargo terraform; do
    if echo "$decoded" | grep -q "package-ecosystem:.*\"$eco\""; then
      # Check if this ecosystem has limit: 0
      # Simple heuristic: find the ecosystem line and look for limit in the next ~10 lines
      local block
      block=$(echo "$decoded" | awk "/package-ecosystem:.*\"$eco\"/{found=1} found{print; if(/package-ecosystem:/ && NR>1 && !/\"$eco\"/) exit}" | head -15)
      local limit
      limit=$(echo "$block" | grep 'open-pull-requests-limit:' | head -1 | grep -oE '[0-9]+' || echo "")
      if [ -n "$limit" ] && [ "$limit" != "0" ]; then
        add_finding "$repo" "dependabot" "wrong-limit-$eco" "warning" \
          "Dependabot \`$eco\` ecosystem has \`open-pull-requests-limit: $limit\` (should be \`0\` for security-only policy)" \
          "standards/dependabot-policy.md#policy"
      fi
    fi
  done

  # Check for required labels in dependabot config
  if ! echo "$decoded" | grep -q '"security"'; then
    add_finding "$repo" "dependabot" "missing-security-label" "warning" \
      "Dependabot config missing \`security\` label on updates" \
      "standards/dependabot-policy.md#policy"
  fi
  if ! echo "$decoded" | grep -q '"dependencies"'; then
    add_finding "$repo" "dependabot" "missing-dependencies-label" "warning" \
      "Dependabot config missing \`dependencies\` label on updates" \
      "standards/dependabot-policy.md#policy"
  fi
}

# ---------------------------------------------------------------------------
# Check: Repository settings
# ---------------------------------------------------------------------------
check_repo_settings() {
  local repo="$1"

  local settings
  settings=$(gh_api "repos/$ORG/$repo" --jq '{
    allow_auto_merge: .allow_auto_merge,
    delete_branch_on_merge: .delete_branch_on_merge,
    has_wiki: .has_wiki,
    has_discussions: .has_discussions,
    default_branch: .default_branch,
    has_issues: .has_issues
  }' 2>/dev/null || echo "{}")

  [ "$settings" = "{}" ] && return

  # Boolean settings checks
  for entry in "${REQUIRED_SETTINGS_BOOL[@]}"; do
    IFS=':' read -r key expected detail <<< "$entry"
    local actual
    actual=$(echo "$settings" | jq -r ".$key // \"null\"")
    if [ "$actual" != "$expected" ]; then
      add_finding "$repo" "settings" "$key" "warning" \
        "$detail (current: \`$actual\`, expected: \`$expected\`)" \
        "standards/github-settings.md#repository-settings--standard-defaults"
    fi
  done

  # Default branch
  local default_branch
  default_branch=$(echo "$settings" | jq -r '.default_branch')
  if [ "$default_branch" != "main" ]; then
    add_finding "$repo" "settings" "default-branch" "error" \
      "Default branch is \`$default_branch\`, should be \`main\`" \
      "standards/github-settings.md#general"
  fi

  # Discussions
  local has_discussions
  has_discussions=$(echo "$settings" | jq -r '.has_discussions')
  if [ "$has_discussions" != "true" ]; then
    add_finding "$repo" "settings" "has-discussions" "warning" \
      "Discussions should be enabled for community engagement" \
      "standards/github-settings.md#general"
  fi
}

# ---------------------------------------------------------------------------
# Check: Required labels
# ---------------------------------------------------------------------------
check_labels() {
  local repo="$1"

  local existing_labels
  existing_labels=$(gh_api "repos/$ORG/$repo/labels" --jq '.[].name' --paginate 2>/dev/null || echo "")

  for label in "${REQUIRED_LABELS[@]}"; do
    if ! echo "$existing_labels" | grep -qx "$label"; then
      add_finding "$repo" "labels" "missing-label-$label" "warning" \
        "Required label \`$label\` is missing" \
        "standards/github-settings.md#labels--standard-set"
    fi
  done
}

# ---------------------------------------------------------------------------
# Check: Repository rulesets
# ---------------------------------------------------------------------------
check_rulesets() {
  local repo="$1"

  local rulesets
  rulesets=$(gh_api "repos/$ORG/$repo/rulesets" --jq '.[].name' 2>/dev/null || echo "")

  if ! echo "$rulesets" | grep -qx "pr-quality"; then
    add_finding "$repo" "rulesets" "missing-pr-quality" "error" \
      "Missing \`pr-quality\` repository ruleset" \
      "standards/github-settings.md#pr-quality--standard-ruleset-all-repositories"
  fi

  if ! echo "$rulesets" | grep -qx "code-quality"; then
    add_finding "$repo" "rulesets" "missing-code-quality" "error" \
      "Missing \`code-quality\` repository ruleset (required status checks)" \
      "standards/github-settings.md#code-quality--required-checks-ruleset-all-repositories"
  fi
}

# ---------------------------------------------------------------------------
# Check: CODEOWNERS
# ---------------------------------------------------------------------------
check_codeowners() {
  local repo="$1"

  # CODEOWNERS can be in root, .github/, or docs/
  local found=false
  for path in CODEOWNERS .github/CODEOWNERS docs/CODEOWNERS; do
    if gh_api "repos/$ORG/$repo/contents/$path" --jq '.name' > /dev/null 2>&1; then
      found=true
      break
    fi
  done

  if [ "$found" = false ]; then
    add_finding "$repo" "settings" "missing-codeowners" "warning" \
      "No \`CODEOWNERS\` file found — recommended for code owner review enforcement" \
      "standards/github-settings.md#pr-quality--standard-ruleset-all-repositories"
  fi
}

# ---------------------------------------------------------------------------
# Check: SonarCloud project properties
# ---------------------------------------------------------------------------
check_sonarcloud() {
  local repo="$1"

  # Only check if sonarcloud.yml exists
  if gh_api "repos/$ORG/$repo/contents/.github/workflows/sonarcloud.yml" --jq '.name' > /dev/null 2>&1; then
    if ! gh_api "repos/$ORG/$repo/contents/sonar-project.properties" --jq '.name' > /dev/null 2>&1; then
      add_finding "$repo" "ci-workflows" "missing-sonar-properties" "warning" \
        "SonarCloud workflow exists but \`sonar-project.properties\` is missing" \
        "standards/ci-standards.md#3-sonarcloud-analysis-sonarcloudyml"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Check: Workflow permissions follow least-privilege
# ---------------------------------------------------------------------------
check_workflow_permissions() {
  local repo="$1"

  local workflows
  workflows=$(gh_api "repos/$ORG/$repo/contents/.github/workflows" --jq '.[].name' 2>/dev/null || echo "")

  for wf in $workflows; do
    [[ "$wf" != *.yml && "$wf" != *.yaml ]] && continue

    local content
    content=$(gh_api "repos/$ORG/$repo/contents/.github/workflows/$wf" --jq '.content' 2>/dev/null || echo "")
    [ -z "$content" ] && continue

    local decoded
    decoded=$(echo "$content" | base64 -d 2>/dev/null || echo "")
    [ -z "$decoded" ] && continue

    # Check if the workflow has a top-level permissions key
    # Single-job workflows may define permissions at job level instead
    if ! echo "$decoded" | grep -qE '^permissions:'; then
      # Count jobs and check if the single job has job-level permissions
      local job_count
      job_count=$(echo "$decoded" | grep -cE '^  [a-zA-Z_-]+:$' || echo "0")
      local has_job_perms
      has_job_perms=$(echo "$decoded" | grep -cE '^    permissions:' || echo "0")
      if [ "$job_count" -gt 1 ] || [ "$has_job_perms" -eq 0 ]; then
        add_finding "$repo" "ci-workflows" "missing-permissions-$wf" "warning" \
          "Workflow \`$wf\` missing top-level \`permissions:\` declaration (least-privilege policy)" \
          "standards/ci-standards.md#permissions-policy"
      fi
    fi
  done
}

# ---------------------------------------------------------------------------
# Check: CLAUDE.md exists and references AGENTS.md
# ---------------------------------------------------------------------------
check_claude_md() {
  local repo="$1"

  local content
  content=$(gh_api "repos/$ORG/$repo/contents/CLAUDE.md" --jq '.content' 2>/dev/null || echo "")

  if [ -z "$content" ]; then
    add_finding "$repo" "standards" "missing-claude-md" "error" \
      "Missing \`CLAUDE.md\` — every repo must have a CLAUDE.md that references AGENTS.md" \
      "AGENTS.md"
    return
  fi

  local decoded
  decoded=$(echo "$content" | base64 -d 2>/dev/null || echo "")

  if ! echo "$decoded" | grep -qi 'AGENTS\.md'; then
    add_finding "$repo" "standards" "claude-md-missing-agents-ref" "error" \
      "\`CLAUDE.md\` does not reference \`AGENTS.md\`" \
      "AGENTS.md"
  fi
}

# ---------------------------------------------------------------------------
# Check: AGENTS.md exists and references org .github/AGENTS.md
# ---------------------------------------------------------------------------
check_agents_md() {
  local repo="$1"

  local content
  content=$(gh_api "repos/$ORG/$repo/contents/AGENTS.md" --jq '.content' 2>/dev/null || echo "")

  if [ -z "$content" ]; then
    add_finding "$repo" "standards" "missing-agents-md" "error" \
      "Missing \`AGENTS.md\` — every repo must have an AGENTS.md that references the org-level standards" \
      "AGENTS.md"
    return
  fi

  # For repos other than .github, AGENTS.md should reference the org-level .github/AGENTS.md
  if [ "$repo" != ".github" ]; then
    local decoded
    decoded=$(echo "$content" | base64 -d 2>/dev/null || echo "")

    if ! echo "$decoded" | grep -qE '\.github/AGENTS\.md'; then
      add_finding "$repo" "standards" "agents-md-missing-org-ref" "error" \
        "\`AGENTS.md\` does not reference the org-level \`.github/AGENTS.md\` standards" \
        "AGENTS.md"
    fi
  fi
}

# ---------------------------------------------------------------------------
# Issue management
# ---------------------------------------------------------------------------
ensure_audit_label() {
  local repo="$1"
  gh label create "$AUDIT_LABEL" \
    --repo "$ORG/$repo" \
    --description "$AUDIT_LABEL_DESC" \
    --color "$AUDIT_LABEL_COLOR" \
    --force 2>/dev/null || true
}

ensure_required_labels() {
  local repo="$1"
  for config in "${REQUIRED_LABEL_CONFIGS[@]}"; do
    local name color description
    name="${config%%:*}"
    color="${config#*:}"
    description="${color#*:}"
    color="${color%%:*}"
    gh label create "$name" \
      --repo "$ORG/$repo" \
      --description "$description" \
      --color "$color" \
      --force 2>/dev/null || true
  done
}

create_issue_for_finding() {
  local repo="$1" category="$2" check="$3" severity="$4" detail="$5" standard_ref="$6"

  local title="Compliance: ${check}"
  # Normalize title for search
  local search_title="${title}"

  # Check for existing open issue with same title
  local existing
  existing=$(gh issue list --repo "$ORG/$repo" \
    --label "$AUDIT_LABEL" \
    --state open \
    --search "\"$search_title\" in:title" \
    --json number,title \
    -q ".[] | select(.title == \"$search_title\") | .number" \
    2>/dev/null | head -1 || echo "")

  if [ -n "$existing" ]; then
    # Update existing issue with a comment
    gh issue comment "$existing" --repo "$ORG/$repo" \
      --body "**Weekly Compliance Audit** ($(date -u +%Y-%m-%d))

This finding is still open.

**Detail:** $detail

**Standard:** [$standard_ref](https://github.com/$ORG/.github/blob/main/$standard_ref)" 2>/dev/null || true
    info "Updated existing issue #$existing in $repo for: $check"
    return
  fi

  # Build issue body — variable values are safe (from our own check logic + GitHub API)
  local body="## Compliance Finding

**Category:** \`${category}\`
**Severity:** \`${severity}\`
**Check:** \`${check}\`

## Detail

${detail}

## Standard Reference

[${standard_ref}](https://github.com/${ORG}/.github/blob/main/${standard_ref})

## Remediation

Please review the linked standard and bring this repository into compliance.

See the [full standards documentation](https://github.com/${ORG}/.github/tree/main/standards) for implementation guidance.

---
*This issue was automatically created by the [weekly compliance audit](https://github.com/${ORG}/.github/blob/main/.github/workflows/compliance-audit.yml).*"

  local issue_url
  issue_url=$(gh issue create --repo "$ORG/$repo" \
    --title "$search_title" \
    --label "$AUDIT_LABEL" \
    --label "claude" \
    --body "$body" 2>/dev/null || echo "")

  if [ -n "$issue_url" ]; then
    local new_issue
    new_issue=$(echo "$issue_url" | grep -oE '[0-9]+$' || echo "")
    info "Created issue #$new_issue in $repo for: $check ($issue_url)"

    # Attempt to assign to claude — the bot user for Claude Code Action
    if [ -n "$new_issue" ]; then
      gh issue edit "$new_issue" --repo "$ORG/$repo" --add-assignee "app/claude" 2>/dev/null || true
    fi
  else
    warn "Failed to create issue in $repo for: $check"
  fi
}

close_resolved_issues() {
  local repo="$1"

  # Get all open compliance-audit issues
  local open_issues
  open_issues=$(gh issue list --repo "$ORG/$repo" \
    --label "$AUDIT_LABEL" \
    --state open \
    --json number,title \
    -q '.[] | "\(.number)\t\(.title)"' 2>/dev/null || echo "")

  [ -z "$open_issues" ] && return

  # Get current findings for this repo (bail if jq fails to avoid false closures)
  local current_checks
  if ! current_checks=$(jq -r --arg repo "$repo" '.[] | select(.repo == $repo) | .check' "$FINDINGS_FILE" 2>/dev/null); then
    warn "Failed to read findings for $repo — skipping issue closure to avoid false positives"
    return
  fi

  while IFS=$'\t' read -r issue_num issue_title; do
    # Extract the check name from the title "Compliance: <check>"
    local check_name="${issue_title#Compliance: }"

    # If this check is no longer in findings, close the issue
    if ! echo "$current_checks" | grep -qx "$check_name"; then
      gh issue close "$issue_num" --repo "$ORG/$repo" \
        --comment "Resolved! This check is now passing as of $(date -u +%Y-%m-%d). Closing automatically." \
        2>/dev/null || true
      info "Closed resolved issue #$issue_num in $repo: $issue_title"
    fi
  done <<< "$open_issues"
}

# ---------------------------------------------------------------------------
# Summary generation
# ---------------------------------------------------------------------------
generate_summary() {
  local total_repos="$1"
  local total_findings
  total_findings=$(jq length "$FINDINGS_FILE")

  local error_count
  error_count=$(jq '[.[] | select(.severity == "error")] | length' "$FINDINGS_FILE")
  local warning_count
  warning_count=$(jq '[.[] | select(.severity == "warning")] | length' "$FINDINGS_FILE")

  cat > "$SUMMARY_FILE" <<HEREDOC
# Org Compliance Audit Report — $(date -u +%Y-%m-%d)

## Summary

| Metric | Count |
|--------|-------|
| Repositories audited | $total_repos |
| Total findings | $total_findings |
| Errors (must fix) | $error_count |
| Warnings (should fix) | $warning_count |

## Findings by Repository

HEREDOC

  # Group findings by repo
  local repos_with_findings
  repos_with_findings=$(jq -r '[.[].repo] | unique[]' "$FINDINGS_FILE")

  if [ -z "$repos_with_findings" ]; then
    echo "All repositories are fully compliant! No findings." >> "$SUMMARY_FILE"
    return
  fi

  for repo in $repos_with_findings; do
    local repo_findings
    repo_findings=$(jq -r --arg repo "$repo" \
      '.[] | select(.repo == $repo) | "| `\(.severity)` | \(.category) | \(.check) | \(.detail) |"' \
      "$FINDINGS_FILE")

    local repo_count
    repo_count=$(jq --arg repo "$repo" '[.[] | select(.repo == $repo)] | length' "$FINDINGS_FILE")

    cat >> "$SUMMARY_FILE" <<HEREDOC
### [$repo](https://github.com/$ORG/$repo) — $repo_count finding(s)

| Severity | Category | Check | Detail |
|----------|----------|-------|--------|
$repo_findings

HEREDOC
  done

  # Category breakdown
  cat >> "$SUMMARY_FILE" <<HEREDOC
## Findings by Category

HEREDOC

  for category in ci-workflows action-pinning dependabot settings labels rulesets standards; do
    local cat_count
    cat_count=$(jq --arg cat "$category" '[.[] | select(.category == $cat)] | length' "$FINDINGS_FILE")
    if [ "$cat_count" -gt 0 ]; then
      echo "- **$category:** $cat_count finding(s)" >> "$SUMMARY_FILE"
    fi
  done

  cat >> "$SUMMARY_FILE" <<HEREDOC

---
*Generated by the [weekly compliance audit](https://github.com/$ORG/.github/blob/main/.github/workflows/compliance-audit.yml) on $(date -u "+%Y-%m-%d %H:%M UTC").*
HEREDOC
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  info "Starting compliance audit for $ORG"
  info "Report directory: $REPORT_DIR"
  info "Dry run: $DRY_RUN"

  # Initialize findings file
  echo "[]" > "$FINDINGS_FILE"

  # Get all non-archived repos in the org
  local repos
  repos=$(gh repo list "$ORG" --no-archived --json name -q '.[].name' --limit 500)

  if [ -z "$repos" ]; then
    warn "No repositories found in $ORG — check GH_TOKEN permissions"
    echo "[]" > "$FINDINGS_FILE"
    return 1
  fi

  local repo_count=0

  for repo in $repos; do
    repo_count=$((repo_count + 1))
    log "Auditing $ORG/$repo"

    detect_ecosystems "$repo"
    if [ ${#ECOSYSTEMS[@]} -eq 0 ]; then
      info "Detected ecosystems: none"
    else
      info "Detected ecosystems: ${ECOSYSTEMS[*]}"
    fi

    check_required_workflows "$repo"
    check_action_pinning "$repo"
    check_dependabot_config "$repo"
    check_repo_settings "$repo"
    check_labels "$repo"
    check_rulesets "$repo"
    check_codeowners "$repo"
    check_sonarcloud "$repo"
    check_workflow_permissions "$repo"
    check_claude_md "$repo"
    check_agents_md "$repo"

    log_end
  done

  info "Audit complete: $findings_count findings across $repo_count repositories"

  # Generate summary report
  generate_summary "$repo_count"

  # Create/update/close issues
  if [ "$CREATE_ISSUES" = "true" ] && [ "$DRY_RUN" != "true" ]; then
    info "Managing issues..."

    for repo in $repos; do
      ensure_audit_label "$repo"
      ensure_required_labels "$repo"

      # Create issues for new findings (process substitution avoids subshell)
      while IFS= read -r finding; do
        [ -z "$finding" ] && continue
        local f_check f_severity f_detail f_standard_ref f_category
        f_category=$(echo "$finding" | jq -r '.category')
        f_check=$(echo "$finding" | jq -r '.check')
        f_severity=$(echo "$finding" | jq -r '.severity')
        f_detail=$(echo "$finding" | jq -r '.detail')
        f_standard_ref=$(echo "$finding" | jq -r '.standard_ref')

        create_issue_for_finding "$repo" "$f_category" "$f_check" "$f_severity" "$f_detail" "$f_standard_ref"
      done < <(jq -c --arg repo "$repo" '.[] | select(.repo == $repo)' "$FINDINGS_FILE")

      # Close issues for resolved findings
      close_resolved_issues "$repo"
    done
  else
    info "Skipping issue creation (DRY_RUN=$DRY_RUN, CREATE_ISSUES=$CREATE_ISSUES)"
  fi

  # Output report paths
  echo "findings=$FINDINGS_FILE"
  echo "summary=$SUMMARY_FILE"

  info "Summary written to $SUMMARY_FILE"
  info "Findings written to $FINDINGS_FILE"

  cat "$SUMMARY_FILE"
}

main "$@"
