#!/usr/bin/env bash
# Decide whether a pull request needs the instrumented coverage run.
#
# The coverage run takes 30 to 45+ minutes. The run is a superset of the plain test run,
# so it may be skipped only for a diff that cannot change any file the suite reads or
# the patch-coverage verdict: documentation, the website, benchmarks, agent notes and
# workflows unrelated to the run.
#
# The rule is an allowlist of paths that cannot matter, not a list of paths that do:
# a new top-level directory (a scene, data file, script, addon, tool) counts as relevant
# until someone decides otherwise, so the gate stays safe as the repo grows. It also
# fails open: if the diff cannot be computed, the run is needed.
#
# Skippable paths: *.md, *.qmd, docs/**, website/**, benchmarks/**,
# .claude/**, and .github/** except the coverage workflow and the Godot setup action
# the run uses. demos/ is not skippable: GUT tests and Battle.gd read demos/inputs.
#
# Renames are listed as a delete plus an add (--no-renames), so moving a file out of a
# relevant path into a skippable one still counts as touching the relevant path.
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

if ! files="$(git diff --no-renames --name-only "$base"...HEAD)"; then
  echo "cannot diff against $base; running coverage" >&2
  echo "needed=true"
  exit 0
fi

while IFS= read -r f; do
  [ -z "$f" ] && continue
  case "$f" in
    .github/workflows/test-coverage.yml|.github/actions/setup-godot-project/*) ;;
    .github/*|.claude/*|docs/*|website/*|benchmarks/*|*.md|*.qmd)
      continue ;;
  esac
  echo "$f is relevant to the coverage run; running coverage" >&2
  echo "needed=true"
  exit 0
done <<< "$files"

echo "no changed path can affect the coverage run; skipping it" >&2
echo "needed=false"
