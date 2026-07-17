#!/usr/bin/env bats
# Unit tests for scripts/apply-repo-settings.sh — the persona opt-out label family
# (petry-projects/.github#756).
#
# The <id>:hands-off labels are DERIVED from the persona manifests
# (personas/<id>/persona.yml in the PUBLIC .github-private repo), never hand-listed:
# adding a persona must require no edit to this script. These tests stub `gh` so the
# derivation, idempotent apply, dry-run, and graceful-degradation paths are exercised
# hermetically.

SCRIPT_DIR="$(cd "$(dirname "$BATS_TEST_FILENAME")/../../.." && pwd)"
APPLY="$SCRIPT_DIR/scripts/apply-repo-settings.sh"

setup() {
  STUB_BIN="$(mktemp -d)"; export PATH="$STUB_BIN:$PATH"
  CALLS="$STUB_BIN/calls.log"; export CALLS
  MANIFEST_DIR="$(mktemp -d)"; export MANIFEST_DIR
  export GH_TOKEN=stub-token
  # Default fixture: one persona (qa-lead) whose manifest declares the conventional
  # <id>:hands-off label. The listing also carries a non-dir entry that MUST be
  # ignored (validate-personas.py actually lives beside the persona dirs today).
  export PERSONA_DIRS_JSON='[{"type":"dir","name":"qa-lead"},{"type":"file","name":"validate-personas.py"}]'
  printf 'triggers:\n  opt_out_label: qa-lead:hands-off\n' > "$MANIFEST_DIR/qa-lead.yml"
  _stub_gh
}

teardown() {
  [ -n "${STUB_BIN:-}" ] && rm -rf "$STUB_BIN"
  [ -n "${MANIFEST_DIR:-}" ] && rm -rf "$MANIFEST_DIR"
  return 0
}

# gh stub:
#   - contents/personas/<id>/persona.yml → the fixture manifest for <id> (raw YAML)
#   - contents/personas                  → $PERSONA_DIRS_JSON (directory listing)
#   - label create ...                   → recorded to $CALLS (a write we assert on)
#   - anything else                      → {}
_stub_gh() {
  cat > "$STUB_BIN/gh" <<EOF
#!/usr/bin/env bash
args="\$*"
case "\$args" in
  *"contents/personas/"*"persona.yml"*)
    id=\$(printf '%s' "\$args" | sed -n 's#.*contents/personas/\([^/?]*\)/persona.yml.*#\1#p')
    [ -f "$MANIFEST_DIR/\$id.yml" ] && cat "$MANIFEST_DIR/\$id.yml"
    exit 0 ;;
  *"contents/personas"*)
    printf '%s' "\${PERSONA_DIRS_JSON:-[]}"; exit 0 ;;
  *"label create"*)
    printf '%s\n' "\$args" >> "$CALLS"; exit 0 ;;
  *) printf '{}'; exit 0 ;;
esac
EOF
  chmod +x "$STUB_BIN/gh"
}

# Source the applier and evaluate an expression against its functions. Sourcing must
# NOT run main() (guarded by BASH_SOURCE) or these helpers are untestable in isolation.
_run_fn() { run bash -c "source '$APPLY'; $*"; }

# ── derivation ────────────────────────────────────────────────────────────────
@test "derives <id>:hands-off from a persona manifest, with the family color" {
  _run_fn persona_opt_out_label_configs
  [ "$status" -eq 0 ]
  [[ "$output" == "qa-lead:hands-off|ededed|"* ]]
}

@test "one consistent color is used for the whole opt-out family" {
  export PERSONA_DIRS_JSON='[{"type":"dir","name":"qa-lead"},{"type":"dir","name":"scrum-master"}]'
  printf 'triggers:\n  opt_out_label: scrum-master:hands-off\n' > "$MANIFEST_DIR/scrum-master.yml"
  _run_fn persona_opt_out_label_configs
  [ "$status" -eq 0 ]
  # Every emitted config carries the same color in field 2.
  run bash -c "printf '%s\n' \"$output\" | awk -F'|' 'NF{print \$2}' | sort -u"
  [ "$output" = "ededed" ]
}

@test "honors the manifest's declared opt_out_label when it overrides the convention" {
  printf 'triggers:\n  opt_out_label: qa-lead:leave-me-be\n' > "$MANIFEST_DIR/qa-lead.yml"
  _run_fn persona_opt_out_label_configs
  [ "$status" -eq 0 ]
  [[ "$output" == "qa-lead:leave-me-be|"* ]]
}

@test "falls back to <id>:hands-off when the manifest omits opt_out_label" {
  printf 'triggers:\n  default_mode: advisory\n' > "$MANIFEST_DIR/qa-lead.yml"
  _run_fn persona_opt_out_label_configs
  [ "$status" -eq 0 ]
  [[ "$output" == "qa-lead:hands-off|"* ]]
}

@test "ignores non-directory entries in the personas listing" {
  _run_fn persona_opt_out_label_configs
  [ "$status" -eq 0 ]
  [[ "$output" != *"validate-personas"* ]]
  run bash -c "printf '%s\n' \"$output\" | grep -c ':hands-off'"
  [ "$output" = "1" ]
}

@test "adding a persona requires no script edit — a new dir yields a new label" {
  export PERSONA_DIRS_JSON='[{"type":"dir","name":"qa-lead"},{"type":"dir","name":"business-analyst"}]'
  printf 'triggers:\n  opt_out_label: business-analyst:hands-off\n' > "$MANIFEST_DIR/business-analyst.yml"
  _run_fn persona_opt_out_label_configs
  [ "$status" -eq 0 ]
  [[ "$output" == *"qa-lead:hands-off|"* ]]
  [[ "$output" == *"business-analyst:hands-off|"* ]]
}

# ── graceful degradation ──────────────────────────────────────────────────────
@test "unavailable manifest listing degrades to no opt-out labels (returns 0)" {
  export PERSONA_DIRS_JSON='not-json'  # jq parse failure on the listing
  _run_fn persona_opt_out_label_configs
  [ "$status" -eq 0 ]
  # No label emitted to stdout; only a WARN (which run merges from stderr) is present.
  [[ "$output" != *":hands-off"* ]]
  [[ "$output" != *"|ededed|"* ]]
}

# ── integration with apply_labels ─────────────────────────────────────────────
@test "apply_labels applies the 7 static labels AND the derived opt-out label" {
  _run_fn apply_labels acme
  [ "$status" -eq 0 ]
  # 7 canonical + 1 derived = 8 label-create writes.
  [ "$(grep -c 'label create' "$CALLS")" -eq 8 ]
  grep -q 'label create security' "$CALLS"
  grep -q 'qa-lead:hands-off' "$CALLS"
}

@test "derived labels are created idempotently via --force" {
  _run_fn apply_labels acme
  [ "$status" -eq 0 ]
  run grep 'qa-lead:hands-off' "$CALLS"
  [[ "$output" == *"--force"* ]]
}

@test "apply_labels --dry-run reports the derived label and writes nothing" {
  export DRY_RUN=true
  _run_fn apply_labels acme
  [ "$status" -eq 0 ]
  [[ "$output" == *"qa-lead:hands-off"* ]]
  [ ! -f "$CALLS" ]
}

@test "apply_labels still succeeds when persona derivation is unavailable" {
  export PERSONA_DIRS_JSON='not-json'
  _run_fn apply_labels acme
  [ "$status" -eq 0 ]
  [ "$(grep -c 'label create' "$CALLS")" -eq 7 ]
  ! grep -q 'hands-off' "$CALLS"
}
