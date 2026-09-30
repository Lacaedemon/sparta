#!/usr/bin/env bash
# Build a compact, human+AI-readable game-state summary from a set of per-tick
# state_<tick>.json snapshots (written by tools/demo/DemoInputRecorder.gd) and a
# single merged JSON of all snapshots. The summary is inlined into the demo PR
# comment so a reviewer — human or the @claude review bot — reads exact per-tick
# unit state (State / formation / order mode / morale / soldiers / centroid)
# directly in the PR conversation, instead of eyeballing the GIF. The merged JSON
# is published alongside the GIF/MP4 for full detail.
#
# Usage:
#   tools/ci/state-transcript-summary.sh <state-dir> <merged-json-out> <summary-md-out> [table-max-bytes]
#
#   <state-dir>        Dir holding state_<tick>.json files (from the dump run).
#   <merged-json-out>  Path to write the merged {"ticks":[{tick,units}, …]} JSON.
#   <summary-md-out>   Path to write the compact markdown summary block.
#   [table-max-bytes]  Byte budget for the summary's table rows (default 45000, which
#                      leaves ~20 KB of GitHub's 65,536-character comment cap for the
#                      wrapper and the defect-scan block the workflow appends).
#
# Emits nothing to the media/comment when no snapshots were produced: exits non-zero
# so the caller treats it as a failed (best-effort) dump and posts no transcript.
# Requires jq.
set -euo pipefail

if [ "$#" -lt 3 ]; then
  echo "Usage: $(basename "$0") <state-dir> <merged-json-out> <summary-md-out> [table-max-bytes]" >&2
  exit 2
fi

STATE_DIR="$1"
MERGED_OUT="$2"
SUMMARY_OUT="$3"
TABLE_MAX_BYTES="${4:-45000}"
case "$TABLE_MAX_BYTES" in
  ''|*[!0-9]*) echo "table-max-bytes must be a non-negative integer, got '$TABLE_MAX_BYTES'" >&2; exit 2 ;;
esac

# Collect the per-tick snapshots in tick order. Zero-padded filenames sort correctly.
shopt -s nullglob
FILES=("$STATE_DIR"/state_*.json)
if [ "${#FILES[@]}" -eq 0 ]; then
  echo "No state_*.json snapshots found in $STATE_DIR" >&2
  exit 1
fi

# Merge every snapshot into one array, sorted by tick, as the full downloadable artifact.
# `-s` slurps the files into an array; each element is already a {tick,units} object.
# The file list goes through xargs rather than onto jq's command line: a per-tick
# sampled demo holds hundreds of snapshots, whose paths overflow Windows' 32 KB command
# line when the script is run locally.
printf '%s\0' "${FILES[@]}" | xargs -0 cat | jq -s 'sort_by(.tick) | {ticks: .}' > "$MERGED_OUT"

# Guard the artifact per the push_error/exit-code note in CLAUDE.md: verify the merged
# JSON exists and is non-empty (and actually holds ticks) rather than trusting exit code.
if [ ! -s "$MERGED_OUT" ] || [ "$(jq '.ticks | length' "$MERGED_OUT")" -eq 0 ]; then
  echo "Merged transcript JSON is empty or has no ticks" >&2
  exit 1
fi

# Build the compact markdown summary: ONE table for the whole transcript, one row per
# unit per dumped tick, with the key fields a reviewer needs. Centroid is the
# soldier-body centre [x,y]; a far-tier unit carries no per-soldier payload (its record
# omits soldier_summary -- see demos/README.md), so its centroid cell reads "-" instead
# of indexing a missing object. `.tier // "CLOSE"` keeps transcripts from before the
# tier field rendering cleanly.
#
# The table is bounded to TABLE_MAX_BYTES so the PR comment it is posted in stays under
# GitHub's 65,536-character cap after the wrapper and the defect-scan block are added.
# A dense `state` list (per-tick sampling, which the consecutive-sample defect detectors
# sometimes need) would otherwise overflow it and fail the whole Demo video job with a
# 422. Over budget, the first and last rows are kept and the middle is replaced by one
# marker row naming what was omitted; the full JSON artifact always holds every tick.
# Bytes over-count characters, so a byte budget is conservative.
TABLE_ROWS="$SUMMARY_OUT.rows"
jq -r '
  .ticks[]
  | .tick as $t
  | .units[]
  | "| \($t) | \(.name) | \(.team) | \(.state) | \(.formation) | \(.order_mode) | \(.morale) | \(.soldiers) | \(.tier // "CLOSE") | \(
      if .soldier_summary != null
      then "[\(.soldier_summary.centroid[0]), \(.soldier_summary.centroid[1])]"
      else "-"
      end) |"
' "$MERGED_OUT" > "$TABLE_ROWS"

{
  echo '<details><summary>🔬 <b>Per-tick state transcript</b> — exact unit state for AI/spot verification</summary>'
  echo
  echo '| tick | unit | team | state | formation | order | morale | soldiers | tier | centroid |'
  echo '| ---: | --- | --- | --- | --- | --- | ---: | ---: | --- | --- |'
  # LC_ALL=C makes awk's length() count bytes, matching the budget's unit.
  LC_ALL=C awk -v budget="$TABLE_MAX_BYTES" '
    { row[NR] = $0; size[NR] = length($0) + 1; total += size[NR] }
    END {
      if (total <= budget) { for (i = 1; i <= NR; i++) print row[i]; exit }
      # Reserve room for the marker row, then split what is left between head and tail.
      half = int((budget - 200) / 2)
      used = 0
      for (h = 0; h < NR && used + size[h + 1] <= half; h++) used += size[h + 1]
      used = 0
      for (t = 0; t < NR - h && used + size[NR - t] <= half; t++) used += size[NR - t]
      for (i = 1; i <= h; i++) print row[i]
      omitted = NR - h - t
      split(row[h + 1], first, "|"); split(row[NR - t], last, "|")
      gsub(/ /, "", first[2]); gsub(/ /, "", last[2])
      printf "| ... | *%d rows (ticks %s to %s) omitted to fit the PR comment size limit; the full JSON transcript linked below has every tick* |\n", omitted, first[2], last[2]
      for (i = NR - t + 1; i <= NR; i++) print row[i]
    }
  ' "$TABLE_ROWS"
  echo
  echo '</details>'
} > "$SUMMARY_OUT"
rm -f "$TABLE_ROWS"

if [ ! -s "$SUMMARY_OUT" ]; then
  echo "Summary markdown is empty" >&2
  exit 1
fi

echo "Wrote merged transcript ($(jq '.ticks | length' "$MERGED_OUT") ticks) and summary."
