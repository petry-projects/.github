# shellcheck shell=bash
# scripts/lib/agent-ingress.sh — identity helpers for the ADR-0007 agent-ingress
# collapse (petry-projects/.github#1226).
#
# A collapsed repo folds its per-role Class-1 caller stubs (dev-lead.yml,
# pr-review-mention.yml, pr-auto-review.yml, …) into ONE
# .github/workflows/agent-ingress.yml carrying EXACTLY ONE job per role, keyed by
# the role name (ADR-0007; reference: petry-projects/.github-private
# docs/architecture/reference/agent-ingress.yml). Every consumer that keyed agent
# identity on the per-role workflow NAME/PATH must instead key on the role JOB:
#
#   - scripts/deploy-standard-workflows.sh never re-seeds a stub whose role an
#     ingress job serves (a resurrected stub double-dispatches every event);
#   - scripts/compliance-audit.sh counts such a role as present;
#   - scripts/lib/agent-rate-limit.sh / scripts/agent-rate-limit-gate.sh count the
#     role's runs from ingress role jobs instead of reading "no workflow" as 0.
#
# Attribution mirrors .github-private scripts/lib/run-attribution.sh: the role is
# the job's caller key (the segment before the first " / " the jobs API prefixes
# onto a reusable call's nested jobs); a role whose only jobs are `skipped`
# (excluded by its event filter) did not run.
#
# All functions are PURE (args / stdin -> stdout, no network) and namespaced
# `agent_ingress_`. Sourcing runs nothing and does not call `set`.

# The collapsed ingress workflow basename (ADR-0007). Overridable for tests/tools.
AGENT_INGRESS_WORKFLOW="${AGENT_INGRESS_WORKFLOW:-agent-ingress.yml}"

# agent_ingress_role_for_workflow <workflow> — the role a per-role workflow
# serves: its basename minus a .yml/.yaml suffix (pre-collapse, one workflow ==
# one role, so the basename IS the role key, e.g. dev-lead.yml -> dev-lead).
agent_ingress_role_for_workflow() {
  local base="${1##*/}"
  base="${base%.yml}"
  base="${base%.yaml}"
  printf '%s\n' "$base"
}

# agent_ingress_is_ingress_workflow <workflow> — 0 iff <workflow> (a path or
# basename) is the collapsed ingress workflow file.
agent_ingress_is_ingress_workflow() {
  [ -n "${1:-}" ] && [ "${1##*/}" = "$AGENT_INGRESS_WORKFLOW" ]
}

# agent_ingress_has_role_job <role> — read a workflow YAML on stdin; 0 iff it
# declares a `jobs.<role>:` key, i.e. the ingress serves <role>. Only a key at
# job indentation (2 spaces) directly under the top-level `jobs:` counts — a
# same-named key elsewhere, a deeper-nested key, a comment, or a role-name prefix
# (`dev-lead-ci:`) never does. CRLF-tolerant.
agent_ingress_has_role_job() {
  local role="${1:-}"
  [ -n "$role" ] || return 1
  awk -v role="$role" '
    BEGIN { injobs = 0; found = 0 }
    { sub(/\r$/, "") }
    /^[^ \t#]/ { injobs = ($0 ~ /^jobs:[ \t]*(#.*)?$/); next }
    injobs && index($0, "  " role ":") == 1 {
      rest = substr($0, length(role) + 4)
      if (rest ~ /^[ \t]*(#.*)?$/ || rest ~ /^[ \t]/) { found = 1; exit }
    }
    END { exit(found ? 0 : 1) }
  '
}

# agent_ingress_gh_error_kind <stderr> — classify a failed `gh run list` /
# `gh api` by its stderr: `missing` for a PERMANENT absence (gh's "could not find
# any workflows named …", or an HTTP 404 / Not Found), `transient` for everything
# else (5xx, rate limit, network, empty). A permanent absence must never be read
# as "zero runs"; a transient one keeps the callers' permissive degrade.
agent_ingress_gh_error_kind() {
  local err="${1:-}"
  case "$err" in
    *"could not find any workflow"*|*"HTTP 404"*|*"Not Found"*) printf 'missing\n' ;;
    *) printf 'transient\n' ;;
  esac
}

# agent_ingress_role_runs <role> — read a JSON array of ingress runs, each
#   {databaseId, status, conclusion?, createdAt, jobs:[{name, status, conclusion}]}
# on stdin and print a JSON array of run-history records for <role> in the SAME
# shape `gh run list --json databaseId,status,conclusion,createdAt` yields for a
# legacy per-role workflow, so downstream counters are unchanged:
#   {databaseId, status, conclusion, createdAt}
#
# Per run, only the role's own jobs (name == role, or "role / <nested>") count:
#   - none, or all `skipped`          -> no record (the role did not run);
#   - any job in_progress             -> status in_progress, conclusion null;
#   - else any job not yet completed  -> status queued, conclusion null;
#   - else completed, conclusion = worst outcome (failure-class > success >
#     cancelled > other), matching run-attribution.sh precedence.
agent_ingress_role_runs() {
  local role="${1:-}"
  jq -c --arg role "$role" '
    def rank(c):
      if   c == "failure" or c == "timed_out" or c == "action_required" or c == "startup_failure" then 5
      elif c == "success"   then 4
      elif c == "cancelled" then 3
      else 2 end;
    (if type == "array" then . else [] end)
    | map(
        . as $run
        | [ ($run.jobs // [])[]
            | select((.name // "") == $role or ((.name // "") | startswith($role + " / ")))
            | select(.conclusion != "skipped") ] as $jobs
        | if ($jobs | length) == 0 then empty
          elif any($jobs[]; .status == "in_progress") then
            {databaseId: $run.databaseId, status: "in_progress", conclusion: null, createdAt: $run.createdAt}
          elif any($jobs[]; .status != "completed") then
            {databaseId: $run.databaseId, status: "queued", conclusion: null, createdAt: $run.createdAt}
          else
            {databaseId: $run.databaseId, status: "completed",
             conclusion: ($jobs | max_by(rank(.conclusion)) | .conclusion),
             createdAt: $run.createdAt}
          end
      )
  '
}
