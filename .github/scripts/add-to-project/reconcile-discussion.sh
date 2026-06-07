#!/usr/bin/env bash
# reconcile-discussion.sh — keep the org Initiatives project in sync with
# the lifecycle of an Ideas-category discussion.
#
# State machine (entry point: reconcile_discussion):
#   Ideas       + no existing draft → add
#   Ideas       + existing draft    → skip (idempotent dedup)
#   non-Ideas   + existing draft    → delete (cleanup when leaving Ideas)
#   non-Ideas   + no existing draft → no-op
#
# Existing draft lookup is paginated; the project can grow past the
# first 100 items without silently missing matches.
#
# Required env:
#   PROJECT_ID            ProjectV2 node ID of the Initiatives project
#   GH_TOKEN              Token with org Projects: Read+write
#
# Optional env:
#   PROJECT_URL           Logged in human-readable messages only
#   PAGE_SIZE             Items fetched per GraphQL page (default 100)
#
# Functions (sourceable):
#   find_existing_draft_id <title-prefix>
#       Echoes the matching ProjectV2Item id, or empty string if none.
#       Exit 0 on success; non-zero on hard GraphQL failure.
#   add_discussion_draft <title> <body>
#   delete_project_item <item_id>
#   reconcile_discussion <number> <title> <url> <category>

set -euo pipefail

_atp_require_env() {
  if [ -z "${PROJECT_ID:-}" ]; then
    printf '[%s] PROJECT_ID env var is required\n' "$1" >&2
    return 64
  fi
  if [ -z "${GH_TOKEN:-}" ]; then
    printf '::error::[%s] GH_TOKEN is empty. INITIATIVES_APP_ID / INITIATIVES_APP_PRIVATE_KEY are likely unset or stale. See petry-projects/.github#387.\n' "$1" >&2
    return 64
  fi
}

find_existing_draft_id() {
  if [ "$#" -ne 1 ]; then
    printf '[find_existing_draft_id] expected 1 arg (title-prefix), got %d\n' "$#" >&2
    return 64
  fi
  local prefix="$1"
  local page_size="${PAGE_SIZE:-100}"
  # Cursor is a nullable String so a single query body handles both first
  # and subsequent pages. gh's `-F` does type inference and would coerce
  # the literal "null" — we use `-f cursor=null` only conceptually, but
  # the cleanest portable form is to omit the variable on the first call
  # via shell expansion below.
  local cursor=""

  while true; do
    local json
    # shellcheck disable=SC2016  # $projectId/$pageSize/$cursor are GraphQL variables
    if [ -n "${cursor}" ]; then
      json=$(gh api graphql \
        -F projectId="${PROJECT_ID}" \
        -F pageSize="${page_size}" \
        -F cursor="${cursor}" \
        -f query='query($projectId:ID!, $pageSize:Int!, $cursor:String!){
          node(id:$projectId){
            ... on ProjectV2 {
              items(first:$pageSize, after:$cursor){
                pageInfo { endCursor hasNextPage }
                nodes {
                  id
                  content {
                    ... on DraftIssue { title }
                    ... on Issue       { title }
                    ... on PullRequest { title }
                  }
                }
              }
            }
          }
        }')
    else
      # shellcheck disable=SC2016
      json=$(gh api graphql \
        -F projectId="${PROJECT_ID}" \
        -F pageSize="${page_size}" \
        -f query='query($projectId:ID!, $pageSize:Int!){
          node(id:$projectId){
            ... on ProjectV2 {
              items(first:$pageSize){
                pageInfo { endCursor hasNextPage }
                nodes {
                  id
                  content {
                    ... on DraftIssue { title }
                    ... on Issue       { title }
                    ... on PullRequest { title }
                  }
                }
              }
            }
          }
        }')
    fi

    # If the project node itself comes back null (wrong PROJECT_ID, token
    # scope drift, project archived), fail loudly rather than treat it as
    # an empty-result and let the caller add duplicates.
    if [ "$(printf '%s' "${json}" | jq -r '.data.node')" = "null" ]; then
      printf '[find_existing_draft_id] GraphQL returned data.node:null. PROJECT_ID=%s — token may lack access, or the project was deleted.\n' "${PROJECT_ID}" >&2
      return 75
    fi

    # Parse match + page info in ONE jq invocation. Use `first(...)` so
    # jq emits at most one id and exits cleanly even when many candidates
    # match (avoids SIGPIPE from `| head -n 1` under pipefail).
    local parsed match has_next end_cursor match_count
    parsed=$(printf '%s' "${json}" | jq -r \
      --arg prefix "${prefix}" \
      '
        (.data.node.items.nodes
          | map(select(.content.title != null and (.content.title | startswith($prefix))))
        ) as $matches
        | "match=" + (first($matches[].id) // ""),
          "count=" + ($matches | length | tostring),
          "next="  + (.data.node.items.pageInfo.hasNextPage | tostring),
          "end="   + (.data.node.items.pageInfo.endCursor // "")
      ')

    match=$(printf '%s' "${parsed}" | awk -F= '/^match=/ {sub(/^match=/, ""); print; exit}')
    match_count=$(printf '%s' "${parsed}" | awk -F= '/^count=/ {sub(/^count=/, ""); print; exit}')
    has_next=$(printf '%s' "${parsed}"   | awk -F= '/^next=/  {sub(/^next=/, "");  print; exit}')
    end_cursor=$(printf '%s' "${parsed}" | awk -F= '/^end=/   {sub(/^end=/, "");   print; exit}')

    if [ -n "${match}" ]; then
      if [ "${match_count}" != "1" ]; then
        # Multi-match on a single page indicates inconsistent state
        # (manual drafts shadowing automation). Emit a warning so the
        # operator can clean up, but proceed with the first match so the
        # state machine still makes progress.
        printf '[find_existing_draft_id] WARNING: %s drafts match prefix %q. Returning first; reconcile may delete the wrong one.\n' \
          "${match_count}" "${prefix}" >&2
      fi
      printf '%s' "${match}"
      return 0
    fi

    if [ "${has_next}" != "true" ]; then
      return 0
    fi
    cursor="${end_cursor}"
  done
}

add_discussion_draft() {
  if [ "$#" -ne 2 ]; then
    printf '[add_discussion_draft] expected 2 args (title body), got %d\n' "$#" >&2
    return 64
  fi
  local title="$1"
  local body="$2"

  # shellcheck disable=SC2016  # $projectId/$title/$body are GraphQL variables
  gh api graphql \
    -F projectId="${PROJECT_ID}" \
    -F title="${title}" \
    -F body="${body}" \
    -f query='mutation($projectId:ID!,$title:String!,$body:String!){
      addProjectV2DraftIssue(input:{projectId:$projectId,title:$title,body:$body}){
        projectItem { id }
      }
    }' >/dev/null
}

delete_project_item() {
  if [ "$#" -ne 1 ]; then
    printf '[delete_project_item] expected 1 arg (item_id), got %d\n' "$#" >&2
    return 64
  fi
  local item_id="$1"

  # Be idempotent on redelivered webhooks / racing runs: a "Could not
  # resolve" error from a no-longer-present item is the desired final
  # state, not a real failure. Capture stderr to inspect.
  local out
  if ! out=$(gh api graphql \
    -F projectId="${PROJECT_ID}" \
    -F itemId="${item_id}" \
    -f query='mutation($projectId:ID!,$itemId:ID!){
      deleteProjectV2Item(input:{projectId:$projectId,itemId:$itemId}){
        deletedItemId
      }
    }' 2>&1); then
    if printf '%s' "${out}" | grep -q -e 'Could not resolve to a node' -e 'not found'; then
      printf '[delete_project_item] item %s was already gone (idempotent path)\n' "${item_id}" >&2
      return 0
    fi
    printf '%s\n' "${out}" >&2
    return 1
  fi
}

reconcile_discussion() {
  if [ "$#" -ne 4 ]; then
    printf '[reconcile_discussion] expected 4 args (number title url category), got %d\n' "$#" >&2
    return 64
  fi
  _atp_require_env reconcile_discussion || return $?
  local number="$1"
  local title="$2"
  local url="$3"
  local category="$4"

  local prefix="[Discussion #${number}] "
  local existing
  existing=$(find_existing_draft_id "${prefix}")

  if [ "${category}" = "Ideas" ]; then
    if [ -n "${existing}" ]; then
      printf 'Discussion #%s already tracked (item %s); no-op\n' "${number}" "${existing}"
      return 0
    fi
    local full_title="[Discussion #${number}] ${title}"
    local body
    body=$(printf 'Source: %s\n\nAuto-added from Ideas-category discussion.' "${url}")
    printf 'Adding discussion #%s as draft to %s\n' "${number}" "${PROJECT_URL:-the project}"
    add_discussion_draft "${full_title}" "${body}"
    return 0
  fi

  if [ -z "${existing}" ]; then
    printf 'Discussion #%s not tracked (category %q); no-op\n' "${number}" "${category}"
    return 0
  fi
  printf 'Removing draft for discussion #%s (now in category %q); item %s\n' "${number}" "${category}" "${existing}"
  delete_project_item "${existing}"
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  reconcile_discussion \
    "${DISC_NUMBER:?DISC_NUMBER is required}" \
    "${DISC_TITLE:?DISC_TITLE is required}" \
    "${DISC_URL:?DISC_URL is required}" \
    "${DISC_CATEGORY:?DISC_CATEGORY is required}"
fi
