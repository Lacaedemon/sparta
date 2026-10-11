#!/usr/bin/env bash
# Self-contained unit test for tools/ci/check-own-blob-links.sh, run against a throwaway
# git repo:
#
#   1. links to a tracked file, a tracked directory, and a file with a #L12 fragment
#      all pass (exit 0)
#   2. a link inside a Markdown code span is ignored, even to a missing path
#   3. a link to a path that is not tracked fails (exit 1) and the report names the
#      file, the line and the URL; the other links in the same file do not hide it
#   4. a link to a file that exists on disk but is untracked also fails
#   5. an external github.com link and a non-main ref are not this script's concern
#
# No network. Needs only git, awk and xargs.
#
# Run by tools/check.sh's shell_tests check, alongside every other tools/lib/tests/test-*.sh.
#
# Usage: tools/lib/tests/test-check-own-blob-links.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
CHECK="$REPO_ROOT/tools/ci/check-own-blob-links.sh"

FAILURES=0

assert_eq() {
  local label="$1" want="$2" got="$3"
  if [ "$want" != "$got" ]; then
    echo "FAIL: $label: want '$want', got '$got'"
    FAILURES=$((FAILURES + 1))
  else
    echo "ok: $label"
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  case "$haystack" in
    *"$needle"*) echo "ok: $label" ;;
    *) echo "FAIL: $label: '$needle' not in output:"; echo "$haystack"; FAILURES=$((FAILURES + 1)) ;;
  esac
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cd "$TMP"
git init -q .
git config user.email t@example.invalid
git config user.name t
mkdir -p scripts docs
echo x > scripts/Unit.gd
echo x > docs/a.md

B='https://github.com/Lacaedemon/sparta'
cat > good.md <<EOF
[file]($B/blob/main/scripts/Unit.gd), [dir]($B/tree/main/scripts),
[frag]($B/blob/main/scripts/Unit.gd#L12), and $B/blob/main/docs/a.md.
Code span, ignored: \`[x]($B/blob/main/nope/in-code-span.gd)\`
External: https://github.com/beyond-all-reason/RecoilEngine/blob/master/AGENTS.md
Other ref: $B/blob/v1.0/gone.gd
EOF
git add -A && git commit -qm base

rc=0; out="$(bash "$CHECK" 2>&1)" || rc=$?
assert_eq "1: resolving links exit 0" 0 "$rc"
assert_contains "1: counts four links" "examined 4 link(s), 0 missing" "$out"

printf '[gone](%s/blob/main/does-not-exist.md) and [ok](%s/blob/main/scripts/Unit.gd)\n' "$B" "$B" > bad.md
git add -A && git commit -qm bad
rc=0; out="$(bash "$CHECK" 2>&1)" || rc=$?
assert_eq "3: missing path exits 1" 1 "$rc"
assert_contains "3: names file and line" "file=bad.md,line=1" "$out"
assert_contains "3: names the URL" "$B/blob/main/does-not-exist.md" "$out"
assert_contains "3: one missing" "1 missing" "$out"

git rm -q bad.md && git commit -qm unbad
echo x > untracked.gd
printf '[u](%s/blob/main/untracked.gd)\n' "$B" > unt.md
git add unt.md && git commit -qm unt
rc=0; out="$(bash "$CHECK" 2>&1)" || rc=$?
assert_eq "4: untracked file exits 1" 1 "$rc"

if [ "$FAILURES" -ne 0 ]; then
  echo "$FAILURES assertion(s) failed"
  exit 1
fi
echo "all own-blob-link assertions passed"
