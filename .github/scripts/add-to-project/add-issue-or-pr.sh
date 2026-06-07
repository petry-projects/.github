#!/usr/bin/env bash
# add-issue-or-pr.sh — add a qualifying issue or PR to the org Initiatives
# project. Qualification:
#   - Must carry the `dev-lead` label
#   - Must NOT carry any of: compliance-audit, health-check, fleet-tracker,
#     daily-report (the noise gate that keeps strategic work distinct from
#     automation-generated work)
#
# Required env:
#   PROJECT_ID            ProjectV2 node ID of the Initiatives project
#   GH_TOKEN              Token with org Projects: Read+write
#
# Optional env:
#   PROJECT_URL           Logged in human-readable messages only
#
# Functions (sourceable):
#   evaluate_noise_gate <labels_json>
#       Returns 0 if the labels qualify, 1 if they don't.
#       Echoes "skip" + reason on stderr when not qualifying.
#   add_content_to_project <content_node_id>
#   process_issue_or_pr <content_node_id> <content_url> <labels_json>

set -euo pipefail

_atp_log() {
  printf '%s\n' "$*"
}

evaluate_noise_gate() {
  if [ "$#" -ne 1 ]; then
    printf '[evaluate_noise_gate] expected 1 arg (labels_json), got %d\n' "$#" >&2
    return 64
  fi
  local labels_json="$1"
  local required="dev-lead"
  # Excluded labels must not appear together with `dev-lead`.
  local excluded=("compliance-audit" "health-check" "fleet-tracker" "daily-report")

  if ! printf '%s' "${labels_json}" | jq -e --arg name "${required}" 'any(.name == $name)' >/dev/null; then
    printf "missing required label '%s'\n" "${required}" >&2
    return 1
  fi

  local ex
  for ex in "${excluded[@]}"; do
    if printf '%s' "${labels_json}" | jq -e --arg name "${ex}" 'any(.name == $name)' >/dev/null; then
      printf "has excluded label '%s'\n" "${ex}" >&2
      return 1
    fi
  done

  return 0
}

add_content_to_project() {
  if [ "$#" -ne 1 ]; then
    printf '[add_content_to_project] expected 1 arg (content_node_id), got %d\n' "$#" >&2
    return 64
  fi
  local content_node_id="$1"

  # shellcheck disable=SC2016  # $projectId/$contentId are GraphQL variables
  gh api graphql \
    -F projectId="${PROJECT_ID}" \
    -F contentId="${content_node_id}" \
    -f query='mutation($projectId:ID!,$contentId:ID!){
      addProjectV2ItemById(input:{projectId:$projectId,contentId:$contentId}){
        item { id }
      }
    }'
}

process_issue_or_pr() {
  if [ "$#" -ne 3 ]; then
    printf '[process_issue_or_pr] expected 3 args (content_node_id content_url labels_json), got %d\n' "$#" >&2
    return 64
  fi
  if [ -z "${PROJECT_ID:-}" ]; then
    printf '[process_issue_or_pr] PROJECT_ID env var is required\n' >&2
    return 64
  fi
  local content_node_id="$1"
  local content_url="$2"
  local labels_json="$3"

  local reason
  if reason=$(evaluate_noise_gate "${labels_json}" 2>&1); then
    _atp_log "Adding ${content_url} to ${PROJECT_URL:-the project}"
    add_content_to_project "${content_node_id}"
  else
    _atp_log "Skip ${content_url}: ${reason}"
  fi
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  process_issue_or_pr \
    "${CONTENT_NODE_ID:?CONTENT_NODE_ID is required}" \
    "${CONTENT_URL:?CONTENT_URL is required}" \
    "${LABELS_JSON:?LABELS_JSON is required}"
fi
