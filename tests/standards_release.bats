#!/usr/bin/env bats
# Unit tests for the standards release-channel decision core
# (scripts/lib/standards-release.sh) and the scripts/cut-standards-release.sh
# orchestrator's pure paths (with gh/git stubbed).
#
# Issue #1091 — cut the standards release channel (standards/v1-stable).
# The channel-tag vocabulary (immutable standards/vX.Y.Z, moving
# standards/v<major>-stable, refuse-to-clobber) mirrors the org's reusable
# versioning model (standards/ci-standards.md, scripts/lib/canary-rollout.sh);
# standards are per-repo so the shape is simpler than the per-agent rings.

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"
LIB="$SCRIPT_DIR/scripts/lib/standards-release.sh"
ORCH="$SCRIPT_DIR/scripts/cut-standards-release.sh"

setup() {
  # shellcheck source=/dev/null
  source "$LIB"
}

# ── tag naming ─────────────────────────────────────────────────────────────────
@test "sr_release_tag: builds the immutable release tag" {
  [ "$(sr_release_tag 1.0.0)" = "standards/v1.0.0" ]
  [ "$(sr_release_tag 2.13.4)" = "standards/v2.13.4" ]
}
@test "sr_release_tag: rejects a non-semver version" {
  run sr_release_tag v1.0.0
  [ "$status" -ne 0 ]
  run sr_release_tag 1.0
  [ "$status" -ne 0 ]
  run sr_release_tag ""
  [ "$status" -ne 0 ]
}
@test "sr_channel_tag: builds the major-scoped moving channel" {
  [ "$(sr_channel_tag 1)" = "standards/v1-stable" ]
  [ "$(sr_channel_tag 2)" = "standards/v2-stable" ]
}
@test "sr_channel_for: maps a version to its major channel" {
  [ "$(sr_channel_for 1.4.0)" = "standards/v1-stable" ]
  [ "$(sr_channel_for 3.0.1)" = "standards/v3-stable" ]
}

# ── release-suffix filter (keeps channel tags out of version math) ─────────────
@test "sr_is_release_suffix: accepts strict vX.Y.Z" {
  run sr_is_release_suffix v1.0.0
  [ "$status" -eq 0 ]
}
@test "sr_is_release_suffix: rejects the moving channel suffix" {
  run sr_is_release_suffix v1-stable
  [ "$status" -ne 0 ]
}
@test "sr_version_from_tag: extracts a bare version from a release tag" {
  [ "$(sr_version_from_tag standards/v1.2.3)" = "1.2.3" ]
}
@test "sr_version_from_tag: emits nothing for a channel tag" {
  [ -z "$(sr_version_from_tag standards/v1-stable)" ]
}

# ── semver compare / max ───────────────────────────────────────────────────────
@test "sr_semver_gt: numeric field ordering (not lexical)" {
  run sr_semver_gt 1.10.0 1.9.0
  [ "$status" -eq 0 ]
  run sr_semver_gt 1.9.0 1.10.0
  [ "$status" -ne 0 ]
}
@test "sr_semver_gt: equal is not greater" {
  run sr_semver_gt 1.0.0 1.0.0
  [ "$status" -ne 0 ]
}
@test "sr_max_version: highest among mixed/invalid tokens" {
  [ "$(sr_max_version 1.0.0 1.10.0 1.2.0 notaversion)" = "1.10.0" ]
  [ -z "$(sr_max_version onlyjunk 1.x)" ]
}

# ── N-1 resolvability (AC #4) ──────────────────────────────────────────────────
@test "sr_current_and_previous: two highest distinct versions" {
  run sr_current_and_previous 1.0.0 1.1.0 1.2.0
  [ "$status" -eq 0 ]
  [ "$output" = $'1.2.0\t1.1.0' ]
}
@test "sr_current_and_previous: single version → empty previous (documented starting state)" {
  run sr_current_and_previous 1.0.0
  [ "$status" -eq 0 ]
  [ "$output" = $'1.0.0\t' ]
}
@test "sr_current_and_previous: no versions → both empty" {
  run sr_current_and_previous
  [ "$status" -eq 0 ]
  [ "$output" = $'\t' ]
}
@test "sr_current_and_previous: dedups and ignores junk, orders numerically" {
  run sr_current_and_previous 1.2.0 1.2.0 1.10.0 junk 1.9.0
  [ "$output" = $'1.10.0\t1.9.0' ]
}

# ── clobber refusal (AC #3 — mirror cut-release.sh) ────────────────────────────
@test "sr_cut_decision: absent tag → CREATE" {
  [ "$(sr_cut_decision "" deadbeef)" = "CREATE" ]
}
@test "sr_cut_decision: existing tag at same commit → NOOP (idempotent)" {
  [ "$(sr_cut_decision deadbeef deadbeef)" = "NOOP" ]
}
@test "sr_cut_decision: existing tag at a different commit → REFUSE (never clobber)" {
  [ "$(sr_cut_decision deadbeef cafef00d)" = "REFUSE" ]
}

# ── orchestrator: dry-run cut is pure + resolves via channel, refuses reclobber ─
# Stub gh + git on PATH so no network/real repo state is touched.
_stub_bin() {
  STUBDIR="$(mktemp -d)"
  export PATH="$STUBDIR:$PATH"
}

@test "cut --dry-run: prints the release tag, channel move, and touches no remote" {
  _stub_bin
  # git: report a HEAD sha and no existing standards tags.
  cat > "$STUBDIR/git" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "rev-parse HEAD") echo "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" ;;
  "for-each-ref"*) : ;;                 # no existing standards/* tags
  *) : ;;
esac
EOF
  # gh may be READ (GET) in a dry run, but must never WRITE — fail loudly on any
  # mutation verb. A missing ref read exits nonzero (as real gh does) → no tag.
  cat > "$STUBDIR/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"-X PATCH"*|*"-X POST"*|*"--method PATCH"*|*"--method POST"*)
    echo "gh WRITE attempted during --dry-run: $*" >&2; exit 99 ;;
esac
# read of a nonexistent ref → nonzero, empty (no existing standards/v1.0.0 tag)
exit 1
EOF
  chmod +x "$STUBDIR/git" "$STUBDIR/gh"
  run bash "$ORCH" cut v1.0.0 --dry-run
  [ "$status" -eq 0 ]
  [[ "$output" == *"standards/v1.0.0"* ]]
  [[ "$output" == *"standards/v1-stable"* ]]
  [[ "$output" == *"aaaaaaaa"* ]]
}

@test "cut: refuses to clobber an existing release tag at a different commit" {
  _stub_bin
  cat > "$STUBDIR/git" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "rev-parse HEAD") echo "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb" ;;
  *) : ;;
esac
EOF
  # gh api resolving the release tag returns a DIFFERENT commit than requested.
  cat > "$STUBDIR/gh" <<'EOF'
#!/usr/bin/env bash
# repos/<repo>/git/ref/tags/standards/v1.0.0 → an annotated/commit sha
if [[ "$*" == *"git/ref/tags/standards/v1.0.0"* ]]; then
  echo "cccccccccccccccccccccccccccccccccccccccc"
  exit 0
fi
exit 0
EOF
  chmod +x "$STUBDIR/git" "$STUBDIR/gh"
  run bash "$ORCH" cut v1.0.0 --commit bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb
  [ "$status" -ne 0 ]
  [[ "$output" == *"REFUSE"* || "$output" == *"refus"* ]]
}

@test "orchestrator: usage on no args, nonzero exit" {
  run bash "$ORCH"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Usage"* || "$output" == *"usage"* ]]
}
