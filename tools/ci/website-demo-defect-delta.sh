#!/usr/bin/env bash
# Per-changed-clip defect delta: run the deterministic DemoDefects analyzer
# (tools/demo/analyze_transcript.gd) over BOTH sides' FULL transcripts of every clip the
# state diff flagged as changed, and emit a markdown fragment labeling any defect that
# fires on the PR side but not the merge-base as a CANDIDATE REGRESSION. This is the
# algorithmic core of the demo-diff classification: most changed clips are the PR's own
# intended effect, and a clean both-sides defect scan says so mechanically -- reviewer
# judgment narrows to the delta rows.
#
# EVERY DELTA IS POST-DIVERGENCE, STRUCTURALLY. The hash pre-filter's first divergent tick
# is the first tick at which the two runs' per-tick state hash differs, and that hash
# (DemoStateHash.cheap_tick_hash, written EVERY tick) covers each unit's position plus the
# whole `_sim_soldier_pos` byte array -- exactly the data the position-derived metrics are
# computed from. So below that tick the two sides are bit-identical by construction and no
# metric can differ; any difference this script reports necessarily developed after it.
#
# That is why the scan is NOT bounded to the pre-divergence ticks: bounding there would not
# narrow the comparison, it would empty it, and every row would report a vacuous machine
# clear. What the divergence tick is good for is CALIBRATION, so it is reported instead:
# a clip that diverges at tick 960 of 1300 had a short chaotic tail to grow a difference in,
# while one that diverges at tick 60 was restructured wholesale and its delta is far more
# likely to mean something. A reviewer needs that number to tell those two rows apart --
# without it, both just read "candidate regression".
#
# Usage: website-demo-defect-delta.sh <baseline-dir> <pr-dir> <changed-list> <out-fragment> \
#            [pr-tree] [hash-verdict]
#
#   baseline-dir / pr-dir  The two transcript trees the state diff compared.
#   changed-list           One clip name per line (the diff script's .changed output).
#   out-fragment           Markdown fragment to write (empty file when nothing to report).
#   pr-tree                Project root whose analyzer runs (default: cwd). Always the PR
#                          side's tree, so both sides are judged by the same metrics.
#   hash-verdict           Optional HASHCMP lines (analyze_transcript.gd
#                          --compare-hash-trees). Supplies each clip's first divergent tick
#                          for the calibration column; without it that column reads
#                          "unknown" and nothing else changes.
#
# A side whose transcripts lack the FULL-dump fields (a merge-base predating them)
# reports "n/a" rather than failing -- absence of data is not a defect, and the
# comparison self-resolves once both sides carry the schema. Exit code is always 0:
# like the state diff itself, this is informational; the PR's OWN demo has its real
# gate in demo-video.yml.
set -euo pipefail

BASELINE_DIR="${1:?usage: website-demo-defect-delta.sh <baseline-dir> <pr-dir> <changed-list> <out-fragment> [pr-tree] [hash-verdict]}"
PR_DIR="${2:?usage: website-demo-defect-delta.sh <baseline-dir> <pr-dir> <changed-list> <out-fragment> [pr-tree] [hash-verdict]}"
CHANGED_LIST="${3:?usage: website-demo-defect-delta.sh <baseline-dir> <pr-dir> <changed-list> <out-fragment> [pr-tree] [hash-verdict]}"
OUT_MD="${4:?usage: website-demo-defect-delta.sh <baseline-dir> <pr-dir> <changed-list> <out-fragment> [pr-tree] [hash-verdict]}"
PR_TREE="${5:-$PWD}"
HASH_VERDICT="${6:-}"
GODOT_BIN="${GODOT_BIN:-godot}"

command -v jq >/dev/null 2>&1 || { echo "error: jq not found on PATH" >&2; exit 1; }

: > "$OUT_MD"
if [ ! -s "$CHANGED_LIST" ]; then
  echo "No changed clips; no defect delta to compute."
  exit 0
fi

# The catalog maps clip names to their source scripts, whose declared `expect` assertions and
# `defect_exemptions` (input-type rows only) join the scan on both sides.
# shellcheck source=../../website/tools/demo-catalog.sh
. "$PR_TREE/website/tools/demo-catalog.sh"

# Both helpers below are shared with the absolute catalog sweep
# (tools/ci/website-demo-defect-sweep.sh), which needs the identical reduction --
# see the lib's own header for why a second copy here would drift silently.
# shellcheck source=../lib/demo-defect-metrics.sh
. "$PR_TREE/tools/lib/demo-defect-metrics.sh"

# Failing metrics for one transcript dir, as "metric (uidN), ..." | "clean" | "n/a".
# The delta deliberately ignores the analyzer's rc (field 1 of the shared verdict): a
# clip whose own declarations are malformed reduces to "n/a" here, which this script
# already reports as an unjudgeable side rather than a clean one.
failing_metrics() {
  demo_defect_verdict "$1" "$2" "$PR_TREE" | cut -f2
}

# The first divergent tick the hash pre-filter recorded for a clip, or empty when it
# reported anything other than CHANGED (or no verdict file was passed at all).
divergence_tick() {
  [ -n "$HASH_VERDICT" ] && [ -f "$HASH_VERDICT" ] || return 0
  awk -F'\t' -v n="$1" '$1=="HASHCMP" && $2==n && $3=="CHANGED" {print $4; exit}' "$HASH_VERDICT"
}

# The highest tick a transcript dir holds a snapshot for, read from the state_<tick>.json
# filenames alone -- no Godot run, no JSON parse. Empty when the dir holds none.
last_snapshot_tick() {
  ls "$1"/state_*.json 2>/dev/null \
    | sed 's|.*/state_||; s|\.json$||' | grep -E '^[0-9]+$' | sort -n | tail -1
}

# "tick 960 of 1300 (26% downstream)" -- when the divergence landed, and how much of the
# clip sits after it, which is the range any reported difference had to develop over.
#
# Both ticks are normalized through 10# before any arithmetic. The snapshot tick comes out
# of a state_%05d.json filename, so it is ALWAYS zero-padded, and bash reads a leading-zero
# numeral as OCTAL: "00960" aborts the script outright under `set -e` ("value too great for
# base", since 9 is not an octal digit), and a value whose digits happen to all be octal-
# valid computes silently wrong instead. The HASHCMP tick is unpadded today, but it is
# normalized too so a future format change cannot reintroduce this.
divergence_label() {
  local div="$1" last="$2" downstream
  if [ -z "$div" ]; then
    printf 'unknown'
    return 0
  fi
  div=$(( 10#$div ))
  if [ -n "$last" ]; then
    last=$(( 10#$last ))
  else
    last=0
  fi
  if [ "$last" -le 0 ]; then
    printf 'tick %d' "$div"
    return 0
  fi
  # A divergence past the last SAMPLED tick is possible -- the hash stream is written every
  # tick while snapshots are sparse -- and means no sampled tick is downstream of it.
  downstream=$(( (last - div) * 100 / last ))
  if [ "$downstream" -lt 0 ]; then
    downstream=0
  fi
  printf 'tick %d of %d (%d%% downstream)' "$div" "$last" "$downstream"
}

# The metrics failing on the PR side ($2) that are absent from the merge-base side ($1).
# "clean" and "n/a" are statuses, not metrics, so they never enter a difference.
metric_set() {
  printf '%s\n' "$1" | tr ',' '\n' | sed 's/^ *//; s/ *$//' \
    | grep -vxE 'clean|n/a|' | sort -u || true
}

new_metrics() {
  comm -13 <(metric_set "$1") <(metric_set "$2") || true
}

ROWS=""
REGRESSION_COUNT=0
while IFS= read -r name; do
  [ -n "$name" ] || continue
  [ -d "$BASELINE_DIR/$name" ] && [ -d "$PR_DIR/$name" ] || continue
  script_src="$(demo_clip_script_source "$name" "$PR_TREE")"
  base_fail="$(failing_metrics "$BASELINE_DIR/$name" "$script_src")"
  pr_fail="$(failing_metrics "$PR_DIR/$name" "$script_src")"
  div_label="$(divergence_label "$(divergence_tick "$name")" "$(last_snapshot_tick "$PR_DIR/$name")")"

  verdict="no new defects"
  if [ "$pr_fail" = "n/a" ] || [ "$base_fail" = "n/a" ]; then
    verdict="n/a (a side lacks full-dump data)"
  elif [ "$pr_fail" != "clean" ]; then
    new_in_pr="$(new_metrics "$base_fail" "$pr_fail")"
    if [ -n "$new_in_pr" ]; then
      verdict="**candidate regression**: $(printf '%s' "$new_in_pr" | tr '\n' ' ')"
      REGRESSION_COUNT=$((REGRESSION_COUNT + 1))
    else
      verdict="pre-existing defects only"
    fi
  fi
  ROWS="$ROWS| \`$name\` | $div_label | $base_fail | $pr_fail | $verdict |
"
done < "$CHANGED_LIST"

if [ -z "$ROWS" ]; then
  echo "Changed clips had no comparable transcript pairs; no defect delta."
  exit 0
fi

{
  printf '\n**Defect delta** (deterministic DemoDefects verdicts on each side, judged by this PR'\''s own analyzer -- a defect firing only on the PR side is a candidate regression; everything else is machine-cleared).\n\n'
  printf 'The **Diverges** column calibrates each row. Both runs are bit-identical up to the divergence tick, so every difference below necessarily developed after it -- the question is how much room it had to develop in. A row that diverges late, with only a few percent of the clip downstream, is reporting a short chaotic tail and is weak evidence about the change; one that diverges early was restructured wholesale, and its delta is far more likely to be real.\n\n'
  printf '| Demo | Diverges | Merge-base failing | PR failing | Delta |\n|---|---|---|---|---|\n%s' "$ROWS"
  if [ "$REGRESSION_COUNT" -gt 0 ]; then
    printf '\n**%d candidate regression clip(s)** -- review those rows first, weighting each by its Diverges column.\n' "$REGRESSION_COUNT"
  fi
} >> "$OUT_MD"

echo "Wrote $OUT_MD ($REGRESSION_COUNT candidate regressions)"
