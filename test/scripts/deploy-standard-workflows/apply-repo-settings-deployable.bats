#!/usr/bin/env bats
# Issue #1128 (#1045 Step D) — apply-repo-settings.yml joins DEPLOYABLE_WORKFLOWS so
# the weekly standards sweep carries the branch-policy self-heal caller stub (#984)
# to the rest of the fleet, not just the hand-seeded ring repos.
#
# Two guarantees, per AC #4:
#   1. The deployable list now contains apply-repo-settings.yml
#      (is_deployable_workflow apply-repo-settings.yml → 0).
#   2. The ring-pin emission for apply-repo-settings in a STABLE-tier repo resolves
#      to @apply-repo-settings/v1-stable — the tag Step C cut (release v1.4.0).
#
# The ring model itself (RING_REUSABLES + standards/canary-rings.json) already lists
# apply-repo-settings, and the assert-exists guard (#1088, in emit-vform.bats) already
# refuses a non-resolving pin. This file guards only the two Step-D deliverables.

setup() {
  TT_TMP="$(mktemp -d "$BATS_TEST_TMPDIR/ars.XXXXXX")"
  REPO_ROOT="$(cd -- "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  SCRIPT="${REPO_ROOT}/scripts/deploy-standard-workflows.sh"
}

teardown() { rm -rf "$TT_TMP"; }

# Fake gh — mirrors emit-vform.bats. GH_MATCHING_REFS feeds the channel-major probe;
# GH_EXISTING_TAGS feeds the assert-exists single-ref probe; contents 404s (stub
# absent) so a dry-run plans a fresh pin.
install_gh_stub() {
  local bin="${TT_TMP}/bin"
  mkdir -p "$bin"
  cat > "$bin/gh" <<'STUB'
#!/usr/bin/env bash
if [ "${1:-}" = "api" ]; then
  case "$2" in
    *git/ref/tags/*)
      [ -z "${GH_EXISTING_TAGS:-}" ] && exit 0
      tag="${2##*/git/ref/tags/}"
      printf '%s\n' "$GH_EXISTING_TAGS" | grep -qxF "$tag" && exit 0
      printf 'Not Found\n' >&2
      exit 1 ;;
    *matching-refs/tags/*)
      [ -n "${GH_MATCHING_REFS:-}" ] && printf '%s\n' "${GH_MATCHING_REFS}"
      exit 0 ;;
    *contents*)
      exit 1 ;;   # stub absent → deploy plans a fresh pin
  esac
fi
exit 0
STUB
  chmod +x "$bin/gh"
  PATH="${bin}:${PATH}"; export PATH
}

@test "AC4: apply-repo-settings.yml is in DEPLOYABLE_WORKFLOWS (is_deployable_workflow)" {
  run bash -c 'source "$1" >/dev/null 2>&1; is_deployable_workflow apply-repo-settings.yml' _ "$SCRIPT"
  [ "$status" -eq 0 ]
}

@test "AC4: ring-pin emission for apply-repo-settings in a stable-tier repo resolves to v1-stable" {
  # v1 channel tags exist on the host (.github); v1-stable was cut by Step C (v1.4.0).
  export GH_MATCHING_REFS="refs/tags/apply-repo-settings/v1-stable"
  export GH_EXISTING_TAGS="apply-repo-settings/v1-stable"
  install_gh_stub
  # broodly sits in the `*` stable tier for apply-repo-settings (not next/ring0/ring1).
  run env GH_TOKEN=x bash "$SCRIPT" --dry-run --repo broodly --workflow apply-repo-settings.yml
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF '@apply-repo-settings/v1-stable'
  echo "$output" | grep -qE 'Would open PR for broodly .* apply-repo-settings.yml'
}
