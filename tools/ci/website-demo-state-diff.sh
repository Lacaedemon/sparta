#!/usr/bin/env bash
# Compare two website demo state-transcript trees (website/tools/dump-demo-states.sh
# output: one subdirectory of state_<tick>.json files per clip) and write a markdown
# summary of which clips' SIM CONTENT changed. This is website-demo-diff.yml's comparison
# step: transcripts are a deterministic function of the sim, so any difference here is a
# real behavioral change -- unlike the rendered clips' bytes, which differ run to run at
# the encoder level and say nothing.
#
# Usage: website-demo-state-diff.sh <baseline-dir> <pr-dir> <out-md> [hash-verdict-file]
#
# For each clip present on both sides, every sampled tick's JSON is normalized (jq -S:
# sorted keys, stable formatting) and compared; a clip row reports the first differing
# tick and the fields that changed there. Clips present on only one side report as
# added/removed. Exit code is always 0 -- the caller posts the summary as an
# informational comment; content changes are for a human to classify, not a gate.
#
# HASH-FIRST FAST PATH (item 4 of #954): pass a hash-verdict file (the `HASHCMP` lines from
# `analyze_transcript.gd --compare-hash-trees`, one per clip) as the optional 4th arg. The
# per-tick hash stream (hash_stream.jsonl, written by every armed dump run) is a strict,
# every-tick digest, so a clip the hash compare calls SAME is genuinely unchanged and skips
# the expensive per-tick jq walk entirely -- the field-level analysis then runs only for the
# clips the hash compare flagged, and each changed row reports the hash's exact first
# divergent tick and tier (positions vs non-position state). Without the file, every clip
# gets the full jq compare, exactly as before (standalone / local use, or a base tree that
# predates the hash stream).
set -euo pipefail

BASELINE_DIR="${1:?usage: website-demo-state-diff.sh <baseline-dir> <pr-dir> <out-md> [hash-verdict-file]}"
PR_DIR="${2:?usage: website-demo-state-diff.sh <baseline-dir> <pr-dir> <out-md> [hash-verdict-file]}"
OUT_MD="${3:?usage: website-demo-state-diff.sh <baseline-dir> <pr-dir> <out-md> [hash-verdict-file]}"
HASH_VERDICT="${4:-}"   # optional HASHCMP lines; when present, SAME clips skip the jq walk

command -v jq >/dev/null 2>&1 || { echo "error: jq not found on PATH" >&2; exit 1; }

# A clip's hash-compare verdict as "STATUS<TAB>tick<TAB>tier" (tick/tier empty unless CHANGED),
# or "" when no verdict file was given or the clip has no line. Lets a SAME clip skip the walk.
hash_status() {
  [ -n "$HASH_VERDICT" ] && [ -f "$HASH_VERDICT" ] || return 0
  awk -F'\t' -v n="$1" '$1=="HASHCMP" && $2==n {printf "%s\t%s\t%s", $3, $4, $5; exit}' "$HASH_VERDICT"
}

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

  # Hash-first fast path: the every-tick hash stream is a strict digest, so a clip the hash
  # compare calls SAME is genuinely unchanged and needs no per-tick jq walk. An empty status
  # (no verdict file, or a clip the compare marked UNKNOWN because a side lacks a stream)
  # falls through to the full walk below, exactly as before.
  status=""; hash_tick=""; hash_tier=""
  IFS=$'\t' read -r status hash_tick hash_tier <<<"$(hash_status "$name")"
  if [ "$status" = "SAME" ]; then
    # Sim content identical over the common tick range. A pure sampling-coverage change (the
    # PR altered this clip's max_frames, so the sampled tick set differs) isn't a sim change,
    # but still surface it -- cheaply, from the file names, no jq.
    if ! diff -q <(ls "$base"/state_*.json 2>/dev/null | xargs -rn1 basename | sort) \
                 <(ls "$pr"/state_*.json 2>/dev/null | xargs -rn1 basename | sort) >/dev/null 2>&1; then
      CHANGED=$((CHANGED + 1))
      CHANGED_ROWS="$CHANGED_ROWS| \`$name\` | coverage | n/a | sampling range changed |
"
      CHANGED_NAMES="$CHANGED_NAMES$name
"
    else
      UNCHANGED=$((UNCHANGED + 1))
    fi
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

  # A hash CHANGED verdict is authoritative for the divergence: report its exact first tick and
  # tier (positions vs non-position state), enriched with the fields differing at the first
  # differing SAMPLED tick -- which can be a later tick than the hash's, or none at all when
  # the divergence is between samples or below display rounding.
  is_changed=0
  tick_col=""; tier_col=""
  if [ "$status" = "CHANGED" ]; then
    is_changed=1
    tick_col="tick $((10#${hash_tick:-0}))"
    case "$hash_tier" in
      cheap) tier_col="positions" ;;
      full) tier_col="non-position state" ;;
      *) tier_col="${hash_tier:-n/a}" ;;
    esac
    [ -n "$fields" ] || fields="below sampled/rounded threshold"
  elif [ -n "$first_diff_tick" ]; then
    # No hash verdict (standalone run, or a tree without a stream): the sampled walk is the
    # only signal, so the tier is unknown.
    is_changed=1
    tick_col="tick $((10#$first_diff_tick))"
    tier_col="n/a"
  fi

  if [ "$is_changed" = "1" ]; then
    CHANGED=$((CHANGED + 1))
    CHANGED_ROWS="$CHANGED_ROWS| \`$name\` | $tick_col | $tier_col | $fields |
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
      printf '| Demo | First divergence | Tier | Changed fields |\n|---|---|---|---|\n%s\n' "$CHANGED_ROWS"
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
