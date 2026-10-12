#!/usr/bin/env bash
# Perturbed melee-outcome delta: judge whether a change to melee dynamics makes routers,
# casualties or contact outcomes worse, across a distribution of runs rather than one seed.
#
# Melee outcomes in the catalog clips are chaotic: a negligible change flips which router
# escapes and when a unit dies, so one run per clip cannot tell a regression from chance.
# This runs every selected clip K times on each tree, each run on a different derived seed
# (SPARTA_DEMO_SEED_RUN=1..K, see tools/demo/DemoSeed.gd), so the scenario and its orders
# are unchanged and only the combat rolls differ. It then compares each metric's base and
# head distributions (tools/demo/melee_outcome_compare.gd) and flags only shifts that are
# both significant after multiple-comparison control and larger than a practical threshold.
#
# Usage: melee-outcome-delta.sh <base-tree> <head-tree> <out-dir>
#
#   base-tree / head-tree  Two checkouts of the project. Both must carry
#                          tools/demo/DemoSeed.gd, or their runs could not be perturbed.
#   out-dir                Where dumps/<side>/<clip>/seed<k>/ and the reports go:
#                          melee-delta.tsv (every metric row) and melee-delta.md (the
#                          summary to paste into a PR). Each run directory keeps its
#                          metrics.json; a finished run is reused, so a re-run with new
#                          thresholds only re-compares. Reuse is keyed on side, clip and
#                          seed only, so use a fresh out-dir whenever either tree changes.
#
#        melee-outcome-delta.sh --derive-clips <tree> <out-dir>
#
#   Runs every catalog clip once and prints the ones with any enemy contact, the list
#   MELEE_CLIPS in tools/lib/melee-clips.sh holds. Needs jq.
#
# Environment (every tunable has a default):
#   GODOT_BIN               Godot 4.7 binary (default: godot).
#   MELEE_DELTA_K           Perturbed runs per clip per side (default 8).
#   MELEE_DELTA_CLIPS       Comma-separated catalog clips (default: every clip in
#                           MELEE_CLIPS, tools/lib/melee-clips.sh).
#   MELEE_DELTA_SUBSET      "quick" selects MELEE_CLIPS_QUICK instead, the clips whose
#                           router outcomes flipped under a 0.0001 rad nudge. Ignored when
#                           MELEE_DELTA_CLIPS is set.
#   MELEE_DELTA_STEP        Snapshot cadence in ticks (default 5): the resolution of every
#                           tick metric.
#   MELEE_DELTA_JOBS        Godot runs in parallel (default 2).
#   MELEE_DELTA_TIMEOUT     Hard per-run timeout in seconds (default 300).
#   MELEE_DELTA_COMPARE_TIMEOUT
#                           Hard timeout for the comparison step in seconds (default 1800).
#   MELEE_DELTA_ALPHA       Benjamini-Hochberg false discovery rate (default 0.05).
#   MELEE_DELTA_MIN_TICKS   Smallest flagged shift of a tick metric (default 30).
#   MELEE_DELTA_MIN_METRES  Smallest flagged shift of a travel metric (default 1).
#   MELEE_DELTA_MIN_MEN     Smallest flagged shift of a headcount (default 2).
#   MELEE_DELTA_MIN_RUNS    Fewest runs per side for a metric to be tested (default 4).
#   MELEE_DELTA_TRAVEL      Tick offsets after a break for the travel metrics
#                           (default 60,150,300).
#   MELEE_DELTA_HEAD_RUN_OFFSET
#                           Play the head side's runs at SPARTA_DEMO_SEED_RUN 1+offset to
#                           K+offset (default 0: both sides play 1..K, so a clip the change
#                           does not touch reads identical). Comparing a tree with itself at
#                           an offset of K is the null calibration: the same code on
#                           disjoint seeds, which should flag nothing.
#   MELEE_DELTA_KEEP_DUMPS  0 (default) deletes each run's snapshots (about 5 MB a run) once
#                           its metrics.json is written; 1 keeps them, which a re-compare
#                           with other MELEE_DELTA_TRAVEL offsets needs.
#   MELEE_DELTA_DERIVE_STEP Snapshot cadence of --derive-clips (default 30).
#
# Exit code: 0 = nothing flagged, 1 = at least one flagged shift, 2 = usage, input or run
# failure.
set -euo pipefail

usage() {
  echo "usage: melee-outcome-delta.sh <base-tree> <head-tree> <out-dir>" >&2
  echo "       melee-outcome-delta.sh --derive-clips <tree> <out-dir>" >&2
  exit 2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
# shellcheck source=../lib/run-bounded.sh
. "$TOOL_ROOT/tools/lib/run-bounded.sh"

# --run-one <tree> <source> <type> <ticks> <run> <dir>: one perturbed dump. Internal: the
# parallel pool below re-invokes this script with it.
if [ "${1:-}" = "--run-one" ]; then
  [ "$#" -eq 7 ] || usage
  tree="$2" source="$3" type="$4" ticks="$5" run="$6" dir="$7"
  if [ "$type" = "input" ]; then
    scene=res://tools/demo/DemoInputRecorder.tscn key=SPARTA_DEMO_INPUT
  else
    scene=res://tools/demo/DemoRunner.tscn key=SPARTA_DEMO_REPLAY
  fi
  rm -rf "$dir"
  mkdir -p "$dir"
  rc=0
  run_bounded "${MELEE_DELTA_TIMEOUT:-300}" env "$key=res://$source" SPARTA_DEMO_SEED_RUN="$run" \
      SPARTA_DEMO_STATE="$ticks" SPARTA_DEMO_STATE_DIR="$dir" \
      "$GODOT_BIN" --headless --fixed-fps 60 --path "$tree" "$scene" > "$dir.log" 2>&1 || rc=$?
  # push_error() exits 0, so the snapshots are the evidence the run worked.
  if [ "$rc" -ne 0 ] || ! ls "$dir"/state_*.json >/dev/null 2>&1; then
    echo "error: run $run of $source in $tree failed (rc $rc); log: $dir.log" >&2
    exit 2
  fi
  # Extract this run's metrics now, in the parallel pool, so the comparison reads one small
  # file per run instead of parsing every snapshot serially.
  rc=0
  run_bounded "${MELEE_DELTA_TIMEOUT:-300}" "$GODOT_BIN" --headless --path "$TOOL_ROOT" \
      -s tools/demo/melee_outcome_compare.gd -- --extract "$dir" \
      --travel "${MELEE_DELTA_TRAVEL:-60,150,300}" >> "$dir.log" 2>&1 || rc=$?
  if [ "$rc" -ne 0 ] || [ ! -s "$dir/metrics.json" ]; then
    echo "error: extracting run $run of $source failed (rc $rc); log: $dir.log" >&2
    exit 2
  fi
  if [ "${MELEE_DELTA_KEEP_DUMPS:-0}" != "1" ]; then
    rm -f "$dir"/state_*.json "$dir"/hash_stream.jsonl
  fi
  touch "$dir.done"
  exit 0
fi

# --derive-clips <tree> <out-dir>: run every catalog clip of <tree> once on its own seed,
# snapshots every MELEE_DELTA_DERIVE_STEP ticks (default 30), and print the clips in which
# some unit is ever in enemy contact: the MELEE_CLIPS list in tools/lib/melee-clips.sh.
if [ "${1:-}" = "--derive-clips" ]; then
  [ "$#" -eq 3 ] || usage
  command -v jq >/dev/null 2>&1 || { echo "error: jq not found on PATH" >&2; exit 2; }
  tree="$(cd "$2" && pwd)" || usage
  mkdir -p "$3"
  out="$(cd "$3" && pwd)"
  step="${MELEE_DELTA_DERIVE_STEP:-30}"
  # shellcheck source=../../website/tools/demo-catalog.sh
  . "$tree/website/tools/demo-catalog.sh"
  : > "$out/jobs.txt"
  for spec in "${DEMOS[@]}"; do
    IFS='|' read -r name source fixed_fps max_frames _width type <<<"$spec"
    printf '%s\0%s\0%s\0%s\0%s\0%s\0' "$tree" "$source" "${type:-replay}" \
        "$(seq -s, "$step" "$step" $(( max_frames * 60 / fixed_fps )))" 0 "$out/$name" >> "$out/jobs.txt"
  done
  run_bounded "${MELEE_DELTA_TIMEOUT:-300}" "$GODOT_BIN" --headless --import --path "$tree" >/dev/null 2>&1 || true
  xargs -0 -n 6 -P "${MELEE_DELTA_JOBS:-2}" bash "$SCRIPT_DIR/melee-outcome-delta.sh" --run-one \
      < "$out/jobs.txt" || { echo "error: at least one clip run failed" >&2; exit 2; }
  for spec in "${DEMOS[@]}"; do
    name="${spec%%|*}"
    # The extractor's own first_contact: the tick any unit was first in enemy contact.
    if jq -e '.metrics.first_contact != null' "$out/$name/metrics.json" >/dev/null; then
      echo "$name"
    fi
  done
  exit 0
fi

[ "$#" -eq 3 ] || usage
BASE_TREE="$(cd "$1" && pwd)" || usage
HEAD_TREE="$(cd "$2" && pwd)" || usage
OUT_DIR="$3"

# Every count must be a positive integer. Read as base 10, so "08" is 8 and not an octal
# error.
positive_int() {
  local name="$1" value="$2"
  case "$value" in
    ''|*[!0-9]*) echo "error: $name must be a positive integer, got '$value'" >&2; exit 2 ;;
  esac
  if [ $(( 10#$value )) -le 0 ]; then
    echo "error: $name must be a positive integer, got '$value'" >&2
    exit 2
  fi
  echo $(( 10#$value ))
}
K="$(positive_int MELEE_DELTA_K "${MELEE_DELTA_K:-8}")"
STEP="$(positive_int MELEE_DELTA_STEP "${MELEE_DELTA_STEP:-5}")"
JOBS="$(positive_int MELEE_DELTA_JOBS "${MELEE_DELTA_JOBS:-2}")"
positive_int MELEE_DELTA_TIMEOUT "${MELEE_DELTA_TIMEOUT:-300}" >/dev/null
positive_int MELEE_DELTA_COMPARE_TIMEOUT "${MELEE_DELTA_COMPARE_TIMEOUT:-1800}" >/dev/null
HEAD_OFFSET="${MELEE_DELTA_HEAD_RUN_OFFSET:-0}"
if [ "$HEAD_OFFSET" != 0 ]; then
  HEAD_OFFSET="$(positive_int MELEE_DELTA_HEAD_RUN_OFFSET "$HEAD_OFFSET")"
fi

for tree in "$BASE_TREE" "$HEAD_TREE"; do
  if [ ! -f "$tree/tools/demo/DemoSeed.gd" ]; then
    echo "error: $tree has no tools/demo/DemoSeed.gd, so its runs cannot be perturbed" >&2
    exit 2
  fi
done

# shellcheck source=../lib/melee-clips.sh
. "$TOOL_ROOT/tools/lib/melee-clips.sh"
# shellcheck source=../../website/tools/demo-catalog.sh
. "$HEAD_TREE/website/tools/demo-catalog.sh"
# shellcheck source=../lib/demo-catalog-selection.sh
. "$TOOL_ROOT/tools/lib/demo-catalog-selection.sh"

SELECTION="$(melee_clip_selection "${MELEE_DELTA_CLIPS:-}" "${MELEE_DELTA_SUBSET:-}")" || exit 2
demo_catalog_check_selection "$SELECTION" || exit 2

mkdir -p "$OUT_DIR/dumps/base" "$OUT_DIR/dumps/head"
OUT_DIR="$(cd "$OUT_DIR" && pwd)"
JOB_LIST="$OUT_DIR/jobs.txt"
: > "$JOB_LIST"
for spec in "${DEMOS[@]}"; do
  IFS='|' read -r name source fixed_fps max_frames _width type <<<"$spec"
  type="${type:-replay}"
  demo_catalog_selected "$name" "$SELECTION" || continue
  covered=$(( max_frames * 60 / fixed_fps ))
  ticks="$(seq -s, "$STEP" "$STEP" "$covered")"
  for side in base head; do
    if [ "$side" = base ]; then tree="$BASE_TREE"; else tree="$HEAD_TREE"; fi
    if [ ! -f "$tree/$source" ]; then
      echo "note: '$name' has no $source in the $side tree; skipping it on that side"
      continue
    fi
    for run in $(seq 1 "$K"); do
      if [ "$side" = head ]; then run=$(( run + HEAD_OFFSET )); fi
      dir="$OUT_DIR/dumps/$side/$name/seed$run"
      [ -f "$dir.done" ] && continue
      printf '%s\0%s\0%s\0%s\0%s\0%s\0' "$tree" "$source" "$type" "$ticks" "$run" "$dir" >> "$JOB_LIST"
    done
  done
done

for tree in "$BASE_TREE" "$HEAD_TREE" "$TOOL_ROOT"; do
  run_bounded "${MELEE_DELTA_TIMEOUT:-300}" "$GODOT_BIN" --headless --import --path "$tree" >/dev/null 2>&1 || true
done
START=$SECONDS
if [ -s "$JOB_LIST" ]; then
  echo "== $(( $(tr -cd '\0' < "$JOB_LIST" | wc -c) / 6 )) perturbed runs, $JOBS at a time =="
  xargs -0 -n 6 -P "$JOBS" bash "$SCRIPT_DIR/melee-outcome-delta.sh" --run-one < "$JOB_LIST" || {
    echo "error: at least one perturbed run failed" >&2
    exit 2
  }
fi
echo "== runs took $(( SECONDS - START ))s =="

rc=0
GODOT_ARGS=(--alpha "${MELEE_DELTA_ALPHA:-0.05}" --min-ticks "${MELEE_DELTA_MIN_TICKS:-30}"
  --min-metres "${MELEE_DELTA_MIN_METRES:-1}" --min-men "${MELEE_DELTA_MIN_MEN:-2}"
  --min-runs "${MELEE_DELTA_MIN_RUNS:-4}" --travel "${MELEE_DELTA_TRAVEL:-60,150,300}"
  --markdown "$OUT_DIR/melee-delta.md"
  --label "Base \`$(git -C "$BASE_TREE" rev-parse --short HEAD 2>/dev/null || echo "$BASE_TREE")\`, head \`$(git -C "$HEAD_TREE" rev-parse --short HEAD 2>/dev/null || echo "$HEAD_TREE")\`; snapshots every $STEP ticks.")
run_bounded "${MELEE_DELTA_COMPARE_TIMEOUT:-1800}" "$GODOT_BIN" --headless --path "$TOOL_ROOT" \
    -s tools/demo/melee_outcome_compare.gd -- "$OUT_DIR/dumps/base" "$OUT_DIR/dumps/head" \
    "${GODOT_ARGS[@]}" > "$OUT_DIR/compare.log" 2>&1 || rc=$?
grep '^MELEE' "$OUT_DIR/compare.log" > "$OUT_DIR/melee-delta.tsv" || true
if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
  echo "error: the comparison failed (rc $rc); log: $OUT_DIR/compare.log" >&2
  exit 2
fi
if [ ! -s "$OUT_DIR/melee-delta.md" ]; then
  echo "error: the comparison wrote no summary; log: $OUT_DIR/compare.log" >&2
  exit 2
fi
grep '^MELEE-SUMMARY' "$OUT_DIR/compare.log" || true
echo "Summary: $OUT_DIR/melee-delta.md"
exit "$rc"
