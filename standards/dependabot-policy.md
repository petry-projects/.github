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
4. **Auto-merge** security patches and minor updates after all CI checks pass, using a
   GitHub App token to satisfy branch protection (CODEOWNERS review bypass for bot PRs).
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

Each repository must have:

| File | Purpose |
|------|---------|
| `.github/dependabot.yml` | Dependabot config scoped to the repo's ecosystems |
| `.github/workflows/dependabot-automerge.yml` | Auto-approve + squash-merge security PRs |
| `.github/workflows/dependency-audit.yml` | CI check — fail on known vulnerabilities |

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
- Fetches Dependabot metadata to determine update type
- For **patch** and **minor** updates (and indirect dependency updates):
  approves the PR and enables auto-merge (waits for all required CI checks)
- **Major** updates are left for human review
- Uses `gh pr merge --auto --squash` so the merge only happens after CI passes

## Vulnerability Audit CI Check

See [`workflows/dependency-audit.yml`](workflows/dependency-audit.yml).

This workflow template detects the ecosystems present in the repo and runs the
appropriate audit tool:

| Ecosystem | Tool | Command |
|-----------|------|---------|
| npm | `npm audit` | `npm audit --audit-level=low` (fails on any advisory) |
| Go | `govulncheck` | `govulncheck ./...` (per module) |
| Rust | `cargo-audit` | `cargo audit` |
| Python | `pip-audit` | `pip-audit` |

The workflow fails if any known vulnerability is found, blocking the PR from merging.

## Applying to a Repository

1. Copy the appropriate `dependabot.yml` template to `.github/dependabot.yml`,
   adjusting `directory` paths as needed.
2. Copy `workflows/dependabot-automerge.yml` to `.github/workflows/`.
3. Copy `workflows/dependency-audit.yml` to `.github/workflows/`.
4. Ensure the repository has the GitHub App secrets (`APP_ID`, `APP_PRIVATE_KEY`)
   configured for auto-merge.
5. Create the `security` and `dependencies` labels in the repository if they
   don't already exist.
6. Add `dependency-audit` as a required status check in branch protection rules.
