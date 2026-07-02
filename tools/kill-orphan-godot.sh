#!/usr/bin/env bash
# tools/kill-orphan-godot.sh — list orphaned Godot processes left behind by
# test/demo runs; kill them with --force. POSIX twin of kill-orphan-godot.ps1;
# on Windows (Git Bash / MSYS) it delegates to the PowerShell version, because
# the MSYS `ps` cannot see native Windows processes.
#
# A Godot process is considered only when its command line matches the
# NON-INTERACTIVE run signature (headless import, GUT suite, demo/benchmark
# recording) — an interactive editor session never matches, so it is never
# listed or killed. Each matching process is classified as:
#
#   orphaned  the parent is gone (PPID 1: reparented to init/launchd), so
#             nothing is consuming its output. Safe to kill by construction:
#             killing Godot cannot lose git state. (On a system with a
#             subreaper — e.g. a systemd user session — an orphan may reparent
#             to the reaper instead of PID 1 and only be caught as overdue.)
#   overdue   older than the age ceiling (default 2h). No legitimate repo run
#             takes that long.
#   child     a matched process whose parent is itself being killed by this
#             sweep — killing only the parent would leave it running, freshly
#             orphaned by the sweep itself.
#   live      everything else — never touched.
#
# Dry-run by default: prints what it WOULD kill. --force kills (TERM, then
# KILL after a short grace for anything that ignored it).
#
# Usage:
#   tools/kill-orphan-godot.sh [--force] [--max-age-hours N] [--pid N[,N...]]
#
#   --force            actually kill (default: dry run)
#   --max-age-hours N  age ceiling for the overdue verdict (default 2)
#   --pid N[,N...]     restrict the sweep to these PIDs — for a surgical kill,
#                      or for testing the sweep on a process you spawned
#                      yourself without touching anyone else's runs
set -uo pipefail

FORCE=0
MAX_AGE_HOURS=2
ONLY_PIDS=""

while [ $# -gt 0 ]; do
  case "$1" in
    --force) FORCE=1 ;;
    --max-age-hours) MAX_AGE_HOURS="$2"; shift ;;
    --pid) ONLY_PIDS="$2"; shift ;;
    -h|--help)
      # Print the usage header: every comment line from line 2 down to `set -uo`.
      sed -n '2,/^set /{/^set /d;s/^# \{0,1\}//;p}' "$0"
      exit 0
      ;;
    *) echo "Unknown argument: $1 (try --help)" >&2; exit 2 ;;
  esac
  shift
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Windows (Git Bash / MSYS / Cygwin): delegate to the PowerShell twin, which
# sees the real (native) process table.
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*)
    PS_ARGS=(-NoProfile -ExecutionPolicy Bypass -File "$SCRIPT_DIR/kill-orphan-godot.ps1" -MaxAgeHours "$MAX_AGE_HOURS")
    if [ "$FORCE" -eq 1 ]; then PS_ARGS+=(-Force); fi
    if [ -n "$ONLY_PIDS" ]; then PS_ARGS+=(-OnlyPids "$ONLY_PIDS"); fi
    exec powershell.exe "${PS_ARGS[@]}"
    ;;
esac

# Keep in sync with tools/kill-orphan-godot.ps1.
SIGNATURE='--headless|--write-movie|--import|--rendering-driver|gut_cmdln|DemoInputRecorder|DemoRunner|BenchmarkRunner'

MAX_AGE_SECS="$(awk -v h="$MAX_AGE_HOURS" 'BEGIN { printf "%d", h * 3600 }')"

# ps `etime` ([[dd-]hh:]mm:ss) -> seconds. Portable across GNU and BSD ps
# (macOS has no `etimes` keyword).
etime_to_seconds() {
  local e="$1" days=0 hours=0 mins=0 secs=0
  case "$e" in
    *-*) days="${e%%-*}"; e="${e#*-}" ;;
  esac
  local IFS=:
  # Word-splitting on ':' is the point here.
  # shellcheck disable=SC2086
  set -- $e
  case $# in
    3) hours="$1"; mins="$2"; secs="$3" ;;
    2) mins="$1"; secs="$2" ;;
    1) secs="$1" ;;
  esac
  echo $(( 10#$days * 86400 + 10#$hours * 3600 + 10#$mins * 60 + 10#$secs ))
}

# Pass 1: collect the matched processes into parallel arrays (Bash 3.2 has no
# associative arrays) with their initial verdicts.
row_pids=()
row_ppids=()
row_etimes=()
row_verdicts=()
row_args=()
while read -r pid ppid etime args; do
  [ "$pid" = "$$" ] && continue
  printf '%s\n' "$args" | grep -qi 'godot' || continue
  printf '%s\n' "$args" | grep -qE "$SIGNATURE" || continue
  if [ -n "$ONLY_PIDS" ]; then
    case ",$ONLY_PIDS," in
      *",$pid,"*) ;;
      *) continue ;;
    esac
  fi
  age_secs="$(etime_to_seconds "$etime")"
  verdict="live"
  if [ "$ppid" -eq 1 ]; then
    verdict="orphaned"
  elif [ "$age_secs" -ge "$MAX_AGE_SECS" ]; then
    verdict="overdue"
  fi
  row_pids+=("$pid")
  row_ppids+=("$ppid")
  row_etimes+=("$etime")
  row_verdicts+=("$verdict")
  row_args+=("$args")
done < <(ps -eo pid=,ppid=,etime=,args=)

if [ ${#row_pids[@]} -eq 0 ]; then
  echo "No non-interactive Godot run processes found."
  exit 0
fi

# Pass 2: doom-propagation to a fixpoint — a matched process whose parent is
# being killed goes too, or the sweep itself creates a fresh orphan.
changed=1
while [ "$changed" -eq 1 ]; do
  changed=0
  for i in "${!row_pids[@]}"; do
    [ "${row_verdicts[$i]}" = "live" ] || continue
    for j in "${!row_pids[@]}"; do
      if [ "${row_verdicts[$j]}" != "live" ] && [ "${row_pids[$j]}" = "${row_ppids[$i]}" ]; then
        row_verdicts[$i]="child"
        changed=1
        break
      fi
    done
  done
done

# Pass 3: print the table and collect the kill list.
kill_list=()
printf '%8s %8s %12s %-9s %s\n' "PID" "PPID" "ELAPSED" "VERDICT" "COMMAND"
for i in "${!row_pids[@]}"; do
  printf '%8s %8s %12s %-9s %.120s\n' \
    "${row_pids[$i]}" "${row_ppids[$i]}" "${row_etimes[$i]}" "${row_verdicts[$i]}" "${row_args[$i]}"
  if [ "${row_verdicts[$i]}" != "live" ]; then
    kill_list+=("${row_pids[$i]}")
  fi
done

if [ ${#kill_list[@]} -eq 0 ]; then
  echo "Nothing to kill: every run has a live parent and is under the ${MAX_AGE_HOURS}h ceiling."
  exit 0
fi

if [ "$FORCE" -ne 1 ]; then
  echo "DRY RUN: would kill ${#kill_list[@]} process(es) (verdict orphaned/overdue above). Re-run with --force to kill."
  exit 0
fi

kill "${kill_list[@]}" 2>/dev/null
# A short grace for a clean TERM shutdown, then KILL any survivor. (A fixed
# in-script grace, not a wait on an external event.)
sleep 5
killed=0
for pid in "${kill_list[@]}"; do
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null
  fi
  killed=$((killed + 1))
done
echo "Killed $killed process(es)."
