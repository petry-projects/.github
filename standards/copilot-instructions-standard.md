# Copilot Instructions Standard

This standard defines how to create and maintain GitHub Copilot custom instruction files across
the **petry-projects** organization.

## Purpose and Benefits

GitHub Copilot generates suggestions based on the open file and surrounding context, but it
cannot infer project-specific facts from code alone: which test runner is in use, what the exact
local dev commands are, which bounded contexts a repo defines, or what coverage thresholds are
enforced in CI. Without instruction files, every developer and every agent session must
re-discover this context through trial-and-error or by reading the README.

Instruction files solve this by surfacing the right context to Copilot automatically:

| Benefit | How instruction files deliver it |
|---------|----------------------------------|
| **Consistent suggestions** | Copilot sees org coding standards on every request — SOLID, DDD, TDD, structured logging — without requiring the developer to repeat them |
| **Reduced onboarding friction** | New contributors and agents get the project's stack, structure, and commands immediately, not after reading multiple docs |
| **Enforced standards** | Language-specific files (TypeScript, Go, Terraform, …) embed org linting, formatting, and security rules so Copilot proposes compliant code by default |
| **Less review churn** | Fewer review comments on style and convention violations; agents are less likely to introduce drift |
| **Faster agent execution** | Copilot coding agents pre-load the right dependencies and follow the right patterns without a bootstrapping phase |

The org-level baseline (`petry-projects/.github`) covers rules that apply everywhere. Repo-level
files add the project-specific context that makes suggestions accurate for that repo in particular.

## Overview

GitHub Copilot supports three scopes of instruction files:

| Type | File | Scope |
|------|------|-------|
| **Org-level** (this repo) | `.github/copilot-instructions.md` | Applies to all repos in the org via the special `.github` repository |
| **Repo-level** | `.github/copilot-instructions.md` in each repo | Applies to that repo; extends or overrides the org-level baseline |
| **Path-specific** | `.github/instructions/<name>.instructions.md` | Applies to files matching the `applyTo` glob pattern |

Path-specific files use YAML frontmatter to specify which files they apply to:

```yaml
---
description: "Purpose of these instructions"
applyTo: "**/*.ts,**/*.tsx"
---
```

The `excludeAgent` frontmatter key restricts which tools use the instructions
(`"code-review"` or `"cloud-agent"`).

Priority order (highest to lowest): Personal instructions → Repository instructions →
Organization instructions.

## Org-Level Instruction Files

The following files live in this repo (`petry-projects/.github`) and apply org-wide:

| File | Languages / Scope |
|------|-------------------|
| `.github/copilot-instructions.md` | All repos — org-wide defaults |
| `.github/instructions/typescript.instructions.md` | `**/*.ts`, `**/*.tsx` |
| `.github/instructions/javascript.instructions.md` | `**/*.js`, `**/*.mjs`, `**/*.cjs` |
| `.github/instructions/python.instructions.md` | `**/*.py` |
| `.github/instructions/go.instructions.md` | `**/*.go`, `**/go.mod`, `**/go.sum` |
| `.github/instructions/terraform.instructions.md` | `**/*.tf`, `**/*.tfvars`, `**/*.tftest.hcl` |
| `.github/instructions/shell.instructions.md` | `**/*.sh`, `**/*.bash`, `**/Makefile` |

## Adding a New Language

To add a new language instruction file:

1. Create `.github/instructions/<language>.instructions.md` in this repo.
2. Add the `applyTo` frontmatter with glob patterns for the language's file extensions.
3. Base the content on the relevant [awesome-copilot template](https://awesome-copilot.github.com/instructions/)
   and adapt it to org conventions defined in `AGENTS.md`.
4. Add an entry to the table above in this document.
5. Open a PR to `petry-projects/.github` following the standard PR workflow.

## Creating a Repo-Level copilot-instructions.md

Each repository SHOULD provide its own `.github/copilot-instructions.md` that adds repo-specific
context on top of the org-level defaults. Repo-level instructions inherit all org-level rules —
only document what differs or adds detail.

### Required Sections

A repo-level `copilot-instructions.md` MUST include the following sections. Keep the file to
approximately two pages — concise, specific, and actionable.

---

```markdown
# Copilot Instructions — [Repo Name]

## About

[One sentence describing what this repo does and its role in the petry-projects org.]

## Tech Stack

- **Runtime:** Node.js 22 / Python 3.12 / Go 1.23 / [adjust]
- **Framework:** React 19 · Electron 41 / FastAPI / [adjust]
- **Testing:** Vitest · Playwright / pytest / go test [adjust]
- **Linting:** ESLint (flat config) + Prettier / ruff + black / golangci-lint [adjust]
- **Key libraries:** [list major dependencies]

## Project Structure

[Describe key directories and naming conventions. Example:]

src/
  domain/          # Domain models, value objects, aggregates
  application/     # Use cases, command/query handlers
  infrastructure/  # Adapters, persistence, external services
  presentation/    # UI components, API routes

## Local Dev Commands

- Install:    `npm install`
- Dev run:    `npm run dev`
- Test:       `npm test`
- Lint:       `npm run lint`
- Typecheck:  `npm run typecheck`

## Required Environment Variables

- `DATABASE_URL`: PostgreSQL connection string (e.g., `postgres://user:pass@host/db`)
- `API_KEY`: External service API key (obtain from the team vault)

## Testing Framework

- Runner: Vitest [or Jest / pytest / go test]
- Coverage threshold: 85% statements / 80% branches [repo-specific]
- Mutation testing: Stryker (runs in CI) [if applicable]

## Repo-Specific Overrides

[List any rules that differ from the org-level copilot-instructions.md. Reference the specific
AGENTS.md section being overridden. Leave this section blank (or remove it) if no overrides
apply.]

## Org Standards

See [petry-projects/.github — AGENTS.md](https://github.com/petry-projects/.github/blob/main/AGENTS.md)
for full development standards.
```

---

### What to Include vs. What to Omit

**Include in repo-level instructions:**

- Specific framework versions and major library choices
- Bounded context names and directory layout
- Exact local dev commands with correct flags
- Coverage thresholds and testing tools specific to this repo
- Architecture patterns unique to this repo (e.g., Electron IPC conventions, GAS extraction pattern)
- Any rule that overrides or refines the org-level defaults

**Do NOT include in repo-level instructions:**

- Org-wide rules already covered in `copilot-instructions.md` (SOLID, TDD, logging format, etc.)
- Rules already covered in language-specific `.instructions.md` files
- Content already documented in `AGENTS.md`
- Secrets, API keys, credentials, or example tokens with real values

## Content Quality Rules

- **Max length:** ~two pages. Copilot applies instructions most effectively when they are
  concise and broadly applicable. Longer files may be truncated.
- **Repo-wide, not task-specific:** Instructions should apply to all work in the repo, not
  to a single task or PR.
- **Actionable language:** Prefer imperatives ("use `pino` for logging") over descriptions
  ("this repo uses pino for logging").
- **No duplication with AGENTS.md:** AGENTS.md is the authoritative source for AI agent
  standards. Copilot instruction files summarize or extend it — they don't replace it.
- **Keep in sync:** When the tech stack changes (major version bump, new framework, tool
  replacement), update `copilot-instructions.md` in the same PR.

## Compliance

The weekly compliance audit (`scripts/compliance-audit.sh`) enforces this standard
automatically. Two `warning`-severity checks run against every repository in the org:

| Check ID | Trigger | Remediation |
|----------|---------|-------------|
| `missing-copilot-instructions` | `.github/copilot-instructions.md` is absent | Copy the template below and fill in the repo-specific sections |
| `copilot-instructions-missing-tech-stack` | File exists but `## Tech Stack` section is absent | Add the section — list runtimes, frameworks, and major library versions |
| `copilot-instructions-missing-local-dev-commands` | File exists but `## Local Dev Commands` section is absent | Add the section — include exact install, dev-run, test, lint, and typecheck commands |

Findings are reported as `warning` (not `error`) because the org-level baseline in
`petry-projects/.github` ensures minimum Copilot guidance even without a repo-level file.
However, all warnings are tracked in the weekly compliance report and surfaced as GitHub issues
for remediation.

The `petry-projects/.github` repo itself is exempt from the repo-level check — its
`.github/copilot-instructions.md` is the org-level baseline that applies to all repos.
