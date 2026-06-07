#!/usr/bin/env bats
# Tests for reconcile-discussion.sh — covers all four corners of the
# discussion state machine (Ideas ± existing, non-Ideas ± existing)
# plus pagination of the existing-draft lookup.

bats_require_minimum_version 1.5.0

load 'helpers/setup'

setup() {
  tt_make_tmpdir
  tt_install_gh_stub
  export PROJECT_ID="PVT_test_project"
  export PROJECT_URL="https://example.invalid/projects/1"
  export GH_TOKEN="t_test"
  export GH_STUB_LOG="${TT_TMP}/gh.log"
  # shellcheck source=/dev/null
  . "${TT_SCRIPTS_DIR}/reconcile-discussion.sh"
}

teardown() {
  tt_cleanup_tmpdir
}

# ---------------------------------------------------------------------------
# Helpers used by tests
# ---------------------------------------------------------------------------

# Write a one-page items response with the given draft titles to STDOUT_FILE.
write_items_page() {
  local out_path="$1"; shift
  local has_next="$1"; shift
  local end_cursor="$1"; shift
  local titles_json='[]'
  for t in "$@"; do
    titles_json=$(jq --arg t "$t" '. + [{"id":("PVTI_" + ($t|@base64|.[:6])),"content":{"title":$t}}]' <<<"$titles_json")
  done
  jq --argjson nodes "$titles_json" \
     --argjson hasNext "$has_next" \
     --arg endCursor "$end_cursor" \
     '{data:{node:{items:{pageInfo:{endCursor:$endCursor, hasNextPage:$hasNext}, nodes:$nodes}}}}' \
     <<<"{}" >"$out_path"
}

# Build a GH_STUB_SCRIPT line "EXIT\tSTDOUT_PATH\tSTDERR_PATH".
gh_script_line() {
  printf '%s\t%s\t%s\n' "$1" "$2" "$3"
}

# Assert that the last gh invocation in GH_STUB_LOG contains all given
# fragments. The stub logs argv via `printf '%q '`, which backslash-escapes
# spaces/brackets/etc.; normalize by stripping the escape backslashes so
# tests can write needles as plain text.
assert_last_invocation_contains() {
  local last
  last=$(tail -n 1 "${GH_STUB_LOG}" | sed 's/\\//g')
  for needle in "$@"; do
    [[ "$last" == *"${needle}"* ]] || {
      printf 'expected last invocation to contain %q\nactual: %s\n' "$needle" "$last" >&2
      return 1
    }
  done
}

# Assert that the gh stub was invoked exactly N times.
assert_invocation_count() {
  local expected="$1"
  local actual
  actual=$(wc -l <"${GH_STUB_LOG}" | tr -d ' ')
  [ "$actual" -eq "$expected" ] || {
    printf 'expected %d gh invocations, got %d:\n%s\n' "$expected" "$actual" "$(cat "${GH_STUB_LOG}")" >&2
    return 1
  }
}

# ---------------------------------------------------------------------------
# Arg validation
# ---------------------------------------------------------------------------

@test "reconcile_discussion: rejects wrong arg count" {
  run reconcile_discussion 1 2 3
  [ "$status" -eq 64 ]
}

@test "reconcile_discussion: fails fast without PROJECT_ID" {
  unset PROJECT_ID
  run reconcile_discussion 42 "Title" "https://x" "Ideas"
  [ "$status" -eq 64 ]
  [[ "$output" == *"PROJECT_ID env var is required"* ]]
}

@test "find_existing_draft_id: rejects wrong arg count" {
  run find_existing_draft_id
  [ "$status" -eq 64 ]
}

# ---------------------------------------------------------------------------
# State machine — Ideas branches
# ---------------------------------------------------------------------------

@test "Ideas + no existing draft → calls addProjectV2DraftIssue" {
  local page="${TT_TMP}/page1.json"
  write_items_page "$page" false "" "[Discussion #999] something else"
  local script="${TT_TMP}/script.txt"
  {
    # Call 1: find_existing_draft_id query (returns no match)
    gh_script_line 0 "$page" "-"
    # Call 2: add_discussion_draft mutation
    gh_script_line 0 "-" "-"
  } >"$script"
  export GH_STUB_SCRIPT="$script"

  run reconcile_discussion 42 "Great idea" "https://example.invalid/d/42" "Ideas"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Adding discussion #42 as draft"* ]]
  assert_invocation_count 2
  assert_last_invocation_contains "addProjectV2DraftIssue" "[Discussion #42] Great idea"
}

@test "Ideas + existing draft → skips (idempotent)" {
  local page="${TT_TMP}/page1.json"
  write_items_page "$page" false "" "[Discussion #42] Stale title"
  local script="${TT_TMP}/script.txt"
  gh_script_line 0 "$page" "-" >"$script"
  export GH_STUB_SCRIPT="$script"

  run reconcile_discussion 42 "New title" "https://example.invalid/d/42" "Ideas"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already tracked"* ]]
  # Only the lookup; no add mutation.
  assert_invocation_count 1
}

# ---------------------------------------------------------------------------
# State machine — non-Ideas branches
# ---------------------------------------------------------------------------

@test "non-Ideas + existing draft → calls deleteProjectV2Item with found id" {
  local page="${TT_TMP}/page1.json"
  write_items_page "$page" false "" "[Discussion #42] Some title"
  # Capture the item id the stub will return so we can assert it later.
  local expected_id
  expected_id=$(jq -r '.data.node.items.nodes[0].id' <"$page")

  local script="${TT_TMP}/script.txt"
  {
    gh_script_line 0 "$page" "-"   # find
    gh_script_line 0 "-" "-"       # delete
  } >"$script"
  export GH_STUB_SCRIPT="$script"

  run reconcile_discussion 42 "Title" "https://example.invalid/d/42" "Show and tell"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removing draft for discussion #42"* ]]
  assert_invocation_count 2
  assert_last_invocation_contains "deleteProjectV2Item" "$expected_id"
}

@test "non-Ideas + no existing draft → no-op" {
  local page="${TT_TMP}/page1.json"
  write_items_page "$page" false "" "[Discussion #1] unrelated"
  local script="${TT_TMP}/script.txt"
  gh_script_line 0 "$page" "-" >"$script"
  export GH_STUB_SCRIPT="$script"

  run reconcile_discussion 42 "Title" "https://example.invalid/d/42" "General"
  [ "$status" -eq 0 ]
  [[ "$output" == *"not tracked"* ]]
  assert_invocation_count 1
}

# ---------------------------------------------------------------------------
# Title prefix matching — no false positives on a numerical prefix
# ---------------------------------------------------------------------------

@test "title prefix is anchored: #42 does not match #420" {
  # The project has a draft for #420 but NOT for #42.
  local page="${TT_TMP}/page1.json"
  write_items_page "$page" false "" "[Discussion #420] longer number"
  local script="${TT_TMP}/script.txt"
  {
    gh_script_line 0 "$page" "-"   # find — should NOT match
    gh_script_line 0 "-" "-"       # add — because no existing match
  } >"$script"
  export GH_STUB_SCRIPT="$script"

  run reconcile_discussion 42 "Title" "https://example.invalid/d/42" "Ideas"
  [ "$status" -eq 0 ]
  assert_invocation_count 2
  assert_last_invocation_contains "addProjectV2DraftIssue"
}

# ---------------------------------------------------------------------------
# Pagination — match lives past the first page
# ---------------------------------------------------------------------------

@test "find_existing_draft_id paginates and finds match on second page" {
  local page1="${TT_TMP}/page1.json"
  local page2="${TT_TMP}/page2.json"
  write_items_page "$page1" true "CUR1" "[Discussion #1] one" "[Discussion #2] two"
  write_items_page "$page2" false ""   "[Discussion #42] forty-two" "[Discussion #43] forty-three"

  local script="${TT_TMP}/script.txt"
  {
    gh_script_line 0 "$page1" "-"
    gh_script_line 0 "$page2" "-"
    gh_script_line 0 "-"      "-"  # subsequent delete (non-Ideas)
  } >"$script"
  export GH_STUB_SCRIPT="$script"

  run reconcile_discussion 42 "Title" "https://example.invalid/d/42" "General"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removing draft for discussion #42"* ]]
  # 2 page fetches + 1 delete = 3
  assert_invocation_count 3
  # Verify second call passed an `after` cursor (the pagination signal).
  local second
  second=$(sed -n '2p' "${GH_STUB_LOG}")
  [[ "$second" == *"cursor"* ]] || {
    printf 'expected second invocation to include cursor; got: %s\n' "$second" >&2
    return 1
  }
}

@test "find_existing_draft_id stops paginating when no more pages and no match" {
  local page1="${TT_TMP}/page1.json"
  local page2="${TT_TMP}/page2.json"
  write_items_page "$page1" true  "CUR1" "[Discussion #1] one"
  write_items_page "$page2" false ""     "[Discussion #2] two"
  local script="${TT_TMP}/script.txt"
  {
    gh_script_line 0 "$page1" "-"
    gh_script_line 0 "$page2" "-"
  } >"$script"
  export GH_STUB_SCRIPT="$script"

  run find_existing_draft_id "[Discussion #999] "
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  assert_invocation_count 2
}
