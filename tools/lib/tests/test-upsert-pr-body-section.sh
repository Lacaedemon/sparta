#!/usr/bin/env bash
# Self-contained unit test for tools/ci/upsert-pr-body-section.sh:
#
#   1. an LF body that already holds the marker pair has its section replaced,
#      leaving exactly one section
#   2. a CRLF body that already holds the marker pair also has its section
#      replaced (not a second section appended), and is written back LF-only
#   2b. only line-ending \r bytes are removed: a bare \r inside the author's
#       text survives
#   3. a body with no marker pair gets exactly one section appended after the
#      author's text
#
# Case 2 is the regression: the script matches the marker line exactly, so a
# body whose lines end in \r never matched and every run appended a new copy.
#
# No network and no real `gh`: a stub `gh` on PATH serves the PR body from a
# temp file for `gh api repos/.../pulls/N --jq ...` and stores the body from the
# JSON payload of `gh api -X PATCH ... --input -`. Needs `jq` on PATH (the
# script's own dependency); skips with a clear message rather than failing
# without it.
#
# Run by tools/check.sh's shell_tests check, alongside every other tools/lib/tests/test-*.sh.
#
# Usage: tools/lib/tests/test-upsert-pr-body-section.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
UPSERT="$REPO_ROOT/tools/ci/upsert-pr-body-section.sh"

if ! command -v jq >/dev/null 2>&1; then
  echo "SKIP test-upsert-pr-body-section: jq not on PATH"
  exit 0
fi

FAILURES=0

assert_eq() {
  local label="$1" want="$2" got="$3"
  if [ "$want" != "$got" ]; then
    printf 'FAIL %s: want %q got %q\n' "$label" "$want" "$got" >&2
    FAILURES=$((FAILURES + 1))
  else
    printf 'ok %s\n' "$label"
  fi
}

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
BODY_FILE="$WORK/body.txt"
mkdir -p "$WORK/bin"

# The real tools come first, resolved before PATH is changed, so the wrappers
# below can exec them.
REAL_AWK=$(command -v awk)
REAL_JQ=$(command -v jq)

# awk wrapper: a Windows (Cygwin/MSYS) gawk reads input in text mode and drops
# the \r before each \n, which hides the bug this test exists for -- the
# script's whole-line marker match then succeeds on a CRLF body even without
# the fix. BINMODE=1 makes gawk read input byte for byte, as Linux awk always
# does; gawk ignores it on Linux, so the wrapper is a no-op there.
printf '#!/usr/bin/env bash\nexec "%s" -v BINMODE=1 "$@"\n' "$REAL_AWK" > "$WORK/bin/awk"
chmod +x "$WORK/bin/awk"

# jq wrapper, for the same reason: a native Windows jq drops \r from \r\n on
# input and writes \n as \r\n on output unless given --binary. A build that
# rejects the flag (it only matters on Windows) runs unwrapped.
if "$REAL_JQ" --binary -n 1 >/dev/null 2>&1; then
  printf '#!/usr/bin/env bash\nexec "%s" --binary "$@"\n' "$REAL_JQ" > "$WORK/bin/jq"
  chmod +x "$WORK/bin/jq"
fi

# Stub gh: reads return the stored body verbatim, a PATCH stores the payload's
# .body verbatim. jq -j prints without a trailing newline, and reads go through
# cat, so the stored bytes match what a real API round trip would return.
cat > "$WORK/bin/gh" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = "api" ] && [ "$2" = "-X" ] && [ "$3" = "PATCH" ]; then
  jq -j '.body' > "$STUB_BODY_FILE"
  exit 0
fi
if [ "$1" = "api" ]; then
  cat "$STUB_BODY_FILE"
  exit 0
fi
echo "stub gh: unexpected call: $*" >&2
exit 2
STUB
chmod +x "$WORK/bin/gh"
export STUB_BODY_FILE="$BODY_FILE"
export PATH="$WORK/bin:$PATH"

OPEN='<!-- sparta-demo -->'
CLOSE='<!-- /sparta-demo -->'

# count_lines <fixed-string> -> number of lines equal to it in the stored body,
# ignoring a trailing \r so a leftover CRLF copy of a line is still counted.
count_lines() {
  awk -v want="$1" '{ sub(/\r$/, "") } $0 == want { n++ } END { print n + 0 }' "$BODY_FILE"
}

has_cr() {
  if grep -q $'\r' "$BODY_FILE"; then echo yes; else echo no; fi
}

# run_upsert <section-body> <case-label>: a non-zero exit from the script counts
# as a failure of that case rather than aborting the whole test.
run_upsert() {
  if ! bash "$UPSERT" owner/repo 1 "$OPEN" "$CLOSE" "$1" >/dev/null; then
    printf 'FAIL %s: upsert script exited non-zero\n' "$2" >&2
    FAILURES=$((FAILURES + 1))
  fi
}

# 1. LF body with an existing section.
printf 'Intro line\n\n%s\nold clip\n%s\n\nOutro line' "$OPEN" "$CLOSE" > "$BODY_FILE"
run_upsert "new clip" lf
assert_eq "lf: one open marker" 1 "$(count_lines "$OPEN")"
assert_eq "lf: old content gone" 0 "$(count_lines "old clip")"
assert_eq "lf: new content present" 1 "$(count_lines "new clip")"
assert_eq "lf: author text kept" 1 "$(count_lines "Outro line")"

# 2. CRLF body with an existing section (the regression).
printf 'Intro line\r\n\r\n%s\r\nold clip\r\n%s\r\n\r\nOutro line' "$OPEN" "$CLOSE" > "$BODY_FILE"
run_upsert "new clip" crlf
assert_eq "crlf: one open marker" 1 "$(count_lines "$OPEN")"
assert_eq "crlf: one close marker" 1 "$(count_lines "$CLOSE")"
assert_eq "crlf: old content gone" 0 "$(count_lines "old clip")"
assert_eq "crlf: new content present" 1 "$(count_lines "new clip")"
assert_eq "crlf: author text kept" 1 "$(count_lines "Outro line")"
assert_eq "crlf: written back LF-only" no "$(has_cr)"

# 2b. CRLF body whose last line also ends in \r\n, plus a bare \r inside the
#     author's text: line-ending \r bytes go, the bare one stays.
printf 'Progress 50%%\rdone\r\n%s\r\nold clip\r\n%s\r\n' "$OPEN" "$CLOSE" > "$BODY_FILE"
run_upsert "new clip" crlf-bare-cr
assert_eq "crlf-bare-cr: one open marker" 1 "$(count_lines "$OPEN")"
assert_eq "crlf-bare-cr: new content present" 1 "$(count_lines "new clip")"
# Both counts use awk regexes over the file rather than a \r-bearing shell
# string: a Windows bash can drop \r from command-substitution output, so a
# string round-tripped through the shell is not a reliable operand.
assert_eq "crlf-bare-cr: bare \\r in author text kept" 1 \
  "$(awk '/\r[^\r]/ { n++ } END { print n + 0 }' "$BODY_FILE")"
assert_eq "crlf-bare-cr: no line-ending \\r left" 0 \
  "$(awk '/\r$/ { n++ } END { print n + 0 }' "$BODY_FILE")"

# 3. Body with no section: append exactly one.
printf 'Just the author text' > "$BODY_FILE"
run_upsert "first clip" append
assert_eq "append: one open marker" 1 "$(count_lines "$OPEN")"
assert_eq "append: content present" 1 "$(count_lines "first clip")"
assert_eq "append: author text kept" 1 "$(count_lines "Just the author text")"

if [ "$FAILURES" -gt 0 ]; then
  echo "$FAILURES failure(s)" >&2
  exit 1
fi
echo "all upsert-pr-body-section checks passed"
