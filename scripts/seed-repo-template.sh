#!/usr/bin/env bash
# scripts/seed-repo-template.sh — emit standard file content for the
# org repo-template to distribute to all new repos (#798, Story: SEED + DISTRIBUTE).
#
# Usage:
#   STANDARDS_DIR=<path> bash scripts/seed-repo-template.sh --emit-baseline .gitignore
#
# --emit-baseline .gitignore
#   Print the seeded .gitignore: the marker-wrapped L1 secrets baseline on top
#   (sourced from $STANDARDS_DIR/.gitignore), then standard ecosystem/OS L2 entries
#   below the END marker. L2 must NOT re-ignore any path the baseline negates
#   (e.g. .env.example is re-allowed in L1 via !.env.example).
#
# Env:
#   STANDARDS_DIR   path to the petry-projects/.github checkout that holds the
#                   canonical /.gitignore and scripts/lib/gitignore-baseline.sh.
#                   Defaults to two levels above this script (the repo root).
set -euo pipefail

STANDARDS_DIR="${STANDARDS_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")/.." && pwd)}"

# shellcheck source=lib/gitignore-baseline.sh
source "${STANDARDS_DIR}/scripts/lib/gitignore-baseline.sh"

_usage() {
  echo "Usage: $0 --emit-baseline <file>" >&2
  echo "  Supported files: .gitignore" >&2
  exit 2
}

[ $# -ge 2 ] && [ "$1" = "--emit-baseline" ] || _usage

file="$2"
case "$file" in
  .gitignore)
    # L1 — marker-wrapped org secrets baseline (org-managed, byte-identical).
    gib_extract_baseline_block "${STANDARDS_DIR}/.gitignore"

    # L2 — ecosystem / OS build artifacts (per-repo; edit freely below this line).
    # Do NOT add .env, .env.*, .envrc or any other path the baseline negates —
    # a later ignore silently re-hides a previously-negated file.
    cat <<'EOF'

# ---------------------------------------------------------------------------
# L2 — ecosystem / OS artifacts (edit freely; never re-ignore a baseline path)
# ---------------------------------------------------------------------------

# Node.js
node_modules/
dist/
build/
.cache/
coverage/
*.tgz

# Python
__pycache__/
*.py[cod]
*.egg-info/
.venv/
venv/

# Java / JVM
target/
*.class
*.jar

# OS
.DS_Store
Thumbs.db
EOF
    ;;
  *)
    echo "::error::unknown file '${file}' — only .gitignore is supported" >&2
    exit 2
    ;;
esac
