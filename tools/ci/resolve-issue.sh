#!/usr/bin/env bash
# Close the marker-tagged tracking issue opened by upsert-issue.sh, if one is
# still open. Called on a GREEN post-merge run so a fixed CI-on-main incident
# doesn't sit open forever waiting for a human to notice and close it by hand.
# A no-op (exit 0) when no matching open issue exists -- most green runs have
# nothing to resolve, and that's expected, not an error.
#
# Usage:
#   tools/ci/resolve-issue.sh <repo> <marker> <search-label> <comment>
#
#   <repo>          owner/name (e.g. lacaedemon/sparta)
#   <marker>        HTML-comment marker identifying the issue (see upsert-issue.sh)
#   <search-label>  same search-scope label passed to upsert-issue.sh, so this
#                    looks at the same bounded candidate set (see that script's
#                    header for why an unscoped search is unsafe on a busy tracker)
#   <comment>       closing comment body (e.g. links the green run)
#
# Requires the `gh` CLI authenticated (GH_TOKEN in the environment).
set -euo pipefail

if [ "$#" -lt 4 ]; then
  echo "Usage: $(basename "$0") <repo> <marker> <search-label> <comment>" >&2
  exit 1
fi

REPO="$1"
MARKER="$2"
SEARCH_LABEL="$3"
COMMENT="$4"

IID=$(gh issue list --repo "$REPO" --state open --label "$SEARCH_LABEL" --limit 100 --json number,body \
  | jq --raw-output --arg marker "$MARKER" \
      '.[] | select(.body // "" | contains($marker)) | .number' \
  | head -n1 || true)

if [ -n "$IID" ]; then
  gh issue close "$IID" --repo "$REPO" --comment "$COMMENT" >/dev/null
  echo "Closed resolved issue #${IID}"
else
  echo "No open tracking issue to close"
fi
