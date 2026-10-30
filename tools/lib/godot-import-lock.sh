# tools/lib/godot-import-lock.sh -- shared helper: import a Godot project at most once
# per source change, under a per-project lock.
#
# Sourced by website/tools/dump-demo-states.sh (after tools/lib/run-bounded.sh, whose
# run_bounded / run_bounded_timed_out this builds on); not executable on its own.
#
# Why (#1882): every dump-demo-states.sh run used to start with its own unguarded
# `godot --headless --import`, so N dumps started in parallel against one project ran N
# imports at once. Measured on Windows (Godot 4.7, 2026-10-30): 8 concurrent imports of
# a project with no .godot/ cache, 5 rounds, logged errors in 34 of 40 imports ("Cannot
# open file 'res://.godot/imported/...'", "Condition f.is_null()"), and rewrote six
# TRACKED assets/**/*.import sidecars with default import params and fresh UIDs, plus a
# stray *.import~RF*.TMP file. Warm imports (cache already built) did not collide in 80
# tries, but they still rewrite .godot/global_script_class_cache.cfg, uid_cache.bin and
# editor/filesystem_cache10 on every run, so they are pure churn under a running dump.
#
# godot_import_once serialises the import behind a per-project mkdir lock and skips it
# when the cache is already current for this tree and this Godot, so N parallel runs
# never import at the same time and a warm project is not re-imported at all. A cold
# project imports twice, one after the other: the first import writes new *.import
# sidecars after the stamp's (pre-import) mtime, so the next caller imports once more,
# and every caller after that skips. Measured: 16 staggered dense dumps x 8, cold start,
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
  while IFS= read -r g; do
    [ -n "$g" ] && prune+=( -o -path "${g%/.gdignore}" )
  done <<<"$ignores"
  newer="$(find "$project" \( "${prune[@]}" \) -prune -o -newer "$stamp" -print)" || return 1
  [ -z "$newer" ]
}

# godot_lock_acquire <lockdir> <wait-secs>
#
# Atomic mkdir lock (mkdir is atomic on every platform this runs on, and Git Bash has no
# flock). The holder's PID goes in <lockdir>/pid. A lock is stale when its holder PID is
# no longer alive, or when it has no PID at all and is over a minute old (a holder killed
# between its mkdir and its PID write). A stale lock is broken with a message: it is first
# renamed to a name unique to this caller, which only one breaker can win, and the
# renamed copy is checked to be the stale lock that was read -- so two waiters can never
# both break it, and a breaker that loses the race never deletes the winner's fresh lock.
# A live holder is waited for up to <wait-secs>, after which this fails loudly rather
# than importing under someone else's import.
godot_lock_acquire() {
  local lockdir="$1" wait_secs="$2" waited=0 holder grave
  while ! mkdir "$lockdir" 2>/dev/null; do
    holder="$(cat "$lockdir/pid" 2>/dev/null || true)"
    if godot_lock_is_stale "$lockdir" "$holder"; then
      grave="$lockdir.stale.${BASHPID:-$$}.$RANDOM"
      if mv "$lockdir" "$grave" 2>/dev/null; then
        if [ "$(cat "$grave/pid" 2>/dev/null || true)" = "$holder" ]; then
          echo "godot-import-lock: broke stale lock $lockdir (holder PID ${holder:-none} is gone)" >&2
          rm -rf "$grave"
          continue
        fi
        # The lock was replaced between the read and the rename: put the new holder's
        # lock back. If that cannot be done, stop rather than run two imports at once.
        # (The existence check comes first because mv onto an existing directory would
        # move the lock INSIDE it instead of failing.)
        if [ -e "$lockdir" ] || ! mv "$grave" "$lockdir" 2>/dev/null; then
          echo "::error::godot-import-lock: lost a race breaking $lockdir and could not restore it" >&2
          return 1
        fi
      fi
      continue
    fi
    if [ "$waited" -ge "$wait_secs" ]; then
      echo "::error::godot-import-lock: gave up after ${wait_secs}s waiting for $lockdir (holder PID ${holder:-unknown})" >&2
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  # BASHPID, not $$: callers backgrounded from one shell share its $$, and each needs
  # its own identity here (bash 3.2 has no BASHPID and falls back to $$).
  echo "${BASHPID:-$$}" > "$lockdir/pid"
}

# godot_lock_is_stale <lockdir> <holder-pid-or-empty>
godot_lock_is_stale() {
  local lockdir="$1" holder="$2"
  if [ -n "$holder" ]; then
    ! kill -0 "$holder" 2>/dev/null
    return
  fi
  # No PID yet: stale only once the lock is old enough that its holder cannot still be
  # about to write one.
  [ -n "$(find "$lockdir" -maxdepth 0 -mmin +1 2>/dev/null)" ]
}

# godot_lock_release <lockdir>
godot_lock_release() {
  rm -rf "$1"
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
# Fails (status 1, no stamp) when the import is killed by the timeout, or dies on a signal
# (status 128 or more -- a crash). Any other non-zero status is not trusted either way:
# Godot's --import exit code is unreliable, so a plain non-zero is not treated as failure.
godot_import_once() {
  local secs="$1" godot="$2" project="$3" want="$4"
  local lockdir="$project/.godot/sparta-import.lock" rc=0
  local stamp log pending
  stamp="$(godot_import_stamp_path "$project")"
  log="$project/.godot/sparta-import.log"
  pending="$stamp.pending.${BASHPID:-$$}.$RANDOM"
  mkdir -p "$project/.godot"
  # Wait at most one import's budget plus slack for another run's import to finish.
  godot_lock_acquire "$lockdir" "$(( secs + 30 ))" || return 1
  if godot_import_is_current "$project" "$want"; then
    echo "godot-import-lock: import cache in $project is current; skipping --import" >&2
    godot_lock_release "$lockdir"
    return 0
  fi
  rm -f "$stamp"
  printf '%s' "$want" > "$pending"
  run_bounded "$secs" "$godot" --headless --import --path "$project" >"$log" 2>&1 || rc=$?
  if run_bounded_timed_out "$rc"; then
    rm -f "$pending"
    godot_lock_release "$lockdir"
    echo "::error::godot --import of $project timed out after ${secs}s and was killed (output: $log)" >&2
    return 1
  fi
  if [ "$rc" -ge 128 ]; then
    rm -f "$pending"
    godot_lock_release "$lockdir"
    echo "::error::godot --import of $project died with status $rc (output: $log)" >&2
    return 1
  fi
  mv "$pending" "$stamp"
  godot_lock_release "$lockdir"
  return 0
}
