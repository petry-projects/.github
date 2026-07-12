#!/usr/bin/env bats
# Tests for the remediation-dispatch routing of three finding types that the
# 2026-07-10 compliance umbrella (#656) surfaced. None can be auto-remediated
# by the remediator (they need workflow/admin token scope or repo-tailored
# content), so each must land in skipped.md — but with an ACCURATE, actionable
# reason instead of a generic or misleading catch-all message.
#
# Before this change:
#   - push-protection/secret_scan_ci_job_present and
#     push-protection/gitignore_secrets_block hit the push-protection/* catch-all,
#     which tells the reader to "run scripts/apply-repo-settings.sh" — but that
#     script only applies security_and_analysis settings and cannot add a CI job
#     or edit .gitignore.
#   - standards/missing-copilot-instructions fell through to the final `*`
#     catch-all ("review manually") instead of the content-agent path used by
#     its sibling missing-claude-md / missing-agents-md cases.

bats_require_minimum_version 1.5.0

load 'helpers/setup'

setup() {
  tt_make_tmpdir
  tt_install_gh_stub
  export GH_STUB_LOG="${TT_TMP}/gh.log"
  : >"$GH_STUB_LOG"
}

teardown() {
  tt_cleanup_tmpdir
}

# ---------------------------------------------------------------------------
# push-protection/secret_scan_ci_job_present
# ---------------------------------------------------------------------------

@test "secret_scan_ci_job_present skips with CI-job guidance, not apply-repo-settings" {
  findings="$(tt_write_finding "broodminder-export" "push-protection" "secret_scan_ci_job_present")"
  report_dir="${TT_TMP}/report"

  GH_TOKEN=fake \
    FINDINGS_FILE="$findings" \
    REPORT_DIR="$report_dir" \
    DRY_RUN=false \
    run bash "$TT_SCRIPT"

  [ "$status" -eq 0 ]

  # Lands in skipped, never in the direct/PR remediation table.
  grep -q 'secret_scan_ci_job_present' "$report_dir/skipped.md"
  ! grep -q 'secret_scan_ci_job_present' "$report_dir/remediation-report.md"

  # Accurate reason: points at the CI gitleaks job + workflow scope.
  grep -q 'gitleaks' "$report_dir/skipped.md"
  grep -q 'workflow' "$report_dir/skipped.md"

  # The misleading apply-repo-settings.sh pointer must be gone for this check.
  ! grep -q 'apply-repo-settings.sh' "$report_dir/skipped.md"

  # Pure skip: no GitHub API calls issued.
  [ ! -s "$GH_STUB_LOG" ]
}

# ---------------------------------------------------------------------------
# push-protection/gitignore_secrets_block
# ---------------------------------------------------------------------------

@test "gitignore_secrets_block skips with .gitignore baseline guidance" {
  findings="$(tt_write_finding "broodminder-export" "push-protection" "gitignore_secrets_block")"
  report_dir="${TT_TMP}/report"

  GH_TOKEN=fake \
    FINDINGS_FILE="$findings" \
    REPORT_DIR="$report_dir" \
    DRY_RUN=false \
    run bash "$TT_SCRIPT"

  [ "$status" -eq 0 ]

  grep -q 'gitignore_secrets_block' "$report_dir/skipped.md"
  ! grep -q 'gitignore_secrets_block' "$report_dir/remediation-report.md"

  # Accurate reason: copy the org baseline .gitignore.
  grep -q 'org baseline' "$report_dir/skipped.md"

  # The misleading apply-repo-settings.sh pointer must be gone for this check.
  ! grep -q 'apply-repo-settings.sh' "$report_dir/skipped.md"
}

# ---------------------------------------------------------------------------
# standards/missing-copilot-instructions
# ---------------------------------------------------------------------------

@test "missing-copilot-instructions routes to the content-agent path" {
  findings="$(tt_write_finding "broodminder-export" "standards" "missing-copilot-instructions")"
  report_dir="${TT_TMP}/report"

  GH_TOKEN=fake \
    FINDINGS_FILE="$findings" \
    REPORT_DIR="$report_dir" \
    DRY_RUN=false \
    run bash "$TT_SCRIPT"

  [ "$status" -eq 0 ]

  grep -q 'missing-copilot-instructions' "$report_dir/skipped.md"
  ! grep -q 'missing-copilot-instructions' "$report_dir/remediation-report.md"

  # Accurate reason: references the canonical template + Claude-agent path,
  # matching the sibling missing-claude-md / missing-agents-md cases.
  grep -q 'copilot-instructions-standard.md' "$report_dir/skipped.md"
  grep -q 'Claude agent' "$report_dir/skipped.md"

  # The generic "review manually" catch-all must no longer be used here.
  ! grep -q 'review manually' "$report_dir/skipped.md"
}
