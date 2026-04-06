# CI/CD Standards

Standard CI/CD configurations for all repositories in the **petry-projects** organization.
This document defines the required workflows, quality gates, and patterns that every
repository must implement.

---

## Required Workflows

Every repository MUST have these 7 workflows. Reusable templates for Dependabot
and AgentShield workflows are in [`standards/workflows/`](workflows/). The CI,
CodeQL, SonarCloud, and Claude Code workflows are documented as patterns
below — copy and adapt the examples to each repo's tech stack.

### 1. CI Pipeline (`ci.yml`)

The primary build-and-test workflow. Structure varies by tech stack but must include:

| Stage | Purpose | Required |
|-------|---------|----------|
| **Lint** | Static analysis / style enforcement | Yes |
| **Format check** | Formatting verification | Yes |
| **Type check** | Type safety (where applicable) | Yes |
| **Unit tests** | Fast, deterministic tests | Yes |
| **Coverage** | Code coverage reporting | Yes |
| **Integration tests** | Backend/API integration | If applicable |
| **E2E tests** | End-to-end functional tests | If applicable |
| **Build / Docker build** | Verify the artifact builds | If applicable |

**Standard triggers:**

```yaml
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
```

**Standard configuration patterns:**

```yaml
permissions: {}   # Reset top-level; set per-job (see Permissions Policy below)

concurrency:
  group: ci-${{ github.ref }}
  cancel-in-progress: true
```

### 2. CodeQL Analysis (`codeql.yml`)

Static Application Security Testing (SAST) via GitHub's CodeQL.

**Standard configuration:**

```yaml
on:
  push:
    branches: [main]
  pull_request:
    branches: [main]
  schedule:
    - cron: '0 17 * * 5'    # Weekly scan (Friday 12:00 PM EST / 17:00 UTC)
```

**Language configuration rule:** All ecosystems present in the repository MUST
be configured as CodeQL languages. If a repo contains `package.json`, add
`javascript-typescript`. If it contains `go.mod`, add `go`. If it contains
`.github/workflows/*.yml`, add `actions`. Multi-language repos configure
multiple languages via a matrix strategy.

### 3. SonarCloud Analysis (`sonarcloud.yml`)

Code quality, maintainability, security hotspots, and coverage tracking.

**Standard configuration:**

```yaml
name: SonarCloud Analysis

permissions: {}

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  sonarcloud:
    name: SonarCloud
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: read
    env:
      SONAR_TOKEN: ${{ secrets.SONAR_TOKEN }}
    steps:
      - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
        with:
          fetch-depth: 0
      - name: SonarCloud Scan
        if: ${{ env.SONAR_TOKEN != '' }}
        uses: SonarSource/sonarqube-scan-action@a31c9398be7ace6bbfaf30c0bd5d415f843d45e9 # v7.0.0
```

**Required secrets:** `SONAR_TOKEN`

Each repo needs a `sonar-project.properties` file at root with project key and org.

### 4. Claude Code (`claude.yml`)

AI-assisted code review on PRs and issue automation via Claude Code Action.
The workflow has two jobs:

- **`claude`** (interactive mode) — reviews PRs and responds to `@claude`
  mentions in comments. No `prompt` input; runs in interactive mode.
- **`claude-issue`** (automation mode) — triggered when the `claude` label is
  applied to an issue. Uses a `prompt` to drive the full lifecycle:
  implement the fix, create a PR, self-review, resolve review comments,
  monitor CI, and tag the maintainer when ready for human review.

**Billing:** This workflow uses Anthropic credits via `CLAUDE_CODE_OAUTH_TOKEN`,
not GitHub Copilot premium requests. This is distinct from the "Assign to Agent"
UI feature which consumes Copilot premium requests.

**Standard configuration:**

```yaml
name: Claude Code

on:
  pull_request:
    branches: [main]
    types: [opened, reopened, synchronize]
  issue_comment:
    types: [created]
  pull_request_review_comment:
    types: [created]
  issues:
    types: [labeled]

permissions: {}

jobs:
  # Interactive mode: PR reviews and @claude mentions
  claude:
    if: >-
      (github.event_name == 'pull_request' &&
        github.event.pull_request.head.repo.full_name == github.repository) ||
      (github.event_name == 'issue_comment' && github.event.issue.pull_request &&
        contains(github.event.comment.body, '@claude') &&
        contains(fromJson('["OWNER","MEMBER","COLLABORATOR"]'), github.event.comment.author_association)) ||
      (github.event_name == 'pull_request_review_comment' &&
        contains(github.event.comment.body, '@claude') &&
        contains(fromJson('["OWNER","MEMBER","COLLABORATOR"]'), github.event.comment.author_association))
    runs-on: ubuntu-latest
    timeout-minutes: 60
    permissions:
      contents: write
      id-token: write
      pull-requests: write
      issues: write
      actions: read
      checks: read
    steps:
      - name: Checkout repository
        uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
        with:
          fetch-depth: 1
      - name: Run Claude Code
        if: github.event_name != 'pull_request' || github.event.pull_request.user.login != 'dependabot[bot]'
        uses: anthropics/claude-code-action@6e2bd52842c65e914eba5c8badd17560bd26b5de # v1.0.89
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          additional_permissions: |
            actions: read
            checks: read

  # Automation mode: issue-triggered work — implement, open PR, review, and notify
  claude-issue:
    if: >-
      github.event_name == 'issues' && github.event.action == 'labeled' &&
        github.event.label.name == 'claude'
    runs-on: ubuntu-latest
    timeout-minutes: 60
    permissions:
      contents: write
      id-token: write
      pull-requests: write
      issues: write
      actions: read
      checks: read
    steps:
      - name: Checkout repository
        uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
        with:
          fetch-depth: 1
      - name: Run Claude Code
        uses: anthropics/claude-code-action@6e2bd52842c65e914eba5c8badd17560bd26b5de # v1.0.89
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
          label_trigger: "claude"
          track_progress: "true"
          additional_permissions: |
            actions: read
            checks: read
          claude_args: |
            --allowedTools "Bash(gh pr create:*),Bash(gh pr view:*),Bash(gh run view:*),Bash(gh run watch:*),Bash(cat:*),Edit,Write"
          prompt: |
            Implement a fix for issue #${{ github.event.issue.number }}.

            After implementing:
            1. Create a pull request with a clear title and description.
               Include "Closes #${{ github.event.issue.number }}" in the PR body.
            2. Self-review your own PR — look for bugs, style issues,
               missed edge cases, and test gaps. If you find problems, push fixes.
            3. Review all comments and review threads on the PR. For each one:
               - If you can address the feedback, make the fix, push, and
                 mark the conversation as resolved.
               - If the comment requires human judgment, leave a reply
                 explaining what you need.
            4. Check CI status. If CI fails, read the logs, fix the issues,
               and push again. Repeat until CI passes.
            5. When CI is green, all actionable review comments are resolved,
               and the PR is ready, read the CODEOWNERS file and leave a
               comment tagging the relevant code owners to review and merge.
```

**Required secrets:** `CLAUDE_CODE_OAUTH_TOKEN`

**Required labels:** The `claude` label (color: `7c3aed`) must exist on every
repository. The weekly compliance audit ensures this label is present. It can
also be applied manually to any issue to trigger Claude.

**How Claude follows org standards:** `claude-code-action` automatically reads
`CLAUDE.md` from the repository root. The org-level `.github/CLAUDE.md` is
inherited by repos without their own. Each repo's `CLAUDE.md` references
`AGENTS.md` for cross-cutting development standards (TDD, SOLID, pre-commit
checks, etc.). The `claude-issue` job adds an automation `prompt` for the
issue-to-PR lifecycle, but Claude still reads `CLAUDE.md` and `AGENTS.md`
for project-specific context.

**Permissions note:** Both jobs use the same permission set. `contents: write`
is required for issue-triggered work where Claude creates branches and pushes
commits. `actions: read` and `checks: read` enable Claude to monitor CI status
via the GitHub MCP tools (`get_ci_status`, `get_workflow_run_details`,
`download_job_log`).

**Dependabot behavior:** The Claude Code step in the `claude` job is skipped
for Dependabot PRs (the `if` condition on the step). The job still runs and
reports SUCCESS to satisfy required status checks. See
[AGENTS.md](../AGENTS.md#claude-code-workflow-on-dependabot-prs).

**Issue trigger security:** The `issues: [labeled]` event fires when any user
with triage or write access applies a label. The label name check in the `if:`
condition ensures only the `claude` label triggers the workflow — other labels
are ignored. Apply the `claude` label manually to any issue to trigger Claude.

**Maintainer notification:** The `claude-issue` prompt reads `CODEOWNERS` at
runtime to determine who to tag. No per-repo customization is needed as long
as `CODEOWNERS` is present (checked by the compliance audit).

### 5. Dependabot Auto-Merge (`dependabot-automerge.yml`)

Automatically approves and squash-merges eligible Dependabot PRs.
See [`workflows/dependabot-automerge.yml`](workflows/dependabot-automerge.yml)
and the [Dependabot Policy](dependabot-policy.md) for full details.

### 6. Dependency Audit (`dependency-audit.yml`)

Vulnerability scanning for all package ecosystems.
See [`workflows/dependency-audit.yml`](workflows/dependency-audit.yml)
and the [Dependabot Policy](dependabot-policy.md).

### 7. AgentShield (`agent-shield.yml`)

Agent configuration security validation. Checks that CLAUDE.md and
AGENTS.md exist and follow standards, scans for secrets in agent config
files, validates SKILL.md frontmatter, and detects permission bypasses.
See [`workflows/agent-shield.yml`](workflows/agent-shield.yml) and the
[Agent Configuration Standards](agent-standards.md) for full details.

---

## Conditional Workflows

These workflows are required only when a specific ecosystem is detected.

### 8. Feature Ideation (`feature-ideation.yml`) — BMAD Method repos

**Condition:** Repository contains a `_bmad/` directory (BMAD Method installed).

Scheduled weekly workflow that uses Claude Code Action as the BMAD Analyst
(Mary) to research market trends, analyze project signals, and create per-idea
Discussion threads in the **Ideas** category. Each proposal is a separate
Discussion, updated by subsequent runs as the market and project evolve.

| Setting | Value |
|---------|-------|
| **Schedule** | Weekly (recommended: Friday early morning) |
| **Output** | GitHub Discussions in the Ideas category |
| **Inputs** | `focus_area` (optional), `research_depth` (quick/standard/deep) |
| **Permissions** | `contents: read`, `discussions: write`, `id-token: write` |
| **Required secrets** | `CLAUDE_CODE_OAUTH_TOKEN` (org-level) |

**Prerequisite:** Discussions must be enabled with an "Ideas" category
(see [Discussions Configuration](github-settings.md#discussions-configuration)).

See the [TalkTerm implementation](https://github.com/petry-projects/TalkTerm/blob/main/.github/workflows/feature-ideation.yml)
as the reference template.

---

## Workflow Patterns by Tech Stack

### TypeScript / Node.js (npm)

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: actions/setup-node@v4
    with:
      node-version: '20'       # or 'lts/*'
      cache: npm
  - run: npm ci
  - run: npm run check         # lint + format
  - run: npm run typecheck     # tsc --noEmit
  - run: npm test              # unit tests + coverage
```

**Repos using this pattern:** google-app-scripts, ContentTwin

### TypeScript / Node.js (pnpm)

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: pnpm/action-setup@v4
  - uses: actions/setup-node@v4
    with:
      node-version: 20
      cache: pnpm
  - run: pnpm install --frozen-lockfile
  - run: pnpm run lint
  - run: pnpm run typecheck
  - run: pnpm run test
```

**Repos using this pattern:** broodly (TypeScript layer)

### Go

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: actions/setup-go@v5
    with:
      go-version: 'stable'   # Or pin to specific version (e.g., '1.24') matching go.mod
      cache-dependency-path: apps/api/go.sum
  - run: go vet ./...
  - uses: golangci/golangci-lint-action@v6
  - run: go test ./... -race -coverprofile=coverage.out
```

**Repos using this pattern:** broodly (Go API)

### TypeScript + Electron (npm)

```yaml
strategy:
  matrix:
    os: [ubuntu-latest, macos-latest, windows-latest]
steps:
  - uses: actions/checkout@v4
  - uses: actions/setup-node@v4
    with:
      node-version: 24
      cache: npm
  - run: npm ci
  - run: npm run typecheck
  - run: npm run lint
  - run: npm run format:check
  - run: npm test
  - run: npm run test:coverage
```

**Additional jobs for Electron:**

- Mutation testing (`npm run test:mutate`) — `continue-on-error: true`
- E2E tests via Playwright (`npx playwright test`) on macOS — `continue-on-error: true`

**Repos using this pattern:** TalkTerm

### Python

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: actions/setup-python@v5
    with:
      python-version: '3.x'
  # Project-specific: pip install, pytest, etc.
```

**Repos using this pattern:** TalkTerm (CodeQL only currently)

---

## Action Pinning Policy

All GitHub Actions MUST be pinned to a specific commit SHA, not a tag or branch.

```yaml
# CORRECT — pinned to SHA
- uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2

# WRONG — mutable tag
- uses: actions/checkout@v4
```

**Rationale:** SHA pinning prevents supply-chain attacks where a tag is
force-pushed to a malicious commit. The comment after the SHA documents the
version for human readability.

Dependabot keeps pinned SHAs up to date via the `github-actions` ecosystem
entry in `dependabot.yml`.

> **Note on examples in this document:** The "Workflow Patterns by Tech Stack"
> section uses tag references (e.g., `@v4`) for readability since those are
> illustrative patterns, not copy-paste templates. The "Required Workflows"
> section above uses SHA-pinned references where possible. When copying any
> example to a repository, always look up the current SHA for each action and
> pin to it with a version comment.

---

## Permissions Policy

All workflows MUST follow the principle of least privilege:

```yaml
# Multi-job workflows: reset at top, set per-job
permissions: {}

jobs:
  my-job:
    permissions:
      contents: read          # Only what this job needs
```

For single-job workflows, top-level least-privilege permissions are acceptable
(e.g., `permissions: contents: read`) since there is only one job to scope.

**Common permission sets:**

| Workflow | Permissions |
|----------|------------|
| CI (build/test) | `contents: read` |
| SonarCloud | `contents: read`, `pull-requests: read` |
| Claude Code | `contents: write`, `id-token: write`, `pull-requests: write`, `issues: write`, `actions: read`, `checks: read` |
| CodeQL | `actions: read`, `security-events: write`, `contents: read` |
| Dependabot auto-merge | `contents: read`, `pull-requests: read` (+ app token for merge) |

---

## Organization-Level Secrets for Standard CI

All secrets required by the standard CI workflows are configured at the
**organization level** and inherited by all repos automatically:

| Secret | Purpose |
|--------|---------|
| `CLAUDE_CODE_OAUTH_TOKEN` | Claude Code Action authentication |
| `SONAR_TOKEN` | SonarCloud analysis authentication |
| `APP_ID` | GitHub App ID for Dependabot auto-merge |
| `APP_PRIVATE_KEY` | GitHub App private key for Dependabot auto-merge |

New repositories inherit these secrets with no additional configuration.
Repos with infrastructure beyond standard CI (e.g., GCP deployment) may
require additional repo-specific secrets.

---

## CI Job Naming Convention

CI job names become the GitHub status check names that branch protection
references. Use consistent, descriptive names:

| Pattern | Example | Notes |
|---------|---------|-------|
| Language / tool name | `TypeScript`, `Go`, `SonarCloud` | For multi-language repos |
| `build-and-test` | `build-and-test` | For single-language repos |
| `Analyze` or `Analyze (<lang>)` | `Analyze`, `Analyze (Python)` | CodeQL jobs |
| `claude` | `claude` | Claude Code Action |

These names are referenced in branch protection required status checks.
Changing a job name requires updating the branch protection configuration.

---

## Org-Level Workflows

The [`.github` repository](https://github.com/petry-projects/.github) contains
org-level workflows that run across all repositories:

### OpenSSF Scorecard (`org-scorecard.yml`)

- **Schedule:** Weekly (Monday 9:00 UTC)
- **Purpose:** Security posture scoring for all public repos
- **Behavior:** Creates/updates GitHub Issues with findings, auto-closes resolved findings
- **Skip list:** CII-Best-Practices, Contributors, Fuzzing, Maintained, Packaging, Signed-Releases

---

## CI Auto-Fix Pattern

Some repositories implement automatic formatting fixes on PRs:

```yaml
autofix:
  needs: build-and-test
  if: >
    github.event_name == 'pull_request' &&
    github.event.pull_request.head.repo.full_name == github.repository
  runs-on: ubuntu-latest
  permissions:
    contents: write
  steps:
    - uses: actions/checkout@de0fac2e4500dabe0009e67214ff5f5447ce83dd # v6.0.2
      with:
        ref: ${{ github.event.pull_request.head.ref }}
    - run: npm run format && npm run lint -- --fix
    - name: Commit fixes
      run: |
        if ! git diff --quiet; then
          git config user.name "github-actions[bot]"
          git config user.email "github-actions[bot]@users.noreply.github.com"
          git add -A
          git commit -m "chore(ci): apply prettier/eslint auto-fixes"
          git push
        fi
```

**Repos using this pattern:** google-app-scripts

> **Note:** Auto-fix only runs on same-repo PRs (not forks) since it needs
> write access to the PR branch.

---

## Applying CI to a New Repository

1. **Determine tech stack** and select the matching workflow patterns above
2. **Create `ci.yml`** with lint, format, typecheck, and test stages
3. **Add `codeql.yml`** with the appropriate language(s)
4. **Add `sonarcloud.yml`** and configure `sonar-project.properties`
5. **Add `claude.yml`** for AI code review
6. **Add `dependabot.yml`** from the appropriate template in [`standards/dependabot/`](dependabot/)
7. **Add `dependabot-automerge.yml`** from [`standards/workflows/`](workflows/)
8. **Add `dependency-audit.yml`** from [`standards/workflows/`](workflows/)
9. **Add `agent-shield.yml`** from [`standards/workflows/`](workflows/)
10. **Configure secrets** in the repository settings
11. **Set required status checks** in branch protection (see [GitHub Settings](github-settings.md))
12. **Pin all action references** to commit SHAs

---

## Current Repository CI Status

All five check categories are **required on every repository** (see
[GitHub Settings — code-quality ruleset](github-settings.md#code-quality--required-checks-ruleset-all-repositories)).
The specific ecosystems configured in each check depend on the repo's stack.

| Repository | CI | CodeQL | SonarCloud | Claude | Coverage | Dep Auto-merge | Dep Audit | Dependabot Config |
|------------|:--:|:------:|:----------:|:------:|:--------:|:--------------:|:---------:|:-----------------:|
| **broodly** | Yes | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| **markets** | — | Yes | Yes | Yes | — | Yes | Yes | Partial |
| **google-app-scripts** | Yes | Yes | Yes | Yes | Yes | Yes (older) | — | Non-standard |
| **TalkTerm** | Yes | — | — | — | Yes | — | — | — |
| **ContentTwin** | — | — | Yes | — | — | — | — | — |
| **bmad-bgreat-suite** | — | — | — | — | — | — | — | — |

### Gaps to Address

Every `—` in the table above is a gap that must be remediated. Priority order:

1. **bmad-bgreat-suite:** Missing all CI workflows — needs full onboarding
2. **ContentTwin:** Missing CI, CodeQL, Claude, Coverage, Dependabot — 5 of 8 categories missing
3. **TalkTerm:** Missing CodeQL, SonarCloud, Claude, Dependabot — 4 of 8 categories missing
4. **markets:** Missing CI pipeline and Coverage; Dependabot config only covers `github-actions` (missing `npm` ecosystem)
5. **google-app-scripts:** Missing dependency audit; Dependabot npm `limit:10` (should be `0` per policy); auto-merge uses older `--admin` bypass pattern

### Version Inconsistencies

All repos MUST align to the latest version of each action:

| Action | Target Version | Repos Needing Update |
|--------|---------------|---------------------|
| **SonarCloud action** | v7.0.0 | ContentTwin, google-app-scripts (currently v6) |
| **CodeQL action** | v4 | markets (currently v3) |
| **Claude Code Action** | v1.0.89 (`6e2bd528`) | All repos should use the same pinned SHA |
