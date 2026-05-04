# CODEOWNERS Standard

**Status:** Active
**Applies to:** All repos in `petry-projects` org

## Rule

CODEOWNERS files MUST reference the `@petry-projects/org-leads` team rather than individual users or bot accounts.

```
# Default
* @petry-projects/org-leads
```

Path-specific rules MAY use additional teams or individuals when a narrower owner is appropriate, but the default `*` rule must always include `@petry-projects/org-leads`.

## Why

- **Stable CODEOWNERS files** — adding/removing an owner is a team membership change, not a multi-repo PR
- **CODEOWNERS support for automation** — GitHub Apps cannot be listed in CODEOWNERS (platform limitation), but a machine user account in the team can satisfy `require_code_owner_review`. See [pr-review-agent issue #27](https://github.com/don-petry/pr-review-agent/issues/27)
- **Centralized control** — team membership is managed in one place via the org admin UI

## Team Composition

The `@petry-projects/org-leads` team contains:

- `@don-petry` — primary maintainer (team maintainer)
- `@donpetry-bot` — automation machine user (used by pr-review-agent and similar tooling)

Add additional human maintainers as needed. Bots/apps that need code owner standing should be machine user accounts added to this team, not GitHub Apps.

## Branch Protection

Repos that require code owner review must set `require_code_owner_review: true` on protected branches. Approvals from any member of `@petry-projects/org-leads` will satisfy the requirement.

## Migration

Repos still using individual owner lists should migrate via PR replacing the legacy `* @don-petry @petry-projects-pr-review-agent @dependabot-automerge-petry` line with `* @petry-projects/org-leads`.

The `petry-projects-pr-review-agent` GitHub App reference is non-functional (GitHub Apps cannot be CODEOWNERS) and should be removed during migration.
