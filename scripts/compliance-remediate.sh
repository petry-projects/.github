#!/usr/bin/env bash
# compliance-remediate.sh — Auto-remediate recurring compliance-audit findings
#
# Reads findings.json produced by compliance-audit.sh and closes the
# audit → report → auto-fix → PR loop.
#
# Remediations fall into two categories:
#   1. Direct API fixes  — applied immediately (no PR): repo settings, labels
#   2. PR-based fixes    — open a branch + PR in the target repo: CODEOWNERS,
#                          action SHA pinning
#
# Findings that cannot be safely auto-remediated are logged as skipped so
# a Claude agent or human can pick them up.
#
# Usage:
#   FINDINGS_FILE=/path/to/findings.json bash scripts/compliance-remediate.sh
#   DRY_RUN=true FINDINGS_FILE=/path/to/findings.json bash scripts/compliance-remediate.sh
#
# Environment variables:
#   GH_TOKEN       GitHub token with repo/org scope (required)
#   FINDINGS_FILE  Path to findings.json from compliance-audit.sh (required)
#   REPORT_DIR     Directory for remediation report output (default: mktemp -d)
#   DRY_RUN        Set to "true" to preview changes without applying (default: false)

set -uo pipefail   # Note: no -e so per-repo errors don't abort the whole run

ORG="petry-projects"
FINDINGS_FILE="${FINDINGS_FILE:-}"
REPORT_DIR="${REPORT_DIR:-$(mktemp -d)}"
DRY_RUN="${DRY_RUN:-false}"

REMEDIATION_REPORT="$REPORT_DIR/remediation-report.md"
SKIPPED_REPORT="$REPORT_DIR/skipped.md"

# ---------------------------------------------------------------------------
# Label definitions — from standards/github-settings.md#labels--standard-set
# ---------------------------------------------------------------------------
declare -A LABEL_COLORS=(
  [security]="d93f0b"
  [dependencies]="0075ca"
  [scorecard]="d93f0b"
  [bug]="d73a4a"
  [enhancement]="a2eeef"
  [documentation]="0075ca"
)

declare -A LABEL_DESCS=(
  [security]="Security-related PRs and issues"
  [dependencies]="Dependency update PRs"
  [scorecard]="OpenSSF Scorecard findings"
  [bug]="Bug reports"
  [enhancement]="Feature requests"
  [documentation]="Documentation changes"
)

# ---------------------------------------------------------------------------
# Logging helpers
# ---------------------------------------------------------------------------
info()  { echo "[INFO]  $*" >&2; }
ok()    { echo "[OK]    $*" >&2; }
warn()  { echo "[WARN]  $*" >&2; }
skip()  { echo "[SKIP]  $*" >&2; }
err()   { echo "[ERROR] $*" >&2; }

# Counters
remediated_direct=0
remediated_pr=0
skipped_count=0
failed_count=0

# ---------------------------------------------------------------------------
# Append to reports
# ---------------------------------------------------------------------------
report_direct() {
  local repo="$1" check="$2" action="$3"
  echo "| \`$repo\` | \`$check\` | Direct API | $action |" >> "$REMEDIATION_REPORT"
  remediated_direct=$((remediated_direct + 1))
}

report_pr() {
  local repo="$1" check="$2" pr_url="$3"
  echo "| \`$repo\` | \`$check\` | PR | $pr_url |" >> "$REMEDIATION_REPORT"
  remediated_pr=$((remediated_pr + 1))
}

report_skip() {
  local repo="$1" check="$2" reason="$3"
  echo "| \`$repo\` | \`$check\` | $reason |" >> "$SKIPPED_REPORT"
  skipped_count=$((skipped_count + 1))
}

report_fail() {
  local repo="$1" check="$2" detail="$3"
  echo "| \`$repo\` | \`$check\` | FAILED: $detail |" >> "$SKIPPED_REPORT"
  failed_count=$((failed_count + 1))
}

# ---------------------------------------------------------------------------
# Direct API: repository settings
# ---------------------------------------------------------------------------
remediate_setting() {
  local repo="$1" setting="$2" expected_value="$3" check="$4"

  if [ "$DRY_RUN" = "true" ]; then
    skip "[DRY] Would PATCH $ORG/$repo: $setting=$expected_value"
    report_direct "$repo" "$check" "DRY: would PATCH \`$setting=$expected_value\`"
    return 0
  fi

  if gh api -X PATCH "repos/$ORG/$repo" -F "$setting=$expected_value" > /dev/null 2>&1; then
    ok "Fixed $ORG/$repo: $setting=$expected_value"
    report_direct "$repo" "$check" "Set \`$setting=$expected_value\`"
  else
    err "Failed to patch $ORG/$repo: $setting=$expected_value"
    report_fail "$repo" "$check" "PATCH $setting=$expected_value failed"
  fi
}

# ---------------------------------------------------------------------------
# Direct API: create missing label
# ---------------------------------------------------------------------------
remediate_label() {
  local repo="$1" label="$2"

  local color="${LABEL_COLORS[$label]:-e4e669}"
  local desc="${LABEL_DESCS[$label]:-}"

  if [ "$DRY_RUN" = "true" ]; then
    skip "[DRY] Would create label '$label' in $ORG/$repo"
    report_direct "$repo" "missing-label-$label" "DRY: would create label \`$label\`"
    return 0
  fi

  if gh label create "$label" \
      --repo "$ORG/$repo" \
      --color "$color" \
      --description "$desc" \
      --force 2>/dev/null; then
    ok "Created/updated label '$label' in $ORG/$repo"
    report_direct "$repo" "missing-label-$label" "Created label \`$label\` (#$color)"
  else
    err "Failed to create label '$label' in $ORG/$repo"
    report_fail "$repo" "missing-label-$label" "gh label create failed"
  fi
}

# ---------------------------------------------------------------------------
# PR-based: generate CODEOWNERS
# ---------------------------------------------------------------------------
remediate_codeowners() {
  local repo="$1"

  info "Generating CODEOWNERS for $ORG/$repo ..."

  # Fetch org admins to use as fallback owners
  local admins
  admins=$(gh api "orgs/$ORG/members?role=admin" --jq '.[].login' 2>/dev/null || echo "")

  if [ -z "$admins" ]; then
    warn "Could not fetch org admins for $ORG — skipping CODEOWNERS generation for $repo"
    report_skip "$repo" "missing-codeowners" "Could not resolve org admins via API"
    return 0
  fi

  # Build CODEOWNERS content
  local owner_line=""
  for admin in $admins; do
    owner_line="$owner_line @$admin"
  done
  owner_line="${owner_line# }"  # trim leading space

  local codeowners_content="# CODEOWNERS — auto-generated by compliance-remediate.sh
# Review and adjust to match actual ownership.
# Ref: standards/github-settings.md#pr-quality--standard-ruleset-all-repositories

*  $owner_line
"

  if [ "$DRY_RUN" = "true" ]; then
    skip "[DRY] Would create .github/CODEOWNERS in $ORG/$repo with owners: $owner_line"
    report_direct "$repo" "missing-codeowners" "DRY: would create \`.github/CODEOWNERS\` (owners: $owner_line)"
    return 0
  fi

  # Get default branch SHA
  local default_branch
  default_branch=$(gh api "repos/$ORG/$repo" --jq '.default_branch' 2>/dev/null || echo "main")

  local base_sha
  base_sha=$(gh api "repos/$ORG/$repo/git/refs/heads/$default_branch" --jq '.object.sha' 2>/dev/null || echo "")

  if [ -z "$base_sha" ]; then
    warn "Could not get HEAD SHA for $ORG/$repo/$default_branch"
    report_fail "$repo" "missing-codeowners" "Could not resolve HEAD SHA for $default_branch"
    return 0
  fi

  local branch_name="fix/compliance-codeowners-$(date +%Y%m%d)"

  # Check if branch already exists; append timestamp suffix if needed
  if gh api "repos/$ORG/$repo/git/refs/heads/$branch_name" > /dev/null 2>&1; then
    branch_name="fix/compliance-codeowners-$(date +%Y%m%d-%H%M%S)"
  fi

  # Create the branch
  if ! gh api -X POST "repos/$ORG/$repo/git/refs" \
      -f ref="refs/heads/$branch_name" \
      -f sha="$base_sha" > /dev/null 2>&1; then
    err "Failed to create branch $branch_name in $ORG/$repo"
    report_fail "$repo" "missing-codeowners" "Could not create branch $branch_name"
    return 0
  fi

  # Create the file via Contents API
  local encoded_content
  encoded_content=$(printf '%s' "$codeowners_content" | base64 -w 0)

  if ! gh api -X PUT "repos/$ORG/$repo/contents/.github/CODEOWNERS" \
      -f message="fix: add CODEOWNERS (compliance remediation)" \
      -f content="$encoded_content" \
      -f branch="$branch_name" > /dev/null 2>&1; then
    err "Failed to create .github/CODEOWNERS in $ORG/$repo"
    # Clean up the branch
    gh api -X DELETE "repos/$ORG/$repo/git/refs/heads/$branch_name" > /dev/null 2>&1 || true
    report_fail "$repo" "missing-codeowners" "Could not create file via Contents API"
    return 0
  fi

  # Open PR
  local pr_url
  pr_url=$(gh pr create \
    --repo "$ORG/$repo" \
    --head "$branch_name" \
    --base "$default_branch" \
    --title "fix: add CODEOWNERS (compliance remediation)" \
    --body "## Summary

Adds a \`.github/CODEOWNERS\` file generated by the compliance remediation workflow.

**Auto-generated owners:** $owner_line

> **Please review and update** to reflect the actual ownership structure of this repo.
> The org admins have been used as fallback owners.

## Context

This PR was automatically created by \`scripts/compliance-remediate.sh\` to resolve
the \`missing-codeowners\` compliance finding.

Ref: \`standards/github-settings.md#pr-quality--standard-ruleset-all-repositories\`" \
    --label "compliance-audit" 2>/dev/null || echo "")

  if [ -n "$pr_url" ]; then
    ok "Opened CODEOWNERS PR in $ORG/$repo: $pr_url"
    report_pr "$repo" "missing-codeowners" "$pr_url"
  else
    warn "Branch created but PR creation failed for $ORG/$repo (may already exist)"
    report_fail "$repo" "missing-codeowners" "PR creation failed (branch: $branch_name)"
  fi
}

# ---------------------------------------------------------------------------
# PR-based: pin unpinned GitHub Actions to SHAs
# ---------------------------------------------------------------------------
remediate_unpinned_actions() {
  local repo="$1" workflow_file="$2"

  info "Pinning actions in $ORG/$repo/.github/workflows/$workflow_file ..."

  # Fetch current workflow content
  local raw_content
  raw_content=$(gh api "repos/$ORG/$repo/contents/.github/workflows/$workflow_file" 2>/dev/null || echo "")

  if [ -z "$raw_content" ]; then
    warn "Could not fetch $workflow_file from $ORG/$repo"
    report_fail "$repo" "unpinned-actions-$workflow_file" "Could not fetch workflow file"
    return 0
  fi

  local encoded
  encoded=$(echo "$raw_content" | jq -r '.content // empty')
  local file_sha
  file_sha=$(echo "$raw_content" | jq -r '.sha // empty')

  if [ -z "$encoded" ] || [ -z "$file_sha" ]; then
    report_fail "$repo" "unpinned-actions-$workflow_file" "Could not parse file content or SHA"
    return 0
  fi

  local decoded
  decoded=$(echo "$encoded" | base64 -d 2>/dev/null || echo "")
  [ -z "$decoded" ] && { report_fail "$repo" "unpinned-actions-$workflow_file" "base64 decode failed"; return 0; }

  # Find all unpinned uses: directives
  local unpinned_refs
  unpinned_refs=$(echo "$decoded" | grep -oE 'uses:\s+[^@\s]+@[^#\s]+' | grep -vE '@[0-9a-f]{40}' | grep -vE '(docker://|\.\/)' | awk '{print $2}' | sort -u || true)

  if [ -z "$unpinned_refs" ]; then
    info "No unpinned actions found in $workflow_file (may already be fixed)"
    report_skip "$repo" "unpinned-actions-$workflow_file" "No unpinned actions found in current file (re-audit may resolve)"
    return 0
  fi

  local patched_content="$decoded"
  local pins_applied=0
  local pins_failed=0

  while IFS= read -r ref; do
    [ -z "$ref" ] && continue

    # Parse owner/action@tag
    local action_part tag_part
    action_part="${ref%@*}"
    tag_part="${ref##*@}"

    # Skip if somehow already a SHA (shouldn't happen given grep above, but be safe)
    if echo "$tag_part" | grep -qE '^[0-9a-f]{40}$'; then
      continue
    fi

    # Resolve the tag to a commit SHA
    local commit_sha=""

    # Try to get the tag's commit SHA (handle annotated tags via ^{})
    commit_sha=$(gh api "repos/$action_part/git/refs/tags/$tag_part" \
      --jq '.object | if .type == "tag" then .sha else .sha end' 2>/dev/null || echo "")

    # For annotated tags, dereference the tag object to get the commit SHA
    if [ -n "$commit_sha" ]; then
      local obj_type
      obj_type=$(gh api "repos/$action_part/git/refs/tags/$tag_part" \
        --jq '.object.type' 2>/dev/null || echo "")
      if [ "$obj_type" = "tag" ]; then
        # Annotated tag — fetch the tag object to get the commit SHA
        local tag_obj_sha="$commit_sha"
        commit_sha=$(gh api "repos/$action_part/git/tags/$tag_obj_sha" \
          --jq '.object.sha' 2>/dev/null || echo "")
      fi
    fi

    # Fallback: try branch/tag lookup via commits API
    if [ -z "$commit_sha" ]; then
      commit_sha=$(gh api "repos/$action_part/commits?sha=$tag_part&per_page=1" \
        --jq '.[0].sha' 2>/dev/null || echo "")
    fi

    if [ -z "$commit_sha" ]; then
      warn "Could not resolve SHA for $ref — skipping"
      pins_failed=$((pins_failed + 1))
      continue
    fi

    # Replace the ref in the file content: uses: owner/action@tag → uses: owner/action@sha # tag
    # Use a portable sed substitution (escape special chars in ref)
    local escaped_ref
    escaped_ref=$(printf '%s' "$ref" | sed 's/[[\.*^$()+?{|]/\\&/g')
    patched_content=$(echo "$patched_content" | sed "s|uses: ${escaped_ref}|uses: ${action_part}@${commit_sha} # ${tag_part}|g")

    ok "  Pinned $ref → $commit_sha"
    pins_applied=$((pins_applied + 1))
  done <<< "$unpinned_refs"

  if [ "$pins_applied" -eq 0 ]; then
    info "No actions could be pinned in $workflow_file (all lookups failed)"
    report_fail "$repo" "unpinned-actions-$workflow_file" "SHA resolution failed for all $pins_failed action(s)"
    return 0
  fi

  if [ "$DRY_RUN" = "true" ]; then
    skip "[DRY] Would pin $pins_applied action(s) in $ORG/$repo/.github/workflows/$workflow_file"
    report_direct "$repo" "unpinned-actions-$workflow_file" "DRY: would pin $pins_applied action(s)"
    return 0
  fi

  # Get the default branch
  local default_branch
  default_branch=$(gh api "repos/$ORG/$repo" --jq '.default_branch' 2>/dev/null || echo "main")

  local base_sha
  base_sha=$(gh api "repos/$ORG/$repo/git/refs/heads/$default_branch" --jq '.object.sha' 2>/dev/null || echo "")

  if [ -z "$base_sha" ]; then
    report_fail "$repo" "unpinned-actions-$workflow_file" "Could not resolve HEAD SHA"
    return 0
  fi

  local branch_name
  branch_name="fix/compliance-pin-actions-$(echo "$workflow_file" | sed 's/\.yml$//' | sed 's/\.yaml$//')-$(date +%Y%m%d)"

  # Ensure branch is unique
  if gh api "repos/$ORG/$repo/git/refs/heads/$branch_name" > /dev/null 2>&1; then
    branch_name="${branch_name}-$(date +%H%M%S)"
  fi

  # Create branch
  if ! gh api -X POST "repos/$ORG/$repo/git/refs" \
      -f ref="refs/heads/$branch_name" \
      -f sha="$base_sha" > /dev/null 2>&1; then
    report_fail "$repo" "unpinned-actions-$workflow_file" "Could not create branch $branch_name"
    return 0
  fi

  # Update the file via Contents API
  local new_encoded
  new_encoded=$(printf '%s' "$patched_content" | base64 -w 0)

  local commit_msg="fix: pin actions to commit SHAs in $workflow_file

Pinned $pins_applied action(s) to full commit SHAs per org security policy.
$([ "$pins_failed" -gt 0 ] && echo "$pins_failed action(s) could not be resolved and were left unpinned.")

Ref: standards/ci-standards.md#action-pinning-policy"

  if ! gh api -X PUT "repos/$ORG/$repo/contents/.github/workflows/$workflow_file" \
      -f message="$commit_msg" \
      -f content="$new_encoded" \
      -f sha="$file_sha" \
      -f branch="$branch_name" > /dev/null 2>&1; then
    # Clean up branch
    gh api -X DELETE "repos/$ORG/$repo/git/refs/heads/$branch_name" > /dev/null 2>&1 || true
    report_fail "$repo" "unpinned-actions-$workflow_file" "Contents API PUT failed"
    return 0
  fi

  # Open PR
  local failed_note=""
  [ "$pins_failed" -gt 0 ] && failed_note="

> **Note:** $pins_failed action(s) could not be resolved to SHAs and were left unchanged.
> Review the workflow file and pin them manually."

  local pr_url
  pr_url=$(gh pr create \
    --repo "$ORG/$repo" \
    --head "$branch_name" \
    --base "$default_branch" \
    --title "fix: pin actions to commit SHAs in $workflow_file" \
    --body "## Summary

Pins $pins_applied unpinned GitHub Actions to full commit SHAs in \`.github/workflows/$workflow_file\`.
$failed_note

## Why

Pinning actions to commit SHAs prevents supply-chain attacks where a tag is moved
to a different (potentially malicious) commit.

Ref: \`standards/ci-standards.md#action-pinning-policy\`

## Context

Auto-generated by \`scripts/compliance-remediate.sh\` to resolve the
\`unpinned-actions-$workflow_file\` compliance finding." \
    --label "compliance-audit" 2>/dev/null || echo "")

  if [ -n "$pr_url" ]; then
    ok "Opened action-pinning PR in $ORG/$repo: $pr_url"
    report_pr "$repo" "unpinned-actions-$workflow_file" "$pr_url"
  else
    warn "Branch created but PR creation failed for $ORG/$repo (workflow: $workflow_file)"
    report_fail "$repo" "unpinned-actions-$workflow_file" "PR creation failed (branch: $branch_name)"
  fi
}

# ---------------------------------------------------------------------------
# Dispatch a single finding to the correct remediation handler
# ---------------------------------------------------------------------------
remediate_finding() {
  local repo="$1" category="$2" check="$3"

  case "$category/$check" in
    # ----- Repository settings -----
    settings/has_wiki)
      remediate_setting "$repo" "has_wiki" "false" "$check"
      ;;
    settings/allow_auto_merge)
      remediate_setting "$repo" "allow_auto_merge" "true" "$check"
      ;;
    settings/delete_branch_on_merge)
      remediate_setting "$repo" "delete_branch_on_merge" "true" "$check"
      ;;
    settings/has_discussions)
      remediate_setting "$repo" "has_discussions" "true" "$check"
      ;;
    settings/has_issues)
      remediate_setting "$repo" "has_issues" "true" "$check"
      ;;
    settings/default-branch)
      report_skip "$repo" "$check" "Renaming default branch requires coordinated git history rewrite — manual fix required"
      ;;

    # ----- Labels -----
    labels/missing-label-*)
      local label="${check#missing-label-}"
      remediate_label "$repo" "$label"
      ;;

    # ----- CODEOWNERS -----
    settings/missing-codeowners)
      remediate_codeowners "$repo"
      ;;

    # ----- Unpinned actions -----
    action-pinning/unpinned-actions-*)
      local wf_file="${check#unpinned-actions-}"
      remediate_unpinned_actions "$repo" "$wf_file"
      ;;

    # ----- Skipped: require workflows scope or complex human judgment -----
    ci-workflows/missing-*)
      report_skip "$repo" "$check" "Creating workflow files requires \`workflow\` token scope — use a PAT or push manually"
      ;;
    rulesets/*)
      report_skip "$repo" "$check" "Ruleset creation is not yet supported by this script — configure via GitHub UI or API manually"
      ;;
    dependabot/missing-config)
      report_skip "$repo" "$check" "Generating dependabot.yml requires ecosystem detection — use \`standards/dependabot/\` templates"
      ;;
    dependabot/*)
      report_skip "$repo" "$check" "Dependabot config updates require review — fix manually using \`standards/dependabot-policy.md\`"
      ;;
    standards/missing-claude-md | standards/claude-md-missing-agents-ref)
      report_skip "$repo" "$check" "CLAUDE.md creation/update requires content knowledge — handled by Claude agent"
      ;;
    standards/missing-agents-md | standards/agents-md-missing-org-ref)
      report_skip "$repo" "$check" "AGENTS.md creation/update requires content knowledge — handled by Claude agent"
      ;;
    ci-workflows/missing-sonar-properties)
      report_skip "$repo" "$check" "sonar-project.properties requires project-specific keys — fix manually"
      ;;
    ci-workflows/missing-permissions-*)
      report_skip "$repo" "$check" "Permissions declarations require understanding each workflow's intent — fix manually"
      ;;
    *)
      report_skip "$repo" "$check" "No automatic remediation available for category=$category"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  # Validate inputs
  if [ -z "$FINDINGS_FILE" ]; then
    err "FINDINGS_FILE is required — set it to the path of findings.json from compliance-audit.sh"
    exit 1
  fi

  if [ ! -f "$FINDINGS_FILE" ]; then
    err "FINDINGS_FILE not found: $FINDINGS_FILE"
    exit 1
  fi

  if [ -z "${GH_TOKEN:-}" ]; then
    err "GH_TOKEN is required"
    exit 1
  fi

  export GH_TOKEN

  info "Starting compliance remediation"
  info "Findings file:  $FINDINGS_FILE"
  info "Report dir:     $REPORT_DIR"
  info "Dry run:        $DRY_RUN"

  mkdir -p "$REPORT_DIR"

  # Initialize report files
  cat > "$REMEDIATION_REPORT" <<'HEADER'
# Compliance Remediation Report

| Repository | Finding | Method | Action |
|------------|---------|--------|--------|
HEADER

  cat > "$SKIPPED_REPORT" <<'HEADER'
# Skipped / Failed Findings

These findings were not automatically remediated and require manual intervention or
a Claude agent to address.

| Repository | Finding | Reason |
|------------|---------|--------|
HEADER

  # Read all findings and group by repo
  local repos
  repos=$(jq -r '[.[].repo] | unique[]' "$FINDINGS_FILE" 2>/dev/null || echo "")

  if [ -z "$repos" ]; then
    info "No findings to remediate — nothing to do"
    exit 0
  fi

  for repo in $repos; do
    info "--- Remediating findings for $ORG/$repo ---"

    # Process each finding for this repo
    while IFS= read -r finding; do
      [ -z "$finding" ] && continue

      local category check
      category=$(echo "$finding" | jq -r '.category')
      check=$(echo "$finding" | jq -r '.check')

      info "  Processing: $category/$check"
      remediate_finding "$repo" "$category" "$check" || {
        err "Unhandled error remediating $category/$check in $repo"
        report_fail "$repo" "$check" "Unhandled script error"
      }
    done < <(jq -c --arg repo "$repo" '.[] | select(.repo == $repo)' "$FINDINGS_FILE")
  done

  # Final summary
  local total=$((remediated_direct + remediated_pr + skipped_count + failed_count))
  info "=== Remediation complete ==="
  info "  Direct fixes applied: $remediated_direct"
  info "  PRs opened:           $remediated_pr"
  info "  Skipped:              $skipped_count"
  info "  Failed:               $failed_count"
  info "  Total processed:      $total"

  # Append summary to report
  cat >> "$REMEDIATION_REPORT" <<SUMMARY

## Summary

| Metric | Count |
|--------|-------|
| Direct API fixes | $remediated_direct |
| PRs opened | $remediated_pr |
| Skipped (manual required) | $skipped_count |
| Failed | $failed_count |
| **Total processed** | **$total** |

*Generated by \`scripts/compliance-remediate.sh\` on $(date -u "+%Y-%m-%d %H:%M UTC").*
SUMMARY

  echo "remediation_report=$REMEDIATION_REPORT"
  echo "skipped_report=$SKIPPED_REPORT"
  echo "remediated_direct=$remediated_direct"
  echo "remediated_pr=$remediated_pr"
  echo "skipped=$skipped_count"
  echo "failed=$failed_count"

  cat "$REMEDIATION_REPORT"

  if [ "$skipped_count" -gt 0 ] || [ "$failed_count" -gt 0 ]; then
    echo ""
    cat "$SKIPPED_REPORT"
  fi

  # Exit non-zero if there were failures (not skips — skips are expected)
  [ "$failed_count" -gt 0 ] && exit 1 || exit 0
}

main "$@"
