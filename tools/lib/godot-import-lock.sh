# tools/lib/godot-import-lock.sh -- shared helper: import a Godot project at most once
# per source change, under a per-project lock.
#
# Sourced by website/tools/dump-demo-states.sh (after tools/lib/run-bounded.sh, whose
# run_bounded / run_bounded_timed_out this builds on); not executable on its own.
#
# Why: every dump-demo-states.sh run used to start with its own unguarded
# `godot --headless --import`, so N dumps started in parallel against one project ran N
# imports at once. Measured on Windows (Godot 4.7, 2026-10-30): 8 concurrent imports of
# a project with no .godot/ cache, 5 rounds, logged errors in 34 of 40 imports ("Cannot
# open file 'res://.godot/imported/...'", "Condition f.is_null()"), and rewrote six
# TRACKED assets/**/*.import sidecars with default import params and fresh UIDs, plus a
# stray *.import~RF*.TMP file. Warm imports (cache already built) did not collide in 80
# tries, but they still rewrite .godot/global_script_class_cache.cfg, uid_cache.bin and
# editor/filesystem_cache10 on every run, so they are pure churn under a running dump.
#
# godot_import_once serialises imports against each other behind a per-project lock
# file (it does not hold dumps off while an import runs) and skips the import when the
# cache is already current for this tree and this Godot, so N parallel runs never
# import at the same time and a warm project is not re-imported at all. A cold
# project imports twice, one after the other: the first import writes new *.import
# sidecars after the stamp's (pre-import) mtime, so the next caller imports once more,
# and every caller after that skips. That second import can run while the first
# caller's dump is already reading the cache. Measured: 16 staggered dense dumps x 8, cold start,
# ran 2 imports in 128 runs, with no import errors and no tracked file changed.

# godot_import_stamp_path <project> -- the stamp godot_import_once writes after a
# completed import. It lives inside .godot/, so wiping the cache wipes the stamp too.
godot_import_stamp_path() {
  printf '%s/.godot/sparta-import.stamp\n' "$1"
}

# godot_import_is_current <project> <stamp-content>
#
# True when the stamp exists, records the same non-empty content (the Godot binary and
# version), and nothing Godot would import is newer than it. "Would import" follows
# Godot's own filesystem scan: hidden paths (.godot/, .git, .claude/ and the worktrees
# under it) and any directory holding a .gdignore (website/, where the dumps themselves
# land by default) are skipped, so a dump writing its transcripts never invalidates the
# stamp. Directories are included, so a deleted or renamed file (which only touches its
# parent directory's mtime) still counts as a change.
#
# Fails closed: an empty <stamp-content> (an unknown Godot version) or any find error
# reads as "not current", so the import runs rather than being skipped on a guess.
godot_import_is_current() {
  local project="$1" want="$2" stamp
  [ -n "$want" ] || return 1
  stamp="$(godot_import_stamp_path "$project")"
  [ -f "$stamp" ] || return 1
  [ "$(cat "$stamp")" = "$want" ] || return 1
  local prune=( -name '.*' ! -path "$project" ) ignores g newer
  # .gdignore is itself a dot-file, so it is exempted from the hidden-path prune here.
  ignores="$(find "$project" \( -name '.*' ! -name .gdignore ! -path "$project" \) -prune \
    -o -name .gdignore -print)" || return 1
  # The project root itself is never pruned: a root .gdignore would otherwise prune the
  # scan at its start node, and every check would report "nothing changed".
  while IFS= read -r g; do
    [ -n "$g" ] || continue
    [ "${g%/.gdignore}" = "$project" ] && continue
    prune+=( -o -path "${g%/.gdignore}" )
  done <<<"$ignores"
  newer="$(find "$project" \( "${prune[@]}" \) -prune -o -newer "$stamp" -print)" || return 1
  [ -z "$newer" ]
}

# godot_lock_create <lock> <pid>
#
# The one exclusive create behind godot_lock_take: opens <lock> under noclobber and
# writes <pid> through the descriptor that open returned, so the PID lands in the file
# this call created and never in one that replaced it at the same path. Status 0 on
# success, 1 (with bash's message on stderr) when the create failed, and 4 when the
# file was created but the PID write failed. Runs in its own subshell, so set -C and
# the C locale (which keeps bash's messages in the English godot_lock_take matches on)
# never reach the caller.
godot_lock_create() (
  LC_ALL=C
  set -C
  { echo "$2" >&3 || exit 4; } 3> "$1"
)

# godot_lock_take <lock>
#
# Creates <lock> holding this caller's PID. Returns 0 when this call created it, 1 when
# <lock> already exists (someone else holds it), and 2, with an ::error:: carrying the
# shell's own message, when the create failed for any other reason (a missing parent
# directory, no permission, a full or failing disk). Which it was is read from the
# create's own message, not from a test afterwards that a holder could change in
# between: "cannot overwrite existing file" (noclobber refused an existing path) or "Is
# a directory" (a directory lock) is held, and anything else is an error. So a lock that
# can never be taken fails at once instead of being waited on for the whole budget. A
# lock its holder released just after the create failed still reads as held: the
# caller waits a second and tries again.
#
# The create is bash's own noclobber redirect, so exactly one of any number of racing
# callers succeeds, on Linux and in Git Bash alike (which has no flock). Under noclobber
# bash stats the path first: an absent path is opened with O_CREAT|O_EXCL, so of two
# callers that both saw it absent only one creates it (the other gets EEXIST); an
# existing regular file is refused without being opened; and an existing non-regular
# path is opened without O_EXCL, which for a directory fails with EISDIR. So the create
# fails whenever the path is already a regular file, a directory, a symlink to either,
# or a dangling symlink (O_EXCL refuses any symlink). A FIFO or device there would be
# opened and written to instead; nothing ever puts one at a lock path.
#
# One window is left, and only while an older mkdir-based helper runs beside this one:
# if the old helper removes its directory lock between bash's stat and its open, that
# open (still O_CREAT, without O_EXCL) creates an empty regular file. Bash then sees a
# regular file where it saw a non-regular one, closes it, and reports "cannot overwrite
# existing file", so this call reads as held and the empty file is left at the lock
# path. Exclusion holds, since no caller took the lock, but every caller then waits on
# a PID-less lock until godot_lock_is_stale breaks it, about a minute later.
#
# The PID is written through the descriptor the create opened (see godot_lock_create).
# Until it lands the lock reads as PID-less, which godot_lock_is_stale allows for. If
# that write fails, the file is removed again and the call fails, rather than leaving
# an empty lock behind that every caller would wait a minute on; a remove that fails
# too is named in the ::error::.
#
# Not mkdir(1): its exit status is not a lock. uutils coreutils' mkdir, the default on
# Ubuntu 26.04 (and so on its CI runners), exits 0 for a directory another process
# created a moment earlier. Measured (uutils 0.8.0, 2026-11-02): five concurrent
# `mkdir d` calls had more than one report success in 24 of 100 rounds, against 0 of
# 100 for GNU mkdir, so two callers both took a mkdir lock and imported at once.
#
# BASHPID, not $$: callers backgrounded from one shell share its $$, and each needs its
# own identity here (bash 3.2 has no BASHPID and falls back to $$). It is read before
# the command substitution, whose own BASHPID would name its subshell.
godot_lock_take() {
  local lock="$1" me="${BASHPID:-$$}" err rc=0 rmerr
  err="$(godot_lock_create "$lock" "$me" 2>&1)" || rc=$?
  [ "$rc" -eq 0 ] && return 0
  if [ "$rc" -eq 4 ]; then
    if rmerr="$(rm -f "$lock" 2>&1)"; then
      echo "::error::godot-import-lock: created lock $lock but could not write its PID, so removed it again: $err" >&2
    else
      echo "::error::godot-import-lock: created lock $lock but could not write its PID ($err), and could not remove it either; remove it by hand: $rmerr" >&2
    fi
    return 2
  fi
  case "$err" in
    *"cannot overwrite existing file"* | *"Is a directory"*)
      return 1 ;;
  esac
  echo "::error::godot-import-lock: cannot create lock $lock: $err" >&2
  return 2
}

# godot_lock_holder <lock> -- prints the holder PID recorded in <lock>, or nothing when
# none is recorded (no lock, or no PID written yet). A directory at <lock> is a lock
# taken by an older version of this helper, which used mkdir locks and kept the PID in
# <lock>/pid. Reading it there means a live old-version holder is waited for like any
# other, and a dead one is broken at once.
#
# <lock> is read first, and only when that read fails with "Is a directory" is
# <lock>/pid read instead. Each read's own error says why it failed, so nothing is
# tested beforehand or afterwards that a holder could change in between. A file that is
# not there (ENOENT, or ENOTDIR for a directory lock replaced by a file) records no PID,
# even if a new holder creates it a moment later: the caller sees a fresh PID-less
# lock, waits, and reads it again. Any other read error is not "no PID", since that
# would let a live holder's lock be broken once it is a minute old: it fails with an
# ::error:: and status 2 instead. LC_ALL=C keeps the error in the English matched here.
godot_lock_holder() {
  local f="$1" out rc=0
  out="$(LC_ALL=C cat "$f" 2>&1)" || rc=$?
  if [ "$rc" -ne 0 ]; then
    case "$out" in
      *"Is a directory"*)
        f="$1/pid" rc=0
        out="$(LC_ALL=C cat "$f" 2>&1)" || rc=$? ;;
    esac
  fi
  if [ "$rc" -eq 0 ]; then
    printf '%s\n' "$out"
    return 0
  fi
  case "$out" in
    *"No such file or directory"* | *"Not a directory"*) return 0 ;;
  esac
  echo "::error::godot-import-lock: cannot read the holder PID in $f: ${out:-unknown error}" >&2
  return 2
}

# godot_lock_acquire <lock> <wait-secs>
#
# Atomic lock file (see godot_lock_take), holding its holder's PID. A lock is stale when
# its holder PID is no longer alive, or when it has no PID at all and is over a minute
# old (a holder killed between creating the file and writing its PID). A directory at
# <lock> is a lock left by a version of this helper that used mkdir locks, and its
# holder is read from <lock>/pid (see godot_lock_holder). An old-version caller never
# breaks a file lock: it reads no PID from one, so it treats it as PID-less, but it
# only ever removes a directory at <lock>. While the file is under a minute old it
# sleeps and counts toward its wait budget like for any held lock. Once the file is
# older it judges it stale, takes its breaker, finds no directory to remove, and
# retries at once without sleeping or counting: it spins, forking mkdir, cat and find
# on every pass, and never reaches its budget. It stops only when the file lock is
# released and it takes the lock, or when it is killed.
#
# Breaking a stale lock is itself serialised by a second lock file, <lock>.break.
# The one waiter holding it re-reads the PID and removes the lock only if it still names
# the same dead holder. Nothing else removes a dead holder's lock, so the lock cannot
# change between that re-read and the removal, and no waiter can delete a lock another
# waiter has just taken. A breaker killed mid-break leaves <lock>.break behind.
# That is never cleared automatically: two waiters that both saw it abandoned could
# both clear it and then break concurrently, which is the race the breaker exists to
# prevent. Once it is over a minute old this fails with an ::error:: naming the
# file to remove by hand.
#
# A live holder is waited for up to <wait-secs>, after which this fails loudly rather
# than importing under someone else's import. A lock or breaker that cannot be created
# at all (see godot_lock_take), a lock whose PID file cannot be read (see
# godot_lock_holder), or a stale lock that cannot be removed fails at once.
godot_lock_acquire() {
  local lock="$1" wait_secs="$2" waited=0 holder now rc out
  local breaker="$lock.break"
  while :; do
    rc=0
    godot_lock_take "$lock" || rc=$?
    [ "$rc" -eq 0 ] && return 0
    [ "$rc" -eq 1 ] || return 1
    holder="$(godot_lock_holder "$lock")" || return 1
    if godot_lock_is_stale "$lock" "$holder"; then
      rc=0
      godot_lock_take "$breaker" || rc=$?
      [ "$rc" -le 1 ] || return 1
      if [ "$rc" -eq 0 ]; then
        if ! now="$(godot_lock_holder "$lock")"; then
          godot_lock_drop_breaker "$breaker"
          return 1
        fi
        if [ "$now" = "$holder" ] && godot_lock_is_stale "$lock" "$now"; then
          if ! out="$(rm -rf "$lock" 2>&1)"; then
            echo "::error::godot-import-lock: cannot remove stale lock $lock (holder PID ${holder:-none} is gone): $out" >&2
            godot_lock_drop_breaker "$breaker"
            return 1
          fi
          echo "godot-import-lock: broke stale lock $lock (holder PID ${holder:-none} is gone)" >&2
        fi
        godot_lock_drop_breaker "$breaker" || return 1
        continue
      fi
      if [ -n "$(find "$breaker" -maxdepth 0 -mmin +1 2>/dev/null)" ]; then
        echo "::error::godot-import-lock: $breaker is over a minute old, so the waiter breaking $lock died mid-break; check no dump is running, then remove $breaker by hand" >&2
        return 1
      fi
      # Another waiter is breaking it: wait like for a live holder.
    fi
    if [ "$waited" -ge "$wait_secs" ]; then
      echo "::error::godot-import-lock: gave up after ${wait_secs}s waiting for $lock (holder PID ${holder:-unknown})" >&2
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
}

# godot_lock_drop_breaker <breaker> -- removes <breaker> (see godot_lock_acquire). A
# remove that fails returns 1 with an ::error:: carrying rm's message, so the caller
# fails now and names the cause, instead of a later waiter finding the breaker over a
# minute old and blaming a breaker that died mid-break.
godot_lock_drop_breaker() {
  local out
  out="$(rm -f "$1" 2>&1)" && return 0
  echo "::error::godot-import-lock: cannot remove breaker $1; remove it by hand: $out" >&2
  return 1
}

# godot_lock_is_stale <lock> <holder-pid-or-empty>
godot_lock_is_stale() {
  local lock="$1" holder="$2"
  if [ -n "$holder" ]; then
    ! kill -0 "$holder" 2>/dev/null
    return
  fi
  # No PID yet: stale only once the lock is old enough that its holder cannot still be
  # about to write one.
  [ -n "$(find "$lock" -maxdepth 0 -mmin +1 2>/dev/null)" ]
}

# godot_lock_release <lock>
#
# Removes <lock> only while it still names this caller's PID. If this caller's lock was
# broken and someone else now holds <lock>, a blind remove would delete their lock and
# let a third caller import alongside them, so the lock is left alone and a ::warning::
# says so; the same warning covers a lock already gone (broken and not retaken), which
# reads as naming no PID. A lock whose PID cannot be read is left in place as well, with
# godot_lock_holder's ::error::, and release still returns 0: the import is already
# over, and failing here would fail the caller over a lock it no longer needs. The read
# and the remove are two steps, and shell has no way to make them one: a lock broken
# and retaken between them would still be removed. That needs this caller's own live
# lock to be judged stale in that instant, which nothing here does. A remove of this
# caller's own lock that fails is named in a ::warning:: carrying rm's message, and
# release still returns 0; the lock left behind names a dead PID once this caller
# exits, so the next caller breaks it.
godot_lock_release() {
  local lock="$1" me="${BASHPID:-$$}" holder out
  holder="$(godot_lock_holder "$lock")" || return 0
  if [ "$holder" = "$me" ]; then
    out="$(rm -f "$lock" 2>&1)" ||
      echo "::warning::godot-import-lock: cannot remove lock $lock: $out" >&2
  else
    echo "::warning::godot-import-lock: $lock no longer names PID $me (it names ${holder:-no PID, or is gone}), so it was broken while held; not removing it" >&2
  fi
}

# godot_import_once <timeout-secs> <godot-bin> <project> <stamp-content>
#
# Runs `<godot-bin> --headless --import --path <project>` under run_bounded, holding the
# project's import lock, unless the import is already current (see
# godot_import_is_current), in which case it says so and does nothing. Pass an empty
# <stamp-content> when the Godot version is unknown: that always imports.
#
# The stamp is created BEFORE the import and only moved into place after it, so its mtime
# predates the import: a source edited while the import runs is newer than the stamp and
# is imported next time. Godot's output goes to .godot/sparta-import.log.
#
# Only a timeout (run_bounded's 124/137) fails the call: status 1, no stamp. Any other
# non-zero status, a signal death included, is not fatal: Godot's --import exit code is
# unreliable, and on Linux CI a headless import that aborts at exit (status 134) still
# leaves a cache the dumps run fine against. Such an import prints a ::warning:: with
# its status and the tail of the log, so the errors are no longer hidden, writes no
# stamp, so the next caller imports again rather than trusting it, and returns 0.
godot_import_once() {
  local secs="$1" godot="$2" project="$3" want="$4"
  local lock="$project/.godot/sparta-import.lock" rc=0
  local stamp log pending
  stamp="$(godot_import_stamp_path "$project")"
  log="$project/.godot/sparta-import.log"
  pending="$stamp.pending.${BASHPID:-$$}.$RANDOM"
  mkdir -p "$project/.godot"
  # Wait at most one import's budget plus slack for another run's import to finish.
  godot_lock_acquire "$lock" "$(( secs + 30 ))" || return 1
  if godot_import_is_current "$project" "$want"; then
    echo "godot-import-lock: import cache in $project is current; skipping --import" >&2
    godot_lock_release "$lock"
    return 0
  fi
  rm -f "$stamp"
  # >| rather than >: a caller running under set -C must not fail on last run's log.
  printf '%s' "$want" >| "$pending"
  run_bounded "$secs" "$godot" --headless --import --path "$project" >|"$log" 2>&1 || rc=$?
  if run_bounded_timed_out "$rc"; then
    rm -f "$pending"
    godot_lock_release "$lock"
    echo "::error::godot --import of $project timed out after ${secs}s and was killed (output: $log)" >&2
    return 1
  fi
  if [ "$rc" -ne 0 ]; then
    rm -f "$pending"
    godot_lock_release "$lock"
    echo "::warning::godot --import of $project exited with status $rc; no stamp written, so the next run imports again (last lines of $log follow)" >&2
    tail -n 20 "$log" | sed 's/^/  | /' >&2
    return 0
  fi
  mv "$pending" "$stamp"
  godot_lock_release "$lock"
  return 0
}
