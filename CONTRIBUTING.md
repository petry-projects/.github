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

The workflow requires an org-level secret `PROJECTS_TOKEN` — a fine-grained PAT
(or GitHub App installation token) with `Projects: Read and write` permission
scoped to the `petry-projects` organization. This is a one-time manual setup;
see issue [#387](https://github.com/petry-projects/.github/issues/387) for details.

### Discussion items

Because the Projects v2 GraphQL API does not include `Discussion` in the
`ProjectV2ItemContent` union, discussions cannot be added as content-linked
items. Instead, the workflow creates a **draft item** with the discussion URL
in the body. If GitHub adds Discussions to the union in the future, the
draft-add path in the workflow can be swapped for direct content linking.
