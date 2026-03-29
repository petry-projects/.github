# AGENTS.md — Petry Projects Organization Standards

This file defines cross-cutting development standards for all repositories in the **petry-projects** organization. It follows the [AGENTS.md convention](https://agents.md/) and is intended to be imported by each repository's own AGENTS.md or CLAUDE.md.

> Individual repositories extend these standards with project-specific guidance. If a repo-level rule conflicts with this file, the repo-level rule takes precedence.

---

## Project Context

- **Assume brownfield.** When exploring a repo, check for existing source code before assuming it is greenfield. Look at all directories, worktrees, and non-main branches before concluding that code does not exist.

---

## Git Workflow

### Branch Creation

- **Always base new branches off the default branch (`main`)** (not off other feature or PR branches) unless explicitly told otherwise.
- Before creating a branch, ensure your working directory is clean (commit or stash any changes), then run:

  ```bash
  git checkout main && git pull origin main
  ```

### Branch Switching

- **Before switching branches, always commit or stash current work.** Git usually prevents checkouts that would overwrite local changes, but forced operations (e.g., `git checkout -f` or `git reset --hard`) or resolving conflicts incorrectly can cause you to lose or misplace work.
- After switching, verify you are on the correct branch with `git branch --show-current` before making any changes.

---

## Development Environment

When the user asks to run or launch an app, first check the environment for required dependencies and report blockers immediately rather than attempting extensive debugging. At minimum, verify:

1. **Required runtimes** — Node.js, Go, Python, etc. as specified by `package.json`, `go.mod`, or equivalent
2. **System dependencies** — display server (for Electron/GUI apps), Homebrew, sudo availability
3. **Available ports** — check for conflicts on common dev ports (3000, 5173, 8080)
4. **Package installation** — run `npm install`, `go mod download`, etc. before attempting to build or run

If a dependency cannot be resolved, report the specific blocker and a workaround immediately — do not spend time debugging environment issues repeatedly.

---

## Test-Driven Development (TDD)

- **TDD is mandatory.** Write tests before implementing features or bug fixes. Include tests in the same PR as the implementation.
- **Achieve and maintain excellent test coverage.** Verify locally before pushing. PRs that reduce coverage below repo-defined thresholds will be rejected.
- **NEVER use `.skip()` to avoid failing tests.** If tests fail, fix them. If functionality cannot be directly tested, extract testable logic and test the extraction.
- **NEVER add coverage-ignore comments** (e.g., `/* istanbul ignore next */`, `/* c8 ignore next */`, `// v8 ignore next`) to artificially boost coverage. If code is difficult to test, improve mocking strategies or adjust thresholds instead.
- Unit tests MUST be fast, deterministic, and not access external networks.
- Integration tests are allowed but MUST be clearly marked. They may be skipped locally during rapid iteration, but CI MUST always run them (for example, in a separate job or scheduled workflow).
- Mock external services using project-provided helpers where available.

---

## Pre-Commit Quality Checks

Before every commit, agents MUST run and pass the project's full check suite. At minimum:

1. **Format** — run the project's formatter (e.g., `prettier`, `gofmt`)
2. **Lint** — run the project's linter with zero warnings/errors
3. **Type check** — if applicable (e.g., `tsc --noEmit`)
4. **Tests** — run the full test suite with coverage (during iteration, run specific tests for speed — see Agent Operation Guidance)

Pre-commit hooks may not run in agent sessions — apply formatting and checks manually.

---

## Code Style & Commits

- Follow existing code style and lint rules in each repository.
- Keep commits small and focused — include tests with behavior changes.
- Do not introduce new linting, formatting, or build tooling unless essential and approved.
- Follow the repository's established naming conventions.

---

## Coding Standards & Principles

All repositories MUST follow these software engineering principles. They apply to every language, framework, and layer in the stack. Repository-level AGENTS.md or CLAUDE.md files may specify how each principle maps to project-specific patterns — those specifics take precedence over the general guidance here.

### SOLID Principles

| Principle | Rule | What it means in practice |
|-----------|------|---------------------------|
| **Single Responsibility (SRP)** | Every module, class, or function has exactly one reason to change | Split files that mix concerns (e.g., HTTP handling + business logic + persistence). Each layer owns its own responsibility. |
| **Open/Closed (OCP)** | Extend behavior through new implementations, not by modifying existing code | Use interfaces, strategy patterns, or composition. Avoid editing stable modules to add new variants. |
| **Liskov Substitution (LSP)** | Subtypes must be substitutable for their base types without breaking callers | Ensure implementations honor the full contract of their interface — preconditions, postconditions, and invariants. |
| **Interface Segregation (ISP)** | Clients should not depend on methods they don't use | Prefer small, focused interfaces over large ones. Split fat interfaces into cohesive groups. |
| **Dependency Inversion (DIP)** | Depend on abstractions, not concretions | High-level policy code MUST NOT import low-level infrastructure directly. Inject dependencies via constructors or configuration. |

### CLEAN Code

- **Meaningful names.** Variables, functions, classes, and files must reveal intent. No abbreviations unless they are universally understood in the domain (e.g., `id`, `url`, `db`).
- **Small functions.** Each function does one thing, at one level of abstraction. If a function needs a comment to explain what it does, it should be renamed or split.
- **Minimal arguments.** Prefer fewer function parameters. If a function requires many arguments, consider grouping related parameters into a value object or configuration type.
- **No side-effect surprises.** Functions that appear to be queries must not mutate state. Clearly separate commands (state changes) from queries (reads).
- **Consistent formatting.** Formatting is enforced by the project's configured tooling (see Pre-Commit Quality Checks). Do not manually override or fight the formatter.
- **Error handling is not an afterthought.** Handle errors at the appropriate layer. Don't swallow exceptions silently. Don't return `null` when an error type is more expressive.

### DRY — Don't Repeat Yourself

- **Eliminate knowledge duplication.** Every piece of business knowledge or logic must have a single, authoritative source. If the same rule exists in two places, extract it.
- **DRY applies to knowledge, not code.** Two blocks of code that look identical but represent different domain concepts are NOT duplication — do not merge them. Two blocks that look different but encode the same business rule ARE duplication — unify them.
- **Premature abstraction is worse than duplication.** Wait until you have at least three concrete instances before extracting a shared abstraction. Two similar cases do not justify a generic helper.

### DDD — Domain-Driven Design

- **Ubiquitous language.** Use the same terminology in code, tests, specs, and conversation. If the domain calls it a "market" or "session", the code uses `Market` or `Session` — not `item` or `context`.
- **Bounded contexts.** Each major subdomain has clear boundaries. Code in one context must not directly depend on the internals of another. Communicate across contexts through well-defined interfaces or events.
- **Aggregate roots.** Enforce invariants through aggregate roots. External code accesses an aggregate's children only through the root.
- **Value objects.** Use typed value objects (branded types, newtypes, or equivalent) for identifiers, quantities, and domain-specific data. Avoid passing raw primitives (`string`, `int`) when a domain type adds safety and meaning.
- **Repository pattern.** Persistence is abstracted behind repository interfaces that the domain defines. Infrastructure implements those interfaces. Domain code never imports ORM, SQL, or storage libraries directly.

### KISS — Keep It Simple

- Choose the simplest solution that satisfies the current requirements.
- Avoid clever code. Readable, boring code is better than compact, clever code.
- Do not add layers of abstraction, configuration, or indirection until complexity demands it.

### YAGNI — You Aren't Gonna Need It

- Do not build features, abstractions, or configuration for hypothetical future requirements.
- Implement exactly what the current story or task requires — no more.
- If a future need arises, it will be specified in a future story with its own tests and acceptance criteria.

### Defensive Coding at System Boundaries

- **Validate all external input.** Data from users, APIs, files, environment variables, and message queues must be validated and sanitized at the system boundary before entering domain logic.
- **Trust internal code.** Once data has crossed a validated boundary, do not re-validate at every function call. Excessive internal checks add noise without value.
- **Fail fast.** When an invariant is violated, fail immediately with a clear error rather than propagating bad state.

### Separation of Concerns

- **Layered architecture.** Maintain clear boundaries between domain logic, application/use-case orchestration, and infrastructure (I/O, persistence, external services).
- **Direction of dependencies.** Dependencies always point inward — infrastructure depends on application, application depends on domain. Never the reverse.
- **No framework bleed.** Framework-specific types and annotations stay at the infrastructure/adapter layer. Domain and application layers must be framework-agnostic.

### Code Organization

- **Co-locate related code.** Tests live next to the code they test. Types live near the code that uses them. Avoid scattering related files across distant directories.
- **No barrel files** unless the project explicitly requires them. Re-export files (`index.ts`, `__init__.py`) add indirection and circular dependency risk.
- **Consistent file naming.** Follow the repository's documented naming convention for source files, test files, components, and modules.

---

## Pull Request Reviews

- When addressing PR review comments, **mark each resolved comment thread as Resolved** on GitHub after the fix is pushed.
- Use the GitHub GraphQL API via `gh api graphql` with the `resolveReviewThread` mutation:

  ```bash
  gh api graphql -f query='mutation { resolveReviewThread(input: {threadId: "PRRT_..."}) { thread { id isResolved } } }'
  ```

  Retrieve thread IDs first with a `reviewThreads` query on the pull request.
- Resolve all addressed threads in one pass after pushing the fix commit.

---

## Security & Secrets

- **Never commit secrets.** Use environment variables, GitHub Actions secrets, or an external secret manager.
- Do not commit `.env` files, credentials, API keys, or tokens.
- Request maintainer review for changes requiring elevated permissions or access to sensitive data.

---

## BMAD Method — Spec-Driven Development

All project repositories MUST install and use the [BMAD Method](https://github.com/bmad-code-org/BMAD-METHOD) to enforce **Spec-Driven Development (SDD)**. BMAD provides structured agents, workflows, and planning artifacts that ensure every feature is fully specified before implementation begins.

### Setup

- Install BMAD in every new repo: `npx bmad-method install`
- Keep BMAD up to date: `npx bmad-method install` (re-run periodically)

### Required Workflow

1. **Plan before you build.** Every feature, epic, or significant change MUST have planning artifacts before implementation starts. Use BMAD agents (PM, Architect, UX Designer) to produce them.
2. **Planning artifacts live in `_bmad-output/planning-artifacts/`** and include:
   - Product Brief — vision, target users, success criteria
   - PRD — functional and non-functional requirements
   - Architecture — technical decisions, component design, data model
   - UX Design Specification — user flows, wireframes, accessibility
   - Epics & Stories — implementation-ready backlog with acceptance criteria
3. **Always consult planning artifacts before implementing.** They are the source of truth for what to build and how. If artifacts are missing or outdated, update them first — do not implement against stale specs.
4. **Use BMAD stories for implementation.** Stories created via `bmad-create-story` contain all context an agent needs. Use `bmad-dev-story` to execute them.
5. **Validate readiness before sprints.** Run `bmad-check-implementation-readiness` to ensure specs are complete before starting implementation work.

### BMAD Agents Available

Use BMAD's specialized agents via their slash commands: `bmad-pm` (Product Manager), `bmad-architect` (Solution Architect), `bmad-ux-designer` (UX Designer), `bmad-dev` (Developer), `bmad-tea` (Test Architect), `bmad-qa` (QA), `bmad-sm` (Scrum Master), and others. Run `bmad-help` for guidance on which agent or workflow to use next.

---

## CI Quality Gates — Required Checks

All repositories MUST configure and enforce the following CI checks. PRs cannot be merged until all checks pass.

### Security & Code Analysis

| Check | Tool | Purpose |
|-------|------|---------|
| **Static analysis (SAST)** | [CodeQL](https://github.com/github/codeql-action) | Detect security vulnerabilities, bugs, and anti-patterns |
| **Code quality** | [SonarCloud](https://sonarcloud.io/) | Maintainability, reliability, security hotspots, duplication |

### Automated Code Review

| Check | Tool | Purpose |
|-------|------|---------|
| **AI code review** | [CodeRabbit](https://coderabbit.ai/) | Automated PR review for logic errors, best practices, and suggestions |
| **AI code review** | [GitHub Copilot](https://docs.github.com/en/copilot/using-github-copilot/code-review/using-copilot-code-review) | Copilot code review for security, performance, and correctness |

### Code Quality

| Check | Tool | Purpose |
|-------|------|---------|
| **Linting** | Project linter (ESLint, golangci-lint, etc.) | Zero warnings, zero errors |
| **Formatting** | Project formatter (Prettier, gofmt, etc.) | Consistent code style |
| **Type checking** | Language type checker (tsc, etc.) | Type safety (where applicable) |

### Testing

| Check | Tool | Purpose |
|-------|------|---------|
| **Unit & integration tests** | Project test framework (Jest, Vitest, etc.) | All tests must pass |
| **Code coverage** | Coverage reporter | Must meet repo-defined thresholds; PRs that reduce coverage are rejected |

### Enforcement

- All checks above are configured as **required status checks** on the default branch.
- **Iterate until all CI checks pass.** Before requesting review or marking a PR as ready:
  - Run all checks locally (format, lint, typecheck, tests, coverage)
  - If any check fails in CI, investigate locally, fix the issue, and re-run
  - Continue iterating until all checks pass both locally and in CI
- Never bypass CI gates or weaken thresholds to make a PR pass.
- Address CodeRabbit and Copilot review comments the same way you address human reviewer comments — fix or explicitly justify skipping with a reply.

### Branch Protection & SonarCloud

- This org uses **branch protection with SonarCloud checks** and `enforce_admins` enabled.

---

## Multi-Agent Isolation — Git Worktrees

When multiple agents work on the same repository concurrently, they MUST use **isolated workspaces** to prevent conflicts. Git worktrees are the industry-standard isolation primitive — used by Claude Code, Cursor, Windsurf, Augment Intent, and dmux. Cloud agents (OpenAI Codex, GitHub Copilot, Devin) use containers or ephemeral environments that provide equivalent isolation.

Never have two agents working in the same working directory simultaneously.

### Rules

1. **One workspace per agent.** Every agent performing code changes MUST operate in its own isolated workspace (git worktree, container, or ephemeral environment). This applies to Claude Code (`isolation: "worktree"` or `--worktree`), Cursor parallel agents, GitHub Copilot coding agent, OpenAI Codex, and any other AI agent tool.
2. **One agent per story/task.** Each workspace maps to exactly one BMAD story, feature, or bug fix. Do not assign the same story to multiple agents.
3. **No overlapping file ownership.** Two agents MUST NOT modify the same file concurrently. If stories touch shared files (e.g., a shared type definition, config, or lockfile), serialize those stories — do not run them in parallel. This is the single most important rule for multi-agent work.
4. **Branch from the default branch** — unless using a stacked PR workflow (see [Stacked PRs for Epic Development](#stacked-prs-for-epic-development)). Outside a stacked-Epic/Feature workflow, workspaces MUST branch from the repository's configured default branch (for example, `origin/main`). You MAY use `origin/HEAD` as a shortcut when it is correctly configured, but MUST NOT rely on it being present. Never branch from another agent's branch **except** when (a) Epics/Features are part of a declared stack and the child Epic/Feature branches from its parent Epic/Feature's branch, or (b) story worktrees/branches are created from the Epic/Feature integration branch as defined in the stacked-PR workflow.
5. **One PR per workspace.** Each workspace produces exactly one pull request. Do not combine unrelated changes. (In a stacked-Epic/Feature workflow, story worktrees may optionally produce short-lived PRs targeting the Epic branch for review — these are internal integration PRs, not standalone feature PRs.)
6. **3–5 parallel agents max.** Coordination overhead increases non-linearly. Limit concurrent agents to 3–5 per repository.

### Detecting File Overlap

Before launching parallel agents, verify that stories won't modify the same files:

1. Review each story's acceptance criteria and implementation scope for shared files
2. Use `git log --stat` on recent similar changes to identify likely touched files
3. If any overlap is detected or uncertain, serialize the stories — do not run them in parallel

### Worktree Naming Convention

Use descriptive worktree names that identify the scope. For tools that auto-generate branch names from your input (see table below), the name you choose flows into the branch name automatically.

| Tool | You provide | Branch created |
|------|------------|----------------|
| Claude Code (`--worktree <name>`) | `S-3.1-hive-health-card` | `worktree-S-3.1-hive-health-card` |
| Claude Code subagent (`isolation: "worktree"`) | Agent `name` field | `worktree-<name>` |
| GitHub Copilot coding agent | Task description | `copilot/<descriptive-name>` (auto) |
| Cursor parallel agents | Prompt | `feat-N-<random>` (auto) |
| Manual worktree | Full branch name | Whatever you specify |

**Name format:** `<story-or-task-id>-<short-description>`

Examples: `S-3.1-hive-health-card`, `fix-auth-token-expiry`, `S-2.4-offline-sync-banner`

### Tool-Specific Setup

**Claude Code subagents** — set `isolation: "worktree"` in the agent definition:

```yaml
---
name: S-3.1-hive-health-card
isolation: "worktree"
---
```

**Claude Code CLI sessions** — start in a named worktree:

```bash
claude --worktree S-3.1-hive-health-card
```

**GitHub Copilot coding agent** — assign a task via GitHub Issues or the Copilot panel. Copilot creates its own branch (`copilot/...`) and ephemeral environment automatically.

**OpenAI Codex** — use worktree mode in the Codex app, or assign tasks to the cloud agent which runs in isolated containers.

**Manual worktree** (for tools without built-in support):

```bash
git worktree add .worktrees/<name> -b agent/<story-id>-<description>
cd .worktrees/<name>
# run agent session here
```

### Environment & Dependencies

- Git worktrees are fresh checkouts — gitignored files (`.env`, `.env.local`) are NOT copied automatically.
- For Claude Code: add a **`.worktreeinclude`** file at the repo root listing gitignored files that should be copied into new worktrees:

  ```text
  .env
  .env.local
  ```

- After entering a worktree, **install dependencies** (`npm install`, `go mod download`, etc.) before starting work.

### Cleanup

- If the worktree has **no changes**, it is automatically removed when the agent session ends (Claude Code, Cursor).
- If the worktree has **uncommitted changes**, the agent MUST commit or discard before exiting. Do not leave dirty worktrees.
- After a PR is merged, remove the worktree and its branch:

  ```bash
  git worktree remove <worktree-path>
  git branch -d <branch-name>  # safe delete; may fail after squash/rebase merges
  # If the above fails and you've confirmed the PR is merged:
  git branch -D <branch-name>
  ```

### Repository Configuration

Add worktree directories to the project's `.gitignore`:

```gitignore
# Agent worktrees
.claude/worktrees/
.worktrees/
```

### Multi-Repo Orchestration

When working across multiple repositories, use separate agents to work on each repo in parallel. Each agent MUST:

1. **Use a separate clone or working directory per repo** — never share a working directory between repos; within each repo, use separate worktrees or isolated environments per agent/task
2. **Work only on its assigned repo** — do not modify files in other repos
3. **Report back status when done** — include PR URL, CI status, and any blockers

Do NOT share branches or state between agents operating on different repos.

### Coordination Checklist (for humans orchestrating multiple agents)

Before launching parallel agents, verify:
- [ ] Each agent has a distinct story/task assignment
- [ ] No two agents will modify the same files
- [ ] Shared dependencies (lockfiles, generated types) are up to date on the default branch before agents start
- [ ] If stories share a dependency file, run them sequentially, not in parallel
- [ ] No more than 3–5 agents are running concurrently on the same repository

---

## Stacked PRs for Epic Development

When a project has multiple Epics with **sequential dependencies** — where Epic 2 builds on the foundation laid by Epic 1, Epic 3 extends Epic 2, and so on — the standard "branch from main" model forces each Epic to wait for the previous Epic's PR to fully merge before work can begin. Stacked PRs eliminate this bottleneck by letting each Epic's branch build on the previous Epic's branch, forming a chain that merges bottom-up.

Each Epic produces a **single PR** containing all of that Epic's stories. The stack is a chain of Epic-level PRs:

```text
main ← Epic-1-PR ← Epic-2-PR ← Epic-3-PR ← Epic-4-PR
```

### How It Works

Each Epic gets one long-lived **Epic branch** (also called its integration branch). Multiple agents work stories concurrently in separate worktrees that branch from the Epic branch, then merge their completed stories back into it. The Epic branch accumulates all story work and becomes one PR in the stack.

| PR | Source branch | Target branch |
|----|---------------|---------------|
| Epic 1 PR | `epic-1/foundation` | `main` |
| Epic 2 PR | `epic-2/core-features` | `epic-1/foundation` |
| Epic 3 PR | `epic-3/integrations` | `epic-2/core-features` |
| Epic 4 PR | `epic-4/polish` | `epic-3/integrations` |

When Epic 1's PR merges into `main`, Epic 2's PR is retargeted to `main`, and so on up the stack.

### Rules for Stacked Epic PRs

1. **One PR per Epic.** Each Epic produces exactly one PR. All stories within the Epic are merged into the Epic's integration branch.
2. **Stacks are strictly linear.** No branching within a stack (no diamond or tree shapes). One parent Epic, one child Epic.
3. **Maximum stack depth: 4 Epics.** Deeper stacks become fragile and painful to rebase. If a project has more than 4 sequential Epics, look for opportunities to merge intermediate Epics before continuing.
4. **Parallel agents within an Epic.** Multiple agents CAN work on stories within the same Epic concurrently — each in its own worktree branching from the Epic branch. The standard multi-agent isolation rules apply: no two agents modify the same file. Story worktrees merge back into the Epic branch when complete.
5. **Sprints within an Epic may overlap.** If Sprint 2's stories are independent of Sprint 1's stories, agents may work on both sprints concurrently. Only serialize sprints when later stories depend on earlier ones.
6. **Independent Epic stacks CAN run in parallel.** If your project has two separate dependency chains (e.g., Epics A1→A2 and Epics B1→B2), run those stacks concurrently with separate agents. The standard multi-agent isolation rules apply — no overlapping file ownership across stacks.
7. **File ownership within a stack is cumulative.** Files touched by Epic 1 may also be touched by Epic 2 (that's the nature of sequential dependency). Ensure agents in the child Epic coordinate with the parent Epic's completed state.
8. **Bottom-up merge order is mandatory.** Always merge the bottom Epic PR first, then retarget the next Epic PR to `main`, and so on. Never merge out of order.

### Workflow — Planning the Stack

Before any agent starts, the orchestrator (human or planning agent) identifies the Epic dependency order and documents the stack plan:

```markdown
## Project Stack Plan
1. Epic 1 — Foundation: data model, core types, DB schema (base → main)
2. Epic 2 — Core Features: service layer, business logic (base → Epic 1)
3. Epic 3 — Integrations: API endpoints, external services (base → Epic 2)
4. Epic 4 — Polish: UI refinements, error handling, docs (base → Epic 3)
```

Each Epic should list its stories, and the plan should call out which files/modules each Epic owns.

### Workflow — Implementing the Stack

**Step 1: Create the Epic integration branch.** The orchestrator (or first agent) creates the Epic branch from its parent:

```bash
# Epic 1 branches from main
git checkout main && git pull origin main
git checkout -b epic-1/foundation
git push -u origin epic-1/foundation

# Open the Epic PR (initially empty or with scaffolding)
gh pr create --base main --title "Epic 1: Foundation" --body "..." --draft
```

**Step 2: Agents work stories in parallel worktrees.** Each agent creates a story worktree branching from the Epic branch:

```bash
# Agent 1 — Story S-1.1
git worktree add .worktrees/S-1.1-data-model -b epic-1/S-1.1-data-model origin/epic-1/foundation

# Agent 2 — Story S-1.2 (concurrent, no file overlap with S-1.1)
git worktree add .worktrees/S-1.2-core-types -b epic-1/S-1.2-core-types origin/epic-1/foundation

# Agent 3 — Story S-1.3 (concurrent, no file overlap)
git worktree add .worktrees/S-1.3-db-schema -b epic-1/S-1.3-db-schema origin/epic-1/foundation
```

Each agent implements its story, runs quality checks, and pushes.

**Step 3: Merge stories back into the Epic branch.** As stories complete, merge them into the Epic branch. See [Story and Sprint Organization Within an Epic](#story-and-sprint-organization-within-an-epic) for merge strategies and commands.

**Step 4: Create the next Epic branch.** Once all stories that the next Epic depends on have been merged into the previous Epic branch, create the next Epic:

```bash
# Epic 2 branches from Epic 1
git checkout epic-1/foundation && git pull origin epic-1/foundation
git checkout -b epic-2/core-features
git push -u origin epic-2/core-features
gh pr create --base epic-1/foundation --title "Epic 2: Core Features" --body "..." --draft
```

Agents then work Epic 2's stories in parallel worktrees branching from `epic-2/core-features`, following the same pattern.

**Step 5: Repeat** for each subsequent Epic in the stack.

### Workflow — Merging the Stack

1. **Merge the bottom PR** (Epic 1 → `main`) using the repo's standard merge strategy.
2. **Retarget the next PR** to `main`:

   ```bash
   gh pr edit <epic-2-PR-number> --base main
   ```

3. **Rebase the next branch** onto `main` to incorporate the merge and resolve any squash/rebase differences:

   ```bash
   # In the Epic 2 worktree
   git fetch origin main
   git rebase origin/main
   git push --force-with-lease
   ```

4. **Review and merge Epic 2** → `main`. Repeat for Epic 3, Epic 4, etc.

### Workflow — Handling Changes to a Lower Epic PR

If a reviewer requests changes to a lower Epic PR (e.g., Epic 1), the agent making fixes MUST propagate changes upward:

1. Make the fix on Epic 1's branch and push.
2. For each child branch in order, rebase onto the updated parent:

   ```bash
   # In Epic 2 worktree
   git fetch origin epic-1/foundation
   git rebase origin/epic-1/foundation
   # Resolve any conflicts
   git push --force-with-lease
   ```

3. Repeat for Epic 3 if it exists (rebasing onto Epic 2's updated branch), and so on.

If conflicts are extensive, consider collapsing the stack — merge what you can into `main` and rebuild the remaining Epics from there.

### Keeping Epic Branches in Sync with Main

If `main` advances while a stack is in progress (e.g., hotfixes or other PRs merge), periodically rebase the bottom Epic branch onto `main` and propagate upward through the stack. Do this between Sprints or at natural breakpoints — not while story agents are actively working. A long-diverged Epic branch will produce painful conflicts at merge time.

### Story and Sprint Organization Within an Epic

The Epic branch accumulates completed stories. Agents do not work directly on the Epic branch. Instead, each agent works in its own story worktree that branches from the Epic branch.

**Sprint-level organization:**

Epics are typically broken into Sprints, each containing a set of stories. Within a Sprint, all stories with no file overlap can be worked in parallel by separate agents. Across Sprints:

- **Independent Sprints** (no data/API dependency between them) — run concurrently.
- **Dependent Sprints** (Sprint 2 stories require Sprint 1 output) — run sequentially. Merge all Sprint 1 stories into the Epic branch before Sprint 2 agents branch from it.

```text
Epic 1 branch
├── Sprint 1 (parallel agents)
│   ├── Agent 1 → S-1.1 worktree
│   ├── Agent 2 → S-1.2 worktree
│   └── Agent 3 → S-1.3 worktree
│   (all merge back into Epic branch)
├── Sprint 2 (parallel agents, after Sprint 1 merges)
│   ├── Agent 1 → S-1.4 worktree
│   └── Agent 2 → S-1.5 worktree
│   (merge back into Epic branch)
└── Epic PR → targets parent Epic branch or main
```

**Story worktree naming convention** (extends the general convention in [Worktree Naming Convention](#worktree-naming-convention) with an Epic prefix):

```text
.worktrees/<epic-id>-<story-id>-<description>
```

Branch name: `<epic-id>/<story-id>-<description>`

Examples: `epic-1/S-1.1-data-model`, `epic-2/S-2.3-auth-middleware`

**Merging stories back into the Epic branch:**

Stories can be integrated via direct merge or via short-lived PRs targeting the Epic branch:

| Method | When to use |
|--------|-------------|
| **Direct merge** (`git merge`) | Small team, high trust, fast iteration |
| **Story PRs** (PR targeting Epic branch) | Larger team, want per-story review before integration |

Direct merge commands (run from the Epic branch worktree):

```bash
# Fetch and merge a completed story
git checkout epic-1/foundation
git fetch origin epic-1/S-1.1-data-model
git merge origin/epic-1/S-1.1-data-model
git push origin epic-1/foundation
```

If a story branch has fallen behind the Epic branch (e.g., other stories merged first), rebase it before merging. Run this from within the story worktree:

```bash
git fetch origin epic-1/foundation
git rebase origin/epic-1/foundation
# resolve any conflicts, push, then merge into the Epic branch
git push --force-with-lease
```

**Story worktree cleanup:** Remove story worktrees and branches immediately after they are merged into the Epic branch — do not wait for the Epic PR to merge into `main`.

Either way, the Epic-level PR in the stack is the final gate for review and CI before merging into the parent Epic or `main`.

### Combining Stacked Epics with Parallel Agents

Stacked PRs and parallel agents operate at different levels and are fully complementary:

| Level | Parallelism | Constraint |
|-------|-------------|------------|
| **Across independent Epic chains** | Full parallel — separate stacks run concurrently | No file overlap between chains |
| **Across Epics in the same stack** | Sequential — child Epic starts after parent Epic branch is stable | Child branches from parent |
| **Within an Epic (across Sprints)** | Parallel if Sprints are independent; sequential if dependent | Dependent Sprints wait for prior Sprint to merge into Epic branch |
| **Within a Sprint** | Full parallel — multiple agents, one story each | No file overlap between stories |

Example — a project with two Epic chains and six agents:

| Agent | Chain | Epic | Sprint | Story | Branch base | Status |
|-------|-------|------|--------|-------|-------------|--------|
| Agent 1 | A | Epic 1 | Sprint 1 | S-1.1 (data model) | `epic-1/foundation` | Active |
| Agent 2 | A | Epic 1 | Sprint 1 | S-1.2 (core types) | `epic-1/foundation` | Active (parallel) |
| Agent 3 | A | Epic 1 | Sprint 1 | S-1.3 (db schema) | `epic-1/foundation` | Active (parallel) |
| Agent 4 | B | Epic 3 | Sprint 1 | S-3.1 (auth) | `epic-3/auth` | Active (parallel, different chain) |
| Agent 5 | B | Epic 3 | Sprint 1 | S-3.2 (sessions) | `epic-3/auth` | Active (parallel) |
| Agent 6 | A | Epic 2 | — | — | `epic-1/foundation` | Waiting (parent Epic incomplete) |

Once Agents 1–3 merge their stories into `epic-1/foundation`, Agent 6 can begin Epic 2's stories. Meanwhile, Agents 4–5 continue independently on Chain B.

### Stack Coordination Checklist

Before starting a stacked Epic workflow, verify:
- [ ] Epics have genuine sequential dependencies (not just conceptual ordering)
- [ ] Stack depth is 4 or fewer Epics
- [ ] Stack plan is documented with Epic order, parent relationships, and Sprint breakdown
- [ ] Each Epic's file/module ownership is identified — no overlap across parallel stacks
- [ ] Within each Epic, stories are assigned to Sprints with file overlap analysis complete
- [ ] Stories within each Sprint have no file overlap (safe for parallel agents)
- [ ] Dependent Sprints are clearly marked — they wait for prior Sprint to merge into Epic branch
- [ ] Stories within each Epic are scoped and ready for implementation (BMAD artifacts complete)
- [ ] No more than 3–5 agents are running concurrently across all active Epics in the repository

### Tooling Notes

- **GitHub natively supports stacked PRs** — each PR targets a non-default base branch. The PR diff shows only the changes introduced by that Epic, not the full stack.
- **`gh` CLI** supports `--base` for targeting parent branches and `gh pr edit --base` for retargeting after merges.
- **Graphite, git-town, and spr** are dedicated stacked PR tools that automate rebasing and retargeting. Consider adopting one if stacks become a frequent workflow.
- **CI runs on each PR independently.** Ensure CI is configured to run against the PR's base branch, not just `main`. Most CI systems (GitHub Actions, etc.) handle this correctly by default.
- **PR review is incremental.** Reviewers see only the diff between the Epic branch and its parent — not the entire stack. This keeps reviews focused and manageable.

---

## Agent Operation Guidance

- Prefer interactive or dev commands when iterating; avoid running production-only commands from an agent session.
- Keep dependencies and lockfiles in sync.
- Prefer small, focused commands — run specific tests rather than the full suite when iterating (the full suite is still required before committing; see Pre-Commit Quality Checks).
- Document project-specific dev/test/run commands and required environment variables in the repo's own AGENTS.md or README.
- Every repository-level AGENTS.md or README MUST include sections following this template:

  ```markdown
  ## Local Development Commands
  - Install: `<install command>`
  - Dev run: `<dev command>`
  - Test: `<test command>`
  - Lint: `<lint command>`
  - Typecheck (if applicable): `<typecheck command>`

  ## Required Environment Variables
  - `VAR_NAME`: purpose, allowed values, example
  ```

---

## References

- AGENTS.md convention: https://agents.md/
- BMAD Method: https://github.com/bmad-code-org/BMAD-METHOD
- Organization: https://github.com/petry-projects
