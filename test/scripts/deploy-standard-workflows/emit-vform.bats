#!/usr/bin/env bats
# F5 (epic #657) tests for scripts/deploy-standard-workflows.sh:
#   - a (re)deployed RING stub is pinned to the major-scoped `@<agent>/v<M>-<tier>`
#     form when the agent has a release; the bare `@<agent>/<tier>` form otherwise.
#   - the deploy sweep's drift check (is_already_compliant) honors the `v<M>-` prefix
#     the same way compliance-audit does: a tier-correct v-form stub is compliant,
#     a wrong-tier v-form is still drift.
#
# All runs are --dry-run (no mutating gh calls) against a single --repo/--workflow so
# they are deterministic. A fake `gh` returns the reusable's release tags (for the
# major derivation) and the target repo's existing stub content.

setup() {
  TT_TMP="$(mktemp -d "$BATS_TEST_TMPDIR/stub.XXXXXX")"
  REPO_ROOT="$(cd -- "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  SCRIPT="${REPO_ROOT}/scripts/deploy-standard-workflows.sh"
}

teardown() { rm -rf "$TT_TMP"; }

# Install a fake gh.
#   GH_RELEASE_REFS  newline-separated `refs/tags/<agent>/vX.Y.Z` for matching-refs
#                    (unset/empty → the agent has no release → bare form expected).
#   GH_CONTENT_B64   base64 of the existing stub (unset → contents 404 = missing stub).
install_gh_stub() {
  local bin="${TT_TMP}/bin"
  mkdir -p "$bin"
  cat > "$bin/gh" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "api" ]; then
  case "$2" in
    *matching-refs/tags/*)
      [ -n "${GH_RELEASE_REFS:-}" ] && printf '%s\n' "${GH_RELEASE_REFS}"
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

stub_pinning() {  # <ref> → base64 of a minimal auto-rebase stub pinning the reusable at <ref>
  local body="jobs:
  auto-rebase:
    uses: petry-projects/.github/.github/workflows/auto-rebase-reusable.yml@$1
    secrets: inherit"
  base64 -w 0 <<<"$body" 2>/dev/null || base64 -b 0 <<<"$body"
}

@test "emits @<agent>/v<M>-<tier> when the reusable has a release" {
  export GH_RELEASE_REFS="refs/tags/auto-rebase/v2.3.1
refs/tags/auto-rebase/v1.0.0"
  install_gh_stub   # no GH_CONTENT_B64 → missing stub → deploy plans a (re)pin
  run env GH_TOKEN=x bash "$SCRIPT" --dry-run --repo markets --workflow auto-rebase.yml
  [ "$status" -eq 0 ]
  # markets is a stable-tier repo → v2 major line → @auto-rebase/v2-stable
  echo "$output" | grep -qF '@auto-rebase/v2-stable'
  echo "$output" | grep -qE 'Would open PR for markets .* auto-rebase.yml'
}

@test "emits the bare @<agent>/<tier> form when the reusable has no release" {
  unset GH_RELEASE_REFS   # matching-refs empty → no major
  install_gh_stub
  run env GH_TOKEN=x bash "$SCRIPT" --dry-run --repo markets --workflow auto-rebase.yml
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF '@auto-rebase/stable'
  ! echo "$output" | grep -qF '@auto-rebase/v'
}

@test "drift check treats a tier-correct v<M>-tier stub as compliant (no PR)" {
  export GH_RELEASE_REFS="refs/tags/auto-rebase/v2.0.0"
  GH_CONTENT_B64="$(stub_pinning auto-rebase/v2-ring1)"; export GH_CONTENT_B64
  install_gh_stub
  run env GH_TOKEN=x bash "$SCRIPT" --dry-run --repo TalkTerm --workflow auto-rebase.yml
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'already compliant'
  ! echo "$output" | grep -q 'Would open PR'
}

@test "drift check still flags a WRONG-tier v<M>-tier stub" {
  export GH_RELEASE_REFS="refs/tags/auto-rebase/v2.0.0"
  # v2-ring0 on TalkTerm (a ring1 repo) is the wrong tier → drift.
  GH_CONTENT_B64="$(stub_pinning auto-rebase/v2-ring0)"; export GH_CONTENT_B64
  install_gh_stub
  run env GH_TOKEN=x bash "$SCRIPT" --dry-run --repo TalkTerm --workflow auto-rebase.yml
  [ "$status" -eq 0 ]
  echo "$output" | grep -qE 'Would open PR for TalkTerm .* auto-rebase.yml'
}
