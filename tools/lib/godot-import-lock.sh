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
# when the cache is already current for this tree and this Godot, so of N parallel runs
# the first imports and the rest wait for it and then skip.

# godot_import_stamp_path <project> -- the stamp godot_import_once writes after a
# completed import. It lives inside .godot/, so wiping the cache wipes the stamp too.
godot_import_stamp_path() {
  printf '%s/.godot/sparta-import.stamp\n' "$1"
}

# godot_import_is_current <project> <stamp-content>
#
# True when the stamp exists, records the same content (the Godot binary and version),
# and nothing Godot would import is newer than it. "Would import" follows Godot's own
# filesystem scan: hidden paths (.godot/, .git, .claude/ and the worktrees under it) and
# any directory holding a .gdignore (website/, where the dumps themselves land by
# default) are skipped, so a dump writing its transcripts never invalidates the stamp.
# Directories are included, so a deleted or renamed file (which only touches its parent
# directory's mtime) still counts as a change.
godot_import_is_current() {
  local project="$1" want="$2" stamp
  stamp="$(godot_import_stamp_path "$project")"
  [ -f "$stamp" ] || return 1
  [ "$(cat "$stamp")" = "$want" ] || return 1
  local prune=( -name '.*' ! -path "$project" ) g newer
  while IFS= read -r g; do
    prune+=( -o -path "${g%/.gdignore}" )
  # .gdignore is itself a dot-file, so it is exempted from the hidden-path prune here.
  done < <(find "$project" \( -name '.*' ! -name .gdignore ! -path "$project" \) -prune \
    -o -name .gdignore -print)
  newer="$(find "$project" \( "${prune[@]}" \) -prune -o -newer "$stamp" -print -quit)"
  [ -z "$newer" ]
}

# godot_lock_acquire <lockdir> <wait-secs>
#
# Atomic mkdir lock (mkdir is atomic on every platform this runs on, and Git Bash has no
# flock). The holder's PID goes in <lockdir>/pid. A lock whose holder is no longer alive
# is broken at once, with a message; a live holder is waited for up to <wait-secs>, after
# which this fails loudly rather than importing under someone else's import.
godot_lock_acquire() {
  local lockdir="$1" wait_secs="$2" waited=0 holder
  while ! mkdir "$lockdir" 2>/dev/null; do
    holder="$(cat "$lockdir/pid" 2>/dev/null || true)"
    if [ -n "$holder" ] && ! kill -0 "$holder" 2>/dev/null; then
      echo "godot-import-lock: breaking stale lock $lockdir (holder PID $holder is gone)" >&2
      rm -rf "$lockdir"
      continue
    fi
    if [ "$waited" -ge "$wait_secs" ]; then
      echo "::error::godot-import-lock: gave up after ${wait_secs}s waiting for $lockdir (holder PID ${holder:-unknown})" >&2
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done
  echo "$$" > "$lockdir/pid"
}

# godot_lock_release <lockdir>
godot_lock_release() {
  rm -rf "$1"
}

# godot_import_once <timeout-secs> <godot-bin> <project> <stamp-content>
#
# Runs `<godot-bin> --headless --import --path <project>` under run_bounded, holding the
# project's import lock, unless the import is already current (see
# godot_import_is_current), in which case it says so and does nothing. A completed import
# writes the stamp; an import killed by the timeout fails (status 1) and writes none.
# Godot's own exit status from --import is unreliable, so it is not consulted.
godot_import_once() {
  local secs="$1" godot="$2" project="$3" want="$4"
  local lockdir="$project/.godot/sparta-import.lock" rc=0
  mkdir -p "$project/.godot"
  # Wait at most one import's budget plus slack for another run's import to finish.
  godot_lock_acquire "$lockdir" "$(( secs + 30 ))" || return 1
  if godot_import_is_current "$project" "$want"; then
    echo "godot-import-lock: import cache in $project is current; skipping --import" >&2
    godot_lock_release "$lockdir"
    return 0
  fi
  run_bounded "$secs" "$godot" --headless --import --path "$project" >/dev/null 2>&1 || rc=$?
  if run_bounded_timed_out "$rc"; then
    godot_lock_release "$lockdir"
    echo "::error::godot --import of $project timed out after ${secs}s and was killed" >&2
    return 1
  fi
  printf '%s' "$want" > "$(godot_import_stamp_path "$project")"
  godot_lock_release "$lockdir"
  return 0
}
