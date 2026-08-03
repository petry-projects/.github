#!/usr/bin/env bats
# Regression guard for the flaky "Lint GitHub Actions" step in
# .github/workflows/ci.yml.
#
# Pins issue #894: ci.yml intermittently fails (~14% of runs) because the pinned
# rhysd/actionlint binary is fetched from GitHub Releases — which redirects to
# objects.githubusercontent.com — with a bare `curl` that aborts on the first
# transient network/5xx blip. This is the same failure mode fixed for
# pr-review-mention-tests.yml under #739. AGENTS.md requires CI to be reliable;
# the one unavoidable network fetch must therefore retry on transient errors.
# These tests assert every download in ci.yml carries bounded curl retries, so a
# future edit can't silently reintroduce a bare download.

load 'helpers/setup'

# Emit the `run:` step block whose text contains the given marker substring.
# Steps in ci.yml start at a 6-space "- " (the `steps:` child indent); every
# deeper-indented line belongs to that step. Isolating a step lets each test
# assert resilience on the one fetch it cares about without matching flags that
# happen to appear in a neighbouring step.
step_block_with() {
  local marker="$1"
  local block="" out="" line=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    if [[ "$line" == "      - "* ]]; then
      if [[ "$block" == "      - "* ]]; then
        [[ "$block" == *"$marker"* ]] && out="$block"
      fi
      block="$line"$'\n'
    else
      if [[ -n "$block" ]]; then
        block+="$line"$'\n'
      fi
    fi
  done < "$TT_WORKFLOW"
  if [[ "$block" == "      - "* ]]; then
    [[ "$block" == *"$marker"* ]] && out="$block"
  fi
  printf '%s' "$out"
}

@test "install: the ci workflow exists" {
  [ -f "$TT_WORKFLOW" ]
}

@test "install: every curl download in ci.yml uses bounded retries" {
  [ -f "$TT_WORKFLOW" ]

  # Parse the workflow joining backslash-continued lines so that a curl command
  # split across multiple lines is treated as a single logical invocation.
  # This avoids false failures when flags appear on continuation lines, and
  # avoids false passes when a bare `curl` is split from its flags.
  local curls=()
  local current=""
  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    if [[ "$line" == *\\ ]]; then
      current+="${line%\\} "
    else
      current+="$line"
      if [[ "$current" == *curl* ]] && ! [[ "$current" =~ ^[[:space:]]*# ]] && ! [[ "$current" =~ ^[[:space:]]*-?[[:space:]]*(name|uses|with): ]]; then
        curls+=("$current")
      fi
      current=""
    fi
  done < "$TT_WORKFLOW"

  # At least one curl invocation must be present so the test remains meaningful.
  [ "${#curls[@]}" -ge 1 ]
  for cmd in "${curls[@]}"; do
    # A finite retry budget (not unbounded) so a truly-down mirror still fails fast.
    [[ "$cmd" =~ --retry[[:space:]=][1-9] ]]
    # Retry on connection refused, which curl otherwise treats as non-transient.
    [[ "$cmd" == *"--retry-connrefused"* ]]
    # Retry on transient HTTP 5xx too, not just connection-level errors.
    [[ "$cmd" == *"--retry-all-errors"* ]]
  done
}

@test "install: the yamllint pip install carries a bounded retry budget" {
  # pip fetches wheels from PyPI/the configured index; a transient index blip
  # would otherwise red the Lint job. An explicit --retries pins the budget so a
  # future edit can't drop resilience and reintroduce a bare install.
  local block
  block="$(step_block_with 'pip install')"
  [ -n "$block" ]
  local pip_cmd
  pip_cmd="$(printf '%s' "$block" | grep -E '^[[:space:]]+pip install' | head -1)"
  [ -n "$pip_cmd" ]
  [[ "$pip_cmd" =~ --retries[[:space:]=][1-9] ]]
}

@test "install: the AgentShield npx fetch retries transient registry errors" {
  # `npx ecc-agentshield` downloads the package from the npm registry before
  # scanning; npm's default of 2 fetch retries is thin. Bump it via npm's native
  # fetch-retries config (env var, NOT a shell loop) so a transient registry
  # error retries while a genuine high-severity finding still fails on the first
  # run instead of being retried three times.
  local block
  block="$(step_block_with 'ecc-agentshield')"
  [ -n "$block" ]
  [[ "$block" =~ npm_config_fetch_retries:[[:space:]]*\'?[1-9] ]]
}

@test "install: the gitleaks release download retries on transient failure" {
  # `gh release download` pulls gitleaks from GitHub Releases (which redirects to
  # objects.githubusercontent.com) and has no native retry — the exact failure
  # mode #894 fixed for the actionlint curl. Wrap it in a bounded retry loop with
  # backoff so a transient blip retries instead of reding the Secret scan job.
  local block
  block="$(step_block_with 'gh release download')"
  [ -n "$block" ]
  [[ "$block" == *"for attempt in"* ]]
  [[ "$block" == *"sleep"* ]]
}
