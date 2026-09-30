#!/usr/bin/env bash
# Self-contained unit test for the demo state-transcript comment's size bound:
#
#   1. tools/ci/state-transcript-summary.sh renders a small transcript whole, as ONE
#      table (one header row, not one per tick), with a tick column on every row
#   2. a dense transcript (504 ticks, the per-tick sampling that once overflowed
#      GitHub's 65,536-character comment cap) is cut to the table byte budget: the
#      first and last rows survive, and one marker row names the omitted ticks
#   3. the budget is caller-configurable (4th argument): a budget of exactly the table's
#      size keeps every row, one byte less cuts it, a zero budget keeps only the marker,
#      and a non-integer is refused
#   4. tools/ci/upsert-pr-comment.sh refuses a body over 65,536 characters with a
#      message naming the size, before calling the API at all, and accepts a body of
#      exactly 65,536
#
# No network and no real `gh`: case 4 puts a stub `gh` on PATH that records every
# call. Needs `jq` on PATH (the summary script's own dependency); skips with a clear
# message rather than failing without it.
#
# Run by tools/check.sh's shell_tests check, alongside every other tools/lib/tests/test-*.sh.
#
# Usage: tools/lib/tests/test-transcript-comment-budget.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
SUMMARY="$REPO_ROOT/tools/ci/state-transcript-summary.sh"
UPSERT="$REPO_ROOT/tools/ci/upsert-pr-comment.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP test-transcript-comment-budget: jq not on PATH"
  exit 0
fi

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

assert_true() {
  local label="$1"
  shift
  if "$@"; then
    printf 'ok %s\n' "$label"
  else
    printf 'FAIL %s\n' "$label" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

# Write <n> state_<tick>.json snapshots, ticks 1..n, each holding <units> unit records
# shaped like DemoInputRecorder's (one far-tier unit without soldier_summary).
make_states() {
  local dir="$1" n="$2" units="$3" t u
  mkdir -p "$dir"
  for ((t = 1; t <= n; t++)); do
    {
      printf '{"tick": %d, "units": [' "$t"
      for ((u = 1; u <= units; u++)); do
        [ "$u" -gt 1 ] && printf ','
        if [ "$u" -eq "$units" ]; then
          printf '{"name": "Far %d", "team": 1, "state": "IDLE", "formation": "LINE", "order_mode": "HOLD", "morale": 100, "soldiers": 120, "tier": "FAR"}' "$u"
        else
          printf '{"name": "Spearmen %d", "team": 0, "state": "MARCHING", "formation": "NORMAL", "order_mode": "MOVE", "morale": 87.5, "soldiers": 140, "tier": "CLOSE", "soldier_summary": {"centroid": [1234.56, 789.01]}}' "$u"
        fi
      done
      printf ']}\n'
    } > "$(printf '%s/state_%05d.json' "$dir" "$t")"
  done
}

# Table rows are the lines that start with "| " followed by a digit (the tick column).
data_rows() { grep -cE '^\| [0-9]+ \|' "$1" || true; }
header_rows() { grep -c '^| tick | unit |' "$1" || true; }
marker_rows() { grep -c '^| \.\.\. |' "$1" || true; }
table_bytes() { grep -E '^\| ([0-9]+|\.\.\.) \|' "$1" | LC_ALL=C wc -c | tr -d ' '; }

# --- 1. small transcript renders whole, as one table ---
make_states "$WORK/small" 3 4
"$SUMMARY" "$WORK/small" "$WORK/small.json" "$WORK/small.md" >/dev/null
assert_eq "small: one header row" 1 "$(header_rows "$WORK/small.md")"
assert_eq "small: every row kept (3 ticks x 4 units)" 12 "$(data_rows "$WORK/small.md")"
assert_eq "small: no marker row" 0 "$(marker_rows "$WORK/small.md")"
assert_true "small: far-tier centroid renders as -" grep -q '^| 3 | Far 4 | 1 | IDLE | LINE | HOLD | 100 | 120 | FAR | - |$' "$WORK/small.md"
assert_true "small: close-tier centroid renders" grep -q '^| 1 | Spearmen 1 | 0 | MARCHING | NORMAL | MOVE | 87.5 | 140 | CLOSE | \[1234.56, 789.01\] |$' "$WORK/small.md"
assert_eq "small: merged JSON holds every tick" 3 "$(jq '.ticks | length' "$WORK/small.json")"

# --- 2. dense transcript is bounded to the default budget ---
make_states "$WORK/dense" 504 10
"$SUMMARY" "$WORK/dense" "$WORK/dense.json" "$WORK/dense.md" >/dev/null
DENSE_BYTES=$(table_bytes "$WORK/dense.md")
assert_true "dense: table within the 45000-byte default budget ($DENSE_BYTES)" test "$DENSE_BYTES" -le 45000
assert_true "dense: whole summary under the 65,536 comment cap" test "$(LC_ALL=C wc -c < "$WORK/dense.md")" -lt 65536
assert_eq "dense: one marker row" 1 "$(marker_rows "$WORK/dense.md")"
assert_true "dense: first row kept" grep -q '^| 1 | Spearmen 1 |' "$WORK/dense.md"
assert_true "dense: last row kept" grep -q '^| 504 | Far 10 |' "$WORK/dense.md"
KEPT=$(data_rows "$WORK/dense.md")
OMITTED=$(sed -nE 's/^\| \.\.\. \| \*([0-9]+) rows .*/\1/p' "$WORK/dense.md")
assert_eq "dense: kept + omitted rows = all 5040" 5040 "$((KEPT + OMITTED))"
FIRST_OMITTED=$(sed -nE 's/^\| \.\.\. \| \*[0-9]+ rows \(ticks ([0-9]+) to ([0-9]+)\).*/\1/p' "$WORK/dense.md")
LAST_KEPT_HEAD=$(grep -B1 -E '^\| \.\.\. \|' "$WORK/dense.md" | head -n1 | sed -nE 's/^\| ([0-9]+) \|.*/\1/p')
# The cut can fall mid-tick (10 rows per tick), so the omitted range may share its end
# ticks with the last head row and the first tail row; it must never reach past them.
LAST_OMITTED=$(sed -nE 's/^\| \.\.\. \| \*[0-9]+ rows \(ticks [0-9]+ to ([0-9]+)\).*/\1/p' "$WORK/dense.md")
FIRST_KEPT_TAIL=$(grep -A1 -E '^\| \.\.\. \|' "$WORK/dense.md" | tail -n1 | sed -nE 's/^\| ([0-9]+) \|.*/\1/p')
assert_true "dense: marker's first omitted tick is not before the last head row" test "$FIRST_OMITTED" -ge "$LAST_KEPT_HEAD"
assert_true "dense: marker's last omitted tick is not after the first tail row" test "$LAST_OMITTED" -le "$FIRST_KEPT_TAIL"
assert_true "dense: marker's range is ordered" test "$FIRST_OMITTED" -le "$LAST_OMITTED"
assert_eq "dense: merged JSON still holds every tick" 504 "$(jq '.ticks | length' "$WORK/dense.json")"

# --- 3. the budget is configurable, and validated ---
"$SUMMARY" "$WORK/dense" "$WORK/tight.json" "$WORK/tight.md" 5000 >/dev/null
TIGHT_BYTES=$(table_bytes "$WORK/tight.md")
assert_true "tight: table within a 5000-byte budget ($TIGHT_BYTES)" test "$TIGHT_BYTES" -le 5000
assert_true "tight: keeps fewer rows than the default" test "$(data_rows "$WORK/tight.md")" -lt "$KEPT"
# The fit test is `total <= budget`: a budget of exactly the table's size keeps every row,
# one byte less cuts it.
SMALL_BYTES=$(table_bytes "$WORK/small.md")
"$SUMMARY" "$WORK/small" "$WORK/exact.json" "$WORK/exact.md" "$SMALL_BYTES" >/dev/null
assert_eq "exact budget: every row kept" 12 "$(data_rows "$WORK/exact.md")"
assert_eq "exact budget: no marker row" 0 "$(marker_rows "$WORK/exact.md")"
"$SUMMARY" "$WORK/small" "$WORK/under.json" "$WORK/under.md" "$((SMALL_BYTES - 1))" >/dev/null
assert_eq "budget one byte short: marker row" 1 "$(marker_rows "$WORK/under.md")"
# A budget too small for any row keeps only the marker, which names every row.
"$SUMMARY" "$WORK/small" "$WORK/zero.json" "$WORK/zero.md" 0 >/dev/null
assert_eq "zero budget: no data rows" 0 "$(data_rows "$WORK/zero.md")"
assert_true "zero budget: marker names all 12 rows, ticks 1 to 3" grep -q '^| \.\.\. | \*12 rows (ticks 1 to 3) omitted' "$WORK/zero.md"
rc=0
"$SUMMARY" "$WORK/dense" "$WORK/bad.json" "$WORK/bad.md" 12k >/dev/null 2>&1 || rc=$?
assert_eq "bad budget: refused with exit 2" 2 "$rc"

# --- 4. upsert refuses an oversized body before calling the API ---
mkdir -p "$WORK/bin"
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "$*" >> "$GH_CALLS"
echo '[]'
STUB
chmod +x "$WORK/bin/gh"
export GH_CALLS="$WORK/gh-calls.txt"
: > "$GH_CALLS"
BIG_BODY="<!-- marker -->$(head -c 70000 /dev/zero | tr '\0' 'x')"
rc=0
PATH="$WORK/bin:$PATH" "$UPSERT" o/r 1 "<!-- marker -->" "$BIG_BODY" "state transcript comment" \
  > "$WORK/upsert.out" 2> "$WORK/upsert.err" || rc=$?
assert_eq "upsert oversized: exit 1" 1 "$rc"
assert_true "upsert oversized: message names the size" grep -q '70015 characters, over GitHub' "$WORK/upsert.err"
assert_eq "upsert oversized: gh never called" 0 "$(wc -l < "$GH_CALLS" | tr -d ' ')"
rc=0
PATH="$WORK/bin:$PATH" "$UPSERT" o/r 1 "<!-- marker -->" "<!-- marker --> small" \
  > "$WORK/upsert.out" 2> "$WORK/upsert.err" || rc=$?
assert_eq "upsert small: exit 0" 0 "$rc"
assert_true "upsert small: posted" grep -q 'Posted new comment' "$WORK/upsert.out"
# The limit itself is allowed; one character over is not. ASCII-only, so bytes and
# characters agree whatever the locale.
AT_LIMIT="<!-- marker -->$(head -c $((65536 - 15)) /dev/zero | tr '\0' 'x')"
rc=0
PATH="$WORK/bin:$PATH" "$UPSERT" o/r 1 "<!-- marker -->" "$AT_LIMIT" >/dev/null 2>&1 || rc=$?
assert_eq "upsert at exactly 65,536 chars: exit 0" 0 "$rc"
rc=0
PATH="$WORK/bin:$PATH" "$UPSERT" o/r 1 "<!-- marker -->" "${AT_LIMIT}x" >/dev/null 2>&1 || rc=$?
assert_eq "upsert at 65,537 chars: exit 1" 1 "$rc"

if [ "$FAILURES" -gt 0 ]; then
  echo "test-transcript-comment-budget: $FAILURES failure(s)" >&2
  exit 1
fi
echo "test-transcript-comment-budget: all passed"
