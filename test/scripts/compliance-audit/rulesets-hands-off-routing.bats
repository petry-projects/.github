#!/usr/bin/env bats
# Tests for the rulesets → dev-lead:hands-off routing in
# scripts/compliance-audit.sh (issue #1093, decision #1037).
#
# dev-lead cannot read or write ruleset configuration, so a compliance finding in
# the `rulesets` category is labelled `dev-lead:hands-off` instead of `dev-lead`.
# The finding still stays open, visible, and re-reported — hands-off removes the
# actor, it does NOT resolve the finding. These tests pin that contract:
#
#   pure — category_actor_label maps rulesets -> dev-lead:hands-off, else dev-lead.
#   AC1  — a NEW rulesets finding is created with dev-lead:hands-off, not dev-lead.
#   AC4  — a NEW non-rulesets finding is created with dev-lead, not hands-off.
#   AC2  — an EXISTING open rulesets finding carrying dev-lead has it swapped for
#          dev-lead:hands-off on the next run.
#   AC3  — that existing finding is still commented/re-reported and never closed;
#          non-rulesets findings keep the dev-lead retrigger.
#   label — ensure_audit_label provisions the dev-lead:hands-off label so issue
#          creation with it never fails on a not-yet-reconciled repo.

bats_require_minimum_version 1.5.0

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

setup() {
  TEST_TMP="$(mktemp -d "$BATS_TEST_TMPDIR/rho.XXXXXX")"
  MOCK_BIN="$TEST_TMP/bin"
  mkdir -p "$MOCK_BIN"
  # No-op sleep so the retrigger cycle's inter-call pause runs instantly.
  printf '#!/usr/bin/env bash\nexit 0\n' > "$MOCK_BIN/sleep"
  chmod +x "$MOCK_BIN/sleep"

  MOCK_ARGS_LOG="$TEST_TMP/gh-args.log"
  : > "$MOCK_ARGS_LOG"
  MOCK_CLOSED_FILE="$TEST_TMP/closed.txt"
  : > "$MOCK_CLOSED_FILE"

  # gh mock: logs every invocation's argv (one entry per call), and returns just
  # enough for the code paths under test.
  #   issue list   -> the pre-filtered `existing` value gh -q would emit ("" = new)
  #   issue create -> a URL ending in digits so the created-issue is recorded
  #   issue close  -> records the closed number (must stay empty in these tests)
  #   api /pulls?  -> "0" open dev-lead PRs (dl_dev_lead_active PR-count lookup)
  cat > "$MOCK_BIN/gh" << 'GH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$MOCK_ARGS_LOG"
case "$1 $2" in
  "issue list")   printf '%s' "${MOCK_EXISTING:-}" ;;
  "issue create") echo "https://github.com/petry-projects/demo/issues/4242" ;;
  "issue close")  echo "$3" >> "$MOCK_CLOSED_FILE" ;;
  "api")
    case "$*" in
      *"/pulls?"*) echo "0" ;;
      *) : ;;
    esac ;;
  *) : ;;
esac
exit 0
GH
  chmod +x "$MOCK_BIN/gh"
}

teardown() { rm -rf "$TEST_TMP"; }

# _cif <repo> <category> <check> <severity> <detail> <std_ref> [existing_number]
# Source the audit and run create_issue_for_finding once. An empty existing
# number exercises the new-finding path; a number exercises the existing path.
_cif() {
  local existing="${7:-}"
  MOCK_EXISTING="$existing" MOCK_ARGS_LOG="$MOCK_ARGS_LOG" MOCK_CLOSED_FILE="$MOCK_CLOSED_FILE" \
  PATH="$MOCK_BIN:$PATH" REPORT_DIR="$TEST_TMP" bash -c '
    set -uo pipefail
    export MOCK_EXISTING MOCK_ARGS_LOG MOCK_CLOSED_FILE
    echo "[]" > "'"$TEST_TMP"'/findings.json"
    # shellcheck disable=SC1090
    source "'"$REPO_ROOT"'/scripts/compliance-audit.sh"
    create_issue_for_finding "$@"
  ' _ "$1" "$2" "$3" "$4" "$5" "$6" 2>/dev/null
}

@test "pure: category_actor_label routes rulesets to hands-off, others to dev-lead" {
  run bash -c '
    set -uo pipefail
    PATH="'"$MOCK_BIN"':$PATH" REPORT_DIR="'"$TEST_TMP"'" \
      source "'"$REPO_ROOT"'/scripts/compliance-audit.sh"
    category_actor_label rulesets
    category_actor_label settings
    category_actor_label labels
    category_actor_label ci-workflows
  '
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "dev-lead:hands-off" ]
  [ "${lines[1]}" = "dev-lead" ]
  [ "${lines[2]}" = "dev-lead" ]
  [ "${lines[3]}" = "dev-lead" ]
}

@test "AC1: new rulesets finding is created with dev-lead:hands-off and without dev-lead" {
  _cif broodly rulesets missing-pr-quality error "Missing pr-quality ruleset" standards/github-settings.md
  local create_line
  create_line="$(grep -m1 '^issue create' "$MOCK_ARGS_LOG")"
  [[ "$create_line" == *"--label dev-lead:hands-off"* ]]
  [[ "$create_line" != *"--label dev-lead "* ]]
  [[ "$create_line" == *"--label compliance-finding"* ]]
  [[ "$create_line" == *"--label compliance-audit"* ]]
}

@test "AC4: new non-rulesets finding is created with dev-lead and without hands-off" {
  _cif broodly settings has_wiki warning "Wiki should be disabled" standards/github-settings.md
  local create_line
  create_line="$(grep -m1 '^issue create' "$MOCK_ARGS_LOG")"
  [[ "$create_line" == *"--label dev-lead "* ]]
  [[ "$create_line" != *"dev-lead:hands-off"* ]]
}

@test "AC2/AC3: existing rulesets finding swaps dev-lead->hands-off, is re-reported, never closed" {
  _cif broodly rulesets ruleset-bypass-dependabot-pr-quality error "bypass missing" standards/github-settings.md 511
  # AC3 — still commented on the existing issue (re-reported, kept visible)
  grep -q '^issue comment 511' "$MOCK_ARGS_LOG"
  # AC2 — actor label swapped
  grep -q -- '--add-label dev-lead:hands-off' "$MOCK_ARGS_LOG"
  grep -q -- '--remove-label dev-lead' "$MOCK_ARGS_LOG"
  # AC3 — hands-off removes the actor, it does not resolve: no close, no relabel cycle
  [ ! -s "$MOCK_CLOSED_FILE" ]
  ! grep -q -- '-X POST' "$MOCK_ARGS_LOG"
}

@test "AC4: existing non-rulesets finding keeps the dev-lead retrigger and no hands-off" {
  _cif broodly settings has_wiki warning "Wiki should be disabled" standards/github-settings.md 540
  ! grep -q 'dev-lead:hands-off' "$MOCK_ARGS_LOG"
  # dl_cycle_trigger_label re-adds the dev-lead label via a POST — the retrigger fired
  grep -q -- '-X POST' "$MOCK_ARGS_LOG"
}

@test "label: ensure_audit_label provisions the dev-lead:hands-off label" {
  MOCK_ARGS_LOG="$MOCK_ARGS_LOG" PATH="$MOCK_BIN:$PATH" REPORT_DIR="$TEST_TMP" bash -c '
    set -uo pipefail
    export MOCK_ARGS_LOG
    # shellcheck disable=SC1090
    source "'"$REPO_ROOT"'/scripts/compliance-audit.sh"
    ensure_audit_label broodly
  ' 2>/dev/null
  grep -q '^label create dev-lead:hands-off ' "$MOCK_ARGS_LOG"
}
