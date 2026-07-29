#!/usr/bin/env bash
# Per-changed-clip defect delta: run the deterministic DemoDefects analyzer
# (tools/demo/analyze_transcript.gd) over BOTH sides' FULL transcripts of every clip the
# state diff flagged as changed, and emit a markdown fragment labeling any defect that
# fires on the PR side but not the merge-base as a CANDIDATE REGRESSION. This is the
# algorithmic core of the demo-diff classification: most changed clips are the PR's own
# intended effect, and a clean both-sides defect scan says so mechanically -- reviewer
# judgment narrows to the delta rows.
#
# Usage: website-demo-defect-delta.sh <baseline-dir> <pr-dir> <changed-list> <out-fragment> [pr-tree]
#
#   baseline-dir / pr-dir  The two transcript trees the state diff compared.
#   changed-list           One clip name per line (the diff script's .changed output).
#   out-fragment           Markdown fragment to write (empty file when nothing to report).
#   pr-tree                Project root whose analyzer runs (default: cwd). Always the PR
#                          side's tree, so both sides are judged by the same metrics.
#
# A side whose transcripts lack the FULL-dump fields (a merge-base predating them)
# reports "n/a" rather than failing -- absence of data is not a defect, and the
# comparison self-resolves once both sides carry the schema. Exit code is always 0:
# like the state diff itself, this is informational; the PR's OWN demo has its real
# gate in demo-video.yml.
set -euo pipefail

BASELINE_DIR="${1:?usage: website-demo-defect-delta.sh <baseline-dir> <pr-dir> <changed-list> <out-fragment> [pr-tree]}"
PR_DIR="${2:?usage: website-demo-defect-delta.sh <baseline-dir> <pr-dir> <changed-list> <out-fragment> [pr-tree]}"
CHANGED_LIST="${3:?usage: website-demo-defect-delta.sh <baseline-dir> <pr-dir> <changed-list> <out-fragment> [pr-tree]}"
OUT_MD="${4:?usage: website-demo-defect-delta.sh <baseline-dir> <pr-dir> <changed-list> <out-fragment> [pr-tree]}"
PR_TREE="${5:-$PWD}"
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

ROWS=""
REGRESSION_COUNT=0
while IFS= read -r name; do
  [ -n "$name" ] || continue
  [ -d "$BASELINE_DIR/$name" ] && [ -d "$PR_DIR/$name" ] || continue
  script_src="$(demo_clip_script_source "$name" "$PR_TREE")"
  base_fail="$(failing_metrics "$BASELINE_DIR/$name" "$script_src")"
  pr_fail="$(failing_metrics "$PR_DIR/$name" "$script_src")"
  verdict="no new defects"
  if [ "$pr_fail" = "n/a" ] || [ "$base_fail" = "n/a" ]; then
    verdict="n/a (a side lacks full-dump data)"
  elif [ "$pr_fail" != "clean" ]; then
    # A PR-side failing metric absent from the base side's list is new.
    new_metrics="$(comm -13 \
      <(printf '%s\n' "$base_fail" | tr ',' '\n' | sed 's/^ *//' | sort -u) \
      <(printf '%s\n' "$pr_fail" | tr ',' '\n' | sed 's/^ *//' | sort -u) | grep -v '^clean$' || true)"
    if [ -n "$new_metrics" ]; then
      verdict="**candidate regression**: $(printf '%s' "$new_metrics" | tr '\n' ' ')"
      REGRESSION_COUNT=$((REGRESSION_COUNT + 1))
    else
      verdict="pre-existing defects only"
    fi
  fi
  ROWS="$ROWS| \`$name\` | $base_fail | $pr_fail | $verdict |
"
done < "$CHANGED_LIST"

if [ -z "$ROWS" ]; then
  echo "Changed clips had no comparable transcript pairs; no defect delta."
  exit 0
fi

{
  printf '\n**Defect delta** (deterministic DemoDefects verdicts on each side, judged by this PR'\''s own analyzer -- a defect firing only on the PR side is a candidate regression; everything else is machine-cleared):\n\n'
  printf '| Demo | Merge-base failing | PR failing | Delta |\n|---|---|---|---|\n%s' "$ROWS"
  if [ "$REGRESSION_COUNT" -gt 0 ]; then
    printf '\n**%d candidate regression clip(s)** -- review those rows first.\n' "$REGRESSION_COUNT"
  fi
} >> "$OUT_MD"

echo "Wrote $OUT_MD ($REGRESSION_COUNT candidate regressions)"
