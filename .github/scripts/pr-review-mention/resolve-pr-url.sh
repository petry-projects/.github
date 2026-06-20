#!/usr/bin/env bash
# resolve-pr-url.sh — resolve the PR html_url for the pr-review-mention dispatcher.
#
# Why this exists (issue #500):
#   The reusable workflow fires on issue_comment, pull_request_review_comment,
#   AND pull_request[review_requested]. The original step assumed an
#   issue_comment payload and ran `gh api "${{ github.event.issue.pull_request.url }}"`.
#   On a review_requested event there is no `github.event.issue`, so that
#   expands to `gh api ""` → exit 1 and `handle-mention` fails — i.e. requesting
#   a review from @donpetry-bot (the documented trigger) did NOT dispatch.
#
#   This resolver selects the PR URL by event name and guards against an empty
#   value before calling `gh api`, so each trigger resolves a real URL and an
#   unresolvable event fails fast with a clear message instead of `gh api ""`.
#
# Reads from the environment (set by the workflow from the event payload):
#   EVENT_NAME        — github.event_name
#   PR_HTML_URL       — github.event.pull_request.html_url
#                       (pull_request, pull_request_review_comment)
#   ISSUE_PR_API_URL  — github.event.issue.pull_request.url (issue_comment)
#
# Prints the resolved html_url to stdout. Exits non-zero with a message on
# stderr if it cannot resolve a non-empty URL.

set -euo pipefail

resolve_pr_url() {
  local event_name="${EVENT_NAME:-}"
  local url=""

  case "$event_name" in
    pull_request | pull_request_review_comment)
      # review_requested and review-comment payloads expose the PR directly.
      url="${PR_HTML_URL:-}"
      ;;
    issue_comment)
      # Only issue_comment needs an API round-trip: the event carries the PR's
      # API url, not its html_url. Guard the empty case so we never `gh api ""`.
      local api_url="${ISSUE_PR_API_URL:-}"
      if [ -z "$api_url" ]; then
        echo "resolve-pr-url: issue_comment event has no pull_request url (not a PR comment)" >&2
        return 1
      fi
      url="$(gh api "$api_url" --jq '.html_url')"
      ;;
    *)
      echo "resolve-pr-url: unsupported event '$event_name'" >&2
      return 1
      ;;
  esac

  if [ -z "$url" ] || [ "$url" = "null" ]; then
    echo "resolve-pr-url: could not resolve a PR url for event '$event_name'" >&2
    return 1
  fi

  printf '%s\n' "$url"
}

# Run when executed directly; stay quiet when sourced (e.g. by unit tests).
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
  resolve_pr_url
fi
