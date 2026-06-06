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
#      have no associated open PR on a dev-lead branch.  Cycles the "dev-lead"
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
#   TRIGGER_LABEL — label used to trigger dev-lead (default: dev-lead)

ORG="${ORG:-petry-projects}"
STALE_DAYS="${STALE_DAYS:-2}"
DRY_RUN="${DRY_RUN:-false}"
AUDIT_LABEL="${AUDIT_LABEL:-compliance-audit}"
TRIGGER_LABEL="${TRIGGER_LABEL:-dev-lead}"
# Legacy label to also sweep during the transition window before the one-time
# migration script has run. Issues that still carry only the old label are
# found here and given the new label so dev-lead picks them up.
LEGACY_TRIGGER_LABEL="${LEGACY_TRIGGER_LABEL:-claude}"

# Shared dev-lead retrigger helpers (dl_dev_lead_active, dl_cycle_trigger_label).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/dev-lead-retrigger.sh
. "$SCRIPT_DIR/lib/dev-lead-retrigger.sh"

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

# has_open_pr / cycle_label live in lib/dev-lead-retrigger.sh as
# dl_dev_lead_active() and dl_cycle_trigger_label(), shared with the weekly
# compliance audit so both stay in sync with dev-lead's branch-naming
# convention. Sourced via SCRIPT_DIR resolved at the top of the file.

# stale_cutoff — ISO timestamp N days ago
stale_cutoff() {
  date -u -d "${STALE_DAYS} days ago" '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null \
    || python3 -c "from datetime import datetime,timedelta,timezone; \
                   print((datetime.now(timezone.utc)-timedelta(days=${STALE_DAYS})).strftime('%Y-%m-%dT%H:%M:%SZ'))"
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

  # Search across the whole org. Fetch raw response first so we can detect
  # HTTP errors — gh api dumps the error JSON to stdout and exits non-zero,
  # which the old `--jq '.items[]' || echo ""` pattern silently swallowed,
  # producing a single "Skipping null#null" iteration when the token lacked
  # search scope. See: failure mode where ORG_SCORECARD_TOKEN scope did not
  # permit cross-org search but the script still reported success.
  local raw rc
  raw=$(gh api \
    "search/issues?q=org:${ORG}+label:${AUDIT_LABEL}+label:${TRIGGER_LABEL}+state:open&per_page=100" \
    2>&1) && rc=0 || rc=$?

  if [ "$rc" -ne 0 ]; then
    error "search/issues API call failed (exit $rc). Response:"
    echo "$raw" | head -5 >&2
    error "Cannot retrigger issues; aborting. Check GH_TOKEN scope — token must be able to read issues across all repos in org ${ORG}."
    return 1
  fi

  # Detect error-response JSON even when exit code was 0 (defensive).
  if echo "$raw" | jq -e 'has("message") and (.items | not)' >/dev/null 2>&1; then
    error "search/issues returned an error response:"
    echo "$raw" | jq -r '.message' >&2
    return 1
  fi

  local total
  total=$(echo "$raw" | jq -r '.total_count // 0')
  info "search/issues returned ${total} matching issues"

  local issues
  issues=$(echo "$raw" | jq -c '.items[] | {number: .number, repo: (.repository_url | split("/") | last), created_at: .created_at, title: .title}')

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

    # Skip if dev-lead is already working this issue (open PR or in-progress).
    if dl_dev_lead_active "$ORG" "$repo" "$number"; then
      info "Skipping $repo#$number — dev-lead already active (open PR or in-progress)"
      ISSUES_SKIPPED=$((ISSUES_SKIPPED + 1))
      continue
    fi

    info "Re-triggering $repo#$number: $title (created $created_at)"
    if dl_cycle_trigger_label "$ORG" "$repo" "$number" "$TRIGGER_LABEL" "$DRY_RUN"; then
      ISSUES_RETRIGGERED=$((ISSUES_RETRIGGERED + 1))
    else
      warn "Failed to re-trigger dev-lead on issue #$number in $repo — attempting to restore label"
      # The label may have been deleted but the re-add failed. Restore it so the
      # issue remains visible to the next sweep's search query.
      if [ "$DRY_RUN" != "true" ]; then
        gh api -X POST "repos/$ORG/$repo/issues/$number/labels" \
          --field "labels[]=$TRIGGER_LABEL" >/dev/null 2>&1 \
          && info "Restored $TRIGGER_LABEL on $repo#$number" \
          || warn "Could not restore $TRIGGER_LABEL on $repo#$number — issue may drop out of next sweep"
      fi
      ISSUES_SKIPPED=$((ISSUES_SKIPPED + 1))
    fi
    # dl_cycle_trigger_label already sleeps 1s internally; no additional pause needed.
  done <<< "$issues"

  # Sweep pre-migration issues that still carry only the legacy trigger label.
  # When this change is deployed before the one-time migration has run, open
  # compliance issues with the legacy label would otherwise be invisible to the
  # main search above and never retriggered. Adding TRIGGER_LABEL to each such
  # issue both recovers the lost event and acts as a lazy per-issue migration.
  if [ -n "${LEGACY_TRIGGER_LABEL:-}" ] && [ "$LEGACY_TRIGGER_LABEL" != "$TRIGGER_LABEL" ]; then
    info "Sweeping pre-migration '$LEGACY_TRIGGER_LABEL'-labeled issues..."
    local legacy_raw legacy_rc
    # Exclude issues that already carry TRIGGER_LABEL — they were handled above.
    legacy_raw=$(gh api \
      "search/issues?q=org:${ORG}+label:${AUDIT_LABEL}+label:${LEGACY_TRIGGER_LABEL}+-label:${TRIGGER_LABEL}+state:open&per_page=100" \
      2>&1) && legacy_rc=0 || legacy_rc=$?
    if [ "$legacy_rc" -ne 0 ]; then
      warn "Legacy label sweep search failed (exit $legacy_rc) — pre-migration issues not swept this run"
    else
      local legacy_total legacy_issues
      legacy_total=$(echo "$legacy_raw" | jq -r '.total_count // 0')
      info "Legacy sweep found ${legacy_total} matching issues"
      legacy_issues=$(echo "$legacy_raw" | jq -c '.items[] | {number: .number, repo: (.repository_url | split("/") | last), created_at: .created_at, title: .title}')
      while IFS= read -r issue_json; do
        [ -z "$issue_json" ] && continue
        number=$(echo "$issue_json" | jq -r '.number')
        repo=$(echo "$issue_json" | jq -r '.repo')
        created_at=$(echo "$issue_json" | jq -r '.created_at')
        title=$(echo "$issue_json" | jq -r '.title')
        if [[ "$created_at" > "$cutoff" ]]; then
          ISSUES_SKIPPED=$((ISSUES_SKIPPED + 1))
          continue
        fi
        if dl_dev_lead_active "$ORG" "$repo" "$number"; then
          info "Skipping legacy $repo#$number — dev-lead already active"
          ISSUES_SKIPPED=$((ISSUES_SKIPPED + 1))
          continue
        fi
        info "Adding '$TRIGGER_LABEL' to pre-migration issue $repo#$number: $title"
        if [ "$DRY_RUN" = "true" ]; then
          info "[dry-run] would add '$TRIGGER_LABEL' to $repo#$number"
          ISSUES_RETRIGGERED=$((ISSUES_RETRIGGERED + 1))
        elif gh api -X POST "repos/$ORG/$repo/issues/$number/labels" \
          --field "labels[]=$TRIGGER_LABEL" >/dev/null 2>&1; then
          info "  added '$TRIGGER_LABEL' to $repo#$number"
          ISSUES_RETRIGGERED=$((ISSUES_RETRIGGERED + 1))
        else
          warn "Failed to add '$TRIGGER_LABEL' to $repo#$number — issue may not be retriggered"
          ISSUES_SKIPPED=$((ISSUES_SKIPPED + 1))
        fi
      done <<< "$legacy_issues"
    fi
  fi

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
