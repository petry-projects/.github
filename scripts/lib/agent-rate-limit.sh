# shellcheck shell=bash
# scripts/lib/agent-rate-limit.sh — Source-side agent admission + circuit-breaker gate
#
# Reusable Bash library implementing the §5/§8.1 source-side mechanism from the
# Agent-Rate-Limit ADR:
#
#   docs/initiatives/agent-rate-limits-adr.md
#
# GitHub exposes no native per-workflow rate limiter and no run-count budget (ADR
# §2/§4), so per-agent-type throttling is enforced at the automation *source*:
# before an agent-creating workflow (dev-lead / initiative-driver / feature-
# ideation / compliance-audit) dispatches a run, it asks this gate whether the
# agent type may run right now. The gate evaluates four admission dimensions plus
# a consecutive-failure circuit breaker, reading every threshold from the config
# single source of truth (standards/agent-rate-limits.json), and returns allow or
# defer — it never cancels an in-flight run (`cancel-in-progress` is the #402
# anti-pattern; ADR §1).
#
# This library delivers the guard + its tests ONLY. Wiring it into the live
# dispatch path is Phases 4-5 (ADR §8): Phase 4 wires the public gate into the
# private engine's dispatch path; Phase 5 builds the private token-budget breaker.
# It is deliberately wired into no live workflow here (AC #6), mirroring how
# scripts/lib/pr-limit-gate.sh shipped its guard + tests before #508 wired it.
#
# ----------------------------------------------------------------------------
# Caller contract
# ----------------------------------------------------------------------------
# This library is `set -euo pipefail`-safe and designed to be sourced by a parent
# script (`# shellcheck source=scripts/lib/agent-rate-limit.sh`). It does NOT call
# `set` itself and runs nothing at source time.
#
# Reads (all optional, with defaults):
#   - $AGENT_RATE_LIMITS_CONFIG — path to the agent-rate-limits.json single source
#                          of truth (default: <repo>/standards/agent-rate-limits.json,
#                          resolved relative to this file)
#   - $AGENT_RATE_LIMITS_STATE — path to a JSON state document holding per-agent
#                          last-run timestamps, daily counters, and breaker state
#                          (default: unset — treated as empty; degrades to allow)
#   - $SOURCE_NOW        — epoch-seconds override for "now" (testability; default:
#                          `date +%s`)
#   - $DRY_RUN / $DEV_LEAD_DRY_RUN — "true" forces an allow result with no side
#                          effects, after printing the computed decision
#   - `gh` CLI on PATH (for concurrency enumeration), `jq` on PATH
#
# Decision fail-safe direction (ADR §7, post-ADR clarification): malformed,
# missing, or unreadable config/state/telemetry ALLOWS dispatch and logs a
# warning — an outage of a data source must never stop the fleet, which is the
# failure mode this epic exists to prevent. Missing counts degrade to an allowing
# default. (A hard first-hand 429 blocking signal belongs to the token-budget
# breaker of Phases 5/6, not this library.)
#
# Functions are namespaced with the `arl_` prefix to avoid colliding with caller
# helpers.

# Default location of the machine-readable thresholds + exempt list (#638).
# Resolved relative to this library so a caller that sources it from anywhere
# still finds the org single source of truth without hardcoding a path.
ARL_DEFAULT_CONFIG="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/standards/agent-rate-limits.json"

# Stable HTML marker prefix for the deduped, human-clearable open-breaker record
# (mirrors the pr-automation-budget exhaustion marker idiom). The agent type is
# appended so one issue/PR can carry markers for distinct agent types.
ARL_BREAKER_MARKER_PREFIX="<!-- agent-rate-limit-breaker open"

# Human-clearable label a caller applies alongside the marker when the breaker
# opens (mirrors the pr-automation-budget needs-human-review gate). A human
# removes it to acknowledge/clear the open breaker.
ARL_BREAKER_LABEL="needs-human-review"

# ---------------------------------------------------------------------------
# Logging — to stderr so a caller can capture the machine-readable decision on
# stdout without the human-readable reasoning getting in the way.
# ---------------------------------------------------------------------------
arl_log() { printf 'agent-rate-limit: %s\n' "$*" >&2; }

# ---------------------------------------------------------------------------
# arl_config_path — echo the effective config path, honoring $AGENT_RATE_LIMITS_CONFIG.
# ---------------------------------------------------------------------------
arl_config_path() {
  printf '%s' "${AGENT_RATE_LIMITS_CONFIG:-$ARL_DEFAULT_CONFIG}"
}

# ---------------------------------------------------------------------------
# arl_now — current epoch seconds, honoring the $SOURCE_NOW test override.
# ---------------------------------------------------------------------------
arl_now() {
  if [ -n "${SOURCE_NOW:-}" ]; then
    printf '%s' "$SOURCE_NOW"
    return 0
  fi
  date +%s
}

# ---------------------------------------------------------------------------
# arl_is_dry_run — 0 (true) when DRY_RUN or DEV_LEAD_DRY_RUN is "true".
# ---------------------------------------------------------------------------
arl_is_dry_run() {
  local dry="${DRY_RUN:-${DEV_LEAD_DRY_RUN:-false}}"
  if [ "$dry" = "true" ]; then
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# arl_sanitize_int <value> [default] — echo <value> when it is a non-negative
# integer, else echo <default> (default 0). The fail-safe integer idiom: a
# malformed count never breaks the numeric gate, it degrades to a value that
# allows (mirrors the pr-automation-budget "degrade malformed input to 0").
# ---------------------------------------------------------------------------
arl_sanitize_int() {
  local value="${1:-}" fallback="${2:-0}"
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    printf '%s' "$value"
  else
    printf '%s' "$fallback"
  fi
}

# ---------------------------------------------------------------------------
# arl_is_exempt_actor <actor> — 0 when <actor> is on the config exempt list.
# Exempt actors (e.g. dependabot[bot], human break-glass) must never be blocked
# or deferred by the rate limits (ADR §8.1, same set as pr-limits).
# ---------------------------------------------------------------------------
arl_is_exempt_actor() {
  local actor="$1" config
  config="$(arl_config_path)"
  if jq -e --arg a "$actor" '(.exempt_actors // []) | index($a) != null' "$config" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

# ---------------------------------------------------------------------------
# arl_agent_threshold <agent_type> <key> — echo the numeric threshold <key> for
# <agent_type> from the config, or empty when the value is absent/non-integer.
# An empty result means "no configured limit" and the caller skips that check
# (an unreadable threshold must not block — it degrades to allow).
# ---------------------------------------------------------------------------
arl_agent_threshold() {
  local agent_type="$1" key="$2" config value
  config="$(arl_config_path)"
  value=""
  value="$(jq -er --arg t "$agent_type" --arg k "$key" \
    '(.agent_types[$t][$k])? // empty' "$config" 2>/dev/null || printf '')"
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    printf '%s' "$value"
  fi
}

# ---------------------------------------------------------------------------
# arl_breaker_threshold <agent_type> <key> — echo a numeric circuit_breaker
# threshold <key> for <agent_type>, or empty when absent/non-integer.
# ---------------------------------------------------------------------------
arl_breaker_threshold() {
  local agent_type="$1" key="$2" config value
  config="$(arl_config_path)"
  value=""
  value="$(jq -er --arg t "$agent_type" --arg k "$key" \
    '(.agent_types[$t].circuit_breaker[$k])? // empty' "$config" 2>/dev/null || printf '')"
  if [[ "$value" =~ ^[0-9]+$ ]]; then
    printf '%s' "$value"
  fi
}

# ---------------------------------------------------------------------------
# arl_admission_decision <agent_type> <concurrent> <last_run_epoch> <daily_count>
#                        <now_epoch>
#
# PURE — computes allow/defer from injected counts/timestamps, reading only the
# configured thresholds (no gh, no state I/O), so every branch is unit-testable.
#
# Defers when, for the configured (non-zero) thresholds:
#   - concurrent runs >= max_concurrent_runs, or
#   - a recorded last run is newer than cooldown_minutes, or
#   - today's run count >= daily_run_budget.
# A zero or absent threshold disables that dimension (e.g. cooldown_minutes = 0
# for the weekly-cron agents). Malformed counts degrade to an allowing default.
#
# Prints `decision=allow` / `decision=defer` on stdout; returns 0 on allow, 1 on
# defer.
# ---------------------------------------------------------------------------
arl_admission_decision() {
  local agent_type="$1"
  local concurrent last_run daily_count now
  concurrent="$(arl_sanitize_int "${2:-}")"
  last_run="$(arl_sanitize_int "${3:-}")"
  daily_count="$(arl_sanitize_int "${4:-}")"
  now="$(arl_sanitize_int "${5:-}")"

  local max cooldown daily
  max="$(arl_agent_threshold "$agent_type" max_concurrent_runs)"
  cooldown="$(arl_agent_threshold "$agent_type" cooldown_minutes)"
  daily="$(arl_agent_threshold "$agent_type" daily_run_budget)"

  local decision="allow" reason="under all limits"

  # 1. Concurrency — hard cap on simultaneous runs of this type (counted, never
  #    cancelled; ADR §5).
  if [ -n "$max" ] && [ "$max" -gt 0 ] && [ "$concurrent" -ge "$max" ]; then
    decision="defer"
    reason="concurrency ${concurrent}/${max} at or over max_concurrent_runs"
  fi

  # 2. Cooldown — minimum quiet interval since the last run (kills dispatch
  #    races; ADR §5). Skipped when disabled (0) or when there is no last run.
  if [ "$decision" = "allow" ] && [ -n "$cooldown" ] && [ "$cooldown" -gt 0 ] && [ "$last_run" -gt 0 ]; then
    local elapsed=$(( now - last_run ))
    local window=$(( cooldown * 60 ))
    if [ "$elapsed" -lt "$window" ]; then
      decision="defer"
      reason="cooldown ${elapsed}s/${window}s since last run has not elapsed"
    fi
  fi

  # 3. Daily budget — runs (dispatches for initiative-driver) per rolling 24h.
  if [ "$decision" = "allow" ] && [ -n "$daily" ] && [ "$daily" -gt 0 ] && [ "$daily_count" -ge "$daily" ]; then
    decision="defer"
    reason="daily budget ${daily_count}/${daily} at or over daily_run_budget"
  fi

  arl_log "admission for '${agent_type}': ${decision} (${reason})"
  printf 'decision=%s\n' "$decision"
  [ "$decision" = "allow" ] && return 0
  return 1
}

# ---------------------------------------------------------------------------
# arl_breaker_decision <agent_type> <consecutive_failures> <opened_epoch>
#                      <now_epoch>
#
# PURE — the consecutive-failure circuit breaker (ADR §5). Reads the threshold
# and backoff from config; computes state from injected counters/timestamps.
#
# State machine:
#   - failures < threshold           -> closed    -> allow
#   - failures >= threshold, and the backoff has NOT elapsed since the breaker
#     opened                         -> open      -> defer
#   - failures >= threshold, and the backoff HAS elapsed
#                                     -> half-open -> allow a single probe run
#
# Fail-safe (ADR §7 / AC #4): a malformed failure count degrades to 0 (closed),
# and a malformed/missing threshold or backoff allows (never blocks) — an
# unreadable breaker config must not stop the fleet.
#
# Prints `decision=allow` / `decision=defer` on stdout and logs the breaker state
# to stderr; returns 0 on allow, 1 on defer.
# ---------------------------------------------------------------------------
arl_breaker_decision() {
  local agent_type="$1"
  local failures opened now
  failures="$(arl_sanitize_int "${2:-}")"
  opened="$(arl_sanitize_int "${3:-}")"
  now="$(arl_sanitize_int "${4:-}")"

  local threshold backoff
  threshold="$(arl_breaker_threshold "$agent_type" consecutive_failure_threshold)"
  backoff="$(arl_breaker_threshold "$agent_type" backoff_minutes)"

  # Malformed / missing breaker config -> cannot evaluate -> allow (never block).
  if [ -z "$threshold" ] || [ "$threshold" -le 0 ]; then
    arl_log "breaker for '${agent_type}': state=closed (no usable consecutive_failure_threshold — allowing)"
    printf 'decision=allow\n'
    return 0
  fi

  if [ "$failures" -lt "$threshold" ]; then
    arl_log "breaker for '${agent_type}': state=closed (${failures}/${threshold} consecutive failures)"
    printf 'decision=allow\n'
    return 0
  fi

  # Breaker has tripped. Without a usable backoff we cannot time a half-open
  # probe; degrade to allow rather than block indefinitely on bad config.
  if [ -z "$backoff" ] || [ "$backoff" -le 0 ]; then
    arl_log "breaker for '${agent_type}': state=open but no usable backoff_minutes — allowing (degraded)"
    printf 'decision=allow\n'
    return 0
  fi

  # Just tripped (no opened timestamp recorded yet) -> open, defer.
  if [ "$opened" -le 0 ]; then
    arl_log "breaker for '${agent_type}': state=open (${failures}/${threshold} failures, just tripped)"
    printf 'decision=defer\n'
    return 1
  fi

  local elapsed=$(( now - opened ))
  local window=$(( backoff * 60 ))
  if [ "$elapsed" -lt "$window" ]; then
    arl_log "breaker for '${agent_type}': state=open (backoff ${elapsed}s/${window}s not elapsed)"
    printf 'decision=defer\n'
    return 1
  fi

  arl_log "breaker for '${agent_type}': state=half-open (backoff ${elapsed}s/${window}s elapsed — allowing one probe)"
  printf 'decision=allow\n'
  return 0
}

# ---------------------------------------------------------------------------
# arl_breaker_marker <agent_type> — echo the stable, deduped HTML marker recording
# that the breaker is open for <agent_type> (the pr-automation-budget marker
# idiom). A caller posts this once on the tracking issue/PR when the breaker
# opens; a human clears it.
# ---------------------------------------------------------------------------
arl_breaker_marker() {
  local agent_type="$1"
  printf '%s: %s -->' "$ARL_BREAKER_MARKER_PREFIX" "$agent_type"
}

# ---------------------------------------------------------------------------
# arl_should_escalate <existing_body> <agent_type> — 0 (true) when the open-breaker
# marker for <agent_type> is NOT already present in <existing_body>, so the caller
# should post it; 1 (false) when it is already present, so the caller dedups and
# does nothing (mirrors the pr-automation-budget deduped escalation).
# ---------------------------------------------------------------------------
arl_should_escalate() {
  local existing_body="$1" agent_type="$2" marker
  marker="$(arl_breaker_marker "$agent_type")"
  case "$existing_body" in
    *"$marker"*) return 1 ;;
    *) return 0 ;;
  esac
}

# ---------------------------------------------------------------------------
# arl_breaker_label — echo the human-clearable label a caller applies alongside
# the open-breaker marker (the pr-automation-budget needs-human-review gate). A
# human removes the label to acknowledge/clear the open breaker. Exposed as an
# accessor so the Phase-4 wiring reads it from the library rather than restating
# the string.
# ---------------------------------------------------------------------------
arl_breaker_label() {
  printf '%s' "$ARL_BREAKER_LABEL"
}

# ---------------------------------------------------------------------------
# arl_state_path — echo the effective state path, honoring $AGENT_RATE_LIMITS_STATE.
# May be empty (no state backend configured); callers degrade to defaults.
# ---------------------------------------------------------------------------
arl_state_path() {
  printf '%s' "${AGENT_RATE_LIMITS_STATE:-}"
}

# ---------------------------------------------------------------------------
# arl_load_state — echo the state document as JSON. A missing, empty, or
# malformed state file degrades to `{}` (with a warning), so every downstream
# count reads its allowing default rather than crashing the caller (AC #4).
# ---------------------------------------------------------------------------
arl_load_state() {
  local path
  path="$(arl_state_path)"
  if [ -z "$path" ] || [ ! -f "$path" ]; then
    printf '{}'
    return 0
  fi
  local raw
  raw="$(cat "$path" 2>/dev/null || printf '')"
  if [ -z "$raw" ] || ! jq -e . <<<"$raw" >/dev/null 2>&1; then
    arl_log "warning: agent-rate-limit state at '$path' is missing or malformed — treating as empty"
    printf '{}'
    return 0
  fi
  printf '%s' "$raw"
}

# ---------------------------------------------------------------------------
# arl_state_field <state_json> <agent_type> <field> [default] — PURE. Echo the
# per-agent state <field> from the injected state JSON, or [default] (0) when
# absent/malformed.
# ---------------------------------------------------------------------------
arl_state_field() {
  local state_json="$1" agent_type="$2" field="$3" fallback="${4:-0}" value
  value=""
  if [ -n "$state_json" ]; then
    value="$(jq -er --arg t "$agent_type" --arg f "$field" \
      '(.[$t][$f])? // empty' <<<"$state_json" 2>/dev/null || printf '')"
  fi
  arl_sanitize_int "$value" "$fallback"
}

# ---------------------------------------------------------------------------
# arl_count_concurrent_runs <agent_type> — count this agent type's in-flight
# (queued or in-progress) workflow runs via `gh run list`. Echoes the integer
# count on stdout. Fail-safe: a `gh` failure or empty payload logs and yields 0,
# so a transient API error degrades to allow rather than wedging dispatch.
#
# The mapping from <agent_type> to a workflow filter is finalized by the Phase-4
# wiring; here the enumeration is intentionally thin, and any read failure
# degrades to 0 (allow).
# ---------------------------------------------------------------------------
arl_count_concurrent_runs() {
  local agent_type="$1"
  local runs
  runs="$(gh run list \
    --workflow "$agent_type" \
    --json status \
    --limit 1000 \
    2>/dev/null || true)"

  if [ -z "$runs" ]; then
    arl_log "warning: run enumeration for '${agent_type}' returned no data (treating concurrency as 0)"
    printf '0'
    return 0
  fi

  jq -r '[ .[]? | select((.status // "") == "in_progress" or (.status // "") == "queued") ] | length' \
    <<<"$runs" 2>/dev/null || printf '0'
  return 0
}

# ---------------------------------------------------------------------------
# arl_finish <agent_type> <decision> <reason> — emit the result and set the
# return code, applying the dry-run override. Internal helper for
# arl_admission_gate (mirrors plg_finish).
# ---------------------------------------------------------------------------
arl_finish() {
  local agent_type="$1" decision="$2" reason="$3"

  if arl_is_dry_run; then
    arl_log "DRY_RUN — computed decision=${decision} for '${agent_type}' (${reason}); returning allow, no side effects"
    printf 'decision=allow\n'
    return 0
  fi

  arl_log "decision=${decision} for '${agent_type}' (${reason})"
  printf 'decision=%s\n' "$decision"

  [ "$decision" = "allow" ] && return 0
  return 1
}

# ---------------------------------------------------------------------------
# arl_admission_gate <agent_type> [actor] — the guard.
#
# Decides whether <agent_type> may dispatch another run right now. [actor] is the
# candidate triggering identity (e.g. an actor login); when it is on the config
# exempt list the run is always allowed and never counted (ADR §8.1).
#
# Decision order:
#   1. Missing/malformed config           -> allow (never block the fleet; AC #4)
#   2. Exempt actor                        -> allow (never blocked, never counted)
#   3. Open consecutive-failure breaker    -> defer (evaluated before admission)
#   4. Admission (concurrency/cooldown/daily) -> allow or defer
#
# Prints `decision=allow` / `decision=defer`; returns 0 on allow, 1 on defer, 2
# on a usage error (no agent type given). DRY_RUN / DEV_LEAD_DRY_RUN prints the
# computed decision then returns allow with no side effects.
# ---------------------------------------------------------------------------
arl_admission_gate() {
  local agent_type="${1:-}" actor="${2:-}"
  if [ -z "$agent_type" ]; then
    arl_log "error: arl_admission_gate requires an <agent_type> argument"
    return 2
  fi

  # 1. Missing / malformed config degrades to allow (ADR §7 / AC #4): an outage of
  #    the config source must never stop the fleet.
  local config
  config="$(arl_config_path)"
  if [ ! -f "$config" ] || ! jq -e . "$config" >/dev/null 2>&1; then
    arl_log "warning: config at '$config' is missing or malformed — allowing dispatch (degraded)"
    arl_finish "$agent_type" "allow" "config unreadable — degraded allow"
    return $?
  fi

  # 2. Exempt actors are always allowed and never counted.
  if [ -n "$actor" ] && arl_is_exempt_actor "$actor"; then
    arl_finish "$agent_type" "allow" "actor '${actor}' is exempt (not subject to the limits)"
    return $?
  fi

  local now state
  now="$(arl_now)"
  state="$(arl_load_state)"

  local failures opened
  failures="$(arl_state_field "$state" "$agent_type" consecutive_failures 0)"
  opened="$(arl_state_field "$state" "$agent_type" breaker_opened_epoch 0)"

  # 3. Circuit breaker first — an open breaker defers regardless of admission.
  #    `|| true`: the decision is carried in the captured stdout, and a defer
  #    returns non-zero — neutralize it so a caller running under `set -e` is not
  #    aborted at this assignment before the decision is emitted.
  local breaker
  breaker="$(arl_breaker_decision "$agent_type" "$failures" "$opened" "$now")" || true
  if [ "$breaker" != "decision=allow" ]; then
    arl_finish "$agent_type" "defer" "consecutive-failure breaker is open"
    return $?
  fi

  # 4. Admission — concurrency / cooldown / daily budget.
  local concurrent last_run daily_count
  concurrent="$(arl_count_concurrent_runs "$agent_type")"
  last_run="$(arl_state_field "$state" "$agent_type" last_run_epoch 0)"
  daily_count="$(arl_state_field "$state" "$agent_type" daily_count 0)"

  local admission
  # `|| true`: as above — a defer returns non-zero, so neutralize it and read the
  # decision from the captured stdout instead of the exit status.
  admission="$(arl_admission_decision "$agent_type" "$concurrent" "$last_run" "$daily_count" "$now")" || true
  if [ "$admission" = "decision=allow" ]; then
    arl_finish "$agent_type" "allow" "under all limits with a clean breaker"
    return $?
  fi

  arl_finish "$agent_type" "defer" "an admission limit is at or over cap"
  return $?
}
