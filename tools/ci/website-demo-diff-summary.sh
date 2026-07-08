#!/usr/bin/env bash
# Build a markdown table comparing a freshly-recorded set of website demo clips
# (this PR's website/tools/record-demos.sh output) against a baseline set (the
# last successfully published main-branch build), by sha256 + byte size per
# clip. This is a cheap "visual snapshot test" surrogate for #532: it can't say
# HOW a clip's pixels changed, only THAT its rendered output changed — but a
# deterministic replay recorded on the same pipeline should otherwise
# byte-for-byte reproduce, so any diff is a real signal (game behavior, camera
# path, or the ffmpeg encode itself moved) worth a human glance, even though
# rendering nondeterminism (timing jitter, codec version drift) can also
# trigger a false positive. That's why this stays informational, not a gate.
#
# Usage: website-demo-diff-summary.sh <baseline-dir> <new-dir> <out-md>
#
#   <baseline-dir>  directory of previously-published *.mp4 clips (may be
#                   empty / not exist — "no baseline yet" is handled, not an
#                   error).
#   <new-dir>       directory of this run's freshly-recorded *.mp4 clips.
#   <out-md>        path to write the markdown summary table to.
set -euo pipefail

if [ "$#" -ne 3 ]; then
  echo "Usage: $(basename "$0") <baseline-dir> <new-dir> <out-md>" >&2
  exit 1
fi

BASELINE_DIR="$1"
NEW_DIR="$2"
OUT_MD="$3"

hash_of() {
  [ -f "$1" ] && sha256sum "$1" | cut -d' ' -f1
}

size_of() {
  [ -f "$1" ] && stat -c%s "$1" 2>/dev/null
}

# Union of demo names (basenames, sans extension) present in either dir, so a
# demo added or dropped from record-demos.sh's DEMOS array shows up too, not
# just ones present in both. Sorted for a stable, reviewable table order.
NAMES=$(
  {
    [ -d "$BASELINE_DIR" ] && find "$BASELINE_DIR" -maxdepth 1 -name '*.mp4' -printf '%f\n'
    [ -d "$NEW_DIR" ] && find "$NEW_DIR" -maxdepth 1 -name '*.mp4' -printf '%f\n'
    true
  } | sed 's/\.mp4$//' | sort -u
)

CHANGED=0
NEW_COUNT=0
REMOVED=0
UNCHANGED=0

{
  echo "| Demo | Status | Baseline size | New size | Baseline sha256 | New sha256 |"
  echo "|---|---|---|---|---|---|"
} > "$OUT_MD"

while IFS= read -r NAME; do
  [ -n "$NAME" ] || continue
  B="$BASELINE_DIR/$NAME.mp4"
  N="$NEW_DIR/$NAME.mp4"
  BH=$(hash_of "$B" || true)
  NH=$(hash_of "$N" || true)
  BS=$(size_of "$B" || true)
  NS=$(size_of "$N" || true)

  if [ ! -f "$B" ]; then
    STATUS="🆕 new"
    NEW_COUNT=$((NEW_COUNT + 1))
  elif [ ! -f "$N" ]; then
    STATUS="🗑️ removed"
    REMOVED=$((REMOVED + 1))
  elif [ "$BH" = "$NH" ]; then
    STATUS="unchanged"
    UNCHANGED=$((UNCHANGED + 1))
  else
    STATUS="⚠️ changed"
    CHANGED=$((CHANGED + 1))
  fi

  printf '| `%s` | %s | %s | %s | `%s` | `%s` |\n' \
    "$NAME" "$STATUS" "${BS:--}" "${NS:--}" "${BH:0:12}" "${NH:0:12}" >> "$OUT_MD"
done <<< "$NAMES"

TOTAL=$((CHANGED + NEW_COUNT + REMOVED + UNCHANGED))
{
  echo ""
  echo "**Summary:** ${TOTAL} demo(s) compared — ${CHANGED} changed, ${NEW_COUNT} new, ${REMOVED} removed, ${UNCHANGED} unchanged."
} >> "$OUT_MD"

echo "changed=$CHANGED new=$NEW_COUNT removed=$REMOVED unchanged=$UNCHANGED" >&2
