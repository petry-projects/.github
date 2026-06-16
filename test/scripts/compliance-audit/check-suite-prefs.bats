#!/usr/bin/env bats
# Tests for the `check-suite-auto-trigger-<app_id>` finding in
# scripts/compliance-audit.sh (check_check_suite_prefs) and the matching
# remediation payload built by scripts/apply-repo-settings.sh
# (apply_check_suite_prefs) and scripts/fix-check-suite-prefs.sh.
#
# GitHub auto-creates a check suite for an app that has previously run in a repo
# on every push. Claude and CodeRabbit only complete a suite when they have real
# work; otherwise it stays `queued` forever, and GitHub auto-merge — which waits
# for every suite to reach a terminal state — is permanently blocked. The fix is
# to set `auto_trigger_checks: false` for both app IDs. The audit raises a
# `settings` / `check-suite-auto-trigger-<app_id>` error when an app's setting is
# anything other than `false` or `missing` (the app never ran).
#
# This suite locks in the detection decision and the remediation payload,
# including the CodeRabbit (347564) case that produced issue #374.

bats_require_minimum_version 1.5.0

# Repo root, derived from this test file's location (test/scripts/compliance-audit).
REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"

CODERABBIT_APP_ID=347564
CLAUDE_APP_ID=1236702

# ---------------------------------------------------------------------------
# Mirrors the per-app decision in check_check_suite_prefs
# (scripts/compliance-audit.sh): read the app's setting from the preferences
# JSON, then treat `missing` (app never ran) and a disabled setting as
# compliant. Returns 0 when compliant (no finding), 1 when a finding is raised.
#
# Note the jq `// "missing"` idiom: jq's `//` treats both `null` AND boolean
# `false` as empty, so a disabled (`false`) setting also resolves to "missing".
# The net decision — disabled is compliant — is what matters and is what we pin.
# ---------------------------------------------------------------------------
_audit_compliant() {
  local prefs="$1" app_id="$2" setting
  setting=$(echo "$prefs" | jq -r --argjson id "$app_id" \
    '.preferences.auto_trigger_checks // [] | map(select(.app_id == $id)) | first | .setting // "missing"')
  [ "$setting" = "missing" ] && return 0
  [ "$setting" = "false" ] && return 0
  return 1
}

# ---------------------------------------------------------------------------
# Detection — compliant cases (status 0, no finding)
# ---------------------------------------------------------------------------

@test "CodeRabbit auto-trigger disabled is compliant" {
  prefs='{"preferences":{"auto_trigger_checks":[{"app_id":347564,"setting":false}]}}'
  run _audit_compliant "$prefs" "$CODERABBIT_APP_ID"
  [ "$status" -eq 0 ]
}

@test "CodeRabbit absent (never ran in repo) is compliant" {
  prefs='{"preferences":{"auto_trigger_checks":[{"app_id":1236702,"setting":false}]}}'
  run _audit_compliant "$prefs" "$CODERABBIT_APP_ID"
  [ "$status" -eq 0 ]
}

@test "an empty auto_trigger_checks array is compliant" {
  prefs='{"preferences":{"auto_trigger_checks":[]}}'
  run _audit_compliant "$prefs" "$CODERABBIT_APP_ID"
  [ "$status" -eq 0 ]
}

@test "preferences object with no auto_trigger_checks key is compliant" {
  prefs='{"preferences":{}}'
  run _audit_compliant "$prefs" "$CODERABBIT_APP_ID"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Detection — finding cases (status 1, error raised)
# ---------------------------------------------------------------------------

@test "CodeRabbit auto-trigger enabled raises a finding (issue #374)" {
  prefs='{"preferences":{"auto_trigger_checks":[{"app_id":347564,"setting":true}]}}'
  run _audit_compliant "$prefs" "$CODERABBIT_APP_ID"
  [ "$status" -eq 1 ]
}

@test "Claude auto-trigger enabled raises a finding" {
  prefs='{"preferences":{"auto_trigger_checks":[{"app_id":1236702,"setting":true}]}}'
  run _audit_compliant "$prefs" "$CLAUDE_APP_ID"
  [ "$status" -eq 1 ]
}

@test "each app is evaluated independently — CodeRabbit enabled while Claude disabled still flags CodeRabbit" {
  prefs='{"preferences":{"auto_trigger_checks":[{"app_id":1236702,"setting":false},{"app_id":347564,"setting":true}]}}'
  run _audit_compliant "$prefs" "$CLAUDE_APP_ID"
  [ "$status" -eq 0 ]
  run _audit_compliant "$prefs" "$CODERABBIT_APP_ID"
  [ "$status" -eq 1 ]
}

# ---------------------------------------------------------------------------
# Remediation payload — mirrors the jq in apply_check_suite_prefs
# (scripts/apply-repo-settings.sh): given the app-ID list, build the PATCH body
# that disables auto-trigger for every app.
# ---------------------------------------------------------------------------
_build_payload() {
  printf '%s\n' "$@" | \
    jq -Rs 'split("\n") | map(select(. != "")) | map(tonumber) |
             {"auto_trigger_checks": map({"app_id": ., "setting": false})}'
}

@test "remediation payload disables auto-trigger for CodeRabbit and Claude" {
  payload=$(_build_payload "$CLAUDE_APP_ID" "$CODERABBIT_APP_ID")

  run jq -e --argjson id "$CODERABBIT_APP_ID" \
    '.auto_trigger_checks | any(.app_id == $id and .setting == false)' <<< "$payload"
  [ "$status" -eq 0 ]

  run jq -e --argjson id "$CLAUDE_APP_ID" \
    '.auto_trigger_checks | any(.app_id == $id and .setting == false)' <<< "$payload"
  [ "$status" -eq 0 ]
}

@test "remediation payload never sets any app's setting to true" {
  payload=$(_build_payload "$CLAUDE_APP_ID" "$CODERABBIT_APP_ID")
  run jq -e '.auto_trigger_checks | all(.setting == false)' <<< "$payload"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# In-repo guarantee — the audit and both remediation scripts must list the
# CodeRabbit app ID, otherwise the #374 finding would be neither detected nor
# fixed. This is the static, checked-in equivalent of "the fix is present."
# ---------------------------------------------------------------------------

@test "compliance-audit.sh lists CodeRabbit (347564) in CHECK_SUITE_APP_IDS" {
  run grep -Eq 'CHECK_SUITE_APP_IDS=\([^)]*\b347564\b' "$REPO_ROOT/scripts/compliance-audit.sh"
  [ "$status" -eq 0 ]
}

@test "apply-repo-settings.sh lists CodeRabbit (347564) in CHECK_SUITE_APP_IDS" {
  run grep -Eq 'CHECK_SUITE_APP_IDS=\([^)]*\b347564\b' "$REPO_ROOT/scripts/apply-repo-settings.sh"
  [ "$status" -eq 0 ]
}

@test "fix-check-suite-prefs.sh lists CodeRabbit (347564) in APP_IDS" {
  run grep -Eq 'APP_IDS=\([^)]*\b347564\b' "$REPO_ROOT/scripts/fix-check-suite-prefs.sh"
  [ "$status" -eq 0 ]
}
