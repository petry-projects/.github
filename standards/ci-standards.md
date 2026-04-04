# CI/CD Standards

Standard CI/CD configurations for all repositories in the **petry-projects** organization.
This document defines the required workflows, quality gates, and patterns that every
repository must implement.

---

## Required Workflows

Every repository MUST have these workflows. Reusable templates for Dependabot
workflows are in [`standards/workflows/`](workflows/). The CI, CodeQL,
SonarCloud, and Claude Code workflows are documented as patterns below — copy
and adapt the examples to each repo's tech stack.

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
    - cron: '25 14 * * 3'   # Weekly scan (Wednesday)
```

**Language matrix by repo:**

| Repository | CodeQL Language(s) |
|------------|-------------------|
| **broodly** | `actions` |
| **google-app-scripts** | `javascript-typescript` |
| **TalkTerm** | `python` (pending: `javascript-typescript`) |
| **markets** | `javascript-typescript` |
| **ContentTwin** | `javascript-typescript` (pending) |

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

AI-assisted code review via Claude Code Action on PRs. Also responds to
`@claude` mentions in PR comments.

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

permissions: {}

jobs:
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
      contents: read
      id-token: write
      pull-requests: write
      issues: write
    steps:
      - name: Run Claude Code
        if: github.event_name != 'pull_request' || github.event.pull_request.user.login != 'dependabot[bot]'
        uses: anthropics/claude-code-action@bee87b3258c251f9279e5371b0cc3660f37f3f77 # v1
        with:
          claude_code_oauth_token: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

**Required secrets:** `CLAUDE_CODE_OAUTH_TOKEN`

**Dependabot behavior:** The Claude Code step is skipped for Dependabot PRs (the
`if` condition on the step). The job still runs and reports SUCCESS to satisfy
required status checks. See [AGENTS.md](../AGENTS.md#claude-code-workflow-on-dependabot-prs).

### 5. Dependabot Auto-Merge (`dependabot-automerge.yml`)

Automatically approves and squash-merges eligible Dependabot PRs.
See [`workflows/dependabot-automerge.yml`](workflows/dependabot-automerge.yml)
and the [Dependabot Policy](dependabot-policy.md) for full details.

### 6. Dependency Audit (`dependency-audit.yml`)

Vulnerability scanning for all package ecosystems.
See [`workflows/dependency-audit.yml`](workflows/dependency-audit.yml)
and the [Dependabot Policy](dependabot-policy.md).

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
| Claude Code | `contents: read`, `id-token: write`, `pull-requests: write`, `issues: write` |
| CodeQL | `actions: read`, `security-events: write`, `contents: read` |
| Dependabot auto-merge | `contents: read`, `pull-requests: read` (+ app token for merge) |

---

## Secrets Required by Repository

| Secret | Purpose | Repos |
|--------|---------|-------|
| `CLAUDE_CODE_OAUTH_TOKEN` | Claude Code Action authentication | All repos with `claude.yml` |
| `SONAR_TOKEN` | SonarCloud analysis | broodly, markets, ContentTwin, google-app-scripts |
| `APP_ID` | GitHub App for Dependabot auto-merge | All repos with `dependabot-automerge.yml` |
| `APP_PRIVATE_KEY` | GitHub App private key | All repos with `dependabot-automerge.yml` |
| `GCP_PROJECT_ID` | GCP project for container registry | broodly |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | GCP Workload Identity Federation | broodly |
| `GCP_SERVICE_ACCOUNT` | GCP service account email | broodly |

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
9. **Configure secrets** in the repository settings
10. **Set required status checks** in branch protection (see [GitHub Settings](github-settings.md))
11. **Pin all action references** to commit SHAs

---

## Current Repository CI Status

| Repository | CI | CodeQL | SonarCloud | Claude | Dep Auto-merge | Dep Audit | Dependabot Config |
|------------|:--:|:------:|:----------:|:------:|:--------------:|:---------:|:-----------------:|
| **broodly** | Yes | Yes | Yes | Yes | Yes | Yes | Yes |
| **markets** | — | Yes | Yes | Yes | Yes | Yes | Yes |
| **google-app-scripts** | Yes | Yes | Yes | Yes | Yes | — | — |
| **TalkTerm** | Yes | — | — | — | — | — | — |
| **ContentTwin** | — | — | Yes | — | — | — | — |
| **bmad-bgreat-suite** | — | — | — | — | — | — | — |

### Gaps to Address

- **TalkTerm:** Missing SonarCloud, Claude Code, Dependabot config, auto-merge, dependency audit
- **ContentTwin:** Missing CI pipeline, CodeQL, Claude Code, Dependabot config, auto-merge, dependency audit
- **bmad-bgreat-suite:** Missing all CI workflows (new repo)
- **google-app-scripts:** Missing dependency audit workflow and Dependabot config
- **markets:** Missing dedicated CI pipeline (relies on SonarCloud + Claude as checks)
