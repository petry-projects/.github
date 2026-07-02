# Repository Rulesets — codified source of truth

This directory holds the **org-wide compliance ruleset JSONs** for `petry-projects`.
`.github` owns org-wide standards and compliance policy; its canonical home is
`standards/`. See [`AGENTS.md`](../../AGENTS.md#organization-standards) for the
repo-boundary rule (codified in petry-projects/.github#576) and
[`standards/github-settings.md`](../github-settings.md#repository-rulesets) for how
these rulesets are enforced.

| File | Ruleset | Target | Enforces |
|------|---------|--------|----------|
| [`pr-quality.json`](pr-quality.json) | `pr-quality` | `~DEFAULT_BRANCH` | 1 approval, code-owner review, thread resolution, dismiss-stale, squash-only merge |
| [`code-quality.json`](code-quality.json) | `code-quality` | `~DEFAULT_BRANCH` | Required status checks (SonarCloud, CodeQL, agent-shield, dependency-audit) |

Both carry the two mandatory bypass actors — `OrganizationAdmin` and the
`dependabot-automerge-petry` Integration app (id `3167543`), both `bypass_mode: always`.

## Applying

`scripts/apply-rulesets.sh` reads these files and creates/updates the named ruleset
on a target repo — re-running converges to the file's desired state (a no-op when
already in sync). Rulesets live **on each repo**; editing a file here changes the
desired state, not any live ruleset, until the applier runs.

```bash
# Preview the payload for one repo (no writes):
RULESETS_REPO=petry-projects/<repo> DRY_RUN=true bash scripts/apply-rulesets.sh
```

## Scope boundary

- **Fleet-wide → here.** `pr-quality` / `code-quality` are org-wide policy.
- **Protects an agent/skill's own assets → stays in `.github-private`.**
  `release-channel-tags` lives in `petry-projects/.github-private` because it
  protects that repo's own `pr-review/**` and `dev-lead/**` release tags.

## Changing the required-check set

Adding a required status-check context to `code-quality.json` makes it a **merge
gate on every repo the ruleset targets**. A repo that does not *produce* that check
is bricked (the required check never reports). Sequence any additions safely: ship
the producing CI job fleet-wide first, then add the context here. Keep stricter sets
scoped to the template / new repos until the fleet backfill lands.
