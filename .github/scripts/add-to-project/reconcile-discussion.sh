#!/usr/bin/env bash
# reconcile-discussion.sh — keep the org Initiatives project in sync with
# the lifecycle of an Ideas-category discussion.
#
# State machine (entry point: reconcile_discussion), where "Ideas" is the
# category named by IDEAS_CATEGORY (default "Ideas"):
#   Ideas       + no existing draft → add
#   Ideas       + existing draft    → skip (idempotent dedup)
#   non-Ideas   + existing draft    → delete (cleanup when leaving Ideas)
#   non-Ideas   + no existing draft → no-op
#
# The paginated existing-draft lookup, the draft/add/delete mutations, and
# the env guard live in lib.sh (shared with add-issue-or-pr.sh).
#
# Required env:
#   PROJECT_ID            ProjectV2 node ID of the Initiatives project
#   GH_TOKEN              Token with org Projects: Read+write
#
# Optional env:
#   PROJECT_URL           Logged in human-readable messages only
#   IDEAS_CATEGORY        Discussion category that maps to the board (default Ideas)
#   PAGE_SIZE             Items fetched per GraphQL page (default 100)
#
# Functions (sourceable):
#   find_existing_draft_id <title-prefix>
#   add_discussion_draft <title> <body>
#   reconcile_discussion <number> <title> <url> <category>

set -euo pipefail

_atp_lib_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
. "${_atp_lib_dir}/lib.sh"

# Thin wrappers preserving the discussion-specific names over the shared
# helpers in lib.sh.
find_existing_draft_id() {
  if [ "$#" -ne 1 ]; then
    printf '[find_existing_draft_id] expected 1 arg (title-prefix), got %d\n' "$#" >&2
    return 64
  fi
  find_project_item title-prefix "$1"
}

add_discussion_draft() {
  if [ "$#" -ne 2 ]; then
    printf '[add_discussion_draft] expected 2 args (title body), got %d\n' "$#" >&2
    return 64
  fi
  add_draft_item "$1" "$2"
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
  local ideas_category="${IDEAS_CATEGORY:-Ideas}"

  local prefix="[Discussion #${number}] "
  local existing
  existing=$(find_existing_draft_id "${prefix}")

  if [ "${category}" = "${ideas_category}" ]; then
    if [ -n "${existing}" ]; then
      printf 'Discussion #%s already tracked (item %s); no-op\n' "${number}" "${existing}"
      return 0
    fi
    local full_title="[Discussion #${number}] ${title}"
    local body
    body=$(printf 'Source: %s\n\nAuto-added from %s-category discussion.' "${url}" "${ideas_category}")
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
  # DISC_CATEGORY may legitimately be empty for `deleted` and `transferred`
  # payloads (the discussion may already be gone, or category is null). The
  # non-Ideas branch of reconcile_discussion treats any non-matching value —
  # including "" — as "if a draft exists, clean it up", which is the right
  # behavior for deleted/transferred.
  reconcile_discussion \
    "${DISC_NUMBER:?DISC_NUMBER is required}" \
    "${DISC_TITLE:?DISC_TITLE is required}" \
    "${DISC_URL:?DISC_URL is required}" \
    "${DISC_CATEGORY:-}"
fi
