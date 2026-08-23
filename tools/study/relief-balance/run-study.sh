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
# Environment. Each is forwarded only when set, so build-scenarios.py's own defaults stay
# reachable -- a shell-side default here would SHADOW that script's, which is exactly how
# this runner kept generating `cautious` scenarios after the generator's default had been
# changed to a zero-reserve doctrine, silently running the arm the README calls invalid.
#   GODOT_BIN                 Godot 4.7 binary (default: godot).
#   SPARTA_STUDY_SEEDS        Seed range LO-HI or comma list.
#   SPARTA_STUDY_DOCTRINE     Team 1's doctrine. A reserve-holding doctrine invalidates
#                             the measurement; the README says why.
#   SPARTA_STUDY_COUNT        Soldiers per unit.
#   SPARTA_STUDY_FRONT_MORALE Front-rank starting morale.
#   SPARTA_STUDY_REAR_MORALE  Rear-rank starting morale.
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

LAST_TICK="${SPARTA_STUDY_LAST_TICK:-1440}"
TICK_STEP="${SPARTA_STUDY_TICK_STEP:-60}"

gen_args=(--arm "$ARM" --last-tick "$LAST_TICK" --tick-step "$TICK_STEP")
[ -n "${SPARTA_STUDY_SEEDS:-}" ] && gen_args+=(--seeds "$SPARTA_STUDY_SEEDS")
[ -n "${SPARTA_STUDY_DOCTRINE:-}" ] && gen_args+=(--doctrine "$SPARTA_STUDY_DOCTRINE")
[ -n "${SPARTA_STUDY_COUNT:-}" ] && gen_args+=(--count "$SPARTA_STUDY_COUNT")
[ -n "${SPARTA_STUDY_FRONT_MORALE:-}" ] && gen_args+=(--front-morale "$SPARTA_STUDY_FRONT_MORALE")
[ -n "${SPARTA_STUDY_REAR_MORALE:-}" ] && gen_args+=(--rear-morale "$SPARTA_STUDY_REAR_MORALE")

python3 "$SCRIPT_DIR/build-scenarios.py" "$GEN_DIR" "${gen_args[@]}" >/dev/null

# What the generator actually chose, read back off a generated file and echoed, so the
# run's own log records the doctrine rather than leaving it to be inferred from a default
# two files away. A study whose validity turns on this value should not make anyone go
# looking for it.
DOCTRINE="$(python3 -c "import json, sys; print(json.load(open(sys.argv[1]))['doctrine'])" \
  "$(find "$GEN_DIR" -name '*.json' | head -1)")"

WANT="$(python3 -c "import sys; print(len(range(int(sys.argv[1]), int(sys.argv[2]) + 1, int(sys.argv[1]))))" "$TICK_STEP" "$LAST_TICK")"
TICKS="$(python3 -c "import sys; print(','.join(str(t) for t in range(int(sys.argv[1]), int(sys.argv[2]) + 1, int(sys.argv[1]))))" "$TICK_STEP" "$LAST_TICK")"

echo "[study] $ARM: doctrine=$DOCTRINE, expecting $WANT snapshot(s) per seed to tick $LAST_TICK"

n=0
dropped=0
for script in "$GEN_DIR"/*.json; do
  seed="$(basename "$script" .json)"
  seed="${seed#*_}"
  rel="${script#"$PROJECT_ROOT"/}"
  echo "[study] $ARM seed $seed"
  # A single seed's battle is one sample of a chaotic sim; a crashed or timed-out run is
  # a MISSING sample, not a zero, so drop it loudly rather than averaging over a gap.
  #
  # The exit status alone does not decide that. DemoInputRecorder's own
  # CAPTURE_TIMEOUT_SEC net calls push_warning and then get_tree().quit(), which exits
  # ZERO -- so a battle cut short at 60 wall-clock seconds leaves a partial dump behind
  # and reports success. Counting the snapshots is what actually catches it, and a
  # truncated battle summarizing as a decided one is the worst failure available here.
  ok=1
  if ! GODOT_BIN="${GODOT_BIN:-godot}" "$PROJECT_ROOT/tools/demo/dump-state.sh" \
        "$rel" "$TICKS" "$OUT_DIR/$seed" >"$OUT_DIR/$seed.log" 2>&1; then
    echo "[study] WARNING: seed $seed exited non-zero; see $OUT_DIR/$seed.log" >&2
    ok=0
  fi
  got="$(find "$OUT_DIR/$seed" -name 'state_*.json' 2>/dev/null | wc -l | tr -d ' ')"
  if [ "$ok" -eq 1 ] && [ "$got" -ne "$WANT" ]; then
    echo "[study] WARNING: seed $seed wrote $got/$WANT snapshots -- truncated run" \
         "(the recorder's capture timeout exits 0); see $OUT_DIR/$seed.log" >&2
    ok=0
  fi
  if [ "$ok" -eq 0 ]; then
    rm -rf "$OUT_DIR/$seed"
    dropped=$((dropped + 1))
    continue
  fi
  n=$((n + 1))
done

echo "[study] $ARM: $n seed(s) kept, $dropped dropped, into $OUT_DIR (doctrine=$DOCTRINE)"
if [ "$n" -eq 0 ]; then
  echo "[study] ERROR: every seed was dropped -- nothing to summarize." >&2
  exit 1
fi
