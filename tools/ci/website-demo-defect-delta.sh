#!/usr/bin/env bash
# Per-changed-clip defect delta: run the deterministic DemoDefects analyzer
# (tools/demo/analyze_transcript.gd) over BOTH sides' transcripts of every clip the
# state diff flagged as changed, and emit a markdown fragment labeling any defect that
# fires on the PR side but not the merge-base as a CANDIDATE REGRESSION. This is the
# algorithmic core of the demo-diff classification: most changed clips are the PR's own
# intended effect, and a clean both-sides defect scan says so mechanically -- reviewer
# judgment narrows to the delta rows.
#
# ATTRIBUTABLE WINDOW. Two runs of the same scripted clip are the same battle only until
# they diverge; once one side's soldier count differs, every later sample's verdict
# difference is chaotic amplification of a legitimate change rather than evidence about
# it -- and it is not even reproducible across platforms. So each clip is judged over the
# ticks BEFORE its first divergence, read from the hash-verdict file the workflow already
# computes for its pre-filter. Defects appearing only past that point are reported in
# their own section and never counted as candidate regressions. A clip with no known
# divergence tick (no hash verdict available) is scanned in full, exactly as before.
#
# The bound is the first STATE divergence, never a fixed tick cap: a defect that genuinely
# appears late in a clip but before any divergence is real, and stays inside the window.
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
#                          --compare-hash-trees). Supplies each clip's first divergent
#                          tick; without it every clip is judged over its full transcript.
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

# Failing metrics for one transcript dir, as "metric (uidN), ..." | "clean" | "n/a",
# optionally bounded to snapshots at or below tick $3.
# The delta deliberately ignores the analyzer's rc (field 1 of the shared verdict): a
# clip whose own declarations are malformed reduces to "n/a" here, which this script
# already reports as an unjudgeable side rather than a clean one.
failing_metrics() {
  demo_defect_verdict "$1" "$2" "$PR_TREE" "${3:-}" | cut -f2
}

# The first divergent tick the hash pre-filter recorded for a clip, or empty when it
# reported anything other than CHANGED (or no verdict file was passed at all).
divergence_tick() {
  [ -n "$HASH_VERDICT" ] && [ -f "$HASH_VERDICT" ] || return 0
  awk -F'\t' -v n="$1" '$1=="HASHCMP" && $2==n && $3=="CHANGED" {print $4; exit}' "$HASH_VERDICT"
}

# One metric per line, normalized for set comparison. "clean" and "n/a" are statuses,
# not metrics, so they never enter a difference.
metric_set() {
  printf '%s\n' "$1" | tr ',' '\n' | sed 's/^ *//; s/ *$//' \
    | grep -vxE 'clean|n/a|' | sort -u || true
}

# Metrics failing on the PR side ($2) that are absent from the merge-base side ($1).
new_metrics() {
  comm -13 <(metric_set "$1") <(metric_set "$2") || true
}

ROWS=""
TAIL_ROWS=""
REGRESSION_COUNT=0
while IFS= read -r name; do
  [ -n "$name" ] || continue
  [ -d "$BASELINE_DIR/$name" ] && [ -d "$PR_DIR/$name" ] || continue
  script_src="$(demo_clip_script_source "$name" "$PR_TREE")"

  # Judge the window in which both sides are still the same battle: everything strictly
  # before the first divergent tick. No known divergence -> judge the whole transcript.
  div_tick="$(divergence_tick "$name")"
  window_max=""
  window_label="full clip"
  if [ -n "$div_tick" ] && [ "$div_tick" -gt 0 ] 2>/dev/null; then
    window_max=$((div_tick - 1))
    window_label="ticks <= $window_max"
  fi

  base_fail="$(failing_metrics "$BASELINE_DIR/$name" "$script_src" "$window_max")"
  pr_fail="$(failing_metrics "$PR_DIR/$name" "$script_src" "$window_max")"

  new_in_window=""
  verdict="no new defects"
  if [ "$pr_fail" = "n/a" ] || [ "$base_fail" = "n/a" ]; then
    verdict="n/a (a side lacks full-dump data, or the window holds no snapshot)"
  elif [ "$pr_fail" != "clean" ]; then
    new_in_window="$(new_metrics "$base_fail" "$pr_fail")"
    if [ -n "$new_in_window" ]; then
      verdict="**candidate regression**: $(printf '%s' "$new_in_window" | tr '\n' ' ')"
      REGRESSION_COUNT=$((REGRESSION_COUNT + 1))
    else
      verdict="pre-existing defects only"
    fi
  fi
  ROWS="$ROWS| \`$name\` | $window_label | $base_fail | $pr_fail | $verdict |
"

  # Post-divergence tail: what a full-range scan would ALSO have called new. Reported so
  # nothing is hidden, but kept out of the candidate-regression count -- past the
  # divergence the two sides are no longer comparable. Only worth computing when the
  # window actually bounded something.
  if [ -n "$window_max" ]; then
    base_full="$(failing_metrics "$BASELINE_DIR/$name" "$script_src")"
    pr_full="$(failing_metrics "$PR_DIR/$name" "$script_src")"
    if [ "$pr_full" != "n/a" ] && [ "$base_full" != "n/a" ]; then
      new_full="$(new_metrics "$base_full" "$pr_full")"
      tail_only="$(comm -13 \
        <(printf '%s\n' "$new_in_window" | sed '/^$/d' | sort -u) \
        <(printf '%s\n' "$new_full" | sed '/^$/d' | sort -u) || true)"
      if [ -n "$tail_only" ]; then
        TAIL_ROWS="$TAIL_ROWS| \`$name\` | after tick $div_tick | $(printf '%s' "$tail_only" | tr '\n' ' ') |
"
      fi
    fi
  fi
done < "$CHANGED_LIST"

if [ -z "$ROWS" ]; then
  echo "Changed clips had no comparable transcript pairs; no defect delta."
  exit 0
fi

{
  printf '\n**Defect delta** (deterministic DemoDefects verdicts on each side, judged by this PR'\''s own analyzer -- a defect firing only on the PR side is a candidate regression; everything else is machine-cleared).\n\n'
  printf 'Each clip is judged over its **attributable window** -- everything up to one tick before the first divergence reported above, i.e. the range in which both sides are still the same battle. Past that point the sides hold different soldier counts, so a verdict difference is chaotic amplification of the change rather than evidence about it.\n\n'
  printf '| Demo | Attributable window | Merge-base failing | PR failing | Delta |\n|---|---|---|---|---|\n%s' "$ROWS"
  if [ "$REGRESSION_COUNT" -gt 0 ]; then
    printf '\n**%d candidate regression clip(s)** -- review those rows first.\n' "$REGRESSION_COUNT"
  fi
  if [ -n "$TAIL_ROWS" ]; then
    printf '\n<details>\n<summary>Post-divergence differences (not attributable to this PR)</summary>\n\n'
    printf 'These metrics differ only once the two runs have already diverged, so they are a downstream consequence of the change, not evidence about it -- and they do not reproduce across platforms. Listed for completeness; occasionally worth an eyeball.\n\n'
    printf '| Demo | Window | Metrics failing only past divergence |\n|---|---|---|\n%s' "$TAIL_ROWS"
    printf '\n</details>\n'
  fi
} >> "$OUT_MD"

scope="full transcripts (no hash verdict supplied)"
[ -n "$HASH_VERDICT" ] && [ -f "$HASH_VERDICT" ] && scope="attributable windows"
echo "Wrote $OUT_MD ($REGRESSION_COUNT candidate regressions over $scope)"
