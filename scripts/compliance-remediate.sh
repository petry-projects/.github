#!/usr/bin/env bash
# compliance-remediate.sh — Auto-remediate common compliance-audit findings
#
# Reads findings.json produced by compliance-audit.sh and applies fixes
# where auto-remediation is safe and deterministic.
#
# Remediation strategies:
#   DIRECT — Applied immediately via GitHub API (settings, labels)
#   PR     — Creates a pull request in the target repo (CODEOWNERS, action pinning)
#   SKIP   — Not auto-remediable; requires manual intervention or Claude agent
#
# Outputs:
#   $REPORT_DIR/remediation-report.json   — machine-readable results
#   $REPORT_DIR/remediation-summary.md    — human-readable report
#
# Environment variables:
#   GH_TOKEN        — GitHub token with repo/org scope (required)
#   FINDINGS_FILE   — path to findings.json from compliance-audit.sh (required)
#   DRY_RUN         — "true" to log actions without executing (default: false)
#   REPORT_DIR      — directory for output files (default: mktemp -d)

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
ORG="petry-projects"
FINDINGS_FILE="${FINDINGS_FILE:-}"
DRY_RUN="${DRY_RUN:-false}"
REPORT_DIR="${REPORT_DIR:-$(mktemp -d)}"

REMEDIATION_REPORT="$REPORT_DIR/remediation-report.json"
REMEDIATION_SUMMARY="$REPORT_DIR/remediation-summary.md"

# Label definitions matching org standards (github-settings.md#labels)
declare -A LABEL_COLORS=(
  ["security"]="d93f0b"
  ["dependencies"]="0075ca"
  ["scorecard"]="d93f0b"
  ["bug"]="d73a4a"
  ["enhancement"]="a2eeef"
  ["documentation"]="0075ca"
  ["claude"]="8B5CF6"
  ["compliance-audit"]="7057ff"
)

declare -A LABEL_DESCS=(
  ["security"]="Security-related PRs and issues"
  ["dependencies"]="Dependency update PRs"
  ["scorecard"]="OpenSSF Scorecard findings"
  ["bug"]="Bug reports"
  ["enhancement"]="Feature requests"
  ["documentation"]="Documentation changes"
  ["claude"]="For Claude agent pickup"
  ["compliance-audit"]="Automated compliance audit finding"
)

# ---------------------------------------------------------------------------
# Tracking
# ---------------------------------------------------------------------------
remediated_count=0
skipped_count=0
failed_count=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()      { echo "[INFO] $*" >&2; }
warn()     { echo "::warning::$*" >&2; }
dry_log()  { echo "[DRY RUN] $*" >&2; }

record_result() {
  local repo="$1" check="$2" strategy="$3" status="$4" detail="$5" pr_url="${6:-}"

  local entry
  entry=$(jq -n \
    --arg repo "$repo" \
    --arg check "$check" \
    --arg strategy "$strategy" \
    --arg status "$status" \
    --arg detail "$detail" \
    --arg pr_url "$pr_url" \
    '{repo:$repo,check:$check,strategy:$strategy,status:$status,detail:$detail,pr_url:$pr_url}')

  jq --argjson e "$entry" '. += [$e]' "$REMEDIATION_REPORT" > "$REMEDIATION_REPORT.tmp"
  mv "$REMEDIATION_REPORT.tmp" "$REMEDIATION_REPORT"

  case "$status" in
    ok)      remediated_count=$((remediated_count + 1)) ;;
    skipped) skipped_count=$((skipped_count + 1)) ;;
    failed)  failed_count=$((failed_count + 1)) ;;
  esac
}

# Retry wrapper for gh api calls (handles transient failures)
gh_api() {
  local retries=3
  for i in $(seq 1 $retries); do
    if gh api "$@" 2>/dev/null; then
      return 0
    fi
    if [ "$i" -lt "$retries" ]; then
      sleep $((i * 2))
    fi
  done
  return 1
}

# ---------------------------------------------------------------------------
# Direct remediation: repository settings
# ---------------------------------------------------------------------------
apply_repo_setting() {
  local repo="$1" field="$2" value="$3" check="$4"

  if [ "$DRY_RUN" = "true" ]; then
    dry_log "Would PATCH repos/$ORG/$repo  $field=$value"
    record_result "$repo" "$check" "DIRECT" "ok" "[dry run] Would set $field=$value"
    return 0
  fi

  if gh_api "repos/$ORG/$repo" -X PATCH -F "$field=$value" > /dev/null; then
    log "Set $field=$value on $ORG/$repo"
    record_result "$repo" "$check" "DIRECT" "ok" "Set $field=$value"
  else
    warn "Failed to set $field=$value on $ORG/$repo"
    record_result "$repo" "$check" "DIRECT" "failed" "gh api PATCH $field=$value failed"
    return 1
  fi
}

remediate_settings() {
  local repo="$1" check="$2"

  case "$check" in
    has_wiki)
      apply_repo_setting "$repo" "has_wiki" "false" "$check"
      ;;
    allow_auto_merge)
      apply_repo_setting "$repo" "allow_auto_merge" "true" "$check"
      ;;
    delete_branch_on_merge)
      apply_repo_setting "$repo" "delete_branch_on_merge" "true" "$check"
      ;;
    has-discussions)
      apply_repo_setting "$repo" "has_discussions" "true" "$check"
      ;;
    missing-codeowners)
      remediate_codeowners "$repo"
      ;;
    *)
      log "Settings check '$check' in $repo requires manual intervention"
      record_result "$repo" "$check" "SKIP" "skipped" "No automated remediation for check '$check'"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Direct remediation: missing labels
# ---------------------------------------------------------------------------
remediate_missing_label() {
  local repo="$1" check="$2"

  # Extract label name from check (format: "missing-label-<name>")
  local label="${check#missing-label-}"

  if [ -z "$label" ]; then
    record_result "$repo" "$check" "SKIP" "skipped" "Could not parse label name from check"
    return 0
  fi

  local color="${LABEL_COLORS[$label]:-ededed}"
  local desc="${LABEL_DESCS[$label]:-}"

  if [ "$DRY_RUN" = "true" ]; then
    dry_log "Would create label '$label' (#$color) in $ORG/$repo"
    record_result "$repo" "$check" "DIRECT" "ok" "[dry run] Would create label '$label'"
    return 0
  fi

  if gh label create "$label" \
      --repo "$ORG/$repo" \
      --color "$color" \
      --description "$desc" \
      --force 2>/dev/null; then
    log "Created/updated label '$label' in $ORG/$repo"
    record_result "$repo" "$check" "DIRECT" "ok" "Created label '$label' with color #$color"
  else
    warn "Failed to create label '$label' in $ORG/$repo"
    record_result "$repo" "$check" "DIRECT" "failed" "gh label create '$label' failed"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# PR remediation: generate CODEOWNERS file
# ---------------------------------------------------------------------------
remediate_codeowners() {
  local repo="$1"

  log "Generating CODEOWNERS for $ORG/$repo"

  # Resolve owners: try repo admins first, then org owners
  local owners=""
  local admin_logins

  if admin_logins=$(gh_api "repos/$ORG/$repo/collaborators?affiliation=direct&permission=admin" \
      --jq '.[].login' 2>/dev/null | head -10); then
    owners="$admin_logins"
  fi

  if [ -z "$owners" ]; then
    if admin_logins=$(gh_api "orgs/$ORG/members?role=admin" \
        --jq '.[].login' 2>/dev/null | head -10); then
      owners="$admin_logins"
    fi
  fi

  if [ -z "$owners" ]; then
    log "No admins found for $ORG/$repo — generating placeholder CODEOWNERS"
    owners="# TODO: add owner handles here"
  else
    owners=$(echo "$owners" | sed 's/^/@/' | paste -sd ' ' -)
  fi

  local codeowners_content="# CODEOWNERS — Auto-generated by compliance remediation
# Review and customize before merging.
# See: https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners
#
# Format: <pattern> <owner> [<owner2> ...]
# Example: * @org/team-name

# Global fallback — all files require review from these owners
* $owners
"

  local pr_body
  pr_body=$(cat <<'EOF'
## Summary

Adds a `CODEOWNERS` file to enable code owner review enforcement per org standards.

## Why

The `pr-quality` ruleset requires code owner review, but without a `CODEOWNERS`
file this rule has no effect — any reviewer can satisfy the requirement.

## What Changed

- Added `.github/CODEOWNERS` with global ownership assigned to repository admins
- Review and adjust ownership patterns before merging (e.g., assign subdirectories
  to specific teams)

## References

- [github-settings.md — PR Quality Ruleset](https://github.com/petry-projects/.github/blob/main/standards/github-settings.md#pr-quality--standard-ruleset-all-repositories)
- [About code owners](https://docs.github.com/en/repositories/managing-your-repositorys-settings-and-features/customizing-your-repository/about-code-owners)

---
*Auto-generated by [compliance remediation](https://github.com/petry-projects/.github/blob/main/scripts/compliance-remediate.sh)*
EOF
)

  local pr_url
  if pr_url=$(create_remediation_pr \
      "$repo" \
      "add-codeowners" \
      ".github/CODEOWNERS" \
      "$codeowners_content" \
      "fix: add CODEOWNERS for code owner review enforcement" \
      "$pr_body"); then
    record_result "$repo" "missing-codeowners" "PR" "ok" "Created PR for CODEOWNERS" "$pr_url"
  else
    record_result "$repo" "missing-codeowners" "PR" "failed" "Failed to create CODEOWNERS PR"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# PR remediation: pin GitHub Actions to commit SHAs
# ---------------------------------------------------------------------------
resolve_action_sha() {
  local action="$1" ref="$2"

  # Try tag ref first
  local sha
  local obj_type
  local tag_data

  if tag_data=$(gh_api "repos/$action/git/refs/tags/$ref" 2>/dev/null); then
    sha=$(echo "$tag_data" | jq -r '.object.sha // empty')
    obj_type=$(echo "$tag_data" | jq -r '.object.type // empty')

    # Dereference annotated tags (type=tag → need to peel to the commit)
    if [ "$obj_type" = "tag" ] && [ -n "$sha" ]; then
      local peeled_sha
      if peeled_sha=$(gh_api "repos/$action/git/tags/$sha" --jq '.object.sha' 2>/dev/null); then
        sha="$peeled_sha"
      fi
    fi
  fi

  # Fall back to commit SHA lookup (handles branch names / SemVer without v-prefix)
  if [ -z "$sha" ] || [ ${#sha} -ne 40 ]; then
    sha=$(gh_api "repos/$action/commits/$ref" --jq '.sha' 2>/dev/null || echo "")
  fi

  if [ -n "$sha" ] && [ ${#sha} -eq 40 ]; then
    echo "$sha"
    return 0
  fi
  return 1
}

pin_workflow_actions() {
  local repo="$1" workflow_file="$2"

  log "Pinning actions in $ORG/$repo/.github/workflows/$workflow_file"

  # Download workflow content
  local raw_content
  if ! raw_content=$(gh_api "repos/$ORG/$repo/contents/.github/workflows/$workflow_file" \
      --jq '.content' 2>/dev/null); then
    record_result "$repo" "unpinned-actions-$workflow_file" "PR" "failed" \
      "Could not download workflow file"
    return 1
  fi

  local content
  content=$(echo "$raw_content" | base64 -d 2>/dev/null || echo "")
  if [ -z "$content" ]; then
    record_result "$repo" "unpinned-actions-$workflow_file" "PR" "failed" \
      "Could not decode workflow file"
    return 1
  fi

  # Process line by line — pin any action not already SHA-pinned
  local new_content=""
  local changed=false
  local pin_log=""

  while IFS= read -r line; do
    # Match lines with uses: <owner>/<repo>@<tag> (not SHA-pinned, not docker://, not ./)
    if echo "$line" | grep -qE '^\s*-?\s*uses:\s+[a-zA-Z0-9_.-]+/[a-zA-Z0-9_.-]+@[^0-9a-f#][^ ]*' && \
       ! echo "$line" | grep -qE '@[0-9a-f]{40}'; then

      local action_ref
      action_ref=$(echo "$line" | grep -oE '[a-zA-Z0-9_.-]+/[a-zA-Z0-9_./-]+@[^ #]+' | head -1 || echo "")

      if [ -n "$action_ref" ]; then
        local action="${action_ref%@*}"
        local tag="${action_ref#*@}"

        # Skip local actions and docker images
        if [[ "$action" == ./* ]] || [[ "$action" == docker://* ]]; then
          new_content="${new_content}${line}"$'\n'
          continue
        fi

        local sha=""
        if sha=$(resolve_action_sha "$action" "$tag" 2>/dev/null) && [ -n "$sha" ]; then
          local pinned_ref="${action}@${sha} # ${tag}"
          local new_line="${line//$action_ref/$pinned_ref}"
          new_content="${new_content}${new_line}"$'\n'
          changed=true
          pin_log="${pin_log}\n  - ${action}@${tag} → @${sha:0:12}…"
          log "Pinned $action@$tag → $sha"
        else
          warn "Could not resolve SHA for $action@$tag — leaving unpinned"
          new_content="${new_content}${line}"$'\n'
        fi
      else
        new_content="${new_content}${line}"$'\n'
      fi
    else
      new_content="${new_content}${line}"$'\n'
    fi
  done <<< "$content"

  if [ "$changed" = false ]; then
    log "No changes needed for $workflow_file in $repo (already pinned or SHA unresolvable)"
    record_result "$repo" "unpinned-actions-$workflow_file" "PR" "skipped" \
      "No SHA-resolvable unpinned actions found"
    return 0
  fi

  local pr_body
  pr_body=$(cat <<EOF
## Summary

Pins GitHub Action references to commit SHAs for supply chain security.

## Why

Actions referenced by mutable tags (e.g., \`@v4\`) can be changed by upstream
maintainers without notice, introducing a supply chain attack vector. Pinning
to an immutable SHA guarantees reproducible builds.

## Actions Pinned
$(printf '%b' "$pin_log")

## References

- [ci-standards.md — Action Pinning Policy](https://github.com/petry-projects/.github/blob/main/standards/ci-standards.md#action-pinning-policy)
- [Keeping your GitHub Actions and workflows secure](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions#using-third-party-actions)

---
*Auto-generated by [compliance remediation](https://github.com/petry-projects/.github/blob/main/scripts/compliance-remediate.sh)*
EOF
)

  local pr_url
  if pr_url=$(create_remediation_pr \
      "$repo" \
      "pin-actions-${workflow_file%.yml}" \
      ".github/workflows/$workflow_file" \
      "$new_content" \
      "fix: pin action SHAs in $workflow_file" \
      "$pr_body"); then
    record_result "$repo" "unpinned-actions-$workflow_file" "PR" "ok" \
      "Created PR to pin actions in $workflow_file" "$pr_url"
  else
    record_result "$repo" "unpinned-actions-$workflow_file" "PR" "failed" \
      "Failed to create action-pinning PR for $workflow_file"
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Create a remediation PR in a target repo via the GitHub Contents API
# ---------------------------------------------------------------------------
create_remediation_pr() {
  local repo="$1" branch_suffix="$2" file_path="$3" file_content="$4" \
        commit_msg="$5" pr_body="$6"

  local branch="compliance-fix/$branch_suffix"

  if [ "$DRY_RUN" = "true" ]; then
    dry_log "Would create branch '$branch' and PR in $ORG/$repo"
    dry_log "  File: $file_path"
    dry_log "  Commit: $commit_msg"
    echo "https://github.com/$ORG/$repo/pulls (dry run)"
    return 0
  fi

  # Check if a remediation PR for this branch already exists
  local existing_pr
  existing_pr=$(gh pr list --repo "$ORG/$repo" \
    --head "$branch" \
    --state open \
    --json number \
    -q '.[0].number' 2>/dev/null || echo "")

  if [ -n "$existing_pr" ]; then
    log "PR already exists for $branch in $repo (#$existing_pr) — skipping"
    echo "https://github.com/$ORG/$repo/pull/$existing_pr"
    return 0
  fi

  # Get default branch and its HEAD SHA
  local default_branch
  default_branch=$(gh_api "repos/$ORG/$repo" --jq '.default_branch' || echo "main")

  local base_sha
  if ! base_sha=$(gh_api "repos/$ORG/$repo/git/refs/heads/$default_branch" \
      --jq '.object.sha' 2>/dev/null); then
    warn "Could not get HEAD SHA for $ORG/$repo/$default_branch"
    return 1
  fi

  # Create the branch (idempotent — skip if already exists)
  if ! gh_api "repos/$ORG/$repo/git/refs/heads/$branch" > /dev/null 2>&1; then
    if ! gh_api "repos/$ORG/$repo/git/refs" \
        -X POST \
        -f ref="refs/heads/$branch" \
        -f sha="$base_sha" > /dev/null; then
      warn "Failed to create branch $branch in $ORG/$repo"
      return 1
    fi
    log "Created branch $branch in $ORG/$repo"
  fi

  # Check if the file already exists (need its SHA for updates)
  local file_sha=""
  file_sha=$(gh_api "repos/$ORG/$repo/contents/$file_path?ref=$branch" \
    --jq '.sha' 2>/dev/null || echo "")

  # Base64-encode the file content (strip newlines from encoded output)
  local encoded_content
  encoded_content=$(printf '%s' "$file_content" | base64 | tr -d '\n')

  # Build the PUT payload
  local put_args=(
    "repos/$ORG/$repo/contents/$file_path"
    -X PUT
    -f message="$commit_msg"
    -f content="$encoded_content"
    -f branch="$branch"
  )
  if [ -n "$file_sha" ]; then
    put_args+=(-f sha="$file_sha")
  fi

  if ! gh_api "${put_args[@]}" > /dev/null; then
    warn "Failed to commit $file_path to $branch in $ORG/$repo"
    # Clean up branch
    gh_api "repos/$ORG/$repo/git/refs/heads/$branch" -X DELETE > /dev/null 2>&1 || true
    return 1
  fi

  # Ensure compliance-audit label exists before creating PR
  gh label create "compliance-audit" \
    --repo "$ORG/$repo" \
    --color "7057ff" \
    --description "Automated compliance audit finding" \
    --force 2>/dev/null || true

  # Create the PR
  local pr_url
  if pr_url=$(gh pr create \
      --repo "$ORG/$repo" \
      --title "$commit_msg" \
      --body "$pr_body" \
      --base "$default_branch" \
      --head "$branch" \
      --label "compliance-audit" 2>/dev/null); then
    log "Created PR: $pr_url"
    echo "$pr_url"
    return 0
  else
    warn "Failed to create PR in $ORG/$repo from $branch"
    # Clean up branch on PR failure
    gh_api "repos/$ORG/$repo/git/refs/heads/$branch" -X DELETE > /dev/null 2>&1 || true
    return 1
  fi
}

# ---------------------------------------------------------------------------
# Dispatch: route each finding to the right remediation
# ---------------------------------------------------------------------------
remediate_finding() {
  local repo="$1" category="$2" check="$3" severity="$4" detail="$5"

  log "Remediating [$category/$check] in $repo (severity: $severity)"

  case "$category" in
    settings)
      remediate_settings "$repo" "$check"
      ;;
    labels)
      if [[ "$check" == missing-label-* ]]; then
        remediate_missing_label "$repo" "$check"
      else
        log "Label check '$check' in $repo requires manual intervention"
        record_result "$repo" "$check" "SKIP" "skipped" "No automated remediation available"
      fi
      ;;
    action-pinning)
      # Extract workflow filename from check (format: "unpinned-actions-<file.yml>")
      local wf_file="${check#unpinned-actions-}"
      if [ -n "$wf_file" ] && [ "$wf_file" != "$check" ]; then
        pin_workflow_actions "$repo" "$wf_file"
      else
        record_result "$repo" "$check" "SKIP" "skipped" "Could not parse workflow filename from check"
      fi
      ;;
    ci-workflows)
      # Missing required workflows require the full workflow template — skip for now
      log "CI workflow finding '$check' in $repo requires template deployment — skipping auto-remediation"
      record_result "$repo" "$check" "SKIP" "skipped" \
        "Missing workflow files require template deployment; tag with 'claude' for agent pickup"
      ;;
    rulesets)
      log "Ruleset finding '$check' in $repo requires manual GitHub UI or Terraform config — skipping"
      record_result "$repo" "$check" "SKIP" "skipped" \
        "Ruleset creation requires GitHub UI or org-level Terraform config"
      ;;
    dependabot)
      log "Dependabot config finding '$check' in $repo requires template deployment — skipping"
      record_result "$repo" "$check" "SKIP" "skipped" \
        "Dependabot config changes require per-repo template PR; tag with 'claude' for agent pickup"
      ;;
    standards)
      log "Standards finding '$check' in $repo requires content creation — skipping"
      record_result "$repo" "$check" "SKIP" "skipped" \
        "CLAUDE.md / AGENTS.md creation requires repo context; tag with 'claude' for agent pickup"
      ;;
    *)
      log "Unknown category '$category' for check '$check' — skipping"
      record_result "$repo" "$check" "SKIP" "skipped" "Unknown category '$category'"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Summary generation
# ---------------------------------------------------------------------------
generate_summary() {
  local total_findings="$1"

  cat > "$REMEDIATION_SUMMARY" <<HEREDOC
# Compliance Remediation Report — $(date -u +%Y-%m-%d)

## Summary

| Metric | Count |
|--------|-------|
| Findings processed | $total_findings |
| Successfully remediated | $remediated_count |
| Skipped (manual required) | $skipped_count |
| Failed | $failed_count |

HEREDOC

  # Group by repo
  local repos_touched
  repos_touched=$(jq -r '[.[].repo] | unique[]' "$REMEDIATION_REPORT" 2>/dev/null || echo "")

  if [ -n "$repos_touched" ]; then
    echo "## Results by Repository" >> "$REMEDIATION_SUMMARY"
    echo "" >> "$REMEDIATION_SUMMARY"

    for repo in $repos_touched; do
      local repo_rows
      repo_rows=$(jq -r --arg repo "$repo" \
        '.[] | select(.repo == $repo) | "| `\(.strategy)` | `\(.status)` | \(.check) | \(.detail) |\(if .pr_url != "" then " [PR](\(.pr_url))" else "" end)"' \
        "$REMEDIATION_REPORT" 2>/dev/null || echo "")

      local repo_count
      repo_count=$(jq --arg repo "$repo" '[.[] | select(.repo == $repo)] | length' \
        "$REMEDIATION_REPORT" 2>/dev/null || echo 0)

      cat >> "$REMEDIATION_SUMMARY" <<HEREDOC
### [$repo](https://github.com/$ORG/$repo) — $repo_count finding(s)

| Strategy | Status | Check | Detail |
|----------|--------|-------|--------|
$repo_rows

HEREDOC
    done
  fi

  cat >> "$REMEDIATION_SUMMARY" <<HEREDOC
## Remediation Strategies

| Strategy | Description |
|----------|-------------|
| **DIRECT** | Applied immediately via GitHub API (no PR needed) |
| **PR** | Created a pull request in the target repository |
| **SKIP** | Not auto-remediable — see detail for next steps |

---
*Generated by the [compliance remediation script](https://github.com/$ORG/.github/blob/main/scripts/compliance-remediate.sh) on $(date -u "+%Y-%m-%d %H:%M UTC").*
HEREDOC
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
main() {
  if [ -z "$FINDINGS_FILE" ]; then
    echo "ERROR: FINDINGS_FILE environment variable is required" >&2
    echo "Usage: FINDINGS_FILE=<path/to/findings.json> $0" >&2
    exit 1
  fi

  if [ ! -f "$FINDINGS_FILE" ]; then
    echo "ERROR: Findings file not found: $FINDINGS_FILE" >&2
    exit 1
  fi

  log "Starting compliance remediation"
  log "Findings file: $FINDINGS_FILE"
  log "Report directory: $REPORT_DIR"
  log "Dry run: $DRY_RUN"

  # Initialize report
  echo "[]" > "$REMEDIATION_REPORT"

  local total_findings
  total_findings=$(jq length "$FINDINGS_FILE")
  log "Processing $total_findings findings"

  if [ "$total_findings" -eq 0 ]; then
    log "No findings to remediate — all repos are compliant!"
    generate_summary 0
    echo "remediation_report=$REMEDIATION_REPORT"
    echo "remediation_summary=$REMEDIATION_SUMMARY"
    cat "$REMEDIATION_SUMMARY"
    return 0
  fi

  # Process each finding
  # Sort by repo so we can batch-comment/close later per repo
  while IFS= read -r finding; do
    [ -z "$finding" ] && continue

    local f_repo f_category f_check f_severity f_detail
    f_repo=$(echo "$finding"     | jq -r '.repo')
    f_category=$(echo "$finding" | jq -r '.category')
    f_check=$(echo "$finding"    | jq -r '.check')
    f_severity=$(echo "$finding" | jq -r '.severity')
    f_detail=$(echo "$finding"   | jq -r '.detail')

    remediate_finding "$f_repo" "$f_category" "$f_check" "$f_severity" "$f_detail"
  done < <(jq -c '.[] | {repo,category,check,severity,detail}' "$FINDINGS_FILE")

  log "Remediation complete"
  log "  Remediated: $remediated_count"
  log "  Skipped:    $skipped_count"
  log "  Failed:     $failed_count"

  generate_summary "$total_findings"

  # Output paths for workflow integration
  echo "remediation_report=$REMEDIATION_REPORT"
  echo "remediation_summary=$REMEDIATION_SUMMARY"
  echo "remediated_count=$remediated_count"
  echo "skipped_count=$skipped_count"
  echo "failed_count=$failed_count"

  cat "$REMEDIATION_SUMMARY"

  # Exit non-zero if any remediations failed (allows workflow to flag this)
  if [ "$failed_count" -gt 0 ]; then
    warn "$failed_count remediation(s) failed — check the report for details"
    return 1
  fi
}

main "$@"
