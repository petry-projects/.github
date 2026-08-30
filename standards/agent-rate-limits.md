# Standard — Agent Rate Limits & Circuit Breakers

Org-wide policy for bounding agentic throughput: the per-agent-type rate limits
and circuit breakers, the org-wide Claude token-budget breaker, the single source
of truth for their configured values, and which actors are intentionally exempt.

This standard is the human-readable companion to the machine-readable config in
[`standards/agent-rate-limits.json`](agent-rate-limits.json). It exists so a
compliance audit — and any contributor — reads the limits and their exemptions as
**sanctioned policy, not misconfiguration or drift**.

- **Decision record (why this exists / the verified mechanism):**
  [`docs/initiatives/agent-rate-limits-adr.md`](../docs/initiatives/agent-rate-limits-adr.md)
  (Phase 1, [#637](https://github.com/petry-projects/.github/issues/637)).
- **Single source of truth (the values):**
  [`standards/agent-rate-limits.json`](agent-rate-limits.json) (Phase 2,
  [#638](https://github.com/petry-projects/.github/issues/638)).
- **Apply path (where it will be enforced):** a source-side gate library
  (`scripts/lib/agent-rate-limit.sh`) is Phase 3; the private telemetry adapter +
  wiring are Phases 4–5 (ADR §8). **Nothing reads this config yet** — see §3.

---

## 1. What is limited

Two complementary controls, both drawn from the ADR taxonomy (§5, §7):

- **Per-agent-type controls.** Each in-scope agent type
  (`dev-lead`, `compliance-audit`, `feature-ideation`, `initiative-driver`) is
  bounded on five dimensions: **max concurrent runs, max runtime, cooldown
  between runs, a daily execution budget, and a consecutive-failure circuit
  breaker** (open → backoff → half-open probe). Over a limit → **defer**, never
  cancel — `cancel-in-progress` is recorded as an anti-pattern (it cancelled 111
  in-flight issue pickups in incident #402; ADR §1).
- **The org-wide token-budget breaker.** A single breaker over the shared Claude
  subscription budget that pauses new agentic dispatch when a **fixed** usage
  window crosses a threshold, prioritizing Claude-backed agents on recovery
  (§4 below).

Why limits at all: agentic automation in this org runs on schedules and event
fan-out with no throughput ceiling of its own, and can exhaust the shared,
finite 5-hour Claude subscription budget — starving the very pipeline that would
repair it (OWASP ASI08; ADR §1).

## 2. Source of truth — the configured values

The per-agent limits, the token-budget thresholds, and the exempt lists live
**only** in [`standards/agent-rate-limits.json`](agent-rate-limits.json). This
document deliberately does **not** restate any of the numbers: a changeable value
stated in prose is a second place to forget to update. To read a current value,
read the config — for example:

```bash
# Every per-agent daily execution budget (the per-agent cost bound; see §5):
jq '.agent_types | map_values(.daily_run_budget)' standards/agent-rate-limits.json

# The 5-hour session pause threshold and the Claude-priority flag:
jq '.org_wide.token_budget.limits.session.pause_threshold_pct,
    .org_wide.token_budget.claude_priority' standards/agent-rate-limits.json
```

The config carries its own inline `_note` fields recording the sign-off state and
the ADR rationale for each value. Consumers (the Phase-3 gate and any future
dispatch path) **must** read values from this file — never hardcode them.

Its contract (parseable JSON, required keys present, per-agent numeric limits are
positive integers, each agent carries a circuit breaker, the session threshold is
in range, only account-wide windows are pause-worthy, and no percentage resume
mark exists) is guarded by
[`tests/test_agent_rate_limits_config.bats`](../tests/test_agent_rate_limits_config.bats),
run in CI by
[`.github/workflows/agent-rate-limits-tests.yml`](../.github/workflows/agent-rate-limits-tests.yml).

## 3. Status — inert pending human sign-off

Like the pr-limits config before its own sign-off gate, **every number in this
file is a proposal (`status: provisional`) pending human sign-off** (epic
[#636](https://github.com/petry-projects/.github/issues/636) gate). The config is
**inert on merge**: no workflow, gate, or engine reads it in the Phase-2 story
that adds it ([#638](https://github.com/petry-projects/.github/issues/638)). The
Phase-3 gate library and the Phase-4/5 wiring consume it later, only after the
values are signed off. This mirrors the PR-Limits staging exactly (ADR §7,
[`pr-limits.md`](pr-limits.md)).

## 4. The token-budget breaker

The breaker reads the shared Claude subscription budget through the OAuth usage
endpoint that is the telemetry **source of record** (ADR §4.1); because that
endpoint authenticates with a credential that lives in
`petry-projects/.github-private`, the **live budget read and the pause actuation
are private** — this public file holds only the thresholds and the policy (ADR
§8). The threshold values themselves are in the config; the properties that must
not drift into prose-restated numbers, but that a reader must understand, are:

- **The windows are FIXED, not rolling.** The 5-hour `session` window and the
  7-day `weekly_all` window each carry an authoritative `resets_at`. Within a
  window utilization is **monotonically non-decreasing**; the only event that
  lowers it is the reset. (The per-minute `anthropic-ratelimit-*` API bucket is a
  different mechanism and *is* continuously replenished — do not conflate them.)
- **There is no percentage resume mark.** Because a downward percentage dip cannot
  occur inside a fixed window, a resume/hysteresis mark would be unreachable by
  construction and is deliberately absent (ADR §7). The `session` breaker closes
  only at its `resets_at`; the `weekly_all` glide-path breaker closes at
  `resets_at` **or** when its time-varying threshold rises past a static
  utilization — never because usage fell.
- **Only account-wide windows are pause-worthy.** `session` and `weekly_all` are
  pause-worthy; `weekly_scoped` (per-model exhaustion) is handled by the engine's
  model-fallback chain and **never** trips a fleet pause (ADR §2.5). The config
  encodes this distinction on each limit kind rather than leaving it to the
  consumer.
- **Claude-priority on recovery.** When a window drains and dispatch resumes,
  Claude-backed agents are prioritized so the recovering budget clears the backlog
  first (the `claude_priority` flag).
- **Fail-safe direction.** On telemetry error the breaker **allows** dispatch and
  logs a warning — an outage of an undocumented third-party endpoint must never
  stop the fleet (ADR §7). This is policy the gate will honor; it is not itself a
  value in this file.

## 5. The daily budget is the per-agent cost bound

The per-agent **`daily_run_budget`** key is the concrete, config-declared cost
bound for each agent type: the maximum runs (for `initiative-driver`, dispatches —
ADR §3) that agent may perform per rolling 24h, independent of concurrency. The
epic's operational cost cap is therefore traceable to a specific config key rather
than to prose: the standing org-wide agentic dispatch ceiling is the aggregate of
these per-agent `daily_run_budget` values (ADR §9.2). Changing the cap is a config
edit to this key, not a redeploy — read the values with:

```bash
jq '.agent_types | map_values(.daily_run_budget)' standards/agent-rate-limits.json
```

## 6. Exempt actors — sanctioned, not a misconfiguration

Some agent runs must **never** be blocked or deferred by these limits. The exempt
actors and labels are listed in `exempt_actors` / `exempt_labels` in
[`standards/agent-rate-limits.json`](agent-rate-limits.json) and are the **same
set** as [`standards/pr-limits.json`](pr-limits.json), so one policy governs both
gates. A compliance audit encountering these actors on the exempt list should
treat them as policy, not drift.

| Exempt entry | Kind | Why it is exempt |
|---|---|---|
| `dependabot[bot]` | actor | Already bounded per-ecosystem by `open-pull-requests-limit`; security update runs must never be starved by a general throttle. |
| `OrganizationAdmin` | actor | Human break-glass / admin runs. |
| `@petry-projects/org-leads` | actor | Maintainer traffic — human review, not automation backlog. |
| `dependabot-automerge-petry` | actor (App) | Operates on *existing* PRs; it does not add agentic run volume. |
| `security` | label | Urgent security / hotfix work bypasses any throttle. |

To change this list, follow the runbook in §7.2. Keep this table in sync with the
config so the human-readable rationale does not drift from the machine-readable
list (the same discipline as [`pr-limits.md`](pr-limits.md) §4).

## 7. Operator runbook

All changes here are edits to the single source of truth
[`standards/agent-rate-limits.json`](agent-rate-limits.json), gated by the config
tests. While the config is inert (§3), an edit changes no runtime behavior; once
the values are signed off and the Phase-3+ consumers are wired, enforcement is
source-side and reads the file at run time, so a change takes effect on merge with
no separate apply step (mirroring [`pr-limits.md`](pr-limits.md) §6).

### 7.1 Change a limit

1. Edit the relevant key in
   [`standards/agent-rate-limits.json`](agent-rate-limits.json). Update the
   adjacent `_note` to record the new rationale and sign-off — keep the value out
   of any other prose, this file is the only place it should appear.
2. Validate the contract locally:

   ```bash
   bats --print-output-on-failure tests/test_agent_rate_limits_config.bats
   ```

3. Open a PR. CI
   ([`.github/workflows/agent-rate-limits-tests.yml`](../.github/workflows/agent-rate-limits-tests.yml))
   re-runs the config contract test.

### 7.2 Add or remove an exempt actor

1. Edit the `exempt_actors` array (or `exempt_labels` for a label) and add a short
   justification to `_exempt_note`, matching the style of the existing entries.
2. Keep §6 of this document in sync with the config, and keep the set aligned with
   [`standards/pr-limits.json`](pr-limits.json) unless there is a documented reason
   to diverge.
3. Validate and open a PR as in §7.1.

## 8. References

- [`docs/initiatives/agent-rate-limits-adr.md`](../docs/initiatives/agent-rate-limits-adr.md)
  — decision record (Phase 1, #637): the verified mechanism, the taxonomy, and the
  proposed values this config encodes.
- [`standards/agent-rate-limits.json`](agent-rate-limits.json) — single source of
  truth (Phase 2, #638).
- [`standards/pr-limits.md`](pr-limits.md) / [`standards/pr-limits.json`](pr-limits.json)
  — the sibling standard + config whose single-source-of-truth and
  never-restate-numbers conventions this standard mirrors.
- [`tests/test_agent_rate_limits_config.bats`](../tests/test_agent_rate_limits_config.bats)
  — the config contract test.
