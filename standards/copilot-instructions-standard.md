# Copilot Instructions Standard

This standard defines how to create and maintain GitHub Copilot custom instruction files across
the **petry-projects** organization.

## Overview

GitHub Copilot supports two types of instruction files:

| Type | File | Scope |
|------|------|-------|
| **Org-level** (this repo) | `.github/copilot-instructions.md` | Applies to all org repos |
| **Repo-level** | `.github/copilot-instructions.md` in each repo | Overrides org-level for that repo |
| **Path-specific** | `.github/instructions/<name>.instructions.md` | Applies to matching file patterns |

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
- **Task-specific, not task-specific:** Instructions should apply to all work in the repo, not
  to a single task or PR.
- **Actionable language:** Prefer imperatives ("use `pino` for logging") over descriptions
  ("this repo uses pino for logging").
- **No duplication with AGENTS.md:** AGENTS.md is the authoritative source for AI agent
  standards. Copilot instruction files summarize or extend it — they don't replace it.
- **Keep in sync:** When the tech stack changes (major version bump, new framework, tool
  replacement), update `copilot-instructions.md` in the same PR.

## Compliance

The compliance audit script (`scripts/compliance-audit.sh`) does not currently check for the
presence of `copilot-instructions.md`. Adding a check is tracked as a feature request. Until
then, maintain the file as a team discipline item.
