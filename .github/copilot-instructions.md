# Copilot Instructions — Petry Projects Organization

## Organization Overview

**Petry Projects** builds TypeScript-first applications: Electron desktop apps (TalkTerm),
backend services, Google Apps Script automation, and GitHub infrastructure. The primary stack is
TypeScript · React · Electron · Vitest · Node.js · Go · Python · Terraform · GitHub Actions.

## Standards Reference

Full AI agent development standards live in **[AGENTS.md](../AGENTS.md)**. This file is a
Copilot-focused summary; AGENTS.md is authoritative when they conflict. Read the relevant
standard in [`standards/`](../standards/) before touching CI, repo settings, or agent
configuration.

Language-specific rules are applied automatically via files in `.github/instructions/`:
`typescript`, `javascript`, `python`, `go`, `terraform`, and `shell` — see those files for
per-language guidance.

## Core Development Rules

**Test-driven development is mandatory.** Write tests before implementing features. Never
`.skip()` a failing test — fix it. Never add coverage-ignore comments (`istanbul ignore`,
`c8 ignore`, `v8 ignore`). PRs that reduce coverage below the repo-defined threshold are
rejected.

**SOLID + DDD.** Each module has one reason to change. High-level policy never imports
infrastructure directly — inject dependencies. Use domain terminology in code, tests, and docs.
Bounded contexts communicate through well-defined interfaces or domain events. Use typed value
objects for domain identifiers and quantities instead of raw primitives.

**CLEAN Code + KISS + YAGNI.** Names reveal intent. Functions do one thing at one level of
abstraction. Implement exactly what the current story requires — no speculative features. Wait
for three concrete cases before extracting an abstraction.

**Fail loud, never fake.** Never swallow exceptions silently. Never substitute placeholder data
when a real fetch or computation fails without an explicit, disclosed fallback (log it, flag it,
or surface a `degraded: true` field). Never report a step complete when it errored.

**No breaking changes without explicit human approval.** Before removing or renaming any public
symbol, endpoint, field, event schema, or database column: search all consumers, count them, and
propose a non-breaking alternative first. Treat the existing test suite as a contract — failing
tests signal breaking changes, not tests to update.

## Pre-Commit Quality Checks

Before every commit run in order: **format → lint → typecheck → test**. Hooks may not execute
in Copilot sessions — apply manually. Zero warnings and zero errors required for lint and
typecheck. Run the full test suite with coverage before pushing.

## Structured Logging

All services emit structured JSON logs in production. Every entry includes `timestamp`
(ISO 8601 UTC), `level`, `msg`, `service`, `version`. Variable data goes in fields, never in
the message string:

- **Wrong:** `logger.info("User 1234 placed order 5678")`
- **Right:** `logger.info({ user_id: "1234", order_id: "5678" }, "order placed")`

Use `pino` in TypeScript/Node.js and `log/slog` in Go. Never use `console.log` in application
code. Never log passwords, tokens, API keys, cookies, or PII.

## CI Quality Gates

All PRs must pass before merge: CodeQL (SAST), SonarCloud (quality), project linter at zero
errors, type-checker, full test suite at coverage threshold, CodeRabbit and Copilot review
comments resolved. Never bypass CI gates or weaken thresholds to make a PR pass.

## Git and PR Workflow

Always branch from `main`:

```bash
git checkout main && git pull origin main && git checkout -b <branch-name>
```

All changes go through pull requests — never commit directly to `main`. Squash merge only
(enforced by the `pr-quality` ruleset). Resolve every review thread before merging. Use
`in-progress` labels when multiple agents work from a shared issue queue.

## Security

Never commit secrets, `.env` files, API keys, or Terraform state. Use GitHub Actions secrets or
an external secret manager. Mark all sensitive Terraform variables `sensitive = true`. Gitleaks
secret scanning runs on every PR.

---

## Extending These Instructions Per Repository

Each repository SHOULD provide its own `.github/copilot-instructions.md`. Repository-level
instructions take priority over this org-level file. A repo-level file SHOULD cover:

1. **About** — one sentence describing what the repo does and its role in the org
2. **Tech stack** — frameworks, libraries, and major versions specific to this repo
3. **Project structure** — key directories, naming conventions, bounded context layout
4. **Local dev commands** — exact install, dev, test, lint, and typecheck commands
5. **Required environment variables** — names, purposes, and example values
6. **Testing framework** — runner (Vitest / Jest / pytest / go test), coverage tool, thresholds
7. **Repo-specific rule overrides** — any rule that differs from these org-level defaults;
   reference the specific AGENTS.md section being overridden

The repo-level file inherits all org-level rules; only document what differs or adds detail.
Copy the template from
[`standards/copilot-instructions-standard.md`](../standards/copilot-instructions-standard.md)
to get started.
