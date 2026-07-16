#!/usr/bin/env bash
# Dump per-tick sim state transcripts for EVERY website demo clip (the demo-catalog.sh
# list), one subdirectory per clip. This is the content signal behind
# .github/workflows/website-demo-diff.yml: the sim is deterministic for these scripted
# clips, so two transcript sets diff clean unless a PR really changed a clip's behavior --
# unlike the rendered clips' bytes, which vary run to run at the encoder level.
#
# Runs each clip fully headless (state dumps read sim state, never the drawn frame) with
# --fixed-fps 60, which detaches the main loop from the wall clock so the sim fast-forwards
# at CPU speed. Ticks are sampled on a fixed cadence over each clip's covered range
# (max_frames * 60 / fixed_fps physics ticks), so two runs of this script -- e.g. a PR head
# and its merge-base -- sample the identical tick set per clip.
#
# Usage:
#   website/tools/dump-demo-states.sh [OUTPUT_DIR] [PROJECT_DIR]
#
#   OUTPUT_DIR   Where the per-clip transcript dirs go (default: website/state-transcripts
#                under the project dir).
#   PROJECT_DIR  The Godot project to run (default: this script's own repo root). Passing a
#                second checkout lets one script version dump a merge-base tree, so the diff
#                never depends on the base revision already containing this script.
#
# Environment:
#   GODOT_BIN                Godot 4.7 binary (default: godot).
#   SPARTA_DUMP_STATE_TIMEOUT   Hard per-clip timeout in seconds (default 300).
#   SPARTA_STATE_TICK_STEP   Tick sampling cadence (default 60 -- once per sim second).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_DIR="${2:-$DEFAULT_ROOT}"
OUT_DIR="${1:-$PROJECT_DIR/website/state-transcripts}"
GODOT_BIN="${GODOT_BIN:-godot}"
DUMP_TIMEOUT="${SPARTA_DUMP_STATE_TIMEOUT:-300}"
TICK_STEP="${SPARTA_STATE_TICK_STEP:-60}"

# shellcheck source=../../tools/lib/run-bounded.sh
. "$DEFAULT_ROOT/tools/lib/run-bounded.sh"
# shellcheck source=demo-catalog.sh
. "$SCRIPT_DIR/demo-catalog.sh"

mkdir -p "$OUT_DIR"

# Import once so autoloads / class_name globals resolve in the target project.
run_bounded "$DUMP_TIMEOUT" "$GODOT_BIN" --headless --import --path "$PROJECT_DIR" >/dev/null 2>&1 || true

# The tick list for a clip: 8 (an early sanity sample, past spawn), then every TICK_STEP
# ticks through the covered range, always including the final covered tick.
tick_list() {
  local fixed_fps="$1" max_frames="$2"
  local covered=$(( max_frames * 60 / fixed_fps ))
  local ticks="8" t=$TICK_STEP
  while [ "$t" -lt "$covered" ]; do
    ticks="$ticks,$t"
    t=$(( t + TICK_STEP ))
  done
  echo "$ticks,$covered"
}

for spec in "${DEMOS[@]}"; do
  IFS='|' read -r NAME SOURCE FIXED_FPS MAX_FRAMES WIDTH TYPE <<<"$spec"
  TYPE="${TYPE:-replay}"
  if [ ! -f "$PROJECT_DIR/$SOURCE" ]; then
    # A clip added (or renamed) by the PR won't exist in a merge-base checkout; the diff
    # script reports the missing transcript dir as a new/removed clip, so just note it.
    echo "== '$NAME': source $SOURCE not in this tree; skipping (new clip here?) =="
    continue
  fi
  if [ "$TYPE" = "input" ]; then
    SCENE=res://tools/demo/DemoInputRecorder.tscn
    ENV_KEY=SPARTA_DEMO_INPUT
  else
    # Replay-type rows need DemoStateSink (DemoRunner is freed on the scene swap, so the
    # sink carries the dump). A tree that predates it — e.g. the merge-base right after
    # the sink lands — can't transcript replays; skip rather than fail, and the diff
    # reports those clips as new on the side that can. Self-resolving after one merge.
    if [ ! -f "$PROJECT_DIR/tools/demo/DemoStateSink.gd" ]; then
      echo "== '$NAME': replay-type row but this tree has no DemoStateSink; skipping =="
      continue
    fi
    SCENE=res://tools/demo/DemoRunner.tscn
    ENV_KEY=SPARTA_DEMO_REPLAY
  fi
  TICKS="$(tick_list "$FIXED_FPS" "$MAX_FRAMES")"
  CLIP_OUT="$OUT_DIR/$NAME"
  rm -rf "$CLIP_OUT"
  mkdir -p "$CLIP_OUT"
  echo "== Dumping '$NAME' ($TYPE: res://$SOURCE) at ticks $TICKS =="
  rc=0
  run_bounded "$DUMP_TIMEOUT" \
    env "${ENV_KEY}=res://${SOURCE}" \
        SPARTA_DEMO_STATE="$TICKS" SPARTA_DEMO_STATE_DIR="$CLIP_OUT" \
    "$GODOT_BIN" --headless --fixed-fps 60 --path "$PROJECT_DIR" "$SCENE" || rc=$?
  if run_bounded_timed_out "$rc"; then
    echo "ERROR: dumping '$NAME' timed out after ${DUMP_TIMEOUT}s and was killed (no orphan left behind)." >&2
    exit 1
  fi
  if [ "$rc" -ne 0 ]; then
    exit "$rc"
  fi
  # push_error() doesn't set a non-zero exit code, so verify the artifacts exist instead
  # of trusting the exit status (the same guard tools/check.sh coverage uses).
  if ! ls "$CLIP_OUT"/state_*.json >/dev/null 2>&1; then
    echo "::error::state dump produced no transcripts for '$NAME'"
    exit 1
  fi
done

echo "Done. State transcripts in: $OUT_DIR"
