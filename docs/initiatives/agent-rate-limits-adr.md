# ADR: Agent Rate-Limit & Circuit-Breaker Taxonomy (mechanism + policy decision)

- **Status:** Proposed (pending human sign-off on §6 numbers, §7 token-breaker threshold, and the §9 cost cap)
- **Date:** 2026-08-21
- **Epic:** [#636](https://github.com/petry-projects/.github/issues/636)
- **Story:** [#637](https://github.com/petry-projects/.github/issues/637) — Phase 1 (decision record only)
- **Scope of this story:** documentation only. **No** workflow, config file, repo
  setting, or org policy is mutated here (AC #1).

This ADR pins down *how* an org can bound agentic throughput — per-agent-type
controls, a token-budget circuit breaker, the telemetry that feeds them, and the
public/private enforcement boundary — so the follow-on stories (config
single-source-of-truth, source-side gate, and the two wiring stories) encode a
**verified** mechanism instead of guessing APIs or baking in unconfirmed numbers.
It deliberately mirrors the proven staging of the Pull-Request-Limits ADR
([`docs/initiatives/pull-request-limits-adr.md`](pull-request-limits-adr.md),
epic #505 → ADR #506 → config #507 → apply path #508).

---

## 1. Context — why this decision is needed (AC #1)

Agentic automation in this org runs on a schedule and on event fan-out with **no
throughput ceiling of its own.** Three production incidents are the measured
baseline this standard must prevent — cited here as symptoms of missing
throughput controls, **not** as bugs to fix in this story:

| Incident | Symptom | Root cause class |
|---|---|---|
| [#402](https://github.com/petry-projects/.github/issues/402) | A concurrency-group `cancel-in-progress` cancelled in-flight dev-lead issue pickups → **111 stuck issues**. | A single-lane serializer used as if it were a queue; cancellation instead of back-pressure. |
| [#443](https://github.com/petry-projects/.github/issues/443) | Dispatch race between event and schedule fan-out. | No cooldown / de-dupe between overlapping triggers. |
| [#571](https://github.com/petry-projects/.github/issues/571) | feature-ideation zero-job dispatch (reusable `with:` referencing `inputs` on an event where the job is gated off). | No admission/gating discipline around dispatch. |

The external framing is **OWASP ASI08 — Denial of Service & Resource
Exhaustion** (OWASP Top 10 for Agentic Applications, 2026): an agent fleet with
no self-imposed rate limit can exhaust a shared, finite resource — here the
**rolling 5-hour Claude subscription budget** shared across every Claude-backed
agent — and starve the very pipeline that would repair it (the self-hosting
circular dependency already documented in
[`docs/initiatives/agent-canary-rings-adr.md`](agent-canary-rings-adr.md)).

The planner's working assumption was that GitHub or the Claude platform ships a
first-party "per-workflow rate limiter" and a "5-hour budget %" surface, and that
we just need to find the API. **This ADR's first job was to verify that
assumption against the vendors' own docs rather than guess** (org standard: *"SHAs
for action pinning must be looked up via the GitHub API — never guessed"*,
[CLAUDE.md](../../CLAUDE.md); the same skepticism applies to any API surface —
[AGENTS.md](../../AGENTS.md)).

---

## 2. Decision (summary)

1. **In scope: four agent types** — `dev-lead`, `compliance-audit`,
   `feature-ideation`, `initiative-driver` — each bounded on five control
   dimensions: **max concurrent runs, max runtime, cooldown between runs, daily
   execution budget, and a consecutive-failure circuit breaker**
   (open → backoff → half-open). See §5 for the taxonomy and §6 for the proposed
   values (proposals, not final).
2. **GitHub exposes no native per-workflow rate limiter and no run-count budget.**
   Verified first-hand (§4): the `concurrency:` key is a **single-lane
   serializer**, not a rate limiter — it caps *simultaneity*, not *rate over a
   window*, and its `cancel-in-progress` is exactly the lever that caused #402.
   There is no repo/org setting or ruleset rule that caps runs-per-hour or
   runs-per-day. Therefore the per-agent-type controls are **source-side**, in the
   dispatch/engine layer, not a GitHub toggle — the same conclusion the
   PR-Limits ADR reached for open-PR caps.
3. **The Claude platform exposes no rolling 5-hour "subscription budget %"
   surface.** Verified first-hand (§4): the Messages API exposes **per-minute**
   token-bucket limits via `anthropic-ratelimit-*` response headers and a
   Rate Limits API for *configured* limits — but **no 5-hour window and no
   subscription-budget percentage.** The 5-hour rolling window is a **Claude
   Pro/Max subscription** concept (shared across Claude + Claude Code, surfaced
   interactively via `/status`), with **no pollable programmatic surface.** The
   org's agents authenticate with the subscription-backed
   `CLAUDE_CODE_OAUTH_TOKEN` (verified in the workflow stubs, §4), so the budget
   that matters is precisely the one with no native telemetry.
4. **The token-budget breaker's telemetry must therefore be *derived*, not
   *queried*** — and it can only be derived where the token accounting lives: the
   private engine (`petry-projects/.github-private` `scripts/engine.sh`,
   subscription-cap handling, [#206](https://github.com/petry-projects/.github/issues/206)).
   Today that engine reacts **after** a rate-limit (exit-2 walks the model
   fallback chain); a *proactive* breaker requires it to record per-run token
   usage + rate-limit timestamps into private state. This splits enforcement
   across a **public standard/gate** (this epic) and a **private companion
   change** (§8).
5. All numeric values in §6, the §7 default threshold, and the §9 cost cap are
   **proposals pending human sign-off**, not final numbers.

> If a reviewer knows of a GitHub per-workflow rate-limit feature, or a
> programmatic Claude endpoint that returns remaining 5-hour subscription budget,
> that those doc surfaces do not describe, that is the one gap this story could
> not close from inside CI (§10). Re-open §2 with the citation if so.

---

## 3. In-scope agent types (AC #2)

Each is a real, deployed org automation whose caller stub was read first-hand for
this ADR (paths below). The "where behavior/concurrency lives today" column is
where the enforceable control must land given §2.2 (no GitHub-side surface).

| Agent type | Caller (this repo) | Trigger surface | Where behavior/concurrency lives today | Auth |
|---|---|---|---|---|
| **dev-lead** | [`standards/workflows/dev-lead.yml`](../../standards/workflows/dev-lead.yml) | PR / review / comment / `issues: labeled` / `check_run` / `repository_dispatch` | Reusable `dev-lead-reusable.yml` (private): per-issue / per-PR concurrency lanes added after #402 | `CLAUDE_CODE_OAUTH_TOKEN` |
| **compliance-audit** | [`.github/workflows/compliance-audit-and-improvement.yml`](../../.github/workflows/compliance-audit-and-improvement.yml) | weekly `schedule` (Fri 12:00 UTC) + `workflow_dispatch` | `concurrency: compliance-audit`, `cancel-in-progress: false`; `audit` job `timeout-minutes: 30` | `ORG_SCORECARD_TOKEN` (deterministic job) + Claude phase |
| **feature-ideation** | [`standards/workflows/feature-ideation.yml`](../../standards/workflows/feature-ideation.yml) | weekly `schedule` (Fri 07:00 UTC) + `workflow_dispatch` + `discussion` | `concurrency: feature-ideation`, `cancel-in-progress: false`; `prep`/`redispatch` `timeout-minutes: 5` | `CLAUDE_CODE_OAUTH_TOKEN` |
| **initiative-driver** | [`standards/workflows/initiative-driver.yml`](../../standards/workflows/initiative-driver.yml) | `issues: [closed, labeled]` + off-peak `schedule` + `workflow_dispatch` | per-repo `concurrency` lane, `cancel-in-progress: true`; dispatch job `timeout-minutes: 5`; **max-in-flight lives in the central driver** (private) | dispatch-only stub; Claude runs in dev-lead it hands off to |

Two facts from this table shape the whole design:

- **The controllable throttle points are already partly in place but are the
  *wrong kind*** — `concurrency` groups bound simultaneity, and `timeout-minutes`
  bounds a single run's wall-clock. Neither bounds *rate over time*, *cooldown*,
  or *daily budget*, and `cancel-in-progress` actively harms (§1, #402).
- **initiative-driver itself runs no LLM** (pure-bash dispatcher); its cost is
  the **dev-lead fan-out it triggers.** Its control dimension is therefore a
  **dispatch budget** (how many sub-issues it releases per window), enforced in
  the central driver, not a per-run LLM budget.

---

## 4. Mechanism research — what the vendors actually expose (AC #4)

Every surface below was fetched **first-hand** during this story (2026-08-21) and
read for a field that caps *rate over a window* or exposes a *5-hour budget*.

| Surface | Source consulted | Result |
|---|---|---|
| **GitHub Actions `concurrency`** | [Using concurrency](https://docs.github.com/en/actions/using-jobs/using-concurrency) | Controls **simultaneous execution only.** The key ensures "only one workflow or job with that key runs at any given time"; `cancel-in-progress` cancels the in-flight run (the #402 lever); `queue: max` allows up to 100 *pending* runs FIFO. **No per-hour/daily execution budget, no run-count-over-time limit, no cost/token telemetry.** |
| **Claude Messages API rate limits** | [Rate limits](https://platform.claude.com/docs/en/api/rate-limits) | Two limit types: **monthly spend cap** and **per-minute** rate limits (RPM / ITPM / OTPM) via a **token-bucket** (continuously replenished, *not* fixed-window). Exposes `anthropic-ratelimit-{requests,tokens,input-tokens,output-tokens}-{limit,remaining,reset}` response headers (reset = RFC 3339) and `retry-after` on 429. **No 5-hour window; no rolling-budget-% surface.** |
| **Claude Rate Limits API** | [Rate Limits API](https://platform.claude.com/docs/en/manage-claude/rate-limits-api) | Reads the org/workspace's *configured* limits programmatically. Returns configured ceilings, **not** live remaining budget for a 5-hour window. |
| **Claude Pro/Max subscription usage** | [Using Claude Code with your Pro/Max plan](https://support.claude.com/en/articles/11145838-using-claude-code-with-your-pro-or-max-plan) | Confirms "usage limits … shared across Claude and Claude Code" and an **interactive** `/status` command that shows "remaining allocation." **No programmatic/CI-pollable endpoint** for the remaining subscription budget is documented. |

**Conclusion (AC #4):** there is **no native GitHub surface** for per-workflow
rate limiting, and **no native Claude surface** that exposes the rolling 5-hour
*subscription* budget. The nearest real signals are:

1. **`anthropic-ratelimit-*` response headers** — a genuine, first-hand token
   signal, but **per-minute and API-key-scoped**, and the org's agents run on the
   **subscription OAuth token**, whose 5-hour window these headers do not report.
2. **The 429 + `retry-after` back-pressure** the engine already sees on cap
   exhaustion (the reactive signal behind #206's exit-2 fallback).

**Selected concrete alternative (the telemetry source of record):** because no
vendor surface reports the 5-hour subscription budget, the breaker's telemetry is
**derived source-side in the private engine.** `scripts/engine.sh` (which already
handles the subscription cap, #206) records, per agentic run, the tokens consumed
and the timestamp of any rate-limit/429, into a **private rolling-window ledger**
keyed to the 5-hour window. The proactive breaker (§7) reads that ledger. This is
the only place the accounting exists; it cannot be read from the public repo — the
basis for the §8 boundary. Where an agent path uses an **API key** rather than the
subscription token, the `anthropic-ratelimit-tokens-remaining` header is the
authoritative live signal and the ledger should prefer it over estimation.

---

## 5. Per-agent-type control taxonomy (AC #2)

Five control dimensions per agent type. Definitions (uniform across types):

- **Max concurrent runs** — hard cap on simultaneous runs of this agent type.
  Implemented as a *counted* admission check, **not** a `cancel-in-progress`
  concurrency group (which cancels, per #402). Over the cap → **defer**, never
  cancel.
- **Max runtime** — wall-clock ceiling per run. `timeout-minutes` is the native,
  verified lever (§3) and is sufficient for this dimension.
- **Cooldown between runs** — minimum quiet interval after a run of this type
  before another may start, to kill dispatch races (#443) and event/schedule
  double-fire.
- **Daily execution budget** — max runs (or, for initiative-driver, max
  dispatches) per rolling 24h, independent of concurrency.
- **Consecutive-failure circuit breaker** — after *N* consecutive failed runs the
  breaker **opens** (no new runs); after a **backoff** it goes **half-open**
  (a single probe run); a passing probe **closes** it, a failing probe re-opens
  with escalated backoff.

| Dimension | dev-lead | compliance-audit | feature-ideation | initiative-driver |
|---|---|---|---|---|
| Max concurrent runs | per-issue / per-PR lane (already) + a global type cap | 1 (already single-lane, non-cancelling) | 1 (already single-lane, non-cancelling) | 1 dispatch lane per repo (already) |
| Max runtime | per-run `timeout-minutes` (add to reusable) | 30 min audit job (already) | 5 min prep; add cap to `ideate` | 5 min dispatch (already) |
| Cooldown between runs | between issue pickups | n/a (weekly cron) | n/a (weekly cron) | between close-event + schedule fan-out (directly targets #443) |
| Daily execution budget | runs/day cap | n/a (weekly) | n/a (weekly) | **dispatches/day** (bounds the dev-lead fan-out it causes) |
| Consecutive-failure breaker | open→backoff→half-open | same | same | same |

Cells marked "already" are existing, verified levers (§3); the standard's job is
to make them **uniform, named, and single-sourced**, and to add the missing
dimensions (global concurrency cap, cooldown, daily budget, failure breaker) at
the source layer.

---

## 6. Proposed values — PROPOSALS, NOT FINAL (AC #2)

> Everything here is a **proposal pending human sign-off** (epic #636 gate),
> anchored to the §1 baseline and current cadence — not to any vendor-imposed
> maximum (none exists, §4).

| Dimension | dev-lead | compliance-audit | feature-ideation | initiative-driver |
|---|---|---|---|---|
| Max concurrent runs | 3–4 global | 1 | 1 | 1 / repo |
| Max runtime | 30 min | 30 min (keep) | 20 min | 5 min (keep) |
| Cooldown | 2–5 min between pickups | n/a | n/a | 10 min |
| Daily budget | 40–60 runs/day | 1 (weekly) | 1 (weekly) | 20 dispatches/day |
| Failure breaker | open after 3 consecutive; backoff 30 min → half-open | 3 → 60 min | 3 → 60 min | 3 → 30 min |

Final values, and whether dev-lead's cap is global vs. per-repo, are **deferred to
human sign-off** before the config story.

---

## 7. Token-budget circuit breaker (AC #3)

The dimension the discussion specifically requested, distinct from the
per-agent-type breaker in §5.

- **Trigger:** pause **new agentic dispatch** when the rolling **5-hour Claude
  subscription budget** reaches a **configurable threshold (default 90%)** of
  consumed budget. The window is the subscription's own 5-hour rolling window
  (§4), not a per-minute API bucket.
- **State machine:** **open** at ≥ threshold → hold new dispatch; **half-open** as
  the rolling window drains back below a lower resume mark (hysteresis, e.g. 80%,
  to avoid flapping at the boundary) → admit a limited probe of dispatch;
  **closed** once comfortably below.
- **Priority on recovery:** when the window drains and dispatch resumes,
  **Claude-backed agents are prioritized** (dev-lead, feature-ideation, and the
  Claude phase of compliance-audit) over lower-value/again-deferrable work, so the
  recovering budget is spent on the pipeline that clears the backlog first.
  initiative-driver dispatch (which *causes* Claude spend downstream) resumes
  after the Claude-backed direct consumers.
- **Telemetry:** the derived private ledger of §4 — there is no native surface to
  poll. The threshold is read from config (the config story), never hardcoded.
- **Fail-safe direction:** the breaker is **fail-open on telemetry error** (a
  ledger read failure must not wedge the whole fleet), matching the fail-open
  posture of the PR-Limits gate; but it is **fail-closed on a fresh 429 +
  `retry-after`** (a hard, first-hand signal that the cap is already hit).

The default 90% threshold, the 80% resume mark, and the exact priority order are
**proposals pending sign-off.**

---

## 8. Cross-repo enforcement boundary (AC #5)

Enforcement splits across two repos. Getting this boundary explicit is the whole
point of a decision record before the config/gate stories.

### 8.1 Lands in the **public** standard/gate (this epic)

- The **standard** (`standards/agent-rate-limits.md`, human-readable) and the
  **single-source-of-truth config** (`standards/agent-rate-limits.json`,
  machine-readable) — the taxonomy of §5, the values of §6, the §7 threshold, the
  §9 metrics/cap. Mirrors the PR-Limits split
  ([`standards/pr-limits.md`](../../standards/pr-limits.md) +
  `standards/pr-limits.json`).
- A **source-side gate library** (`scripts/lib/…`) that reads the config and
  answers admission questions — the per-type concurrency/cooldown/daily-budget
  and failure-breaker checks that need only public inputs (run counts,
  timestamps, failure counters derivable from the GitHub API), analogous to
  [`scripts/lib/pr-limit-gate.sh`](../../scripts/lib/pr-limit-gate.sh).
- The caller stubs in [`standards/workflows/`](../../standards/workflows/) stay
  **thin** (AGENTS.md rule); they gain no new logic — behavior lives in the
  reusable/engine and is promoted centrally via the canary channel
  ([agent-canary-rings-adr](agent-canary-rings-adr.md)).

### 8.2 Requires a **private** companion change (`petry-projects/.github-private`)

- The **token-budget breaker's telemetry** (§4/§7): only `scripts/engine.sh`
  sees per-run token usage and the subscription 429s (#206). The **5-hour rolling
  ledger and the proactive breaker read** must be built there. The public gate
  can encode the *threshold and policy*, but the *live budget number* is private.
- **dev-lead's per-issue lanes and the initiative-driver max-in-flight** already
  live in the private reusable/central driver (§3); the new concurrency-cap,
  cooldown, and failure-breaker wiring for those two attach there.
- **Wiring stories** (the two follow-ons after config + gate) are therefore
  cross-repo: one wires the public gate into the private engine's dispatch path;
  the other builds the private 5-hour ledger + proactive breaker and points it at
  the public threshold config.

> **Boundary rule of thumb:** *policy and any control computable from public
> GitHub state* → public gate; *anything that needs the token ledger or the
> subscription 429 stream* → private engine. The public repo owns the numbers and
> the decision; the private repo owns the budget telemetry.

---

## 9. Initiative success metrics & cost cap (AC #6)

Pinned here so Phases 2–5 inherit them (proposals pending sign-off):

### 9.1 Success metrics

- **Zero recurrences** of the #402-class incident: no agent run is ever
  *cancelled* mid-flight by a throughput control (deferral only) → target **0
  stuck-issue events** attributable to concurrency cancellation.
- **No dispatch races** (#443-class) or zero-job dispatches (#571-class) after the
  cooldown/admission discipline lands.
- **Budget headroom:** the 5-hour subscription budget stays **below the §7
  threshold** in normal operation; when it trips, Claude-backed agents recover
  first and the backlog clears without manual intervention.
- **Bounded fan-out:** initiative-driver never releases more than its daily
  dispatch budget, so a single epic cannot flood dev-lead (the §1 fan-out risk).

### 9.2 Operational cost cap the standard installs

- A single, config-declared **org-wide agentic dispatch ceiling** (the aggregate
  daily-budget sum across types) is the standing cost cap. It is expressed in
  `standards/agent-rate-limits.json` and read at run time — changing it is a
  config edit, not a redeploy (mirroring PR-Limits §6.1). The **concrete number is
  deferred to human sign-off**; this ADR fixes only that the cap exists, is
  single-sourced, and is enforced source-side.

---

## 10. Residual gap / what this story could not close (AC #4 honesty)

- **WebSearch was not used;** the four surfaces in §4 were fetched **first-hand**
  via documentation URLs (GitHub Actions concurrency; Claude rate-limits;
  Rate Limits API; Pro/Max subscription support article) and are the basis for the
  decision. The Anthropic docs host redirected `docs.anthropic.com` →
  `platform.claude.com` and `support.anthropic.com` → `support.claude.com`; both
  redirects were followed and the canonical pages read.
- **The 5-hour window's exact mechanics are not publicly documented** at a
  programmatic level — the subscription support page confirms the *existence* of
  shared usage limits and the interactive `/status` view, but no page exposes a
  pollable "remaining 5-hour budget" API. §4's selected alternative (derive it in
  the private engine) stands on that verified absence. If Anthropic later ships a
  subscription-budget endpoint, §7's telemetry source should be revisited to
  prefer it over the derived ledger.

---

## 11. Consequences

- The follow-on stories are **build, not configure**: like PR-Limits, there is no
  vendor toggle to flip — the work is a source-side gate, a private token ledger,
  and thin, centrally-promoted wiring.
- The §6/§7/§9 numbers are explicitly provisional; the config story starts from a
  human-signed set.
- `cancel-in-progress` is recorded as an **anti-pattern** for throughput control
  (it cancels, per #402); all new controls **defer**, never cancel.
- The design is cross-repo by necessity (§8): the public repo cannot see the
  budget telemetry, so the token breaker cannot be fully implemented in this epic
  alone — a private companion change is a named dependency, not a surprise.

## 12. References

- [`docs/initiatives/pull-request-limits-adr.md`](pull-request-limits-adr.md) — the staged-epic ADR template mirrored here.
- [`docs/initiatives/agent-canary-rings-adr.md`](agent-canary-rings-adr.md) — the self-hosting circular-dependency + central-promotion model.
- [`standards/pr-limits.md`](../../standards/pr-limits.md) / [`scripts/lib/pr-limit-gate.sh`](../../scripts/lib/pr-limit-gate.sh) — the standard + source-side gate pattern to reuse.
- The four in-scope caller stubs (read first-hand):
  - [`standards/workflows/dev-lead.yml`](../../standards/workflows/dev-lead.yml)
  - [`standards/workflows/feature-ideation.yml`](../../standards/workflows/feature-ideation.yml)
  - [`standards/workflows/initiative-driver.yml`](../../standards/workflows/initiative-driver.yml)
  - [`.github/workflows/compliance-audit-and-improvement.yml`](../../.github/workflows/compliance-audit-and-improvement.yml)
- [AGENTS.md](../../AGENTS.md) / [CLAUDE.md](../../CLAUDE.md) — the "never guess an API surface" org rule.
- GitHub docs: [Using concurrency](https://docs.github.com/en/actions/using-jobs/using-concurrency).
- Claude docs (fetched first-hand):
  - [Rate limits](https://platform.claude.com/docs/en/api/rate-limits)
  - [Rate Limits API](https://platform.claude.com/docs/en/manage-claude/rate-limits-api)
  - [Using Claude Code with your Pro/Max plan](https://support.claude.com/en/articles/11145838-using-claude-code-with-your-pro-or-max-plan)
- Cross-repo: `petry-projects/.github-private` `scripts/engine.sh` — 5-hour subscription-cap handling ([#206](https://github.com/petry-projects/.github/issues/206)).
- Baseline incidents: [#402](https://github.com/petry-projects/.github/issues/402), [#443](https://github.com/petry-projects/.github/issues/443), [#571](https://github.com/petry-projects/.github/issues/571).
- External framing: OWASP Top 10 for Agentic Applications (2026), **ASI08 — Denial of Service & Resource Exhaustion**.
