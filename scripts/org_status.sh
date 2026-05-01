#!/usr/bin/env bash
# Daily org status data collector — runs in GitHub Actions, outputs a markdown report to stdout.
set -euo pipefail

TODAY=$(date -u +%Y-%m-%d)
if [[ "$(uname)" == "Darwin" ]]; then
  SINCE=$(date -u -v-7d +%Y-%m-%d)
else
  SINCE=$(date -u -d '7 days ago' +%Y-%m-%d)
fi
DATA_DIR=$(mktemp -d)
trap 'rm -rf "$DATA_DIR"' EXIT

# ── Repo Discovery ────────────────────────────────────────────────────────────
echo "::group::Discovering repos" >&2
ORG_REPOS=$(gh repo list petry-projects --json name --limit 100 | jq -r '.[].name' | sort)
PERSONAL_REPOS=$(gh repo list don-petry --json name --limit 100 | jq -r '.[].name' | sort)
echo "petry-projects: $(echo "$ORG_REPOS" | wc -l | tr -d ' ') repos  |  don-petry: $(echo "$PERSONAL_REPOS" | wc -l | tr -d ' ') repos" >&2
echo "::endgroup::" >&2

# ── PR Collection + Classification ───────────────────────────────────────────
collect_classify_prs() {
  local owner=$1 repo=$2
  local cursor="null" all_nodes='[]'

  while true; do
    local result
    result=$(gh api graphql \
      -f query='query($owner:String!,$repo:String!,$cursor:String){
        repository(owner:$owner,name:$repo){
          pullRequests(states:OPEN,first:100,after:$cursor){
            pageInfo{hasNextPage endCursor}
            nodes{
              number title createdAt isDraft
              labels(first:5){nodes{name}}
              reviewDecision
              statusCheckRollup{state}
              reviews(last:20){nodes{state}}
            }
          }
        }
      }' \
      -f owner="$owner" -f repo="$repo" -f cursor="$cursor" 2>/dev/null) \
      || result='{"data":{"repository":{"pullRequests":{"pageInfo":{"hasNextPage":false},"nodes":[]}}}}'

    local nodes has_next end_cursor
    nodes=$(echo "$result" | jq '.data.repository.pullRequests.nodes // []')
    has_next=$(echo "$result" | jq -r '.data.repository.pullRequests.pageInfo.hasNextPage // false')
    end_cursor=$(echo "$result" | jq -r '.data.repository.pullRequests.pageInfo.endCursor // "null"')

    all_nodes=$(jq -n --argjson a "$all_nodes" --argjson b "$nodes" '$a + $b')
    [ "$has_next" = "true" ] || break
    cursor="\"$end_cursor\""
  done

  echo "$all_nodes" | jq --arg owner "$owner" --arg repo "$repo" '
    map({
      repo:   ($owner + "/" + $repo),
      number: .number,
      title:  .title,
      opened: (.createdAt | split("T")[0]),
      url:    ("https://github.com/" + $owner + "/" + $repo + "/pull/" + (.number|tostring)),
      labels: [.labels.nodes[].name],
      isDraft: .isDraft,
      ci:     (.statusCheckRollup.state // "null"),
      review: (.reviewDecision // "null"),
      approvals: ([.reviews.nodes[] | select(.state=="APPROVED")] | length),
      needsHumanReview: ([.labels.nodes[].name] | any(. == "needs-human-review")),
      isDepBump: (.title | test("^chore\\(deps")),
      category: (
        if   .isDraft then "Draft"
        elif (.statusCheckRollup.state == "FAILURE" or .statusCheckRollup.state == "ERROR") then "CI Failing"
        elif (.statusCheckRollup.state == "PENDING" or .statusCheckRollup.state == "EXPECTED") then "CI Pending"
        elif .reviewDecision == "CHANGES_REQUESTED" then "Changes Requested"
        elif .reviewDecision == "APPROVED" then "Approved"
        elif .reviewDecision == "REVIEW_REQUIRED" then "Awaiting Review"
        else "No CI / No Policy"
        end
      )
    })'
}

echo "::group::Collecting PR data" >&2
ALL_PRS='[]'
for repo in $ORG_REPOS; do
  prs=$(collect_classify_prs "petry-projects" "$repo")
  count=$(echo "$prs" | jq 'length')
  [ "$count" -gt 0 ] && echo "  petry-projects/$repo: $count open PRs" >&2
  ALL_PRS=$(jq -n --argjson a "$ALL_PRS" --argjson b "$prs" '$a + $b')
done
for repo in $PERSONAL_REPOS; do
  prs=$(collect_classify_prs "don-petry" "$repo")
  count=$(echo "$prs" | jq 'length')
  [ "$count" -gt 0 ] && echo "  don-petry/$repo: $count open PRs" >&2
  ALL_PRS=$(jq -n --argjson a "$ALL_PRS" --argjson b "$prs" '$a + $b')
done
echo "Total open PRs: $(echo "$ALL_PRS" | jq 'length')" >&2
echo "::endgroup::" >&2

# Pre-aggregate PR counts by category per repo (keeps prompt size manageable)
PR_BY_REPO=$(echo "$ALL_PRS" | jq '
  group_by(.repo) | map({
    repo: .[0].repo,
    total: length,
    draft:             ([.[] | select(.category=="Draft")] | length),
    ci_failing:        ([.[] | select(.category=="CI Failing")] | length),
    ci_pending:        ([.[] | select(.category=="CI Pending")] | length),
    changes_requested: ([.[] | select(.category=="Changes Requested")] | length),
    approved:          ([.[] | select(.category=="Approved")] | length),
    awaiting_review:   ([.[] | select(.category=="Awaiting Review")] | length),
    no_ci_policy:      ([.[] | select(.category=="No CI / No Policy")] | length),
    dep_bumps:         ([.[] | select(.isDepBump)] | length)
  }) | sort_by(-.total)')

NEEDS_REVIEW_PRS=$(echo "$ALL_PRS" | jq '[.[] | select(.needsHumanReview)]')

# ── Merge Activity ────────────────────────────────────────────────────────────
echo "::group::Collecting merge activity" >&2
ORG_MERGES=$(gh search prs --owner=petry-projects --merged --merged-at=">=$SINCE" \
  --json number,repository,closedAt --limit 1000 2>/dev/null || echo '[]')
PERSONAL_MERGES=$(gh search prs --owner=don-petry --merged --merged-at=">=$SINCE" \
  --json number,repository,closedAt --limit 1000 2>/dev/null || echo '[]')

MERGE_DAILY=$(jq -n --arg since "$SINCE" --arg today "$TODAY" \
  --argjson org "$ORG_MERGES" --argjson personal "$PERSONAL_MERGES" '
  # Build 8-day date list (since through today inclusive)
  def dates: [range(8) | ($since | strptime("%Y-%m-%d") | mktime) + (. * 86400) | strftime("%Y-%m-%d")];
  # Capture $date before entering the generator so . refers to the right scope
  dates | map(. as $date | {
    date: $date,
    org:      ([$org[]      | select(.closedAt[:10] == $date)] | length),
    personal: ([$personal[] | select(.closedAt[:10] == $date)] | length)
  })')
echo "::endgroup::" >&2

# ── Issues ────────────────────────────────────────────────────────────────────
echo "::group::Collecting issues" >&2
ISSUES_BY_REPO='[]'
for repo in $ORG_REPOS; do
  issues=$(gh issue list --repo "petry-projects/$repo" --state open \
    --json number,title,createdAt,labels --limit 1000 2>/dev/null || echo '[]')
  count=$(echo "$issues" | jq 'length')
  if [ "$count" -gt 0 ]; then
    echo "  petry-projects/$repo: $count open issues" >&2
    entry=$(echo "$issues" | jq --arg repo "petry-projects/$repo" '{repo: $repo, count: length, issues: .}')
    ISSUES_BY_REPO=$(jq -n --argjson a "$ISSUES_BY_REPO" --argjson b "$entry" '$a + [$b]')
  fi
done
for repo in $PERSONAL_REPOS; do
  issues=$(gh issue list --repo "don-petry/$repo" --state open \
    --json number,title,createdAt,labels --limit 1000 2>/dev/null || echo '[]')
  count=$(echo "$issues" | jq 'length')
  if [ "$count" -gt 0 ]; then
    echo "  don-petry/$repo: $count open issues" >&2
    entry=$(echo "$issues" | jq --arg repo "don-petry/$repo" '{repo: $repo, count: length, issues: .}')
    ISSUES_BY_REPO=$(jq -n --argjson a "$ISSUES_BY_REPO" --argjson b "$entry" '$a + [$b]')
  fi
done
echo "::endgroup::" >&2

# ── Discussions ───────────────────────────────────────────────────────────────
echo "::group::Collecting discussions" >&2
DISCUSSIONS=$(gh api graphql -f query='
{
  organization(login:"petry-projects"){
    repositories(first:100){
      nodes{
        name hasDiscussionsEnabled
        discussions(first:50,states:OPEN){
          totalCount
          nodes{
            number title createdAt
            comments{totalCount}
            labels(first:5){nodes{name}}
          }
        }
      }
    }
  }
}' 2>/dev/null | jq '[
  .data.organization.repositories.nodes[]
  | select(.hasDiscussionsEnabled and .discussions.totalCount > 0)
  | {repo: ("petry-projects/" + .name), discussions: .discussions.nodes}
]') || DISCUSSIONS='[]'
echo "::endgroup::" >&2

# ── Build Prompt ──────────────────────────────────────────────────────────────
cat > "$DATA_DIR/prompt.txt" << PROMPT
Generate a daily GitHub org status report for $TODAY.

Use ONLY the data below. Output ONLY the markdown report — no preamble, no commentary.

---

## DATA

### PR Counts by Repo (pre-classified)
$(echo "$PR_BY_REPO" | jq -c '.')

### PRs Needing Human Review (full detail)
$(echo "$NEEDS_REVIEW_PRS" | jq -c '.')

### Merge Activity — Daily Counts (last 7 days, $SINCE to $TODAY)
$(echo "$MERGE_DAILY" | jq -c '.')

### Org Merges Raw (for per-repo breakdown)
$(echo "$ORG_MERGES" | jq -c '[group_by(.repository.name) | .[] | {repo: .[0].repository.name, count: length}] | sort_by(-.count)')

### Personal Merges Raw (for per-repo breakdown)
$(echo "$PERSONAL_MERGES" | jq -c '[group_by(.repository.name) | .[] | {repo: .[0].repository.name, count: length}] | sort_by(-.count)')

### Open Issues by Repo
$(echo "$ISSUES_BY_REPO" | jq -c '.')

### Open Discussions
$(echo "$DISCUSSIONS" | jq -c '.')

---

## REPORT FORMAT

Produce these sections in order:

### \`## Open PRs — Why They're Unmerged (N total)\`
Org-wide blocker summary table (sum all repos):
| Category | Count | % of Total |
|---|---|---|
Rows in this order: Awaiting Review, CI Failing, CI Pending, Changes Requested, Approved, Draft, No CI / No Policy, **TOTAL**

Per-repo breakdown table (omit repos with 0 total PRs):
| Repo | Total | Awaiting Review | CI Failing | CI Pending | Changes Req | Approved | No CI/Policy | Draft |
Add ⚠ next to repo name if CI Failing > 5 or Awaiting Review > 10.

### \`## Open PRs — Needs Human Review\`
Full table for PRs with needsHumanReview == true:
| Repo | PR # | Opened | Title | CI | Approvals |
PR # as markdown link: [#N](url)
CI: PASS (SUCCESS) / FAIL (FAILURE or ERROR) / PENDING / N/A (null)
If none: _none_

### \`## Open PRs — Automation (Dependency Bumps)\`
Counts only per repo (dep_bumps > 0):
| Repo | # Dep PRs |
If none: _none_

### \`## Open Issues (N total)\`
For each repo with issues, show top 20 rows:
| Repo | # | Opened | Title | Labels |
Opened = createdAt date only (YYYY-MM-DD).
If issues count hits 1000, note "(truncated at 1000)" next to repo name.

### \`## Open Discussions\`
| Repo | # | Opened | Title | Replies |
If none: _No open discussions found across petry-projects._

### \`## PR Merge Activity — Last 7 Days\`
Daily table (include zero rows):
| Date | petry-projects | don-petry |
Per-org repo breakdown sorted descending:
| Repo | Merges |
Grand total. Trend: Increasing if avg(last 3 days) > avg(first 3 days), Decreasing if opposite, Flat otherwise.

---

OUTPUT CONTRACT
- Dates: YYYY-MM-DD
- Section headers include total counts: \`## Open Issues (47 total)\`
- Empty sections show _none_, never omit them
- Links: [#N](url)
PROMPT

# ── Generate Report ───────────────────────────────────────────────────────────
# --dangerously-skip-permissions: required in CI to bypass interactive tool-approval prompts
echo "Generating report with Claude..." >&2
claude -p "$(cat "$DATA_DIR/prompt.txt")" --dangerously-skip-permissions 2>/dev/null
