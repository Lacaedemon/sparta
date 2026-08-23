#!/usr/bin/env bash
# tools/study/relief-balance/run-study.sh -- run one arm of the relief-balance study
# across a seed range and collect the per-tick state dumps.
#
# Generates one scripted-input file per seed with build-scenarios.py, drives each through
# tools/demo/dump-state.sh, and leaves the raw state_*.json under <out-dir>/<seed>/.
# summarize.py turns that tree into the study's numbers.
#
# The generated scripts land under tools/study/relief-balance/_generated/ (gitignored)
# rather than a temp dir, because DemoInputRecorder opens them through res:// and so can
# only see paths inside the project.
#
# Usage:
#   tools/study/relief-balance/run-study.sh <arm> <out-dir>
#
#   <arm>       mirror (both sides in the same shape) or asym (one wide line against a
#               reserved rear rank). Both sides rotate in BOTH arms -- see the README.
#   <out-dir>   Where to collect the dumps. Created if absent.
#
# Environment:
#   GODOT_BIN                 Godot 4.7 binary (default: godot).
#   SPARTA_STUDY_SEEDS        Seed range LO-HI or comma list (default 101-120).
#   SPARTA_STUDY_DOCTRINE     Team 1's doctrine (default cautious).
#   SPARTA_STUDY_COUNT        Soldiers per unit (default 45).
#   SPARTA_STUDY_FRONT_MORALE Front-rank starting morale (default 34).
#   SPARTA_STUDY_LAST_TICK    Final dump tick (default 1440).
#   SPARTA_STUDY_TICK_STEP    Dump interval (default 60).
#
# Example (Windows, from the repo root):
#   GODOT_BIN="C:\Users\you\apps\Godot_v4.7-stable_win64_console.exe" \
#     SPARTA_STUDY_SEEDS=101-110 \
#     tools/study/relief-balance/run-study.sh mirror /tmp/relief-mirror
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../../.." && pwd)}"

if [ "$#" -lt 2 ]; then
  sed -n '2,/^set /{/^set /d;s/^# \{0,1\}//;p}' "$0"
  exit 2
fi

ARM="$1"
OUT_DIR="$2"
GEN_DIR="$SCRIPT_DIR/_generated/$ARM"

rm -rf "$GEN_DIR"
mkdir -p "$GEN_DIR" "$OUT_DIR"

python3 "$SCRIPT_DIR/build-scenarios.py" "$GEN_DIR" \
  --arm "$ARM" \
  --seeds "${SPARTA_STUDY_SEEDS:-101-120}" \
  --doctrine "${SPARTA_STUDY_DOCTRINE:-cautious}" \
  --count "${SPARTA_STUDY_COUNT:-45}" \
  --front-morale "${SPARTA_STUDY_FRONT_MORALE:-34}" \
  --last-tick "${SPARTA_STUDY_LAST_TICK:-1440}" \
  --tick-step "${SPARTA_STUDY_TICK_STEP:-60}" >/dev/null

LAST_TICK="${SPARTA_STUDY_LAST_TICK:-1440}"
TICK_STEP="${SPARTA_STUDY_TICK_STEP:-60}"
WANT="$(python3 -c "import sys; print(len(range(int(sys.argv[1]), int(sys.argv[2]) + 1, int(sys.argv[1]))))" "$TICK_STEP" "$LAST_TICK")"
TICKS="$(python3 -c "import sys; print(','.join(str(t) for t in range(int(sys.argv[1]), int(sys.argv[2]) + 1, int(sys.argv[1]))))" "$TICK_STEP" "$LAST_TICK")"

n=0
for script in "$GEN_DIR"/*.json; do
  seed="$(basename "$script" .json)"
  seed="${seed#*_}"
  rel="${script#"$PROJECT_ROOT"/}"
  echo "[study] $ARM seed $seed"
  # A single seed's battle is one sample of a chaotic sim; a crashed or timed-out run is
  # a MISSING sample, not a zero, so drop it loudly and let summarize.py report the count
  # it actually had rather than silently averaging over a gap.
  if ! GODOT_BIN="${GODOT_BIN:-godot}" "$PROJECT_ROOT/tools/demo/dump-state.sh" \
        "$rel" "$TICKS" "$OUT_DIR/$seed" >"$OUT_DIR/$seed.log" 2>&1; then
    echo "[study] WARNING: seed $seed failed; see $OUT_DIR/$seed.log" >&2
    rm -rf "$OUT_DIR/$seed"
    continue
  fi
  n=$((n + 1))
done

echo "[study] $ARM: $n seed(s) completed into $OUT_DIR (each with $WANT snapshots)"
