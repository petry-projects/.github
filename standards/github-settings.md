# GitHub Repository Settings Standards

Standard configurations for all repositories in the **petry-projects** organization.
These settings are enforced via the GitHub UI, API, and repository rulesets.

---

## Organization-Level Settings

| Setting | Value | Notes |
|---------|-------|-------|
| **Default repository permission** | `read` | Least privilege; grant write/admin via teams |
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

### `code-quality` — Required Checks Ruleset (All Repositories)

Every repository MUST have all five quality checks configured and required.
The specific check names and ecosystem configurations vary by repo, but the
categories are universal.

#### Required Check Categories

| Check | Required | Check Name(s) | Notes |
|-------|----------|---------------|-------|
| **SonarCloud** | All repos | `SonarCloud` | Code quality, maintainability, security hotspots |
| **CodeQL** | All repos | `Analyze` or `Analyze (<language>)` | SAST — all ecosystems present in the repo must be configured |
| **Claude Code** | All repos | `claude` | AI code review on every PR |
| **CI Pipeline** | All repos | Repo-specific (e.g., `build-and-test`, `TypeScript`, `Go`) | Lint, format, typecheck, test |
| **Coverage** | All repos | `coverage` or embedded in CI job | Must meet repo-defined thresholds |

#### Ecosystem-Specific Configuration

The ecosystems scanned by each check depend on which languages/tools the repo
contains. If a repo contains an ecosystem, that ecosystem MUST be configured
in the relevant checks:

| Ecosystem Detected | CodeQL Language | SonarCloud | CI Pipeline | Dependency Audit |
|--------------------|----------------|------------|-------------|------------------|
| `package.json` / `package-lock.json` | `javascript-typescript` | JS/TS analysis | npm/pnpm lint, typecheck, test | `npm audit` or `pnpm audit` |
| `go.mod` | `go` | Go analysis | `go vet`, `golangci-lint`, `go test` | `govulncheck` |
| `Cargo.toml` | `rust` (if supported) | Rust analysis | `cargo fmt`, `cargo check`, `cargo test` | `cargo audit` |
| `pyproject.toml` / `requirements.txt` | `python` | Python analysis | pytest, coverage | `pip-audit` |
| `.github/workflows/*.yml` | `actions` | — | — | — |
| `*.tf` (Terraform) | — | — | `terraform validate` | Dependabot security updates |

Multi-language repos (e.g., TypeScript + Go) MUST configure all applicable
ecosystems in each check.

#### Additional Settings

| Setting | Value |
|---------|-------|
| **Require branches to be up to date** | Yes (`strict: true`) |
| **Enforce for admins** | Yes |

See [CI Standards](ci-standards.md) for workflow templates and patterns.

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

### Organization-Level Secrets for Standard CI

These secrets are configured at the **organization level** and inherited by
all repos automatically — no per-repo setup needed:

| Secret | Purpose |
|--------|---------|
| `APP_ID` | GitHub App ID for Dependabot auto-merge (app_id: 3167543) |
| `APP_PRIVATE_KEY` | GitHub App private key for Dependabot auto-merge |
| `CLAUDE_CODE_OAUTH_TOKEN` | Authentication for Claude Code Action |
| `SONAR_TOKEN` | SonarCloud analysis authentication |

Repos's may require repo-specific secrets beyond this standard set.

---

## Labels — Standard Set

All repositories MUST have these labels configured:

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

> **Note:** All standard CI secrets are configured at the org level and inherited
> automatically — see [Organization-Level Secrets](#organization-level-secrets-for-standard-ci).
> No per-repo secret setup is needed for standard CI workflows.

---

## Applying Standard Settings

Use the [`scripts/apply-repo-settings.sh`](../scripts/apply-repo-settings.sh) script to apply
or verify the standard boolean settings on any repository:

```bash
# Apply to a single repo (requires a token with repo admin scope)
GH_TOKEN=<admin-token> bash scripts/apply-repo-settings.sh .github

# Preview changes without applying
DRY_RUN=true GH_TOKEN=<token> bash scripts/apply-repo-settings.sh --all

# Apply to all repos
GH_TOKEN=<admin-token> bash scripts/apply-repo-settings.sh --all
```

The script enforces: `delete_branch_on_merge`, `allow_auto_merge`, `has_wiki`, `has_issues`.

---

## Current Compliance Status

Settings deviations from the standard documented above:

| Repository | Deviations |
|------------|-----------|
| **.github** | `delete_branch_on_merge: null` — run `bash scripts/apply-repo-settings.sh .github` to remediate |
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
