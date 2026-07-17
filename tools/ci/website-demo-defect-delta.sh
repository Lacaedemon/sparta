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

# The catalog maps clip names to their source scripts, whose declared `expect`
# assertions (input-type rows only) join the scan on both sides.
# shellcheck source=../../website/tools/demo-catalog.sh
. "$PR_TREE/website/tools/demo-catalog.sh"

expect_source() {
  local want="$1" spec NAME SOURCE FIXED_FPS MAX_FRAMES WIDTH TYPE
  for spec in "${DEMOS[@]}"; do
    IFS='|' read -r NAME SOURCE FIXED_FPS MAX_FRAMES WIDTH TYPE <<<"$spec"
    if [ "$NAME" = "$want" ] && [ "${TYPE:-replay}" = "input" ] \
        && jq -e '.expect | type == "array" and length > 0' "$PR_TREE/$SOURCE" >/dev/null 2>&1; then
      printf '%s' "$PR_TREE/$SOURCE"
      return 0
    fi
  done
  return 0
}

# Failing metrics for one transcript dir, as "metric(uidN), ..." | "clean" | "n/a".
# The analyzer prints a Godot banner before the JSON line, so keep only the JSON.
failing_metrics() {
  local dir="$1" expect_src="$2" out rc=0
  if [ -n "$expect_src" ]; then
    out="$("$GODOT_BIN" --headless --path "$PR_TREE" -s tools/demo/analyze_transcript.gd -- \
        "$dir" --json --expect "$expect_src" 2>/dev/null | grep -m1 '^{' || true)" || rc=$?
  else
    out="$("$GODOT_BIN" --headless --path "$PR_TREE" -s tools/demo/analyze_transcript.gd -- \
        "$dir" --json 2>/dev/null | grep -m1 '^{' || true)" || rc=$?
  fi
  if [ -z "$out" ]; then
    printf 'n/a'
    return 0
  fi
  printf '%s' "$out" | jq -r \
    '[.verdicts[] | select(.pass | not) | "\(.metric) (uid\(.uid))"] | if length == 0 then "clean" else join(", ") end' \
    2>/dev/null || printf 'n/a'
}

ROWS=""
REGRESSION_COUNT=0
while IFS= read -r name; do
  [ -n "$name" ] || continue
  [ -d "$BASELINE_DIR/$name" ] && [ -d "$PR_DIR/$name" ] || continue
  expect_src="$(expect_source "$name")"
  base_fail="$(failing_metrics "$BASELINE_DIR/$name" "$expect_src")"
  pr_fail="$(failing_metrics "$PR_DIR/$name" "$expect_src")"
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
