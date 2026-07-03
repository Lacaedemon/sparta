#!/usr/bin/env bash
# Upsert a marker-tagged section inside a PR's description (body), rather than
# posting a comment: replace the content between <marker-open>/<marker-close>
# if both are already present, else append a new marked section to the end of
# whatever the author already wrote. Mirrors upsert-pr-comment.sh's find-and-
# update shape, but targets the PR body via the REST API's `PATCH /pulls/{id}`
# instead of the issue-comments endpoint -- there is exactly one body, so
# "find" means "look for the marker pair inside it", not "search a list".
#
# Usage:
#   tools/ci/upsert-pr-body-section.sh <repo> <pr-number> <marker-open> <marker-close> <section-body> [label]
#
#   <repo>          owner/name (e.g. lacaedemon/sparta)
#   <pr-number>     PR number whose description to edit
#   <marker-open>   HTML-comment marker that opens our section (e.g. "<!-- sparta-demo -->")
#   <marker-close>  HTML-comment marker that closes our section (e.g. "<!-- /sparta-demo -->")
#   <section-body>  the content to place BETWEEN the markers (markers are added by this script,
#                    not included in this argument)
#   [label]         optional noun used in the log line (default: "PR body section")
#
# Requires the `gh` CLI authenticated via GH_TOKEN in the environment, plus `awk`
# and `jq`.
#
# Uses `jq -Rs '{body: .}' | gh api --input -` (a pre-built JSON payload piped via
# stdin) rather than `gh pr edit --body-file`, which has been observed to silently
# no-op on at least one Windows/Git Bash setup. NOTE: `gh api -f body=@-` looks like
# it should also read the field value from stdin (by analogy with `--body-file -`
# elsewhere in the gh CLI), but it does NOT -- confirmed empirically against gh
# 2.52.0: it sets the literal 3-character string "@-" as the field value, no error,
# no warning. `-f`/`-F` only support `@filename` for a field value; `@-` is not a
# recognized stdin sentinel for them. Only `--input -` (a full pre-built request
# body) honors `-` as stdin. This is exactly the kind of silent-no-op CI hazard
# CLAUDE.md's push_error/exit-code note warns about, which is why this script
# reads the body back afterward and fails loudly if it doesn't match.
set -euo pipefail

if [ "$#" -lt 5 ]; then
  echo "Usage: $(basename "$0") <repo> <pr-number> <marker-open> <marker-close> <section-body> [label]" >&2
  exit 1
fi

REPO="$1"
PR="$2"
MARKER_OPEN="$3"
MARKER_CLOSE="$4"
SECTION_BODY="$5"
LABEL="${6:-PR body section}"

CURRENT_BODY=$(gh api "repos/${REPO}/pulls/${PR}" --jq '.body // ""')

# Build the full replacement section (markers + content) once, so both the
# replace and append paths below insert byte-identical text.
SECTION=$(printf '%s\n%s\n%s' "$MARKER_OPEN" "$SECTION_BODY" "$MARKER_CLOSE")

# awk state machine: copy every line outside the marker pair verbatim; on
# hitting MARKER_OPEN, splice in the new section and skip through the old
# one's lines (including the old MARKER_CLOSE) without emitting them. Exact
# string match on the whole line (awk's == on $0), not a substring/regex
# search, so a marker that happens to contain regex metacharacters can't
# misbehave and a line merely mentioning the marker text mid-sentence can't
# false-positive. Markers and content are passed as awk -v vars (never
# interpolated into the program text), so their contents can't be
# interpreted as awk source. Variables are named open_m/close_m/section_v
# (not open/close/section) because gawk reserves `close` as a builtin
# function name -- `-v close=...` fails with "cannot use gawk builtin
# `close` as variable name".
MODE_FILE=$(mktemp)
trap 'rm -f "$MODE_FILE"' EXIT
NEW_BODY=$(printf '%s' "$CURRENT_BODY" | awk \
  -v open_m="$MARKER_OPEN" -v close_m="$MARKER_CLOSE" -v section_v="$SECTION" '
    BEGIN { in_section = 0; replaced = 0 }
    $0 == open_m {
      print section_v
      in_section = 1
      replaced = 1
      next
    }
    in_section && $0 == close_m { in_section = 0; next }
    in_section { next }
    { print }
    END { print (replaced ? "REPLACED" : "APPENDED") > "/dev/stderr" }
  ' 2>"$MODE_FILE")

MODE=$(cat "$MODE_FILE" 2>/dev/null || echo "APPENDED")

if [ "$MODE" != "REPLACED" ]; then
  # No existing marker pair (first run, or a body with no markers at all) --
  # append the new section after whatever the author already wrote, separated
  # by a blank line so it doesn't run into their last paragraph. An empty
  # original body (a PR opened with `gh pr create` and no --body) is handled
  # the same way: the leading blank line is harmless.
  NEW_BODY=$(printf '%s\n\n%s' "$CURRENT_BODY" "$SECTION")
fi

# Build the request body as JSON with jq (-R raw input, -s slurp the whole
# stdin into one string) so quotes/backslashes/newlines in NEW_BODY are
# escaped correctly, then pipe that JSON to `gh api --input -`. This is the
# reliable path for a large/multiline body; see the note above on why
# `-f body=@-` is NOT equivalent despite looking like it should be.
printf '%s' "$NEW_BODY" | jq -Rs '{body: .}' | gh api -X PATCH "repos/${REPO}/pulls/${PR}" --input - >/dev/null

# Verify the write actually landed by reading the body back, rather than
# trusting the PATCH's exit code (CLAUDE.md: push_error-style silent no-ops
# are a known hazard for CI steps in this repo).
VERIFY_BODY=$(gh api "repos/${REPO}/pulls/${PR}" --jq '.body // ""')
if [ "$VERIFY_BODY" != "$NEW_BODY" ]; then
  echo "::error::PR body update did not take effect -- read-back does not match what was written." >&2
  exit 1
fi

if [ "$MODE" = "REPLACED" ]; then
  echo "Replaced ${LABEL} in PR #${PR} description"
else
  echo "Appended ${LABEL} to PR #${PR} description"
fi
