#!/usr/bin/env bash
# Self-contained test for tools/ci/melee-outcome-delta.sh's plumbing (the statistics are
# GUT-tested in test/unit/test_outcome_stats.gd and test_melee_outcome_delta.gd):
#
#   1. a wrong argument count, a malformed count variable and an unknown subset each exit 2
#   2. a tree without tools/demo/DemoSeed.gd exits 2, since its runs could not be perturbed
#   3. a clip the catalog lacks exits 2 rather than comparing nothing
#   4. each selected clip runs K times per side with SPARTA_DEMO_SEED_RUN 1..K on the base
#      and 1+offset..K+offset on the head, and no unselected clip runs at all
#   5. the comparison's exit code passes through (1 = flagged) and the summary is written;
#      every run keeps its metrics.json, and its snapshots only under KEEP_DUMPS=1
#   6. a second run on the same out-dir reuses every finished dump
#   7. a run that writes no snapshots fails the whole delta with exit 2
#   8. --derive-clips runs every catalog clip on its own seed and prints only the clips
#      with enemy contact
#
# No Godot binary is needed: GODOT_BIN points at a stub that writes one fake snapshot per
# dump run (in contact for input clips, not for replay clips), logs the seed run it was
# given, and stands in for the comparison CLI. Case 8 needs jq and is skipped without it.
#
# Run by tools/check.sh's shell_tests check, alongside every other tools/lib/tests/test-*.sh.
#
# Usage: tools/lib/tests/test-melee-outcome-delta.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DELTA="$REPO_ROOT/tools/ci/melee-outcome-delta.sh"

FAILURES=0
assert_eq() {
  local label="$1" want="$2" got="$3"
  if [ "$want" != "$got" ]; then
    printf 'FAIL %s: want %q got %q\n' "$label" "$want" "$got" >&2
    FAILURES=$((FAILURES + 1))
  else
    printf 'ok %s\n' "$label"
  fi
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# The stub: a dump run (SPARTA_DEMO_STATE_DIR set) logs "<dir>|<seed run>" and writes a
# snapshot unless STUB_FAIL_RUN names its seed run; --extract writes a metrics.json whose
# first_contact says whether that snapshot was in contact; the comparison writes its
# markdown and exits STUB_COMPARE_RC; anything else (the import) does nothing.
cat > "$WORK/godot" <<'EOF'
#!/usr/bin/env bash
if [ -n "${SPARTA_DEMO_STATE_DIR:-}" ]; then
  echo "$SPARTA_DEMO_STATE_DIR|${SPARTA_DEMO_SEED_RUN:-}" >> "$STUB_LOG"
  [ "${SPARTA_DEMO_SEED_RUN:-}" = "${STUB_FAIL_RUN:-none}" ] && exit 0
  contact=false
  [ -n "${SPARTA_DEMO_INPUT:-}" ] && contact=true
  echo "{\"tick\": 5, \"units\": [{\"uid\": 0, \"in_enemy_contact\": $contact}]}" \
    > "$SPARTA_DEMO_STATE_DIR/state_00005.json"
  exit 0
fi
md="" extract=""
while [ "$#" -gt 0 ]; do
  if [ "$1" = "--markdown" ]; then md="$2"; fi
  if [ "$1" = "--extract" ]; then extract="$2"; fi
  shift
done
if [ -n "$extract" ]; then
  first=null
  grep -q '"in_enemy_contact": true' "$extract"/state_*.json && first=5
  echo "{\"travel\": [60], \"metrics\": {\"first_contact\": $first}}" > "$extract/metrics.json"
  exit 0
fi
if [ -n "$md" ]; then
  echo "### Melee outcome delta" > "$md"
  printf 'MELEE\tclip_a\tuid1_break\t3\t3\t1\t2\t1\t0.5\ttested\t-\n'
  printf 'MELEE-SUMMARY\tclips=1\ttested=1\tflagged=0\n'
  exit "${STUB_COMPARE_RC:-0}"
fi
exit 0
EOF
chmod +x "$WORK/godot"
export GODOT_BIN="$WORK/godot" STUB_LOG="$WORK/stub.log"

# make_tree <dir> [no-seed]: a fake project with a two-clip catalog and both sources.
make_tree() {
  local dir="$1"
  mkdir -p "$dir/website/tools" "$dir/tools/demo" "$dir/demos/inputs"
  cat > "$dir/website/tools/demo-catalog.sh" <<'EOF'
DEMOS=(
  "clip_a|demos/inputs/a.json|30|20|640|input"
  "clip_b|demos/b.json|30|20|640|replay"
)
EOF
  echo '{}' > "$dir/demos/inputs/a.json"
  echo '{}' > "$dir/demos/b.json"
  [ "${2:-}" = "no-seed" ] || touch "$dir/tools/demo/DemoSeed.gd"
}
make_tree "$WORK/base"
make_tree "$WORK/head"
make_tree "$WORK/old" no-seed

# rc_of <cmd...>: the command's exit status, its output discarded.
rc_of() {
  local rc=0
  "$@" >/dev/null 2>&1 || rc=$?
  echo "$rc"
}

# 1-3. Refusals.
assert_eq "wrong argument count" 2 "$(rc_of bash "$DELTA" "$WORK/base" "$WORK/head")"
assert_eq "malformed K" 2 "$(MELEE_DELTA_K=abc rc_of bash "$DELTA" "$WORK/base" "$WORK/head" "$WORK/o0")"
assert_eq "zero K" 2 "$(MELEE_DELTA_K=0 rc_of bash "$DELTA" "$WORK/base" "$WORK/head" "$WORK/o0")"
assert_eq "unknown subset" 2 "$(MELEE_DELTA_SUBSET=nope rc_of bash "$DELTA" "$WORK/base" "$WORK/head" "$WORK/o0")"
assert_eq "tree without DemoSeed" 2 "$(MELEE_DELTA_CLIPS=clip_a rc_of bash "$DELTA" "$WORK/old" "$WORK/head" "$WORK/o0")"
assert_eq "unknown clip" 2 "$(MELEE_DELTA_CLIPS=clip_z rc_of bash "$DELTA" "$WORK/base" "$WORK/head" "$WORK/o0")"

# 4-5. One selected clip, three runs per side, head shifted by three.
: > "$STUB_LOG"
rc="$(MELEE_DELTA_CLIPS=clip_a MELEE_DELTA_K=3 MELEE_DELTA_HEAD_RUN_OFFSET=3 STUB_COMPARE_RC=1 \
  rc_of bash "$DELTA" "$WORK/base" "$WORK/head" "$WORK/o1")"
assert_eq "flagged comparison passes its exit code through" 1 "$rc"
seeds() { grep "/dumps/$1/" "$STUB_LOG" | sed 's/.*|//' | sort -n | paste -sd, -; }
assert_eq "base plays seed runs 1..K" "1,2,3" "$(seeds base)"
assert_eq "head plays seed runs offset+1..offset+K" "4,5,6" "$(seeds head)"
assert_eq "unselected clip never runs" 0 "$(grep -c '/clip_b/' "$STUB_LOG" || true)"
assert_eq "summary written" "### Melee outcome delta" "$(head -1 "$WORK/o1/melee-delta.md")"
assert_eq "metric rows kept" 1 "$(grep -c '^MELEE	' "$WORK/o1/melee-delta.tsv")"
assert_eq "each run keeps its metrics" yes \
  "$([ -s "$WORK/o1/dumps/base/clip_a/seed1/metrics.json" ] && echo yes || echo no)"
assert_eq "snapshots are dropped by default" 0 \
  "$(find "$WORK/o1/dumps" -name 'state_*.json' | wc -l | tr -d ' ')"
MELEE_DELTA_CLIPS=clip_a MELEE_DELTA_K=1 MELEE_DELTA_KEEP_DUMPS=1 \
  bash "$DELTA" "$WORK/base" "$WORK/head" "$WORK/o4" >/dev/null 2>&1 || true
assert_eq "MELEE_DELTA_KEEP_DUMPS=1 keeps them" 2 \
  "$(find "$WORK/o4/dumps" -name 'state_*.json' | wc -l | tr -d ' ')"

# 6. Reuse.
: > "$STUB_LOG"
rc="$(MELEE_DELTA_CLIPS=clip_a MELEE_DELTA_K=3 MELEE_DELTA_HEAD_RUN_OFFSET=3 \
  rc_of bash "$DELTA" "$WORK/base" "$WORK/head" "$WORK/o1")"
assert_eq "re-run with nothing flagged exits 0" 0 "$rc"
assert_eq "re-run reuses every finished dump" 0 "$(grep -c 'dumps' "$STUB_LOG" || true)"

# 7. A run with no snapshots.
rc="$(MELEE_DELTA_CLIPS=clip_a MELEE_DELTA_K=2 STUB_FAIL_RUN=2 \
  rc_of bash "$DELTA" "$WORK/base" "$WORK/head" "$WORK/o2")"
assert_eq "a run without snapshots fails the delta" 2 "$rc"

# 8. Deriving the melee list.
if command -v jq >/dev/null 2>&1; then
  : > "$STUB_LOG"
  derived="$(bash "$DELTA" --derive-clips "$WORK/base" "$WORK/o3" 2>/dev/null | paste -sd, -)"
  assert_eq "derive lists only the clip in contact" "clip_a" "$derived"
  assert_eq "derive runs every catalog clip on its own seed" "0,0" \
    "$(sed 's/.*|//' "$STUB_LOG" | paste -sd, -)"
else
  echo "skip --derive-clips (jq not on PATH)"
fi

if [ "$FAILURES" -gt 0 ]; then
  echo "$FAILURES failure(s)" >&2
  exit 1
fi
echo "All melee-outcome-delta plumbing tests passed."
