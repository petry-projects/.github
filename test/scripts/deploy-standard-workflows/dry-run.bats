#!/usr/bin/env bats
# Dry-run tests for scripts/deploy-standard-workflows.sh
#
# Exercises the rewired PR-based dry-run path end-to-end with a fake `gh`:
#   - a missing stub  → "Would open PR to create …"
#   - a compliant stub → "already compliant" (no PR planned)
# A single --repo + --workflow keeps the run deterministic (no `gh repo list`),
# and --dry-run guarantees no mutating gh calls are made.

setup() {
  TT_TMP="$(mktemp -d)"
  REPO_ROOT="$(cd -- "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  SCRIPT="${REPO_ROOT}/scripts/deploy-standard-workflows.sh"
  TEMPLATE="${REPO_ROOT}/standards/workflows/add-to-project.yml"
  GH_CALLS="${TT_TMP}/gh-calls.log"; export GH_CALLS
  : > "$GH_CALLS"
}

teardown() { rm -rf "$TT_TMP"; }

# Install a fake gh. GH_CONTENT_B64 unset → contents API 404s (file missing);
# set → contents API returns it as the file body (compliant-stub case).
install_gh_stub() {
  local bin="${TT_TMP}/bin"
  mkdir -p "$bin"
  cat > "$bin/gh" <<'STUB'
#!/usr/bin/env bash
{ printf 'gh'; for a in "$@"; do printf ' %s' "$a"; done; printf '\n'; } >> "$GH_CALLS"
if [ "${1:-}" = "api" ]; then
  case "$2" in
    *contents*)
      if [ -n "${GH_CONTENT_B64:-}" ]; then
        printf '{"sha":"abc123","content":"%s"}' "$GH_CONTENT_B64"
        exit 0
      fi
      exit 1 ;;   # simulate 404 — file absent
  esac
fi
exit 0
STUB
  chmod +x "$bin/gh"
  PATH="${bin}:${PATH}"; export PATH
}

@test "dry-run plans a PR to create a missing stub" {
  install_gh_stub
  run env GH_TOKEN=x bash "$SCRIPT" --dry-run --repo markets --workflow add-to-project.yml
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'DRY RUN — no PRs will be opened'
  echo "$output" | grep -qE 'Would open PR for markets \(branch standards-sync/workflows-[0-9]+\) — 1 stub\(s\): add-to-project.yml'
  # dry-run must not mutate: no branch creation, no PUT, no PR create
  ! grep -q 'git/refs --method POST' "$GH_CALLS"
  ! grep -q 'gh pr create' "$GH_CALLS"
}

@test "dry-run skips a stub that is already compliant" {
  GH_CONTENT_B64="$(base64 -w 0 "$TEMPLATE" 2>/dev/null || base64 -b 0 "$TEMPLATE")"
  export GH_CONTENT_B64
  install_gh_stub
  run env GH_TOKEN=x bash "$SCRIPT" --dry-run --repo markets --workflow add-to-project.yml
  [ "$status" -eq 0 ]
  echo "$output" | grep -q 'already compliant'
  echo "$output" | grep -vq 'Would open PR'
}
