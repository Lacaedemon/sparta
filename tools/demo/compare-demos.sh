#!/usr/bin/env bash
# tools/demo/compare-demos.sh -- compare demo state dumps and hash streams between two directories
# or between a base git commit and the current branch.
#
# Usage:
#   tools/demo/compare-demos.sh --dirs <dump-dir-1> <dump-dir-2>
#   tools/demo/compare-demos.sh <input-script> [base-ref] [ticks]
#
#   --dirs <dir1> <dir2>  Directly compare hash streams and state snapshots between two dirs.
#   <input-script>        Repo-relative or res:// path to a demos/inputs/*.json script.
#   [base-ref]            Base commit to compare against (default: merge-base with origin/main).
#   [ticks]               Comma-separated ticks to dump (default: 30,60,120,180,240).
#
# Environment:
#   GODOT_BIN             Godot 4.7 binary (default: godot).
#   SPARTA_DEMO_KEEP      Set to 1 to keep temporary dump directories on exit.
#   SPARTA_COMPARE_TIMEOUT Hard timeout in seconds (default 300).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="${PROJECT_ROOT:-$(cd "$SCRIPT_DIR/../.." && pwd)}"
GODOT_BIN="${GODOT_BIN:-godot}"
COMPARE_TIMEOUT="${SPARTA_COMPARE_TIMEOUT:-300}"

# shellcheck source=../lib/run-bounded.sh
. "$SCRIPT_DIR/../lib/run-bounded.sh"

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ] || [ "$#" -lt 1 ]; then
  sed -n '2,/^set /{/^set /d;s/^# \{0,1\}//;p}' "$0"
  exit 0
fi

if [ "$1" = "--dirs" ]; then
  if [ "$#" -lt 3 ]; then
    echo "ERROR: --dirs requires two directory arguments." >&2
    exit 2
  fi
  DIR1="$2"
  DIR2="$3"
  echo "Comparing demo hash streams between $DIR1 and $DIR2..."
  run_bounded "$COMPARE_TIMEOUT" "$GODOT_BIN" --headless --path "$PROJECT_ROOT" \
    -s tools/demo/analyze_transcript.gd -- "$DIR1" --compare-hashes "$DIR2"
  exit $?
fi

INPUT="$1"
BASE_ARG="${2:-}"
TICKS="${3:-30,60,120,180,240}"

resolve_base() {
  if [ -n "$BASE_ARG" ]; then
    git -C "$PROJECT_ROOT" rev-parse --verify "$BASE_ARG^{commit}" 2>/dev/null && return 0
  fi
  git -C "$PROJECT_ROOT" merge-base HEAD origin/main 2>/dev/null && return 0
  git -C "$PROJECT_ROOT" rev-parse --verify origin/main 2>/dev/null && return 0
  git -C "$PROJECT_ROOT" rev-parse --verify main 2>/dev/null && return 0
  return 1
}

BASE_SHA="$(resolve_base || true)"
if [ -z "$BASE_SHA" ]; then
  echo "ERROR: could not resolve a base ref to compare against." >&2
  exit 1
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/sparta_compare_XXXXXX")"
BEFORE_DIR="$WORK_DIR/before"
AFTER_DIR="$WORK_DIR/after"
BASE_TREE="$WORK_DIR/base_tree"
mkdir -p "$BEFORE_DIR" "$AFTER_DIR"

cleanup() {
  if [ "${SPARTA_DEMO_KEEP:-0}" = "1" ]; then
    echo "Kept comparison dumps in $WORK_DIR (SPARTA_DEMO_KEEP=1)."
    return
  fi
  if [ -d "$BASE_TREE" ]; then
    git -C "$PROJECT_ROOT" worktree remove --force "$BASE_TREE" >/dev/null 2>&1 || true
  fi
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

echo "== before: $(git -C "$PROJECT_ROOT" log --oneline -1 "$BASE_SHA")"
git -C "$PROJECT_ROOT" worktree add --detach --quiet "$BASE_TREE" "$BASE_SHA"
SPARTA_DEMO_STATE_DIR="$BEFORE_DIR" PROJECT_ROOT="$BASE_TREE" \
  "$BASE_TREE/tools/demo/dump-state.sh" "$INPUT" "$TICKS" "$BEFORE_DIR"

echo
echo "== after:  $(git -C "$PROJECT_ROOT" log --oneline -1 HEAD)"
SPARTA_DEMO_STATE_DIR="$AFTER_DIR" PROJECT_ROOT="$PROJECT_ROOT" \
  "$PROJECT_ROOT/tools/demo/dump-state.sh" "$INPUT" "$TICKS" "$AFTER_DIR"

echo
echo "== comparison result:"
rc=0
run_bounded "$COMPARE_TIMEOUT" "$GODOT_BIN" --headless --path "$PROJECT_ROOT" \
  -s tools/demo/analyze_transcript.gd -- "$BEFORE_DIR" --compare-hashes "$AFTER_DIR" || rc=$?

if [ "$rc" -eq 0 ]; then
  echo "Simulations match across common ticks."
else
  echo "Simulations diverged (see first divergent tick above)."
fi
exit "$rc"