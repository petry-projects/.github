# Common test helpers for the pr-review-mention bats suite.

# Repo root, regardless of where bats is invoked from.
TT_REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd)"
export TT_REPO_ROOT

# The reusable workflow that owns all mention-dispatch logic (the file under test).
TT_REUSABLE="${TT_REPO_ROOT}/.github/workflows/pr-review-mention-reusable.yml"
export TT_REUSABLE

# Print the job-level `if:` guard block: everything from the `if: |` line up to
# (but not including) the `steps:` key of the handle-mention job.
prm_if_guard() {
  awk '
    /^[[:space:]]*if:[[:space:]]*\|/ { grab=1; next }
    grab && /^[[:space:]]*steps:[[:space:]]*$/ { exit }
    grab { print }
  ' "$TT_REUSABLE"
}

# Print the body of the "Post acknowledgement comment" step: everything from that
# step's `- name:` line up to (but not including) the next `- name:` line.
prm_ack_step() {
  awk '
    /^[[:space:]]*-[[:space:]]*name:[[:space:]]*Post acknowledgement comment/ { grab=1; print; next }
    grab && /^[[:space:]]*-[[:space:]]*name:/ { exit }
    grab { print }
  ' "$TT_REUSABLE"
}
