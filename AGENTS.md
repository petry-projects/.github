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
4. **Tests** — run the full test suite with coverage

Pre-commit hooks may not run in agent sessions — apply formatting and checks manually.

---

## Code Style & Commits

- Follow existing code style and lint rules in each repository.
- Keep commits small and focused — include tests with behavior changes.
- Do not introduce new linting, formatting, or build tooling unless essential and approved.
- Follow the repository's established naming conventions.

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

## Agent Operation Guidance

- Prefer interactive or dev commands when iterating; avoid running production-only commands from an agent session.
- Keep dependencies and lockfiles in sync.
- Prefer small, focused commands — run specific tests rather than the full suite when iterating.
- Document project-specific dev/test/run commands and required environment variables in the repo's own AGENTS.md or README.

---

## References

- AGENTS.md convention: https://agents.md/
- BMAD Method: https://github.com/bmad-code-org/BMAD-METHOD
- Organization: https://github.com/petry-projects
