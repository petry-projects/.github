# AGENTS.md — Petry Projects Organization Standards

This file defines cross-cutting development standards for all repositories in the **petry-projects** organization. It follows the [AGENTS.md convention](https://agents.md/) and is intended to be imported by each repository's own AGENTS.md or CLAUDE.md.

> Individual repositories extend these standards with project-specific guidance. If a repo-level rule conflicts with this file, the repo-level rule takes precedence.

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

---

## Multi-Agent Isolation — Git Worktrees

When multiple agents work on the same repository concurrently, they MUST use **isolated workspaces** to prevent conflicts. Git worktrees are the industry-standard isolation primitive — used by Claude Code, Cursor, Windsurf, Augment Intent, and dmux. Cloud agents (OpenAI Codex, GitHub Copilot, Devin) use containers or ephemeral environments that provide equivalent isolation.

Never have two agents working in the same working directory simultaneously.

### Rules

1. **One workspace per agent.** Every agent performing code changes MUST operate in its own isolated workspace (git worktree, container, or ephemeral environment). This applies to Claude Code (`isolation: "worktree"` or `--worktree`), Cursor parallel agents, GitHub Copilot coding agent, OpenAI Codex, and any other AI agent tool.
2. **One agent per story/task.** Each workspace maps to exactly one BMAD story, feature, or bug fix. Do not assign the same story to multiple agents.
3. **No overlapping file ownership.** Two agents MUST NOT modify the same file concurrently. If stories touch shared files (e.g., a shared type definition, config, or lockfile), serialize those stories — do not run them in parallel. This is the single most important rule for multi-agent work.
4. **Branch from the default branch.** Workspaces MUST branch from the repository's configured default branch (for example, `origin/main`). You MAY use `origin/HEAD` as a shortcut when it is correctly configured, but MUST NOT rely on it being present. Never branch from another agent's branch.
5. **One PR per workspace.** Each workspace produces exactly one pull request. Do not combine unrelated changes.
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

### Coordination Checklist (for humans orchestrating multiple agents)

Before launching parallel agents, verify:
- [ ] Each agent has a distinct story/task assignment
- [ ] No two agents will modify the same files
- [ ] Shared dependencies (lockfiles, generated types) are up to date on the default branch before agents start
- [ ] If stories share a dependency file, run them sequentially, not in parallel
- [ ] No more than 3–5 agents are running concurrently on the same repository

---

## Agent Operation Guidance

- Prefer interactive or dev commands when iterating; avoid running production-only commands from an agent session.
- Keep dependencies and lockfiles in sync.
- Prefer small, focused commands — run specific tests rather than the full suite when iterating (the full suite is still required before committing; see Pre-Commit Quality Checks).
- Document project-specific dev/test/run commands and required environment variables in the repo's own AGENTS.md or README.

---

## References

- AGENTS.md convention: https://agents.md/
- BMAD Method: https://github.com/bmad-code-org/BMAD-METHOD
- Organization: https://github.com/petry-projects
