# Contributing to petry-projects/.github

This repository holds org-wide CI templates, workflow standards, and engineering
guidelines for the `petry-projects` organization.

## Getting started

1. Fork the repository and create a branch off `main`.
2. Read [AGENTS.md](./AGENTS.md) before making any changes — it defines org-wide
   standards for CI, workflows, labels, and agent configuration.
3. Follow the relevant standard in [`standards/`](./standards/) for the area you
   are changing (CI workflows, Dependabot, repo settings, etc.).
4. Open a pull request — CI (lint, YAML, actionlint, shellcheck) must pass before review.

## GitHub Projects — Initiatives board

The org maintains a single **Initiatives project** at
<https://github.com/orgs/petry-projects/projects/1> that tracks cross-repo
work across the following initiative buckets: Compliance Blitz, Agent Shield,
Self-healing, Auto-rebase, Model fallback, Tooling, and Compliance program.

### What gets added automatically

The [`add-to-project.yml`](./.github/workflows/add-to-project.yml) workflow
adds items to the board automatically:

| Item type | Rule |
|---|---|
| Issues | Labeled `dev-lead` **and** none of the excluded labels below |
| Pull requests | Labeled `dev-lead` **and** none of the excluded labels below |
| Discussions | Created in (or moved into) the **Ideas** category — added as draft items |

### Noise gate — excluded labels

Issues and PRs carrying any of the following labels are **not** added to the
board, even if they also carry `dev-lead`. These labels indicate automated or
operational items that would flood the board with noise:

- `compliance-audit`
- `health-check`
- `fleet-tracker`
- `daily-report`

### Token requirement

The workflow authenticates using the **`petry-projects-planner` GitHub App**
(App ID 3985527) via
[`actions/create-github-app-token`](https://github.com/actions/create-github-app-token).
Two org-level secrets must be set — this is a one-time manual setup;
see issue [#387](https://github.com/petry-projects/.github/issues/387) for details:

| Secret | Value |
|---|---|
| `INITIATIVES_APP_ID` | The numeric App ID (`3985527`) |
| `INITIATIVES_APP_PRIVATE_KEY` | The PEM private key generated for the app |

The app installation must be granted the following repository/org permissions:

- **Organization projects:** Read and write
- **Issues:** Read-only (required for the action to resolve issue node IDs)
- **Pull requests:** Read-only (required for the action to resolve PR node IDs)

> **Note:** Fine-grained personal access tokens (PATs) do not support
> organization-level Projects v2. If you need a PAT-based fallback, use a
> classic PAT with the `project` OAuth scope instead of a fine-grained token.

### Discussion items

Because the Projects v2 GraphQL API does not include `Discussion` in the
`ProjectV2ItemContent` union, discussions cannot be added as content-linked
items. Instead, the workflow creates a **draft item** with the discussion URL
in the body. If GitHub adds Discussions to the union in the future, the
draft-add path in the workflow can be swapped for direct content linking.
