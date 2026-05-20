#!/usr/bin/env bash
set -euo pipefail
# compliance-retrigger.sh — Re-trigger stale compliance-audit issues and enforce
# dev-lead workflow health across the fleet.
#
# Run daily (see .github/workflows/compliance-retrigger.yml).
#
# What it does:
#   1. Verifies that the dev-lead workflow is ACTIVE in every fleet repo.
#      Disabled workflows silently swallow issue-labeled events — findings
#      will never be fixed even if labels are applied correctly.
#   2. Finds all open compliance-audit issues that are ≥ STALE_DAYS old and
#      have no associated open PR on a dev-lead branch.  Cycles the "claude"
#      label (remove + re-add) to re-fire the issues:labeled event and give
#      dev-lead a fresh chance to create a fix PR.
#
# Why re-trigger instead of relying on the original event?
#   GitHub only fires issues:labeled once per label application.  If dev-lead
#   had a transient failure at that moment (template error, git-identity bug,
#   rate-limit, disabled workflow), the event is lost forever unless the label
#   is re-applied.  This script recovers those lost events automatically.
#
# Environment:
#   GH_TOKEN      — must have issues:write and contents:read across the org
#   ORG           — GitHub org name (default: petry-projects)
#   STALE_DAYS    — issues older than this are considered stale (default: 2)
#   DRY_RUN       — set to "true" to log actions without executing them
#   AUDIT_LABEL   — label used to tag compliance findings (default: compliance-audit)
#   TRIGGER_LABEL — label used to trigger dev-lead (default: claude)

ORG="${ORG:-petry-projects}"
STALE_DAYS="${STALE_DAYS:-2}"
DRY_RUN="${DRY_RUN:-false}"
AUDIT_LABEL="${AUDIT_LABEL:-compliance-audit}"
TRIGGER_LABEL="${TRIGGER_LABEL:-claude}"

ISSUES_RETRIGGERED=0
ISSUES_SKIPPED=0
WORKFLOWS_DISABLED=0
WORKFLOWS_ENABLED=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

info()  { echo "[info]  $*"; }
warn()  { echo "[warn]  $*" >&2; }
error() { echo "[error] $*" >&2; }

gh_api() { gh api "$@"; }

# stale_cutoff — ISO timestamp N days ago
stale_cutoff() {
  date -u -d "${STALE_DAYS} days ago" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
    || python3 -c "from datetime import datetime,timedelta,timezone; \
                   print((datetime.now(timezone.utc)-timedelta(days=${STALE_DAYS})).strftime('%Y-%m-%dT%H:%M:%SZ'))"
}

# has_open_pr <repo> <issue_number>
# Returns 0 (true) if there is an open PR with head ref dev-lead/issue-<number>*
has_open_pr() {
  local repo="$1" issue="$2"
  local count
  count=$(gh_api "repos/$ORG/$repo/pulls?state=open" \
    --jq "[.[] | select(.head.ref | startswith(\"dev-lead/issue-${issue}\"))] | length" \
    2>/dev/null || echo "0")
  [ "${count:-0}" -gt 0 ]
}

# cycle_label <repo> <issue>
# Removes and re-adds TRIGGER_LABEL so issues:labeled fires again.
cycle_label() {
  local repo="$1" issue="$2"
  if [ "$DRY_RUN" = "true" ]; then
    info "[dry-run] would cycle '$TRIGGER_LABEL' on $repo#$issue"
    return 0
  fi
  gh api -X DELETE "repos/$ORG/$repo/issues/$issue/labels/$TRIGGER_LABEL" 2>/dev/null || true
  gh api -X POST "repos/$ORG/$repo/issues/$issue/labels" \
    --field "labels[]=$TRIGGER_LABEL" >/dev/null
}

# ---------------------------------------------------------------------------
# Step 1: Check dev-lead workflow health in fleet repos
# ---------------------------------------------------------------------------

check_devlead_workflows() {
  info "Checking dev-lead workflow state across fleet repos..."
  local repos
  repos=$(gh api "orgs/$ORG/repos?per_page=100" \
    --jq '[.[] | select(.archived == false and .disabled == false) | .name][]' \
    2>/dev/null || echo "")

  while IFS= read -r repo; do
    [ -z "$repo" ] && continue
    local state
    state=$(gh api "repos/$ORG/$repo/actions/workflows/dev-lead.yml" \
      --jq '.state' 2>/dev/null || echo "missing")

    case "$state" in
      active)
        WORKFLOWS_ENABLED=$((WORKFLOWS_ENABLED + 1))
        ;;
      disabled_manually|disabled_inactivity)
        warn "dev-lead workflow is '$state' in $repo — enabling it"
        if [ "$DRY_RUN" != "true" ]; then
          local wf_id
          wf_id=$(gh api "repos/$ORG/$repo/actions/workflows/dev-lead.yml" \
            --jq '.id' 2>/dev/null || echo "")
          if [ -n "$wf_id" ] && [ "$wf_id" != "null" ]; then
            gh api -X PUT "repos/$ORG/$repo/actions/workflows/$wf_id/enable" 2>/dev/null \
              && info "Enabled dev-lead in $repo" \
              || warn "Failed to enable dev-lead in $repo"
          fi
        fi
        WORKFLOWS_DISABLED=$((WORKFLOWS_DISABLED + 1))
        ;;
      missing)
        # Repo does not have dev-lead.yml — not a fleet repo, skip silently
        ;;
      *)
        warn "Unexpected dev-lead state '$state' in $repo"
        ;;
    esac
  done <<< "$repos"

  info "dev-lead workflow check complete: ${WORKFLOWS_ENABLED} active, ${WORKFLOWS_DISABLED} re-enabled"
}

# ---------------------------------------------------------------------------
# Step 2: Re-trigger stale compliance issues
# ---------------------------------------------------------------------------

retrigger_stale_issues() {
  info "Looking for stale compliance-audit issues (older than ${STALE_DAYS} days)..."
  local cutoff
  cutoff=$(stale_cutoff)
  info "Stale cutoff: $cutoff"

  # Search across the whole org
  local issues
  issues=$(gh api \
    "search/issues?q=org:${ORG}+label:${AUDIT_LABEL}+label:${TRIGGER_LABEL}+state:open&per_page=100" \
    --jq '.items[] | {number: .number, repo: (.repository_url | split("/") | last), created_at: .created_at, title: .title}' \
    2>/dev/null || echo "")

  if [ -z "$issues" ]; then
    info "No open compliance-audit issues found."
    return 0
  fi

  while IFS= read -r issue_json; do
    [ -z "$issue_json" ] && continue
    local number repo created_at title
    number=$(echo "$issue_json" | jq -r '.number')
    repo=$(echo "$issue_json" | jq -r '.repo')
    created_at=$(echo "$issue_json" | jq -r '.created_at')
    title=$(echo "$issue_json" | jq -r '.title')

    # Check if stale
    if [[ "$created_at" > "$cutoff" ]]; then
      info "Skipping $repo#$number ($title) — created $created_at, not yet stale"
      ISSUES_SKIPPED=$((ISSUES_SKIPPED + 1))
      continue
    fi

    # Check if a dev-lead PR already exists for this issue
    if has_open_pr "$repo" "$number"; then
      info "Skipping $repo#$number — open dev-lead PR already exists"
      ISSUES_SKIPPED=$((ISSUES_SKIPPED + 1))
      continue
    fi

    info "Re-triggering $repo#$number: $title (created $created_at)"
    cycle_label "$repo" "$number"
    ISSUES_RETRIGGERED=$((ISSUES_RETRIGGERED + 1))
    # Brief pause to avoid flooding the API
    sleep 1
  done <<< "$issues"

  info "Re-trigger complete: ${ISSUES_RETRIGGERED} retriggered, ${ISSUES_SKIPPED} skipped"
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

print_summary() {
  echo ""
  echo "=========================================="
  echo "  compliance-retrigger summary"
  echo "=========================================="
  echo "  Stale threshold : ${STALE_DAYS} days"
  echo "  Dry run         : ${DRY_RUN}"
  echo "  Issues retriggered  : ${ISSUES_RETRIGGERED}"
  echo "  Issues skipped      : ${ISSUES_SKIPPED}"
  echo "  Workflows re-enabled: ${WORKFLOWS_DISABLED}"
  echo "  Workflows already active: ${WORKFLOWS_ENABLED}"
  echo "=========================================="

  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      echo "## Compliance Re-trigger Summary"
      echo ""
      echo "| Metric | Value |"
      echo "| ------ | ----- |"
      echo "| Issues retriggered | $ISSUES_RETRIGGERED |"
      echo "| Issues skipped (PR exists or recent) | $ISSUES_SKIPPED |"
      echo "| dev-lead workflows re-enabled | $WORKFLOWS_DISABLED |"
      echo "| dev-lead workflows already active | $WORKFLOWS_ENABLED |"
      echo "| Stale threshold | ${STALE_DAYS} days |"
      echo "| Dry run | $DRY_RUN |"
    } >> "$GITHUB_STEP_SUMMARY"
  fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
  info "compliance-retrigger starting (org=$ORG, stale_days=$STALE_DAYS, dry_run=$DRY_RUN)"
  check_devlead_workflows
  retrigger_stale_issues
  print_summary
}

main "$@"
