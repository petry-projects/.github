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
  [ "$status" -eq 1 ]
  run sr_release_tag 1.0
  [ "$status" -eq 1 ]
  run sr_release_tag ""
  [ "$status" -eq 1 ]
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
  [ "$status" -eq 1 ]
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
  [ "$status" -eq 1 ]
}
@test "sr_semver_gt: equal is not greater" {
  run sr_semver_gt 1.0.0 1.0.0
  [ "$status" -eq 1 ]
}
@test "sr_max_version: highest among mixed/invalid tokens" {
  [ "$(sr_max_version 1.0.0 1.10.0 1.2.0 notaversion)" = "1.10.0" ]
  [ -z "$(sr_max_version onlyjunk 1.x)" ]
}
@test "leading-zero fields are rejected (no octal misread in (( )) )" {
  run sr_valid_version 1.08.0
  [ "$status" -eq 1 ]
  run sr_is_release_suffix v1.08.0
  [ "$status" -eq 1 ]
  # a non-leading-zero version still parses and compares safely
  [ "$(sr_major 1.8.0)" = "1" ]
  run sr_semver_gt 1.8.0 1.10.0
  [ "$status" -eq 1 ]
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
# read of a nonexistent ref → nonzero with a 404 (as real gh does), so
# _gh_tag_commit treats it as ABSENT rather than as an unavailable-tag error.
echo "gh: Not Found (HTTP 404)" >&2
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
  [ "$status" -eq 1 ]
  [[ "$output" == *"REFUSE"* || "$output" == *"refus"* ]]
}

@test "cut: a non-404 read error aborts (an unavailable tag is not treated as absent)" {
  _stub_bin
  cat > "$STUBDIR/git" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "rev-parse HEAD") echo "dddddddddddddddddddddddddddddddddddddddd" ;;
  *) : ;;
esac
EOF
  # gh read of the release ref fails with a 5xx (NOT a 404): the existing tag is
  # unavailable, not proven absent, so the cut must abort rather than CREATE.
  cat > "$STUBDIR/gh" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *"-X PATCH"*|*"-X POST"*) echo "gh WRITE attempted after unavailable read: $*" >&2; exit 99 ;;
esac
if [[ "$*" == *"git/ref/tags/standards/v1.0.0"* ]]; then
  echo "gh: Internal Server Error (HTTP 500)" >&2
  exit 1
fi
exit 0
EOF
  chmod +x "$STUBDIR/git" "$STUBDIR/gh"
  run bash "$ORCH" cut v1.0.0 --commit dddddddddddddddddddddddddddddddddddddddd
  [ "$status" -ne 0 ]
  [[ "$output" == *"unavailable"* || "$output" == *"could not resolve"* ]]
}

@test "cut: does not move the channel backward when a newer release already exists" {
  _stub_bin
  cat > "$STUBDIR/git" <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "rev-parse HEAD") echo "2222222222222222222222222222222222222222" ;;
  "config --get remote.origin.url") echo "https://github.com/petry-projects/.github.git" ;;
  *) : ;;
esac
EOF
  # Cutting v1.2.0 while v1.3.0 is already published on the same major. The
  # immutable v1.2.0 tag is absent (CREATE succeeds), but the channel move must
  # be SKIPPED — a PATCH here would drag standards/v1-stable backward.
  cat > "$STUBDIR/gh" <<'EOF'
#!/usr/bin/env bash
args="$*"
if [[ "$args" == *"-X PATCH"* ]]; then
  echo "gh PATCH (channel move) attempted despite newer release: $args" >&2
  exit 99
fi
if [[ "$args" == *"git/ref/tags/standards/v1.2.0"* ]]; then
  echo "gh: Not Found (HTTP 404)" >&2; exit 1
fi
if [[ "$args" == *"-X POST"* && "$args" == *"git/tags"* ]]; then
  echo "1111111111111111111111111111111111111111"; exit 0
fi
if [[ "$args" == *"-X POST"* && "$args" == *"git/refs"* ]]; then
  echo "{}"; exit 0
fi
if [[ "$args" == *"matching-refs/tags/standards/v"* ]]; then
  echo "refs/tags/standards/v1.2.0"
  echo "refs/tags/standards/v1.3.0"
  exit 0
fi
exit 0
EOF
  chmod +x "$STUBDIR/git" "$STUBDIR/gh"
  run bash "$ORCH" cut v1.2.0 --commit 2222222222222222222222222222222222222222
  [ "$status" -eq 0 ]
  [[ "$output" == *"standards/v1.3.0"* ]]
  [[ "$output" == *"skipping backward move"* ]]
}

@test "orchestrator: usage on no args, nonzero exit" {
  run bash "$ORCH"
  [ "$status" -eq 2 ]
  [[ "$output" == *"Usage"* || "$output" == *"usage"* ]]
}
