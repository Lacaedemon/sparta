#!/usr/bin/env bash
# Self-contained unit test for the parallel-load guards behind
# website/tools/dump-demo-states.sh:
#
# run_bounded_retry() (tools/lib/run-bounded.sh):
#   1. a command that times out once and then finishes succeeds on attempt 2, runs its
#      prepare hook before each attempt, and logs the retry (the first timeout is faked
#      by its exit status, so a slow start cannot use up a short budget)
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
#      time -- also when they all start against a stale lock they race to break, and
#      also when mkdir(1) reports success for a directory that already exists
#   7. a lock left by a dead holder, or with no holder PID and over a minute old, is
#      broken; a fresh PID-less one is not; a breaker that arrives after another caller
#      already broke and retook the lock leaves it alone; an abandoned .break lock fails
#      loudly and is not cleared; a directory lock left by the older mkdir-based helper
#      is judged by the PID in <lock>/pid (a live one is waited for however old the
#      lock, a dead one is broken at once) and without one is waited for while fresh
#      and broken once old; one held by a live holder is waited for and then refused
#      loudly when the wait runs out; a lock that cannot be created at all (under a
#      missing directory) fails at once with the shell's error, not after the wait;
#      an existing directory reads as held; a failed PID write removes the file it
#      made, and says so when that remove fails too; a stale lock that cannot be
#      removed fails at once, and so does a breaker that cannot be removed; a stale
#      dangling symlink at the lock path is broken; an
#      unreadable PID file fails at once instead of reading as "no PID", while a read
#      that finds no file reads as "no PID" even if the file is back; a directory lock
#      is read at <lock>/pid, also when it appears just before the read; release
#      leaves a lock that names another holder in place, warns about one already
#      gone, leaves an unreadable one in place without failing, and warns without
#      failing when removing its own lock fails; a caller under
#      set -C can still take, release and import
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

# Cases 1 and 2 count attempts with the prepare hook, which runs in this shell before
# every attempt, not with the stubs: on a loaded machine a stub can be killed by the
# timeout before it runs a single line, and that attempt must still count.
PREPS="$TMP/preps"
count_prep() { echo x >> "$PREPS"; }
attempts_made() { wc -l < "$PREPS" | tr -d ' '; }

# timeout_first <prep-log> <run-log>: logs each run, then on the first attempt (by the
# prepare hook's count) exits 124, the status run_bounded returns when its timeout kills
# a run; later attempts exit 0. Faking the first timeout lets the budget be generous, so
# a retry that starts slowly still runs and finishes inside it, and the run log can be
# trusted. Case 2 covers a real timeout kill.
cat > "$TMP/timeout-first" <<'EOF'
#!/usr/bin/env bash
echo x >> "$2"
if [ "$(wc -l < "$1" | tr -d ' ')" -eq 1 ]; then exit 124; fi
exit 0
EOF
chmod +x "$TMP/timeout-first"

rc=0
run_bounded_retry 3 30 "case-1" count_prep "$TMP/timeout-first" "$PREPS" "$TMP/c1.runs" \
  2>"$TMP/c1.err" || rc=$?
assert_eq "a once-timed-out command succeeds on a retry" 0 "$rc"
assert_eq "it ran twice" 2 "$(wc -l < "$TMP/c1.runs" | tr -d ' ')"
assert_eq "the prepare hook ran before each attempt" 2 "$(attempts_made)"
assert_eq "the retry is logged" 1 "$(grep -c 'attempt 1/3 timed out after 30s' "$TMP/c1.err" || true)"

# always_hang: hangs until the timeout kills it. Every attempt times out whether or not
# the stub got to start before the kill, so a short budget is safe here.
cat > "$TMP/always-hang" <<'EOF'
#!/usr/bin/env bash
exec sleep 60
EOF
chmod +x "$TMP/always-hang"
rm -f "$PREPS"
rc=0
run_bounded_retry 2 1 "case-2" count_prep "$TMP/always-hang" 2>"$TMP/c2.err" || rc=$?
assert_eq "an always-hung command fails with the timeout status" yes \
  "$(run_bounded_timed_out "$rc" && echo yes || echo no)"
assert_eq "it ran exactly the attempt budget" 2 "$(attempts_made)"
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

# A stub Godot for --import: logs each import, and fails the test if two overlap. The
# busy marker is a noclobber file, not a mkdir: a mkdir(1) that reports success for an
# existing directory would hide the very overlap this looks for.
cat > "$TMP/godot-import-stub" <<'EOF'
#!/usr/bin/env bash
log="$STUB_LOG"
if ! ( set -C; : > "$log.busy" ) 2>/dev/null; then echo overlap >> "$log"; fi
echo import >> "$log"
# Godot's own output, which godot_import_once sends to .godot/sparta-import.log.
echo "stub import output"
sleep "${STUB_SLEEP:-0}"
# STUB_EDIT_DURING names a file to edit mid-import (an edit racing the import).
if [ -n "${STUB_EDIT_DURING:-}" ]; then echo '# mid-import edit' >> "$STUB_EDIT_DURING"; fi
rm -f "$log.busy"
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

# A PID from a finished background job is dead.
sh -c 'exit 0' &
dead=$!
wait "$dead"

# The concurrent cases run twice: once with the real mkdir, and once with a mkdir that
# reports success for a directory that already exists. The second is what uutils
# coreutils' mkdir (Ubuntu 26.04's) does when another process creates the directory a
# moment before it, which on CI let two callers take a mkdir lock and import at once.
# Faking it on every call makes that race certain rather than timing-dependent, so a
# lock that trusts mkdir's exit status fails here every run.
lying_mkdir() { command mkdir -p "$@"; }
for mkdir_mode in real lying; do
  if [ "$mkdir_mode" = lying ]; then
    mkdir() { lying_mkdir "$@"; }
    mode_note=" (mkdir reports success for an existing dir)"
  else
    mode_note=""
  fi

  # Concurrent callers on a cold project: one import, never two at once.
  rm -rf "$PROJ/.godot" "$STUB_LOG"
  pids=()
  for _ in 1 2 3 4 5; do
    STUB_SLEEP=2 godot_import_once 30 "$TMP/godot-import-stub" "$PROJ" "stub|v1" 2>/dev/null &
    pids+=($!)
  done
  failed_callers=0
  for p in "${pids[@]}"; do wait "$p" || failed_callers=$((failed_callers + 1)); done
  assert_eq "five concurrent callers all succeed$mode_note" 0 "$failed_callers"
  assert_eq "five concurrent callers run one import$mode_note" 1 "$(imports)"
  assert_eq "no two imports overlapped$mode_note" 0 "$(grep -c '^overlap$' "$STUB_LOG" || true)"
  assert_eq "the lock is released afterwards$mode_note" no \
    "$([ -e "$PROJ/.godot/sparta-import.lock" ] && echo yes || echo no)"

  # Five callers that all find a stale lock race to break it: still exactly one import,
  # never two at once, and the stale lock is broken exactly once.
  rm -rf "$PROJ/.godot" "$STUB_LOG" "$TMP"/race-*.err
  command mkdir -p "$PROJ/.godot"
  echo "$dead" > "$PROJ/.godot/sparta-import.lock"
  pids=()
  for i in 1 2 3 4 5; do
    STUB_SLEEP=2 godot_import_once 30 "$TMP/godot-import-stub" "$PROJ" "stub|v1" 2>"$TMP/race-$i.err" &
    pids+=($!)
  done
  failed_callers=0
  for p in "${pids[@]}"; do wait "$p" || failed_callers=$((failed_callers + 1)); done
  assert_eq "callers racing to break a stale lock all succeed$mode_note" 0 "$failed_callers"
  assert_eq "callers racing to break a stale lock run one import$mode_note" 1 "$(imports)"
  assert_eq "no two imports overlapped after the race$mode_note" 0 "$(grep -c '^overlap$' "$STUB_LOG" || true)"
  assert_eq "the stale lock was broken once$mode_note" 1 \
    "$(cat "$TMP"/race-*.err | grep -c 'broke stale lock' || true)"
  assert_eq "no stale-lock leftovers remain$mode_note" 0 \
    "$(find "$PROJ/.godot" -maxdepth 1 -name 'sparta-import.lock*' | wc -l | tr -d ' ')"
done
unset -f mkdir

# A dead holder's lock is broken.
LOCK="$TMP/lock"
echo "$dead" > "$LOCK"
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
    rm -f "$1"; echo "$$" > "$1"
    return 0
  fi
  orig_godot_lock_is_stale "$@"
}
echo "$dead" > "$LOCK"
rc=0
godot_lock_acquire "$LOCK" 1 2>/dev/null || rc=$?
assert_eq "a late breaker does not take the lock" 1 "$rc"
assert_eq "the new holder's lock is left intact" "$$" "$(cat "$LOCK" 2>/dev/null || echo missing)"
eval "$(declare -f orig_godot_lock_is_stale | sed '1s/^orig_//')"
godot_lock_release "$LOCK"

# A breaker killed mid-break leaves <lock>.break behind. It is never cleared
# automatically (two waiters could both clear it and break concurrently): once over a
# minute old it fails the caller loudly, naming the file, and is left in place.
echo "$dead" > "$LOCK"
: > "$LOCK.break"
touch -d '2 minutes ago' "$LOCK.break"
rc=0
godot_lock_acquire "$LOCK" 3 2>"$TMP/breaker.err" || rc=$?
assert_eq "an abandoned breaker lock fails the caller" 1 "$rc"
assert_eq "the failure names the .break file to remove" 1 \
  "$(grep -c "::error::.*$LOCK.break is over a minute old" "$TMP/breaker.err" || true)"
assert_eq "the abandoned breaker lock is left in place" yes "$([ -e "$LOCK.break" ] && echo yes || echo no)"
assert_eq "the stale lock under it is not broken" "$dead" "$(cat "$LOCK" 2>/dev/null || echo missing)"
rm -f "$LOCK.break" "$LOCK"

# A lock with no PID: a fresh one may be a holder about to write its PID, so it is
# waited for; one over a minute old is a holder that died first, so it is broken.
: > "$LOCK"
rc=0
godot_lock_acquire "$LOCK" 1 2>/dev/null || rc=$?
assert_eq "a fresh PID-less lock is not broken" 1 "$rc"
touch -d '2 minutes ago' "$LOCK"
rc=0
godot_lock_acquire "$LOCK" 1 2>"$TMP/nopid.err" || rc=$?
assert_eq "an old PID-less lock is broken" 0 "$rc"
assert_eq "the PID-less takeover is reported" 1 "$(grep -c 'holder PID none is gone' "$TMP/nopid.err" || true)"
godot_lock_release "$LOCK"

# A directory lock left by the older mkdir-based helper keeps its holder in <lock>/pid.
# A live holder there (this shell), even one older than the PID-less stale age, is
# waited for and never broken: its import may still be running. Each directory case
# clears the lock path first, so one that fails does not abort the cases after it.
rm -rf "$LOCK"; mkdir "$LOCK"
echo "$$" > "$LOCK/pid"
touch -d '2 minutes ago' "$LOCK"
rc=0
godot_lock_acquire "$LOCK" 2 2>"$TMP/dirlive.err" || rc=$?
assert_eq "an old directory lock with a live holder is not broken" 1 "$rc"
assert_eq "the refusal names the directory lock's live holder" 1 \
  "$(grep -c "gave up after 2s.*holder PID $$)" "$TMP/dirlive.err" || true)"
assert_eq "the live directory lock is left in place" "$$" "$(cat "$LOCK/pid" 2>/dev/null || echo missing)"
rm -rf "$LOCK"

# A dead holder in <lock>/pid is broken at once, fresh as the lock is.
rm -rf "$LOCK"; mkdir "$LOCK"
echo "$dead" > "$LOCK/pid"
rc=0
godot_lock_acquire "$LOCK" 1 2>"$TMP/dirlock.err" || rc=$?
assert_eq "a directory lock with a dead holder is broken" 0 "$rc"
assert_eq "the directory-lock takeover names the dead holder" 1 \
  "$(grep -c "broke stale lock.*holder PID $dead is gone" "$TMP/dirlock.err" || true)"
assert_eq "the lock is a file after the takeover" yes "$([ -f "$LOCK" ] && echo yes || echo no)"
godot_lock_release "$LOCK"

# A directory lock with no <lock>/pid (an old holder killed before writing one) reads as
# PID-less: waited for while fresh, broken once over a minute old.
rm -rf "$LOCK"; mkdir "$LOCK"
rc=0
godot_lock_acquire "$LOCK" 1 2>/dev/null || rc=$?
assert_eq "a fresh PID-less directory lock is not broken" 1 "$rc"
touch -d '2 minutes ago' "$LOCK"
rc=0
godot_lock_acquire "$LOCK" 1 2>"$TMP/dirnopid.err" || rc=$?
assert_eq "an old PID-less directory lock is broken" 0 "$rc"
assert_eq "the PID-less directory-lock takeover is reported" 1 \
  "$(grep -c 'holder PID none is gone' "$TMP/dirnopid.err" || true)"
godot_lock_release "$LOCK"
rm -rf "$LOCK"

# A lock that cannot be created at all (here, under a missing directory) is not mistaken
# for one someone else holds: it fails at once, well inside the wait budget, with the
# shell's own error, rather than waiting the budget out and blaming an unknown holder.
start=$SECONDS
rc=0
godot_lock_acquire "$TMP/no-such-dir/lock" 30 2>"$TMP/nodir.err" || rc=$?
assert_eq "a lock under a missing directory fails" 1 "$rc"
assert_eq "that failure is immediate, not the wait budget" yes \
  "$([ $((SECONDS - start)) -le 5 ] && echo yes || echo no)"
assert_eq "that failure says the lock cannot be created" 1 \
  "$(grep -c "::error::godot-import-lock: cannot create lock $TMP/no-such-dir/lock: .*No such file or directory" "$TMP/nodir.err" || true)"
assert_eq "that failure does not blame a holder" 0 "$(grep -c 'holder PID' "$TMP/nodir.err" || true)"

# godot_lock_take itself tells a create error (2) from a held lock (1): a path under a
# regular file cannot be created, and nothing is left behind.
: > "$TMP/not-a-dir"
rc=0
godot_lock_take "$TMP/not-a-dir/lock" 2>"$TMP/notdir.err" || rc=$?
assert_eq "a lock under a non-directory is a create error, not held" 2 "$rc"
assert_eq "that create error is reported" 1 \
  "$(grep -c '::error::godot-import-lock: cannot create lock' "$TMP/notdir.err" || true)"
echo "$$" > "$LOCK"
rc=0
godot_lock_take "$LOCK" 2>"$TMP/held.err" || rc=$?
assert_eq "an existing lock reads as held" 1 "$rc"
assert_eq "a held lock is not reported as an error" 0 "$(wc -c < "$TMP/held.err" | tr -d ' ')"
godot_lock_release "$LOCK"
# The shell's own message for a directory at the lock path (an old helper's lock) reads
# as held, so a change in its wording fails here rather than in a waiting caller.
rm -rf "$LOCK"; mkdir "$LOCK"
rc=0
godot_lock_take "$LOCK" 2>"$TMP/held-dir.err" || rc=$?
assert_eq "an existing directory lock reads as held" 1 "$rc"
assert_eq "a held directory lock is not reported as an error" 0 "$(wc -c < "$TMP/held-dir.err" | tr -d ' ')"
rm -rf "$LOCK"

# bounded <secs> <function> [args...]: runs one of the lock helper's functions in a
# fresh bash under run_bounded, so a case that regresses into an endless loop fails
# (status 124) instead of hanging the run. A function a case overrides must be exported.
bounded() {
  local secs="$1"
  shift
  run_bounded "$secs" bash -c '. "$0"; "$@"' "$REPO_ROOT/tools/lib/godot-import-lock.sh" "$@"
}
export LOCK

# A stale dangling symlink at the lock path (its target gone) holds no PID, so once it
# is over a minute old it is broken like any old PID-less lock, not spun on forever.
ln -s "$TMP/nowhere" "$LOCK" 2>/dev/null ||
  MSYS=winsymlinks:nativestrict ln -s "$TMP/nowhere" "$LOCK" 2>/dev/null || true
if [ -L "$LOCK" ]; then
  touch -h -d '2 minutes ago' "$LOCK"
  rc=0
  bounded 10 godot_lock_acquire "$LOCK" 3 2>"$TMP/dangling.err" || rc=$?
  assert_eq "a stale dangling symlink lock is broken" 0 "$rc"
  assert_eq "the dangling-symlink takeover is reported" 1 \
    "$(grep -c 'broke stale lock.*holder PID none is gone' "$TMP/dangling.err" || true)"
  rm -f "$LOCK" "$LOCK.break"
else
  echo "skip: cannot create a dangling symlink here; the dangling-symlink lock case did not run" >&2
fi

# A stale lock that cannot be removed fails the caller at once, rather than claiming a
# takeover or retrying the remove forever. Forced by an rm that fails on the lock.
rm() {
  if [ "${*: -1}" = "$LOCK" ]; then builtin echo "rm: cannot remove '$LOCK': Permission denied" >&2; return 1; fi
  command rm "$@"
}
export -f rm
echo "$dead" > "$LOCK"
rc=0
bounded 10 godot_lock_acquire "$LOCK" 3 2>"$TMP/rmfail.err" || rc=$?
assert_eq "a stale lock that cannot be removed fails the caller" 1 "$rc"
assert_eq "that failure names the lock and the rm error" 1 \
  "$(grep -c "::error::godot-import-lock: cannot remove stale lock $LOCK (holder PID $dead is gone): .*Permission denied" "$TMP/rmfail.err" || true)"
assert_eq "no takeover is claimed" 0 "$(grep -c 'broke stale lock' "$TMP/rmfail.err" || true)"
assert_eq "its breaker is released" no "$([ -e "$LOCK.break" ] && echo yes || echo no)"
unset -f rm
rm -f "$LOCK" "$LOCK.break"

# A breaker that cannot be removed after a takeover fails the caller at once with rm's
# error, rather than leaving it for a later waiter to blame on a breaker that died
# mid-break. Forced by an rm that fails on the breaker.
rm() {
  if [ "${*: -1}" = "$LOCK.break" ]; then builtin echo "rm: cannot remove '$LOCK.break': Permission denied" >&2; return 1; fi
  command rm "$@"
}
export -f rm
echo "$dead" > "$LOCK"
rc=0
bounded 10 godot_lock_acquire "$LOCK" 3 2>"$TMP/brkrm.err" || rc=$?
unset -f rm
assert_eq "a breaker that cannot be removed fails the caller" 1 "$rc"
assert_eq "that failure names the breaker and the rm error" 1 \
  "$(grep -c "::error::godot-import-lock: cannot remove breaker $LOCK.break; remove it by hand: .*Permission denied" "$TMP/brkrm.err" || true)"
assert_eq "that failure is not blamed on a breaker that died mid-break" 0 \
  "$(grep -c 'died mid-break' "$TMP/brkrm.err" || true)"
rm -f "$LOCK" "$LOCK.break"

# A create whose PID write fails removes the file it made and fails, rather than leaving
# a PID-less lock that every caller would wait a minute on. Forced by an echo that fails
# on this caller's PID, as a full disk would.
echo() {
  if [ "$*" = "$$" ]; then builtin echo "echo: write error: No space left on device" >&2; return 1; fi
  builtin echo "$@"
}
rc=0
godot_lock_take "$LOCK" 2>"$TMP/pidwrite.err" || rc=$?
assert_eq "a failed PID write fails the take as an error" 2 "$rc"
assert_eq "a failed PID write is reported" 1 \
  "$(grep -c "::error::godot-import-lock: created lock $LOCK but could not write its PID, so removed it again: .*No space left" "$TMP/pidwrite.err" || true)"
assert_eq "a failed PID write leaves no lock behind" no "$([ -e "$LOCK" ] && echo yes || echo no)"
# When removing that file fails too, the error says it is still there, not "removed".
rm() {
  if [ "${*: -1}" = "$LOCK" ]; then builtin echo "rm: cannot remove '$LOCK': Permission denied" >&2; return 1; fi
  command rm "$@"
}
rc=0
godot_lock_take "$LOCK" 2>"$TMP/pidwrite-rm.err" || rc=$?
unset -f echo rm
assert_eq "a failed PID write whose remove fails is an error" 2 "$rc"
assert_eq "that error says the lock could not be removed" 1 \
  "$(grep -c "::error::godot-import-lock: created lock $LOCK but could not write its PID (.*No space left.*), and could not remove it either; remove it by hand: .*Permission denied" "$TMP/pidwrite-rm.err" || true)"
assert_eq "that error does not claim the lock was removed" 0 \
  "$(grep -c 'removed it again' "$TMP/pidwrite-rm.err" || true)"
rm -f "$LOCK"

# A PID file that exists but cannot be read is not "no PID": treated that way, an old
# lock of a live holder would be broken. Forced by a cat that fails on the lock.
echo "$$" > "$LOCK"
touch -d '2 minutes ago' "$LOCK"
cat() {
  if [ "${1:-}" = "$LOCK" ]; then builtin echo "cat: $1: Permission denied" >&2; return 1; fi
  command cat "$@"
}
start=$SECONDS
rc=0
godot_lock_acquire "$LOCK" 30 2>"$TMP/unread.err" || rc=$?
unset -f cat
assert_eq "an unreadable lock fails the caller" 1 "$rc"
assert_eq "that failure is immediate, not the wait budget" yes \
  "$([ $((SECONDS - start)) -le 5 ] && echo yes || echo no)"
assert_eq "that failure names the unreadable PID file" 1 \
  "$(grep -c "::error::godot-import-lock: cannot read the holder PID in $LOCK: .*Permission denied" "$TMP/unread.err" || true)"
assert_eq "the unreadable lock is not broken" "$$" "$(cat "$LOCK" 2>/dev/null || echo missing)"
assert_eq "no breaker is left behind" no "$([ -e "$LOCK.break" ] && echo yes || echo no)"
godot_lock_release "$LOCK"

# A read that finds no file is "no PID", not an error, even when the file is back by
# the time anything could test for it (a holder that released and a new one that took
# the lock in between). Forced by a cat that fails that way once on a lock that exists.
cat() {
  if [ "${1:-}" = "$LOCK" ] && [ ! -e "$TMP/cat-failed" ]; then
    : > "$TMP/cat-failed"
    builtin echo "cat: $1: $CAT_ERR" >&2
    return 1
  fi
  command cat "$@"
}
echo "$dead" > "$LOCK"
for CAT_ERR in "No such file or directory" "Not a directory"; do
  rm -f "$TMP/cat-failed"
  rc=0
  out="$(godot_lock_holder "$LOCK" 2>"$TMP/enoent.err")" || rc=$?
  assert_eq "a holder read failing with '$CAT_ERR' reads as no PID" "0:" "$rc:$out"
  assert_eq "a holder read failing with '$CAT_ERR' is not an error" 0 \
    "$(wc -c < "$TMP/enoent.err" | tr -d ' ')"
done
# In acquire, that read is a fresh PID-less lock: waited for, read again, and broken
# once the re-read names its dead holder, instead of failing the caller.
CAT_ERR="No such file or directory"
rm -f "$TMP/cat-failed"
rc=0
godot_lock_acquire "$LOCK" 5 2>"$TMP/enoent-acq.err" || rc=$?
unset -f cat
assert_eq "a lock whose first read finds no file is still taken" 0 "$rc"
assert_eq "that read is not reported as an error" 0 \
  "$(grep -c '::error::' "$TMP/enoent-acq.err" || true)"
assert_eq "the re-read's dead holder is broken" 1 \
  "$(grep -c "broke stale lock.*holder PID $dead is gone" "$TMP/enoent-acq.err" || true)"
godot_lock_release "$LOCK"

# With the real cat: a directory lock's holder is read from <lock>/pid, and a path under
# a regular file (ENOTDIR) reads as no PID, so a change in cat's wording fails here.
rm -rf "$LOCK"; mkdir "$LOCK"
echo "$dead" > "$LOCK/pid"
rc=0
out="$(godot_lock_holder "$LOCK" 2>"$TMP/holder-dir.err")" || rc=$?
assert_eq "a directory lock's holder is read from <lock>/pid" "0:$dead" "$rc:$out"
rm -rf "$LOCK"
rc=0
out="$(godot_lock_holder "$TMP/not-a-dir/x" 2>"$TMP/holder-notdir.err")" || rc=$?
assert_eq "a holder read under a regular file reads as no PID" "0:" "$rc:$out"
assert_eq "that read is not an error" 0 "$(wc -c < "$TMP/holder-notdir.err" | tr -d ' ')"
# A directory lock that appears just before the read (an older helper taking the lock
# in between) is read at <lock>/pid, not reported as an error. Forced by a cat that, on
# its first read of the lock, puts an old helper's directory lock there and fails as
# reading a directory does.
cat() {
  if [ "${1:-}" = "$LOCK" ] && [ ! -e "$TMP/cat-failed" ]; then
    : > "$TMP/cat-failed"
    command mkdir "$LOCK"
    builtin echo "$dead" > "$LOCK/pid"
    builtin echo "cat: $1: Is a directory" >&2
    return 1
  fi
  command cat "$@"
}
rm -f "$TMP/cat-failed"
rc=0
out="$(godot_lock_holder "$LOCK" 2>"$TMP/holder-race.err")" || rc=$?
unset -f cat
assert_eq "a directory lock that appears before the read is read at <lock>/pid" "0:$dead" "$rc:$out"
assert_eq "that read is not an error" 0 "$(wc -c < "$TMP/holder-race.err" | tr -d ' ')"
rm -rf "$LOCK"

# Release removes the lock only while it names this caller: a lock broken and retaken
# by someone else is theirs, and is left in place with a warning.
echo "$dead" > "$LOCK"
rc=0
godot_lock_release "$LOCK" 2>"$TMP/release.err" || rc=$?
assert_eq "releasing someone else's lock does not fail" 0 "$rc"
assert_eq "someone else's lock is left in place" "$dead" "$(cat "$LOCK" 2>/dev/null || echo missing)"
assert_eq "leaving it is reported" 1 \
  "$(grep -c "::warning::godot-import-lock: $LOCK no longer names PID $$ (it names $dead)" "$TMP/release.err" || true)"
rm -f "$LOCK"
echo "$$" > "$LOCK"
godot_lock_release "$LOCK" 2>"$TMP/release-own.err"
assert_eq "this caller's own lock is released" no "$([ -e "$LOCK" ] && echo yes || echo no)"
assert_eq "releasing its own lock is silent" 0 "$(wc -c < "$TMP/release-own.err" | tr -d ' ')"
# A remove of its own lock that fails is a warning with rm's error, and still returns 0.
echo "$$" > "$LOCK"
rm() {
  if [ "${*: -1}" = "$LOCK" ]; then builtin echo "rm: cannot remove '$LOCK': Permission denied" >&2; return 1; fi
  command rm "$@"
}
rc=0
godot_lock_release "$LOCK" 2>"$TMP/release-rm.err" || rc=$?
unset -f rm
assert_eq "a failed remove at release returns 0" 0 "$rc"
assert_eq "a failed remove at release is a warning with rm's error" 1 \
  "$(grep -c "::warning::godot-import-lock: cannot remove lock $LOCK: .*Permission denied" "$TMP/release-rm.err" || true)"
rm -f "$LOCK"
# A lock already gone gets the same warning: it no longer names this caller.
rc=0
godot_lock_release "$LOCK" 2>"$TMP/release-gone.err" || rc=$?
assert_eq "releasing a lock already gone does not fail" 0 "$rc"
assert_eq "a lock already gone is reported" 1 \
  "$(grep -c "::warning::godot-import-lock: $LOCK no longer names PID $$ (it names no PID, or is gone)" "$TMP/release-gone.err" || true)"
# A lock whose PID cannot be read is left in place with the read's ::error::, and the
# release still returns 0: the caller's import is over.
echo "$$" > "$LOCK"
cat() {
  if [ "${1:-}" = "$LOCK" ]; then builtin echo "cat: $1: Permission denied" >&2; return 1; fi
  command cat "$@"
}
rc=0
godot_lock_release "$LOCK" 2>"$TMP/release-unread.err" || rc=$?
unset -f cat
assert_eq "releasing an unreadable lock returns 0" 0 "$rc"
assert_eq "an unreadable lock at release is reported" 1 \
  "$(grep -c "::error::godot-import-lock: cannot read the holder PID in $LOCK: .*Permission denied" "$TMP/release-unread.err" || true)"
assert_eq "an unreadable lock at release is left in place" "$$" "$(cat "$LOCK" 2>/dev/null || echo missing)"
rm -f "$LOCK"

# A caller running under set -C (noclobber) can still take, release and import twice:
# the helper's own writes, last run's import log included, do not trip on it. A log
# that cannot be written would only show as a non-zero import status, which is not
# fatal, so the imports themselves are counted and the stderr checked.
before="$(imports)"
rc=0
( set -C
  godot_import_once 30 "$TMP/godot-import-stub" "$PROJ" "" 2>"$TMP/noclobber.err"
  godot_import_once 30 "$TMP/godot-import-stub" "$PROJ" "" 2>>"$TMP/noclobber.err" ) || rc=$?
assert_eq "a caller under set -C succeeds twice in a row" 0 "$rc"
assert_eq "a caller under set -C runs both imports" $((before + 2)) "$(imports)"
assert_eq "a caller under set -C gets no warning or error" 0 \
  "$(grep -c '::\(warning\|error\)::' "$TMP/noclobber.err" || true)"
assert_eq "its lock is released afterwards" no \
  "$([ -e "$PROJ/.godot/sparta-import.lock" ] && echo yes || echo no)"

# A live holder (this shell) is waited for, then refused.
echo "$$" > "$LOCK"
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
rm -f "$STUB_LOG.busy"

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
# STUB_ATTEMPTS names an attempt log, its first dump writes ONE hash line and then
# hangs, the shape of a run killed mid-dump.
#
# The attempt log is not written by the stub: a stub killed before it ran a line would
# leave the next attempt reading as the first, and hanging again. A fake `rm` first on
# PATH writes it instead, one line each time dump-demo-states.sh's prepare step wipes the
# clip dir, which it does before every attempt and outside the timeout.
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
if [ -n "${STUB_ATTEMPTS:-}" ] && [ "$(wc -l < "$STUB_ATTEMPTS" | tr -d ' ')" -eq 1 ]; then
  echo '{"tick":8,"hash":"aaaa"}' >> "$dir/hash_stream.jsonl"
  exec sleep 60
fi
echo '{"tick":8,"hash":"aaaa"}' >> "$dir/hash_stream.jsonl"
echo '{"tick":200,"hash":"bbbb"}' >> "$dir/hash_stream.jsonl"
echo '{"tick":8}' > "$dir/state_00008.json"
EOF
chmod +x "$TMP/godot-dump-stub"

REAL_RM="$(command -v rm)"
mkdir -p "$TMP/attemptbin"
cat > "$TMP/attemptbin/rm" <<EOF
#!/usr/bin/env bash
case "\$*" in
  *"/alpha") [ -n "\${STUB_ATTEMPTS:-}" ] && echo x >> "\$STUB_ATTEMPTS" ;;
esac
exec "$REAL_RM" "\$@"
EOF
chmod +x "$TMP/attemptbin/rm"
dump_attempts() { wc -l < "$TMP/attempts.log" | tr -d ' '; }

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
STUB_ATTEMPTS="$TMP/attempts.log" PATH="$TMP/attemptbin:$PATH" \
  dump "$TMP/retried" >"$TMP/retried.log" 2>&1 || rc=$?
assert_eq "a dump hung on its first attempt succeeds on retry" 0 "$rc"
assert_eq "the retried dump took two attempts" 2 "$(dump_attempts)"
assert_eq "the dump's retry is logged" 1 "$(grep -c "attempt 1/3 timed out" "$TMP/retried.log" || true)"
assert_eq "the retry says how far the killed attempt got" 1 \
  "$(grep -c "killed attempt for 'alpha' had written 0 of " "$TMP/retried.log" || true)"
assert_eq "the retried hash stream is byte-identical to a clean run's" same \
  "$(cmp -s "$TMP/clean/alpha/hash_stream.jsonl" "$TMP/retried/alpha/hash_stream.jsonl" && echo same || echo differs)"

rm -f "$TMP/attempts.log"
rc=0
STUB_ATTEMPTS="$TMP/attempts.log" PATH="$TMP/attemptbin:$PATH" SPARTA_DUMP_ATTEMPTS=1 \
  dump "$TMP/once" >"$TMP/once.log" 2>&1 || rc=$?
assert_eq "with one attempt a hung dump fails" 1 "$rc"
assert_eq "the failure names the timeout" 1 "$(grep -c "timed out on all 1 attempts" "$TMP/once.log" || true)"

# Under CI the default is one attempt, so a deterministic hang fails within one timeout
# instead of outlasting the CI step's own limit.
rm -f "$TMP/attempts.log"
rc=0
STUB_ATTEMPTS="$TMP/attempts.log" PATH="$TMP/attemptbin:$PATH" CI=true GODOT_BIN="$TMP/godot-dump-stub" SPARTA_DUMP_STATE_TIMEOUT=5 \
  bash "$REPO_ROOT/website/tools/dump-demo-states.sh" "$TMP/ci" "$TREE" >"$TMP/ci.log" 2>&1 || rc=$?
assert_eq "under CI a hung dump fails without a retry" 1 "$rc"
assert_eq "under CI the default is one attempt" 1 "$(grep -c "timed out on all 1 attempts" "$TMP/ci.log" || true)"

# A wipe that fails (a killed Godot on Windows still holding a file) is retried, and
# only a wipe that keeps failing fails the run. A fake `rm` first on PATH fails its
# first RM_FAILS calls on the clip dir, then hands over to the real rm.
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
