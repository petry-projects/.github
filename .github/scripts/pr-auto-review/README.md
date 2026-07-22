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
| `pr_auto_review_blocking_thread_count` | review-threads JSON on stdin (`reviewThreads(first:100){nodes{isResolved isOutdated}}`) | prints the count of **blocking** threads — unresolved AND not outdated |
| `pr_auto_review_ready STATE IS_DRAFT CHECKS_JSON REQUIRED_JSON SELF_NAME REVIEW_DECISION BLOCKING_THREAD_COUNT` | the PR facts the workflow gathers (all as arguments — no stdin) | prints the **decision class** on stdout; `0` ready, `1` not ready |

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

### Unresolved-thread semantics (issue #806)

Criterion #4 blocks dispatch on open review threads, but not all open threads
should block. dev-lead's fix-review cycle frequently **addresses an advisory
finding (Copilot / Gemini / CodeRabbit) in a follow-up commit but never marks
the thread resolved**. The code is fixed and CI is green, yet the PR sits
`REVIEW_REQUIRED` until a human resolves the thread by hand.

`pr_auto_review_blocking_thread_count` is the consumer-side, defense-in-depth
fix: it counts a thread as **blocking only when it is unresolved AND not
outdated**. GitHub sets `reviewThread.isOutdated == true` exactly when the diff
position the thread anchors to no longer exists at the current HEAD (the line
changed or the file moved) — a heuristic that the diff anchor shifted, not a
guarantee the concern was resolved. So an
unresolved-but-outdated thread — the signature of a fix that changed the flagged
line without resolving the thread — is treated as non-blocking, and the PR
converges without manual thread resolution.

Fail-safe: only an explicit `isOutdated == true` makes a thread non-blocking. A
`null` or absent `isOutdated` on an unresolved thread still blocks, so a thread
whose staleness cannot be confirmed is never silently dropped. This is
defense-in-depth: the producer side (dev-lead resolving the threads it fixes) is
still the preferred fix; this gate just stops forgotten resolutions from
stalling otherwise-mergeable PRs.

## The catch-up sweep — `sweep.sh` + `lib/sweep.sh`

The event-driven reusable workflow reviews a PR when its triggering event
(CI green, review submitted, …) fires. A dropped or missed event — or a PR that
went green while no event was in flight — can leave a mergeable PR un-reviewed.
`sweep.sh` is a periodically-run **catch-up sweep**: it re-scans open PRs and
dispatches the review agent for the ones the event path missed.

`sweep.sh` is thin gh I/O glue; every decision lives in the pure, unit-tested
cores it sources — `lib/ready-check.sh` (per-PR readiness) and `lib/sweep.sh`
(candidate selection, `test/workflows/pr-auto-review/sweep.bats`).

### `lib/sweep.sh`

Pure, side-effect-free helpers. Source the file, then call:

| Function | Input | Returns |
|----------|-------|---------|
| `pr_auto_review_sweep_valid_search` | a search payload on stdin | `0` if it is a valid JSON array (incl. empty `[]`); non-zero + stderr otherwise |
| `pr_auto_review_sweep_extract` | a search payload (JSON array of PR objects) on stdin | prints a compact `[{number,updatedAt}]`; **non-zero** (not an abort) on a malformed / non-array payload |
| `pr_auto_review_sweep_page_full COUNT PER_PAGE` | — | `0` if `COUNT >= PER_PAGE` (more pages may exist), `1` otherwise |
| `pr_auto_review_sweep_merge_pages` | one-or-more candidate arrays concatenated on stdin | prints one array, deduped by `.number` |
| `pr_auto_review_sweep_order` | a candidate array on stdin | prints it sorted oldest-first by `updatedAt`, ties by `number` asc |
| `pr_auto_review_sweep_plan MAX_PER_RUN` | an ordered `[{number,ready}]` array on stdin | prints the PR numbers to dispatch — ready-only, capped at **MAX dispatched** |

### Robustness properties (issue #872)

The sweep is hardened against four failure modes; each maps to a pure helper so
the behaviour is unit-tested without a live gh:

1. **Cap on the number _dispatched_, not considered.** Readiness is evaluated for
   every candidate *before* the per-run cap is applied
   (`pr_auto_review_sweep_plan` counts only ready PRs), so a run of older
   non-ready PRs can never consume all slots and starve newer ready ones.
2. **Full pagination.** The labeled-PR search is paged while
   `pr_auto_review_sweep_page_full` reports a full page; pages are combined with
   `pr_auto_review_sweep_merge_pages`, so PRs beyond page 1 are swept rather than
   dropped at the 100-item cliff.
3. **A failed search surfaces, never no-ops.** A non-zero gh exit *or* a payload
   `pr_auto_review_sweep_valid_search` rejects (empty string, error object,
   malformed JSON) aborts the run with an error, instead of being read as an
   empty candidate set / "nothing to do".
4. **A malformed payload is guarded.** `pr_auto_review_sweep_extract` catches a
   jq parse failure and returns non-zero rather than letting an unguarded jq
   error abort the whole sweep under `set -euo pipefail`.

Plus deterministic **oldest-first ordering** (`pr_auto_review_sweep_order`): when
more PRs are ready than one run's cap allows, the longest-waiting ready PR drains
first, so no ready PR is perpetually starved across runs.

### Context name matching

Rulesets store the bare context (e.g. a job name `Lint`, or a third-party status
context `SonarCloud Code Analysis`), while `gh pr checks` renders Actions checks
as `"<workflow> / <job>"` (e.g. `CI / Lint`). A check matches a required context
when the names are equal, or when either ends with `" / <the other>"`, so both
forms resolve to the same required check.
