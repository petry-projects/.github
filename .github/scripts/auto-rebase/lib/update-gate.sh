#!/usr/bin/env bash
# Update gate for the auto-rebase reusable workflow (issue #1272).
#
# Decides whether a PR that is BEHIND its base should actually be updated.
# Being merely behind blocks nothing unless one of these holds:
#
#   1. the base branch's effective rules require branches to be up to date
#      (strict required status checks — from rulesets or classic protection);
#   2. the PR is in, or is being added to, a merge queue;
#   3. the PR carries the maintainer opt-in label (`ready_label` input).
#
# A conflicting PR is still attempted so the reusable's existing conflict
# notice → dev-lead recovery path fires. Anything that cannot be read fails
# safe to the pre-gate behaviour (update) and says so.
#
# Tested by test/workflows/auto-rebase/update-gate.bats.
# Contract: see .github/scripts/auto-rebase/README.md

# auto_rebase_strict_policy REPO BRANCH
#   Prints `true` if the branch's effective rules require branches to be up to
#   date, `false` if they do not, `unknown` if that could not be determined.
#   Always returns 0.
auto_rebase_strict_policy() {
  local repo="$1" branch="$2" out strict msg

  # Rulesets: the effective (active) rules for the branch, from every ruleset
  # that targets it (repo- and org-level). Readable with read access.
  if ! out=$(gh api "repos/${repo}/rules/branches/${branch}?per_page=100" 2>/dev/null); then
    echo unknown
    return 0
  fi
  strict=$(printf '%s' "$out" | jq -r '
    if type == "array" then
      [.[] | select(.type == "required_status_checks")
           | .parameters.strict_required_status_checks_policy == true] | any
    else "invalid" end' 2>/dev/null) || strict=""
  case "$strict" in
    true) echo true; return 0 ;;
    false) ;;
    *) echo unknown; return 0 ;;
  esac

  # Classic branch protection. A 404 naming the absence of protection / status
  # checks means "not strict"; any other failure (e.g. 403 for a token without
  # admin access) means the configuration is unreadable.
  if out=$(gh api "repos/${repo}/branches/${branch}/protection/required_status_checks" 2>/dev/null); then
    strict=$(printf '%s' "$out" | jq -r '.strict | if type == "boolean" then tostring else "invalid" end' 2>/dev/null) || strict=""
    case "$strict" in
      true|false) echo "$strict" ;;
      *) echo unknown ;;
    esac
    return 0
  fi
  msg=$(printf '%s' "$out" | jq -r '.message // empty' 2>/dev/null) || msg=""
  case "$msg" in
    "Branch not protected"|"Required status checks not enabled") echo false ;;
    *) echo unknown ;;
  esac
  return 0
}

# auto_rebase_pr_gate_state REPO PR_NUMBER LABEL
#   Prints "IN_QUEUE HAS_LABEL MERGEABLE" for the PR, e.g. "false true MERGEABLE".
#   IN_QUEUE / HAS_LABEL are true|false|unknown; MERGEABLE is the GraphQL
#   MergeableState (MERGEABLE|CONFLICTING|UNKNOWN). IN_QUEUE is true when the
#   PR is in the merge queue or has auto-merge enabled on a queue-enabled base
#   (i.e. is being added to it). An empty LABEL disables the label condition.
#   Always returns 0.
auto_rebase_pr_gate_state() {
  local repo="$1" pr="$2" label="$3" out state
  # shellcheck disable=SC2016 # GraphQL variables, not shell expansions
  local query='query($owner:String!,$name:String!,$number:Int!){repository(owner:$owner,name:$name){pullRequest(number:$number){isInMergeQueue isMergeQueueEnabled autoMergeRequest{enabledAt} mergeable labels(first:100){nodes{name}}}}}'

  if ! out=$(gh api graphql -f query="$query" -f owner="${repo%%/*}" \
      -f name="${repo#*/}" -F number="$pr" 2>/dev/null); then
    echo "unknown unknown UNKNOWN"
    return 0
  fi
  state=$(printf '%s' "$out" | jq -r --arg label "$label" '
    .data.repository.pullRequest
    | if type == "object" then
        "\(.isInMergeQueue == true or (.isMergeQueueEnabled == true and .autoMergeRequest != null)) "
        + "\($label != "" and ([.labels.nodes[]?.name] | index($label) != null)) "
        + "\(.mergeable // "UNKNOWN")"
      else "unknown unknown UNKNOWN" end' 2>/dev/null) || state=""
  echo "${state:-unknown unknown UNKNOWN}"
  return 0
}

# auto_rebase_gate_decide STRICT IN_QUEUE HAS_LABEL MERGEABLE LABEL
#   Pure decision. Prints the reason and returns:
#     0  update (a blocking condition applies, the PR conflicts, or the gate
#        could not be evaluated — fail safe to the pre-gate behaviour)
#     1  skip (none applied)
#     3  undecided: nothing else applies and mergeability is not yet computed
auto_rebase_gate_decide() {
  local strict="$1" in_queue="$2" has_label="$3" mergeable="$4" label="$5"

  if [[ "$strict" == "true" ]]; then
    echo "base branch rules require branches to be up to date"
    return 0
  fi
  if [[ "$in_queue" == "true" ]]; then
    echo "PR is in or being added to a merge queue"
    return 0
  fi
  if [[ "$has_label" == "true" ]]; then
    echo "label '${label}' present"
    return 0
  fi
  if [[ "$strict" != "false" ]]; then
    echo "could not evaluate (base branch rules unreadable) — updating as before"
    return 0
  fi
  if [[ "$in_queue" != "false" || "$has_label" != "false" ]]; then
    echo "could not evaluate (PR merge-queue/label state unreadable) — updating as before"
    return 0
  fi
  case "$mergeable" in
    CONFLICTING)
      echo "merge conflict — attempting so the conflict notice is posted"
      return 0
      ;;
    MERGEABLE)
      echo "none applied (strict up-to-date not required, not in a merge queue, no '${label:-<none>}' label)"
      return 1
      ;;
    *)
      echo "mergeability not yet computed"
      return 3
      ;;
  esac
}

# auto_rebase_update_decision STRICT REPO PR_NUMBER LABEL
#   Gathers the PR's state and applies auto_rebase_gate_decide, re-polling
#   while GitHub is still computing mergeability (common right after a base
#   push). Prints the reason; returns 0 (update) or 1 (skip).
#   Tunables: AUTO_REBASE_MERGEABLE_POLLS (default 5),
#             AUTO_REBASE_MERGEABLE_POLL_SECONDS (default 3).
auto_rebase_update_decision() {
  local strict="$1" repo="$2" pr="$3" label="$4"
  local polls="${AUTO_REBASE_MERGEABLE_POLLS:-5}"
  local delay="${AUTO_REBASE_MERGEABLE_POLL_SECONDS:-3}"
  local in_queue has_label mergeable reason rc i

  if [[ "$strict" == "true" ]]; then
    auto_rebase_gate_decide true "" "" "" "$label"
    return 0
  fi

  for ((i = 1; i <= polls; i++)); do
    read -r in_queue has_label mergeable < <(auto_rebase_pr_gate_state "$repo" "$pr" "$label")
    rc=0
    reason=$(auto_rebase_gate_decide "$strict" "$in_queue" "$has_label" "$mergeable" "$label") || rc=$?
    if [[ "$rc" -ne 3 ]]; then
      echo "$reason"
      return "$rc"
    fi
    if [[ "$i" -lt "$polls" ]]; then sleep "$delay"; fi
  done
  echo "could not evaluate (mergeability still unknown after ${polls} checks) — updating as before"
  return 0
}
