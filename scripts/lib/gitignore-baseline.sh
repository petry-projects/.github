#!/usr/bin/env bash
# scripts/lib/gitignore-baseline.sh — shared, idempotent upsert of the org secrets
# baseline (the L1 block) into a repo's .gitignore.
#
# The canonical L1 block lives in this repo's root /.gitignore, wrapped in the
# BEGIN/END markers defined by the .gitignore standard (standards/gitignore-standard.md,
# STORY1 / #797). This lib is the single mechanism that PLACES or REFRESHES that
# block in a target .gitignore. It is pure text (no gh, no network) so it can be
# unit-tested and reused by every distribution path:
#
#   • scripts/bootstrap-new-repo.sh          — seed the baseline into a new repo
#   • scripts/sync-gitignore-baseline.sh     — append-or-replace it fleet-wide
#   • STORY4 remediation                     — fix a drifted repo in place
#
# Contract (matches standards/gitignore-standard.md's two-layer model):
#   L1 — the marker-wrapped block; org-managed, byte-for-byte identical, on TOP.
#   L2 — everything BELOW the END marker; per-repo, freely edited, NEVER touched.
#
#   Nothing goes ABOVE the BEGIN marker; if a stale file somehow has content there
#   it is preserved (the standard forbids it, but the lib does not silently drop
#   bytes it didn't author).
#
# shellcheck shell=bash

# Guard against double-sourcing.
if [ -n "${_GITIGNORE_BASELINE_SOURCED:-}" ]; then
  return 0 2>/dev/null || true
fi
_GITIGNORE_BASELINE_SOURCED=1

# Canonical markers — MUST match the ones committed in /.gitignore and documented
# in standards/gitignore-standard.md. Compared as whole lines (grep -xF / awk ==).
GIB_BEGIN_MARKER='# >>> BEGIN petry-projects secrets baseline (managed by .github — do not edit) >>>'
GIB_END_MARKER='# <<< END petry-projects secrets baseline <<<'

# gib_extract_baseline_block <canonical_gitignore_file>
# Print the marker-wrapped L1 block (BEGIN..END lines, inclusive) from a canonical
# .gitignore. Returns non-zero if either marker is missing (so callers never ship
# a half-open block).
gib_extract_baseline_block() {
  local file="${1:-}"
  [ -n "$file" ] && [ -f "$file" ] || { echo "gib: canonical gitignore not found: ${file:-<none>}" >&2; return 2; }
  tr -d '\r' < "$file" | awk -v b="$GIB_BEGIN_MARKER" -v e="$GIB_END_MARKER" '
    $0 == b { inb = 1 }
    inb     { print }
    $0 == e && inb { found = 1; exit }
    END     { exit(found ? 0 : 1) }
  ' || { echo "gib: no complete BEGIN..END baseline block in $file" >&2; return 1; }
}

# _gib_has_markers — read stdin; succeed iff BOTH markers are present as whole lines.
_gib_has_markers() {
  local content; content="$(cat)"
  printf '%s\n' "$content" | grep -qxF "$GIB_BEGIN_MARKER" \
    && printf '%s\n' "$content" | grep -qxF "$GIB_END_MARKER"
}

# _gib_neutralize_l2 <block>
# Read candidate L2 content on stdin; print it with every line that would fight
# the L1 block removed. A line is dropped when — after CRLF and trailing-whitespace
# trimming — it exactly matches a *pattern* line of <block> (comment and blank
# lines of the block are ignored, so they never strip a repo's own comments). This
# does double duty:
#
#   • Negations win: a bare re-hiding pattern the target kept in L2 (e.g. `*.pem`
#     with no `!public.pem`) is identical to the block's own broad pattern, so it
#     is stripped. The file it re-hid stays ignored by the block, and the block's
#     `!public.pem` (which sits after `*.pem` inside the block) is no longer
#     overridden by a later L2 line — the negated path is re-allowed as intended.
#   • Migrate, don't duplicate: an old *unmarkered* baseline pasted into L2 has its
#     pattern lines folded away (they all live in the block now), so upsert stops
#     shipping a second full copy. The genuine ecosystem/OS entries the repo added
#     stay put.
#
# Only pattern lines are matched — never comments — because block comments include
# bare `#` separators that would otherwise clobber a repo's own comment lines.
# Runs of blank lines left behind by the removed patterns are squeezed (leading and
# consecutive blanks dropped) so migration output stays tidy. Idempotent: once the
# duplicate patterns are gone a second pass finds nothing to strip.
_gib_neutralize_l2() {
  local block="$1"
  awk -v block="$block" '
    BEGIN {
      n = split(block, barr, "\n")
      for (i = 1; i <= n; i++) {
        bl = barr[i]
        sub(/\r$/, "", bl)
        sub(/[ \t]+$/, "", bl)
        if (bl ~ /^[ \t]*$/) continue    # skip blank block lines
        if (bl ~ /^[ \t]*#/) continue    # skip comment block lines (incl. bare #)
        drop[bl] = 1
      }
      prev_blank = 1   # squeeze any blank lines that would lead the output
    }
    {
      line = $0
      sub(/\r$/, "", line)
      key = line
      sub(/[ \t]+$/, "", key)
      if (key in drop) next
      is_blank = (key ~ /^[ \t]*$/)
      if (is_blank && prev_blank) next
      print line
      prev_blank = is_blank
    }
  '
}

# upsert_gitignore_baseline <block_file> [existing_file]
# Print the upserted .gitignore content to stdout:
#   • <block_file>   — a file containing the marker-wrapped L1 block (e.g. the
#                      output of gib_extract_baseline_block).
#   • [existing_file]— the target repo's current .gitignore. Absent/empty/missing
#                      is treated as a brand-new file.
#
# Behaviour (idempotent):
#   • existing has the markers  → REPLACE the block in place; content above BEGIN
#                                 is preserved verbatim and the L2 below END is
#                                 neutralized (see below).
#   • existing lacks the markers → INSERT the block on top; the existing file
#                                 becomes L2 below the END marker, neutralized.
#   • existing empty/absent      → output is exactly the block.
#
# L2 neutralization (#809): every L2 line that duplicates a block *pattern* line is
# dropped, so a re-hiding pattern the target kept in L2 (e.g. a bare `*.pem` with no
# `!public.pem`) can't override the block's negations, and an old unmarkered
# baseline pasted into L2 folds into the single block instead of duplicating.
# Genuine per-repo L2 (ecosystem/OS entries) is preserved. See _gib_neutralize_l2.
# Re-running on its own output is a no-op.
upsert_gitignore_baseline() {
  local block_file="${1:-}" existing_file="${2:-}"
  [ -n "$block_file" ] && [ -f "$block_file" ] || { echo "gib: block file not found: ${block_file:-<none>}" >&2; return 2; }

  local block
  block="$(cat "$block_file")"
  if ! printf '%s\n' "$block" | _gib_has_markers; then
    echo "gib: block file $block_file is missing the BEGIN/END markers" >&2
    return 2
  fi

  local existing=""
  if [ -n "$existing_file" ] && [ -f "$existing_file" ]; then
    existing="$(cat "$existing_file")"
  fi

  # Brand-new file: output block only.
  if [ -z "$existing" ]; then
    printf '%s\n' "$block"
    return 0
  fi

  # Check marker state — detect half-open before assuming "marker-less" to avoid
  # silently duplicating markers and preserving the broken fragment.
  local has_begin has_end
  printf '%s\n' "$existing" | grep -qxF "$GIB_BEGIN_MARKER" && has_begin=1 || has_begin=0
  printf '%s\n' "$existing" | grep -qxF "$GIB_END_MARKER"   && has_end=1   || has_end=0
  if [ "$((has_begin + has_end))" -eq 1 ]; then
    echo "gib: half-open marker state in ${existing_file:-<stdin>} (exactly one of BEGIN/END present); refusing to upsert" >&2
    return 2
  fi

  # Marker-less target: block on top, existing content becomes L2 — but neutralize
  # any L2 line that duplicates/fights the block (see _gib_neutralize_l2).
  if [ "$has_begin" -eq 0 ]; then
    local l2
    l2="$(_gib_neutralize_l2 "$block" <<< "$existing")"
    printf '%s\n' "$block"
    [ -n "$l2" ] && printf '%s\n' "$l2"
    return 0
  fi

  # Replace in place: keep anything above BEGIN (standard forbids it, but don't
  # drop bytes) and the full L2 below END; swap only the block itself.
  # Strip CRLF so exact-match works on files with Windows line endings.
  local pre post
  pre="$(tr -d '\r' <<< "$existing" | awk -v b="$GIB_BEGIN_MARKER" '$0 == b { exit } { print }')"
  post="$(tr -d '\r' <<< "$existing" | awk -v e="$GIB_END_MARKER" 'seen { print } $0 == e { seen = 1 }')"
  post="$(_gib_neutralize_l2 "$block" <<< "$post")"

  [ -n "$pre" ] && printf '%s\n' "$pre"
  printf '%s\n' "$block"
  [ -n "$post" ] && printf '%s\n' "$post"
  return 0
}
