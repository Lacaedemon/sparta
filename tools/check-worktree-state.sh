#!/usr/bin/env bash
# tools/check-worktree-state.sh -- report every worktree of this repository that
# is stale against the default branch, holds commits that exist on no remote, or
# keeps uncommitted work somewhere work should never be kept.
#
# Why this exists: a checkout can sit dozens of commits behind origin with staged
# entries committed nowhere and look completely ordinary. It is not mid-merge,
# mid-rebase, or mid-cherry-pick, so nothing announces it, and the state is
# invisible to any session that does not go looking. Two concrete hazards follow:
# a session obeying the standing freshness rule either fails to fast-forward or
# silently carries that staged set into unrelated work.
#
# The verdicts, in the order they are reported:
#
#   prunable    the worktree's directory is gone; the administrative entry is
#               stale. `git worktree prune` clears it.
#   stale       the worktree is on the DEFAULT branch and behind its remote
#               counterpart. Always actionable: fast-forward it. A feature
#               branch sitting behind the default branch is normal and is
#               reported without being flagged.
#   diverged    on the default branch with commits the remote default lacks --
#               a fast-forward will refuse, so this needs a human.
#   unpushed    commits reachable from HEAD that no remote ref contains. This is
#               the loss-bearing case: the content exists on one disk only.
#   misplaced   uncommitted entries in a DEFAULT-branch worktree. The default
#               branch is never where work is kept, so anything here is either
#               abandoned or about to be carried somewhere it does not belong.
#   dirty       uncommitted entries on a feature branch. Reported, and flagged
#               only under --strict, because this is exactly what a live session
#               looks like and flagging it by default would make every run red.
#
# Exit status is 0 when nothing is flagged and 1 when anything is, so this can
# gate a script; --warn-only keeps it at 0 either way.
#
# The summary line reports how many worktrees were EXAMINED alongside how many
# were flagged, so a clean run is distinguishable from a detector that silently
# examined nothing.
#
# Usage:
#   tools/check-worktree-state.sh [--strict] [--warn-only] [--json]
#
#   --strict     also flag uncommitted work on feature branches
#   --warn-only  always exit 0; report only
#   --json       emit one JSON object instead of the table
#
# Environment:
#   SPARTA_WORKTREE_REMOTE      remote to measure against (default: origin)
#   SPARTA_WORKTREE_STALE_MAX   commits a default-branch worktree may be behind
#                               before it counts as stale (default: 0)
set -uo pipefail

STRICT=0
WARN_ONLY=0
AS_JSON=0

while [ $# -gt 0 ]; do
  case "$1" in
    --strict) STRICT=1 ;;
    --warn-only) WARN_ONLY=1 ;;
    --json) AS_JSON=1 ;;
    # Print the whole leading comment block rather than a fixed line range:
    # a hard-coded range silently truncates the moment the header grows, and
    # the cut lands on whatever section happens to be last -- which is how the
    # Environment section went missing from --help. awk stops at the first
    # non-comment line, so the boundary is derived from the file itself.
    -h|--help) awk 'NR > 1 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "$0"; exit 0 ;;
    *) printf 'check-worktree-state: unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

REMOTE="${SPARTA_WORKTREE_REMOTE:-origin}"
STALE_MAX="${SPARTA_WORKTREE_STALE_MAX:-0}"

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  printf 'check-worktree-state: not inside a git repository\n' >&2
  exit 2
fi

# Resolve the default branch from the remote rather than assuming "main": a repo
# whose default is named otherwise would otherwise be measured against a ref
# that does not exist, and every worktree would read as clean.
resolve_default_branch() {
  local ref
  ref="$(git symbolic-ref --quiet "refs/remotes/$REMOTE/HEAD" 2>/dev/null)"
  if [ -n "$ref" ]; then
    printf '%s\n' "${ref##*/}"
    return 0
  fi
  ref="$(git ls-remote --symref "$REMOTE" HEAD 2>/dev/null | awk '/^ref:/ { print $2; exit }')"
  if [ -n "$ref" ]; then
    printf '%s\n' "${ref##*/}"
    return 0
  fi
  return 1
}

DEFAULT_BRANCH="$(resolve_default_branch)"
if [ -z "$DEFAULT_BRANCH" ]; then
  printf 'check-worktree-state: could not resolve the default branch of remote %s.\n' "$REMOTE" >&2
  printf '  Try: git remote set-head %s --auto\n' "$REMOTE" >&2
  exit 2
fi
DEFAULT_REF="$REMOTE/$DEFAULT_BRANCH"

if ! git rev-parse --verify --quiet "$DEFAULT_REF" >/dev/null; then
  printf 'check-worktree-state: %s is not present locally; run: git fetch %s\n' "$DEFAULT_REF" "$REMOTE" >&2
  exit 2
fi

# One number per measurement, and an empty reading is reported as empty rather
# than silently becoming 0 -- a failed count and a genuine zero are different
# facts, and conflating them is how a detector reports all-clear over a repo it
# could not read.
count_or_empty() {
  local out
  out="$( "$@" 2>/dev/null )"
  case "$out" in
    ''|*[!0-9]*) printf '' ;;
    *) printf '%s' "$out" ;;
  esac
}

EXAMINED=0
FLAGGED=0
ROWS=()
JSON_ITEMS=()

json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

emit() {
  # emit <path> <branch> <verdicts-csv> <behind> <ahead> <unpushed> <dirty> <staged>
  local path="$1" branch="$2" verdicts="$3" behind="$4" ahead="$5" unpushed="$6" dirty="$7" staged="$8"
  ROWS+=("$(printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s' \
    "${verdicts:-ok}" "$branch" "${behind:-?}" "${ahead:-?}" "${unpushed:-?}" "${dirty:-?}" "${staged:-?}" "$path")")
  JSON_ITEMS+=("$(printf '{"path":"%s","branch":"%s","verdicts":"%s","behind":%s,"ahead":%s,"unpushed":%s,"uncommitted":%s,"staged":%s}' \
    "$(json_escape "$path")" "$(json_escape "$branch")" "${verdicts:-ok}" \
    "${behind:-null}" "${ahead:-null}" "${unpushed:-null}" "${dirty:-null}" "${staged:-null}")")
}

wt_path=""
wt_branch=""
wt_prunable=0

flush_worktree() {
  [ -n "$wt_path" ] || return 0
  EXAMINED=$((EXAMINED + 1))

  local verdicts="" flagged=0
  local behind="" ahead="" unpushed="" dirty="" staged=""
  local branch_label="${wt_branch:-(detached)}"

  if [ "$wt_prunable" -eq 1 ] || [ ! -d "$wt_path" ]; then
    verdicts="prunable"
    flagged=1
  else
    behind="$(count_or_empty git -C "$wt_path" rev-list --count "HEAD..$DEFAULT_REF")"
    ahead="$(count_or_empty git -C "$wt_path" rev-list --count "$DEFAULT_REF..HEAD")"
    unpushed="$(count_or_empty git -C "$wt_path" rev-list --count HEAD --not --remotes)"
    dirty="$(git -C "$wt_path" status --porcelain 2>/dev/null | grep -c '^' || true)"
    staged="$(git -C "$wt_path" diff --cached --name-only HEAD 2>/dev/null | grep -c '^' || true)"

    local on_default=0
    [ "$wt_branch" = "$DEFAULT_BRANCH" ] && on_default=1

    if [ "$on_default" -eq 1 ] && [ -n "$behind" ] && [ "$behind" -gt "$STALE_MAX" ]; then
      verdicts="${verdicts:+$verdicts,}stale"
      flagged=1
    fi
    if [ "$on_default" -eq 1 ] && [ -n "$ahead" ] && [ "$ahead" -gt 0 ]; then
      verdicts="${verdicts:+$verdicts,}diverged"
      flagged=1
    fi
    if [ -n "$unpushed" ] && [ "$unpushed" -gt 0 ]; then
      verdicts="${verdicts:+$verdicts,}unpushed"
      flagged=1
    fi
    if [ "${dirty:-0}" -gt 0 ]; then
      if [ "$on_default" -eq 1 ]; then
        verdicts="${verdicts:+$verdicts,}misplaced"
        flagged=1
      else
        verdicts="${verdicts:+$verdicts,}dirty"
        [ "$STRICT" -eq 1 ] && flagged=1
      fi
    fi
  fi

  [ "$flagged" -eq 1 ] && FLAGGED=$((FLAGGED + 1))
  emit "$wt_path" "$branch_label" "$verdicts" "$behind" "$ahead" "$unpushed" "$dirty" "$staged"

  wt_path=""
  wt_branch=""
  wt_prunable=0
}

while IFS= read -r line; do
  case "$line" in
    'worktree '*) flush_worktree; wt_path="${line#worktree }" ;;
    'branch refs/heads/'*) wt_branch="${line#branch refs/heads/}" ;;
    'prunable'*) wt_prunable=1 ;;
    'detached') wt_branch="" ;;
  esac
done < <(git worktree list --porcelain)
flush_worktree

if [ "$AS_JSON" -eq 1 ]; then
  printf '{"remote":"%s","default_branch":"%s","examined":%s,"flagged":%s,"worktrees":[' \
    "$(json_escape "$REMOTE")" "$(json_escape "$DEFAULT_BRANCH")" "$EXAMINED" "$FLAGGED"
  sep=""
  for item in ${JSON_ITEMS+"${JSON_ITEMS[@]}"}; do
    printf '%s%s' "$sep" "$item"
    sep=","
  done
  printf ']}\n'
else
  printf 'Worktree state vs %s (default branch: %s)\n\n' "$DEFAULT_REF" "$DEFAULT_BRANCH"
  {
    printf 'VERDICT\tBRANCH\tBEHIND\tAHEAD\tUNPUSHED\tDIRTY\tSTAGED\tPATH\n'
    for row in ${ROWS+"${ROWS[@]}"}; do
      printf '%s\n' "$row"
    done
  } | column -t -s "$(printf '\t')" 2>/dev/null || {
    printf 'VERDICT\tBRANCH\tBEHIND\tAHEAD\tUNPUSHED\tDIRTY\tSTAGED\tPATH\n'
    for row in ${ROWS+"${ROWS[@]}"}; do printf '%s\n' "$row"; done
  }
  printf '\nExamined %s worktree(s); flagged %s.\n' "$EXAMINED" "$FLAGGED"
  if [ "$FLAGGED" -gt 0 ]; then
    printf 'Remedies: prunable -> git worktree prune; stale -> git merge --ff-only %s;\n' "$DEFAULT_REF"
    printf '  unpushed -> push the branch; misplaced -> commit it to a branch and push before cleaning up.\n'
  fi
fi

if [ "$WARN_ONLY" -eq 1 ]; then
  exit 0
fi
[ "$FLAGGED" -eq 0 ]