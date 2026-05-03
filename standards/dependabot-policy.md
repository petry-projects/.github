# Dependabot Policy: Security-Only Updates

## Rationale

New package versions pose risk to stability and security. Keeping known-good versions
and upgrading only when vulnerabilities are found and fixed provides a better
security posture than chasing every minor/patch release.

## Policy

1. **Security updates only** for application dependencies (npm, Go modules, pip, Cargo).
   Dependabot opens PRs only when a vulnerability advisory exists for a dependency.
   Version update PRs are suppressed by setting `open-pull-requests-limit: 0` for
   application ecosystems — Dependabot security updates bypass this limit.
2. **Version updates weekly** for GitHub Actions, since pinned action versions do not
   affect application stability and staying current reduces CI attack surface.
3. **Labels** `security` and `dependencies` on every Dependabot PR for filtering and audit.
4. **Auto-merge** after all CI checks pass, using a GitHub App token to approve
   and merge eligible PRs. Both bot accounts (`dependabot-automerge-petry` and
   `petry-projects-pr-review-agent`) are listed as code owners in every repo's
   `CODEOWNERS` file so their approvals satisfy `require_code_owner_review`
   without any bypass. Eligible updates:
   - **GitHub Actions**: all version bumps including major (SHA-pinned, no runtime impact)
   - **App ecosystems**: patch and minor security updates only (major requires human review)
   - **Indirect (transitive) dependencies**: all updates regardless of version bump
   Uses `gh pr merge --auto` to wait for required checks before merging.
5. **Vulnerability audit CI check** runs on every PR and push to `main`, failing the
   build if any dependency has a known advisory. This is a required status check.

## Prerequisites

- **Dependabot security updates** must be enabled at the org or repo level
  (Settings > Code security > Dependabot security updates).
- The `dependabot.yml` entries below configure which ecosystems and directories
  Dependabot monitors. Setting `open-pull-requests-limit: 0` for application
  ecosystems suppresses routine version-update PRs while still allowing
  security-alert-triggered PRs to be created.

## Configuration Files

Each repository must have the following baseline files:

| File | Purpose |
|------|---------|
| `.github/dependabot.yml` | Dependabot config scoped to the repo's ecosystems |
| `.github/workflows/dependabot-automerge.yml` | Auto-approve + squash-merge security PRs |
| `.github/workflows/dependency-audit.yml` | CI check — fail on known vulnerabilities |

The following file is conditional:

| File | When required |
|------|--------------|
| `.github/workflows/dependabot-rebase.yml` | Required when strict required-status-checks (`strict_required_status_checks_policy: true`) applies — without it, Dependabot PRs fall behind after each merge and stall. **Not** required for CODEOWNERS enforcement; bot accounts in `CODEOWNERS` handle that. See [Applying to a Repository](#applying-to-a-repository) for details. |

## Dependabot Templates

Use the template matching your repository type.

**Application ecosystems** (npm, gomod, cargo, pip, terraform) use:

```yaml
schedule:
  interval: "weekly"
open-pull-requests-limit: 0   # suppress version updates; security PRs bypass this
labels:
  - "security"
  - "dependencies"
```

**GitHub Actions** uses:

```yaml
schedule:
  interval: "weekly"
open-pull-requests-limit: 10  # allow version updates for CI actions
labels:
  - "security"
  - "dependencies"
```

### Frontend (npm)

For repos with `package.json` at root or in subdirectories.

- Ecosystem: `npm`
- Directory: `/` (or path to each `package.json`)

See [`dependabot/frontend.yml`](dependabot/frontend.yml)

### Backend — Go

For repos with `go.mod`.

- Ecosystem: `gomod`
- Directory: path to `go.mod`

See [`dependabot/backend-go.yml`](dependabot/backend-go.yml)

### Backend — Rust

For repos with `Cargo.toml`.

- Ecosystem: `cargo`
- Directory: `/`

See [`dependabot/backend-rust.yml`](dependabot/backend-rust.yml)

### Backend — Python

For repos with `pyproject.toml` or `requirements.txt`.

- Ecosystem: `pip`
- Directory: `/`

See [`dependabot/backend-python.yml`](dependabot/backend-python.yml)

### Infrastructure — Terraform

For repos with Terraform modules.

- Ecosystem: `terraform`
- Directory: path to Terraform root module

See [`dependabot/infra-terraform.yml`](dependabot/infra-terraform.yml)

### GitHub Actions (all repos)

Every repository must include the `github-actions` ecosystem entry.
GitHub Actions use **version updates** (not security-only) on a weekly schedule
since pinned action SHAs do not affect application runtime stability.

```yaml
- package-ecosystem: "github-actions"
  directory: "/"
  schedule:
    interval: "weekly"
  open-pull-requests-limit: 10
  labels:
    - "security"
    - "dependencies"
```

### Full-Stack Example

A full-stack repo (e.g., npm + Go + Terraform + GitHub Actions) combines the
relevant ecosystem entries into a single `dependabot.yml`. See
[`dependabot/fullstack.yml`](dependabot/fullstack.yml) for a complete example.

## Auto-Merge Workflow

See [`workflows/dependabot-automerge.yml`](workflows/dependabot-automerge.yml).

Behavior:

- Triggers on `pull_request_target` from `dependabot[bot]`
- Fetches Dependabot metadata to determine update type and ecosystem
- For **GitHub Actions**: approves and auto-merges all version bumps including
  major, since actions are SHA-pinned and CI catches breaking interface changes
- For **app ecosystems**: approves **patch** and **minor** updates (and indirect
  dependency updates); **major** updates are left for human review
- Uses `gh pr merge --auto --squash` so the merge only happens after CI passes

## Update and Merge Behind PRs Workflow

See [`workflows/dependabot-rebase.yml`](workflows/dependabot-rebase.yml).

When branch protection requires branches to be up-to-date (`strict: true`),
merging one Dependabot PR makes the others fall behind. Dependabot only rebases
PRs on its scheduled run (weekly) or when there are merge conflicts — not when
a PR merely falls behind `main`. Additionally, GitHub's auto-merge (`--auto`)
may not trigger when rulesets cause `mergeable_state` to report "blocked" even
when all requirements are met. Together, these issues stall Dependabot PR
merges indefinitely.

This workflow fires on every push to `main` and:

1. **Updates behind PRs** — uses the GitHub API `update-branch` endpoint with
   the **merge** method to bring Dependabot PR branches up to date with `main`.
2. **Merges ready PRs** — directly merges any Dependabot PR that is up-to-date,
   has auto-merge enabled, and has all CI checks passing.

Using the app token for merges ensures each merge triggers a new push to `main`,
creating a self-sustaining chain that serializes Dependabot PR merges.

**Important:** always use the **merge** method (not rebase) with `update-branch`.
The rebase method force-pushes, replacing Dependabot's commit signature, which
breaks `dependabot/fetch-metadata` verification and causes Dependabot to refuse
future operations ("edited by someone other than Dependabot"). The merge method
preserves the original commits. The automerge workflow must use
`skip-commit-verification: true` in `dependabot/fetch-metadata` since the merge
commit is authored by GitHub, not Dependabot.

## Vulnerability Audit CI Check

See [`workflows/dependency-audit.yml`](workflows/dependency-audit.yml).

This workflow template detects the ecosystems present in the repo and runs the
appropriate audit tool:

| Ecosystem | Tool | Command |
|-----------|------|---------|
| npm | `npm audit` | `npm audit --audit-level=low` per `package-lock.json` (fails on any advisory) |
| pnpm | `pnpm audit` | `pnpm audit --audit-level low` per `pnpm-lock.yaml` |
| Go | `govulncheck` | `govulncheck ./...` per `go.mod` directory |
| Rust | `cargo-audit` | `cargo audit` per `Cargo.toml` workspace |
| Python | `pip-audit` | `pip-audit .` per `pyproject.toml` / `-r requirements.txt` |

The workflow fails if any known vulnerability is found, blocking the PR from merging.

## Applying to a Repository

1. Copy the appropriate `dependabot.yml` template to `.github/dependabot.yml`,
   adjusting `directory` paths as needed.
2. Add `workflows/dependabot-automerge.yml` to `.github/workflows/`.
3. Add `workflows/dependabot-rebase.yml` to `.github/workflows/` if the repo
   enforces **strict required-status-checks** (`strict_required_status_checks_policy: true`
   or classic branch protection `required_status_checks.strict: true`) — without
   this workflow, Dependabot PRs fall behind after each merge to `main` and stall.
   If the repo does not use strict status checks, the rebase workflow is unnecessary.

   > **Note:** The rebase workflow is **not** required for `require_code_owner_review`.
   > The correct solution for CODEOWNERS enforcement is to list the bot accounts
   > (`@dependabot-automerge-petry`, `@petry-projects-pr-review-agent`) as owners
   > in every CODEOWNERS pattern — see the
   > [CODEOWNERS Standard](github-settings.md#codeowners-standard). The earlier
   > approach of using `gh api .../merge` as a bypass was fragile and has been
   > superseded.
4. Add `workflows/dependency-audit.yml` to `.github/workflows/`.
5. **GitHub App secrets** — `APP_ID` and `APP_PRIVATE_KEY` are managed at the
   **organization level** (`gh secret set <name> --org petry-projects --visibility all`),
   not per-repo. Caller stubs use `secrets: inherit` so any repo with at least
   one centralized dependabot workflow picks them up automatically. Per-repo
   `APP_ID` / `APP_PRIVATE_KEY` settings are deprecated drift — once the org
   secrets are confirmed in place, delete any per-repo copies so there's a
   single source of truth and rotations propagate everywhere.

   **Verify before deleting per-repo copies.** Run

   ```bash
   gh secret list --org petry-projects | grep -E '^(APP_ID|APP_PRIVATE_KEY)\s'
   ```

   to confirm both org-level secrets exist with `visibility: all`. Then
   confirm the dependabot caller stubs in the target repo include
   `secrets: inherit` (they will if copied verbatim from
   `standards/workflows/dependabot-automerge.yml` and
   `standards/workflows/dependabot-rebase.yml`). Only after both checks
   pass should you run `gh secret delete APP_ID --repo <repo>` etc. to
   clean up the per-repo copies — otherwise the workflow falls back to
   nothing and `gh pr review` calls fail with `Secret APP_ID is required`.
6. Create the `security` and `dependencies` labels in the repository if they
   don't already exist.
7. Add `dependency-audit / Detect ecosystems` as a required status check in
   branch protection rules. Do **not** require the per-ecosystem audit jobs
   (`npm audit`, `govulncheck`, `cargo audit`, `pip-audit`, `pnpm audit`) —
   they're conditional on lockfile presence and report `SKIPPED` when absent,
   and a required-but-skipped check fails the merge gate.
