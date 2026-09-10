# tools/lib/demo-catalog-selection.sh -- shared helper: narrow a catalog walk to the
# clips SPARTA_DUMP_CLIPS names, and refuse a narrowing that would select nothing.
#
# Sourced by website/tools/dump-demo-states.sh and tools/ci/website-demo-defect-sweep.sh
# from the tree the SCRIPT lives in, never from the tree whose catalog is being walked:
# the demo diff dumps the merge-base tree with the PR's dump script, and that tree's
# demo-catalog.sh may predate these helpers. Keeping them here (rather than inside the
# catalog) means the script always finds them, whichever catalog it loaded. Reads the
# DEMOS array the catalog defines; not executable on its own.

# demo_catalog_selected <clip-name> <selection>
#
# True when <selection> (a comma-separated list of clip names, e.g. the
# SPARTA_DUMP_CLIPS environment variable) is empty or names the clip. Whitespace
# around a name is ignored, so "a, b" selects both. Both catalog consumers narrow their
# row loop through this one predicate, so a narrowed dump and the sweep judging it agree
# on which rows exist: a clip the dump skipped is not a "no transcript" finding when the
# sweep was narrowed the same way.
demo_catalog_selected() {
  local want="$1" selection="$2" name
  local -a names
  [ -n "$selection" ] || return 0
  IFS=',' read -r -a names <<<"$selection"
  for name in "${names[@]}"; do
    name="${name#"${name%%[![:space:]]*}"}"
    name="${name%"${name##*[![:space:]]}"}"
    [ "$name" = "$want" ] && return 0
  done
  return 1
}

# demo_catalog_check_selection <selection>
#
# Fails (exit 1, saying why on stderr) when <selection> names a clip the catalog does
# not have, or is non-empty yet names nothing at all ("," or whitespace). Either would
# otherwise select nothing, and a dump or sweep of nothing exits 0 with an empty tree --
# the one outcome a diagnostic dispatch cannot tell from "the clip was dumped and is
# clean". Call it once, before the row loop.
demo_catalog_check_selection() {
  local selection="$1" name spec catalog_name unknown="" named=0
  local -a names
  [ -n "$selection" ] || return 0
  IFS=',' read -r -a names <<<"$selection"
  for name in "${names[@]}"; do
    name="${name#"${name%%[![:space:]]*}"}"
    name="${name%"${name##*[![:space:]]}"}"
    # A stray comma ("a,,b", "a,") yields an empty name; that is not a misspelt clip.
    [ -n "$name" ] || continue
    named=$((named + 1))
    for spec in "${DEMOS[@]}"; do
      catalog_name="${spec%%|*}"
      [ "$catalog_name" = "$name" ] && continue 2
    done
    unknown="$unknown $name"
  done
  if [ "$named" -eq 0 ]; then
    echo "error: SPARTA_DUMP_CLIPS is set but names no clip (unset it to select every row)" >&2
    return 1
  fi
  [ -z "$unknown" ] && return 0
  echo "error: SPARTA_DUMP_CLIPS names clips not in website/tools/demo-catalog.sh:$unknown" >&2
  return 1
}
