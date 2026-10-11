#!/usr/bin/env bash
# Check the repo's own https://github.com/Lacaedemon/sparta/{blob,tree}/main/<path> links
# against the tracked tree instead of over HTTP (#1796).
#
# lychee.toml excludes these URLs because github.com answers the CI runner's burst of
# blob-page requests with intermittent 503s. Excluding them would let a deleted or
# renamed file go unnoticed, so this script keeps that half of the check: every such
# link must name a path that `git ls-files` tracks (a file, or a directory with at
# least one tracked file). A #fragment or ?query is ignored, as is trailing prose
# punctuation. Links inside a Markdown code span are ignored (lychee does not parse
# them either); the check is by parity of backtick runs before the URL on its line.
#
# Scans tracked *.md, *.qmd and *.html, the files lychee's default glob set covers.
#
# Usage: tools/ci/check-own-blob-links.sh [repo-root]    (default: the current directory)
# Exit:  0 all links resolve; 1 at least one points at a missing path; 2 usage error.
set -euo pipefail

ROOT="${1:-.}"
cd "$ROOT" || { echo "check-own-blob-links: cannot cd to '$ROOT'" >&2; exit 2; }
git rev-parse --git-dir >/dev/null 2>&1 || { echo "check-own-blob-links: '$ROOT' is not a git work tree" >&2; exit 2; }

# lychee.toml's exclude regex for this prefix must stay in step with this one.
export OWN_LINK_PREFIX='https://github\.com/Lacaedemon/sparta/(blob|tree)/main/'

# Emit "file:line<TAB>url" for each link outside a code span.
find_links() {
  git ls-files -z -- '*.md' '*.qmd' '*.html' \
    | xargs -0 -r awk '
        BEGIN { pat = ENVIRON["OWN_LINK_PREFIX"] "[^]) \"'"'"'<>`]*" }
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

missing=0
checked=0
while IFS=$'\t' read -r where url; do
  path="${url#*/main/}"
  path="${path%%[#?]*}"
  path="${path%[.,;:]}"
  path="${path%/}"
  checked=$((checked + 1))
  if [ -z "$path" ] || [ -z "$(git ls-files -- "$path" | head -n 1)" ]; then
    echo "::error file=${where%:*},line=${where##*:}::own-repo link points at a path not tracked on main: $url"
    missing=$((missing + 1))
  fi
done < <(find_links)

echo "check-own-blob-links: examined $checked link(s), $missing missing."
[ "$missing" -eq 0 ]
