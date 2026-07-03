#!/usr/bin/env bash
# Common test helpers for the apply-rulesets bats suite.
set -euo pipefail

TT_REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd)"
readonly TT_REPO_ROOT
export TT_REPO_ROOT

TT_SCRIPT="${TT_REPO_ROOT}/scripts/apply-rulesets.sh"
readonly TT_SCRIPT
export TT_SCRIPT

TT_STUBS_DIR="${TT_REPO_ROOT}/test/scripts/apply-rulesets/stubs"
readonly TT_STUBS_DIR
export TT_STUBS_DIR

tt_make_tmpdir() {
  TT_TMP="$(mktemp -d)"
  export TT_TMP
}

tt_cleanup_tmpdir() {
  if [[ -n "${TT_TMP:-}" && -d "${TT_TMP}" ]]; then
    rm -rf "${TT_TMP}"
  fi
}

# Install the fake `gh` binary on PATH for the test.
tt_install_gh_stub() {
  local tt_tmp="${TT_TMP:?TT_TMP must be set (call tt_make_tmpdir first)}"
  local stubs_dir="${TT_STUBS_DIR:?TT_STUBS_DIR must be set}"
  local stub_dir="${tt_tmp}/bin"
  mkdir -p "$stub_dir"
  cp "${stubs_dir}/gh" "$stub_dir/gh"
  chmod +x "$stub_dir/gh"
  PATH="${stub_dir}:${PATH}"
  export PATH
}
