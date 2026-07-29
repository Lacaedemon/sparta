#!/usr/bin/env bash
# ABSOLUTE defect sweep over the whole website demo catalog: run the deterministic
# DemoDefects analyzer (tools/demo/analyze_transcript.gd) over EVERY row of
# website/tools/demo-catalog.sh and emit a per-clip verdict table.
#
# Usage: website-demo-defect-sweep.sh <transcript-dir> <out-markdown> [tree]
#
#   transcript-dir  A full-catalog transcript tree (website/tools/dump-demo-states.sh
#                    output): one subdirectory per clip name.
#   out-markdown    Markdown report to write.
#   tree            Project root whose analyzer and catalog are used (default: cwd).
#
# Why this exists, when website-demo-defect-delta.sh already scans clips: every demo
# check in the repo is DIFF-scoped -- `check.sh demo_defects` looks only at demo scripts
# changed in the diff, demo-video.yml scans only the one PR-tailored clip, and
# website-demo-diff.yml runs the analyzer only over clips whose transcript CHANGED versus
# the merge-base. So a defect sitting identically on both sides of every diff, or one that
# predates the scan entirely, is invisible to all of them. The catalog is 70+ clips
# published on the live docs site, most untouched for weeks; this sweep is the only thing
# that ever asks "is this clip defective, full stop".
#
# Deliberately INFORMATIONAL: exit status is always 0 and the caller reports to a tracking
# issue rather than failing a check. We do not yet know how many existing clips fail, and
# turning a wall of pre-existing failures into a merge blocker would be unusable. Report
# first; decide about gating once the baseline is known.
set -euo pipefail

TRANSCRIPT_DIR="${1:?usage: website-demo-defect-sweep.sh <transcript-dir> <out-markdown> [tree]}"
OUT_MD="${2:?usage: website-demo-defect-sweep.sh <transcript-dir> <out-markdown> [tree]}"
TREE="${3:-$PWD}"
GODOT_BIN="${GODOT_BIN:-godot}"
export GODOT_BIN

command -v jq >/dev/null 2>&1 || { echo "error: jq not found on PATH" >&2; exit 1; }

# shellcheck source=../../website/tools/demo-catalog.sh
. "$TREE/website/tools/demo-catalog.sh"
# shellcheck source=../lib/demo-defect-metrics.sh
. "$TREE/tools/lib/demo-defect-metrics.sh"

TOTAL=0; CLEAN=0; DEFECT=0; MALFORMED=0; NA=0; MISSING=0
PROBLEM_ROWS=""
ALL_ROWS=""

for spec in "${DEMOS[@]}"; do
  IFS='|' read -r NAME SOURCE FIXED_FPS MAX_FRAMES WIDTH TYPE <<<"$spec"
  TYPE="${TYPE:-replay}"
  TOTAL=$((TOTAL + 1))

  if [ ! -d "$TRANSCRIPT_DIR/$NAME" ]; then
    # The dump skips a row whose source file is absent, and errors out on a row whose
    # dump produced nothing -- either way the clip went unjudged, which is a finding in
    # its own right rather than a pass.
    MISSING=$((MISSING + 1))
    verdict='**no transcript** (dump skipped or produced nothing)'
    PROBLEM_ROWS="$PROBLEM_ROWS| \`$NAME\` | \`$SOURCE\` | $verdict |
"
    ALL_ROWS="$ALL_ROWS| \`$NAME\` | $verdict |
"
    continue
  fi

  script_src="$(demo_clip_script_source "$NAME" "$TREE")"
  verdict_line="$(demo_defect_verdict "$TRANSCRIPT_DIR/$NAME" "$script_src" "$TREE")"
  rc="$(printf '%s' "$verdict_line" | cut -f1)"
  status="$(printf '%s' "$verdict_line" | cut -f2)"

  if [ "$rc" = "3" ]; then
    # The clip's own expect/defect_exemptions block is malformed, so the analyzer judged
    # NOTHING for it. That is strictly worse than a defect -- every metric is silently
    # disabled for this clip -- so it gets its own bucket rather than folding into n/a.
    MALFORMED=$((MALFORMED + 1))
    verdict='**malformed `expect` / `defect_exemptions`** -- nothing was judged'
  elif [ "$status" = "n/a" ]; then
    NA=$((NA + 1))
    verdict='n/a (no analyzable full-dump data)'
  elif [ "$status" = "clean" ]; then
    CLEAN=$((CLEAN + 1))
    verdict='clean'
  else
    DEFECT=$((DEFECT + 1))
    verdict="**defect**: $status"
  fi

  if [ "$verdict" != "clean" ]; then
    PROBLEM_ROWS="$PROBLEM_ROWS| \`$NAME\` | \`$SOURCE\` | $verdict |
"
  fi
  ALL_ROWS="$ALL_ROWS| \`$NAME\` | $verdict |
"
done

{
  printf '| bucket | clips |\n|---|---|\n'
  printf '| clean | %d |\n' "$CLEAN"
  printf '| **defect** | %d |\n' "$DEFECT"
  printf '| **malformed declarations** | %d |\n' "$MALFORMED"
  printf '| not analyzable | %d |\n' "$NA"
  printf '| no transcript | %d |\n' "$MISSING"
  printf '| **total** | %d |\n\n' "$TOTAL"

  if [ -n "$PROBLEM_ROWS" ]; then
    printf 'Clips needing attention:\n\n'
    printf '| clip | source | verdict |\n|---|---|---|\n%s\n' "$PROBLEM_ROWS"
  else
    printf 'Every catalog clip came back clean.\n\n'
  fi

  printf '<details>\n<summary>Full per-clip verdict table (%d clips)</summary>\n\n' "$TOTAL"
  printf '| clip | verdict |\n|---|---|\n%s\n</details>\n' "$ALL_ROWS"
} > "$OUT_MD"

printf 'SWEEP-SUMMARY\t%d\t%d\t%d\t%d\t%d\t%d\n' \
  "$TOTAL" "$CLEAN" "$DEFECT" "$MALFORMED" "$NA" "$MISSING"
echo "Wrote $OUT_MD ($DEFECT defect, $MALFORMED malformed, $NA n/a, $MISSING missing, of $TOTAL)"
