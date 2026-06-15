# auto-rebase scripts

Supporting logic for the org-level **auto-rebase** reusable workflow
(`.github/workflows/auto-rebase-reusable.yml`). All bash/jq decision logic
lives here so it can be unit-tested with bats
(`test/workflows/auto-rebase/`) instead of being trapped inline in YAML.

The reusable workflow checks this repo out at `inputs.tooling_ref` (default
`v1`) and sources `lib/eligibility.sh` to decide which behind PRs to update.

## `lib/eligibility.sh`

Pure, side-effect-free predicates. Source the file, then call:

| Function | Input | Returns |
|----------|-------|---------|
| `auto_rebase_has_current_approval` | PR reviews JSON array on stdin (`GET /repos/{repo}/pulls/{n}/reviews`, oldest-first) | `0` if the PR has a current APPROVED review, else `1` |
| `auto_rebase_has_ready_label LABEL` | PR labels JSON array on stdin | `0` if a label named `LABEL` is present, else `1` |
| `auto_rebase_pr_eligible MODE IS_DRAFT IS_APPROVED HAS_LABEL` | mode + three `true`/`false` strings | `0` eligible, `1` not eligible, `2` unknown mode |

### Approval semantics

`auto_rebase_has_current_approval` inspects the **actual review states**, not
`reviewDecision` (which is `null` on repos without required reviews). The most
recent *decision* review per reviewer wins — a later `CHANGES_REQUESTED` or
`DISMISSED` cancels an earlier `APPROVED`, while `COMMENTED`/`PENDING` reviews
do not change a reviewer's stance.

### Eligibility modes (the tunable `eligibility` workflow input)

| Mode | Meaning |
|------|---------|
| `review-ready` (default) | non-draft **AND** (current approval **OR** carries the ready label) |
| `all` | every behind PR, including drafts — restores the original unrestricted fan-out |

New modes (e.g. a future "front-of-queue N") can be added here and selected by
callers via the `eligibility` input with no change to the workflow file.
