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
| [`release-channel-tags.json`](release-channel-tags.json) | `release-channel-tags` | `refs/tags/**` | Blocks unauthorized **update/deletion** of any tag (protects moving channel pointers + version tags); creation stays free |

`pr-quality` / `code-quality` carry the two mandatory bypass actors —
`OrganizationAdmin` and the `dependabot-automerge-petry` Integration app (id
`3167543`), both `bypass_mode: always`. `release-channel-tags` additionally grants
bypass to the **release-manager** Integration app (id `4193127`) so channel promotion
and dev-lead autocut can move channel tags.

## Applying

These files are the **desired-state source of truth**. `scripts/apply-rulesets.sh`
creates/updates the named ruleset on a target repo to match — re-running is a no-op
when already in sync. Rulesets live **on each repo**; editing a file here changes the
desired state, not any live ruleset, until the applier runs.

```bash
# Preview the payload for one repo (no writes):
GH_TOKEN=<admin-token> bash scripts/apply-rulesets.sh <repo> --dry-run
```

## Scope boundary

- **Org standards → here.** All ruleset definitions are org standards owned by
  `.github`. `pr-quality` / `code-quality` are applied **fleet-wide** (the default
  set); `release-channel-tags` is an org standard but **targeted** — applied only to
  the reusable-hosting meta-repos (`.github`, `.github-private`), whose tags are all
  release-management tags. It is applied by name, never swept fleet-wide:

  ```bash
  GH_TOKEN=<admin> bash scripts/apply-rulesets.sh --repo petry-projects/.github release-channel-tags
  GH_TOKEN=<admin> bash scripts/apply-rulesets.sh --repo petry-projects/.github-private release-channel-tags
  ```

- **The default (no-name) set is the `FLEET_RULESETS` allowlist**, *not* every
  `*.json` here — so adding a targeted ruleset like `release-channel-tags` never
  leaks into `--all` / `--repo` fleet runs.

## Changing the required-check set

Adding a required status-check context to `code-quality.json` makes it a **merge
gate on every repo the ruleset targets**. A repo that does not *produce* that check
is bricked (the required check never reports). Sequence any additions safely: ship
the producing CI job fleet-wide first, then add the context here. Keep stricter sets
scoped to the template / new repos until the fleet backfill lands.
