#!/usr/bin/env bash
# Melee penetration report: how deep enemy men stand inside a block in melee, per catalog
# melee clip and engaged pair. Runs each selected clip once on <tree> with FULL state dumps
# every MELEE_PEN_STEP ticks, then measures each run with tools/demo/melee_penetration.py
# (see its docstring for the footprint, depth and "frontal" definitions).
#
# Usage: melee-penetration.sh <tree> <out-dir>
#
#   tree     A checkout of the project to run.
#   out-dir  Where <clip>/ dumps, <clip>.log, pen.tsv (one row per clip and ordered pair),
#            series.tsv (one row per snapshot and pair) and pen.md (per-clip roll-up) go.
#            A clip whose dump is kept (MELEE_PEN_KEEP=1) is not re-run, so use a fresh
#            out-dir whenever the tree changes.
#
# Environment (every tunable has a default):
#   GODOT_BIN          Godot 4.7 binary (default: godot).
#   MELEE_PEN_CLIPS    Comma-separated catalog clips (default: every clip in MELEE_CLIPS,
#                      tools/lib/melee-clips.sh).
#   MELEE_PEN_STEP     Snapshot cadence in ticks (default 10).
#   MELEE_PEN_JOBS     Godot runs in parallel (default 4).
#   MELEE_PEN_TIMEOUT  Hard per-run timeout in seconds (default 300).
#   MELEE_PEN_SEED_RUN When set, plays each clip on that perturbed seed (SPARTA_DEMO_SEED_RUN,
#                      tools/demo/DemoSeed.gd) instead of its own.
#   MELEE_PEN_KEEP     1 keeps the full dumps (about 5 to 60 MB a clip); default 0 deletes
#                      each one once the report is written.
#
# Exit code: 0 = report written, 2 = usage, input or run failure.
set -euo pipefail

usage() {
  echo "usage: melee-penetration.sh <tree> <out-dir>" >&2
  exit 2
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
GODOT_BIN="${GODOT_BIN:-godot}"
TIMEOUT="${MELEE_PEN_TIMEOUT:-300}"
# shellcheck source=../lib/run-bounded.sh
. "$TOOL_ROOT/tools/lib/run-bounded.sh"

PYTHON=""
for cand in python3 python; do
  if command -v "$cand" >/dev/null 2>&1 && "$cand" -c 'import sys; sys.exit(sys.version_info < (3, 8))' \
      >/dev/null 2>&1; then
    PYTHON="$cand"
    break
  fi
done

# --run-one <tree> <source> <type> <ticks> <dir>: one FULL dump. Internal: the parallel pool
# below re-invokes this script with it.
if [ "${1:-}" = "--run-one" ]; then
  [ "$#" -eq 6 ] || usage
  tree="$2" source="$3" type="$4" ticks="$5" dir="$6"
  if [ "$type" = "input" ]; then
    scene=res://tools/demo/DemoInputRecorder.tscn key=SPARTA_DEMO_INPUT
  else
    scene=res://tools/demo/DemoRunner.tscn key=SPARTA_DEMO_REPLAY
  fi
  rm -rf "$dir"
  mkdir -p "$dir"
  seed_env=()
  if [ -n "${MELEE_PEN_SEED_RUN:-}" ]; then
    seed_env=(SPARTA_DEMO_SEED_RUN="$MELEE_PEN_SEED_RUN")
  fi
  rc=0
  run_bounded "$TIMEOUT" env "$key=res://$source" ${seed_env[@]+"${seed_env[@]}"} \
      SPARTA_DEMO_STATE_FULL=1 SPARTA_DEMO_STATE="$ticks" SPARTA_DEMO_STATE_DIR="$dir" \
      "$GODOT_BIN" --headless --fixed-fps 60 --path "$tree" "$scene" > "$dir.log" 2>&1 || rc=$?
  # push_error() exits 0, so the snapshots are the evidence the run worked.
  if [ "$rc" -ne 0 ] || ! ls "$dir"/state_*.json >/dev/null 2>&1; then
    echo "error: $source in $tree failed (rc $rc); log: $dir.log" >&2
    exit 2
  fi
  # A run that stopped short of its last requested tick without a battle_over snapshot was
  # cut off. A replay clip's stream carries no battle_over marker, so a replay whose battle
  # ends early lands here too: say so, and list it in truncated.txt beside the report,
  # rather than measuring a partial run silently.
  last="${ticks##*,}"
  if [ ! -f "$dir/$(printf 'state_%05d.json' "$last")" ] \
      && ! grep -q '"battle_over"' "$(ls "$dir"/state_*.json | tail -n 1)"; then
    echo "warning: $source stopped before tick $last; its report row is partial" >&2
    echo "$(basename "$dir")" >> "$(dirname "$dir")/truncated.txt"
  fi
  touch "$dir.done"
  exit 0
fi

[ "$#" -eq 2 ] || usage
[ -n "$PYTHON" ] || { echo "error: python 3.8 or later not found on PATH" >&2; exit 2; }
TREE="$(cd "$1" && pwd)" || usage
mkdir -p "$2"
OUT_DIR="$(cd "$2" && pwd)"
STEP="${MELEE_PEN_STEP:-10}"
case "$STEP" in ''|*[!0-9]*|0) echo "error: MELEE_PEN_STEP must be a positive integer" >&2; exit 2 ;; esac

# shellcheck source=../lib/melee-clips.sh
. "$TOOL_ROOT/tools/lib/melee-clips.sh"
# shellcheck source=../../website/tools/demo-catalog.sh
. "$TREE/website/tools/demo-catalog.sh"
# shellcheck source=../lib/demo-catalog-selection.sh
. "$TOOL_ROOT/tools/lib/demo-catalog-selection.sh"
SELECTION="$(melee_clip_selection "${MELEE_PEN_CLIPS:-}" "")" || exit 2
demo_catalog_check_selection "$SELECTION" || exit 2

JOB_LIST="$OUT_DIR/jobs.txt"
: > "$JOB_LIST"
RUNS=()
for spec in "${DEMOS[@]}"; do
  IFS='|' read -r name source fixed_fps max_frames _width type <<<"$spec"
  demo_catalog_selected "$name" "$SELECTION" || continue
  if [ ! -f "$TREE/$source" ]; then
    echo "note: '$name' has no $source in $TREE; skipping it"
    continue
  fi
  covered=$(( max_frames * 60 / fixed_fps ))
  RUNS+=("$OUT_DIR/$name=$name")
  [ -f "$OUT_DIR/$name.done" ] && continue
  printf '%s\0%s\0%s\0%s\0%s\0' "$TREE" "$source" "${type:-replay}" \
      "$(seq -s, "$STEP" "$STEP" "$covered")" "$OUT_DIR/$name" >> "$JOB_LIST"
done
[ "${#RUNS[@]}" -gt 0 ] || { echo "error: no selected clip exists in $TREE" >&2; exit 2; }

if [ -s "$JOB_LIST" ]; then
  rc=0
  run_bounded "$TIMEOUT" "$GODOT_BIN" --headless --import --path "$TREE" > "$OUT_DIR/import.log" 2>&1 \
      || rc=$?
  [ "$rc" -eq 0 ] || { echo "error: importing $TREE failed (rc $rc); log $OUT_DIR/import.log" >&2; exit 2; }
  rm -f "$OUT_DIR/truncated.txt"
  xargs -0 -n 5 -P "${MELEE_PEN_JOBS:-4}" bash "$SCRIPT_DIR/melee-penetration.sh" --run-one \
      < "$JOB_LIST" || { echo "error: at least one clip run failed" >&2; exit 2; }
fi

"$PYTHON" "$SCRIPT_DIR/melee_penetration.py" "${RUNS[@]}" --tsv "$OUT_DIR/pen.tsv" \
    --series "$OUT_DIR/series.tsv" --markdown "$OUT_DIR/pen.md" > "$OUT_DIR/report.txt"
grep '^PEN-CLIP\|^PEN-ALL' "$OUT_DIR/report.txt" || true
if [ -s "$OUT_DIR/truncated.txt" ]; then
  echo "warning: these clips stopped short, so their rows are partial: $(tr '\n' ' ' < "$OUT_DIR/truncated.txt")" >&2
fi
if [ "${MELEE_PEN_KEEP:-0}" != "1" ]; then
  for run in "${RUNS[@]}"; do
    rm -f "${run%%=*}"/state_*.json "${run%%=*}"/hash_stream.jsonl "${run%%=*}.done"
  done
fi
echo "Report: $OUT_DIR/pen.md, $OUT_DIR/pen.tsv"
