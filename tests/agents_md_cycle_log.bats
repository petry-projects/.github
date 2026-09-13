#!/usr/bin/env bats
# Contract tests for scripts/agents-md-cycle-log.sh — the pure, tested helper
# that reads the append-only committed AGENTS.md structural cycle log
# (docs/initiatives/agents-md-validation-cycle-log.md) and reports (a) whether
# the log is well-formed with every false-positive determination attributed to
# a named maintainer, and (b) whether the promotion gate's clean-cycle
# precondition is met — WITHOUT ever promoting anything (#647, Phase 4 of epic
# #642).
#
# The gate: the informational structural check is promoted to blocking only
# after (1) two consecutive audit cycles with zero confirmed false positives
# AND (2) explicit maintainer sign-off — never automatically. This script is the
# pure decision core for precondition (1); precondition (2) and the flip itself
# are human actions. Reference doc: docs/initiatives/agents-md-validation.md.
#
# The script's main() is guarded, so sourcing only defines its pure helpers; the
# CLI subcommands (validate, eligibility) are exercised via `bash "$SCRIPT" ...`.
# No network, no gh — the cycle log is a committed file.

bats_require_minimum_version 1.5.0

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/agents-md-cycle-log.sh"
COMMITTED_LOG="$REPO_ROOT/docs/initiatives/agents-md-validation-cycle-log.md"

setup() {
  TMPDIR_TEST="$(mktemp -d)"
}

teardown() {
  rm -rf "$TMPDIR_TEST"
}

# write_log <body> — write a cycle-log fixture (header + given data rows) to a
# temp file and echo its path.
write_log() {
  local f="$TMPDIR_TEST/cycle-log.md"
  {
    printf '# Cycle Log\n\n'
    printf '| Cycle | Structural findings | Confirmed false positives | False-positive details | Determined by | Clean? |\n'
    printf '|-------|---------------------|---------------------------|------------------------|---------------|--------|\n'
    printf '%b' "$1"
  } > "$f"
  printf '%s' "$f"
}

# ---------------------------------------------------------------------------
# validate — well-formed rows with attribution pass; malformed / unattributed
# rows fail loudly.
# ---------------------------------------------------------------------------

@test "validate accepts a baseline log with no recorded cycles" {
  local log
  log="$(write_log '')"
  run bash "$SCRIPT" validate "$log"
  [ "$status" -eq 0 ]
}

@test "validate accepts two clean, attributed cycles" {
  local log
  log="$(write_log '| 2026-10-01 | 3 | 0 | — | @alice | yes |\n| 2026-11-01 | 1 | 0 | — | @bob | yes |\n')"
  run bash "$SCRIPT" validate "$log"
  [ "$status" -eq 0 ]
}

@test "validate rejects a false-positive determination with no maintainer named (AC #5)" {
  # A confirmed false positive that names no maintainer is exactly the
  # reward-hacking hole the append-only + attribution rule closes.
  local log
  log="$(write_log '| 2026-10-01 | 3 | 1 | anchor false alarm |  | no |\n')"
  run bash -c 'bash "$1" validate "$2" 2>&1' _ "$SCRIPT" "$log"
  [ "$status" -ne 0 ]
  [[ "$output" == *maintainer* ]]
}

@test "validate rejects a clean cycle with no reviewing maintainer named (AC #5)" {
  # Even a zero-false-positive cycle must name the maintainer who reviewed it,
  # so a 'clean cycle' claim is never anonymous.
  local log
  log="$(write_log '| 2026-10-01 | 0 | 0 | — |  | yes |\n')"
  run bash -c 'bash "$1" validate "$2" 2>&1' _ "$SCRIPT" "$log"
  [ "$status" -ne 0 ]
  [[ "$output" == *maintainer* ]]
}

@test "validate rejects a non-integer finding count" {
  local log
  log="$(write_log '| 2026-10-01 | many | 0 | — | @alice | yes |\n')"
  run bash "$SCRIPT" validate "$log"
  [ "$status" -ne 0 ]
}

@test "validate rejects a clean flag that contradicts the false-positive count" {
  # clean=yes but a confirmed false positive is recorded — an inconsistent row
  # that could fake a clean cycle.
  local log
  log="$(write_log '| 2026-10-01 | 3 | 2 | two false alarms | @alice | yes |\n')"
  run bash "$SCRIPT" validate "$log"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# eligibility — reports the clean-cycle precondition only, and NEVER signals an
# automatic promotion.
# ---------------------------------------------------------------------------

@test "eligibility reports met after two consecutive clean cycles" {
  local log
  log="$(write_log '| 2026-10-01 | 3 | 0 | — | @alice | yes |\n| 2026-11-01 | 1 | 0 | — | @bob | yes |\n')"
  run bash "$SCRIPT" eligibility "$log" 2
  [ "$status" -eq 0 ]
  [[ "$output" == *clean-cycles-met=true* ]]
}

@test "eligibility is NOT met with only one clean cycle recorded" {
  local log
  log="$(write_log '| 2026-11-01 | 1 | 0 | — | @bob | yes |\n')"
  run bash "$SCRIPT" eligibility "$log" 2
  [ "$status" -eq 0 ]
  [[ "$output" == *clean-cycles-met=false* ]]
}

@test "a confirmed false positive in the latest cycle breaks the clean streak" {
  local log
  log="$(write_log '| 2026-10-01 | 3 | 0 | — | @alice | yes |\n| 2026-11-01 | 2 | 1 | anchor false alarm | @bob | no |\n')"
  run bash "$SCRIPT" eligibility "$log" 2
  [ "$status" -eq 0 ]
  [[ "$output" == *clean-cycles-met=false* ]]
}

@test "eligibility always states sign-off is required and never auto-promotes (AC #4)" {
  local log
  log="$(write_log '| 2026-10-01 | 0 | 0 | — | @alice | yes |\n| 2026-11-01 | 0 | 0 | — | @bob | yes |\n')"
  run bash "$SCRIPT" eligibility "$log" 2
  [ "$status" -eq 0 ]
  # Even when the clean-cycle precondition is met, the tool must NOT signal an
  # automatic promotion and MUST restate the maintainer sign-off requirement.
  [[ "$output" == *maintainer_sign_off_required=true* ]]
  [[ "$output" == *auto_promote=false* ]]
}

# ---------------------------------------------------------------------------
# The committed log ships INERT: it is well-formed but records no clean cycles
# yet, so the shipped state cannot claim promotion eligibility (AC #4).
# ---------------------------------------------------------------------------

@test "the committed cycle log exists and is well-formed" {
  [ -f "$COMMITTED_LOG" ]
  run bash "$SCRIPT" validate "$COMMITTED_LOG"
  [ "$status" -eq 0 ]
}

@test "the committed cycle log is not promotion-eligible on merge (ships inert)" {
  run bash "$SCRIPT" eligibility "$COMMITTED_LOG" 2
  [ "$status" -eq 0 ]
  [[ "$output" == *clean-cycles-met=false* ]]
}
