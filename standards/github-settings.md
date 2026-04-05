# GitHub Repository Settings Standards

Standard configurations for all repositories in the **petry-projects** organization.
These settings are enforced via the GitHub UI, API, and repository rulesets.

---

## Organization-Level Settings

| Setting | Value | Notes |
|---------|-------|-------|
| **Default repository permission** | `write` | Members get write access by default |
| **Organization profile** | `petry-projects` | Public org (free plan) |
| **Default branch name** | `main` | Org-wide default for new repos |
| **Members can create repos** | Yes (public + private) | |
| **Two-factor requirement** | **Required** | All org members must have 2FA enabled |

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
| **Has Projects** | `true` | Currently enabled on all repos |
| **Has Wiki** | `false` | Disabled — documentation lives in the repo |
| **Has Discussions** | `true` | Enabled for community engagement |

### Merge Settings

| Setting | Standard Value | Rationale |
|---------|---------------|-----------|
| **Allow squash merging** | `true` | **Primary merge method** — enforced by `pr-quality` ruleset |
| **Allow merge commits** | `true` | Enabled to avoid conflicts with admin overrides; `pr-quality` ruleset enforces squash-only |
| **Allow rebase merging** | `true` | Enabled to avoid conflicts with admin overrides; `pr-quality` ruleset enforces squash-only |
| **Allow auto-merge** | `true` | Required for Dependabot auto-merge workflow |
| **Automatically delete head branches** | `true` | Clean up merged branches automatically |
| **Default squash merge commit title** | `PR_TITLE` | Clean, descriptive commit history |
| **Default squash merge commit message** | Commit messages (`COMMIT_MESSAGES`) | Preserves individual commit messages |

> **Note:** While merge commits and rebase merging are enabled at the repository
> level, the `pr-quality` ruleset enforces **squash-only** merges. The repo-level
> settings are permissive to avoid conflicts with admin overrides when needed.

---

## Repository Rulesets

Rulesets are the primary enforcement mechanism for branch policies. All
repositories MUST use rulesets on the default branch. Classic branch protection
rules are deprecated — migrate existing classic rules to rulesets.

### `pr-quality` — Standard Ruleset (All Repositories)

| Setting | Value |
|---------|-------|
| **Target branches** | Default branch (`main`) |
| **Enforcement** | Active |
| **Required approving reviews** | 1 |
| **Dismiss stale reviews on push** | **Yes** — prevents merging unreviewed code after approval |
| **Required review thread resolution** | **Yes** — all threads must be Resolved before merge |
| **Require code owner review** | **Yes** — requires approval from a CODEOWNERS-defined owner |
| **Require last push approval** | **Yes** — the person who pushed last cannot be the sole approver |
| **Allowed merge methods** | **Squash only** |
| **Allow force pushes** | No |
| **Allow deletions** | No |

> **CODEOWNERS:** Repos SHOULD add a `CODEOWNERS` file defining ownership.
> Without one, the "Require code owner review" setting has no effect. Add
> CODEOWNERS incrementally as team structure and domain ownership solidifies.

### `code-quality` — Conditional Checks Ruleset

Required status checks are configured per-repo based on which tools are
present. Add checks to this ruleset when the corresponding configuration exists
in the repository:

| Condition | Required Check(s) |
|-----------|--------------------|
| Repo has a `sonarcloud.yml` workflow or `sonar-project.properties` | `SonarCloud` |
| Repo has a `codeql.yml` workflow | `Analyze` (or `Analyze (<language>)` for multi-language) |
| Repo has a `claude.yml` workflow | `claude` |
| Repo has a `ci.yml` workflow | CI job name (e.g., `build-and-test`, `TypeScript`, `Go`) |
| Repo has a `coverage.yml` or coverage step | `coverage` |

Additional settings:

| Setting | Value |
|---------|-------|
| **Require branches to be up to date** | Yes (`strict: true`) |
| **Enforce for admins** | Yes |

When adding a new repository, determine which CI tools apply to its stack
(see [CI Standards](ci-standards.md)) and add the corresponding checks.

---

## GitHub Apps & Integrations

### Installed GitHub Apps (org-wide, all repos)

| App | Purpose | Installed |
|-----|---------|-----------|
| **Claude** | AI code review and PR assistance via Claude Code Action | 2026-03-20 |
| **dependabot-automerge-petry** | Provides approving review for Dependabot auto-merge (bypasses branch protection) | 2026-03-23 |
| **SonarQube Cloud (SonarCloud)** | Code quality, security hotspots, coverage tracking | 2026-03-25 |
| **CodeRabbit AI** | AI-powered code review on PRs | 2026-03-25 |

### Other Integrations

| Integration | Purpose | Scope |
|-------------|---------|-------|
| **GitHub Copilot** | AI code review (native GitHub feature) | All repos |
| **CodeQL** | Static analysis (SAST) via GitHub Actions | Repos with CodeQL workflows |
| **Dependabot** | Security updates for dependencies | All repos (see [Dependabot Policy](dependabot-policy.md)) |

### GitHub App Secrets for Auto-Merge

The `dependabot-automerge-petry` app provides the approving review required by
rulesets for automated Dependabot merges. These secrets are configured at the
**organization level** and inherited by all repos:

| Secret | Level | Purpose |
|--------|-------|---------|
| `APP_ID` | Organization | GitHub App ID (app_id: 3167543) |
| `APP_PRIVATE_KEY` | Organization | GitHub App private key |

New repositories automatically inherit these secrets — no per-repo configuration needed.

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

1. **Create the repo** with standard settings (public, `main` branch, wiki disabled, discussions enabled)
2. **Create the `pr-quality` ruleset** matching the standard configuration above
3. **Create the `code-quality` ruleset** with required checks for the repo's stack
4. **Add a `CODEOWNERS` file** defining ownership for the repo's key paths
5. **Add Dependabot configuration** — copy the appropriate template from
   [`standards/dependabot/`](dependabot/) and add to `.github/dependabot.yml`
6. **Add CI workflows** — see [CI Standards](ci-standards.md) for required workflows
7. **Create standard labels** — all labels from the [Standard Set](#labels--standard-set) above, plus any project-specific labels
8. **Enable auto-delete head branches** and **auto-merge** in repo settings
9. **Connect integrations** — ensure CodeRabbit and SonarCloud (if applicable) are enabled

> **Note:** Org-level secrets (`APP_ID`, `APP_PRIVATE_KEY`, `CLAUDE_CODE_OAUTH_TOKEN`)
> are inherited automatically. Repo-specific secrets (e.g., `SONAR_TOKEN`, GCP
> credentials) must be configured per-repo.

---

## Current Compliance Status

Settings deviations from the standard documented above:

| Repository | Deviations |
|------------|-----------|
| **bmad-bgreat-suite** | No rulesets, `delete_branch_on_merge: false`, `allow_auto_merge: false`, `has_wiki: true`, `has_discussions: false` |
| **ContentTwin** | `allow_auto_merge: false`, `has_discussions: false` |
| **google-app-scripts** | `allow_merge_commit: false`, `allow_rebase_merge: false` (stricter than standard), `has_discussions: false` |
| **broodly** | `has_wiki: true`, `has_discussions: false` |
| **markets** | `has_wiki: true`, `has_discussions: false` |
| **TalkTerm** | `has_wiki: true`, `has_discussions: false` |

> **Migration note:** All repos currently use classic branch protection. These
> should be migrated to rulesets per the standard above. Classic rules should
> be removed after rulesets are verified.

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
