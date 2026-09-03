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

- **Do:** name the explanation field `"reason"`, not `"skip_reason"`.
  `demo-video.yml` parses `.reason // .caption // <generic fallback>`, so a
  misnamed field is silently ignored and the posted note shows the caption
  instead, or the generic placeholder when there is no caption.

## Design docs cite only paths that exist

A plausible-looking path -- a test file named after the class it would test,
or a glob over a demo-input prefix -- reads as real, and is a common way
a phantom path gets published in a design doc.

- **Do:** run `git ls-files <path>` (or the glob) and cite only what it
  returns, before publishing a design doc.

- **Don't:** name a test script or input manifest a design doc "will use"
  unless it is already tracked, or the doc marks it as proposed.

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

## A green review check is not an approval: read the verdict payload on every surface before merging under `mwc`

`review / claude-review` and `review / require-review` both conclude `success`
when a reviewer ran and posted a verdict, whatever that verdict said.
The reusable `Morrison-Lab/gha` `claude-code-review.yml@v2` workflow says so in
its own comments: a green result attests that "a reviewer RAN and the job did
not fail", and "does not attest that the reviewer APPROVED".
Measured on #1471 at head `0c8a63aa`: the posted review carried
`"verdict": "NOT_CLEAN"` while every `review / *` check run reported
`success`.
Those are the check-run names exactly as `gh pr checks` printed them on
2026-09-02: the caller job in `.github/workflows/claude-code-review.yml` is
named `review` and delegates to the reusable workflow, so the prefix is that
job's name and moves with it, not the workflow's display name (`Claude Code
Review`).
The job's conclusion tracks whether a verdict was produced and posted, not
what it said, and the converse holds too: a red `claude-review` can sit on top
of a genuine verdict (see "A red `claude-review` can sit on top of a GENUINE,
complete verdict" in part file 07).
Nothing server-side catches this either: the `main` ruleset has no required
status checks (#1432), so under `mwc` the agent is the only gate.

- **Do:** run `check-pr-fully-clean.py` (the section above) and read its exit
  status three ways: 0 means nothing blocking was found, 1 means not clean,
  or no review found at all (the output says `No automated review comments or
  reviews found`), or a crash (a traceback with no finding bullets), and
  anything else means it did not answer.
  Exit 0 is not approval on its own: the exit status is only the first gate,
  and the `verdict scan:` line and the `Notes:` block the script prints
  beside it are required structured context.
  That does not contradict the section above, whose "not its printed prose"
  rule targets grepping the report for a verdict phrase rather than reading
  those two fixed lines.
  `latest = NONE` on the scan line means no readable verdict-bearing review
  was found.
  A quota-skip notice is excluded before the scan even starts, so a PR whose
  only bot comment is that notice takes the no-review exit 1 above rather
  than exiting 0, and that exit 1 is a missing review, not a not-clean
  verdict.
  A `NOTE:` saying a review has a format the classifier cannot read means a
  review arrived whose verdict was never read.
  A `latest = NONE` scan line, the no-review exit 1, or a `NOTE:` about an
  unreadable review each send you to the hand read below.

- **Do:** read the inline review comments and the unresolved review threads
  on every merge decision, whatever the exit status:
  `gh api repos/<owner>/<repo>/pulls/<N>/comments --paginate` plus the GraphQL
  `reviewThreads` list.
  The instrument's only PR fetch is `gh pr view --json ...,reviews,comments`,
  which never carries inline findings, and this repo's `prompt-addendum` and
  the auto-requested Copilot reviewer both put line-specific findings there,
  so a clean exit 0 is silent about that surface by construction.

- **Do:** when the instrument cannot run, or reports `latest = NONE`, the
  no-review exit 1, or an unreadable-review `NOTE:`, read every surface by
  hand and paginate each: `gh api repos/<owner>/<repo>/pulls/<N>/reviews --paginate`
  (formal reviews), `gh api repos/<owner>/<repo>/pulls/<N>/comments --paginate`
  (inline findings, where this repo's `prompt-addendum` tells the reviewer to
  put line-specific findings), and
  `gh api repos/<owner>/<repo>/issues/<N>/comments --paginate` selecting the
  LAST body that starts with `**Claude finished` (the verdict comment), whose
  trailing `Reviewed commit:` line must name the PR's current head, because a
  mismatch means the head is unreviewed.

- **Don't:** read a green `review / claude-review` or `review / require-review`
  check as approval, and don't read an unpaginated `issues/<N>/comments` call
  as the verdict: that endpoint is oldest-first, 30 per page, and never
  carries inline findings.

- **Don't:** rely on a branch ruleset or a forge hook to refuse the merge for
  you.

Links/provenance: measured 2026-09-01 on `Lacaedemon/sparta` CI (workflow runs
observed on PRs in the #1452/#1453/#1459/#1462 range).

## agy: tautological replay test and unwired apply_grid coverage (2026-09-02)

- **Do:** write tests that fail without the production change by reasoning about pre-patch code.
- **Don't:** add tests that already pass against unchanged code due to existing payload handling.
- **Do:** test every changed call path when changing a shared helper or dispatch method.
- **Don't:** assume testing one caller covers others that batch or structure inputs differently.
- **Do:** keep every comment describing an order payload key in sync when new producers arise.
- **Don't:** leave payload key comments listing only historical order sources when new ones carry it.
- **Do:** mirror the sibling functions' empty-input guard when extending an enqueue_* method.
- **Don't:** describe an integer field as a flag in a doc comment.

## agy: relative output paths and issue-number-shaped examples (2026-09-02)

The overwrite guard resolved relative paths against the project root rather than the caller's cwd.
Example branch names in the usage comment used real issue numbers.
A sibling script's docstring example was left stale.

- Do: prefix relative path arguments with $PWD before checking them against git ls-files.
- Don't: test raw relative paths with git -C $PROJECT_ROOT ls-files when invoked outside the project root.
- Do: use generic sample numbers like 42 or 99 in comment examples.
- Don't: write digits matching real repository issue numbers in code comments.
- Do: update example invocations in sibling script docstrings when modifying output path conventions.
- Don't: leave legacy output file paths in sibling docstrings after changing tool output naming.
- Do: put a blank line between a paragraph and the list that follows it in Markdown, because the repo's lint job fails on a list item glued to prose.
- Don't: start a bullet list on the line right after a sentence.
- Do: document every exit-1 path a tool gains in the same README edit that documents the new default.
- Don't: describe the happy path of a new default and leave its error case only in --help.

## agy: coverage tokenizer poisoning by trailing comments (2026-09-02)

Coverage.gd counts bracket openers on code lines including trailing comments,
but skips lines beginning with '#' without decrementing.
An unclosed bracket in a trailing comment leaves block count stuck positive
and suppresses coverage instrumentation for all later lines in that file.

- **Do:** read the target file directly to locate every offending comment
  rather than trusting remembered line numbers from an earlier report.

- **Don't:** rely on remembered line numbers or cite line 101 when line 50
  was the true first unclosed bracket in the file.

- **Do:** balance every parenthesis, bracket, or brace in a trailing comment
  on the same line or reword without delimiters.

- **Don't:** open a bracket in a trailing comment and close it on a subsequent
  comment line where the coverage instrumenter will skip it.

- **Do:** put a blank line between a paragraph and the list that follows it
  in Markdown; the repo's lint job fails on a list glued to prose.

- **Don't:** repeat a mistake already recorded in this file;
  re-read the agy sections before writing a new one.

- **Do:** add a test for any executable line the diff touches,
  even a comment-only rewording,
  because codecov/patch counts every modified line.

- **Don't:** treat a comment edit on a code line as coverage-neutral.

- **Do:** write awk word boundaries as an explicit character class such as ([ \t]|$),
  and test the regex with a one-line awk BEGIN block before shipping it.

- **Don't:** use \b in an awk regex;
  POSIX awk lacks it and GNU awk reads it as a backspace.

- **Do:** enumerate the real input forms (annotated declarations, signatures)
  and run each through the regex before shipping a classifier.

- **Don't:** ship a token list assembled from memory;
  two reviewers found the same missing forms.
