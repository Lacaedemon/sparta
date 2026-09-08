#!/usr/bin/env bash
# Self-contained unit test for demo_clip_script_source() in
# tools/lib/demo-defect-metrics.sh -- exercises the cases the function's own header
# comment claims to handle without needing a Godot binary or the real catalog:
#   1. type=input row: always returns its own scripted-input path.
#   2. type=replay row WITH a <source-without-.json>.defects.json sidecar present in
#      the tree: returns that sidecar's path.
#   3. type=replay row with no sidecar: returns nothing.
#   4. type=replay row whose SOURCE does not end in .json: returns nothing, even when
#      a sidecar-shaped file sits at SOURCE + ".defects.json" -- guards the ${SOURCE%.json}
#      no-op that would otherwise build a bogus path instead of reporting no sidecar.
#
# Builds a fake tree in a temp dir with a throwaway DEMOS array, so a real catalog or
# real demo files are never touched.
#
# Run by tools/check.sh's shell_tests check, alongside every other tools/lib/tests/test-*.sh.
#
# Usage: tools/lib/tests/test-demo-defect-metrics.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../demo-defect-metrics.sh
. "$SCRIPT_DIR/../demo-defect-metrics.sh"

TREE="$(mktemp -d)"
trap 'rm -rf "$TREE"' EXIT

mkdir -p "$TREE/demos/inputs"
: > "$TREE/demos/inputs/scripted.json"
: > "$TREE/demos/with_sidecar.json"
: > "$TREE/demos/with_sidecar.defects.json"
: > "$TREE/demos/no_sidecar.json"
: > "$TREE/demos/no_ext_replay"
: > "$TREE/demos/no_ext_replay.defects.json"

DEMOS=(
  "scripted_clip|demos/inputs/scripted.json|30|100|640|input"
  "sidecar_clip|demos/with_sidecar.json|30|100|640|replay"
  "bare_clip|demos/no_sidecar.json|30|100|640|replay"
  "no_ext_clip|demos/no_ext_replay|30|100|640|replay"
)

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

assert_eq "input row returns its own script" \
  "$TREE/demos/inputs/scripted.json" \
  "$(demo_clip_script_source "scripted_clip" "$TREE")"

assert_eq "replay row WITH sidecar returns the sidecar" \
  "$TREE/demos/with_sidecar.defects.json" \
  "$(demo_clip_script_source "sidecar_clip" "$TREE")"

assert_eq "replay row with NO sidecar returns empty" \
  "" \
  "$(demo_clip_script_source "bare_clip" "$TREE")"

assert_eq "replay row whose SOURCE does not end in .json returns empty, even with a sidecar-shaped file present" \
  "" \
  "$(demo_clip_script_source "no_ext_clip" "$TREE")"

if [ "$FAILURES" -gt 0 ]; then
  echo "$FAILURES assertion(s) failed" >&2
  exit 1
fi
echo "All demo_clip_script_source() assertions passed."
