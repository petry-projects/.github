#!/usr/bin/env bats
# Tests for the feature-ideation project_context placeholder guard and the
# expanded REQUIRED_WORKFLOWS added in #844.
#
# #844 promotes feature-ideation.yml, pr-auto-review.yml, and initiative-driver.yml
# to required org-wide. For feature-ideation, presence is necessary but NOT
# sufficient: the seed stub ships a `TODO:`/`Example:` placeholder project_context,
# and a repo that merely has the file but never customised it would run weekly
# ideation on "TODO". feature_ideation_context_is_placeholder() is the pure guard
# the audit uses to raise the `feature-ideation-placeholder-context` finding.
#
# The script is sourced in an isolated subshell (its `main` is guarded, so
# sourcing only defines functions / top-level vars) and the real helpers are
# exercised directly.

bats_require_minimum_version 1.5.0

REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)"
SCRIPT="$REPO_ROOT/scripts/compliance-audit.sh"
SEED="$REPO_ROOT/standards/workflows/feature-ideation.yml"

# feature_ideation_context_is_placeholder returns status 0 when the decoded stub
# still carries the seed template's TODO:/Example: project_context, non-zero once
# it has been customised.
is_placeholder() {
  run bash -c 'source "$1" >/dev/null 2>&1; feature_ideation_context_is_placeholder "$2"' \
    _ "$SCRIPT" "$1"
}

# ---------------------------------------------------------------------------
# Fixtures — trimmed but realistic project_context blocks.
# ---------------------------------------------------------------------------

PLACEHOLDER_STUB=$(cat <<'EOF'
jobs:
  ideate:
    uses: petry-projects/.github/.github/workflows/feature-ideation-reusable.yml@feature-ideation/stable  # NOSONAR
    with:
      project_context: |
        TODO: Replace this with a description of the project and its market.
        Example: "ProjectX is a [type of product] for [target user]. Competitors
        include A, B, C. Key emerging trends in this space: X, Y, Z."
EOF
)

CUSTOMISED_STUB=$(cat <<'EOF'
jobs:
  ideate:
    uses: petry-projects/.github/.github/workflows/feature-ideation-reusable.yml@feature-ideation/stable  # NOSONAR
    with:
      project_context: |
        TalkTerm is a terminal-native AI chat client for developers. Its users are
        power-terminal engineers. Competitors include Warp, Fig, and iTerm2. Key
        emerging trends: local LLMs, the Model Context Protocol, and agentic CLIs.
EOF
)

# ---------------------------------------------------------------------------
# The pure placeholder guard.
# ---------------------------------------------------------------------------

@test "the shipped seed template still-placeholder → guard fires on the untouched stub" {
  is_placeholder "$(cat "$SEED")"
  [ "$status" -eq 0 ]
}

@test "a placeholder project_context (TODO:/Example: sentinel) is flagged" {
  is_placeholder "$PLACEHOLDER_STUB"
  [ "$status" -eq 0 ]
}

@test "a customised project_context is NOT flagged" {
  is_placeholder "$CUSTOMISED_STUB"
  [ "$status" -ne 0 ]
}

@test "a stub with no project_context block at all is NOT flagged as placeholder" {
  # Presence-missing is a separate `error` finding (REQUIRED_WORKFLOWS); the
  # placeholder guard only speaks to a present-but-uncustomised context.
  is_placeholder "jobs:\n  ideate:\n    uses: x@y"
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# REQUIRED_WORKFLOWS now includes all three promoted workflows (org-wide).
# ---------------------------------------------------------------------------

required_workflows() {
  run bash -c 'source "$1" >/dev/null 2>&1; printf "%s\n" "${REQUIRED_WORKFLOWS[@]}"' _ "$SCRIPT"
}

@test "feature-ideation.yml is a universal required workflow" {
  required_workflows
  [ "$status" -eq 0 ]
  grep -qx 'feature-ideation.yml' <<< "$output"
}

@test "pr-auto-review.yml is a required workflow" {
  required_workflows
  grep -qx 'pr-auto-review.yml' <<< "$output"
}

@test "initiative-driver.yml is a required workflow" {
  required_workflows
  grep -qx 'initiative-driver.yml' <<< "$output"
}

# ---------------------------------------------------------------------------
# The BMAD-conditional block is gone — feature-ideation is now universal, not
# gated on the bmad-method ecosystem.
# ---------------------------------------------------------------------------

@test "check_required_workflows no longer carries the bmad-method conditional" {
  run bash -c 'source "$1" >/dev/null 2>&1; declare -f check_required_workflows' _ "$SCRIPT"
  [ "$status" -eq 0 ]
  ! grep -q 'bmad-method' <<< "$output"
  ! grep -q 'missing-feature-ideation.yml' <<< "$output"
}
