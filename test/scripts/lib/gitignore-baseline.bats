#!/usr/bin/env bats
# Tests for scripts/lib/gitignore-baseline.sh — the shared, idempotent upsert of
# the org secrets baseline (L1) into a repo's .gitignore, preserving per-repo L2.
#
# The lib is pure text transformation (no gh, no network): given the canonical
# marker-wrapped L1 block and an existing .gitignore, it inserts the block on top
# when absent, replaces it in place when present, and never touches the L2 lines
# below the END marker. Shared by bootstrap, deploy/sync, and STORY4 remediation.

load 'helpers/setup'

setup() {
  tt_make_tmpdir
  # shellcheck source=scripts/lib/gitignore-baseline.sh
  source "${TT_SCRIPTS_LIB_DIR}/gitignore-baseline.sh"

  # A small synthetic canonical baseline: markers, a broad pattern carved out by a
  # negation (the discipline the lib must preserve), and the STORY3 anchors.
  BLOCK="${TT_TMP}/canonical.gitignore"
  cat > "$BLOCK" <<EOF
${GIB_BEGIN_MARKER}
# petry-projects baseline — SECRETS ONLY
.env
!.env.example
*.pem
!*.pub
*.key
${GIB_END_MARKER}
EOF
}

teardown() { tt_cleanup_tmpdir; }

# ── extraction ────────────────────────────────────────────────────────────────
@test "gib_extract_baseline_block pulls the BEGIN..END block inclusive" {
  run gib_extract_baseline_block "$BLOCK"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$GIB_BEGIN_MARKER" ]
  [ "${lines[${#lines[@]}-1]}" = "$GIB_END_MARKER" ]
  [[ "$output" == *".env"* ]]
  [[ "$output" == *"!.env.example"* ]]
}

@test "gib_extract_baseline_block fails when no markers are present" {
  local nomarkers="${TT_TMP}/plain"
  printf 'node_modules/\ndist/\n' > "$nomarkers"
  run gib_extract_baseline_block "$nomarkers"
  [ "$status" -ne 0 ]
}

@test "gib_extract_baseline_block works on the real repo /.gitignore (anchors present)" {
  run gib_extract_baseline_block "${TT_REPO_ROOT}/.gitignore"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$GIB_BEGIN_MARKER" ]
  [ "${lines[${#lines[@]}-1]}" = "$GIB_END_MARKER" ]
  # STORY3 anchors must live inside the block.
  grep -qxF '.env' <<< "$output"
  grep -qxF '*.pem' <<< "$output"
  grep -qxF '*.key' <<< "$output"
}

# ── absent → insert on top ────────────────────────────────────────────────────
@test "absent: inserts the block on top, existing content becomes L2 below END" {
  local existing="${TT_TMP}/existing"
  printf '# repo extras\nnode_modules/\ndist/\n' > "$existing"

  run upsert_gitignore_baseline "$BLOCK" "$existing"
  [ "$status" -eq 0 ]

  # Block on top.
  [ "${lines[0]}" = "$GIB_BEGIN_MARKER" ]
  # The END marker precedes the L2 lines.
  local end_ln node_ln
  end_ln="$(printf '%s\n' "$output" | grep -nxF "$GIB_END_MARKER" | head -1 | cut -d: -f1)"
  node_ln="$(printf '%s\n' "$output" | grep -nxF 'node_modules/' | head -1 | cut -d: -f1)"
  [ -n "$end_ln" ] && [ -n "$node_ln" ]
  [ "$end_ln" -lt "$node_ln" ]
  # L2 preserved verbatim.
  grep -qxF 'node_modules/' <<< "$output"
  grep -qxF 'dist/' <<< "$output"
}

@test "absent + empty existing: output is exactly the block" {
  run upsert_gitignore_baseline "$BLOCK"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$GIB_BEGIN_MARKER" ]
  [ "${lines[${#lines[@]}-1]}" = "$GIB_END_MARKER" ]
  # No stray L2.
  [ "$(printf '%s\n' "$output" | grep -cxF "$GIB_BEGIN_MARKER")" -eq 1 ]
}

# ── present → replace in place ────────────────────────────────────────────────
@test "present: replaces a stale block between markers, leaving L2 intact" {
  # A repo whose L1 block is an OLD/short version, with real L2 below END.
  local existing="${TT_TMP}/existing"
  cat > "$existing" <<EOF
${GIB_BEGIN_MARKER}
.env
${GIB_END_MARKER}
# --- repo L2 ---
node_modules/
target/
EOF

  run upsert_gitignore_baseline "$BLOCK" "$existing"
  [ "$status" -eq 0 ]

  # The refreshed block now carries the anchors the stale one lacked.
  grep -qxF '*.pem' <<< "$output"
  grep -qxF '*.key' <<< "$output"
  grep -qxF '!.env.example' <<< "$output"
  # L2 is untouched and still below the (single) END marker.
  grep -qxF 'node_modules/' <<< "$output"
  grep -qxF 'target/' <<< "$output"
  [ "$(printf '%s\n' "$output" | grep -cxF "$GIB_END_MARKER")" -eq 1 ]
  local end_ln l2_ln
  end_ln="$(printf '%s\n' "$output" | grep -nxF "$GIB_END_MARKER" | head -1 | cut -d: -f1)"
  l2_ln="$(printf '%s\n' "$output" | grep -nxF 'target/' | head -1 | cut -d: -f1)"
  [ "$end_ln" -lt "$l2_ln" ]
}

# ── idempotency ───────────────────────────────────────────────────────────────
@test "idempotent: upserting an already-upserted file is a no-op" {
  local existing="${TT_TMP}/existing"
  printf 'node_modules/\ndist/\n' > "$existing"

  local first second
  first="$(upsert_gitignore_baseline "$BLOCK" "$existing")"
  printf '%s\n' "$first" > "${TT_TMP}/after1"
  second="$(upsert_gitignore_baseline "$BLOCK" "${TT_TMP}/after1")"
  [ "$first" = "$second" ]
}

# ── negation discipline ───────────────────────────────────────────────────────
@test "negations survive verbatim and stay immediately after their broad pattern" {
  run upsert_gitignore_baseline "$BLOCK"
  [ "$status" -eq 0 ]
  # !.env.example must appear on the line right after .env (order preserved).
  local env_ln neg_ln
  env_ln="$(printf '%s\n' "$output" | grep -nxF '.env' | head -1 | cut -d: -f1)"
  neg_ln="$(printf '%s\n' "$output" | grep -nxF '!.env.example' | head -1 | cut -d: -f1)"
  [ -n "$env_ln" ] && [ -n "$neg_ln" ]
  [ "$neg_ln" -eq "$((env_ln + 1))" ]
}

@test "replace does not drop a negation the stale block already carried" {
  local existing="${TT_TMP}/existing"
  cat > "$existing" <<EOF
${GIB_BEGIN_MARKER}
.env
!.env.example
${GIB_END_MARKER}
dist/
EOF
  run upsert_gitignore_baseline "$BLOCK" "$existing"
  [ "$status" -eq 0 ]
  grep -qxF '!.env.example' <<< "$output"
  grep -qxF '!*.pub' <<< "$output"
}

# ── half-open marker detection ────────────────────────────────────────────────
@test "upsert fails on a file with only BEGIN marker (half-open state)" {
  local half_open="${TT_TMP}/half-open-begin"
  cat > "$half_open" <<EOF
${GIB_BEGIN_MARKER}
.env
node_modules/
EOF
  run upsert_gitignore_baseline "$BLOCK" "$half_open"
  [ "$status" -eq 2 ]
  [[ "$output" == *"half-open"* ]]
}

@test "upsert fails on a file with only END marker (half-open state)" {
  local half_open="${TT_TMP}/half-open-end"
  cat > "$half_open" <<EOF
.env
node_modules/
${GIB_END_MARKER}
EOF
  run upsert_gitignore_baseline "$BLOCK" "$half_open"
  [ "$status" -eq 2 ]
  [[ "$output" == *"half-open"* ]]
}
