#!/usr/bin/env bash
# Self-contained unit test for tools/ci/check-own-blob-links.sh, run against a throwaway
# git repo. Each case asserts the exit status and, where it matters, the report:
#
#   1. links that resolve pass: a tracked file, a tracked directory (with and without a
#      trailing slash), a #L12 fragment, ?plain=1, a link followed by `)`, `>`, `,`,
#      `.`, `;`, `**`, `_` or a CR, a %20-encoded path, and links in .md, .qmd and .html
#   2. ignored, so a missing target there does not fail: a code span, a fenced code
#      block, an external github.com link, and a non-main ref
#   3. a missing path fails (exit 1) and the report names the file, line and URL
#   4. an untracked file on disk also fails
#   5. a failing scan (awk exits non-zero) fails instead of reporting 0 links
#   6. a scan that silently finds nothing, while a file holds the URL prefix, fails
#   7. too many arguments exit 2, and a non-repo directory exits 2
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

assert_not_contains() {
  local label="$1" needle="$2" haystack="$3"
  case "$haystack" in
    *"$needle"*) echo "FAIL: $label: '$needle' found in output:"; echo "$haystack"; FAILURES=$((FAILURES + 1)) ;;
    *) echo "ok: $label" ;;
  esac
}

# Run the checker, leaving its combined output in $out and exit status in $rc.
run_check() {
  rc=0
  out="$("$@" 2>&1)" || rc=$?
}

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
STUB="$TMP/stub"
FIX="$TMP/repo"
mkdir -p "$STUB" "$FIX"
cd "$FIX"
git init -q .
git config user.email t@example.invalid
git config user.name t
git config core.autocrlf false
mkdir -p scripts docs "dir with space"
echo x > scripts/Unit.gd
echo x > docs/a.md
echo x > "dir with space/f.md"

B='https://github.com/Lacaedemon/sparta'
{
  echo "[file]($B/blob/main/scripts/Unit.gd), [dir]($B/tree/main/scripts), [slash]($B/tree/main/scripts/)."
  echo "[frag]($B/blob/main/scripts/Unit.gd#L12) [plain]($B/blob/main/scripts/Unit.gd?plain=1)"
  echo "Bare $B/blob/main/docs/a.md. And <$B/blob/main/docs/a.md>, then **$B/blob/main/docs/a.md**"
  echo "and _${B}/blob/main/docs/a.md_ and ${B}/blob/main/docs/a.md;"
  echo "Encoded: $B/blob/main/dir%20with%20space/f.md"
  printf 'CRLF: %s/blob/main/docs/a.md\r\n' "$B"
  echo "Code span, ignored: \`[x]($B/blob/main/nope/in-code-span.gd)\`"
  echo '```'
  echo "$B/blob/main/nope/in-fence.gd"
  echo '```'
  echo "External: https://github.com/beyond-all-reason/RecoilEngine/blob/master/AGENTS.md"
  echo "Other ref: $B/blob/v1.0/gone-ref.gd and $B/blob/master/gone-master.gd"
} > good.md
printf '# q\n\n[a](%s/blob/main/scripts/Unit.gd)\n' "$B" > good.qmd
printf '<a href="%s/blob/main/docs/a.md">a</a>\n' "$B" > good.html
git add -A && git commit -qm base

run_check bash "$CHECK"
assert_eq "1: resolving links exit 0" 0 "$rc"
assert_contains "1: examined all 12 links in good.md plus the qmd and html" "examined 14 link(s), 0 missing" "$out"
assert_not_contains "2: code span ignored" "in-code-span" "$out"
assert_not_contains "2: fenced block ignored" "in-fence" "$out"
assert_not_contains "2: external link ignored" "RecoilEngine" "$out"
assert_not_contains "2: non-main ref ignored" "gone-ref" "$out"
assert_not_contains "2: master ref ignored" "gone-master" "$out"

printf '[gone](%s/blob/main/does-not-exist.md) and [ok](%s/blob/main/scripts/Unit.gd)\n' "$B" "$B" > bad.md
git add -A && git commit -qm bad
run_check bash "$CHECK"
assert_eq "3: missing path exits 1" 1 "$rc"
assert_contains "3: names file and line" "file=bad.md,line=1" "$out"
assert_contains "3: names the URL" "$B/blob/main/does-not-exist.md" "$out"
assert_contains "3: one missing" "1 missing" "$out"

git rm -q bad.md && git commit -qm unbad
echo x > untracked.gd
printf '[u](%s/blob/main/untracked.gd)\n' "$B" > unt.md
git add unt.md && git commit -qm unt
run_check bash "$CHECK"
assert_eq "4: untracked file exits 1" 1 "$rc"
git rm -q unt.md && git commit -qm ununt

# 5: awk exits non-zero.
printf '#!/bin/sh\nexit 3\n' > "$STUB/awk"
chmod +x "$STUB/awk"
run_check env PATH="$STUB:$PATH" bash "$CHECK"
assert_eq "5: failing scan exits non-zero" 1 "$([ "$rc" -ne 0 ] && echo 1 || echo 0)"
assert_not_contains "5: no 'examined 0' pass" "examined 0 link(s)" "$out"

# 6: awk succeeds but finds nothing.
printf '#!/bin/sh\ncat >/dev/null\nexit 0\n' > "$STUB/awk"
run_check env PATH="$STUB:$PATH" bash "$CHECK"
assert_eq "6: silent empty scan exits 1" 1 "$rc"
assert_contains "6: says the scan is broken" "the scan is broken" "$out"

# 7: usage errors.
run_check bash "$CHECK" a b
assert_eq "7: two arguments exit 2" 2 "$rc"
run_check bash "$CHECK" "$TMP"
assert_eq "7: non-repo directory exits 2" 2 "$rc"

if [ "$FAILURES" -ne 0 ]; then
  echo "$FAILURES assertion(s) failed"
  exit 1
fi
echo "all own-blob-link assertions passed"
