#!/usr/bin/env bats
# Tests for lint-prompt.sh — kills R2 (unescaped shell expansions in
# direct_prompt blocks that YAML/claude-code-action will not interpolate).

load 'helpers/setup'

setup() {
  tt_make_tmpdir
}

teardown() {
  tt_cleanup_tmpdir
}

LINTER="${TT_REPO_ROOT}/.github/scripts/feature-ideation/lint-prompt.sh"

write_yml() {
  local path="$1"
  cat >"$path"
}

@test "lint-prompt: clean prompt passes" {
  write_yml "${TT_TMP}/clean.yml" <<'YML'
jobs:
  analyze:
    steps:
      - uses: anthropics/claude-code-action@v1
        with:
          direct_prompt: |
            You are Mary.
            The date is ${{ env.RUN_DATE }}.
            Repo is ${{ github.repository }}.
YML
  run bash "$LINTER" "${TT_TMP}/clean.yml"
  [ "$status" -eq 0 ]
}

@test "lint-prompt: FAILS on unescaped \$(date)" {
  write_yml "${TT_TMP}/bad.yml" <<'YML'
jobs:
  analyze:
    steps:
      - uses: anthropics/claude-code-action@v1
        with:
          direct_prompt: |
            You are Mary.
            Date: $(date -u +%Y-%m-%d)
YML
  run bash "$LINTER" "${TT_TMP}/bad.yml"
  [ "$status" -eq 1 ]
}

@test "lint-prompt: FAILS on bare \${VAR}" {
  write_yml "${TT_TMP}/bad2.yml" <<'YML'
jobs:
  analyze:
    steps:
      - uses: anthropics/claude-code-action@v1
        with:
          direct_prompt: |
            You are Mary.
            Focus area: ${FOCUS_AREA}
YML
  run bash "$LINTER" "${TT_TMP}/bad2.yml"
  [ "$status" -eq 1 ]
}

@test "lint-prompt: ALLOWS GitHub Actions expressions \${{ }}" {
  write_yml "${TT_TMP}/gh-expr.yml" <<'YML'
jobs:
  analyze:
    steps:
      - uses: anthropics/claude-code-action@v1
        with:
          direct_prompt: |
            Repo: ${{ github.repository }}
            Run: ${{ github.run_id }}
            Inputs: ${{ inputs.focus_area || 'open' }}
YML
  run bash "$LINTER" "${TT_TMP}/gh-expr.yml"
  [ "$status" -eq 0 ]
}

@test "lint-prompt: detects expansions only inside direct_prompt block" {
  write_yml "${TT_TMP}/scoped.yml" <<'YML'
jobs:
  build:
    steps:
      - run: |
          echo "$(date)"  # this is fine — it's a real shell
  analyze:
    steps:
      - uses: anthropics/claude-code-action@v1
        with:
          direct_prompt: |
            This is $(unsafe).
YML
  run bash "$LINTER" "${TT_TMP}/scoped.yml"
  [ "$status" -eq 1 ]
}

@test "lint-prompt: live feature-ideation-reusable.yml lints clean" {
  # Contract: the live reusable workflow must never reintroduce unescaped
  # shell expansions in the prompt block (kills R2).
  workflow="${TT_REPO_ROOT}/.github/workflows/feature-ideation-reusable.yml"
  [ -f "$workflow" ]
  run bash "$LINTER" "$workflow"
  [ "$status" -eq 0 ]
}

@test "lint-prompt: standards caller-stub template lints clean" {
  # The org-standard caller stub template that downstream repos copy.
  workflow="${TT_REPO_ROOT}/standards/workflows/feature-ideation.yml"
  [ -f "$workflow" ]
  run bash "$LINTER" "$workflow"
  [ "$status" -eq 0 ]
}

@test "lint-prompt: scans every .github/workflows file by default" {
  run bash "$LINTER"
  [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------------------
# Coverage of claude-code-action v1 `prompt:` form (in addition to v0 `direct_prompt:`)
# Caught by Copilot review on PR #85 — the original linter only scanned
# `direct_prompt:` and would silently miss R2 regressions in the actual
# reusable workflow which uses the v1 `prompt:` form.
# ---------------------------------------------------------------------------

@test "lint-prompt: scans v1 prompt: blocks (not just direct_prompt:)" {
  write_yml "${TT_TMP}/v1-prompt.yml" <<'YML'
jobs:
  analyze:
    steps:
      - uses: anthropics/claude-code-action@v1
        with:
          prompt: |
            You are Mary.
            Date: $(date -u +%Y-%m-%d)
YML
  run bash "$LINTER" "${TT_TMP}/v1-prompt.yml"
  [ "$status" -eq 1 ]
}

@test "lint-prompt: clean v1 prompt: passes" {
  write_yml "${TT_TMP}/v1-clean.yml" <<'YML'
jobs:
  analyze:
    steps:
      - uses: anthropics/claude-code-action@v1
        with:
          prompt: |
            You are Mary.
            Repo: ${{ github.repository }}
            Read RUN_DATE from the environment at runtime via printenv.
YML
  run bash "$LINTER" "${TT_TMP}/v1-clean.yml"
  [ "$status" -eq 0 ]
}
