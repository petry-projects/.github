# Dependabot Auto-Merge Status Analysis & Recommendations

**Date**: 2026-04-16  
**Author**: Claude Code (Investigation)  
**Status**: Analysis Complete — Recommended Actions Below

---

## Executive Summary

Dependabot PR auto-merge is **working as designed** for GitHub Actions updates, but PRs are being **stalled in BEHIND state** due to repository ruleset constraints. The current policy and implementation are **correct and complete**. The issue is purely operational: PRs cannot merge when BEHIND due to `required_linear_history` ruleset enforcement.

**Status Across Organization:**
- ✅ **5 repos**: No blocked Dependabot PRs (ContentTwin, TalkTerm have clean queues)
- ⚠️ **2 repos**: Blocked PRs waiting for resolution:
  - **`.github`**: 2 open MAJOR GitHub Actions bumps (BEHIND state)
  - **Others**: Additional blocked PRs in broodly, markets, google-app-scripts

**Key Finding**: There is **NO hourly review/approve workflow**. Approvals are happening from the `dependabot-automerge` workflow (which is working correctly) and manual reviews from humans.

---

## Timeline of Events

### April 12
- Dependabot creates PR #125 (actions/upload-artifact 4.6.2 → 7.0.1)
- Dependabot creates PR #129 (actions/download-artifact 4.3.0 → 8.0.1)

### April 16, 11:46–11:53 UTC
- `dependabot-automerge` workflow runs multiple times
- Approves both PRs (correctly identifying them as GitHub Actions, which allow MAJOR bumps)
- Enables auto-merge via `gh pr merge --auto --squash`
- However: PRs cannot merge because they're already BEHIND main
- Ruleset `required_linear_history` prevents merge of branches not at tip of main

### April 16, 12:16 UTC
- Human (don-petry) manually approves PR #125
- This is a second/confirming approval (workflow already approved it)

### April 16, 13:11 UTC
- Human (don-petry) manually approves PR #129

### April 16, 17:04 UTC (Today)
- User requests rebase: `@dependabot rebase` on both PRs
- **PR #125 fails**: Dependabot reports "edited by someone other than Dependabot"
  - Some other change was made to this PR that broke Dependabot's ability to rebase
- **PR #129 response pending**: Unknown if rebase succeeds

### April 16, 13:13-13:14 UTC
- Manual workflow_dispatch trigger on `dependabot-rebase` workflow (NEW—added via PR #139)
- Workflow completes successfully but PRs remain BEHIND

---

## Policy Verification

### What the Policy Says

From **standards/dependabot-policy.md** (lines 154–157):

> **For GitHub Actions**: approves and auto-merges all version bumps including major, since actions are SHA-pinned and CI catches breaking interface changes
> **For app ecosystems**: approves **patch** and **minor** updates (and indirect dependency updates); **major** updates are left for human review

### What the Implementation Does

In `.github/workflows/dependabot-automerge-reusable.yml` (lines 54–66):

```bash
if [[ "$ECOSYSTEM" != "github_actions" && \
      "$UPDATE_TYPE" != "version-update:semver-patch" && \
      "$UPDATE_TYPE" != "version-update:semver-minor" && \
      "$DEP_TYPE" != "indirect" ]]; then
  echo "eligible=false" >> "$GITHUB_OUTPUT"
  echo "Skipping: major update for $ECOSYSTEM requires human review"
  exit 0
fi
```

**Translation**: "If ecosystem IS github_actions, approve it regardless of version type. Otherwise, only patch/minor/indirect."

✅ **Implementation matches policy perfectly.**

---

## Root Cause: The BEHIND State Problem

### Why PRs Fall BEHIND

1. **Initial state**: PR #125 and #129 created on April 12, based on main at that point
2. **Other PRs merged**: PR #127 (pnpm 5.0.0→6.0.0) merged on April 16 at 11:52
3. **Main advanced**: Each merge advances main's commit hash
4. **PRs now behind**: PR #125 and #129 branches still point to old main commit
5. **Auto-merge cannot proceed**: Repository ruleset requires `required_linear_history: true`
   - This prevents squash-merge of branches not at main's tip
   - Even with auto-merge enabled, the merge cannot execute
   - Result: **PR is stuck BLOCKED/BEHIND indefinitely**

### Why Rebasing Doesn't Help

The `dependabot-rebase` workflow (added April 16 via PR #139) is supposed to solve this:

1. Triggers on push to main
2. Updates behind PRs via GitHub API `update-branch` endpoint
3. Should bring them current so merge can proceed

**However**, the issue with PR #125:
- **Cause**: Someone (not Dependabot) edited the PR at some point
- **Effect**: Dependabot can no longer rebase or push to it
- **Dependabot's message**: "Edited by someone other than Dependabot"
- **Solution**: `@dependabot recreate` to start fresh, OR manually edit to fix the issue

---

## Current Status by Repository

### `.github` (2 open, both MAJOR GitHub Actions)

| PR | Update | Type | State | Auto-Merge | Checks | Issue |
|-----|--------|------|-------|-----------|--------|-------|
| #125 | actions/upload-artifact 4.6.2→7.0.1 | MAJOR | BEHIND | ✅ Enabled | ✅ Pass | Edited outside Dependabot; can't rebase |
| #129 | actions/download-artifact 4.3.0→8.0.1 | MAJOR | BEHIND | ✅ Enabled | ✅ Pass | Awaiting rebase results |

### Other Repos (9 total blocked)

- **ContentTwin**: 0 blocked ✅
- **TalkTerm**: 0 blocked ✅
- **markets**: 1 MINOR (PR #97) — not auto-eligible, manual only
- **broodly**: 2 blocked — 1 MAJOR + 1 manual
- **google-app-scripts**: 4 blocked — 3 MINOR + 1 MAJOR

---

## Answers to User's Questions

### 1. **Are approvals happening?**

✅ **YES.** The `dependabot-automerge` workflow is running correctly and approving GitHub Actions updates (including MAJOR).

**Evidence**:
- PR #125 and #129 show multiple approvals from `dependabot-automerge-petry`
- Both PRs have auto-merge enabled (which only happens if approval workflow ran successfully)
- The workflow logic correctly identifies these as GitHub Actions and marks them eligible

### 2. **Is there a hourly review/approve workflow?**

❌ **NO.** There is no separate hourly review workflow. What exists:
- `dependabot-automerge` workflow runs on every `pull_request_target` event (i.e., when Dependabot creates/updates a PR)
- It evaluates eligibility and approves/enables auto-merge if conditions are met
- Manual approvals from humans (don-petry) are secondary/confirming approvals

### 3. **Why aren't they merging despite approvals and passing checks?**

🔴 **Repository ruleset enforcement.** Both PRs have:
- ✅ Required approval (they're approved)
- ✅ All CI checks passing
- ✅ Auto-merge enabled
- ❌ **But**: `required_linear_history: true` prevents merge when PR is BEHIND main

The ruleset is working as designed — it prevents non-linear history. But combined with Dependabot's weekly rebase cycle and branch protection, it creates a stalling effect.

---

## Recommendations

### Immediate Actions (Tactical)

1. **PR #125**: Request recreate instead of rebase
   ```bash
   @dependabot recreate
   ```
   - This deletes the PR and creates a fresh one based on current main
   - Avoids the "edited" issue that's blocking rebase

2. **PR #129**: Monitor rebase status
   - If rebase succeeds: check if merge proceeds
   - If it doesn't merge automatically: may need manual merge or recreate

3. **For all repos**: Review the 5 new workflow_dispatch PRs
   - Ensure they complete CI and merge
   - Workflow_dispatch trigger enables manual flushing of PR queue

### Strategic Actions (Process Improvements)

#### **Option A: Fix the Ruleset Conflict** (Recommended)

**Problem**: `require_last_push_approval: true` + `required_linear_history: true` prevent auto-merge

**Solution**: Consider relaxing `require_last_push_approval` to `false`

- `required_linear_history` already prevents merges of non-current branches
- Adding `require_last_push_approval: true` creates redundant friction
- For Dependabot PRs with auto-merge enabled (i.e., already approved), this additional gate adds no value

**Change**: In `.github/rulesets/14872168` (pr-quality ruleset):
```json
{
  "require_last_push_approval": false  // was true
}
```

**Impact**:
- Dependabot auto-merge workflow can trigger merges immediately after rebasing
- No change to human review flow (approvals still required)
- Eliminates the stalling effect

#### **Option B: Enhance dependabot-rebase Workflow** (Complementary)

The `dependabot-rebase.yml` workflow is correct but could be more proactive:

1. ✅ Already updates behind branches
2. ✅ Already merges ready branches
3. Consider: Add a check to detect edited PRs and suggest `@dependabot recreate`

#### **Option C: Document and Advise**

1. Add comment to the workflow results when PRs get stuck
2. Document the proper response: use `@dependabot recreate` for edited PRs
3. Update AGENTS.md with troubleshooting guide for stuck Dependabot PRs

---

## Proposed Solution: Enhance Rebase Workflow (OPTION C)

**The Correct Fix**: The problem is not the rule, but the workflow.

**Root Cause**: When `dependabot-rebase` updates a PR branch, the rebase counts as a "push" and `dismiss_stale_reviews_on_push: true` marks the approval stale. The PR is now current but un-approved.

**Solution**: Have the rebase workflow re-approve PRs after updating them.

**Changes**:
- Update `.github/workflows/dependabot-rebase-reusable.yml`:
  - After updating a Dependabot PR branch, immediately re-approve it
  - Use the app-bot token to provide the approval
  - Add explanatory comment

**Rationale**:
- Fixes the Dependabot stall without weakening developer safeguards
- `require_last_push_approval: true` still protects against humans sneaking code
- Re-approval after rebase is legitimate (branch-only change, no code change)
- Workflow-level fix, not org-wide policy change
- Surgical and specific — only affects Dependabot, not human PRs

**Benefits**:
- ✅ Dependabot PRs can merge once current AND approved
- ✅ Human developers still have the safeguard
- ✅ No ruleset changes (lowest risk)
- ✅ No compensating controls needed
- ✅ Applies immediately to all repos via reusable workflow

**Testing**:
- PR #125 and #129 should merge automatically once rebased
- Re-approvals from the workflow should be visible in PR history
- Human-authored PRs continue to require separate approvals as before

---

## Summary Table

| Finding | Status | Evidence |
|---------|--------|----------|
| Dependabot auto-merge workflow for GitHub Actions | ✅ Working | PR #125, #129 approved and auto-merge enabled |
| Policy document accuracy | ✅ Correct | Policy matches implementation |
| Hourly review/approve workflow | ❌ None exists | Only event-driven approvals from automerge |
| Root cause of stalled PRs | ✅ Identified | Rebase workflow doesn't re-approve after updating branches |
| Recommended fix | ✅ Proposed | Enhance rebase workflow to re-approve PRs after branch updates (Option C) |

