#!/usr/bin/env bash
# Upsert a marker-tagged GitHub issue: if an OPEN issue carrying the marker
# exists, add a comment to it (so repeated failures thread onto one issue
# instead of spawning duplicates); otherwise open a new issue with the given
# title/body/labels. Mirrors upsert-pr-comment.sh's find-or-create shape, but
# for issues rather than PR comments -- there is no PR to comment on when a
# push-to-main job fails outside any pull request.
#
# Usage:
#   tools/ci/upsert-issue.sh <repo> <marker> <title> <body> <labels> [update-body]
#
#   <repo>         owner/name (e.g. lacaedemon/sparta)
#   <marker>       HTML-comment marker that identifies our issue (must appear
#                  in the issue body so re-runs can find it)
#   <title>        issue title, used only when creating
#   <body>         full issue body (may be multiline; must contain <marker>)
#   <labels>       comma-separated label list (passed straight to `gh issue
#                  create --label`), used only when creating
#   [update-body]  comment body to post when an existing open issue is found
#                  (default: reuse <body>)
#
# Requires the `gh` CLI authenticated (GH_TOKEN in the environment).
set -euo pipefail

if [ "$#" -lt 5 ]; then
  echo "Usage: $(basename "$0") <repo> <marker> <title> <body> <labels> [update-body]" >&2
  exit 1
fi

REPO="$1"
MARKER="$2"
TITLE="$3"
BODY="$4"
LABELS="$5"
UPDATE_BODY="${6:-$BODY}"

# Search OPEN issues only -- a resolved incident's issue is closed by
# upsert-issue-resolved.sh on the next green run, so a fresh failure after
# that opens a new issue rather than silently reopening an old closed one.
# The marker is passed to jq via --arg (not interpolated into the filter),
# matching upsert-pr-comment.sh, so a marker containing quotes can't break it.
IID=$(gh issue list --repo "$REPO" --state open --limit 100 --json number,body \
  | jq --raw-output --arg marker "$MARKER" \
      '.[] | select(.body // "" | contains($marker)) | .number' \
  | head -n1 || true)

if [ -n "$IID" ]; then
  gh issue comment "$IID" --repo "$REPO" --body "$UPDATE_BODY" >/dev/null
  echo "Commented on existing issue #${IID}"
else
  gh issue create --repo "$REPO" --title "$TITLE" --body "$BODY" --label "$LABELS" >/dev/null
  echo "Opened new issue"
fi
