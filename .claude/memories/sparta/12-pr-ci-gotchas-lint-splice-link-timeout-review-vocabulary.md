## `lint / lint-markdown`: the whole-repo lint is advisory, the diff-scoped splice check is blocking

The reusable `Morrison-Lab/gha` `lint-markdown@v2` workflow lints ALL tracked
Markdown on every run, not just the diff.
It prints roughly 255 pre-existing markdownlint errors, concentrated in
`.claude/memories/` and `.jules/`, on every PR -- including on `main`, where
the job still passes.
Those whole-repo findings are advisory noise, not something a PR is expected
to clear.

The step that actually blocks is diff-scoped: "Check list-item merge splices"
(`check_list_item_splices.mjs`; `fail-on-item-splices` defaults to `true` in the
reusable `Morrison-Lab/gha` `lint-markdown.yml@v2` workflow, and this repo's
caller `.github/workflows/lint-markdown.yml` only passes `base-ref` and `fail`).
It fails when a list item follows directly after the previous item's
continuation line with no blank line between them, reported as "List-item
merged directly onto continuation line."
Semantic line breaks inside a single list item are fine; what fails is two
adjacent items with no blank line between them.

- **Do:** make a Markdown list loose (a blank line between items) whenever an
  item's text wraps onto a continuation line before the next item starts.

- **Do:** read the reusable `Morrison-Lab/gha` workflow at the pinned `@v2`
  ref for the exact input names (`fail-on-item-splices`, `base-ref`) before
  citing them; the caller file in this repo sets only `base-ref` and `fail`.

- **Don't:** treat the ~255 whole-repo markdownlint findings as something this
  PR must fix -- they are pre-existing and pass on `main` too.

- **Don't:** assume a tight (no-blank-line) list is safe just because it
  renders fine locally -- the splice checker is the blocking gate, not visual
  inspection.

## `check / link-checker` (lychee) fails on TIMEOUTS, not just broken links

`lychee.toml`-driven link checking exits non-zero (exit 2) on a request
timeout exactly as it does on a genuinely dead link, with zero broken links
otherwise.
A slow scholarly host is enough to redden the check even though every link is
valid.

LacusCurtius (`https://penelope.uchicago.edu/`) times out this way and is now
listed in `lychee.toml`'s `exclude` array.

- **Do:** add a slow-but-legitimate host to `lychee.toml`'s `exclude` array
  when it times out, keeping the citation in the prose.

- **Don't:** drop or reword a citation just to dodge a lychee timeout -- the
  fix belongs in `lychee.toml`, not in the prose.

- **Don't:** read a non-zero lychee exit as proof of a broken link without
  checking whether the failure was a timeout.

## Design-doc-only PRs: the demo manifest must be skip-form, not an `input` recording

A PR that only adds or edits a design document -- no implemented mechanic
behind it -- must ship a `demos/demo.<slug>.json` in skip form
(`"skip": true`, with an honest `"reason"`).
An `input`-recording manifest paired with a caption describing mechanics the
PR does not implement is the defect: the recording cannot show a mechanic
that does not exist yet, so the clip and the caption both misrepresent what
the PR does.
This is exactly the defect that got #1459's original manifest, and the
reverted #1452/#1453 manifests, rejected.

- **Do:** use `"skip": true` with a reason like "design-doc-only PR; mechanic
  not yet implemented" for a PR that adds no battlefield-visible behavior.

- **Don't:** point `demos/demo.<slug>.json` at an `input` recording whose
  caption claims a mechanic the PR has not actually implemented.

## Pre-push guard verdict vocabulary is exact-match; brief reviewers with the literal phrasing

The pre-push guard (`no-push-without-self-review.py`, from ai-config) parses a
review report for exactly two verdict lines:

```
### Verdict: Ready for merge
### Verdict: Needs more work
```

each expected to be followed by a `Reviewed-Commit: <sha>` line.
A report that ends with anything else -- including a plain "Verdict: Clean" --
is invisible to the guard's parser.
The guard scans the whole transcript and keeps the LAST parseable verdict,
whatever commit it names, and only afterwards compares that verdict's
`Reviewed-Commit` against the commits being pushed.
A later review that ended "Verdict: Clean" is skipped as unparseable, so an
older, blocking "Needs more work" stays the last parseable verdict and the
push is refused on stale grounds even though the actual latest review was
clean.

- **Do:** brief any local/self-dispatched reviewer with the two exact heading
  phrases above, verbatim, plus the `Reviewed-Commit: <sha>` line.

- **Do:** never run a `git push` in the same message/turn as dispatching a
  reviewer -- the guard reads whatever verdict already exists, and a
  just-dispatched review has no result yet, so the push races an empty
  answer.

- **Don't:** phrase a self-review's conclusion as "Verdict: Clean" or any
  other wording -- the guard's parser only recognizes the two headings above.

## `check-pr-fully-clean.py` is the merge instrument; sweep for quota-skipped reviews after a reset

`check-pr-fully-clean.py` (from the ai-config marketplace checkout) is the
instrument for deciding whether a PR is fully clean and mergeable -- read its
exit status, not its printed prose (see ai-config's `fully-clean.md` for the
three-way exit-status read).
A Claude review dispatched against a PR can come back quota-skipped ("Claude
review skipped -- API quota exhausted" or an equivalent credential/limit
message) when the account's usage limit is hit mid-session.

- **Do:** after a quota reset, sweep every PR that was pushed to during the
  outage window and re-dispatch its review explicitly:
  `gh workflow run claude-code-review.yml -f pr_number=N`.

- **Don't:** read a quota-skip notice as a clean verdict, or as something that
  resolves itself without a re-dispatch once quota is back.

Links/provenance: measured 2026-09-01 on `Lacaedemon/sparta` CI (workflow runs
observed on PRs in the #1452/#1453/#1459/#1462 range).
