# tools/lib/run-bounded.sh — shared helper: run a command under a hard timeout.
#
# Sourced by the repo's Godot-launching shell scripts (tools/check.sh,
# tools/demo/*.sh, tools/benchmark/run-benchmark.sh, website/tools/record-demos.sh);
# not executable on its own.
#
# Why: when the calling shell dies (harness command timeout, session end), a
# child Godot process survives on Windows — no process-tree kill — and a hung
# headless run then lives forever as an orphan, starving later runs. Bounding
# every invocation with coreutils `timeout` kills Godot itself, not just the
# calling shell. See tools/README.md, "Orphaned Godot processes".

# run_bounded <secs> <cmd...>
#
# Runs the command under coreutils `timeout` (GNU `timeout`, or Homebrew's
# `gtimeout` on macOS). TERM at <secs>, then KILL 10s later if the process
# ignored it. When neither tool is available (stock macOS without coreutils),
# runs unbounded with a one-time warning rather than failing — the timeout is
# a safety net, not a requirement.
#
# Exit status: the command's own, or 124 (TERM) / 137 (KILL) when the budget
# expired. Callers that swallow Godot's unreliable exit codes (`|| true`)
# should still check for a timeout via run_bounded_timed_out.
run_bounded() {
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then
    timeout -k 10 "$secs" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then
    gtimeout -k 10 "$secs" "$@"
  else
    if [ -z "${_RUN_BOUNDED_WARNED:-}" ]; then
      _RUN_BOUNDED_WARNED=1
      echo "warning: coreutils 'timeout' not found; Godot runs are unbounded (on macOS: brew install coreutils)." >&2
    fi
    "$@"
  fi
}

# run_bounded_timed_out <rc> — true when the exit status came from the timeout
# kill (124 = TERM on expiry, 137 = 128+9, the follow-up KILL).
run_bounded_timed_out() {
  [ "$1" -eq 124 ] || [ "$1" -eq 137 ]
}
