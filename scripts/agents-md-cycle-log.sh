#!/usr/bin/env bash
# scripts/agents-md-cycle-log.sh — pure, deterministic reader for the
# APPEND-ONLY, COMMITTED AGENTS.md structural cycle log
# (docs/initiatives/agents-md-validation-cycle-log.md), the tamper-evident
# durable record behind the informational → blocking promotion gate (#647,
# Phase 4 of epic #642). Reference doc: docs/initiatives/agents-md-validation.md.
#
# The promotion gate is human-gated by design. The structural check ships
# INFORMATIONAL and is promoted to BLOCKING only after (1) two consecutive audit
# cycles with zero confirmed false positives AND (2) explicit maintainer
# sign-off — never automatically. This script is the pure decision core for
# precondition (1) ONLY: it reports whether the recorded cycles are well-formed
# and whether the clean-cycle streak is met. It NEVER performs a promotion, never
# writes the log, and never signals an automatic flip — precondition (2) and the
# discrete toggle flip are deliberate human actions (see the reference doc).
#
# Why a committed log and not just the audit summary issue: an editable issue can
# be silently edited to fabricate a "two clean cycles" claim. Persisting per-cycle
# finding counts and each false-positive determination — every one attributed to
# a NAMED maintainer — to an append-only file under git makes the baseline record
# immutable (git history is the tamper-evidence) and independently auditable.
#
# The log's machine-readable surface is a Markdown table. A DATA ROW is a table
# line whose first cell is an ISO date (YYYY-MM-DD); the header and separator
# rows are ignored. Columns, in order:
#   1. Cycle                      — audit date (YYYY-MM-DD)
#   2. Structural findings        — non-negative integer (from the audit summary)
#   3. Confirmed false positives  — non-negative integer
#   4. False-positive details     — free text ('—' when none)
#   5. Determined by              — the maintainer who made the determination
#   6. Clean?                     — 'yes' iff confirmed false positives == 0
#
# Caller contract: the pure helpers below are `source`-able and side-effect-free
# (they run nothing and call no `set` at source time), so tests can source this
# file and exercise them directly. Only when executed directly does it
# `set -euo pipefail` and run the CLI.
#
# Usage:
#   agents-md-cycle-log.sh validate    <log-file>
#   agents-md-cycle-log.sh eligibility <log-file> [required-clean-cycles]
#
#   validate     exit non-zero if any recorded row is malformed or a
#                determination is not attributed to a named maintainer.
#   eligibility  report whether the last <required-clean-cycles> (default 2)
#                cycles are all clean; always exit 0 (it is a report, not a gate).

# Field separator for the parsed-row stream emitted by amcl_data_rows and read
# back by the validators. It is the ASCII Unit Separator (0x1f) — a NON-whitespace
# char — deliberately, not a tab: `read` with a whitespace IFS collapses runs of
# the delimiter, which would silently swallow an EMPTY cell (e.g. an unattributed
# "Determined by"). Empty cells must survive so the attribution guard can catch
# them, so the separator must not be whitespace.
AMCL_FS=$'\037'

# ---------------------------------------------------------------------------
# amcl_data_rows <log> — emit one line per DATA ROW (first cell is an ISO date),
# fields separated by AMCL_FS (0x1f), in order:
#   <cycle> <findings> <false_positives> <details> <maintainer> <clean>
# Header/separator/prose lines are skipped. Cells are trimmed. Pure.
# ---------------------------------------------------------------------------
amcl_data_rows() {
  local log="$1"
  [ -f "$log" ] || return 0
  awk -F'|' -v US='\037' '
    function trim(s) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", s); return s }
    {
      # A markdown table row has an empty leading and trailing cell around 6
      # data cells, so NF is 8 (| c1 | c2 | c3 | c4 | c5 | c6 |).
      if (NF < 8) next
      cycle = trim($2)
      if (cycle !~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/) next
      printf "%s%s%s%s%s%s%s%s%s%s%s\n", \
        cycle, US, trim($3), US, trim($4), US, trim($5), US, trim($6), US, trim($7)
    }
  ' "$log"
}

# ---------------------------------------------------------------------------
# amcl_is_uint <s> — 0 (true) iff <s> is a non-negative integer. Pure.
# ---------------------------------------------------------------------------
amcl_is_uint() {
  [[ "$1" =~ ^[0-9]+$ ]]
}

# ---------------------------------------------------------------------------
# amcl_validate_log <log> — 0 iff every data row is well-formed:
#   - findings and false-positive counts are non-negative integers,
#   - a maintainer is named (attribution guard — never anonymous),
#   - the Clean? flag agrees with the false-positive count (yes iff 0).
# Emits a per-row reason to stderr and returns 1 on the first violation. An empty
# log (no data rows — the shipped baseline) is valid. Pure (reads only).
# ---------------------------------------------------------------------------
amcl_validate_log() {
  local log="$1" cycle findings fps details maintainer clean rc=0
  while IFS="$AMCL_FS" read -r cycle findings fps details maintainer clean; do
    [ -n "$cycle" ] || continue
    : "${details:-}"
    if ! amcl_is_uint "$findings"; then
      printf 'cycle %s: structural-findings count "%s" is not a non-negative integer\n' "$cycle" "$findings" >&2
      rc=1; continue
    fi
    if ! amcl_is_uint "$fps"; then
      printf 'cycle %s: confirmed-false-positive count "%s" is not a non-negative integer\n' "$cycle" "$fps" >&2
      rc=1; continue
    fi
    if [ -z "$maintainer" ] || [ "$maintainer" = "—" ] || [ "$maintainer" = "-" ]; then
      printf 'cycle %s: no maintainer named in "Determined by" — every determination must name a maintainer\n' "$cycle" >&2
      rc=1; continue
    fi
    local expected_clean
    if [ "$fps" -eq 0 ]; then expected_clean="yes"; else expected_clean="no"; fi
    local clean_lc="${clean,,}"
    if [ "$clean_lc" != "$expected_clean" ]; then
      printf 'cycle %s: Clean? is "%s" but %s confirmed false positive(s) recorded (expected "%s")\n' \
        "$cycle" "$clean" "$fps" "$expected_clean" >&2
      rc=1; continue
    fi
  done < <(amcl_data_rows "$log")
  return "$rc"
}

# ---------------------------------------------------------------------------
# amcl_clean_cycles_met <log> <required> — print "true" iff the last <required>
# recorded cycles all have zero confirmed false positives AND a named maintainer;
# otherwise "false". Fewer than <required> recorded cycles is "false". Pure.
# ---------------------------------------------------------------------------
amcl_clean_cycles_met() {
  local log="$1" required="$2"
  local rows recent count clean=0
  rows="$(amcl_data_rows "$log")"
  count="$(printf '%s' "$rows" | grep -c . || true)"
  if [ "$count" -lt "$required" ]; then
    printf 'false'
    return 0
  fi
  recent="$(printf '%s\n' "$rows" | grep . | tail -n "$required")"
  local cycle findings fps details maintainer cln
  while IFS="$AMCL_FS" read -r cycle findings fps details maintainer cln; do
    [ -n "$cycle" ] || continue
    : "${findings:-}" "${details:-}" "${cln:-}"
    if amcl_is_uint "$fps" && [ "$fps" -eq 0 ] && [ -n "$maintainer" ] \
       && [ "$maintainer" != "—" ] && [ "$maintainer" != "-" ]; then
      clean=$((clean + 1))
    fi
  done < <(printf '%s\n' "$recent")
  if [ "$clean" -eq "$required" ]; then
    printf 'true'
  else
    printf 'false'
  fi
  return 0
}

# ---------------------------------------------------------------------------
# amcl_usage — print CLI usage to stdout.
# ---------------------------------------------------------------------------
amcl_usage() {
  sed -n 's/^# \{0,1\}//p' <<'USAGE'
# agents-md-cycle-log.sh validate    <log-file>
# agents-md-cycle-log.sh eligibility <log-file> [required-clean-cycles]
#
# Reads the append-only AGENTS.md structural cycle log and either validates its
# rows (every determination attributed to a named maintainer) or reports whether
# the clean-cycle promotion precondition is met. It never promotes.
USAGE
}

# ---------------------------------------------------------------------------
# amcl_main <args...> — CLI entry point. Returns 2 on usage/environment errors,
# 1 when `validate` finds a malformed/unattributed row, else 0.
# ---------------------------------------------------------------------------
amcl_main() {
  local cmd="${1:-}"
  case "$cmd" in
    validate)
      local log="${2:-}"
      if [ -z "$log" ]; then
        printf 'agents-md-cycle-log: validate needs a <log-file>\n\n' >&2
        amcl_usage >&2
        return 2
      fi
      if [ ! -f "$log" ]; then
        printf 'agents-md-cycle-log: log file not found: %s\n' "$log" >&2
        return 2
      fi
      if amcl_validate_log "$log"; then
        printf 'cycle log is well-formed: %s\n' "$log"
        return 0
      fi
      return 1
      ;;
    eligibility)
      local log="${2:-}" required="${3:-2}"
      if [ -z "$log" ]; then
        printf 'agents-md-cycle-log: eligibility needs a <log-file>\n\n' >&2
        amcl_usage >&2
        return 2
      fi
      if [ ! -f "$log" ]; then
        printf 'agents-md-cycle-log: log file not found: %s\n' "$log" >&2
        return 2
      fi
      if ! amcl_is_uint "$required" || [ "$required" -lt 1 ]; then
        printf 'agents-md-cycle-log: required-clean-cycles must be a positive integer, got "%s"\n' "$required" >&2
        return 2
      fi
      local met
      met="$(amcl_clean_cycles_met "$log" "$required")"
      # The report is deliberately explicit that meeting the clean-cycle
      # precondition is NOT a promotion: sign-off is still required and the flip
      # is never automatic (AC #4). A consumer must not read `clean-cycles-met`
      # alone as authorization to promote.
      printf 'clean-cycles-required=%s\n' "$required"
      printf 'clean-cycles-met=%s\n' "$met"
      printf 'maintainer_sign_off_required=true\n'
      printf 'auto_promote=false\n'
      if [ "$met" = "true" ]; then
        printf 'note=clean-cycle precondition met; promotion still requires explicit maintainer sign-off and a deliberate, reviewable flip — it is never automatic\n'
      else
        printf 'note=clean-cycle precondition NOT met; the check remains informational\n'
      fi
      return 0
      ;;
    -h|--help)
      amcl_usage
      return 0
      ;;
    *)
      printf 'agents-md-cycle-log: unknown or missing command: %s\n\n' "$cmd" >&2
      amcl_usage >&2
      return 2
      ;;
  esac
}

# Run the CLI only when executed directly, not when sourced by the bats tests
# that exercise the pure helper functions above.
if [ "${BASH_SOURCE[0]:-$0}" = "$0" ]; then
  set -euo pipefail
  amcl_main "$@"
fi
