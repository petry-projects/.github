# Initiatives Project — operator guide

The **Initiatives** project board ([orgs/petry-projects/projects/1](https://github.com/orgs/petry-projects/projects/1)) is the org's single cross-repo plane for strategic work. It's the home for items that span multiple PRs, multiple repos, or multiple agents — anything that an `gh issue list` filter would lose track of.

This doc covers what belongs on the board, how items get there, and how to operate the project. The pilot itself is tracked in [#387](https://github.com/petry-projects/.github/issues/387).

## What belongs on the board

The signal we filter for is **"strategic work that benefits from a roll-up view"**, not "every dev-lead-handled issue".

### Auto-added (no manual step)

| Content type | Conditions | Result |
|---|---|---|
| Issues / PRs in `petry-projects/.github` | Has label `dev-lead` AND none of `compliance-audit`, `health-check`, `fleet-tracker`, `daily-report` | Linked item appears on the board |
| Discussions in `petry-projects/.github` | Category is `Ideas` | Draft item appears with title `[Discussion #N] <title>` |

The four excluded labels are the noise gate. They flag automation-generated work that, while real, doesn't belong on a strategic roll-up: routine compliance fixes, fleet-monitor failures, daily status reports.

### Auto-cleaned

| Trigger | Result |
|---|---|
| Ideas discussion moved to a non-Ideas category | Draft is deleted |
| Ideas discussion deleted | Draft is deleted |
| Ideas discussion transferred to another repo | Draft is deleted |

The reconciliation is idempotent — re-delivered webhooks don't double-error.

### Not auto-added (manual add path)

- **Issues / PRs from repos other than `.github`** — multi-repo rollout is a follow-on (see deferred items below).
- **Fork PRs labeled by a maintainer when the author is `FIRST_TIMER` / `CONTRIBUTOR`.** The `pull_request_target` gate evaluates the PR author's association; this is documented as a known limit in the workflow header.
- **Historical (already-open) qualifying items.** The workflow only fires on new events. To backfill, add via the UI or the GraphQL API.

To add a content-linked item manually:

```bash
# Find the issue/PR node ID
NODE_ID=$(gh api graphql -f query='{
  repository(owner:"<owner>",name:"<repo>") {
    issue(number:<n>) { id }
  }
}' -q '.data.repository.issue.id')

# Add to the project
gh api graphql -F projectId="PVT_kwDOD2inqs4BZq3-" -F contentId="$NODE_ID" \
  -f query='mutation($projectId:ID!,$contentId:ID!){
    addProjectV2ItemById(input:{projectId:$projectId,contentId:$contentId}){ item { id } }
  }'
```

## Fields

| Field | Values | Use it for |
|---|---|---|
| **Status** | `Inbox` → `Specced` → `In Dev` → `In Review` → `Deployed` → `Verified` → `Wont do` | Stage tracking. `Inbox` is the default for auto-adds; promote manually as work moves. |
| **Initiative** | `Compliance Blitz`, `Compliance program`, `Fleet Monitor`, `Agent Shield`, `Auto-rebase`, `Self-healing`, `Model fallback`, `Tooling`, `Ad hoc` | Program bucket — what initiative this item belongs to. |
| **Work type** | `Feature`, `Spike`, `Fix`, `Infra`, `Security`, `Docs` | Categorization. (Named `Work type`, not `Type` — `Type` is a reserved field name in GitHub Projects v2.) |
| **Priority** | `P0`, `P1`, `P2`, `P3` | Triage / sequencing. |
| **Owner-agent** | `dev-lead`, `claude`, `coderabbit`, `copilot`, `human` | Who's expected to drive this. |
| **Target date** | (date) | Optional commitment date. Used on the Roadmap view. |

Field schema is locked in for the pilot's 30-day review window. Renaming or removing single-select options on a populated project is painful — propose schema changes in [#387](https://github.com/petry-projects/.github/issues/387).

## Views

The project ships with four views (the API can't create them; they're configured manually in the UI):

| View | Layout | Use it when |
|---|---|---|
| **Roadmap** | Table, grouped by Initiative, sorted by Status | Planning, weekly review |
| **In flight** | Board, columns = Status, filter `-status:Inbox -status:Verified -status:"Wont do"` | Daily standup-equivalent — what's actually moving |
| **Ideation** | Table, filter `status:Inbox`, sorted by Created desc | Triage queue for new ideas |
| **By agent** | Board, columns = Owner-agent | "What's on each agent's plate" snapshot |

## How the auto-add works

```
.github/workflows/add-to-project.yml             # Workflow (events → script call)
.github/scripts/add-to-project/
    add-issue-or-pr.sh                           # Noise gate + addProjectV2ItemById
    reconcile-discussion.sh                      # Paginated find + 4-state reconciler
.github/workflows/add-to-project-tests.yml       # shellcheck + bats CI gate
test/workflows/add-to-project/                   # 35 bats tests, gh stub, fixtures
```

**Auth:** A dedicated GitHub App (`petry-projects-planner`, App ID `3985527`) installed on the org. The workflow mints a fresh installation token per run via `actions/create-github-app-token@v3.2.0` — no static long-lived token. App permissions: Organization Projects `Read+write`, Repository Issues `Read`, Repository Pull requests `Read`. Org secrets: `INITIATIVES_APP_ID`, `INITIATIVES_APP_PRIVATE_KEY`.

**Concurrency:** Workflow runs for the same content (same issue / PR / discussion number) serialize via concurrency group — `created` and `category_changed` for the same discussion can't race against each other.

**Project ID:** `PVT_kwDOD2inqs4BZq3-` (hardcoded in the workflow env). Multi-Project consumers of the same scripts would parameterize this.

## Deferred work (not in the pilot)

Tracked in [#415](https://github.com/petry-projects/.github/issues/415). Summary:

- **Multi-repo rollout** — workflow only fires for events in `.github` today.
- **Issue/PR cleanup-on-label-change** — `process_issue_or_pr` only adds; it doesn't reconcile when an existing item later receives an excluded label.
- **Configurable noise gate** — required-label + excluded-labels list is hard-coded in `evaluate_noise_gate`. Same for `Ideas` category in `reconcile_discussion`.
- **Fork-PR maintainer-label gate** — `pull_request_target` author_association evaluates the PR author, not the labeler.

These belong in one follow-on PR so the underlying mechanism (a generic `reconcile_content_with_project`) gets designed once instead of three times.

## Related

- **Tracking:** [#387](https://github.com/petry-projects/.github/issues/387)
- **Founding discussion:** [#386](https://github.com/petry-projects/.github/discussions/386)
- **Validation + 30-day review:** [#414](https://github.com/petry-projects/.github/issues/414)
- **Multi-repo follow-on:** [#415](https://github.com/petry-projects/.github/issues/415)
- **Pilot retrospective:** [#416](https://github.com/petry-projects/.github/issues/416)
- **Issue Fields rollout:** discussion [#364](https://github.com/petry-projects/.github/discussions/364) (waiting on Project schema to stabilize ~30 days)
