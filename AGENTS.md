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
- Integration tests are allowed but MUST be clearly marked and skippable in CI.
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

## CI Quality Gates

- **Iterate until all CI checks pass.** Before requesting review or marking a PR as ready:
  - Run all checks locally (format, lint, typecheck, tests, coverage)
  - If any check fails in CI, investigate locally, fix the issue, and re-run
  - Continue iterating until all checks pass both locally and in CI
- Never bypass CI gates or weaken thresholds to make a PR pass.

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

## Planning Artifacts

Repositories using the BMAD method store planning documents in `_bmad-output/planning-artifacts/`. Always consult these before implementing — they contain PRDs, architecture decisions, UX specs, and epics/stories.

---

## Agent Operation Guidance

- Prefer interactive or dev commands when iterating; avoid running production-only commands from an agent session.
- Keep dependencies and lockfiles in sync.
- Prefer small, focused commands — run specific tests rather than the full suite when iterating.
- Document project-specific dev/test/run commands and required environment variables in the repo's own AGENTS.md or README.

---

## References

- AGENTS.md convention: https://agents.md/
- Organization: https://github.com/petry-projects
