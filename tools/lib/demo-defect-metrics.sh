# tools/lib/demo-defect-metrics.sh -- shared helper: run the DemoDefects analyzer
# (tools/demo/analyze_transcript.gd) over ONE clip's transcript directory and reduce
# its verdicts to a compact, printable status.
#
# Sourced by the two consumers that judge website-catalog transcripts; not executable
# on its own:
#   - tools/ci/website-demo-defect-delta.sh   both sides of a PR's changed clips
#   - tools/ci/website-demo-defect-sweep.sh   every catalog clip, absolutely, on main
#
# Why this is shared rather than copied: both consumers need the identical reduction,
# including a subtle guard that is easy to get wrong and fails SILENTLY when it is --
# a transcript carrying only `expect:` verdicts has not had the physics metrics run at
# all, so it must report "n/a" rather than a confident "clean". Two hand-maintained
# copies of that rule would drift, and the drift would read as a passing scan.
#
# Environment:
#   GODOT_BIN   Godot 4.7 binary (default: godot).
#
# Requires `jq` on PATH; callers check for it and degrade themselves.

# demo_clip_script_source <clip-name> <tree>
#
# Absolute path to the clip's own scripted-input file for the catalog row named
# <clip-name>, or empty for a replay-type row (which has no input script, and so
# declares neither `expect` assertions nor `defect_exemptions`). The caller must have
# sourced the tree's own website/tools/demo-catalog.sh first, so DEMOS is in scope.
demo_clip_script_source() {
  local want="$1" tree="$2" spec NAME SOURCE FIXED_FPS MAX_FRAMES WIDTH TYPE
  for spec in "${DEMOS[@]}"; do
    IFS='|' read -r NAME SOURCE FIXED_FPS MAX_FRAMES WIDTH TYPE <<<"$spec"
    if [ "$NAME" = "$want" ] && [ "${TYPE:-replay}" = "input" ]; then
      printf '%s' "$tree/$SOURCE"
      return 0
    fi
  done
  return 0
}

# demo_defect_verdict <transcript-dir> <script-source-or-empty> <tree> [max-tick]
#
# Prints one line: "<analyzer-rc><TAB><status>", where <status> is
#   "metric (uidN), ..."  the failing metrics, when the clip has any
#   "clean"               every verdict passed
#   "n/a"                 the transcript cannot be judged (no snapshots, or a
#                          transcript predating the FULL-dump schema, so only
#                          expect-verdicts came back and no physics metric ran)
#
# <max-tick> bounds the scan to snapshots at or below that tick (empty = the whole
# transcript). The delta consumer passes the last tick before its two sides diverge, so
# both are judged over a window in which they are still the same battle; a window too
# narrow to hold a snapshot reduces to "n/a" via the analyzer's own rc 2.
#
# The rc is the analyzer's OWN exit status, captured through a temp file rather than a
# pipe: `godot ... | grep` would yield grep's status, not Godot's, which silently loses
# the rc 3 ("the clip's own expect/defect_exemptions block is malformed, so NOTHING was
# judged") that callers must gate on rather than treat as a clean scan.
# Per analyze_transcript.gd: 0 = all passed, 1 = a defect, 2 = unusable input,
# 3 = malformed declarations in the demo script itself.
demo_defect_verdict() {
  local dir="$1" script_src="$2" tree="$3" max_tick="${4:-}"
  local godot="${GODOT_BIN:-godot}"
  local raw status rc=0 tmp
  # Seeded with the two always-present arguments so the array is never empty, which
  # "${argv[@]}" would reject under `set -u` on bash older than 4.4.
  local -a argv=("$dir" --json)
  if [ -n "$script_src" ]; then
    argv+=(--script "$script_src")
  fi
  if [ -n "$max_tick" ]; then
    argv+=(--max-tick "$max_tick")
  fi
  tmp="$(mktemp)"
  "$godot" --headless --path "$tree" -s tools/demo/analyze_transcript.gd -- \
    "${argv[@]}" >"$tmp" 2>/dev/null || rc=$?
  # Godot prints its own banner before the JSON line, so keep only the JSON.
  raw="$(grep -m1 '^{' "$tmp" || true)"
  rm -f "$tmp"

  if [ -z "$raw" ]; then
    printf '%s\t%s' "$rc" "n/a"
    return 0
  fi
  status="$(printf '%s' "$raw" | jq -r '
    if ([.verdicts[] | select(.metric | startswith("expect:") | not)] | length) == 0
    then "n/a"
    else [.verdicts[] | select(.pass | not) | "\(.metric) (uid\(.uid))"]
      | if length == 0 then "clean" else join(", ") end
    end' 2>/dev/null || true)"
  [ -n "$status" ] || status="n/a"
  printf '%s\t%s' "$rc" "$status"
}
