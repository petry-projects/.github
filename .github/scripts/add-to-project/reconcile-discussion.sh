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
#       Exit 0 on success; non-zero only on hard GraphQL failure.
#   add_discussion_draft <title> <body>
#   delete_project_item <item_id>
#   reconcile_discussion <number> <title> <url> <category>

set -euo pipefail

# Helper: emit a key/value pair to GITHUB_OUTPUT and stdout when available.
_atp_log() {
  printf '%s\n' "$*"
}

find_existing_draft_id() {
  if [ "$#" -ne 1 ]; then
    printf '[find_existing_draft_id] expected 1 arg (title-prefix), got %d\n' "$#" >&2
    return 64
  fi
  local prefix="$1"
  local page_size="${PAGE_SIZE:-100}"
  local cursor=""

  while true; do
    local json
    # shellcheck disable=SC2016  # $projectId/$cursor are GraphQL variables
    if [ -n "$cursor" ]; then
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
                  content { ... on DraftIssue { title } }
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
                  content { ... on DraftIssue { title } }
                }
              }
            }
          }
        }')
    fi

    local match
    match=$(printf '%s' "${json}" | jq -r \
      --arg prefix "${prefix}" \
      '.data.node.items.nodes[]
        | select(.content.title != null and (.content.title | startswith($prefix)))
        | .id' | head -n 1)

    if [ -n "${match}" ]; then
      printf '%s' "${match}"
      return 0
    fi

    local has_next
    has_next=$(printf '%s' "${json}" | jq -r '.data.node.items.pageInfo.hasNextPage')
    if [ "${has_next}" != "true" ]; then
      return 0
    fi
    cursor=$(printf '%s' "${json}" | jq -r '.data.node.items.pageInfo.endCursor')
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
    }'
}

delete_project_item() {
  if [ "$#" -ne 1 ]; then
    printf '[delete_project_item] expected 1 arg (item_id), got %d\n' "$#" >&2
    return 64
  fi
  local item_id="$1"

  # shellcheck disable=SC2016  # $projectId/$itemId are GraphQL variables
  gh api graphql \
    -F projectId="${PROJECT_ID}" \
    -F itemId="${item_id}" \
    -f query='mutation($projectId:ID!,$itemId:ID!){
      deleteProjectV2Item(input:{projectId:$projectId,itemId:$itemId}){
        deletedItemId
      }
    }'
}

reconcile_discussion() {
  if [ "$#" -ne 4 ]; then
    printf '[reconcile_discussion] expected 4 args (number title url category), got %d\n' "$#" >&2
    return 64
  fi
  if [ -z "${PROJECT_ID:-}" ]; then
    printf '[reconcile_discussion] PROJECT_ID env var is required\n' >&2
    return 64
  fi
  local number="$1"
  local title="$2"
  local url="$3"
  local category="$4"

  local prefix="[Discussion #${number}] "
  local existing
  existing=$(find_existing_draft_id "${prefix}")

  if [ "${category}" = "Ideas" ]; then
    if [ -n "${existing}" ]; then
      _atp_log "Discussion #${number} already tracked (item ${existing}); no-op"
      return 0
    fi
    local full_title="[Discussion #${number}] ${title}"
    local body
    body=$(printf 'Source: %s\n\nAuto-added from Ideas-category discussion.' "${url}")
    _atp_log "Adding discussion #${number} as draft to ${PROJECT_URL:-the project}"
    add_discussion_draft "${full_title}" "${body}"
    return 0
  fi

  if [ -z "${existing}" ]; then
    _atp_log "Discussion #${number} not tracked (category '${category}'); no-op"
    return 0
  fi
  _atp_log "Removing draft for discussion #${number} (now in category '${category}'); item ${existing}"
  delete_project_item "${existing}"
}

# Run main when executed directly (not sourced).
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  reconcile_discussion \
    "${DISC_NUMBER:?DISC_NUMBER is required}" \
    "${DISC_TITLE:?DISC_TITLE is required}" \
    "${DISC_URL:?DISC_URL is required}" \
    "${DISC_CATEGORY:?DISC_CATEGORY is required}"
fi
