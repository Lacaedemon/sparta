#!/usr/bin/env bash
# tools/perf/ops-before-after.sh -- record computations per tick on the base build and on this
# branch, then graph the two together. The required evidence artifact for a backend-only
# performance PR (see tools/perf/README.md and CLAUDE.md's "Backend-only performance PRs").
#
# Runs the benchmark TWICE, sequentially: once in a throwaway git worktree checked out at the
# base ref, once in the current tree. Sequential is not incidental -- two Godot processes on
# one machine share user://settings.cfg and the import cache, so a parallel run would corrupt
# both sides (see .claude/memories/sparta.md).
#
# Usage:
#   tools/perf/ops-before-after.sh [base-ref] [out.png]
#
#   [base-ref]  Commit-ish to treat as "before" (default: the merge-base with origin/main,
#               falling back to origin/main, then main).
#   [out.png]   Where to write the graph (default: demos/shots/ops-per-tick-<slug>.png,
#               where <slug> is the first run of digits in the branch name, e.g.
#               feat/42-perf -> 42, bolt-99 -> 99). If the branch name contains
#               no digits, or HEAD is detached / the branch is main, exit 1 and pass an
#               explicit [out.png] argument (e.g. demos/shots/ops-per-tick-<issue>.png).
#
# Environment:
#   GODOT_BIN                      Godot 4.7 binary (default: godot).
#   SPARTA_PERF_SCENARIO           Scenario to run on BOTH sides
#                                   (default: benchmarks/scenarios/large-battle.json).
#   SPARTA_PERF_SCALE              Soldier-count multiplier for both sides (default 1).
#   SPARTA_PERF_BUCKET             Work bucket to graph (default: total).
#   SPARTA_PERF_KEEP               Set to 1 to keep the recorded series JSONs and the base
#                                   worktree instead of cleaning them up.
#   SPARTA_PERF_OVERWRITE          Set to 1 to allow overwriting a graph file already
#                                   tracked by git (untracked files may be overwritten freely).
#   SPARTA_BENCHMARK_WARMUP_TICKS  Forwarded to both runs (default: the runner's own 120).
#   SPARTA_BENCHMARK_TICKS         Forwarded to both runs (default: the runner's own 600).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  sed -n '2,/^set /{/^set /d;s/^# \{0,1\}//;p}' "$0"
  exit 0
fi

SCENARIO="${SPARTA_PERF_SCENARIO:-benchmarks/scenarios/large-battle.json}"
SCALE="${SPARTA_PERF_SCALE:-1}"
BUCKET="${SPARTA_PERF_BUCKET:-total}"

resolve_base() {
  if [ -n "${1:-}" ]; then
    git -C "$PROJECT_ROOT" rev-parse --verify "$1^{commit}" 2>/dev/null && return 0
  fi
  git -C "$PROJECT_ROOT" merge-base HEAD origin/main 2>/dev/null && return 0
  git -C "$PROJECT_ROOT" rev-parse --verify origin/main 2>/dev/null && return 0
  git -C "$PROJECT_ROOT" rev-parse --verify main 2>/dev/null && return 0
  return 1
}

default_out_png() {
  local branch slug re
  branch="$(git -C "$PROJECT_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
  if [ -z "$branch" ] || [ "$branch" = "HEAD" ] || [ "$branch" = "main" ]; then
    echo "ERROR: cannot derive output filename on detached HEAD or main branch." >&2
    echo "       Pass an explicit [out.png] argument, e.g. demos/shots/ops-per-tick-<issue>.png." >&2
    return 1
  fi
  re='([0-9]+)'
  if [[ "$branch" =~ $re ]]; then
    slug="${BASH_REMATCH[1]}"
    echo "$PROJECT_ROOT/demos/shots/ops-per-tick-${slug}.png"
    return 0
  fi
  echo "ERROR: branch '$branch' contains no digits to derive a graph filename from." >&2
  echo "       Pass an explicit [out.png] argument, e.g. demos/shots/ops-per-tick-<issue>.png." >&2
  return 1
}

refuse_tracked_overwrite() {
  local target="$1"
  if [ "${SPARTA_PERF_OVERWRITE:-0}" = "1" ]; then
    return 0
  fi
  if [[ "$target" != /* && ! "$target" =~ ^[A-Za-z]: ]]; then
    target="$PWD/$target"
  fi
  if git -C "$PROJECT_ROOT" ls-files --error-unmatch "$target" >/dev/null 2>&1; then
    echo "ERROR: output file '$target' is already tracked by git." >&2
    echo "       Set SPARTA_PERF_OVERWRITE=1 to overwrite a tracked graph." >&2
    exit 1
  fi
}

if [ -n "${2:-}" ]; then
  OUT_PNG="$2"
elif ! OUT_PNG="$(default_out_png)"; then
  exit 1
fi
refuse_tracked_overwrite "$OUT_PNG"

BASE_SHA="$(resolve_base "${1:-}" || true)"
if [ -z "$BASE_SHA" ]; then
  echo "ERROR: could not resolve a base ref to compare against (tried the argument, the" >&2
  echo "       merge-base with origin/main, origin/main and main)." >&2
  exit 1
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sparta_perf_XXXXXX")"
BASE_TREE="$WORK_DIR/base"
BEFORE_JSON="$WORK_DIR/before.json"
AFTER_JSON="$WORK_DIR/after.json"

cleanup() {
  if [ "${SPARTA_PERF_KEEP:-0}" = "1" ]; then
    echo "Kept recordings in $WORK_DIR (SPARTA_PERF_KEEP=1)."
    return
  fi
  if [ -d "$BASE_TREE" ]; then
    git -C "$PROJECT_ROOT" worktree remove --force "$BASE_TREE" >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# --- before: the base build, in its own worktree ------------------------------------------
echo "== before: $(git -C "$PROJECT_ROOT" log --oneline -1 "$BASE_SHA")"
git -C "$PROJECT_ROOT" worktree add --detach --quiet "$BASE_TREE" "$BASE_SHA"
if [ ! -f "$BASE_TREE/scripts/SimOps.gd" ]; then
  echo "ERROR: the base build at $BASE_SHA has no scripts/SimOps.gd, so it cannot count its" >&2
  echo "       own work -- there is nothing to compare against. Rebase onto a base that" >&2
  echo "       includes the counters, or record only this branch's side:" >&2
  echo "         SPARTA_BENCHMARK_SERIES=after.json tools/benchmark/run-benchmark.sh" >&2
  echo "         tools/perf/plot-ops-per-tick.py --after after.json --out graph.png" >&2
  exit 1
fi

SPARTA_BENCHMARK_SERIES="$BEFORE_JSON" SPARTA_BENCHMARK_LABEL="before" \
  SPARTA_BENCHMARK_OUT="$WORK_DIR/before-report.json" PROJECT_ROOT="$BASE_TREE" \
  "$BASE_TREE/tools/benchmark/run-benchmark.sh" "$SCENARIO" "$SCALE"

# --- after: this branch --------------------------------------------------------------------
echo
echo "== after:  $(git -C "$PROJECT_ROOT" log --oneline -1 HEAD)"
SPARTA_BENCHMARK_SERIES="$AFTER_JSON" SPARTA_BENCHMARK_LABEL="after" \
  SPARTA_BENCHMARK_OUT="$WORK_DIR/after-report.json" PROJECT_ROOT="$PROJECT_ROOT" \
  "$PROJECT_ROOT/tools/benchmark/run-benchmark.sh" "$SCENARIO" "$SCALE"

for f in "$BEFORE_JSON" "$AFTER_JSON"; do
  if [ ! -s "$f" ]; then
    echo "ERROR: no per-tick series was written to $f -- the run crashed, hung, or the build" >&2
    echo "       there does not support SPARTA_BENCHMARK_SERIES." >&2
    exit 1
  fi
done

mkdir -p "$(dirname "$OUT_PNG")"
echo
python3 "$SCRIPT_DIR/plot-ops-per-tick.py" \
  --before "$BEFORE_JSON" --after "$AFTER_JSON" --bucket "$BUCKET" --out "$OUT_PNG"
echo
echo "Commit $OUT_PNG and embed it in the PR description, with the table above."
