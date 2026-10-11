#!/usr/bin/env bash
# Check the repo's own https://github.com/Lacaedemon/sparta/{blob,tree}/main/<path> links
# against the tracked tree instead of over HTTP (#1796).
#
# lychee.toml excludes these URLs because github.com answers the CI runner's burst of
# blob-page requests with intermittent 503s. Excluding them would let a deleted or
# renamed file go unnoticed, so this script keeps that half of the check: every such
# link must name a path that `git ls-files` tracks (a file, or a directory with at
# least one tracked file).
#
# Path handling: a #fragment or ?query is dropped, trailing prose punctuation
# (. , ; :), Markdown emphasis (* _), a CR and a trailing slash are stripped, and
# %XX escapes are decoded before the lookup.
#
# Scope matches lychee's: Morrison-Lab/gha's check-links action passes
# './**/*.qmd' './**/*.md' './**/*.html' when lychee-args is empty (it is, in
# .github/workflows/check-links.yml), so this scans tracked *.md, *.qmd and *.html.
# Links in other file types, such as *.yml, are checked by neither tool. Like lychee,
# it ignores links inside a Markdown code span (odd count of backtick runs before the
# URL on its line) and inside a fenced code block (*.md and *.qmd only).
#
# The scan must not pass vacuously: a failing scan exits non-zero, and finding no
# links while a scanned file contains the URL prefix is an error.
#
# Usage: tools/ci/check-own-blob-links.sh [repo-root]    (default: the current directory)
# Exit:  0 all links resolve; 1 a link points at a missing path, or the scan failed;
#        2 usage error.
set -euo pipefail

if [ "$#" -gt 1 ]; then
  echo "usage: check-own-blob-links.sh [repo-root]" >&2
  exit 2
fi
ROOT="${1:-.}"
cd "$ROOT" 2>/dev/null || { echo "check-own-blob-links: cannot cd to '$ROOT'" >&2; exit 2; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "check-own-blob-links: '$ROOT' is not a git work tree" >&2; exit 2; }

# lychee.toml's exclude regex for this prefix must stay in step with this one.
export OWN_LINK_PREFIX='https://github\.com/Lacaedemon/sparta/(blob|tree)/main/'
SCANNED=('*.md' '*.qmd' '*.html')
TRAILING='[.,;:*_/]$'

# Emit "file:line<TAB>url" for each link outside a code span or fenced block.
find_links() {
  git ls-files -z -- "${SCANNED[@]}" \
    | xargs -0 -r awk '
        BEGIN { pat = ENVIRON["OWN_LINK_PREFIX"] "[^]) \"'"'"'<>`\r]*" }
        FNR == 1 { fenced = 0 }
        FILENAME !~ /\.html$/ && $0 ~ /^[ \t]*(```|~~~)/ { fenced = !fenced; next }
        fenced { next }
        {
          line = $0
          offset = 0
          while (match(line, pat)) {
            url = substr(line, RSTART, RLENGTH)
            before = substr($0, 1, offset + RSTART - 1)
            runs = gsub(/`+/, "x", before)
            if (runs % 2 == 0) print FILENAME ":" FNR "\t" url
            offset += RSTART + RLENGTH - 1
            line = substr(line, RSTART + RLENGTH)
          }
        }'
}

# Capture first: a failing scan must stop the script under `set -e`, not feed the
# loop below an empty list.
links="$(find_links)"

missing=0
checked=0
while IFS=$'\t' read -r where url; do
  [ -n "$url" ] || continue
  path="${url#*/main/}"
  path="${path%%[#?]*}"
  while [[ "$path" =~ $TRAILING ]]; do path="${path%?}"; done
  case "$path" in
    *%*) path="$(printf '%b' "${path//%/\\x}")" ;;
  esac
  checked=$((checked + 1))
  if [ -z "$path" ] || [ -z "$(git ls-files -- "$path" | head -n 1)" ]; then
    echo "::error file=${where%:*},line=${where##*:}::own-repo link points at a path not tracked on main: $url"
    missing=$((missing + 1))
  fi
done <<< "$links"

if [ "$checked" -eq 0 ] && git grep -qF -e 'github.com/Lacaedemon/sparta/blob/main/' -e 'github.com/Lacaedemon/sparta/tree/main/' -- "${SCANNED[@]}"; then
  echo "check-own-blob-links: found 0 links, but a scanned file contains the URL prefix; the scan is broken." >&2
  exit 1
fi

echo "check-own-blob-links: examined $checked link(s), $missing missing."
[ "$missing" -eq 0 ]
