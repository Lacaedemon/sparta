#!/usr/bin/env bash
# Unit test for tools/ci/coverage-needed.sh, run against a throwaway git repo.
#
#   1. docs-only, website-only and agent-notes-only diffs skip the run
#   2. an unrelated workflow edit skips it; the coverage workflow and setup action do not
#   3. scripts/*.gd, test/*, scenes, project.godot, an unknown new top-level path need it
#   4. one relevant file among skippable ones needs it
#   5. benchmarks, a .qmd outside website/, scripts/README.md skip; demos/ needs it
#   6. a rename from scripts/ into docs/ needs it
#   7. an empty diff skips; an unresolvable base fails open (needed=true)
#
# No network. Run by tools/check.sh's shell_tests check.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NEEDED="$(cd "$SCRIPT_DIR/../../ci" && pwd)/coverage-needed.sh"
FAILURES=0

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
git init -q -b main .
git config user.email t@example.com
git config user.name t
echo seed > seed.txt
git add . && git commit -qm seed

# Verdict for a branch that changes the given paths on top of main.
verdict() {
  git checkout -q -B topic main
  local p
  for p in "$@"; do
    mkdir -p "$(dirname "$p")"
    echo "$RANDOM" > "$p"
  done
  git add -A && git commit -qm change --allow-empty
  "$NEEDED" main 2>/dev/null
}

expect() {
  local label="$1" want="$2"
  shift 2
  local got
  got="$(verdict "$@")"
  if [ "$got" = "needed=$want" ]; then
    echo "ok: $label"
  else
    echo "FAIL: $label: want needed=$want, got '$got'"
    FAILURES=$((FAILURES + 1))
  fi
}

expect "README only" false README.md
expect "docs and website" false docs/a.md website/index.qmd website/x.html
expect "agent notes" false .claude/memories/x.txt
expect "unrelated workflow" false .github/workflows/lint.yml
expect "coverage workflow" true .github/workflows/test-coverage.yml
expect "setup action" true .github/actions/setup-godot-project/action.yml
expect "gdscript" true scripts/units/unit.gd
expect "test" true test/unit/test_a.gd
expect "scene" true scenes/main.tscn
expect "project.godot" true project.godot
expect "check.sh" true tools/check.sh
expect "unknown new top-level path" true newdir/thing.dat
expect "docs plus one script" true docs/a.md scripts/a.gd
expect "empty diff" false
expect "benchmarks" false benchmarks/x.txt
expect "qmd outside website" false notes/a.qmd
expect "scripts README" false scripts/README.md
expect "demos inputs" true demos/inputs/a.json
expect "other .github file" false .github/ISSUE_TEMPLATE/a.yml

# A rename from a relevant path into a skippable one lists both paths.
git checkout -q -B topic main
mkdir -p scripts
echo 1 > scripts/moved.gd
git add -A && git commit -qm base
git checkout -q -B topic2 topic
mkdir -p docs
git mv scripts/moved.gd docs/moved.md
git commit -qm rename
got="$("$NEEDED" topic 2>/dev/null)"
if [ "$got" = "needed=true" ]; then echo "ok: rename out of scripts/"; else echo "FAIL: rename: '$got'"; FAILURES=$((FAILURES + 1)); fi

git checkout -q -B topic main
got="$("$NEEDED" no-such-ref 2>/dev/null)"
if [ "$got" = "needed=true" ]; then echo "ok: bad base fails open"; else echo "FAIL: bad base: '$got'"; FAILURES=$((FAILURES + 1)); fi

rc=0
"$NEEDED" >/dev/null 2>&1 || rc=$?
if [ "$rc" = "2" ]; then echo "ok: usage exit"; else echo "FAIL: usage exit: $rc"; FAILURES=$((FAILURES + 1)); fi

if [ "$FAILURES" -ne 0 ]; then echo "$FAILURES failure(s)"; exit 1; fi
echo "all passed"
