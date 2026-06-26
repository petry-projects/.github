#!/usr/bin/env bats
# Contract tests for .github/workflows/pr-review-mention-reusable.yml
#
# Pins issue #538: the mention listener must never trigger on its own work.
# The pr-review ack comment is authored by donpetry-bot and carries a
# `<!-- pr-review-agent ... -->` marker; either property must keep the job's
# `if:` gate (and its secrets) from ever starting. The ack must also fire no
# mention webhook (#860 runaway: 1,481 byte-identical acks at ~9s cadence).

load 'helpers/setup'

@test "reusable workflow file exists" {
  [ -f "$TT_REUSABLE" ]
}

# ── Acceptance 1: bot-authored / marker comments never re-trigger ─────────────

@test "if-guard excludes comments authored by the bot itself" {
  run prm_if_guard
  [ "$status" -eq 0 ]
  [[ "$output" == *"github.event.comment.user.login != 'donpetry-bot'"* ]]
}

@test "if-guard excludes comments carrying a pr-review-agent marker" {
  run prm_if_guard
  [ "$status" -eq 0 ]
  [[ "$output" == *"!contains(github.event.comment.body, '<!-- pr-review-agent')"* ]]
}

@test "if-guard still requires an @donpetry-bot mention to fire (trigger preserved)" {
  run prm_if_guard
  [ "$status" -eq 0 ]
  [[ "$output" == *"contains(github.event.comment.body, '@donpetry-bot')"* ]]
}

@test "if-guard still gates on trusted author_association (trust gate preserved)" {
  run prm_if_guard
  [ "$status" -eq 0 ]
  [[ "$output" == *'["OWNER","MEMBER","COLLABORATOR"]'* ]]
}

# ── Acceptance 2: the ack comment fires no mention webhook ────────────────────

@test "ack step never @-mentions any user (no mention webhook)" {
  run prm_ack_step
  [ "$status" -eq 0 ]
  # A mention webhook fires only on a literal `@handle`. The ack must reference
  # the actor as plain text, so no `@$` / `@${` interpolation may remain.
  [[ "$output" != *'@$'* ]]
}

@test "ack step never literally @-mentions donpetry-bot" {
  run prm_ack_step
  [ "$status" -eq 0 ]
  [[ "$output" != *"@donpetry-bot"* ]]
}

@test "ack step still tags its comment with the pr-review-agent marker" {
  run prm_ack_step
  [ "$status" -eq 0 ]
  [[ "$output" == *"<!-- pr-review-agent mention-ack -->"* ]]
}

@test "ack step still names the actor in the acknowledgement (plain text)" {
  run prm_ack_step
  [ "$status" -eq 0 ]
  [[ "$output" == *'${ACTOR}'* ]]
}
