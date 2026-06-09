#!/usr/bin/env bash
# Common test helpers for compliance-remediate bats suites.

TT_REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd)"
export TT_REPO_ROOT

TT_SCRIPT="${TT_REPO_ROOT}/scripts/compliance-remediate.sh"
export TT_SCRIPT

TT_STUBS_DIR="${TT_REPO_ROOT}/test/scripts/compliance-remediate/stubs"
export TT_STUBS_DIR

tt_make_tmpdir() {
  TT_TMP="$(mktemp -d)"
  export TT_TMP
}

tt_cleanup_tmpdir() {
  if [ -n "${TT_TMP:-}" ] && [ -d "${TT_TMP}" ]; then
    rm -rf "${TT_TMP}"
  fi
}

# Install the fake `gh` binary on PATH for the test.
tt_install_gh_stub() {
  local stub_dir="${TT_TMP}/bin"
  mkdir -p "$stub_dir"
  cp "${TT_STUBS_DIR}/gh" "$stub_dir/gh"
  chmod +x "$stub_dir/gh"
  PATH="${stub_dir}:${PATH}"
  export PATH
}

# Write a findings.json file with a single finding and echo its path.
# Args: repo, category, check
tt_write_finding() {
  local repo="$1" category="$2" check="$3"
  local path="${TT_TMP}/findings.json"
  jq -n \
    --arg repo "$repo" \
    --arg category "$category" \
    --arg check "$check" \
    '[{repo:$repo, category:$category, check:$check, severity:"warning", detail:"test", standard_ref:"x"}]' \
    > "$path"
  printf '%s' "$path"
}
