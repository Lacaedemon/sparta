# tools/lib/run-bounded.sh — shared helper: run a command under a hard timeout.
#
# Sourced by the repo's Godot-launching shell scripts (tools/check.sh,
# tools/demo/*.sh, tools/benchmark/run-benchmark.sh, website/tools/record-demos.sh,
# website/tools/dump-demo-states.sh); not executable on its own.
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

# run_bounded_retry <attempts> <secs> <label> <prepare-fn> <cmd...>
#
# run_bounded with a fixed attempt budget for a run that HANGS rather than fails: each
# attempt is bounded by <secs>; an attempt killed by the timeout is logged (a
# ::warning:: naming <label> and the attempt number) and retried, up to <attempts> in
# all. <prepare-fn> (a function or command name; empty for none) runs before every
# attempt, so a caller can wipe a killed attempt's partial output and each attempt starts
# from the same state as a first one.
#
# Only a timeout is retried. A command that exits non-zero on its own is returned at
# once with its own status: a deterministic failure would just fail again.
#
# Exit status: the last attempt's. When every attempt timed out it is the timeout's (124
# or 137, so run_bounded_timed_out still reads it), after a ::error:: saying so. A
# non-positive or non-numeric <attempts> is refused with status 2.
run_bounded_retry() {
  local attempts="$1" secs="$2" label="$3" prep="$4"; shift 4
  case "$attempts" in
    ''|*[!0-9]*) echo "run_bounded_retry: attempt count must be a positive integer, got '$attempts'" >&2; return 2 ;;
  esac
  attempts=$(( 10#$attempts ))
  if [ "$attempts" -le 0 ]; then
    echo "run_bounded_retry: attempt count must be a positive integer, got '$attempts'" >&2
    return 2
  fi
  local n=1 rc
  while :; do
    if [ -n "$prep" ]; then
      "$prep"
    fi
    rc=0
    run_bounded "$secs" "$@" || rc=$?
    if ! run_bounded_timed_out "$rc"; then
      return "$rc"
    fi
    if [ "$n" -ge "$attempts" ]; then
      echo "::error::$label timed out on all $attempts attempts (${secs}s each)" >&2
      return "$rc"
    fi
    echo "::warning::$label: attempt $n/$attempts timed out after ${secs}s and was killed; retrying" >&2
    n=$(( n + 1 ))
  done
}
