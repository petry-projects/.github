#!/usr/bin/env bash
# Common test helpers for auto-rebase bats suites.

AR_REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../../.." && pwd)"
export AR_REPO_ROOT

AR_SCRIPT="${AR_REPO_ROOT}/scripts/auto-rebase.sh"
export AR_SCRIPT

ar_make_tmpdir() {
  AR_TMP="$(mktemp -d)"
  export AR_TMP
}

ar_cleanup_tmpdir() {
  if [ -n "${AR_TMP:-}" ] && [ -d "${AR_TMP}" ]; then
    rm -rf "${AR_TMP}"
  fi
}

# Install a recording gh stub on PATH.
# Args:
#   $1 — value to echo on stdout for every call (default: empty)
#   $2 — exit code for every call (default: 0)
# The stub logs each invocation to $AR_GH_LOG (one line per call, argv tab-separated).
ar_install_gh_stub() {
  local stdout="${1:-}"
  local exit_code="${2:-0}"
  local stub_dir="${AR_TMP}/bin"
  mkdir -p "$stub_dir"
  AR_GH_LOG="${AR_TMP}/gh.log"
  export AR_GH_LOG
  # Write the fixed stdout/exit values into files so the stub can read them at
  # runtime without relying on env vars that may not survive the function call.
  echo -n "$stdout"    > "${AR_TMP}/gh-stdout"
  echo -n "$exit_code" > "${AR_TMP}/gh-exit"
  # Expand AR_TMP now (double-quote around heredoc delimiter) so the stub
  # path is baked in at install time.
  # shellcheck disable=SC2086
  cat >"$stub_dir/gh" <<STUB
#!/usr/bin/env bash
printf '%s ' "\$@" >> "${AR_TMP}/gh.log"
printf '\n'   >> "${AR_TMP}/gh.log"
cat "${AR_TMP}/gh-stdout"
exit \$(cat "${AR_TMP}/gh-exit")
STUB
  chmod +x "$stub_dir/gh"
  PATH="${stub_dir}:${PATH}"
  export PATH
}

# Install a multi-response gh stub driven by AR_GH_RESPONSES (bash array).
# Each element is echoed as the response for successive gh invocations.
ar_install_multi_gh_stub() {
  local stub_dir="${AR_TMP}/bin"
  mkdir -p "$stub_dir"
  AR_GH_LOG="${AR_TMP}/gh.log"
  export AR_GH_LOG
  local counter_file="${AR_TMP}/.gh-counter"
  local responses_file="${AR_TMP}/gh-responses"
  echo "0" > "$counter_file"
  # One response per line (elements must not contain literal newlines).
  printf '%s\n' "${AR_GH_RESPONSES[@]}" > "$responses_file"
  # shellcheck disable=SC2086
  cat >"$stub_dir/gh" <<STUB
#!/usr/bin/env bash
printf '%s ' "\$@" >> "${AR_TMP}/gh.log"
printf '\n'   >> "${AR_TMP}/gh.log"
n=\$(cat "${counter_file}")
sed -n "\$((n+1))p" "${responses_file}"
echo \$((n+1)) > "${counter_file}"
exit 0
STUB
  chmod +x "$stub_dir/gh"
  PATH="${stub_dir}:${PATH}"
  export PATH
}

# Count how many times gh was called with a substring match on the full argv line.
ar_gh_call_count() {
  local pattern="$1"
  local count
  # grep -c prints 0 even on no match; exit code 1 means no match (not error).
  count=$(grep -c "$pattern" "${AR_GH_LOG:-/dev/null}" 2>/dev/null) || count=0
  echo "$count"
}

# Assert gh was called at least once with the given pattern.
ar_assert_gh_called() {
  local pattern="$1"
  local count
  count=$(ar_gh_call_count "$pattern")
  if [[ "$count" -eq 0 ]]; then
    echo "Expected gh to be called with pattern '$pattern' but it was not." >&2
    echo "Actual calls:" >&2
    cat "${AR_GH_LOG:-/dev/null}" >&2
    return 1
  fi
}

# Assert gh was NOT called with the given pattern.
ar_assert_gh_not_called() {
  local pattern="$1"
  local count
  count=$(ar_gh_call_count "$pattern")
  if [[ "$count" -gt 0 ]]; then
    echo "Expected gh NOT to be called with pattern '$pattern' but it was ($count times)." >&2
    return 1
  fi
}
