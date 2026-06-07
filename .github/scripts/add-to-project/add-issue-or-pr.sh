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
#       Returns 0 if the labels qualify, 1 if they don't (a clean Skip).
#       Returns 64 on bad arg-count and 65 on bad jq input shape — those
#       are programmer/payload bugs and the caller must NOT treat them as
#       a clean skip.
#       Echoes a short reason on stderr when not qualifying.
#   add_content_to_project <content_node_id>
#   process_issue_or_pr <content_node_id> <content_url> <labels_json>

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

evaluate_noise_gate() {
  if [ "$#" -ne 1 ]; then
    printf '[evaluate_noise_gate] expected 1 arg (labels_json), got %d\n' "$#" >&2
    return 64
  fi
  local labels_json="$1"

  # Defensive: GitHub event payloads can deliver labels=null in some
  # delivery variants. Treat any non-array as the empty-labels case
  # rather than letting jq abort the script under set -e.
  if ! printf '%s' "${labels_json}" | jq -e 'type == "array"' >/dev/null 2>&1; then
    labels_json='[]'
  fi

  local required="dev-lead"
  # Excluded labels must not appear together with `dev-lead`. Run in ONE
  # jq invocation rather than spawning per-label so we stay cheap and the
  # policy is declarative in one place.
  local result
  result=$(printf '%s' "${labels_json}" | jq -r \
    --arg required "${required}" \
    --argjson excluded '["compliance-audit","health-check","fleet-tracker","daily-report"]' \
    '
      [.[].name] as $names
      | if ($names | index($required) | not) then
          "missing:" + $required
        else
          ([$excluded[] | select(. as $e | $names | index($e))]) as $hits
          | if ($hits | length) > 0 then "excluded:" + $hits[0]
            else "ok"
            end
        end
    ')

  case "${result}" in
    ok)
      return 0
      ;;
    missing:*)
      printf "missing required label '%s'\n" "${result#missing:}" >&2
      return 1
      ;;
    excluded:*)
      printf "has excluded label '%s'\n" "${result#excluded:}" >&2
      return 1
      ;;
    *)
      printf '[evaluate_noise_gate] unexpected gate result %q\n' "${result}" >&2
      return 65
      ;;
  esac
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
    }' >/dev/null
}

process_issue_or_pr() {
  if [ "$#" -ne 3 ]; then
    printf '[process_issue_or_pr] expected 3 args (content_node_id content_url labels_json), got %d\n' "$#" >&2
    return 64
  fi
  _atp_require_env process_issue_or_pr || return $?
  local content_node_id="$1"
  local content_url="$2"
  local labels_json="$3"

  # Run the gate. Distinguish:
  #   exit 0 → qualifies, add
  #   exit 1 → clean skip, log reason and continue
  #   exit 64/65 → programmer or payload bug, fail loudly so the workflow
  #               run is marked failed instead of silently dropping the item.
  local reason
  set +e
  reason=$(evaluate_noise_gate "${labels_json}" 2>&1)
  local gate_status=$?
  set -e

  case "${gate_status}" in
    0)
      printf 'Adding %s to %s\n' "${content_url}" "${PROJECT_URL:-the project}"
      add_content_to_project "${content_node_id}"
      ;;
    1)
      printf 'Skip %s: %s\n' "${content_url}" "${reason}"
      ;;
    *)
      printf '[process_issue_or_pr] noise gate returned %d (programmer/payload bug, not a clean skip): %s\n' "${gate_status}" "${reason}" >&2
      return "${gate_status}"
      ;;
  esac
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  process_issue_or_pr \
    "${CONTENT_NODE_ID:?CONTENT_NODE_ID is required}" \
    "${CONTENT_URL:?CONTENT_URL is required}" \
    "${LABELS_JSON:?LABELS_JSON is required}"
fi
