#!/usr/bin/env bash
# Self-contained unit test for tools/lib/demo-defect-metrics.sh -- exercises the cases
# its functions' own header comments claim to handle, without needing a Godot binary
# or the real catalog:
#
# demo_clip_script_source():
#   1. type=input row: always returns its own scripted-input path.
#   2. type=replay row WITH a <source-without-.json>.defects.json sidecar present in
#      the tree: returns that sidecar's path.
#   3. type=replay row with no sidecar: returns nothing.
#   4. type=replay row whose SOURCE does not end in .json: returns nothing, even when
#      a sidecar-shaped file sits at SOURCE + ".defects.json" -- guards the ${SOURCE%.json}
#      no-op that would otherwise build a bogus path instead of reporting no sidecar.
#
# demo_sidecar_shape_ok():
#   accepted  -- {}, {"_comment":"x"} (an unrelated key), {"expect":[]},
#                {"defect_exemptions":{}}
#   rejected  -- [], "s", malformed JSON, and expect/defect_exemptions present with
#                the wrong type
# Needs `jq` on PATH (the same dependency check.sh's demo_defects check itself makes);
# skips with a clear message rather than failing when it is absent.
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

# A template is required for BSD mktemp (macOS) -- unlike GNU mktemp, it
# doesn't default to one when called as `mktemp -d` with no arguments.
TREE="$(mktemp -d "${TMPDIR:-/tmp}/demo-defect-metrics.XXXXXX")"
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

if ! command -v jq >/dev/null 2>&1; then
  echo "jq not found -- skipping demo_sidecar_shape_ok() assertions." >&2
else
  SHAPE_FILE="$TREE/shape-under-test.json"

  # assert_shape <label> <want: ok|reject> <json-body>
  assert_shape() {
    local label="$1" want="$2" body="$3" got="reject"
    printf '%s' "$body" > "$SHAPE_FILE"
    if demo_sidecar_shape_ok "$SHAPE_FILE"; then
      got="ok"
    fi
    assert_eq "$label" "$want" "$got"
  }

  # Accepted shapes.
  assert_shape "empty object is a valid (all-optional) sidecar" ok '{}'
  assert_shape "an unrelated top-level key is tolerated" ok '{"_comment":"x"}'
  assert_shape "expect as an (empty) array is valid" ok '{"expect":[]}'
  assert_shape "defect_exemptions as an (empty) object is valid" ok '{"defect_exemptions":{}}'

  # Rejected shapes.
  assert_shape "a top-level array is not a valid sidecar" reject '[]'
  assert_shape "a top-level string is not a valid sidecar" reject '"s"'
  assert_shape "expect as a string is invalid" reject '{"expect":"nope"}'
  assert_shape "expect as an object is invalid" reject '{"expect":{}}'
  assert_shape "defect_exemptions as an array is invalid" reject '{"defect_exemptions":[]}'
  assert_shape "malformed JSON is invalid" reject '{not json'
fi

if [ "$FAILURES" -gt 0 ]; then
  echo "$FAILURES assertion(s) failed" >&2
  exit 1
fi
echo "All tools/lib/demo-defect-metrics.sh assertions passed."
