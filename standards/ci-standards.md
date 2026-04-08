# CI/CD Standards

Standard CI/CD configurations for all repositories in the **petry-projects** organization.
This document defines the required workflows, quality gates, and patterns that every
repository must implement.

---

## Using Templates from `standards/workflows/`

> **Rule:** When fixing a compliance finding by adding a workflow file, **copy
> the template from [`standards/workflows/`](workflows/) verbatim.** Do not
> generate the file from scratch, even if the change seems trivial. The
> templates are the source of truth — anything generated from scratch is, by
> definition, drift.

### Centralization tiers

Every standard workflow falls into one of three tiers. Knowing the tier tells
you how much of the file you may edit when adopting it in a new repo, and
where to send a fix when behavior needs to change.

| Tier | Examples | What lives in `standards/workflows/` | Where logic lives | Edits allowed in adopting repo |
|---|---|---|---|---|
| **1. Stub** | `claude.yml`, `dependency-audit.yml`, `dependabot-automerge.yml`, `dependabot-rebase.yml`, `agent-shield.yml`, `feature-ideation.yml` | A thin caller stub that delegates via `uses: petry-projects/.github/.github/workflows/<name>-reusable.yml@v1` | The matching `*-reusable.yml` in this repo (single source of truth) | **None** in normal use. May tune `with:` inputs where the reusable exposes them (e.g. `agent-shield` accepts `min-severity`, `required-files`; `feature-ideation` requires `project_context`). To change behavior, open a PR against the reusable in this repo — the change propagates everywhere on next run. |
| **2. Per-repo template** | `ci.yml`, `codeql.yml`, `sonarcloud.yml` | _(no template — see the patterns documented below)_ | In each repo, because the workflow is tech-stack-specific (language matrix, build tool, test framework) | **Limited.** Each adopting repo carries its own copy. Stay within the patterns in this document; do not change action SHAs, permission scopes, trigger events, or job names without raising a standards PR first. |
| **3. Free per-repo** | `release.yml`, project-specific automation | _(out of scope for this standard)_ | Per-repo | Free, but must still comply with the [Action Pinning Policy](#action-pinning-policy) and the [Required Workflows](#required-workflows) constraints. |

Tier 1 stubs all carry an identical `SOURCE OF TRUTH` header block telling
agents what they may and may not edit. If you're considering modifying a
file with that header, **stop and read the header first** — if the change
isn't allowed by the contract, the right move is a PR against the central
reusable, not a local edit.

> **Why pin to `@v1`?** Stubs reference reusables by tag, not `@main`, so a
> bad commit on the central repo's `main` branch cannot break every
> downstream repo simultaneously. The `v1` tag is bumped deliberately when
> a backward-compatible release is ready; breaking changes will publish a
> `v2` tag that downstream repos opt into explicitly.

### Available templates

| Template | Tier | Purpose |
|----------|------|---------|
| [`agent-shield.yml`](workflows/agent-shield.yml) | 1 | Deep agent-config security scan via `ecc-agentshield` |
| [`claude.yml`](workflows/claude.yml) | 1 | Thin caller delegating to the org-level reusable Claude Code workflow |
| [`dependabot-automerge.yml`](workflows/dependabot-automerge.yml) | 1 | Auto-approve and squash-merge eligible Dependabot PRs |
| [`dependabot-rebase.yml`](workflows/dependabot-rebase.yml) | 1 | Rebase Dependabot PRs on demand |
| [`dependency-audit.yml`](workflows/dependency-audit.yml) | 1 | Multi-ecosystem audit (npm, pnpm, gomod, cargo, pip) |
| [`feature-ideation.yml`](workflows/feature-ideation.yml) | 1 | BMAD Method ideation pipeline (BMAD-enabled repos only) |

**Adapt only when the template genuinely requires repo-specific content** (e.g., a
project name in a comment, a different cron schedule for a known reason). Anything
beyond surface adaptation indicates either a missing template or a missing standard
— file an issue against `petry-projects/.github` rather than diverging silently.

**Fetching a template programmatically** (e.g., from a Claude Code automation run):

```bash
gh api repos/petry-projects/.github/contents/standards/workflows/<file>.yml \
  --jq '.content' | base64 -d > .github/workflows/<file>.yml
```

---

## Required Workflows

Every repository MUST have these 7 workflows. Reusable templates for Dependabot
and AgentShield workflows are in [`standards/workflows/`](workflows/). The CI,
CodeQL, SonarCloud, and Claude Code workflows are documented as patterns
below — copy and adapt the examples to each repo's tech stack.

In addition, BMAD Method-enabled repositories MUST also include the conditional
[Feature Ideation workflow](#8-feature-ideation-feature-ideationyml--bmad-method-repos)
documented below — see [`standards/workflows/feature-ideation.yml`](workflows/feature-ideation.yml)
for the template.

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
A copy-paste ready template is available at [`standards/workflows/claude.yml`](workflows/claude.yml).

> **Both jobs require a checkout step.** The `claude` job (PR reviews) and the
> `claude-issue` job (issue automation) each need `actions/checkout` **before**
> the `claude-code-action` step. Without it, `claude-code-action` cannot read
> `CLAUDE.md` or `AGENTS.md` and will error on every trigger. The weekly
> compliance audit (`check_claude_workflow_checkout`) detects repos missing this
> step and creates a labeled issue to drive remediation.

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
    concurrency:
      group: claude-issue-${{ github.event.issue.number }}
      cancel-in-progress: true
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
            --allowedTools "Bash(gh pr create:*),Bash(gh pr view:*),Bash(gh pr comment:*),Bash(gh issue comment:*),Bash(gh run view:*),Bash(gh run watch:*),Edit,Write"
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

**Condition:** Repository has BMAD Method installed (presence of `_bmad/`,
`_bmad-output/`, or equivalent BMAD planning artifacts).

Scheduled weekly workflow that runs the BMAD Analyst (Mary) on **Claude Opus 4.6**
through a 5-phase multi-skill ideation pipeline, producing evidence-grounded
feature proposals as GitHub Discussions in the **Ideas** category. Each proposal
is a separate Discussion, updated by subsequent runs as the market and project
evolve.

**The pipeline (the reason this workflow exists):**

| Phase | Skill | Purpose |
|------:|-------|---------|
| 1 | Load Context | Read signals JSON, planning artifacts, README, codebase extension points |
| 2 | **Market Research** | Iterative evidence gathering — competitor moves, emerging capabilities, user-need signals. Loops until evidence base feels solid. |
| 3 | **Brainstorming** | Divergent ideation — 8-15 raw ideas, builds on Phase 2 evidence. Loops back to research if gaps appear. |
| 4 | **Party Mode** | Collaborative refinement — amplify, connect synergies, ground in feasibility, score on Feasibility/Impact/Urgency. Top 5 advance. |
| 5 | **Adversarial** | 5-question stress test ("So what?", "Who else?", "At what cost?", "What breaks?", "Prove it."). Only survivors are proposed. |
| 6-7 | Publish | Resolve Discussion category, then create new Discussions or comment on existing ones with deltas. |

The adversarial pass is the load-bearing part: ideas that survive it are
**robust and defensible**, with a documented rebuttal to the strongest objection.

| Setting | Value |
|---------|-------|
| **Model** | `claude-opus-4-6` (set via `ANTHROPIC_MODEL` env var on the step) |
| **Schedule** | Weekly (template uses Friday 07:00 UTC) |
| **Output** | GitHub Discussions in the Ideas category, one per proposal |
| **Inputs** | `focus_area` (optional), `research_depth` (quick/standard/deep) |
| **Permissions** | `contents: read`, `discussions: write`, `id-token: write` |
| **Required secrets** | `CLAUDE_CODE_OAUTH_TOKEN` (org-level) |
| **Typical cost** | ~$2-3 per run on Opus 4.6, standard depth, 25-40 turns |

**Prerequisite:** Discussions must be enabled with an "Ideas" category
(see [Discussions Configuration](github-settings.md#discussions-configuration)).

#### Architecture: reusable workflow + thin caller stub

To avoid duplicating ~600 lines of prompt logic across every BMAD repo —
and to let us tune the multi-skill pipeline in one place — the workflow is
split into two parts:

1. **Reusable workflow** (single source of truth, hosted in this repo):
   [`.github/workflows/feature-ideation-reusable.yml`](../.github/workflows/feature-ideation-reusable.yml).
   Contains both jobs (signal collection + analyst), the full prompt with
   the 5-phase pipeline, and the four critical gotchas (model selection,
   token override, etc.) hard-coded so they cannot regress.

2. **Caller stub** (copied into each adopting repo, ~60 lines):
   [`standards/workflows/feature-ideation.yml`](workflows/feature-ideation.yml).
   Defines the schedule, the `workflow_dispatch` inputs, and calls the
   reusable workflow with a single required parameter: `project_context`.

When we tune the prompt, the model, or the gotchas, we change one file in
this repo and every adopter picks up the change on their next scheduled run.

#### Adopting in a new repo

1. Copy [`standards/workflows/feature-ideation.yml`](workflows/feature-ideation.yml)
   to `.github/workflows/feature-ideation.yml` in the target repo.
2. Replace the `project_context` value with a 3-5 sentence description of
   what the project is, who it serves, and the competitive landscape Mary
   should research. This is the **only** required edit.
3. (Optional) Adjust the cron schedule, focus area choices, or pin to a
   tag instead of `@main` if you want change isolation.
4. Ensure GitHub Discussions is enabled with an "Ideas" category — see
   [Discussions Configuration](github-settings.md#discussions-configuration).
5. Confirm the org-level secret `CLAUDE_CODE_OAUTH_TOKEN` is accessible.

#### Critical gotchas (baked into the reusable workflow)

These were discovered during the TalkTerm pilot. They live in the reusable
workflow with inline warning comments — **do not remove them without
understanding why they exist:**

1. **`github_token: ${{ secrets.GITHUB_TOKEN }}` is passed explicitly.**
   The `claude-code-action` auto-generates its own GitHub App installation
   token (`claude[bot]`), which lacks the `discussions: write` scope.
   Without an explicit `github_token` input, every `createDiscussion` and
   `addDiscussionComment` mutation fails silently with `FORBIDDEN: Resource
   not accessible by integration` — the run reports success and produces
   no Discussions. Passing the workflow's `GITHUB_TOKEN` makes the job-level
   `permissions: discussions: write` grant apply.

2. **`ANTHROPIC_MODEL: claude-opus-4-6` is set as a step env var.**
   The action does not expose model selection as an input — it reads the
   `ANTHROPIC_MODEL` environment variable. Opus is required for the depth
   the multi-skill pipeline expects; Sonnet runs cheaper but produces
   noticeably shallower adversarial passes. The reusable workflow exposes
   this as the optional `model` input for callers that need an override.

3. **`show_full_output: true` is NOT enabled.**
   It echoes raw tool results to public action logs, which can leak secrets.
   The reusable workflow intentionally omits it.

4. **The Phase 2-5 sequence is structural, not cosmetic.**
   Each phase explicitly switches the agent's mindset ("skill"), which is
   what produces *defensible* ideas instead of plausible ones. Keep this
   structure when tuning the prompt.

#### Reusable workflow inputs

| Input | Required | Default | Notes |
|-------|----------|---------|-------|
| `project_context` | yes | — | 3-5 sentence project description; the only required input |
| `focus_area` | no | `''` | Optional research focus, typically wired to `workflow_dispatch` input |
| `research_depth` | no | `'standard'` | `quick` / `standard` / `deep` |
| `model` | no | `'claude-opus-4-6'` | Override only for cost experiments — see gotcha #2 |
| `timeout_minutes` | no | `60` | Analyst job timeout (signal collection has its own short timeout) |

| Secret | Required | Notes |
|--------|----------|-------|
| `CLAUDE_CODE_OAUTH_TOKEN` | yes | Org-level secret, must be passed explicitly by the caller |

#### Reference implementation

[`petry-projects/TalkTerm`](https://github.com/petry-projects/TalkTerm/blob/main/.github/workflows/feature-ideation.yml)
is the pilot adopter. The TalkTerm workflow is the standard caller stub
with `project_context` set to a TalkTerm-specific paragraph — no other
customisation.

---

## Workflow Patterns by Tech Stack

### TypeScript / Node.js (npm)

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: actions/setup-node@v4
    with:
      node-version: '24'       # or 'lts/*'
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
      node-version: 24
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

### Looking Up the Correct SHA

> **Never guess or fabricate a SHA.** A SHA that doesn't exist in the upstream
> repo will fail at runtime — and worse, may "pass CI" if the job that uses it
> is conditionally skipped, leaving a latent failure waiting to bite the next
> developer.

Use the GitHub API to resolve a tag or branch to its current commit SHA:

```bash
# For a tag (e.g., v6.0.2)
gh api repos/actions/checkout/git/refs/tags/v6.0.2 --jq '.object.sha'

# For a branch (e.g., stable)
gh api repos/dtolnay/rust-toolchain/branches/stable --jq '.commit.sha'

# Verify a SHA exists in the upstream repo before pinning
gh api repos/actions/checkout/commits/de0fac2e4500dabe0009e67214ff5f5447ce83dd --jq '.sha'
```

**If the lookup fails or the network is unavailable, do not pin.** Leave the
action with its tag reference and document the blocker in the PR body so a
human can complete the fix. A correct unpinned reference is better than an
incorrect pinned one.

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

> **Note on admin operations from Claude Code:** GitHub Actions does **not**
> expose an `administration` permission scope. The valid set is documented at
> [docs.github.com](https://docs.github.com/en/actions/using-jobs/assigning-permissions-to-jobs).
> Admin-level operations the `claude-issue` job needs — creating repository
> rulesets, enabling Discussions, modifying repo settings — must be performed
> with a token that already carries the right scope. The reusable workflow
> passes `GH_PAT_WORKFLOWS` to `claude-code-action` for exactly this reason:
> as long as that org-level secret is a classic PAT with `repo` scope (which
> includes admin capability for the authenticated user's repos) or a
> fine-grained PAT with `Administration: Read and write`, admin calls
> succeed. Granting a non-existent workflow permission has no effect and
> will fail `actionlint`.

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
