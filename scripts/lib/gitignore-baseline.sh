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
  awk -v b="$GIB_BEGIN_MARKER" -v e="$GIB_END_MARKER" '
    $0 == b { inb = 1 }
    inb     { print }
    $0 == e && inb { found = 1; exit }
    END     { exit(found ? 0 : 1) }
  ' "$file" || { echo "gib: no complete BEGIN..END baseline block in $file" >&2; return 1; }
}

# _gib_has_markers — read stdin; succeed iff BOTH markers are present as whole lines.
_gib_has_markers() {
  local content; content="$(cat)"
  printf '%s\n' "$content" | grep -qxF "$GIB_BEGIN_MARKER" \
    && printf '%s\n' "$content" | grep -qxF "$GIB_END_MARKER"
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
#                                 and the entire L2 below END are preserved verbatim.
#   • existing lacks the markers → INSERT the block on top; the whole existing file
#                                 becomes L2 below the END marker.
#   • existing empty/absent      → output is exactly the block.
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

  # Brand-new (or marker-less) target: block on top, existing becomes L2.
  if [ -z "$existing" ] || ! printf '%s\n' "$existing" | _gib_has_markers; then
    printf '%s\n' "$block"
    [ -n "$existing" ] && printf '%s\n' "$existing"
    return 0
  fi

  # Replace in place: keep anything above BEGIN (standard forbids it, but don't
  # drop bytes) and the full L2 below END; swap only the block itself.
  local pre post
  pre="$(awk -v b="$GIB_BEGIN_MARKER" '$0 == b { exit } { print }' <<< "$existing")"
  post="$(awk -v e="$GIB_END_MARKER" 'seen { print } $0 == e { seen = 1 }' <<< "$existing")"

  [ -n "$pre" ] && printf '%s\n' "$pre"
  printf '%s\n' "$block"
  [ -n "$post" ] && printf '%s\n' "$post"
  return 0
}
