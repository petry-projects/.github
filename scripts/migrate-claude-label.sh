#!/usr/bin/env bash
set -euo pipefail
# migrate-claude-label.sh — One-time org-wide migration of the legacy `claude`
# issue-trigger label to the canonical `dev-lead` label.
#
# Background:
#   The dev-lead agent historically accepted BOTH `dev-lead` and `claude` labels
#   (claude being backward-compat from the retired claude.yml workflow). We are
#   removing the `claude` label entirely. dev-lead now triggers on `dev-lead`
#   only, and the compliance audit creates/cycles the `dev-lead` label.
#
# What this does, per non-archived org repo that has a `claude` label:
#   1. Ensure the `dev-lead` label exists (created idempotently).
#   2. For every OPEN issue still labelled `claude`, add the `dev-lead` label so
#      the issue stays actionable. (Adding the label re-fires issues:labeled, so
#      dev-lead will pick the issue up — this is intended: a `claude`-labelled
#      open issue was already pending pickup.)
#   3. If DELETE_OLD_LABEL=true, delete the `claude` label object from the repo,
#      which strips it from every issue/PR (open and closed).
#
# Idempotent: re-running skips issues that already carry `dev-lead` (no duplicate
# trigger) and is a no-op once the `claude` label has been deleted.
#
# Environment:
#   GH_TOKEN          — token with issues:write + repo admin (label delete) across
#                       the org (e.g. ORG_SCORECARD_TOKEN). Required.
#   ORG               — GitHub org (default: petry-projects)
#   OLD_LABEL         — legacy label to retire (default: claude)
#   NEW_LABEL         — canonical replacement label (default: dev-lead)
#   NEW_LABEL_COLOR   — hex color for the new label (default: 8B5CF6)
#   NEW_LABEL_DESC    — description for the new label (default: For dev-lead agent pickup)
#   DELETE_OLD_LABEL  — "true" to delete the old label object (default: true)
#   DRY_RUN           — "true" to log without mutating (default: true — safe)
#   TARGET_REPO       — limit to one repo (name or owner/name); blank = all repos

ORG="${ORG:-petry-projects}"
OLD_LABEL="${OLD_LABEL:-claude}"
NEW_LABEL="${NEW_LABEL:-dev-lead}"
NEW_LABEL_COLOR="${NEW_LABEL_COLOR:-8B5CF6}"
NEW_LABEL_DESC="${NEW_LABEL_DESC:-For dev-lead agent pickup}"
DELETE_OLD_LABEL="${DELETE_OLD_LABEL:-true}"
DRY_RUN="${DRY_RUN:-true}"
TARGET_REPO="${TARGET_REPO:-}"

REPOS_PROCESSED=0
LABELS_ADDED=0
ISSUES_SKIPPED=0
LABELS_DELETED=0

info()  { echo "[info]  $*"; }
warn()  { echo "[warn]  $*" >&2; }

# repo_has_label <repo> <label> — 0 if the label object exists in the repo.
repo_has_label() {
  gh api "repos/$ORG/$1/labels/$2" --jq '.name' >/dev/null 2>&1
}

# issue_has_label <repo> <issue> <label> — 0 if the issue already carries label.
issue_has_label() {
  local present
  present=$(gh api "repos/$ORG/$1/issues/$2" \
    --jq "[.labels[].name] | index(\"$3\") // empty" 2>/dev/null || echo "")
  [ -n "$present" ]
}

migrate_repo() {
  local repo="$1"

  if ! repo_has_label "$repo" "$OLD_LABEL"; then
    return 0  # nothing to migrate in this repo
  fi
  REPOS_PROCESSED=$((REPOS_PROCESSED + 1))
  info "Repo $repo has '$OLD_LABEL' label — migrating"

  # 1. Ensure the new label exists.
  if [ "$DRY_RUN" = "true" ]; then
    info "[dry-run] would ensure label '$NEW_LABEL' exists in $repo"
  else
    gh label create "$NEW_LABEL" --repo "$ORG/$repo" \
      --color "$NEW_LABEL_COLOR" --description "$NEW_LABEL_DESC" --force 2>/dev/null || true
  fi

  # 2. Re-label every OPEN issue currently carrying the old label.
  local issues repo_failed=0
  issues=$(gh issue list --repo "$ORG/$repo" --label "$OLD_LABEL" --state open \
    --limit 1000 --json number -q '.[].number' 2>/dev/null || echo "")
  while IFS= read -r num; do
    [ -z "$num" ] && continue
    if issue_has_label "$repo" "$num" "$NEW_LABEL"; then
      info "  #$num already has '$NEW_LABEL' — skipping"
      ISSUES_SKIPPED=$((ISSUES_SKIPPED + 1))
      continue
    fi
    if [ "$DRY_RUN" = "true" ]; then
      info "[dry-run] would add '$NEW_LABEL' to $repo#$num"
    else
      if gh issue edit "$num" --repo "$ORG/$repo" --add-label "$NEW_LABEL" >/dev/null 2>&1; then
        info "  added '$NEW_LABEL' to $repo#$num"
      else
        warn "  failed to add '$NEW_LABEL' to $repo#$num"
        repo_failed=1
      fi
    fi
    LABELS_ADDED=$((LABELS_ADDED + 1))
  done <<< "$issues"

  # 3. Delete the old label object (strips it from all issues/PRs).
  if [ "$DELETE_OLD_LABEL" = "true" ] && [ "$repo_failed" -eq 0 ]; then
    if [ "$DRY_RUN" = "true" ]; then
      info "[dry-run] would DELETE label '$OLD_LABEL' from $repo"
    else
      gh api -X DELETE "repos/$ORG/$repo/labels/$OLD_LABEL" >/dev/null 2>&1 \
        && info "  deleted '$OLD_LABEL' label from $repo" \
        || warn "  failed to delete '$OLD_LABEL' label from $repo"
    fi
    LABELS_DELETED=$((LABELS_DELETED + 1))
  elif [ "$repo_failed" -ne 0 ]; then
    warn "  keeping '$OLD_LABEL' on $repo — one or more re-labels failed"
  fi
}

main() {
  info "migrate-claude-label starting (org=$ORG, $OLD_LABEL -> $NEW_LABEL, dry_run=$DRY_RUN, delete_old=$DELETE_OLD_LABEL)"

  local repos
  if [ -n "$TARGET_REPO" ]; then
    repos="${TARGET_REPO#"$ORG/"}"
  else
    repos=$(gh repo list "$ORG" --no-archived --limit 1000 --json name -q '.[].name')
  fi

  for repo in $repos; do
    migrate_repo "$repo"
  done

  echo ""
  echo "=========================================="
  echo "  migrate-claude-label summary"
  echo "=========================================="
  echo "  Dry run             : $DRY_RUN"
  echo "  Repos migrated      : $REPOS_PROCESSED"
  echo "  Issues re-labelled  : $LABELS_ADDED"
  echo "  Issues skipped      : $ISSUES_SKIPPED (already had '$NEW_LABEL')"
  echo "  Old labels deleted  : $LABELS_DELETED"
  echo "=========================================="

  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    {
      echo "## claude → dev-lead label migration"
      echo ""
      echo "| Metric | Value |"
      echo "| ------ | ----- |"
      echo "| Dry run | $DRY_RUN |"
      echo "| Repos migrated | $REPOS_PROCESSED |"
      echo "| Issues re-labelled | $LABELS_ADDED |"
      echo "| Issues skipped (already \`$NEW_LABEL\`) | $ISSUES_SKIPPED |"
      echo "| Old labels deleted | $LABELS_DELETED |"
    } >> "$GITHUB_STEP_SUMMARY"
  fi
}

main "$@"
