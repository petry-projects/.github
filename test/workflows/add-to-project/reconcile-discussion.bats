#!/usr/bin/env bats
# Tests for reconcile-discussion.sh — covers all four corners of the
# discussion state machine (Ideas ± existing, non-Ideas ± existing),
# pagination of the existing-draft lookup, error paths, and idempotency.

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
# Each title gets a deterministic, unique id based on its full SHA-256 prefix
# (the previous base64-of-first-6-chars scheme made every title share an id).
write_items_page() {
  local out_path="$1"; shift
  local has_next="$1"; shift
  local end_cursor="$1"; shift
  local titles_json='[]'
  for t in "$@"; do
    local id_suffix
    id_suffix=$(printf '%s' "$t" | sha256sum | cut -c1-10)
    titles_json=$(jq --arg t "$t" --arg id "PVTI_${id_suffix}" \
      '. + [{id: $id, content: {title: $t}}]' <<<"$titles_json")
  done
  jq --argjson nodes "$titles_json" \
     --argjson hasNext "$has_next" \
     --arg endCursor "$end_cursor" \
     '{data:{node:{items:{pageInfo:{endCursor:$endCursor, hasNextPage:$hasNext}, nodes:$nodes}}}}' \
     <<<"{}" >"$out_path"
}

# Write a data.node:null response — simulates wrong PROJECT_ID or scope drift.
write_null_node_response() {
  printf '{"data":{"node":null}}\n' >"$1"
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

# Assert that invocation N (1-indexed) contains all given fragments.
assert_invocation_n_contains() {
  local n="$1"; shift
  local row
  row=$(sed -n "${n}p" "${GH_STUB_LOG}" | sed 's/\\//g')
  for needle in "$@"; do
    [[ "$row" == *"${needle}"* ]] || {
      printf 'expected invocation #%d to contain %q\nactual: %s\n' "$n" "$needle" "$row" >&2
      return 1
    }
  done
}

assert_invocation_count() {
  local expected="$1"
  local actual=0
  if [ -f "${GH_STUB_LOG}" ]; then
    actual=$(wc -l <"${GH_STUB_LOG}" | tr -d ' ')
  fi
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

@test "reconcile_discussion: fails fast without PROJECT_ID (stderr-aware)" {
  unset PROJECT_ID
  run --separate-stderr reconcile_discussion 42 "Title" "https://x" "Ideas"
  [ "$status" -eq 64 ]
  [[ "$stderr" == *"PROJECT_ID env var is required"* ]]
}

@test "reconcile_discussion: fails fast with ::error:: when GH_TOKEN is empty" {
  unset GH_TOKEN
  run --separate-stderr reconcile_discussion 42 "Title" "https://x" "Ideas"
  [ "$status" -eq 64 ]
  [[ "$stderr" == *"::error::"* ]]
  [[ "$stderr" == *"GH_TOKEN is empty"* ]]
}

@test "find_existing_draft_id: rejects wrong arg count" {
  run find_existing_draft_id
  [ "$status" -eq 64 ]
}

# ---------------------------------------------------------------------------
# State machine — Ideas branches
# ---------------------------------------------------------------------------

@test "Ideas + no existing draft → ONE addProjectV2DraftIssue with title AND body" {
  local page="${TT_TMP}/page1.json"
  write_items_page "$page" false "" "[Discussion #999] something else"
  local script="${TT_TMP}/script.txt"
  {
    gh_script_line 0 "$page" "-"   # find
    gh_script_line 0 "-" "-"       # add
  } >"$script"
  export GH_STUB_SCRIPT="$script"

  run reconcile_discussion 42 "Great idea" "https://example.invalid/d/42" "Ideas"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Adding discussion #42 as draft"* ]]
  assert_invocation_count 2
  # The add mutation must include the title, the source URL, AND the
  # "Auto-added from Ideas-category" body marker — protects against
  # regressions that drop or empty the body.
  assert_last_invocation_contains \
    "addProjectV2DraftIssue" \
    "Discussion" "#42" "Great" \
    "Source: https://example.invalid/d/42" \
    "Auto-added from Ideas-category"
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
  assert_invocation_count 1
}

# ---------------------------------------------------------------------------
# State machine — non-Ideas branches
# ---------------------------------------------------------------------------

@test "non-Ideas + existing draft → deleteProjectV2Item with the unique found id" {
  local page="${TT_TMP}/page1.json"
  write_items_page "$page" false "" "[Discussion #42] Some title"
  # Each title now has its own SHA-derived id — the assertion can verify
  # the EXACT id was passed to delete, not just 'any deletion happened'.
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

@test "empty category (deleted/transferred payload) + existing draft → delete (cleanup)" {
  # `discussion:deleted` / `discussion:transferred` may deliver an empty
  # or missing discussion.category. Treat as non-Ideas: if a draft exists
  # for the discussion, clean it up.
  local page="${TT_TMP}/page1.json"
  write_items_page "$page" false "" "[Discussion #42] Some title"
  local expected_id
  expected_id=$(jq -r '.data.node.items.nodes[0].id' <"$page")

  local script="${TT_TMP}/script.txt"
  {
    gh_script_line 0 "$page" "-"
    gh_script_line 0 "-" "-"
  } >"$script"
  export GH_STUB_SCRIPT="$script"

  run reconcile_discussion 42 "Title" "https://example.invalid/d/42" ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removing draft for discussion #42"* ]]
  assert_invocation_count 2
  assert_last_invocation_contains "deleteProjectV2Item" "$expected_id"
}

@test "empty category + no existing draft → no-op (deleted before automation tracked it)" {
  local page="${TT_TMP}/page1.json"
  write_items_page "$page" false "" "[Discussion #99] something else"
  local script="${TT_TMP}/script.txt"
  gh_script_line 0 "$page" "-" >"$script"
  export GH_STUB_SCRIPT="$script"

  run reconcile_discussion 42 "Title" "https://example.invalid/d/42" ""
  [ "$status" -eq 0 ]
  [[ "$output" == *"not tracked"* ]]
  assert_invocation_count 1
}

@test "non-Ideas + no existing draft → no-op, one (find) gh call" {
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
# Title prefix matching — no false positives, plus multi-match warning
# ---------------------------------------------------------------------------

@test "title prefix is anchored: #42 does not match #420" {
  local page="${TT_TMP}/page1.json"
  write_items_page "$page" false "" "[Discussion #420] longer number"
  local script="${TT_TMP}/script.txt"
  {
    gh_script_line 0 "$page" "-"
    gh_script_line 0 "-" "-"
  } >"$script"
  export GH_STUB_SCRIPT="$script"

  run reconcile_discussion 42 "Title" "https://example.invalid/d/42" "Ideas"
  [ "$status" -eq 0 ]
  assert_invocation_count 2
  assert_last_invocation_contains "addProjectV2DraftIssue"
}

@test "find_existing_draft_id: multiple matches on one page → warns and returns first (no SIGPIPE crash)" {
  local page="${TT_TMP}/page1.json"
  # Two drafts share the prefix — pathological state, but find should
  # NOT crash via SIGPIPE under pipefail and SHOULD log a warning.
  write_items_page "$page" false "" "[Discussion #42] one" "[Discussion #42] two"
  local script="${TT_TMP}/script.txt"
  gh_script_line 0 "$page" "-" >"$script"
  export GH_STUB_SCRIPT="$script"

  run --separate-stderr find_existing_draft_id "[Discussion #42] "
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  [[ "$stderr" == *"WARNING"* ]]
  [[ "$stderr" == *"drafts match prefix"* ]]
}

# ---------------------------------------------------------------------------
# Pagination — cursor value, not just substring
# ---------------------------------------------------------------------------

@test "find_existing_draft_id paginates: second call's cursor MUST equal page 1's endCursor" {
  local page1="${TT_TMP}/page1.json"
  local page2="${TT_TMP}/page2.json"
  # Use a distinctive cursor value to anchor the assertion.
  write_items_page "$page1" true "MY_DISTINCTIVE_CURSOR" "[Discussion #1] one" "[Discussion #2] two"
  write_items_page "$page2" false ""                      "[Discussion #42] forty-two"

  local script="${TT_TMP}/script.txt"
  {
    gh_script_line 0 "$page1" "-"
    gh_script_line 0 "$page2" "-"
    gh_script_line 0 "-"      "-"   # subsequent delete (non-Ideas)
  } >"$script"
  export GH_STUB_SCRIPT="$script"

  run reconcile_discussion 42 "Title" "https://example.invalid/d/42" "General"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Removing draft for discussion #42"* ]]
  assert_invocation_count 3
  # Call 1 (find page 1) MUST NOT pass a cursor flag.
  local first
  first=$(sed -n '1p' "${GH_STUB_LOG}" | sed 's/\\//g')
  [[ "$first" != *"-F cursor="* ]] || {
    printf 'page-1 call should not pass -F cursor=; got: %s\n' "$first" >&2
    return 1
  }
  # Call 2 (find page 2) MUST pass the exact endCursor from page 1.
  assert_invocation_n_contains 2 "cursor=MY_DISTINCTIVE_CURSOR"
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

# ---------------------------------------------------------------------------
# Robustness — data.node:null fails loudly instead of silently adding duplicates
# ---------------------------------------------------------------------------

@test "find_existing_draft_id: data.node:null → exit 75 with diagnostic, no add/delete" {
  local null_resp="${TT_TMP}/null.json"
  write_null_node_response "$null_resp"
  local script="${TT_TMP}/script.txt"
  gh_script_line 0 "$null_resp" "-" >"$script"
  export GH_STUB_SCRIPT="$script"

  run --separate-stderr find_existing_draft_id "[Discussion #42] "
  [ "$status" -eq 75 ]
  [[ "$stderr" == *"GraphQL returned data.node:null"* ]]
  [[ "$stderr" == *"${PROJECT_ID}"* ]]
}

# ---------------------------------------------------------------------------
# DraftIssue → Issue conversion: lookup still finds the item
# ---------------------------------------------------------------------------

@test "find_existing_draft_id: matches Issue.title too (handles Convert-to-issue)" {
  # Items()...content { ... on Issue { title } } also returns the title;
  # the lookup should NOT miss a draft that's been converted to an issue.
  local page="${TT_TMP}/page1.json"
  jq -n '{data:{node:{items:{pageInfo:{endCursor:"", hasNextPage:false},
    nodes:[{id:"PVTI_converted_issue", content:{title:"[Discussion #42] After conversion"}}]}}}}' >"$page"
  local script="${TT_TMP}/script.txt"
  gh_script_line 0 "$page" "-" >"$script"
  export GH_STUB_SCRIPT="$script"

  run find_existing_draft_id "[Discussion #42] "
  [ "$status" -eq 0 ]
  [ "$output" = "PVTI_converted_issue" ]
}

# ---------------------------------------------------------------------------
# delete_project_item idempotency on redelivered webhook
# ---------------------------------------------------------------------------

@test "delete_project_item: already-deleted item is treated as success (idempotent)" {
  # gh exits non-zero with 'Could not resolve to a node' on second delete.
  local err="${TT_TMP}/err.txt"
  printf 'GraphQL: Could not resolve to a node with the global id of '\''PVTI_gone'\''\n' >"$err"
  local script="${TT_TMP}/script.txt"
  gh_script_line 1 "-" "$err" >"$script"
  export GH_STUB_SCRIPT="$script"

  run --separate-stderr delete_project_item "PVTI_gone"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"already gone"* ]]
}

@test "delete_project_item: real error (not 'not found') is propagated" {
  local err="${TT_TMP}/err.txt"
  printf 'GraphQL: Rate limit exceeded\n' >"$err"
  local script="${TT_TMP}/script.txt"
  gh_script_line 1 "-" "$err" >"$script"
  export GH_STUB_SCRIPT="$script"

  run --separate-stderr delete_project_item "PVTI_real"
  [ "$status" -eq 1 ]
  [[ "$stderr" == *"Rate limit"* ]]
}
