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
<<<<<<< HEAD
<<<<<<< HEAD
| **Has Discussions** | `true` | **Required** — enables Discussions for ideation, feedback, and community engagement (see [Discussions Configuration](#discussions-configuration)) |

### Security & Analysis

All repositories MUST have the following security features enabled. These are
the enforcement primitives behind the [Push Protection Standard](push-protection.md).

| Setting | Standard Value | Rationale |
|---------|---------------|-----------|
| **Secret scanning** | `enabled` | Detect leaked credentials in history and new commits |
| **Secret scanning push protection** | `enabled` | Block pushes containing known secret patterns at the server side |
| **Secret scanning AI detection** | `enabled` | Catch generic secrets missed by regex patterns |
| **Secret scanning non-provider patterns** | `enabled` | Private keys, HTTP basic auth, high-entropy strings |
| **Dependabot security updates** | `enabled` | Automated patches for known-vulnerable dependencies |

> See the full requirements, custom patterns, CI job, incident response flow,
> and compliance audit checks in [`push-protection.md`](push-protection.md).
<<<<<<< HEAD
=======
| **Has Discussions** | `true` | Enabled for community engagement |
>>>>>>> ed24e34 (docs: add GitHub repository settings standards (#10))
=======
| **Has Discussions** | `true` | **Required** — enables Discussions for ideation, feedback, and community engagement (see [Discussions Configuration](#discussions-configuration)) |
>>>>>>> e1cf1d8 (feat: require GitHub Discussions on all repos (#53))
=======
>>>>>>> d1ac0ee (docs(standards): propose push protection standard (#95))

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

<<<<<<< HEAD
<<<<<<< HEAD
=======
>>>>>>> e1cf1d8 (feat: require GitHub Discussions on all repos (#53))
## Discussions Configuration

GitHub Discussions MUST be enabled on all repositories. Discussions serve as the
durable, threaded home for feature ideation, design proposals, and community
feedback — distinct from Issues (which track actionable work).

### Required Discussion Categories

All repositories MUST have the following categories configured:

| Category | Format | Emoji | Description |
|----------|--------|-------|-------------|
| **Ideas** | Open-ended | `💡` | Feature proposals, ideation threads, and innovation exploration |
| **General** | Open-ended | `💬` | General project discussions and questions |

Additional categories MAY be added per project needs (e.g., "Q&A", "Show and Tell",
"Polls"). The two above are the required minimum.

### Automated Ideation Workflow

Repositories with the [BMAD Method](https://github.com/bmad-code-org/BMAD-METHOD)
installed (`_bmad/` directory) MUST have the `feature-ideation.yml` workflow,
which uses the **Ideas** category to post and maintain feature proposal
Discussions. Each proposal is a separate Discussion thread, updated by subsequent
workflow runs as market signals and project context evolve. See
[CI Standards § Feature Ideation](ci-standards.md#8-feature-ideation-feature-ideationyml-bmad-method-repos)
for requirements.

### Setup

To enable and configure Discussions on an existing repository:

```bash
# Enable Discussions
gh api -X PATCH repos/<owner>/<repo> -f has_discussions=true

# Discussion categories are managed via the GitHub UI:
# Settings → General → Features → Discussions → Set up discussions
# Or via GraphQL after initial setup.
```

> **Note:** Discussion categories cannot currently be created via the REST API.
> Use the GitHub UI or GraphQL `createDiscussionCategory` mutation. The compliance
> audit checks that Discussions are enabled; category configuration is verified
> manually during onboarding.

---

<<<<<<< HEAD
=======
>>>>>>> ed24e34 (docs: add GitHub repository settings standards (#10))
=======
>>>>>>> e1cf1d8 (feat: require GitHub Discussions on all repos (#53))
## Repository Rulesets

Rulesets are the primary enforcement mechanism for branch policies. All
repositories MUST use rulesets on the default branch. Classic branch protection
rules are deprecated — migrate existing classic rules to rulesets.

<<<<<<< HEAD
<<<<<<< HEAD
=======
>>>>>>> 0cb4bba (fix(dependabot): fix automerge stall — bypass fallback, schedule trigger, standards enforcement)
### Bypass Actors — Required on Every Ruleset Targeting `main`

**The `dependabot-automerge-petry` GitHub App MUST be a bypass actor on every
ruleset that targets the default branch**, not only on `pr-quality`. GitHub
evaluates bypass eligibility independently per ruleset — having bypass in
`pr-quality` does NOT grant bypass in `protect-branches`, `main`, or any other
ruleset applied to the same branch. Every such ruleset must include:

| Actor | Type | `bypass_mode` | Reason |
|-------|------|--------------|--------|
| `dependabot-automerge-petry` | GitHub App | `always` | Merges Dependabot PRs via API; rejected without bypass in every active ruleset |
| `OrganizationAdmin` | Role | `always` | Emergency admin override |

**Why `bypass_mode: always`:** `pull_request` bypass mode only works when the
bypass actor *opens* the PR. Dependabot opens its own PRs, so the
`dependabot-automerge-petry` app cannot use that mode — its merge API calls are
rejected. `always` mode is safe here because the rebase workflow explicitly
verifies CI pass and `MERGEABLE` state before calling the merge API.

**API snippet to add the bypass actor to an existing ruleset:**

```bash
# Get current ruleset (capture bypass_actors and rules arrays)
gh api repos/petry-projects/<repo>/rulesets/<ruleset-id>

# PUT the full ruleset back, adding actor_id 3167543 to bypass_actors
gh api repos/petry-projects/<repo>/rulesets/<ruleset-id> \
  -X PUT --input ruleset.json
# where ruleset.json adds {"actor_id": 3167543, "actor_type": "Integration", "bypass_mode": "always"}
# to the existing bypass_actors array alongside all existing rules and conditions.
```

**Compliance check:** verify all rulesets on all repos have the bypass actor:

```bash
for repo in $(gh repo list petry-projects --json name --jq '.[].name' --limit 1000); do
  for rs_id in $(gh api "repos/petry-projects/$repo/rulesets" --jq '.[].id' 2>/dev/null); do
    rs=$(gh api "repos/petry-projects/$repo/rulesets/$rs_id" 2>/dev/null)
    missing=$(echo "$rs" | jq '[.bypass_actors[]? | select(.actor_id == 3167543)] | length == 0')
    [[ "$missing" == "true" ]] && echo "MISSING: $repo / $(echo "$rs" | jq -r '.name')"
  done
done
```

<<<<<<< HEAD
=======
>>>>>>> ed24e34 (docs: add GitHub repository settings standards (#10))
=======
>>>>>>> 0cb4bba (fix(dependabot): fix automerge stall — bypass fallback, schedule trigger, standards enforcement)
### `pr-quality` — Standard Ruleset (All Repositories)

| Setting | Value |
|---------|-------|
| **Target branches** | Default branch (`main`) |
| **Enforcement** | Active |
| **Required approving reviews** | 1 |
| **Dismiss stale reviews on push** | **Yes** — prevents merging unreviewed code after approval |
| **Required review thread resolution** | **Yes** — all threads must be Resolved before merge |
| **Require code owner review** | **Yes** — requires approval from a CODEOWNERS-defined owner |
<<<<<<< HEAD
<<<<<<< HEAD
| **Require last push approval** | **Yes** — ensures different people review substantive code changes; Dependabot rebase workflow re-approves after branch updates to maintain approval validity |
| **Allow auto-merge** | **Yes** — enables automatic merge when all status checks pass and requirements are satisfied |
<<<<<<< HEAD
=======
| **Require last push approval** | **Yes** — the person who pushed last cannot be the sole approver |
>>>>>>> ed24e34 (docs: add GitHub repository settings standards (#10))
=======
| **Require last push approval** | **Yes** — ensures different people review substantive code changes; Dependabot rebase workflow re-approves after branch updates to maintain approval validity |
>>>>>>> 35e0e20 (fix(dependabot-rebase): re-approve PRs after branch updates to unblock auto-merge)
=======
>>>>>>> 12858a4 (docs: require auto-merge in ruleset standards (#194))
| **Allowed merge methods** | **Squash only** |
| **Allow force pushes** | No |
| **Allow deletions** | No |

<<<<<<< HEAD
<<<<<<< HEAD
> **CODEOWNERS:** All repos MUST have a `CODEOWNERS` file. Without one, the
> "Require code owner review" setting has no effect. See the
> [CODEOWNERS Standard](#codeowners-standard) below for the required format.

<<<<<<< HEAD
<<<<<<< HEAD
=======
>>>>>>> 12858a4 (docs: require auto-merge in ruleset standards (#194))
#### Auto-Merge Configuration

The **Allow auto-merge** setting enables PRs to merge automatically once all status checks pass and review requirements are satisfied. This is required for:

- **Dependabot auto-merge workflows** — enables `gh pr merge --auto` API calls
- **Agentic PR automation** — CI/CD agents can queue PRs for automatic merge after approval and check passage
- **Efficient CI workflows** — avoids manual merge steps when all quality gates have passed

Auto-merge is a **safe setting** because the ruleset still enforces all approval and review requirements before
the merge occurs — the automation only handles the final merge step after human review and all CI checks pass.
See [GitHub's auto-merge documentation](https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/incorporating-changes-from-a-pull-request/automatically-merging-a-pull-request)
for more details.

<<<<<<< HEAD
#### Bypass Actors

See [Bypass Actors — Required on Every Ruleset Targeting `main`](#bypass-actors--required-on-every-ruleset-targeting-main) above.
The same `dependabot-automerge-petry` + `OrganizationAdmin` bypass actors MUST appear in `pr-quality` and in every other ruleset that targets `main`.
=======
=======
>>>>>>> 12858a4 (docs: require auto-merge in ruleset standards (#194))
#### Bypass Actors

<<<<<<< HEAD
The `pr-quality` ruleset MUST include the following bypass actors:

| Actor | Type | `bypass_mode` | Reason |
|-------|------|--------------|--------|
| `dependabot-automerge-petry` | GitHub App | `always` | Approves and merges Dependabot PRs; must bypass review gate |
| `OrganizationAdmin` | Role | `always` | Emergency admin override |

> **Critical:** `bypass_mode: pull_request` does **not** work for Dependabot PRs.
> That mode only bypasses review requirements when the bypass actor *opens* the PR
> via the PR flow. Since `dependabot[bot]` opens Dependabot PRs, the
> `dependabot-automerge-petry` app cannot use `pull_request` bypass for them —
> its merge API calls are rejected with `Required status check` errors.
> Use `bypass_mode: always` so the app can call `gh api .../merge` directly
> after manually verifying CI. The rebase workflow verifies CI before merging,
> so `always` does not bypass safety checks.
>>>>>>> 177e3d7 (docs: update standards with Dependabot auto-merge learnings (#187))
=======
See [Bypass Actors — Required on Every Ruleset Targeting `main`](#bypass-actors--required-on-every-ruleset-targeting-main) above.
The same `dependabot-automerge-petry` + `OrganizationAdmin` bypass actors MUST appear in `pr-quality` and in every other ruleset that targets `main`.
>>>>>>> 0cb4bba (fix(dependabot): fix automerge stall — bypass fallback, schedule trigger, standards enforcement)

#### CODEOWNERS Approval Timing

GitHub evaluates code owner status **at the time an approval is submitted**, not
retroactively. If `CODEOWNERS` is updated (e.g., adding bot accounts), approvals
already on open PRs from those accounts are not retroactively credited as code
owner approvals.

**Recovery:** comment `@dependabot rebase` on blocked PRs. This triggers
Dependabot to push a new commit, which fires the automerge workflow and submits
a fresh approval under the current CODEOWNERS.
<<<<<<< HEAD
=======
> **CODEOWNERS:** All repos MUST have a `CODEOWNERS` file. Without one, the
> "Require code owner review" setting has no effect. See the
> [CODEOWNERS Standard](#codeowners-standard) below for the required format.
>>>>>>> b25bf5c (chore: add bot accounts to CODEOWNERS + define org standard)
=======
>>>>>>> 177e3d7 (docs: update standards with Dependabot auto-merge learnings (#187))

### `code-quality` — Required Checks Ruleset (All Repositories)

Every repository MUST have the following quality checks configured and
required. The specific check names and ecosystem configurations vary by repo,
but the categories are universal.
=======
> **CODEOWNERS:** Repos SHOULD add a `CODEOWNERS` file defining ownership.
> Without one, the "Require code owner review" setting has no effect. Add
> CODEOWNERS incrementally as team structure and domain ownership solidifies.

### `code-quality` — Required Checks Ruleset (All Repositories)

<<<<<<< HEAD
Every repository MUST have all five quality checks configured and required.
The specific check names and ecosystem configurations vary by repo, but the
categories are universal.
>>>>>>> ed24e34 (docs: add GitHub repository settings standards (#10))
=======
Every repository MUST have the following quality checks configured and
required. The specific check names and ecosystem configurations vary by repo,
but the categories are universal.
>>>>>>> eaa792d (Add org-wide push protection standard (#134))

#### Required Check Categories

| Check | Required | Check Name(s) | Notes |
|-------|----------|---------------|-------|
| **SonarCloud** | All repos | `SonarCloud` | Code quality, maintainability, security hotspots |
<<<<<<< HEAD
<<<<<<< HEAD
| **CodeQL** | All repos | `CodeQL` | SAST via GitHub-managed default setup — auto-detects all supported languages (see [ci-standards.md §2](ci-standards.md#2-codeql-analysis-github-managed-default-setup)) |
| **Claude Code** | All repos | `claude` | AI code review on every PR |
| **CI Pipeline** | All repos | Repo-specific (e.g., `build-and-test`, `TypeScript`, `Go`) | Lint, format, typecheck, test |
| **Coverage** | All repos | `coverage` or embedded in CI job | Must meet repo-defined thresholds |
| **Secret Scan** | All repos | `Secret scan (gitleaks)` | Full-history gitleaks scan — see [Push Protection Standard](push-protection.md#layer-3--ci-secret-scanning-secondary-defense) |
<<<<<<< HEAD

> **Check names must match exactly.** GitHub-managed CodeQL produces a check named
> `CodeQL` — **not** `Analyze (actions)`, `Analyze (javascript-typescript)`, or
> `CodeQL / Analyze (go)`. Requiring a check name that no job produces permanently
> blocks every PR. Verify check names against actual workflow runs:
>
> ```bash
> gh pr checks <PR-number> --repo petry-projects/<repo>
> ```
=======
| **CodeQL** | All repos | `Analyze` or `Analyze (<language>)` | SAST — all ecosystems present in the repo must be configured |
=======
| **CodeQL** | All repos | `CodeQL` | SAST via GitHub-managed default setup — auto-detects all supported languages (see [ci-standards.md §2](ci-standards.md#2-codeql-analysis-github-managed-default-setup)) |
>>>>>>> a3e9658 (Replace per-repo CodeQL workflows with GitHub default setup (#103))
| **Claude Code** | All repos | `claude` | AI code review on every PR |
| **CI Pipeline** | All repos | Repo-specific (e.g., `build-and-test`, `TypeScript`, `Go`) | Lint, format, typecheck, test |
| **Coverage** | All repos | `coverage` or embedded in CI job | Must meet repo-defined thresholds |
>>>>>>> ed24e34 (docs: add GitHub repository settings standards (#10))
=======
>>>>>>> eaa792d (Add org-wide push protection standard (#134))

> **Check names must match exactly.** GitHub-managed CodeQL produces a check named
> `CodeQL` — **not** `Analyze (actions)`, `Analyze (javascript-typescript)`, or
> `CodeQL / Analyze (go)`. Requiring a check name that no job produces permanently
> blocks every PR. Verify check names against actual workflow runs:
>
> ```bash
> gh pr checks <PR-number> --repo petry-projects/<repo>
> ```

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
<<<<<<< HEAD
<<<<<<< HEAD
| `_bmad/` (BMAD Method) | — | — | `feature-ideation.yml` (weekly) | — |
=======
>>>>>>> ed24e34 (docs: add GitHub repository settings standards (#10))
=======
| `_bmad/` (BMAD Method) | — | — | `feature-ideation.yml` (weekly) | — |
>>>>>>> e1cf1d8 (feat: require GitHub Discussions on all repos (#53))

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
<<<<<<< HEAD
<<<<<<< HEAD
<<<<<<< HEAD
=======
>>>>>>> bc338c0 (chore: finalize CODEOWNERS standard as Required + add enforcement (#193))
| **dependabot-automerge-petry** | Provides approving review for Dependabot auto-merge | 2026-03-23 |
| **petry-projects-pr-review-agent** | (deprecated) GitHub App formerly used for PR review — replaced by `donpetry-bot` machine user in `@petry-projects/org-leads` because Apps cannot be CODEOWNERS | 2026-04-01 |
| **donpetry-bot** | Machine-user account in `@petry-projects/org-leads`; satisfies CODEOWNERS for automated PR review | 2026-05-04 |
| **SonarQube Cloud (SonarCloud)** | Code quality, security hotspots, coverage tracking | 2026-03-25 |
| **CodeRabbit AI** | AI-powered code review on PRs | 2026-03-25 |

### Check-Suite Auto-Trigger Preferences

GitHub automatically creates a check suite for any app that has previously created check runs in a repo, on every push.
Some apps (Claude, CodeRabbit) create these suites proactively but only complete them when they have real work to do.
When they have nothing to do, the suite stays in `queued` state indefinitely —
**GitHub auto-merge waits for all check suites to reach a terminal state before merging**,
so these orphaned suites permanently block auto-merge.

**Required configuration** (enforced by `scripts/apply-repo-settings.sh` and detected by `scripts/compliance-audit.sh`):

| App | app_id | Setting |
|-----|--------|---------|
| Claude (`anthropics/claude-code-action`) | `1236702` | `auto_trigger_checks: false` |
| CodeRabbit | `347564` | `auto_trigger_checks: false` |

Disabling auto-trigger stops GitHub from creating suites on every push. The apps still create suites explicitly when they have work to report.

If an app has never created a check run in a repository, GitHub omits that app from `auto_trigger_checks` entirely.
Both `scripts/apply-repo-settings.sh` and `scripts/compliance-audit.sh` treat this `missing` state as compliant —
no PATCH is needed and no finding is raised until the app is first seen in the repo.

**Applying manually** (requires a classic PAT with `repo` scope — OAuth app tokens are rejected by this API endpoint):

```bash
GH_TOKEN=<classic-pat> bash scripts/apply-repo-settings.sh <repo-name>
# or for all org repos:
GH_TOKEN=<classic-pat> bash scripts/apply-repo-settings.sh --all
```

<<<<<<< HEAD
=======
| **dependabot-automerge-petry** | Provides approving review for Dependabot auto-merge (bypasses branch protection) | 2026-03-23 |
=======
| **dependabot-automerge-petry** | Provides approving review for Dependabot auto-merge; listed in CODEOWNERS so its approvals satisfy `require_code_owner_review` | 2026-03-23 |
| **petry-projects-pr-review-agent** | General PR review agent; listed in CODEOWNERS as the org-standard automation reviewer | 2026-04-01 |
>>>>>>> b25bf5c (chore: add bot accounts to CODEOWNERS + define org standard)
| **SonarQube Cloud (SonarCloud)** | Code quality, security hotspots, coverage tracking | 2026-03-25 |
| **CodeRabbit AI** | AI-powered code review on PRs | 2026-03-25 |

>>>>>>> ed24e34 (docs: add GitHub repository settings standards (#10))
=======
>>>>>>> d23e834 (fix: disable Claude + CodeRabbit auto-trigger check suites to unblock auto-merge (#195))
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

<<<<<<< HEAD
<<<<<<< HEAD
Repos may require repo-specific secrets beyond this standard set.
=======
Repos's may require repo-specific secrets beyond this standard set.
>>>>>>> ed24e34 (docs: add GitHub repository settings standards (#10))
=======
Repos may require repo-specific secrets beyond this standard set.
>>>>>>> 177e3d7 (docs: update standards with Dependabot auto-merge learnings (#187))

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
<<<<<<< HEAD
<<<<<<< HEAD
| `in-progress` | `#fbca04` (yellow) | An agent is actively working this issue |

---

## CODEOWNERS Standard

All repositories MUST have a `CODEOWNERS` file at `.github/CODEOWNERS`
(or `CODEOWNERS` at the repo root for repos with no `.github/` directory).

<<<<<<< HEAD
<<<<<<< HEAD
The full policy lives in [`codeowners-standard.md`](codeowners-standard.md).
Summary:

- The default owner line MUST be `* @petry-projects/org-leads`
- Direct listings of users or bot accounts (e.g.,
  `@petry-projects-pr-review-agent`, `@dependabot-automerge-petry`) are
  **forbidden** — manage membership through the team instead
- GitHub Apps cannot be code owners (platform limitation); use machine-user
  accounts added to the team
=======
### Required Bot Accounts

Every CODEOWNERS file MUST include these two bot accounts alongside `@don-petry`
so that automated PR approvals satisfy the `require_code_owner_review` setting
in the `pr-quality` ruleset:

| Account | App | Role |
|---------|-----|------|
| `@petry-projects-pr-review-agent` | `petry-projects-pr-review-agent` | General org PR review bot |
| `@dependabot-automerge-petry` | `dependabot-automerge-petry` | Dependabot auto-merge approver |

The `pr-quality` ruleset requires **1 code owner approval**. With all three
accounts on every pattern, an approval from `@don-petry`, `@petry-projects-pr-review-agent`,
or `@dependabot-automerge-petry` satisfies the requirement — provided the approver
is not also the author of the last push to that branch (`require_last_push_approval`
prevents self-approval after one's own push). For Dependabot PRs this is never an
issue: Dependabot pushes the branch and a separate bot approves it.
>>>>>>> b25bf5c (chore: add bot accounts to CODEOWNERS + define org standard)
=======
The full policy lives in [`codeowners-standard.md`](codeowners-standard.md).
Summary:

- The default owner line MUST be `* @petry-projects/org-leads`
- Direct listings of users or bot accounts (e.g.,
  `@petry-projects-pr-review-agent`, `@dependabot-automerge-petry`) are
  **forbidden** — manage membership through the team instead
- GitHub Apps cannot be code owners (platform limitation); use machine-user
  accounts added to the team
>>>>>>> bc338c0 (chore: finalize CODEOWNERS standard as Required + add enforcement (#193))

### Standard Template

```gitignore
# CODEOWNERS
<<<<<<< HEAD
<<<<<<< HEAD
# Standard: https://github.com/petry-projects/.github/blob/main/standards/codeowners-standard.md

* @petry-projects/org-leads
```

Repos with finer-grained path ownership MUST include `@petry-projects/org-leads`
on every owner line so the team can always satisfy `require_code_owner_review`.
=======
>>>>>>> ed24e34 (docs: add GitHub repository settings standards (#10))
=======
| `in-progress` | `#fbca04` (yellow) | An agent is actively working this issue |
>>>>>>> 6ce0e96 (feat: prevent duplicate agent PRs via in-progress labels and umbrella issues (#76))
=======
# Each line is a pattern followed by one or more owners.
# Owners are matched in order, last matching pattern wins.
# Standard: https://github.com/petry-projects/.github/blob/main/standards/github-settings.md#codeowners-standard
=======
# Standard: https://github.com/petry-projects/.github/blob/main/standards/codeowners-standard.md
>>>>>>> bc338c0 (chore: finalize CODEOWNERS standard as Required + add enforcement (#193))

* @petry-projects/org-leads
```

<<<<<<< HEAD
Repos with finer-grained path ownership (e.g., `/apps/api/`, `/infra/`) MUST
add the two bot accounts to every path-specific line, not just the default `*`.
>>>>>>> b25bf5c (chore: add bot accounts to CODEOWNERS + define org standard)
=======
Repos with finer-grained path ownership MUST include `@petry-projects/org-leads`
on every owner line so the team can always satisfy `require_code_owner_review`.
>>>>>>> bc338c0 (chore: finalize CODEOWNERS standard as Required + add enforcement (#193))

---

## Applying to a New Repository

When creating a new repository in `petry-projects`:

1. **Create the repo** with standard settings (public, `main` branch, wiki disabled, discussions enabled)
<<<<<<< HEAD
<<<<<<< HEAD
<<<<<<< HEAD
=======
>>>>>>> 12858a4 (docs: require auto-merge in ruleset standards (#194))
2. **Create the `pr-quality` ruleset** matching the standard configuration above, including:
   - Bypass actors with `bypass_mode: always` for `dependabot-automerge-petry` and `OrganizationAdmin`
   - **Allow auto-merge enabled** — in the ruleset's "Merge settings", check the "Allow auto-merge" option.
     Required for seamless PR automation and CI-dependent merges
3. **Create the `code-quality` ruleset** with required checks for the repo's stack — verify check names against actual workflow runs before requiring them
4. **Add a `CODEOWNERS` file** using the [CODEOWNERS Standard](#codeowners-standard) template, extended with any repo-specific path patterns
=======
2. **Create the `pr-quality` ruleset** matching the standard configuration above
3. **Create the `code-quality` ruleset** with required checks for the repo's stack
<<<<<<< HEAD
4. **Add a `CODEOWNERS` file** defining ownership for the repo's key paths
>>>>>>> ed24e34 (docs: add GitHub repository settings standards (#10))
=======
=======
2. **Create the `pr-quality` ruleset** matching the standard configuration above, including bypass actors with `bypass_mode: always` for `dependabot-automerge-petry`
3. **Create the `code-quality` ruleset** with required checks for the repo's stack — verify check names against actual workflow runs before requiring them
>>>>>>> 177e3d7 (docs: update standards with Dependabot auto-merge learnings (#187))
4. **Add a `CODEOWNERS` file** using the [CODEOWNERS Standard](#codeowners-standard) template, extended with any repo-specific path patterns
>>>>>>> b25bf5c (chore: add bot accounts to CODEOWNERS + define org standard)
5. **Add Dependabot configuration** — copy the appropriate template from
   [`standards/dependabot/`](dependabot/) and add to `.github/dependabot.yml`
6. **Add CI workflows** — see [CI Standards](ci-standards.md) for required workflows
7. **Create standard labels** — all labels from the [Standard Set](#labels--standard-set) above, plus any project-specific labels
<<<<<<< HEAD
<<<<<<< HEAD
8. **Enable auto-delete head branches** in repo settings
=======
8. **Enable auto-delete head branches** and **auto-merge** in repo settings
>>>>>>> ed24e34 (docs: add GitHub repository settings standards (#10))
=======
8. **Enable auto-delete head branches** in repo settings
>>>>>>> 12858a4 (docs: require auto-merge in ruleset standards (#194))
9. **Connect integrations** — ensure CodeRabbit and SonarCloud (if applicable) are enabled

> **Note:** All standard CI secrets are configured at the org level and inherited
> automatically — see [Organization-Level Secrets](#organization-level-secrets-for-standard-ci).
> No per-repo secret setup is needed for standard CI workflows.

---

## Current Compliance Status

<<<<<<< HEAD
<<<<<<< HEAD
**Repository settings:** All 7 repos are fully compliant as of 2026-05-13
(check-suite auto-trigger preferences re-applied for `.github` via API — issue #274;
last full remediation via `scripts/apply-repo-settings.sh --all` on 2026-04-05).

**Ruleset status (as of 2026-05-04):**

| Repository | `pr-quality` | `code-quality` | Notes |
|------------|:---:|:---:|-------|
| **.github** | ✅ | — | `pr-quality` added; `code-quality` not yet configured |
| **bmad-bgreat-suite** | ✅ | ✅ | Both rulesets present; CodeQL check fixed (`CodeQL` not `Analyze (actions)`) |
| **ContentTwin** | ✅ | ✅ | `dependabot-automerge-petry` bypass actor added; CodeQL check fixed |
| **broodly** | ✅ | — | `code-quality` not yet configured |
| **TalkTerm** | ✅ | ✅ | Both rulesets present; stale CI check names removed |
| **markets** | ✅ | — | `code-quality` not yet configured |
| **google-app-scripts** | ✅ | — | Migrated from `protect-branches` to `pr-quality`; legacy CodeQL check removed |
=======
Settings deviations from the standard documented above:
=======
**Repository settings:** All 7 repos are fully compliant as of 2026-04-05
(remediated via `scripts/apply-repo-settings.sh --all`).
>>>>>>> db1f90d (docs: update compliance status and add bash 4+ requirement (#73))

**Ruleset status (as of 2026-05-04):**

<<<<<<< HEAD
> **Migration note:** All repos currently use classic branch protection. These
> should be migrated to rulesets per the standard above. Classic rules should
> be removed after rulesets are verified.
>>>>>>> ed24e34 (docs: add GitHub repository settings standards (#10))
=======
| Repository | `pr-quality` | `code-quality` | Notes |
|------------|:---:|:---:|-------|
<<<<<<< HEAD
| **.github** | — | — | No rulesets yet |
| **bmad-bgreat-suite** | — | — | No rulesets yet |
| **ContentTwin** | ✅ | — | |
| **broodly** | ✅ | — | |
| **TalkTerm** | ✅ | — | |
| **markets** | ✅ | — | |
| **google-app-scripts** | — | — | Has non-standard `protect-branches` ruleset — migrate to `pr-quality` |

> **Next steps:** Run `scripts/apply-rulesets.sh --all` to create both `pr-quality`
> and `code-quality` rulesets across all repos.
> Migrate `google-app-scripts` from its legacy `protect-branches` ruleset.
>>>>>>> db1f90d (docs: update compliance status and add bash 4+ requirement (#73))
=======
| **.github** | ✅ | — | `pr-quality` added; `code-quality` not yet configured |
| **bmad-bgreat-suite** | ✅ | ✅ | Both rulesets present; CodeQL check fixed (`CodeQL` not `Analyze (actions)`) |
| **ContentTwin** | ✅ | ✅ | `dependabot-automerge-petry` bypass actor added; CodeQL check fixed |
| **broodly** | ✅ | — | `code-quality` not yet configured |
| **TalkTerm** | ✅ | ✅ | Both rulesets present; stale CI check names removed |
| **markets** | ✅ | — | `code-quality` not yet configured |
| **google-app-scripts** | ✅ | — | Migrated from `protect-branches` to `pr-quality`; legacy CodeQL check removed |
>>>>>>> 177e3d7 (docs: update standards with Dependabot auto-merge learnings (#187))

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
