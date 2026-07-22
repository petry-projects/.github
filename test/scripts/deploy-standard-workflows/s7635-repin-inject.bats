#!/usr/bin/env bats
# Issue #879 (defense-in-depth, epic #850) — the deploy driver's in-place repin
# path (`deploy_repo` re-pinning a repo's OWN stub body: BODY_PRESERVING_WORKFLOWS
# and meta-repo channel-consumers) rewrites only `uses:`/`agent_ref` via
# ring_repin_uses. A repinned body that lacks the S7635 marker its template
# mandates would be flagged as marker-drift by the guard yet never RESTORED by the
# repin → a non-converging drift loop the moment a marker-affected workflow enters
# that path. This suite pins the fix: template_requires_s7635_marker detects a
# template that needs the marker, inject_s7635_marker restores it on the repinned
# body, and the composed driver path converges in a single pass.

bats_require_minimum_version 1.5.0

setup() {
  TT_TMP="$(mktemp -d "$BATS_TEST_TMPDIR/s7635.XXXXXX")"
  REPO_ROOT="$(cd -- "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  SCRIPT="${REPO_ROOT}/scripts/deploy-standard-workflows.sh"
  MARKER='# NOSONAR(githubactions:S7635) first-party trusted reusable'
}

teardown() { rm -rf "$TT_TMP"; }

# Fake gh (mirrors feature-ideation-seed-repin.bats):
#   GH_MATCHING_REFS newline-separated `refs/tags/<agent>/…` for matching-refs.
#   GH_CONTENT_B64   base64 of the existing stub (unset → contents 404 = absent).
# A `git/ref/tags/*` lookup (ring_tag_exists) falls through to exit 0 = tag exists.
install_gh_stub() {
  local bin="${TT_TMP}/bin"
  mkdir -p "$bin"
  cat > "$bin/gh" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "api" ]; then
  case "$2" in
    *matching-refs/tags/*)
      [ -n "${GH_MATCHING_REFS:-}" ] && printf '%s\n' "${GH_MATCHING_REFS}"
      exit 0 ;;
    *contents*)
      if [ -n "${GH_CONTENT_B64:-}" ]; then
        printf '{"sha":"abc123","content":"%s"}' "$GH_CONTENT_B64"
        exit 0
      fi
      exit 1 ;;   # simulate 404 — stub absent
  esac
fi
exit 0
STUB
  chmod +x "$bin/gh"
  PATH="${bin}:${PATH}"; export PATH
}

b64() { base64 -w 0 <<<"$1" 2>/dev/null || base64 -b 0 <<<"$1"; }

# ── template_requires_s7635_marker ──────────────────────────────────────────────

@test "template_requires_s7635_marker: true for a template whose secrets: inherit line carries the marker" {
  run bash -c 'source "$1" >/dev/null 2>&1; template_requires_s7635_marker "$2"' \
    _ "$SCRIPT" "${REPO_ROOT}/standards/workflows/auto-rebase.yml"
  [ "$status" -eq 0 ]
}

@test "template_requires_s7635_marker: false for a template with no secrets: inherit line" {
  # add-to-project.yml passes secrets explicitly (no `secrets: inherit`), so it
  # neither trips S7635 nor requires the marker.
  run bash -c 'source "$1" >/dev/null 2>&1; template_requires_s7635_marker "$2"' \
    _ "$SCRIPT" "${REPO_ROOT}/standards/workflows/add-to-project.yml"
  [ "$status" -ne 0 ]
}

@test "template_requires_s7635_marker: false for a bare secrets: inherit line lacking the marker" {
  local tpl="${TT_TMP}/bare.yml"
  printf 'jobs:\n  x:\n    uses: petry-projects/.github/.github/workflows/x-reusable.yml@x/stable\n    secrets: inherit\n' > "$tpl"
  run bash -c 'source "$1" >/dev/null 2>&1; template_requires_s7635_marker "$2"' _ "$SCRIPT" "$tpl"
  [ "$status" -ne 0 ]
}

@test "template_requires_s7635_marker: not fooled by a commented prose mention of secrets: inherit" {
  local tpl="${TT_TMP}/prose.yml"
  printf 'jobs:\n  x:\n    # callers pass secrets: inherit  # NOSONAR(githubactions:S7635) prose\n    uses: petry-projects/.github/.github/workflows/x-reusable.yml@x/stable\n' > "$tpl"
  run bash -c 'source "$1" >/dev/null 2>&1; template_requires_s7635_marker "$2"' _ "$SCRIPT" "$tpl"
  [ "$status" -ne 0 ]
}

# ── inject_s7635_marker ─────────────────────────────────────────────────────────

@test "inject_s7635_marker: a marker-less secrets: inherit line gains the canonical marker" {
  local body="jobs:
  auto-rebase:
    uses: petry-projects/.github/.github/workflows/auto-rebase-reusable.yml@auto-rebase/v2-next
    secrets: inherit"
  run bash -c 'source "$1" >/dev/null 2>&1; inject_s7635_marker' _ "$SCRIPT" <<<"$body"
  [ "$status" -eq 0 ]
  grep -qF "secrets: inherit  ${MARKER}" <<<"$output"
  # indentation preserved
  grep -qE '^    secrets: inherit  # NOSONAR' <<<"$output"
}

@test "inject_s7635_marker: an already-marked line is left untouched (idempotent)" {
  local body="jobs:
  auto-rebase:
    uses: petry-projects/.github/.github/workflows/auto-rebase-reusable.yml@auto-rebase/v2-next
    secrets: inherit  ${MARKER}"
  run bash -c 'source "$1" >/dev/null 2>&1; inject_s7635_marker' _ "$SCRIPT" <<<"$body"
  [ "$status" -eq 0 ]
  [ "$output" = "$body" ]
  # exactly one marker — no double injection
  [ "$(grep -cF 'NOSONAR(githubactions:S7635)' <<<"$output")" -eq 1 ]
}

@test "inject_s7635_marker: a body with no real secrets: inherit line passes through unchanged" {
  # feature-ideation-style secrets BLOCK (explicit keys) — S7635 does not fire, so
  # nothing to inject.
  local body="jobs:
  ideate:
    uses: petry-projects/.github/.github/workflows/feature-ideation-reusable.yml@feature-ideation/v1-stable
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: \${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}"
  run bash -c 'source "$1" >/dev/null 2>&1; inject_s7635_marker' _ "$SCRIPT" <<<"$body"
  [ "$status" -eq 0 ]
  [ "$output" = "$body" ]
}

@test "inject_s7635_marker: composed with ring_repin_uses, converges in one pass" {
  # Faithful to the driver pipeline: repin the uses ref first, then inject. Running
  # inject a SECOND time is a no-op (the drift-loop the fix eliminates).
  local body="jobs:
  auto-rebase:
    uses: petry-projects/.github/.github/workflows/auto-rebase-reusable.yml@auto-rebase/v1-next
    secrets: inherit"
  run bash -c '
    source "$1" >/dev/null 2>&1
    ring_repin_uses auto-rebase auto-rebase/v2-next <<<"$2" | inject_s7635_marker
  ' _ "$SCRIPT" "$body"
  [ "$status" -eq 0 ]
  grep -qF '@auto-rebase/v2-next' <<<"$output"
  grep -qF "secrets: inherit  ${MARKER}" <<<"$output"
  # second pass is a fixpoint — no churn
  local pass2
  pass2="$(bash -c 'source "$1" >/dev/null 2>&1; inject_s7635_marker' _ "$SCRIPT" <<<"$output")"
  [ "$pass2" = "$output" ]
}

# ── End-to-end: the in-place repin path in deploy_repo ──────────────────────────

@test "deploy_repo: an in-place repin of a marker-less consumer stub injects the marker (converges in one pass)" {
  # .github-private consuming auto-rebase via a channel pin is the meta-repo
  # channel-consumer repin path. Its existing stub is marker-LESS; the auto-rebase
  # template REQUIRES the marker, so the repinned body must come out carrying it.
  export GH_MATCHING_REFS="refs/tags/auto-rebase/v2-stable
refs/tags/auto-rebase/v2-next
refs/tags/auto-rebase/v2-ring0
refs/tags/auto-rebase/v2-ring1"
  local existing="jobs:
  auto-rebase:
    uses: petry-projects/.github/.github/workflows/auto-rebase-reusable.yml@auto-rebase/v1-next
    secrets: inherit"
  GH_CONTENT_B64="$(b64 "$existing")"; export GH_CONTENT_B64
  install_gh_stub

  # Source the driver and capture the deployed file instead of opening a PR.
  # --force so the bare/aligned-tier compliance short-circuit does not skip it.
  run env GH_TOKEN=x CAPTURE="${TT_TMP}/deployed.yml" bash -c '
    source "$1" >/dev/null 2>&1
    sd_deploy_files_via_pr() { shift 5; cp "$2" "$CAPTURE"; echo "OPENED file://pr"; }
    FORCE=true
    WORKFLOWS=(auto-rebase.yml)
    deploy_repo ".github-private"
  ' _ "$SCRIPT"
  [ "$status" -eq 0 ]
  [ -f "${TT_TMP}/deployed.yml" ]

  # Repin happened (v1-next → v2-next) AND the marker was restored in one pass.
  grep -qF '@auto-rebase/v2-next' "${TT_TMP}/deployed.yml"
  grep -qF "secrets: inherit  ${MARKER}" "${TT_TMP}/deployed.yml"
  # exactly one secrets: inherit line, exactly one marker — no drift/duplication
  [ "$(grep -cE '^[[:space:]]*secrets:[[:space:]]+inherit' "${TT_TMP}/deployed.yml")" -eq 1 ]
  [ "$(grep -cF 'NOSONAR(githubactions:S7635)' "${TT_TMP}/deployed.yml")" -eq 1 ]
}
