#!/usr/bin/env bats
# Issue #1226 (Gap 1, AC #3) — check_required_workflows must treat a required
# role served by an ADR-0007 agent-ingress.yml JOB as PRESENT.
#
# A collapsed repo deletes its per-role caller stubs (dev-lead.yml,
# pr-review-mention.yml, pr-auto-review.yml) and serves each role from one job of
# .github/workflows/agent-ingress.yml. Before this fix the audit read the deleted
# file as `missing-<wf>` and flagged the repo non-compliant forever.
#
# The script is sourced (its main is guarded) and gh_api is replaced by a fake
# that serves a scripted set of present workflow files plus an optional ingress.

bats_require_minimum_version 1.5.0

SCRIPT="$(cd "$BATS_TEST_DIRNAME/../../.." && pwd)/scripts/compliance-audit.sh"

# run_check <present_wfs> <ingress_roles> [listing_err]
#   present_wfs   space-separated workflow files that exist in the repo
#   ingress_roles space-separated role jobs in agent-ingress.yml ("" ⇒ no ingress)
#   listing_err   non-empty ⇒ the workflows-directory listing fails (optional)
# Prints the `check` of every finding filed, one per line.
run_check() {
  local findings="$BATS_TEST_TMPDIR/findings.json"
  echo "[]" > "$findings"
  run bash -c '
    source "$1" >/dev/null 2>&1
    FINDINGS_FILE="$2"
    PRESENT=" $3 "
    INGRESS_ROLES="$4"
    LISTING_ERR="${6:-}"
    ingress_yaml() {
      local r
      printf "name: Agent Ingress\njobs:\n"
      for r in $INGRESS_ROLES; do printf "  %s:\n    uses: x/y/.github/workflows/%s-reusable.yml@%s/stable\n" "$r" "$r" "$r"; done
    }
    list_workflow_files() {
      # LISTING_ERR: "404" ⇒ workflows dir absent (rc 2); other non-empty ⇒ transient (rc 1)
      case "$LISTING_ERR" in
        "") return 0 ;;
        listed) printf "agent-ingress.yml\n"; return 0 ;;
        404) return 2 ;;
        *) return 1 ;;
      esac
    }
    gh_api() {
      local path="$1" wf
      wf="${path##*/}"
      if [ "$wf" = "agent-ingress.yml" ]; then
        [ -n "$INGRESS_ROLES" ] || return 1
        case " $* " in
          *" .content "*) ingress_yaml | base64 | tr -d "\n" ;;
          *) printf "%s" "$wf" ;;
        esac
        return 0
      fi
      case "$PRESENT" in
        *" $wf "*) case " $* " in *" .content "*) : ;; *) printf "%s" "$wf" ;; esac; return 0 ;;
      esac
      return 1
    }
    check_required_workflows "$5"
    jq -r ".[].check" "$FINDINGS_FILE"
  ' _ "$SCRIPT" "$findings" "$1" "$2" "markets" "${3:-}"
}

ALL_BUT_COLLAPSED="ci.yml sonarcloud.yml dependabot-automerge.yml dependency-audit.yml agent-shield.yml feature-ideation.yml initiative-driver.yml"

@test "collapsed repo: roles served by agent-ingress.yml jobs are not flagged missing" {
  run_check "$ALL_BUT_COLLAPSED" "dev-lead pr-review-mention pr-auto-review"
  [ "$status" -eq 0 ]
  run grep -qE 'missing-(dev-lead|pr-review-mention|pr-auto-review)\.yml' <<< "$output"
  [ "$status" -eq 1 ]
}

@test "partial collapse: a role the ingress does NOT serve is still flagged missing" {
  run_check "$ALL_BUT_COLLAPSED" "dev-lead pr-review-mention"
  [ "$status" -eq 0 ]
  grep -qx 'missing-pr-auto-review.yml' <<< "$output"
  run grep -qE 'missing-(dev-lead|pr-review-mention)\.yml' <<< "$output"
  [ "$status" -eq 1 ]
}

@test "non-collapsed repo: missing role stubs are still flagged (no ingress)" {
  run_check "$ALL_BUT_COLLAPSED" ""
  [ "$status" -eq 0 ]
  grep -qx 'missing-dev-lead.yml' <<< "$output"
  grep -qx 'missing-pr-review-mention.yml' <<< "$output"
  grep -qx 'missing-pr-auto-review.yml' <<< "$output"
}

@test "collapsed repo: an unrelated missing required workflow (ci.yml) is still flagged" {
  # The ingress reconciles only the files whose role it has a job for.
  run_check "sonarcloud.yml dependabot-automerge.yml dependency-audit.yml agent-shield.yml feature-ideation.yml initiative-driver.yml" "dev-lead pr-review-mention pr-auto-review"
  [ "$status" -eq 0 ]
  grep -qx 'missing-ci.yml' <<< "$output"
}

@test "no .github/workflows directory (404 listing): required workflows are still flagged missing" {
  run_check "" "" "404"
  [ "$status" -eq 0 ]
  grep -qx 'missing-ci.yml' <<< "$output"
  grep -qx 'missing-dev-lead.yml' <<< "$output"
}

@test "ingress listed but its content read failed: no missing-* findings (inconclusive)" {
  run_check "ci.yml" "" "listed"
  [ "$status" -eq 0 ]
  [[ "$output" != *missing-* ]]
}

@test "unreadable ingress AND unreadable listing: no missing-* findings (inconclusive)" {
  run_check "ci.yml" "" "1"
  [ "$status" -eq 0 ]
  [[ "$output" != *missing-* ]]
}
