# pr-auto-review scripts

Supporting logic for the org-level **PR Auto-Review — Ready Check** reusable
workflow (`.github/workflows/pr-auto-review-reusable.yml`). All bash/jq decision
logic lives here so it can be unit-tested with bats
(`test/workflows/pr-auto-review/`) instead of being trapped inline in YAML.

The reusable workflow checks this repo out at `github.job_workflow_sha` (using
the `GH_PAT_WORKFLOWS` secret for authentication, so no extra caller permission
is required) and sources `lib/ready-check.sh` to decide whether a PR's CI checks
satisfy the passing-gate before the review agent is dispatched. Sourcing from the
reusable's own commit keeps the predicate matched to the pinned workflow version.

## `lib/ready-check.sh`

Pure, side-effect-free helpers. Source the file, then call:

| Function | Input | Returns |
|----------|-------|---------|
| `pr_auto_review_required_contexts` | branch-rules JSON on stdin (`GET /repos/{owner}/{repo}/rules/branches/{branch}`) | prints a compact JSON array of required status-check context names (`[]` if none / non-array) |
| `pr_auto_review_checks_ready REQUIRED_JSON SELF_NAME` | checks JSON on stdin (`gh pr checks --json bucket,name`) | prints a one-line reason; `0` ready, `1` not ready |
| `pr_auto_review_ready STATE IS_DRAFT CHECKS_JSON REQUIRED_JSON SELF_NAME REVIEW_DECISION UNRESOLVED_COUNT` | the PR facts the workflow gathers (all as arguments — no stdin) | prints the **decision class** on stdout; `0` ready, `1` not ready |

### The unified decision core — `pr_auto_review_ready`

`pr_auto_review_ready` is the single pure core the reusable workflow calls. It
evaluates all four readiness criteria, in gate order, and **prints the decision
class** on stdout — one of the classes Layer 2 decision-telemetry (issue #668
increment 4) consumes:

| Class | Meaning | Criterion |
|-------|---------|-----------|
| `skip-draft` | PR is not `OPEN`, or is a draft | #1 |
| `skip-checks-pending` | a required check is missing / not yet passing, or no checks reported at all | #2 |
| `skip-changes-requested` | effective review decision is `CHANGES_REQUESTED` | #3 |
| `skip-unresolved-threads` | ≥1 unresolved review thread | #4 |
| `dispatched` | all criteria satisfied — dispatch the review agent | — |

Exit status is `0` iff the class is `dispatched`. Criteria are checked in order,
so an earlier skip wins (a draft PR that also has `CHANGES_REQUESTED` reports
`skip-draft`). The required-checks gate (#2) is delegated verbatim to
`pr_auto_review_checks_ready`, so the required-vs-non-required behaviour of
issue #680 is unchanged. The function makes **no** external calls — the workflow does
all the gh / GraphQL I/O and echoes the returned class to `$GITHUB_OUTPUT`.

### Passing-gate semantics (issue #680)

The old gate counted **every** check context, so a non-required or **cancelled**
advisory context (e.g. a superseded `dev-lead / ci-relay` run, cancelled by
per-PR concurrency) was scored as "not passing" and silently blocked
auto-dispatch on PRs that were actually mergeable.

`pr_auto_review_checks_ready` instead evaluates only the checks that actually
gate merge:

- **`REQUIRED_JSON` non-empty** — gate on the required contexts only. The PR is
  **not ready** if any required context has no matching check reported yet, or a
  matching check is not in the `pass`/`skipping` bucket (i.e. `fail`, `pending`
  or `cancel`). Every non-required context — including cancelled advisory
  runs — is ignored.
- **`REQUIRED_JSON` empty** — fallback (issue option **B**) for branches with no
  configured required status checks: block only when a non-self check is
  `fail` or `pending`; `cancel`, `skipping` and `pass` are non-blocking.

`SELF_NAME` is this workflow's own check-run name; it is excluded from the gate
so an in-progress run never blocks itself.

### Context name matching

Rulesets store the bare context (e.g. a job name `Lint`, or a third-party status
context `SonarCloud Code Analysis`), while `gh pr checks` renders Actions checks
as `"<workflow> / <job>"` (e.g. `CI / Lint`). A check matches a required context
when the names are equal, or when either ends with `" / <the other>"`, so both
forms resolve to the same required check.
