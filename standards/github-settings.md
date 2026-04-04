# GitHub Repository Settings Standards

Standard configurations for all repositories in the **petry-projects** organization.
These settings are enforced via the GitHub UI, API, and repository rulesets.

---

## Organization-Level Settings

| Setting | Value | Notes |
|---------|-------|-------|
| **Default repository permission** | `read` | Members get read access; write access is per-repo |
| **Organization profile** | `petry-projects` | Public org |
| **Dependabot security updates** | Enabled | Org-wide default; repos inherit unless overridden |

---

## Repository Settings — Standard Defaults

All new repositories MUST be created with these settings. Existing repositories
SHOULD be audited and brought into compliance.

### General

| Setting | Standard Value | Rationale |
|---------|---------------|-----------|
| **Default branch** | `main` | All repos use `main` |
| **Visibility** | `public` | Default for org repos; private repos require justification |
| **Has Issues** | `true` | Issue tracking enabled on all repos |
| **Has Projects** | `false` | GitHub Projects disabled by default (use org-level projects if needed) |
| **Has Wiki** | `false` | Wiki disabled; documentation lives in the repo |
| **Has Discussions** | `false` | Disabled by default |

### Merge Settings

| Setting | Standard Value | Rationale |
|---------|---------------|-----------|
| **Allow squash merging** | `true` | **Primary merge method** — enforced by `pr-quality` ruleset |
| **Allow merge commits** | `true` | Enabled to avoid conflicts with admin overrides; `pr-quality` ruleset enforces squash-only |
| **Allow rebase merging** | `true` | Enabled to avoid conflicts with admin overrides; `pr-quality` ruleset enforces squash-only |
| **Allow auto-merge** | `true` | Required for Dependabot auto-merge workflow |
| **Automatically delete head branches** | `true` | Clean up merged branches automatically |
| **Default squash merge commit title** | PR title | Keeps commit history clean |
| **Default squash merge commit message** | PR body | Preserves PR description in commit |

> **Note:** While merge commits and rebase merging are enabled at the repository
> level, the `pr-quality` ruleset enforces **squash-only** merges. The repo-level
> settings are permissive to avoid conflicts with admin overrides when needed.

---

## Branch Protection — Classic Rules

All repositories enforce classic branch protection on the `main` branch.

### Standard Configuration

| Setting | Value |
|---------|-------|
| **Require pull request before merging** | Yes |
| **Required approving reviews** | 1 |
| **Dismiss stale reviews** | No |
| **Require code owner reviews** | No |
| **Require status checks to pass** | Yes |
| **Require branches to be up to date** | Yes (`strict: true`) |
| **Enforce for admins** | Yes |
| **Allow force pushes** | No |
| **Allow deletions** | No |

### Required Status Checks by Repository

Each repository has specific required status checks based on its tech stack and
CI configuration. The table below lists the current required checks:

| Repository | Required Checks | Stack |
|------------|----------------|-------|
| **broodly** | `Analyze` (CodeQL) | Rust |
| **markets** | `SonarCloud`, `claude` | TypeScript/Go fullstack |
| **google-app-scripts** | `build-and-test` | TypeScript (Apps Script) |
| **TalkTerm** | `Analyze (Python)` (CodeQL) | Python |
| **ContentTwin** | `SonarCloud` | TypeScript |
| **bmad-bgreat-suite** | *(pending — new repo)* | TypeScript |

When adding a new repository, configure the required status checks to match the
tools and checks available for its tech stack (see [CI Standards](ci-standards.md)).

---

## Repository Rulesets

### `pr-quality` (All Repositories)

The `pr-quality` ruleset is applied to all org repos and enforces merge
discipline beyond what classic branch protection provides.

| Setting | Value |
|---------|-------|
| **Target branches** | Default branch (`main`) |
| **Required approving reviews** | 1 |
| **Required review thread resolution** | **Yes** — all threads must be Resolved before merge |
| **Dismiss stale reviews on push** | No |
| **Require code owner review** | No |
| **Require last push approval** | No |
| **Allowed merge methods** | **Squash only** |

### `protect-branches` (google-app-scripts)

The `google-app-scripts` repository has an additional ruleset that layers on
top of `pr-quality` with code scanning gates and tighter review policies:

| Setting | Value |
|---------|-------|
| **Required approving reviews** | 0 (relies on `pr-quality` for approval requirement) |
| **Dismiss stale reviews on push** | Yes |
| **Required review thread resolution** | Yes |
| **Allowed merge methods** | Squash only |
| **Code scanning — CodeQL** | Errors threshold: `errors`; Security alerts: `high_or_higher` |
| **Required status checks** | `Analyze (CodeQL) (javascript)`, `CodeQL`, `coverage` |
| **Branch restrictions** | No direct push, no deletion, no non-fast-forward, no branch creation |

---

## GitHub Apps & Integrations

### Required Integrations

| App / Integration | Purpose | Scope |
|-------------------|---------|-------|
| **CodeRabbit** | AI-powered code review on PRs | All repos |
| **GitHub Copilot** | AI code review (native) | All repos |
| **SonarCloud** | Code quality, security hotspots, coverage | Repos with SonarCloud checks |
| **CodeQL** | Static analysis (SAST) | Repos with CodeQL workflows |
| **Dependabot** | Security updates for dependencies | All repos (see [Dependabot Policy](dependabot-policy.md)) |

### GitHub App for Auto-Merge

A GitHub App is used to provide the approving review required by branch
protection for automated Dependabot merges. Each repository that uses the
Dependabot auto-merge workflow must have these secrets configured:

| Secret | Purpose |
|--------|---------|
| `APP_ID` | GitHub App ID |
| `APP_PRIVATE_KEY` | GitHub App private key |

---

## Labels — Standard Set

All repositories SHOULD have these labels available:

| Label | Color | Purpose |
|-------|-------|---------|
| `security` | `#d93f0b` (red) | Security-related PRs and issues |
| `dependencies` | `#0075ca` (blue) | Dependency update PRs |
| `scorecard` | `#d93f0b` (red) | OpenSSF Scorecard findings (auto-created) |
| `bug` | `#d73a4a` (red) | Bug reports |
| `enhancement` | `#a2eeef` (teal) | Feature requests |
| `documentation` | `#0075ca` (blue) | Documentation changes |

---

## Applying to a New Repository

When creating a new repository in `petry-projects`:

1. **Create the repo** with standard settings (public, `main` branch, no wiki/projects)
2. **Enable branch protection** on `main` with the standard configuration above
3. **Create the `pr-quality` ruleset** (or apply the org-level ruleset if available)
4. **Add Dependabot configuration** — copy the appropriate template from
   [`standards/dependabot/`](dependabot/) and add to `.github/dependabot.yml`
5. **Add CI workflows** — see [CI Standards](ci-standards.md) for required workflows
6. **Configure secrets** — add `APP_ID` and `APP_PRIVATE_KEY` for Dependabot auto-merge
7. **Create standard labels** — `security`, `dependencies`, plus any project-specific labels
8. **Enable auto-delete head branches** in repo settings
9. **Connect integrations** — ensure CodeRabbit and SonarCloud (if applicable) are enabled

---

## Audit & Compliance

The org runs a weekly [OpenSSF Scorecard](https://github.com/ossf/scorecard)
audit via the [`org-scorecard.yml`](../.github/workflows/org-scorecard.yml)
workflow. This workflow:

- Scans all public repos in the org
- Creates/updates GitHub Issues for findings (labeled `scorecard`)
- Auto-closes issues when checks reach a score of 10/10
- Produces a summary report in the workflow step summary

Scorecard results should be reviewed weekly and remediated per the
[OpenSSF Scorecard documentation](https://github.com/ossf/scorecard/blob/main/docs/checks.md).
