#!/usr/bin/env bash
# Perturbed melee-outcome delta: judge whether a change to melee dynamics makes routers,
# casualties or contact outcomes worse, across a distribution of runs rather than one seed.
#
# Melee outcomes in the catalog clips are chaotic: a negligible change flips which router
# escapes and when a unit dies, so one run per clip cannot tell a regression from chance.
# This runs every selected clip K times on each tree, each run on a different derived seed
# (SPARTA_DEMO_SEED_RUN=1..K, see tools/demo/DemoSeed.gd), so the scenario and its orders
# are unchanged and only the random draws differ. It then compares each metric's base and
# head distributions (tools/demo/melee_outcome_compare.gd) and flags only shifts that are
# both significant at a controlled false discovery rate and at least the row's threshold.
# A clean report is not evidence of no regression for a row that could not have been
# flagged; the report gives each row's minimum detectable shift.
#
# Usage: melee-outcome-delta.sh <base-tree> <head-tree> <out-dir>
#
#   base-tree / head-tree  Two checkouts of the project. Both must carry
#                          tools/demo/DemoSeed.gd, or their runs could not be perturbed.
#   out-dir                Where dumps/<side>/<clip>/seed<k>/ and the reports go:
#                          melee-delta.tsv (every metric row) and melee-delta.md (the
#                          summary to paste into a PR). Each run directory keeps its
#                          metrics.json; a finished run is reused, so a re-run with new
#                          thresholds only re-compares, and only the clips and seeds this
#                          run selects are compared. Reuse is keyed on side, clip and seed,
#                          so use a fresh out-dir whenever either tree changes.
#
#        melee-outcome-delta.sh --derive-clips <tree> <out-dir>
#
#   Runs every catalog clip once and prints the ones with any enemy contact, the list
#   MELEE_CLIPS in tools/lib/melee-clips.sh holds. Needs jq.
#
# Environment (every tunable has a default):
#   GODOT_BIN               Godot 4.7 binary (default: godot).
#   MELEE_DELTA_K           Perturbed runs per clip per side (default 16).
#   MELEE_DELTA_CLIPS       Comma-separated catalog clips (default: every clip in
#                           MELEE_CLIPS, tools/lib/melee-clips.sh).
#   MELEE_DELTA_SUBSET      "quick" selects MELEE_CLIPS_QUICK instead, the clips whose
#                           router outcomes flipped under a 0.0001 rad nudge. Ignored when
#                           MELEE_DELTA_CLIPS is set.
#   MELEE_DELTA_METRICS     A regular expression the metric names must match (default: all).
#                           Narrow it, with MELEE_DELTA_CLIPS, to the question a change
#                           asks: fewer rows means each one needs a less extreme p-value.
#   MELEE_DELTA_STEP        Snapshot cadence in ticks (default 5): the resolution of every
#                           tick metric, and the floor of every tick threshold.
#   MELEE_DELTA_JOBS        Godot runs in parallel (default 2).
#   MELEE_DELTA_TIMEOUT     Hard per-run timeout in seconds (default 300).
#   MELEE_DELTA_COMPARE_TIMEOUT
#                           Hard timeout for the comparison step in seconds (default 1800).
#   MELEE_DELTA_ALPHA       False discovery rate (default 0.05).
#   MELEE_DELTA_CORRECTION  "bh" (default, Benjamini-Hochberg) or "by" (Benjamini-Yekutieli,
#                           valid under any dependence between rows, at a power cost).
#   MELEE_DELTA_MIN_EFFECT  A row's threshold as a multiple of its own run-to-run spread
#                           (default 0.5).
#   MELEE_DELTA_FLOOR_METRES / MELEE_DELTA_FLOOR_MEN
#                           Smallest threshold for a travel metric (default 0.1) and a
#                           headcount (default 1).
#   MELEE_DELTA_MIN_RUNS    Fewest runs per side for a metric to be tested (default 4).
#   MELEE_DELTA_TRAVEL      Tick offsets after a break for the travel metrics
#                           (default 60,150,300).
#   MELEE_DELTA_HEAD_RUN_OFFSET
#                           Play the head side's runs at SPARTA_DEMO_SEED_RUN 1+offset to
#                           K+offset (default 0: both sides play 1..K, so a clip the change
#                           does not touch reads identical). Comparing a tree with itself at
#                           an offset of K is the null calibration: the same code on
#                           disjoint seeds.
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

# import_tree <tree> <log>: import a project once so its class_name globals resolve. A
# failed import fails the delta with its log, rather than leaving every run to fail later
# with a less direct error.
import_tree() {
  local rc=0
  run_bounded "${MELEE_DELTA_TIMEOUT:-300}" "$GODOT_BIN" --headless --import --path "$1" \
      > "$2" 2>&1 || rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "error: importing $1 failed (rc $rc); log $2:" >&2
    tail -n 40 "$2" >&2
    exit 2
  fi
}

# --run-one <tree> <source> <type> <ticks> <end> <run> <dir>: one perturbed dump and its
# metrics. Internal: the parallel pool below re-invokes this script with it.
if [ "${1:-}" = "--run-one" ]; then
  [ "$#" -eq 8 ] || usage
  tree="$2" source="$3" type="$4" ticks="$5" end="$6" run="$7" dir="$8"
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
      --travel "${MELEE_DELTA_TRAVEL:-60,150,300}" --end "$end" >> "$dir.log" 2>&1 || rc=$?
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
    covered=$(( max_frames * 60 / fixed_fps ))
    printf '%s\0%s\0%s\0%s\0%s\0%s\0%s\0' "$tree" "$source" "${type:-replay}" \
        "$(seq -s, "$step" "$step" "$covered")" "$covered" 0 "$out/$name" >> "$out/jobs.txt"
  done
  import_tree "$tree" "$out/import.log"
  xargs -0 -n 7 -P "${MELEE_DELTA_JOBS:-2}" bash "$SCRIPT_DIR/melee-outcome-delta.sh" --run-one \
      < "$out/jobs.txt" || { echo "error: at least one clip run failed" >&2; exit 2; }
  for spec in "${DEMOS[@]}"; do
    name="${spec%%|*}"
    # The extractor's own first_contact: the tick any unit was first in enemy contact.
    if jq -e '.metrics.first_contact | type == "number"' "$out/$name/metrics.json" >/dev/null; then
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
K="$(positive_int MELEE_DELTA_K "${MELEE_DELTA_K:-16}")"
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
COMPARED=""
for spec in "${DEMOS[@]}"; do
  IFS='|' read -r name source fixed_fps max_frames _width type <<<"$spec"
  type="${type:-replay}"
  demo_catalog_selected "$name" "$SELECTION" || continue
  covered=$(( max_frames * 60 / fixed_fps ))
  ticks="$(seq -s, "$STEP" "$STEP" "$covered")"
  if [ ! -f "$BASE_TREE/$source" ] || [ ! -f "$HEAD_TREE/$source" ]; then
    echo "note: '$name' has no $source in one of the trees; skipping it"
    continue
  fi
  COMPARED="$COMPARED,$name"
  for side in base head; do
    if [ "$side" = base ]; then tree="$BASE_TREE"; else tree="$HEAD_TREE"; fi
    for run in $(seq 1 "$K"); do
      if [ "$side" = head ]; then run=$(( run + HEAD_OFFSET )); fi
      dir="$OUT_DIR/dumps/$side/$name/seed$run"
      [ -f "$dir.done" ] && continue
      printf '%s\0%s\0%s\0%s\0%s\0%s\0%s\0' "$tree" "$source" "$type" "$ticks" "$covered" "$run" "$dir" \
          >> "$JOB_LIST"
    done
  done
done
COMPARED="${COMPARED#,}"
[ -n "$COMPARED" ] || { echo "error: no selected clip exists in both trees" >&2; exit 2; }

import_tree "$BASE_TREE" "$OUT_DIR/import-base.log"
import_tree "$HEAD_TREE" "$OUT_DIR/import-head.log"
import_tree "$TOOL_ROOT" "$OUT_DIR/import-tool.log"
START=$SECONDS
if [ -s "$JOB_LIST" ]; then
  echo "== $(( $(tr -cd '\0' < "$JOB_LIST" | wc -c) / 7 )) perturbed runs, $JOBS at a time =="
  xargs -0 -n 7 -P "$JOBS" bash "$SCRIPT_DIR/melee-outcome-delta.sh" --run-one < "$JOB_LIST" || {
    echo "error: at least one perturbed run failed" >&2
    exit 2
  }
fi
echo "== runs took $(( SECONDS - START ))s =="

rc=0
GODOT_ARGS=(--clips "$COMPARED"
  --seeds-base "$(seq -s, 1 "$K")"
  --seeds-head "$(seq -s, $(( 1 + HEAD_OFFSET )) $(( K + HEAD_OFFSET )))"
  --alpha "${MELEE_DELTA_ALPHA:-0.05}" --correction "${MELEE_DELTA_CORRECTION:-bh}"
  --min-effect "${MELEE_DELTA_MIN_EFFECT:-0.5}" --floor-ticks "$STEP"
  --floor-metres "${MELEE_DELTA_FLOOR_METRES:-0.1}" --floor-men "${MELEE_DELTA_FLOOR_MEN:-1}"
  --min-runs "${MELEE_DELTA_MIN_RUNS:-4}"
  --travel "${MELEE_DELTA_TRAVEL:-60,150,300}"
  --markdown "$OUT_DIR/melee-delta.md"
  --label "Base \`$(git -C "$BASE_TREE" rev-parse --short HEAD 2>/dev/null || echo "$BASE_TREE")\`, head \`$(git -C "$HEAD_TREE" rev-parse --short HEAD 2>/dev/null || echo "$HEAD_TREE")\`; snapshots every $STEP ticks.")
if [ -n "${MELEE_DELTA_METRICS:-}" ]; then
  GODOT_ARGS+=(--metrics "$MELEE_DELTA_METRICS")
fi
run_bounded "${MELEE_DELTA_COMPARE_TIMEOUT:-1800}" "$GODOT_BIN" --headless --path "$TOOL_ROOT" \
    -s tools/demo/melee_outcome_compare.gd -- "$OUT_DIR/dumps/base" "$OUT_DIR/dumps/head" \
    "${GODOT_ARGS[@]}" > "$OUT_DIR/compare.log" 2>&1 || rc=$?
grep '^MELEE' "$OUT_DIR/compare.log" > "$OUT_DIR/melee-delta.tsv" || true
if [ "$rc" -ne 0 ] && [ "$rc" -ne 1 ]; then
  echo "error: the comparison failed (rc $rc); log: $OUT_DIR/compare.log" >&2
  tail -n 20 "$OUT_DIR/compare.log" >&2
  exit 2
fi
if [ ! -s "$OUT_DIR/melee-delta.md" ]; then
  echo "error: the comparison wrote no summary; log: $OUT_DIR/compare.log" >&2
  exit 2
fi
grep '^MELEE-SUMMARY' "$OUT_DIR/compare.log" || true
echo "Summary: $OUT_DIR/melee-delta.md"
exit "$rc"
