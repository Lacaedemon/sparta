#!/usr/bin/env bash
# Decide whether a pull request needs the instrumented coverage run (#1963).
#
# The coverage run takes 30 to 45+ minutes. A diff that touches only documentation, the
# website, agent notes or workflows unrelated to the run cannot change a test result or
# the patch-coverage verdict, so the run is skipped for it.
#
# The rule is an allowlist of paths that cannot matter, not a list of paths that do:
# a new top-level directory (a scene, data file, script, addon, tool) counts as relevant
# until someone decides otherwise, so the gate stays safe as the repo grows. It also
# fails open: if the diff cannot be computed, the run is needed.
#
# Skippable paths: *.md, *.qmd, docs/**, website/**, demos/**, benchmarks/**,
# .claude/**, and .github/** except the coverage workflow and the Godot setup action
# the run uses.
#
# Usage: tools/ci/coverage-needed.sh <base-ref>
# Output: "needed=true" or "needed=false" on stdout (append to $GITHUB_OUTPUT), and the
#         reason on stderr.
# Exit:   0 always, except 2 on a usage error.
set -uo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: $0 <base-ref>" >&2
  exit 2
fi
base="$1"

if ! files="$(git diff --name-only "$base"...HEAD)"; then
  echo "cannot diff against $base; running coverage" >&2
  echo "needed=true"
  exit 0
fi

while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in
    .github/workflows/test-coverage.yml|.github/actions/setup-godot-project/*) ;;
    .github/*|.claude/*|docs/*|website/*|demos/*|benchmarks/*|*.md|*.qmd)
      continue ;;
  esac
  echo "$f is relevant to the coverage run; running coverage" >&2
  echo "needed=true"
  exit 0
done <<< "$files"

echo "no changed path can affect the coverage run; skipping it" >&2
echo "needed=false"
