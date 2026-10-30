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
#   SPARTA_DUMP_STATE_TIMEOUT   Hard per-attempt timeout in seconds (default 300); also
#                            bounds the import.
#   SPARTA_DUMP_ATTEMPTS     Attempts per clip (default 3, or 1 when CI is set: a
#                            deterministic hang retried at 300 s a time would outlast a CI
#                            step's own time limit before the clean error printed, and
#                            CI runners do not share the parallel load). A clip dump killed by the
#                            timeout is logged as a ::warning::, its partial output wiped,
#                            and rerun from scratch; after this many timed-out attempts the
#                            run fails. Only a timeout is retried -- any other failure
#                            fails at once. Under parallel load on Windows about 1 dump in
#                            40 hung and then passed on a plain rerun (#1882).
#   SPARTA_STATE_TICK_STEP   Tick sampling cadence (default 60 -- once per sim second).
#   SPARTA_STATE_DENSE_FROM  When set, also sample every SPARTA_STATE_DENSE_STEP ticks
#                            (default 2) from this tick through the clip's end, on top of
#                            the regular cadence. The demo diff sets it to a changed clip's
#                            first divergent tick, so a facing snap that starts and ends
#                            between two regular samples is still seen by DemoDefects.
#                            Applies to every selected clip, so pair it with a one-clip
#                            SPARTA_DUMP_CLIPS.
#   SPARTA_DUMP_CLIPS        Comma-separated catalog clip names to dump (default: empty,
#                            the whole catalog). A one-clip dump is the cheap way to
#                            reproduce a single sweep row, or to get one platform's
#                            transcript of a clip for a cross-platform hash compare.
#   SPARTA_DEMO_BITDUMP      Comma-separated ticks to ALSO dump raw soldier-position bits
#                            at, as bit_dump.jsonl beside each clip's snapshots (default:
#                            empty, off). Where the hash stream names the tick that first
#                            differs across platforms, these bits name which unit, field and
#                            axis moved there. Pass it through to both platforms unchanged --
#                            only ticks present on both sides are compared. A clip that
#                            produces no bit_dump.jsonl when this is set fails the run rather
#                            than dumping on, since an absent dump and two agreeing dumps are
#                            the same silence to the comparison.
#
# Every dump also writes OUTPUT_DIR/platform.txt (OS, Godot version, tick cadence): the
# sim is bit-exact only within one build and platform, so a transcript tree that travels
# (a CI artifact diffed against a local dump) has to say where it came from.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
PROJECT_DIR="${2:-$DEFAULT_ROOT}"
OUT_DIR="${1:-$PROJECT_DIR/website/state-transcripts}"
GODOT_BIN="${GODOT_BIN:-godot}"
DUMP_TIMEOUT="${SPARTA_DUMP_STATE_TIMEOUT:-300}"
TICK_STEP="${SPARTA_STATE_TICK_STEP:-60}"
DENSE_FROM="${SPARTA_STATE_DENSE_FROM:-}"
DENSE_STEP="${SPARTA_STATE_DENSE_STEP:-2}"
case "$DENSE_FROM" in
  *[!0-9]*) echo "SPARTA_STATE_DENSE_FROM must be a tick number, got '$DENSE_FROM'" >&2; exit 2 ;;
esac
# Digits only, then read as base 10: a zero-padded value would otherwise be octal, so
# "08" aborts the arithmetic and "00" is a zero step that never advances the loop.
case "$DENSE_STEP" in
  ''|*[!0-9]*) echo "SPARTA_STATE_DENSE_STEP must be a positive tick count, got '$DENSE_STEP'" >&2; exit 2 ;;
esac
if [ $(( 10#$DENSE_STEP )) -le 0 ]; then
  echo "SPARTA_STATE_DENSE_STEP must be a positive tick count, got '$DENSE_STEP'" >&2
  exit 2
fi
DENSE_STEP=$(( 10#$DENSE_STEP ))
ONLY_CLIPS="${SPARTA_DUMP_CLIPS:-}"
if [ -n "${CI:-}" ]; then
  DUMP_ATTEMPTS="${SPARTA_DUMP_ATTEMPTS:-1}"
else
  DUMP_ATTEMPTS="${SPARTA_DUMP_ATTEMPTS:-3}"
fi
case "$DUMP_ATTEMPTS" in
  ''|*[!0-9]*) echo "SPARTA_DUMP_ATTEMPTS must be a positive attempt count, got '$DUMP_ATTEMPTS'" >&2; exit 2 ;;
esac
if [ $(( 10#$DUMP_ATTEMPTS )) -le 0 ]; then
  echo "SPARTA_DUMP_ATTEMPTS must be a positive attempt count, got '$DUMP_ATTEMPTS'" >&2
  exit 2
fi
DUMP_ATTEMPTS=$(( 10#$DUMP_ATTEMPTS ))

# shellcheck source=../../tools/lib/run-bounded.sh
. "$DEFAULT_ROOT/tools/lib/run-bounded.sh"
# shellcheck source=../../tools/lib/godot-import-lock.sh
. "$DEFAULT_ROOT/tools/lib/godot-import-lock.sh"
# shellcheck source=../../tools/lib/demo-catalog-selection.sh
. "$DEFAULT_ROOT/tools/lib/demo-catalog-selection.sh"
# Each tree's OWN catalog decides what it dumps (falling back to this script's sibling
# for a tree that predates the extraction). This is what makes removed clips real in
# the diff: a clip the PR drops from the catalog still dumps on the merge-base side,
# so it reports as removed instead of silently vanishing from both sides.
if [ -f "$PROJECT_DIR/website/tools/demo-catalog.sh" ]; then
  # shellcheck source=demo-catalog.sh
  . "$PROJECT_DIR/website/tools/demo-catalog.sh"
else
  # shellcheck source=demo-catalog.sh
  . "$SCRIPT_DIR/demo-catalog.sh"
fi
# A misspelt narrowing must fail here, not dump nothing and exit 0.
demo_catalog_check_selection "$ONLY_CLIPS"

mkdir -p "$OUT_DIR"

# Godot prints its version as the last line of --version (a console wrapper may print
# more before it).
GODOT_VERSION="$("$GODOT_BIN" --version 2>/dev/null | tail -n1 || true)"

# Import so autoloads / class_name globals resolve in the target project -- under the
# project's import lock, and only when the cache is stale for this tree and this Godot,
# so parallel dumps of one project never import at the same time: at most two imports,
# one after the other, on a cold project and none on a warm one. The lock serialises
# imports only, not an import against another run's dump (#1882;
# tools/lib/godot-import-lock.sh has the measurements). An import that times
# out or crashes fails the run here (it used to be ignored). With the version unknown the
# stamp content is empty, which always imports rather than trust a cache it cannot match.
IMPORT_STAMP=""
if [ -n "$GODOT_VERSION" ]; then
  IMPORT_STAMP="godot=$GODOT_BIN version=$GODOT_VERSION"
fi
godot_import_once "$DUMP_TIMEOUT" "$GODOT_BIN" "$PROJECT_DIR" "$IMPORT_STAMP"
{
  printf 'os=%s\n' "$(uname -s)"
  printf 'godot=%s\n' "${GODOT_VERSION:-unknown}"
  printf 'tick_step=%s\n' "$TICK_STEP"
  if [ -n "$DENSE_FROM" ]; then
    printf 'dense_from=%s\ndense_step=%s\n' "$DENSE_FROM" "$DENSE_STEP"
  fi
  printf 'clips=%s\n' "${ONLY_CLIPS:-all}"
} > "$OUT_DIR/platform.txt"

# The tick list for a clip: 8 (an early sanity sample, past spawn), then every TICK_STEP
# ticks through the covered range, always including the final covered tick. With
# DENSE_FROM set, every DENSE_STEP ticks from there through the covered range are added,
# and the merged list is sorted and de-duplicated.
tick_list() {
  local fixed_fps="$1" max_frames="$2"
  local covered=$(( max_frames * 60 / fixed_fps ))
  local ticks="8" t=$TICK_STEP
  while [ "$t" -lt "$covered" ]; do
    ticks="$ticks,$t"
    t=$(( t + TICK_STEP ))
  done
  ticks="$ticks,$covered"
  if [ -n "$DENSE_FROM" ]; then
    t=$(( 10#$DENSE_FROM ))
    while [ "$t" -lt "$covered" ]; do
      ticks="$ticks,$t"
      t=$(( t + DENSE_STEP ))
    done
    ticks="$(printf '%s\n' "$ticks" | tr ',' '\n' | sort -n -u | paste -sd, -)"
  fi
  echo "$ticks"
}

# Before every dump attempt: start the clip's output dir empty. When a timed-out attempt
# left files there, say how many state snapshots it got through first -- a hang after the
# last armed tick (a stuck exit) and one mid-battle are different bugs.
# CLIP_ATTEMPTED is reset per clip, so the first attempt reports nothing.
fresh_clip_out() {
  if [ "$CLIP_ATTEMPTED" -eq 1 ] && [ -d "$CLIP_OUT" ]; then
    local got armed
    got="$(find "$CLIP_OUT" -maxdepth 1 -name 'state_*.json' | wc -l | tr -d ' ')"
    armed="$(printf '%s\n' "$TICKS" | tr ',' '\n' | wc -l | tr -d ' ')"
    echo "dump-demo-states: the killed attempt for '$NAME' had written $got of $armed state snapshot(s)" >&2
  fi
  CLIP_ATTEMPTED=1
  # A killed Godot on Windows can still hold a file open for a moment, so the wipe is
  # tried 3 times, 1 s apart. If it still fails, that fails the whole run
  # (run_bounded_retry stops on a failed prepare step) rather than letting the next
  # attempt append to the last one's hash_stream.jsonl.
  local try
  for try in 1 2 3; do
    if rm -rf "$CLIP_OUT" 2>/dev/null && [ ! -e "$CLIP_OUT" ]; then
      break
    fi
    if [ "$try" -eq 3 ]; then
      echo "::error::could not clear $CLIP_OUT before dumping '$NAME' (3 tries); failing the run" >&2
      return 1
    fi
    sleep 1
  done
  mkdir -p "$CLIP_OUT"
}

for spec in "${DEMOS[@]}"; do
  IFS='|' read -r NAME SOURCE FIXED_FPS MAX_FRAMES WIDTH TYPE <<<"$spec"
  TYPE="${TYPE:-replay}"
  if ! demo_catalog_selected "$NAME" "$ONLY_CLIPS"; then
    continue
  fi
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
  CLIP_ATTEMPTED=0
  echo "== Dumping '$NAME' ($TYPE: res://$SOURCE) at ticks $TICKS =="
  rc=0
  # FULL dumps (per-soldier arrays + ordered slots + motion_ref, where the tree's
  # DemoState supports them): the defect-delta pass reads them, and the diff script
  # projects them back out before comparing, so the transcript-diff semantics stay
  # exactly the compact fields they always were. A tree predating the full-dump
  # schema just emits compact records; the delta pass degrades to "n/a" there.
  #
  # A hung attempt is killed, its partial output wiped by fresh_clip_out, and rerun, so a
  # retried clip's transcripts (hash_stream.jsonl included, which the sink appends to)
  # are byte-identical to a clean first attempt's.
  run_bounded_retry "$DUMP_ATTEMPTS" "$DUMP_TIMEOUT" "dumping '$NAME'" fresh_clip_out \
    env "${ENV_KEY}=res://${SOURCE}" \
        SPARTA_DEMO_STATE="$TICKS" SPARTA_DEMO_STATE_DIR="$CLIP_OUT" \
        SPARTA_DEMO_STATE_FULL=1 \
    "$GODOT_BIN" --headless --fixed-fps 60 --path "$PROJECT_DIR" "$SCENE" || rc=$?
  if run_bounded_timed_out "$rc"; then
    echo "ERROR: dumping '$NAME' timed out on all $DUMP_ATTEMPTS attempt(s) of ${DUMP_TIMEOUT}s each and was killed (no orphan left behind)." >&2
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
  # Same guard, for the raw-bit dump -- but split, because absent and empty mean different
  # things here and only one of them is a defect.
  #
  # SPARTA_DEMO_BITDUMP is ONE tick list applied to every clip, unlike the state ticks, which
  # tick_list() derives per clip from that clip's own fixed_fps/max_frames and so are reachable
  # by construction. Covered ranges across the catalog span roughly 240 to 5000 ticks, so a
  # tick chosen for a long clip simply never arrives in a short one.
  #
  #   absent  -- the dump was never opened, so the tool did not do what it was told. Fail.
  #   empty   -- opened, but no armed tick occurred before this clip's battle ended. Say so
  #              and carry on: aborting here would take the whole sweep down over a clip
  #              nobody was asking about.
  if [ -n "${SPARTA_DEMO_BITDUMP:-}" ]; then
    if [ ! -f "$CLIP_OUT/bit_dump.jsonl" ]; then
      echo "::error::SPARTA_DEMO_BITDUMP was set but '$NAME' opened no bit_dump.jsonl at all"
      exit 1
    elif [ ! -s "$CLIP_OUT/bit_dump.jsonl" ]; then
      echo "::warning::'$NAME' wrote an empty bit_dump.jsonl -- tick(s) ${SPARTA_DEMO_BITDUMP} lie past this clip's covered range"
    fi
  fi
done

echo "Done. State transcripts in: $OUT_DIR"
