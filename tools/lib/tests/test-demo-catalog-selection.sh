#!/usr/bin/env bash
# Self-contained unit test for the catalog-narrowing contract shared by
# website/tools/dump-demo-states.sh and tools/ci/website-demo-defect-sweep.sh:
#
# demo_catalog_selected() (website/tools/demo-catalog.sh):
#   1. an empty selection selects every clip
#   2. a one-name selection selects that clip and no other
#   3. a comma-separated selection selects each named clip, whole-name only
#      (a name that is merely a prefix or substring of a selected one is NOT selected);
#      whitespace around a name is ignored
#
# demo_catalog_check_selection():
#   3b. a selection naming a clip the catalog lacks fails, naming the offender, and an
#       all-known (or empty) selection passes -- so a misspelt SPARTA_DUMP_CLIPS cannot
#       dump or judge nothing and exit 0
#
# website-demo-defect-sweep.sh under SPARTA_DUMP_CLIPS:
#   4. the sweep judges only the selected rows -- its SWEEP-SUMMARY total is the
#      selection's size and the unselected rows never appear as "no transcript"
#   5. the report leads with the dump's platform.txt line when the transcript tree
#      carries one, and has no such line when it does not
#
# Case 4 is the one that matters: a narrowed diagnostic dispatch of the sweep
# workflow dumps one clip, and the sweep judging that tree must agree on which rows
# exist, or the report is a wall of missing-transcript rows for clips nobody asked for.
#
# No Godot binary is needed: the sweep is run with GODOT_BIN pointing at a stub that
# prints a fixed clean analyzer verdict, and a fake tree with a throwaway catalog, so
# the real catalog and real transcripts are never touched. Needs `jq` on PATH (the
# sweep's own dependency); skips with a clear message rather than failing without it.
#
# Run by tools/check.sh's shell_tests check, alongside every other tools/lib/tests/test-*.sh.
#
# Usage: tools/lib/tests/test-demo-catalog-selection.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=../../../website/tools/demo-catalog.sh
. "$REPO_ROOT/website/tools/demo-catalog.sh"

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

# selected <clip> <selection> -> "yes" / "no", so the predicate's exit status reads
# as a value assert_eq can compare.
selected() {
  if demo_catalog_selected "$1" "$2"; then echo yes; else echo no; fi
}

assert_eq "empty selection selects every clip" yes "$(selected charge "")"
assert_eq "one-name selection selects that clip" yes "$(selected charge "charge")"
assert_eq "one-name selection excludes the others" no "$(selected clash "charge")"
assert_eq "comma list selects its first name" yes "$(selected charge "charge,support")"
assert_eq "comma list selects its last name" yes "$(selected support "charge,support")"
assert_eq "comma list excludes an unnamed clip" no "$(selected clash "charge,support")"
assert_eq "a prefix of a selected name is not selected" no "$(selected cycle_charge "cycle_charge_flee")"
assert_eq "a substring of a selected name is not selected" no "$(selected charge "cycle_charge")"
assert_eq "whitespace around a name is ignored" yes "$(selected support "charge, support ")"

# checked <selection> -> "ok" / "bad"; the check's stderr lands in CHECK_ERR.
CHECK_ERR="$(mktemp "${TMPDIR:-/tmp}/demo-catalog-selection-err.XXXXXX")"
checked() {
  if demo_catalog_check_selection "$1" 2>"$CHECK_ERR"; then echo ok; else echo bad; fi
}
assert_eq "empty selection passes the catalog check" ok "$(checked "")"
assert_eq "known names pass the catalog check" ok "$(checked "charge, support")"
assert_eq "a stray comma is not an unknown clip" ok "$(checked "charge,,support,")"
assert_eq "an unknown name fails the catalog check" bad "$(checked "charge,chrage")"
assert_eq "the check names the unknown clip" \
  "1" "$(grep -c 'not in website/tools/demo-catalog.sh: chrage$' "$CHECK_ERR" || true)"
rm -f "$CHECK_ERR"

if ! command -v jq >/dev/null 2>&1; then
  echo "skip: jq not on PATH; the sweep-narrowing cases need it" >&2
  exit "$FAILURES"
fi

# --- the sweep under SPARTA_DUMP_CLIPS -------------------------------------------

# A template is required for BSD mktemp (macOS) -- unlike GNU mktemp, it
# doesn't default to one when called as `mktemp -d` with no arguments.
TREE="$(mktemp -d "${TMPDIR:-/tmp}/demo-catalog-selection.XXXXXX")"
trap 'rm -rf "$TREE"' EXIT

# A fake project tree: the real sweep script and metrics helper, a three-row catalog,
# and a Godot stub whose analyzer output is one clean verdict.
mkdir -p "$TREE/tools/ci" "$TREE/tools/lib" "$TREE/website/tools" "$TREE/demos/inputs"
cp "$REPO_ROOT/tools/ci/website-demo-defect-sweep.sh" "$TREE/tools/ci/"
cp "$REPO_ROOT/tools/lib/demo-defect-metrics.sh" "$TREE/tools/lib/"
cat > "$TREE/website/tools/demo-catalog.sh" <<EOF
DEMOS=(
  "alpha|demos/inputs/alpha.json|30|100|640|input"
  "beta|demos/inputs/beta.json|30|100|640|input"
  "gamma|demos/inputs/gamma.json|30|100|640|input"
)
$(declare -f demo_catalog_selected)
$(declare -f demo_catalog_check_selection)
EOF
: > "$TREE/demos/inputs/alpha.json"
: > "$TREE/demos/inputs/beta.json"
: > "$TREE/demos/inputs/gamma.json"
cat > "$TREE/godot-stub" <<'EOF'
#!/usr/bin/env bash
printf 'Godot Engine (stub)\n{"verdicts":[{"metric":"overlap","uid":0,"pass":true}]}\n'
EOF
chmod +x "$TREE/godot-stub"

# Only beta has a transcript: with no narrowing, alpha and gamma read as missing.
TX="$TREE/transcripts"
mkdir -p "$TX/beta"
: > "$TX/beta/state_00008.json"

# summary_of <report-path> [SPARTA_DUMP_CLIPS]: run the sweep and print its
# SWEEP-SUMMARY fields as "total clean defect malformed na missing".
summary_of() {
  local out="$1" sel="${2:-}"
  SPARTA_DUMP_CLIPS="$sel" GODOT_BIN="$TREE/godot-stub" \
    bash "$TREE/tools/ci/website-demo-defect-sweep.sh" "$TX" "$out" "$TREE" \
    | grep '^SWEEP-SUMMARY' | cut -f2- | tr '\t' ' '
}

assert_eq "unnarrowed sweep judges every row and reports the undumped ones missing" \
  "3 1 0 0 0 2" "$(summary_of "$TREE/all.md")"
assert_eq "narrowed sweep judges only the selected row" \
  "1 1 0 0 0 0" "$(summary_of "$TREE/one.md" beta)"
assert_eq "narrowed report names no missing transcript" \
  "0" "$(grep -c 'no transcript\*\*' "$TREE/one.md" || true)"
assert_eq "a sweep narrowed to an unknown clip fails instead of judging nothing" \
  "" "$(summary_of "$TREE/none.md" delta 2>/dev/null || true)"

assert_eq "report without platform.txt has no platform line" \
  "0" "$(grep -c '^Transcripts dumped with:' "$TREE/one.md" || true)"
printf 'os=Linux\ngodot=4.7.stable.official\ntick_step=60\nclips=beta\n' > "$TX/platform.txt"
summary_of "$TREE/stamped.md" beta >/dev/null
assert_eq "report leads with the dump's platform line" \
  'Transcripts dumped with: `os=Linux godot=4.7.stable.official tick_step=60 clips=beta`' \
  "$(head -n1 "$TREE/stamped.md")"

if [ "$FAILURES" -ne 0 ]; then
  echo "$FAILURES failure(s)" >&2
  exit 1
fi
echo "all passed"
