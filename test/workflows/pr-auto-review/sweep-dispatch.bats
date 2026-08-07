#!/usr/bin/env bats
# End-to-end fault-isolation tests for the catch-up sweep orchestrator
# .github/scripts/pr-auto-review/sweep-dispatch.sh
#
# Pins issue #947 (Fleet Monitor WARNING: pr-auto-review-sweep.yml failure rate
# 11.1%). The sweep runs under `set -euo pipefail` on a 15-min schedule. Before
# this guard, the unguarded repository_dispatch POST inside the candidate loop
# ran with errexit active, so a single transient API failure (secondary rate
# limit / 5xx / network blip) on ONE PR aborted the whole run — failing the
# workflow and stranding every remaining candidate. The sweep is idempotent and
# re-runs every cycle, so a transient per-PR error must be logged and skipped,
# not fail the run. These tests drive the script with a scripted `gh` stub and
# assert that one PR's transient failure never aborts the sweep.

bats_require_minimum_version 1.5.0

load 'helpers/setup'

# Write an executable `gh` stub onto PATH. Behaviour is driven by env vars so a
# test can script per-PR success/failure without a stub variant per case.
#
#   STUB_PR_LIST            JSON returned by `gh search prs`
#   STUB_VIEW_FAIL_URL      `gh pr view <url>` exits 1 when url matches (transient fetch failure)
#   STUB_DISPATCH_FAIL_URL  the repository_dispatch POST exits 1 when its args contain this url
#   STUB_DISPATCH_FAIL_ONCE fail the first N dispatch POSTs (any url), then succeed (retry test)
#   STUB_COUNTER            counter file backing STUB_DISPATCH_FAIL_ONCE
write_gh_stub() {
  local bin="${BATS_TEST_TMPDIR}/bin"; mkdir -p "$bin"
  cat > "$bin/gh" <<'STUB'
#!/usr/bin/env bash
case "$*" in
  *"search prs"*)
    printf '%s' "${STUB_PR_LIST:-[]}"
    ;;
  "pr view "*)
    url="$3"
    if [ -n "${STUB_VIEW_FAIL_URL:-}" ] && [ "$url" = "$STUB_VIEW_FAIL_URL" ]; then
      exit 1
    fi
    printf '{"state":"OPEN","isDraft":false,"number":1,"reviewDecision":"","baseRefName":"main"}'
    ;;
  "pr checks "*)
    printf '[{"name":"CI / Lint","bucket":"pass"}]'
    ;;
  *"rules/branches"*)
    exit 1  # 404 → no required contexts configured → required_json=[]
    ;;
  *graphql*)
    printf '{"data":{"repository":{"pullRequest":{"reviewThreads":{"nodes":[]}}}}}'
    ;;
  *dispatches*)
    if [ -n "${STUB_DISPATCH_FAIL_URL:-}" ] && [[ "$*" == *"$STUB_DISPATCH_FAIL_URL"* ]]; then
      exit 1
    fi
    if [ -n "${STUB_DISPATCH_FAIL_ONCE:-}" ]; then
      n=0
      [ -f "${STUB_COUNTER:-/dev/null}" ] && n=$(cat "$STUB_COUNTER")
      n=$((n + 1))
      printf '%s' "$n" > "$STUB_COUNTER"
      if [ "$n" -le "$STUB_DISPATCH_FAIL_ONCE" ]; then
        exit 1
      fi
    fi
    printf '{"ok":true}'
    ;;
  *)
    ;;
esac
STUB
  chmod +x "$bin/gh"
  PATH="${bin}:${PATH}"; export PATH
}

setup() {
  write_gh_stub
  export GH_TOKEN="t"
  export SEARCH_OWNER="petry-projects"
  export SWEEP_LABEL="standards-sync"
  export MAX_PER_RUN="8"
  export DRY_RUN="0"
  export DISPATCH_REPO="petry-projects/.github-private"
  # Keep retries bounded and instant so the suite stays fast + deterministic.
  export DISPATCH_RETRIES="2"
  export DISPATCH_RETRY_SLEEP="0"
  export STUB_COUNTER="${BATS_TEST_TMPDIR}/dispatch-count"
  # Two ready, non-draft PRs.
  export STUB_PR_LIST='[
    {"url":"https://github.com/petry-projects/repo-a/pull/1","isDraft":false},
    {"url":"https://github.com/petry-projects/repo-c/pull/3","isDraft":false}
  ]'
}

run_sweep() { run bash "${TT_SCRIPTS_DIR}/sweep-dispatch.sh"; }

# ── happy path baseline ───────────────────────────────────────────────────────

@test "sweep: both ready PRs dispatch and the run succeeds" {
  run_sweep
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'dispatched auto-review for https://github.com/petry-projects/repo-a/pull/1'
  echo "$output" | grep -q 'dispatched auto-review for https://github.com/petry-projects/repo-c/pull/3'
  echo "$output" | grep -q 'dispatched 2 of 2'
}

# ── fault isolation: a transient dispatch failure must not abort the sweep ─────

@test "sweep: a transient dispatch failure on one PR does not abort the run" {
  export STUB_DISPATCH_FAIL_URL="https://github.com/petry-projects/repo-a/pull/1"
  run_sweep
  # The whole run must still succeed — a transient dispatch error is retried
  # next cycle, not a workflow failure.
  [ "$status" -eq 0 ]
  # repo-a persistently fails → warning, not an abort.
  echo "$output" | grep -q 'failed to dispatch https://github.com/petry-projects/repo-a/pull/1'
  # repo-c is still reached and dispatched (loop was not aborted).
  echo "$output" | grep -q 'dispatched auto-review for https://github.com/petry-projects/repo-c/pull/3'
  echo "$output" | grep -q 'dispatched 1 of 2'
}

# ── fault isolation: a transient fact-fetch failure skips only that PR ─────────

@test "sweep: a transient 'gh pr view' failure skips that PR and continues" {
  export STUB_VIEW_FAIL_URL="https://github.com/petry-projects/repo-a/pull/1"
  run_sweep
  [ "$status" -eq 0 ]
  # repo-a could not be evaluated → skipped, never dispatched.
  ! echo "$output" | grep -q 'dispatched auto-review for https://github.com/petry-projects/repo-a/pull/1'
  # repo-c still dispatches.
  echo "$output" | grep -q 'dispatched auto-review for https://github.com/petry-projects/repo-c/pull/3'
  echo "$output" | grep -q 'dispatched 1 of 2'
}

# ── bounded retry: a dispatch that fails once then succeeds is retried ─────────

@test "sweep: a dispatch that fails once is retried and then succeeds" {
  export STUB_DISPATCH_FAIL_ONCE="1"
  # Only one PR so the single retry budget is spent on it deterministically.
  export STUB_PR_LIST='[{"url":"https://github.com/petry-projects/repo-a/pull/1","isDraft":false}]'
  run_sweep
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'dispatched auto-review for https://github.com/petry-projects/repo-a/pull/1'
  echo "$output" | grep -q 'dispatched 1 of 1'
  # No persistent-failure warning — the retry recovered it.
  ! echo "$output" | grep -q 'failed to dispatch'
}
