#!/usr/bin/env bash
# Self-contained unit test for tools/check-worktree-state.sh.
#
# Every case is a negative control for one verdict: the test first regresses a
# throwaway repository into the exact state that verdict is meant to catch, then
# asserts the detector reports that verdict AND the intended exit status. A
# detector that answered "ok" for everything would fail here, which is the point
# -- a clean run against a healthy repo proves nothing about whether the checks
# bite.
#
# No network and no Godot: a local repository stands in for the remote, so the
# clone, its origin/HEAD symref, and every measurement are real git operations
# against paths this test created.
#
# The fixture lives under one mktemp directory and is deliberately left in place
# at exit rather than torn down: its path is printed on the last line, a git
# worktree it registers has already been renamed aside by case 6, and the tree
# is the only evidence available for diagnosing a failure after the fact. It is
# ephemeral by construction -- mktemp puts it under TMPDIR.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DETECTOR="$REPO_ROOT/tools/check-worktree-state.sh"

if [ ! -f "$DETECTOR" ]; then
  printf 'FAIL: detector not found at %s\n' "$DETECTOR" >&2
  exit 1
fi

TMP="$(mktemp -d)"

FAILURES=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  FAILURES=$((FAILURES + 1))
}

pass() {
  printf 'ok: %s\n' "$1"
}

# Run the detector inside $WORK and capture both its JSON and its exit status.
# The assertions read --json rather than the table, so a formatting change to the
# human-readable output cannot silently break the test.
run_detector() {
  DETECTOR_JSON="$(cd "$WORK" && bash "$DETECTOR" --json "$@" 2>/dev/null)"
  DETECTOR_STATUS=$?
  return 0
}

assert_contains() {
  # assert_contains <needle> <description>
  case "$DETECTOR_JSON" in
    *"$1"*) pass "$2" ;;
    *) fail "$2 -- expected '$1' in: $DETECTOR_JSON" ;;
  esac
}

assert_absent() {
  case "$DETECTOR_JSON" in
    *"$1"*) fail "$2 -- did NOT expect '$1' in: $DETECTOR_JSON" ;;
    *) pass "$2" ;;
  esac
}

assert_status() {
  # assert_status <expected> <description>
  if [ "$DETECTOR_STATUS" -eq "$1" ]; then
    pass "$2"
  else
    fail "$2 -- expected exit $1, got $DETECTOR_STATUS"
  fi
}

g() { git -c user.email=test@example.com -c user.name=test -c commit.gpgsign=false "$@"; }

# ---------------------------------------------------------------------------
# Fixture: a local repository playing the role of the remote, plus a clone.
# ---------------------------------------------------------------------------
UPSTREAM="$TMP/upstream"
WORK="$TMP/work"

mkdir -p "$UPSTREAM"
if ! g init --quiet --initial-branch=main "$UPSTREAM" >/dev/null 2>&1; then
  # Older git without --initial-branch.
  g init --quiet "$UPSTREAM" >/dev/null 2>&1
  g -C "$UPSTREAM" symbolic-ref HEAD refs/heads/main
fi
for i in 1 2 3 4; do
  printf 'line %s\n' "$i" >> "$UPSTREAM/file.txt"
  g -C "$UPSTREAM" add file.txt
  g -C "$UPSTREAM" commit --quiet -m "commit $i"
done

g clone --quiet "$UPSTREAM" "$WORK" >/dev/null 2>&1
g -C "$WORK" remote set-head origin --auto >/dev/null 2>&1

# ---------------------------------------------------------------------------
# Case 1: clean and current -- nothing flagged, and the examined count is not 0.
# ---------------------------------------------------------------------------
run_detector
assert_status 0 "case 1: a clean, current checkout exits 0"
assert_contains '"flagged":0' "case 1: nothing is flagged"
assert_absent '"examined":0' "case 1: the examined count is non-zero (the detector actually ran)"

# ---------------------------------------------------------------------------
# Case 2: the default-branch checkout is behind its remote -> stale, exit 1.
# ---------------------------------------------------------------------------
g -C "$WORK" reset --hard --quiet HEAD~2
run_detector
assert_status 1 "case 2: a stale default branch exits 1"
assert_contains 'stale' "case 2: staleness is reported as stale"
assert_contains '"behind":2' "case 2: the behind count is measured, not guessed"

# The threshold is configurable, so a tolerance wider than the gap clears it.
DETECTOR_JSON="$(cd "$WORK" && SPARTA_WORKTREE_STALE_MAX=5 bash "$DETECTOR" --json 2>/dev/null)"
DETECTOR_STATUS=$?
assert_status 0 "case 2b: SPARTA_WORKTREE_STALE_MAX above the gap clears the verdict"

# ---------------------------------------------------------------------------
# Case 3: staged work in the default-branch checkout -> misplaced. This is the
# state the tracking issue described, which nothing previously surfaced.
# ---------------------------------------------------------------------------
printf 'staged but committed nowhere\n' > "$WORK/orphan.txt"
g -C "$WORK" add orphan.txt
run_detector
assert_status 1 "case 3: staged work on the default branch exits 1"
assert_contains 'misplaced' "case 3: default-branch dirt is reported as misplaced"
assert_contains '"staged":1' "case 3: the staged count is measured"

# ---------------------------------------------------------------------------
# Case 4: uncommitted work on a FEATURE branch is reported but not flagged,
# unless --strict. A live session always looks like this.
# ---------------------------------------------------------------------------
g -C "$WORK" reset --quiet
g -C "$WORK" checkout --quiet -B feature/wip origin/main
printf 'work in progress\n' > "$WORK/wip.txt"
g -C "$WORK" add wip.txt
run_detector
assert_status 0 "case 4: feature-branch dirt does not fail by default"
assert_contains 'dirty' "case 4: feature-branch dirt is still reported"
run_detector --strict
assert_status 1 "case 4b: --strict flags feature-branch dirt"

# ---------------------------------------------------------------------------
# Case 5: a commit no remote ref contains -> unpushed, the loss-bearing case.
# ---------------------------------------------------------------------------
g -C "$WORK" commit --quiet -m "local only"
run_detector
assert_status 1 "case 5: a commit on no remote exits 1"
assert_contains 'unpushed' "case 5: the commit is reported as unpushed"
assert_contains '"unpushed":1' "case 5: the unpushed count is measured"

# ---------------------------------------------------------------------------
# Case 6: a worktree whose directory is gone -> prunable. The directory is
# renamed out from under its administrative entry, which produces the same
# missing-path state the detector has to notice.
# ---------------------------------------------------------------------------
g -C "$WORK" worktree add --quiet --detach "$TMP/gone" >/dev/null 2>&1
mv "$TMP/gone" "$TMP/moved-aside"
run_detector
assert_status 1 "case 6: a missing worktree directory exits 1"
assert_contains 'prunable' "case 6: the vanished worktree is reported as prunable"

# ---------------------------------------------------------------------------
# Case 7: --warn-only never fails, however dirty the repo is.
# ---------------------------------------------------------------------------
run_detector --warn-only
assert_status 0 "case 7: --warn-only exits 0 over a flagged repo"
assert_absent '"flagged":0' "case 7: --warn-only still reports the flags"

if [ "$FAILURES" -gt 0 ]; then
  printf '\n%s assertion(s) failed; fixture kept at %s\n' "$FAILURES" "$TMP" >&2
  exit 1
fi

printf '\nall worktree-state assertions passed; fixture kept at %s\n' "$TMP"