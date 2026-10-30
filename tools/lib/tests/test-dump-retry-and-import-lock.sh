#!/usr/bin/env bash
# Self-contained unit test for the parallel-load guards behind
# website/tools/dump-demo-states.sh:
#
# run_bounded_retry() (tools/lib/run-bounded.sh):
#   1. a command that times out once and then finishes succeeds on attempt 2, runs its
#      prepare hook before each attempt, and logs the retry
#   2. a command that times out on every attempt fails with the timeout's status after
#      exactly N attempts and says so
#   3. a command that fails WITHOUT timing out is not retried -- a deterministic failure
#      would only fail again, and retrying it would hide nothing but cost time
#   3b. a non-numeric or zero attempt count is refused, not treated as "never run"
#   3c. a failing prepare hook stops the loop before the attempt runs
#
# godot_import_once() (tools/lib/godot-import-lock.sh):
#   4. the first call imports and stamps; a second call with nothing changed skips the
#      import -- a warm cache is not rewritten at all
#   5. a source file newer than the stamp, a deleted file, or a different Godot binary or
#      version each force a fresh import; a write under a .gdignore'd or hidden
#      directory (where the dumps land) does not; a source edited WHILE the import runs
#      forces the next one; an empty stamp content (unknown version) always imports
#   6. several calls started at once (on a stub that writes no sidecars) run one
#      import, and never two at the same
#      time -- also when they all start against a stale lock they race to break
#   7. a lock left by a dead holder, or with no holder PID and over a minute old, is
#      broken; a fresh PID-less one is not; a breaker that arrives after another caller
#      already broke and retook the lock leaves it alone; an abandoned .break lock fails
#      loudly and is not cleared; one held by a live holder is waited for and then
#      refused loudly when the wait runs out
#   8. an import killed by the timeout fails and leaves no stamp, so the next run
#      imports; any other non-zero status (a signal death included) warns with the
#      log's tail, writes no stamp, and does not fail
#   8b. a .gdignore at the project root does not blind the freshness scan
#
# website/tools/dump-demo-states.sh end to end, with a stub Godot:
#   9. a dump whose first attempt hangs (after writing part of its hash stream) is
#      retried, and the retried transcript is byte-identical to a clean run's
#   10. with SPARTA_DUMP_ATTEMPTS=1 the same hang fails the run, naming the timeout
#   11. with CI set (and no SPARTA_DUMP_ATTEMPTS) the default is one attempt
#   12. a clip-dir wipe that fails twice is retried; one that fails three times fails
#       the run, naming the dir
#
# No Godot binary is needed: every Godot call goes to a stub. Needs coreutils `timeout`
# (as run_bounded does) and a `touch -d` that reads relative dates (GNU touch, as in
# Git Bash and Ubuntu CI); skips with a clear message without either.
#
# Run by tools/check.sh's shell_tests check, alongside every other tools/lib/tests/test-*.sh.
#
# Usage: tools/lib/tests/test-dump-retry-and-import-lock.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
# shellcheck source=../run-bounded.sh
. "$REPO_ROOT/tools/lib/run-bounded.sh"
# shellcheck source=../godot-import-lock.sh
. "$REPO_ROOT/tools/lib/godot-import-lock.sh"

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

if ! command -v timeout >/dev/null 2>&1 && ! command -v gtimeout >/dev/null 2>&1; then
  echo "skip: coreutils timeout not on PATH; the retry and lock cases need it" >&2
  exit 0
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/dump-retry-lock.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT

if ! touch -d '2 minutes ago' "$TMP/probe" 2>/dev/null; then
  echo "skip: this touch cannot set a relative date (BSD touch?); the freshness cases need it" >&2
  exit 0
fi

# --- run_bounded_retry ------------------------------------------------------------

# hang_first <counter-file>: hangs on its first call (until killed), exits 0 after.
cat > "$TMP/hang-first" <<'EOF'
#!/usr/bin/env bash
n=$(( $(cat "$1" 2>/dev/null || echo 0) + 1 ))
echo "$n" > "$1"
if [ "$n" -eq 1 ]; then exec sleep 60; fi
exit 0
EOF
chmod +x "$TMP/hang-first"

PREPS="$TMP/preps"
count_prep() { echo x >> "$PREPS"; }

rc=0
run_bounded_retry 3 1 "case-1" count_prep "$TMP/hang-first" "$TMP/c1" 2>"$TMP/c1.err" || rc=$?
assert_eq "a once-hung command succeeds on a retry" 0 "$rc"
assert_eq "it ran twice" 2 "$(cat "$TMP/c1")"
assert_eq "the prepare hook ran before each attempt" 2 "$(wc -l < "$PREPS" | tr -d ' ')"
assert_eq "the retry is logged" 1 "$(grep -c 'attempt 1/3 timed out after 1s' "$TMP/c1.err" || true)"

cat > "$TMP/always-hang" <<'EOF'
#!/usr/bin/env bash
echo x >> "$1"
exec sleep 60
EOF
chmod +x "$TMP/always-hang"
rc=0
run_bounded_retry 2 1 "case-2" "" "$TMP/always-hang" "$TMP/c2" 2>"$TMP/c2.err" || rc=$?
assert_eq "an always-hung command fails with the timeout status" yes \
  "$(run_bounded_timed_out "$rc" && echo yes || echo no)"
assert_eq "it ran exactly the attempt budget" 2 "$(wc -l < "$TMP/c2" | tr -d ' ')"
assert_eq "the give-up is logged" 1 "$(grep -c 'timed out on all 2 attempts' "$TMP/c2.err" || true)"

cat > "$TMP/fail-3" <<'EOF'
#!/usr/bin/env bash
echo x >> "$1"
exit 3
EOF
chmod +x "$TMP/fail-3"
rc=0
run_bounded_retry 3 5 "case-3" "" "$TMP/fail-3" "$TMP/c3" 2>/dev/null || rc=$?
assert_eq "a non-timeout failure keeps its own status" 3 "$rc"
assert_eq "a non-timeout failure is not retried" 1 "$(wc -l < "$TMP/c3" | tr -d ' ')"

rc=0
run_bounded_retry 0 5 "case-3b" "" true 2>"$TMP/c3b.err" || rc=$?
assert_eq "a zero attempt count is refused" 2 "$rc"
rc=0
run_bounded_retry x 5 "case-3b" "" true 2>/dev/null || rc=$?
assert_eq "a non-numeric attempt count is refused" 2 "$rc"

failing_prep() { return 1; }
rm -f "$TMP/c3c"
rc=0
run_bounded_retry 3 5 "case-3c" failing_prep "$TMP/fail-3" "$TMP/c3c" 2>"$TMP/c3c.err" || rc=$?
assert_eq "a failing prepare hook fails the call" 1 "$rc"
assert_eq "a failing prepare hook stops the attempt from running" no \
  "$([ -e "$TMP/c3c" ] && echo yes || echo no)"
assert_eq "the prepare failure is logged" 1 "$(grep -c 'prepare step failed before attempt 1' "$TMP/c3c.err" || true)"

# --- godot_import_once ------------------------------------------------------------

# A stub Godot for --import: logs each import, and fails the test if two overlap.
cat > "$TMP/godot-import-stub" <<'EOF'
#!/usr/bin/env bash
log="$STUB_LOG"
if ! mkdir "$log.busy" 2>/dev/null; then echo overlap >> "$log"; fi
echo import >> "$log"
# Godot's own output, which godot_import_once sends to .godot/sparta-import.log.
echo "stub import output"
sleep "${STUB_SLEEP:-0}"
# STUB_EDIT_DURING names a file to edit mid-import (an edit racing the import).
if [ -n "${STUB_EDIT_DURING:-}" ]; then echo '# mid-import edit' >> "$STUB_EDIT_DURING"; fi
rmdir "$log.busy" 2>/dev/null || true
exit "${STUB_EXIT:-0}"
EOF
chmod +x "$TMP/godot-import-stub"
export STUB_LOG="$TMP/imports.log"

PROJ="$TMP/proj"
mkdir -p "$PROJ/scripts"
echo 'extends Node' > "$PROJ/scripts/a.gd"
echo 'extends Node' > "$PROJ/scripts/b.gd"
# grep -c prints 0 itself (and exits 1) on a log with no match; only a missing log needs
# the fallback.
imports() {
  if [ -f "$STUB_LOG" ]; then grep -c '^import$' "$STUB_LOG" || true; else echo 0; fi
}

godot_import_once 30 "$TMP/godot-import-stub" "$PROJ" "stub|v1" 2>/dev/null
assert_eq "the first call imports" 1 "$(imports)"
assert_eq "the first call writes the stamp" "stub|v1" "$(cat "$(godot_import_stamp_path "$PROJ")")"
godot_import_once 30 "$TMP/godot-import-stub" "$PROJ" "stub|v1" 2>"$TMP/skip.err"
assert_eq "an unchanged project is not re-imported" 1 "$(imports)"
assert_eq "the skip is reported" 1 "$(grep -c 'skipping --import' "$TMP/skip.err" || true)"

# mtimes have one-second resolution on some filesystems: age the stamp instead of sleeping.
age_stamp() { touch -d '2 minutes ago' "$(godot_import_stamp_path "$PROJ")"; }
age_stamp
echo '# edit' >> "$PROJ/scripts/a.gd"
godot_import_once 30 "$TMP/godot-import-stub" "$PROJ" "stub|v1" 2>/dev/null
assert_eq "an edited source forces an import" 2 "$(imports)"
age_stamp
touch -d '10 minutes ago' "$PROJ/scripts/a.gd" "$PROJ/scripts/b.gd"
rm "$PROJ/scripts/b.gd"
godot_import_once 30 "$TMP/godot-import-stub" "$PROJ" "stub|v1" 2>/dev/null
assert_eq "a deleted source forces an import" 3 "$(imports)"
godot_import_once 30 "$TMP/godot-import-stub" "$PROJ" "stub|v2" 2>/dev/null
assert_eq "a different Godot version forces an import" 4 "$(imports)"

# Writes Godot's own scan never sees -- a .gdignore'd directory (where the dumps land by
# default) and a hidden one -- must not force an import, or every dump would re-import.
mkdir -p "$PROJ/website/out" "$PROJ/.claude"
: > "$PROJ/website/.gdignore"
godot_import_once 30 "$TMP/godot-import-stub" "$PROJ" "stub|v2" 2>/dev/null
assert_eq "creating a .gdignore'd dir forces one import" 5 "$(imports)"
# Age the whole tree, then put the stamp after it, so only the writes below are new.
find "$PROJ" -exec touch -d '10 minutes ago' {} +
touch -d '5 minutes ago' "$(godot_import_stamp_path "$PROJ")"
echo '{}' > "$PROJ/website/out/state_00008.json"
echo x > "$PROJ/.claude/note"
godot_import_once 30 "$TMP/godot-import-stub" "$PROJ" "stub|v2" 2>/dev/null
assert_eq "writes under .gdignore'd and hidden dirs do not force an import" 5 "$(imports)"

# A source edited while the import runs is newer than the stamp (which predates the
# import), so the next call imports again rather than trusting a cache built before it.
find "$PROJ" -exec touch -d '10 minutes ago' {} +
STUB_SLEEP=1 STUB_EDIT_DURING="$PROJ/scripts/a.gd" godot_import_once 30 "$TMP/godot-import-stub" "$PROJ" "stub|v3" 2>/dev/null
assert_eq "an import runs for the new version" 6 "$(imports)"
godot_import_once 30 "$TMP/godot-import-stub" "$PROJ" "stub|v3" 2>/dev/null
assert_eq "a source edited during the import forces the next import" 7 "$(imports)"

# An unknown Godot version (empty stamp content) never matches, even itself.
godot_import_once 30 "$TMP/godot-import-stub" "$PROJ" "" 2>/dev/null
godot_import_once 30 "$TMP/godot-import-stub" "$PROJ" "" 2>/dev/null
assert_eq "an empty stamp content always imports" 9 "$(imports)"

# A .gdignore at the project root must not prune the scan at its start node, or every
# check would say "nothing changed". Its own project, stamped by hand, so the import
# count above is untouched.
ROOTG="$TMP/rootg"
mkdir -p "$ROOTG/scripts" "$ROOTG/.godot"
echo 'extends Node' > "$ROOTG/scripts/a.gd"
: > "$ROOTG/.gdignore"
printf '%s' "stub|v1" > "$(godot_import_stamp_path "$ROOTG")"
find "$ROOTG" -exec touch -d '10 minutes ago' {} +
touch -d '5 minutes ago' "$(godot_import_stamp_path "$ROOTG")"
assert_eq "an untouched project with a root .gdignore is current" yes \
  "$(godot_import_is_current "$ROOTG" "stub|v1" && echo yes || echo no)"
echo '# edit' >> "$ROOTG/scripts/a.gd"
assert_eq "an edit under a root .gdignore is still seen" no \
  "$(godot_import_is_current "$ROOTG" "stub|v1" && echo yes || echo no)"

# Concurrent callers on a cold project: one import, never two at once.
rm -rf "$PROJ/.godot" "$STUB_LOG"
pids=()
for _ in 1 2 3 4 5; do
  STUB_SLEEP=2 godot_import_once 30 "$TMP/godot-import-stub" "$PROJ" "stub|v1" 2>/dev/null &
  pids+=($!)
done
failed_callers=0
for p in "${pids[@]}"; do wait "$p" || failed_callers=$((failed_callers + 1)); done
assert_eq "five concurrent callers all succeed" 0 "$failed_callers"
assert_eq "five concurrent callers run one import" 1 "$(imports)"
assert_eq "no two imports overlapped" 0 "$(grep -c '^overlap$' "$STUB_LOG" || true)"
assert_eq "the lock is released afterwards" no "$([ -e "$PROJ/.godot/sparta-import.lock" ] && echo yes || echo no)"

# A PID from a finished background job is dead.
sh -c 'exit 0' &
dead=$!
wait "$dead"

# Five callers that all find a stale lock race to break it: still exactly one import,
# never two at once, and the stale lock is broken exactly once.
rm -rf "$PROJ/.godot" "$STUB_LOG"
mkdir -p "$PROJ/.godot/sparta-import.lock"
echo "$dead" > "$PROJ/.godot/sparta-import.lock/pid"
pids=()
for i in 1 2 3 4 5; do
  STUB_SLEEP=2 godot_import_once 30 "$TMP/godot-import-stub" "$PROJ" "stub|v1" 2>"$TMP/race-$i.err" &
  pids+=($!)
done
failed_callers=0
for p in "${pids[@]}"; do wait "$p" || failed_callers=$((failed_callers + 1)); done
assert_eq "callers racing to break a stale lock all succeed" 0 "$failed_callers"
assert_eq "callers racing to break a stale lock run one import" 1 "$(imports)"
assert_eq "no two imports overlapped after the race" 0 "$(grep -c '^overlap$' "$STUB_LOG" || true)"
assert_eq "the stale lock was broken once" 1 "$(cat "$TMP"/race-*.err | grep -c 'broke stale lock' || true)"
assert_eq "no stale-lock leftovers remain" 0 \
  "$(find "$PROJ/.godot" -maxdepth 1 -name 'sparta-import.lock*' | wc -l | tr -d ' ')"

# A dead holder's lock is broken.
LOCK="$TMP/lock.d"
mkdir "$LOCK"
echo "$dead" > "$LOCK/pid"
rc=0
godot_lock_acquire "$LOCK" 5 2>"$TMP/stale.err" || rc=$?
assert_eq "a dead holder's lock is taken over" 0 "$rc"
assert_eq "the takeover is reported" 1 "$(grep -c 'broke stale lock' "$TMP/stale.err" || true)"
godot_lock_release "$LOCK"

# The late breaker: it read the dead PID, but before it got to break the lock another
# caller broke it and took it. Forced deterministically by a staleness check that swaps
# in a live holder's lock (this shell's PID) right after the read. The breaker's re-read
# must see the new holder and leave the lock alone -- not delete it and take the lock
# alongside its holder.
eval "orig_$(declare -f godot_lock_is_stale)"
swapped=0
godot_lock_is_stale() {
  if [ "$swapped" -eq 0 ]; then
    swapped=1
    rm -rf "$1"; mkdir "$1"; echo "$$" > "$1/pid"
    return 0
  fi
  orig_godot_lock_is_stale "$@"
}
mkdir "$LOCK"
echo "$dead" > "$LOCK/pid"
rc=0
godot_lock_acquire "$LOCK" 1 2>/dev/null || rc=$?
assert_eq "a late breaker does not take the lock" 1 "$rc"
assert_eq "the new holder's lock is left intact" "$$" "$(cat "$LOCK/pid" 2>/dev/null || echo missing)"
eval "$(declare -f orig_godot_lock_is_stale | sed '1s/^orig_//')"
godot_lock_release "$LOCK"

# A breaker killed mid-break leaves <lock>.break behind. It is never cleared
# automatically (two waiters could both clear it and break concurrently): once over a
# minute old it fails the caller loudly, naming the directory, and is left in place.
mkdir "$LOCK" "$LOCK.break"
echo "$dead" > "$LOCK/pid"
touch -d '2 minutes ago' "$LOCK.break"
rc=0
godot_lock_acquire "$LOCK" 3 2>"$TMP/breaker.err" || rc=$?
assert_eq "an abandoned breaker lock fails the caller" 1 "$rc"
assert_eq "the failure names the .break dir to remove" 1 \
  "$(grep -c "::error::.*$LOCK.break is over a minute old" "$TMP/breaker.err" || true)"
assert_eq "the abandoned breaker lock is left in place" yes "$([ -d "$LOCK.break" ] && echo yes || echo no)"
assert_eq "the stale lock under it is not broken" "$dead" "$(cat "$LOCK/pid" 2>/dev/null || echo missing)"
rm -rf "$LOCK.break"
godot_lock_release "$LOCK"

# A lock with no PID: a fresh one may be a holder about to write its PID, so it is
# waited for; one over a minute old is a holder that died first, so it is broken.
mkdir "$LOCK"
rc=0
godot_lock_acquire "$LOCK" 1 2>/dev/null || rc=$?
assert_eq "a fresh PID-less lock is not broken" 1 "$rc"
touch -d '2 minutes ago' "$LOCK"
rc=0
godot_lock_acquire "$LOCK" 1 2>"$TMP/nopid.err" || rc=$?
assert_eq "an old PID-less lock is broken" 0 "$rc"
assert_eq "the PID-less takeover is reported" 1 "$(grep -c 'holder PID none is gone' "$TMP/nopid.err" || true)"
godot_lock_release "$LOCK"

# A live holder (this shell) is waited for, then refused.
mkdir "$LOCK"
echo "$$" > "$LOCK/pid"
rc=0
godot_lock_acquire "$LOCK" 2 2>"$TMP/live.err" || rc=$?
assert_eq "a live holder's lock is refused after the wait" 1 "$rc"
assert_eq "the refusal is loud" 1 "$(grep -c 'gave up after 2s' "$TMP/live.err" || true)"
godot_lock_release "$LOCK"

# An import killed by the timeout fails and writes no stamp.
rm -rf "$PROJ/.godot"
rc=0
STUB_SLEEP=60 godot_import_once 1 "$TMP/godot-import-stub" "$PROJ" "stub|v1" 2>"$TMP/hung.err" || rc=$?
assert_eq "a hung import fails" 1 "$rc"
assert_eq "a hung import leaves no stamp" no "$([ -f "$(godot_import_stamp_path "$PROJ")" ] && echo yes || echo no)"
assert_eq "a hung import releases the lock" no "$([ -e "$PROJ/.godot/sparta-import.lock" ] && echo yes || echo no)"
rmdir "$STUB_LOG.busy" 2>/dev/null || true

# An import that dies on a signal (here 134, the abort a Linux CI import hit) is not
# fatal: Godot's --import status is unreliable and the cache it leaves works. It warns
# with its status and the log's tail, writes no stamp, and returns 0.
rc=0
STUB_EXIT=134 godot_import_once 30 "$TMP/godot-import-stub" "$PROJ" "stub|v1" 2>"$TMP/crash.err" || rc=$?
assert_eq "an import that aborts (134) does not fail" 0 "$rc"
assert_eq "an aborted import leaves no stamp" no "$([ -f "$(godot_import_stamp_path "$PROJ")" ] && echo yes || echo no)"
assert_eq "the abort is a warning naming the status" 1 \
  "$(grep -c '^::warning::godot --import of .* exited with status 134' "$TMP/crash.err" || true)"
assert_eq "the warning carries the log tail" 1 "$(grep -c '^  | stub import output$' "$TMP/crash.err" || true)"
assert_eq "an aborted import releases the lock" no "$([ -e "$PROJ/.godot/sparta-import.lock" ] && echo yes || echo no)"
godot_import_once 30 "$TMP/godot-import-stub" "$PROJ" "stub|v1" 2>/dev/null
assert_eq "the next call imports again and stamps" "stub|v1" \
  "$(cat "$(godot_import_stamp_path "$PROJ")" 2>/dev/null || echo missing)"
# A plain non-zero status takes the same path: no failure, no stamp.
rm -f "$(godot_import_stamp_path "$PROJ")"
rc=0
STUB_EXIT=1 godot_import_once 30 "$TMP/godot-import-stub" "$PROJ" "stub|v1" 2>/dev/null || rc=$?
assert_eq "a plain non-zero import status is not a failure" 0 "$rc"
assert_eq "a plain non-zero import status writes no stamp" missing \
  "$(cat "$(godot_import_stamp_path "$PROJ")" 2>/dev/null || echo missing)"

# --- dump-demo-states.sh end to end -----------------------------------------------

# A fake project with a one-row catalog, and a stub Godot that answers --version and
# --import, and for a dump writes a two-line hash stream and one state file. When
# STUB_HANG_FIRST names a counter file, its first dump writes ONE hash line and then
# hangs, the shape of a run killed mid-dump.
TREE="$TMP/tree"
mkdir -p "$TREE/website/tools" "$TREE/demos/inputs"
cat > "$TREE/website/tools/demo-catalog.sh" <<'EOF'
DEMOS=(
  "alpha|demos/inputs/alpha.json|30|100|640|input"
)
EOF
: > "$TREE/demos/inputs/alpha.json"
cat > "$TMP/godot-dump-stub" <<'EOF'
#!/usr/bin/env bash
case " $* " in
  *" --version "*) echo "4.7.stub"; exit 0 ;;
  *" --import "*) exit 0 ;;
esac
dir="$SPARTA_DEMO_STATE_DIR"
if [ -n "${STUB_HANG_FIRST:-}" ]; then
  n=$(( $(cat "$STUB_HANG_FIRST" 2>/dev/null || echo 0) + 1 ))
  echo "$n" > "$STUB_HANG_FIRST"
  if [ "$n" -eq 1 ]; then
    echo '{"tick":8,"hash":"aaaa"}' >> "$dir/hash_stream.jsonl"
    exec sleep 60
  fi
fi
echo '{"tick":8,"hash":"aaaa"}' >> "$dir/hash_stream.jsonl"
echo '{"tick":200,"hash":"bbbb"}' >> "$dir/hash_stream.jsonl"
echo '{"tick":8}' > "$dir/state_00008.json"
EOF
chmod +x "$TMP/godot-dump-stub"

dump() {
  # 5 s, not 1: a clean stub run on a loaded machine must never use up a retry.
  # CI is unset so the local default (3 attempts) applies even when this test itself
  # runs in CI; the CI default is its own case below.
  env -u CI GODOT_BIN="$TMP/godot-dump-stub" SPARTA_DUMP_STATE_TIMEOUT=5 \
    bash "$REPO_ROOT/website/tools/dump-demo-states.sh" "$1" "$TREE"
}

rc=0
dump "$TMP/clean" >"$TMP/clean.log" 2>&1 || rc=$?
assert_eq "a clean stub dump succeeds" 0 "$rc"
rc=0
STUB_HANG_FIRST="$TMP/hang.count" dump "$TMP/retried" >"$TMP/retried.log" 2>&1 || rc=$?
assert_eq "a dump hung on its first attempt succeeds on retry" 0 "$rc"
assert_eq "the dump's retry is logged" 1 "$(grep -c "attempt 1/3 timed out" "$TMP/retried.log" || true)"
assert_eq "the retry says how far the killed attempt got" 1 \
  "$(grep -c "killed attempt for 'alpha' had written 0 of " "$TMP/retried.log" || true)"
assert_eq "the retried hash stream is byte-identical to a clean run's" same \
  "$(cmp -s "$TMP/clean/alpha/hash_stream.jsonl" "$TMP/retried/alpha/hash_stream.jsonl" && echo same || echo differs)"

rm -f "$TMP/hang.count"
rc=0
STUB_HANG_FIRST="$TMP/hang.count" SPARTA_DUMP_ATTEMPTS=1 dump "$TMP/once" >"$TMP/once.log" 2>&1 || rc=$?
assert_eq "with one attempt a hung dump fails" 1 "$rc"
assert_eq "the failure names the timeout" 1 "$(grep -c "timed out on all 1 attempts" "$TMP/once.log" || true)"

# Under CI the default is one attempt, so a deterministic hang fails within one timeout
# instead of outlasting the CI step's own limit.
rm -f "$TMP/hang.count"
rc=0
STUB_HANG_FIRST="$TMP/hang.count" CI=true GODOT_BIN="$TMP/godot-dump-stub" SPARTA_DUMP_STATE_TIMEOUT=5 \
  bash "$REPO_ROOT/website/tools/dump-demo-states.sh" "$TMP/ci" "$TREE" >"$TMP/ci.log" 2>&1 || rc=$?
assert_eq "under CI a hung dump fails without a retry" 1 "$rc"
assert_eq "under CI the default is one attempt" 1 "$(grep -c "timed out on all 1 attempts" "$TMP/ci.log" || true)"

# A wipe that fails (a killed Godot on Windows still holding a file) is retried, and
# only a wipe that keeps failing fails the run. A fake `rm` first on PATH fails its
# first RM_FAILS calls on the clip dir, then hands over to the real rm.
REAL_RM="$(command -v rm)"
mkdir -p "$TMP/fakebin"
cat > "$TMP/fakebin/rm" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *"/wipe-"*"/alpha"*)
    n=\$(( \$(cat "$TMP/rm.count" 2>/dev/null || echo 0) + 1 ))
    echo "\$n" > "$TMP/rm.count"
    if [ "\$n" -le "\${RM_FAILS:-0}" ]; then exit 1; fi ;;
esac
exec "$REAL_RM" "\$@"
EOF
chmod +x "$TMP/fakebin/rm"
"$REAL_RM" -f "$TMP/rm.count"
rc=0
RM_FAILS=2 PATH="$TMP/fakebin:$PATH" dump "$TMP/wipe-ok" >"$TMP/wipe-ok.log" 2>&1 || rc=$?
assert_eq "a wipe that fails twice is retried and the dump succeeds" 0 "$rc"
assert_eq "the retried wipe still yields a clean transcript" same \
  "$(cmp -s "$TMP/clean/alpha/hash_stream.jsonl" "$TMP/wipe-ok/alpha/hash_stream.jsonl" && echo same || echo differs)"
"$REAL_RM" -f "$TMP/rm.count"
rc=0
RM_FAILS=3 PATH="$TMP/fakebin:$PATH" dump "$TMP/wipe-bad" >"$TMP/wipe-bad.log" 2>&1 || rc=$?
assert_eq "a wipe that fails three times fails the run" 1 "$rc"
assert_eq "the wipe failure is named" 1 "$(grep -c "could not clear .* (3 tries); failing the run" "$TMP/wipe-bad.log" || true)"

if [ "$FAILURES" -ne 0 ]; then
  echo "$FAILURES failure(s)" >&2
  exit 1
fi
echo "all dump-retry / import-lock cases passed"
