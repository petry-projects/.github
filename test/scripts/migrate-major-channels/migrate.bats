#!/usr/bin/env bats
# F5 (epic #657) tests for scripts/migrate-major-channels.sh — the DRY_RUN-aware,
# App-token gh-api migration helper (never direct-push):
#   (a) create <agent>/v<M>-<tier> for every ring tier at the SAME commit as the
#       bare <agent>/<tier>, idempotent (skip if the v-tag already exists);
#   (b) --retire-bare <agent> deletes the bare-tier tags ONLY when no enrolled
#       consumer still pins them — it refuses otherwise.
#
# A fake `gh` supplies the reusable's release tags (for the major), the bare-tier
# tag commits, v-tag existence, and consumer stub contents. Mutating calls are
# logged to GH_CALLS so a DRY_RUN can be proven side-effect-free.

setup() {
  TT_TMP="$(mktemp -d "$BATS_TEST_TMPDIR/stub.XXXXXX")"
  REPO_ROOT="$(cd -- "${BATS_TEST_DIRNAME}/../../.." && pwd)"
  SCRIPT="${REPO_ROOT}/scripts/migrate-major-channels.sh"
  GH_CALLS="${TT_TMP}/gh-calls.log"; export GH_CALLS
  : > "$GH_CALLS"
  RINGS="${TT_TMP}/canary-rings.json"; export RINGS
  cat > "$RINGS" <<'JSON'
{
  "org_infra_repos": ["petry-projects/.github", "petry-projects/.github-private"],
  "agents": {
    "foo": {
      "host": "petry-projects/repoA",
      "reusable": ".github/workflows/foo-reusable.yml",
      "rings": [
        { "channel": "next",   "order": 0, "members": ["$host"] },
        { "channel": "ring0",  "order": 1, "members": ["$org_infra"] },
        { "channel": "ring1",  "order": 2, "members": ["petry-projects/consumerX"] },
        { "channel": "stable", "order": 3, "members": ["*"] }
      ]
    }
  }
}
JSON
}

teardown() { rm -rf "$TT_TMP"; }

# Fake gh. Env knobs:
#   FOO_MAJOR_REFS  matching-refs output for foo's release tags (empty → no major)
#   VTAG_EXISTS     if "true", every foo/v<M>-<tier> lookup reports the tag exists
#   CONSUMER_REF    the ref the consumerX stub pins (e.g. foo/ring1 or foo/v2-ring1)
install_gh_stub() {
  local bin="${TT_TMP}/bin"; mkdir -p "$bin"
  cat > "$bin/gh" <<'STUB'
#!/usr/bin/env bash
{ printf 'gh'; for a in "$@"; do printf ' %s' "$a"; done; printf '\n'; } >> "$GH_CALLS"
[ "${1:-}" = "api" ] || { exit 0; }
# find the path arg (first non-flag after 'api')
path=""
for a in "$@"; do case "$a" in -*|api) ;; *) path="$a"; break ;; esac; done
case "$path" in
  *matching-refs/tags/foo/v*)
    [ -n "${FOO_MAJOR_REFS:-}" ] && printf '%s\n' "${FOO_MAJOR_REFS}"
    exit 0 ;;
  *git/ref/tags/foo/v*)                 # v-tag existence / commit lookup
    if [ "${VTAG_EXISTS:-false}" = "true" ]; then
      printf 'ccccccccccccccccccccccccccccccccccccccc\tcommit\n'; exit 0
    fi
    exit 1 ;;                           # v-tag absent
  *git/ref/tags/foo/*)                  # bare-tier tag → resolves to a commit
    printf 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef\tcommit\n'; exit 0 ;;
  *contents/.github/workflows/foo.yml*) # consumer stub content as JSON
    body="    uses: petry-projects/.github/.github/workflows/foo-reusable.yml@${CONSUMER_REF:-foo/ring1}"
    # Only emit an agent_ref: line when the test asks for one (NO_AGENT_REF omits it —
    # the common case: a stub with a uses: pin but no agent_ref input).
    if [ "${NO_AGENT_REF:-false}" != "true" ]; then
      body="${body}
    with:
      agent_ref: ${AGENT_REF:-${CONSUMER_REF:-foo/ring1}}"
    fi
    b64="$(printf '%s' "$body" | base64 | tr -d '\n')"
    printf '{"content":"%s"}' "$b64"
    exit 0 ;;
  *git/refs*) exit 0 ;;                 # create/delete ref (mutating)
esac
exit 0
STUB
  chmod +x "$bin/gh"
  PATH="${bin}:${PATH}"; export PATH
}

@test "DRY_RUN plans same-commit v-tag creation for every tier, no mutating calls" {
  export FOO_MAJOR_REFS="refs/tags/foo/v2.1.0"
  install_gh_stub
  run env GH_TOKEN=x DRY_RUN=true CANARY_RINGS="$RINGS" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  # all four tiers planned against the SAME bare commit (deadbeef…)
  echo "$output" | grep -qF 'foo/v2-next'
  echo "$output" | grep -qF 'foo/v2-ring0'
  echo "$output" | grep -qF 'foo/v2-ring1'
  echo "$output" | grep -qF 'foo/v2-stable'
  echo "$output" | grep -qF 'deadbeefdeadbeef'
  # DRY_RUN must not create any ref
  ! grep -qE 'POST .*git/refs' "$GH_CALLS"
}

@test "idempotent — skips a tier whose v-tag already exists" {
  export FOO_MAJOR_REFS="refs/tags/foo/v2.1.0"
  export VTAG_EXISTS=true
  install_gh_stub
  run env GH_TOKEN=x DRY_RUN=true CANARY_RINGS="$RINGS" bash "$SCRIPT"
  [ "$status" -eq 0 ]
  echo "$output" | grep -qiE 'foo/v2-stable.*(exist|skip)'
  # nothing planned for creation since all exist
  ! grep -qi 'would create' <<< "$output"
}

@test "--retire-bare refuses while an enrolled consumer still pins bare" {
  export FOO_MAJOR_REFS="refs/tags/foo/v2.1.0"
  export CONSUMER_REF="foo/ring1"   # consumerX still on the bare tier
  install_gh_stub
  run env GH_TOKEN=x DRY_RUN=true CANARY_RINGS="$RINGS" bash "$SCRIPT" --retire-bare foo
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi 'refuse'
  echo "$output" | grep -qF 'consumerX'
  # guard must not delete any tag
  ! grep -qE 'DELETE .*git/refs' "$GH_CALLS"
}

@test "--retire-bare proceeds (dry-run) when no enrolled consumer pins bare" {
  export FOO_MAJOR_REFS="refs/tags/foo/v2.1.0"
  export CONSUMER_REF="foo/v2-ring1"   # consumerX already migrated to the v-form (uses: AND agent_ref)
  install_gh_stub
  run env GH_TOKEN=x DRY_RUN=true CANARY_RINGS="$RINGS" bash "$SCRIPT" --retire-bare foo
  [ "$status" -eq 0 ]
  echo "$output" | grep -qiE 'would delete .*foo/(stable|ring1)'
  ! grep -qE 'DELETE .*git/refs' "$GH_CALLS"
}

@test "--retire-bare proceeds when the stub has a v-form uses: pin and NO agent_ref (must not fail-close on the empty grep)" {
  export FOO_MAJOR_REFS="refs/tags/foo/v2.1.0"
  export CONSUMER_REF="foo/v2-ring1"   # uses: v-form
  export NO_AGENT_REF="true"            # stub carries no agent_ref: line (the common case)
  install_gh_stub
  run env GH_TOKEN=x DRY_RUN=true CANARY_RINGS="$RINGS" bash "$SCRIPT" --retire-bare foo
  [ "$status" -eq 0 ]
  echo "$output" | grep -qiE 'would delete .*foo/(stable|ring1)'
  ! echo "$output" | grep -qi 'could not read'   # must NOT fail-close
}

@test "--retire-bare refuses when uses: is v-form but agent_ref: is still bare (regression: broke dev-lead)" {
  export FOO_MAJOR_REFS="refs/tags/foo/v2.1.0"
  export CONSUMER_REF="foo/v2-ring1"   # uses: pin already migrated…
  export AGENT_REF="foo/ring1"          # …but agent_ref: still bare (the load-bearing checkout ref)
  install_gh_stub
  run env GH_TOKEN=x DRY_RUN=true CANARY_RINGS="$RINGS" bash "$SCRIPT" --retire-bare foo
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi 'refuse'
  echo "$output" | grep -qF 'consumerX'
  ! grep -qE 'DELETE .*git/refs' "$GH_CALLS"
}

@test "--emit-repins lists enrolled consumers still on a bare tier with the v-form to move to" {
  export FOO_MAJOR_REFS="refs/tags/foo/v2.1.0"
  export CONSUMER_REF="foo/ring1"   # consumerX still on the bare tier
  install_gh_stub
  run env GH_TOKEN=x CANARY_RINGS="$RINGS" bash "$SCRIPT" --emit-repins --agent foo
  [ "$status" -eq 0 ]
  echo "$output" | grep -qF 'consumerX'
  echo "$output" | grep -qF 'foo/v2-ring1'
}
