#!/usr/bin/env bash
# Compare two website demo state-transcript trees (website/tools/dump-demo-states.sh
# output: one subdirectory of state_<tick>.json files per clip) and write a markdown
# summary of which clips' SIM CONTENT changed. This is website-demo-diff.yml's comparison
# step: transcripts are a deterministic function of the sim, so any difference here is a
# real behavioral change -- unlike the rendered clips' bytes, which differ run to run at
# the encoder level and say nothing.
#
# Usage: website-demo-state-diff.sh <baseline-dir> <pr-dir> <out-md>
#
# For each clip present on both sides, every sampled tick's JSON is normalized (jq -S:
# sorted keys, stable formatting) and compared; a clip row reports the first differing
# tick and the fields that changed there. Clips present on only one side report as
# added/removed. Exit code is always 0 -- the caller posts the summary as an
# informational comment; content changes are for a human to classify, not a gate.
set -euo pipefail

BASELINE_DIR="${1:?usage: website-demo-state-diff.sh <baseline-dir> <pr-dir> <out-md>}"
PR_DIR="${2:?usage: website-demo-state-diff.sh <baseline-dir> <pr-dir> <out-md>}"
OUT_MD="${3:?usage: website-demo-state-diff.sh <baseline-dir> <pr-dir> <out-md>}"

command -v jq >/dev/null 2>&1 || { echo "error: jq not found on PATH" >&2; exit 1; }

# The union of clip names on either side, sorted for a stable report.
clip_names() {
  {
    [ -d "$BASELINE_DIR" ] && find "$BASELINE_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n'
    [ -d "$PR_DIR" ] && find "$PR_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%f\n'
  } | sort -u
}

# The top-level unit fields that differ between two normalized tick files, as a compact
# comma-separated list (e.g. "position, morale, state"). Compares each uid's record
# field-by-field; battle-level differences (a unit appearing/disappearing) report as
# "units present".
changed_fields() {
  local base_file="$1" pr_file="$2"
  jq -n --slurpfile a "$base_file" --slurpfile b "$pr_file" '
    def recs(s): s[0].units
      | map(del(.soldiers_full, .motion_ref))
      | map({key: (.uid | tostring), value: .}) | from_entries;
    (recs($a)) as $ra | (recs($b)) as $rb |
    if ($ra | keys) != ($rb | keys) then "units present"
    else
      [ $ra | keys[] as $uid |
        (($ra[$uid] | keys) + ($rb[$uid] | keys) | unique[]) as $f |
        select($ra[$uid][$f] != $rb[$uid][$f]) | $f
      ] | unique | join(", ")
    end
  ' -r
}

CHANGED_ROWS=""
CHANGED_NAMES=""
UNCHANGED=0
ADDED=""
REMOVED=""
CHANGED=0

for name in $(clip_names); do
  base="$BASELINE_DIR/$name"
  pr="$PR_DIR/$name"
  if [ ! -d "$base" ]; then
    ADDED="$ADDED $name"
    continue
  fi
  if [ ! -d "$pr" ]; then
    REMOVED="$REMOVED $name"
    continue
  fi
  first_diff_tick=""
  fields=""
  # Walk the union of tick files so a coverage change (a tick present on one side only)
  # also reads as a content change rather than being skipped.
  for tick_file in $({ ls "$base"/state_*.json 2>/dev/null; ls "$pr"/state_*.json 2>/dev/null; } \
      | xargs -rn1 basename | sort -u); do
    bf="$base/$tick_file"
    pf="$pr/$tick_file"
    if [ ! -f "$bf" ] || [ ! -f "$pf" ]; then
      first_diff_tick="${tick_file//[!0-9]/}"
      fields="tick sampled on one side only"
      break
    fi
    # Compare the COMPACT projection only: the FULL-dump extras (per-soldier arrays,
    # ordered slots, motion constants) exist for the defect-delta pass, not the diff --
    # projecting them out keeps this report's semantics identical to the pre-full-dump
    # transcripts, and lets a mixed pair (one side's tree predating the full schema)
    # still compare apples to apples.
    if ! cmp -s <(jq -S 'del(.units[].soldiers_full, .units[].motion_ref)' "$bf") \
                <(jq -S 'del(.units[].soldiers_full, .units[].motion_ref)' "$pf"); then
      first_diff_tick="${tick_file//[!0-9]/}"
      fields="$(changed_fields "$bf" "$pf")"
      break
    fi
  done
  if [ -n "$first_diff_tick" ]; then
    CHANGED=$((CHANGED + 1))
    CHANGED_ROWS="$CHANGED_ROWS| \`$name\` | tick $((10#$first_diff_tick)) | $fields |
"
    CHANGED_NAMES="$CHANGED_NAMES$name
"
  else
    UNCHANGED=$((UNCHANGED + 1))
  fi
done

{
  if [ "$CHANGED" -eq 0 ] && [ -z "$ADDED" ] && [ -z "$REMOVED" ]; then
    printf '**No sim-content changes** across %d clips -- every sampled tick of every website demo plays out identically to the merge-base.\n' "$UNCHANGED"
  else
    if [ "$CHANGED" -gt 0 ]; then
      printf '| Demo | First divergence | Changed fields there |\n|---|---|---|\n%s\n' "$CHANGED_ROWS"
    fi
    [ -n "$ADDED" ] && printf '**New clips:**%s\n\n' "$ADDED"
    [ -n "$REMOVED" ] && printf '**Removed clips:**%s\n\n' "$REMOVED"
  fi
  printf '\n**Summary:** %d changed, %d unchanged, %d new, %d removed.\n' \
    "$CHANGED" "$UNCHANGED" "$(echo "$ADDED" | wc -w)" "$(echo "$REMOVED" | wc -w)"
} > "$OUT_MD"

# Machine-readable list of the clips classified CHANGED (both-sides rows only), one name
# per line -- the defect-delta pass iterates exactly these.
printf '%s' "$CHANGED_NAMES" > "$OUT_MD.changed"

echo "Wrote $OUT_MD (+ .changed list: $CHANGED changed clips)"
