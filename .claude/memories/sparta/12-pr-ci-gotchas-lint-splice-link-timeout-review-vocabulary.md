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

## check-new-line-breaks flags a long line with a mid-line semicolon, numbered lists included

`check / check-new-line-breaks` runs with `clause-breaks: true` and `clause-min-length: 80`:
any ADDED line whose visible length (markup stripped) is 80 characters or more and that carries a semicolon before its end fails the job,
and a numbered-list item counts like prose.
Measured 2026-09-02 on the agy ledger (nine rules failed in one push).
The fix is a continuation line indented three spaces under the item,
one clause per line, which the splice-by-marker consumers read unchanged.

- **Do:** break a list item at its semicolon or comma before it reaches 80 visible characters.
- **Don't:** treat numbered rules as exempt from the semantic-line-break check.

## 2026-09-02 subagent (Sonnet): three misses on the SfxSynth extraction

Extracting `Sfx.gd`'s synthesiser into `scripts/SfxSynth.gd`
left an existing sibling test still calling the removed `Sfx._synth`.
A new `_init(seed: int = 1)` parameter shadowed GDScript's
built-in `seed()` global.
Two new test locals used `:=` on a call against an untyped local,
which GDScript 4 rejects because the call returns `Variant`.

- **Do:** grep every directory a moved symbol could be referenced from
   (`test/`, `scripts/`, `tools/`), not only the file being edited,
   before calling a rename or extraction complete.

- **Don't:** trust that a new file's own tests cover a symbol's
   old call sites elsewhere in the suite.

- **Do:** name a constructor or function parameter something
   that cannot collide with a GDScript builtin
   (`rng_seed`, not `seed`).

- **Don't:** assume a parameter name is safe just because it reads
   naturally for its purpose;
   check it against GDScript's builtin globals
   (`seed`, `hash`, `randi`, `name`, and similar).

- **Do:** give an explicit type annotation (`var x: T = ...`)
   whenever the right-hand side is a method call on an untyped
   (`var x = ...`) local.

- **Don't:** use `:=` type inference on a call through an
   untyped local;
   GDScript 4 cannot infer past `Variant` and raises a compile error.

- **Do:** re-read a memory file's own formatting rule near its top
   before appending a new section to it.

- **Don't:** append a new section in a style that violates a rule
   the same file states a few sections above it.

- **Do:** name a `for` loop variable something other than `name`
   in any Node-derived script (GutTest included),
   since `name` is an inherited Node property;
   grep the production script too for `for name in`,
   not only its tests, when the script extends Node.

- **Don't:** write `for name in ...` in a Node-derived script;
   it silently shadows `Node.name` instead of erroring.

- **Do:** read the memory file's first section on the splice check
   and make any wrapped list loose,
   with a blank line between every item.

- **Don't:** put a wrapped list item directly under another item,
   even inside a Do/Don't pair.

## 2026-09-02 agy: Godot check-only fails on addon classes like GutTest

Running Godot `--check-only --script`
does not initialize project addons or plugins,
so scripts referencing addon classes such as `GutTest`
fail with parse errors.
The check works for standalone RefCounted or Node scripts under `scripts/`.

- **Do:** run Godot `--check-only` against standalone scripts,
  relying on the test runner for files that extend addon classes.

- **Don't:** expect `--check-only` to resolve
  addon-provided class names like `GutTest`.

## 2026-09-03 agy: three misses on the Settings extraction

SettingsStorage.gd duplicated FORM_UP_DIST_MAX
and FPS_CORNER_MAX from Settings.gd
and clamped values on load,
although the Settings property setters already own that clamping;
the fix passes the one bound the loader needs as an argument.
save_to_path and load_from_path repeated every key and section by hand
in sixteen blocks instead of one SECTIONS table
with a cast matched to the type of each default.
load_from_path returned the defaults on a missing file,
so the caller could not keep the original early return
and reassigned every property instead.

- **Do:** pass a bound into a storage helper
  as an argument from the owning class,
  keeping the constant canonical to its owner.

- **Don't:** duplicate a constant or clamp a value in a storage helper
  when a property setter already enforces the range.

- **Do:** drive config-file persistence from a single SECTIONS table,
  casting each value to the type of its default.

- **Don't:** write one if-block per key across save and load.

- **Do:** return an empty dictionary from a loader on a missing file
  when the caller's contract is an early return.

- **Don't:** return a populated defaults dictionary
  that hides the missing-file case from the caller.

- **Do:** reference a production bound from a test
  through the script that owns it
  (preload and read the const).

- **Don't:** copy a production constant into a test file,
  or mix a named bound with its literal value in one file.

- **Do:** when a loader replaces an "if value is Array" guard,
  keep the non-Array branch falling back to the default,
  since the caller assigns into a typed property.

- **Don't:** return a raw cfg value of the wrong type from a loader.

- **Do:** after a "verbatim" move,
  diff the moved block against its source
  and paste the empty diff.

- **Don't:** report a move as verbatim from memory,
  since an extra word slipped in here
  and survived a later rewording pass.

## 2026-09-03 agy: two nits on the Replay track extraction

Adversarial review of the Replay helper extraction found two nits.
First, a doc comment opened a parenthesis on one line
and closed it on the next line.
Ledger rule 3 applied to trailing comments on executable lines,
but every comment line must close any bracket it opens.
Second, deserializing loops in start_playback()
appended through forwarding properties
instead of appending to the helper's own track array directly.
Forwarding properties exist only for test assertions that snapshot state,
so internal replay deserialization must populate helper storage directly.

- **Do:** close every bracket opened on a comment line on that same line,
  applying ledger rule 3 to doc comments and not just trailing comments.

- **Don't:** allow an open bracket on a comment line to close on a later line,
  even though comment-only lines are skipped by the tokenizer.

- **Do:** append deserialized entries directly to the helper's own track array
  (_camera.track.append, _pointer.track.append, _keys.track.append),
  keeping forwarding properties exclusively for tests that snapshot them.

- **Don't:** append to helper state through forwarding properties
  in playback loading loops.

- **Do:** derive a test's expected value
  by tracing the production code path for the exact input,
  and prefer inputs that make a branch observable.

- **Don't:** write an expectation for a branch you assumed runs
  (a defensive guard)
  without first checking the cursor or index logic actually reaches it.

- **Do:** type a test's helper factory and locals
  against the preloaded script const
  so member access is checked.

- **Don't:** annotate a helper instance as RefCounted
  and then call its members dynamically.

## 2026-09-03 agy: PowerShell call operator required for quoted executable paths

Running a quoted executable path directly in PowerShell fails with a parse error
because PowerShell parses the leading quoted path as a string expression.
Prefixing the command with the ampersand call operator
or invoking through a bash subshell resolves the executable.

- **Do:** invoke a quoted Windows executable path
  using the ampersand call operator (`& "path" --args`)
  or through `bash -c` in PowerShell.

- **Don't:** run a quoted binary path directly in PowerShell without `&`,
  which treats the path as a string literal
  and fails on subsequent arguments.

## 2026-09-03 agy: four misses on the Replay codec extraction

Extracting ReplayCodec introduced four defects across codec and track helpers.
First, encode() wrapped the created timestamp in an int() cast,
converting a float timestamp to an integer.
Second, ReplayTimeScaleTrack carried three unused helper and alias methods,
which counted against patch coverage and duplicated the API.
Third, moved decoder code dropped original explanatory comments
for the order mode and line fields.
Fourth, the decoder compressed statements and dictionary literals
onto single lines to fit the new-file length cap
instead of splitting into separate helper files or functions.

- **Do:** preserve the exact type of serialized values when extracting code,
  avoiding spurious casts on moved values
  (see "2026-09-03 agy: three misses on the Settings extraction").

- **Don't:** cast a floating-point timestamp to int during serialization,
  which silently changes the payload data type in stored JSON.

- **Do:** expose only the methods callers actually invoke
  on a new instrumented helper class,
  and verify call sites across production and test code.

- **Don't:** add unused methods or alias wrappers to new instrumented files,
  which count against patch coverage and duplicate the interface.

- **Do:** carry forward existing explanatory comments when moving logic,
  ensuring any opened bracket closes on the same comment line
  (see "2026-09-03 agy: two nits on the Replay track extraction").

- **Don't:** drop explanatory domain comments during extraction passes
  or leave brackets unclosed on comment lines.

- **Do:** split distinct responsibilities into separate files or helpers
  when logic approaches the new-file line cap,
  retaining the standard one-statement-per-line style.

- **Don't:** compress multiple statements or wide dictionaries onto one line
  solely to satisfy a line-count limit.

- **Do:** when moving code,
  move every comment that explained it
  and re-read every comment left behind that pointed at it.

- **Don't:** leave a "see below" or a rationale comment orphaned
  on the caller's side
  after the code it described moved into a helper.

- **Do:** after rewrapping any comment,
  run the awk bracket control above on the file before finishing.

- **Don't:** trust that a rewrap kept brackets on one line,
  since re-flowing text is exactly
  what moves a closing bracket to the next line.

- **Do:** after moving a function into a helper,
  grep for every caller of the old wrapper
  and delete the wrapper when the count is zero.

- **Don't:** leave a one-line delegating wrapper behind "for compatibility"
  without a caller,
  since it is dead, uncovered surface.

## 2026-09-03 agy: preloading DemoState into DemoDefects broke bare godot -s

DemoDefects was given a preload of DemoState to read its coordinate precision constant,
violating the import boundary documented in lines 8-9 of DemoDefects.gd.
The header explicitly states that DemoDefects must not reference Unit or anything needing Settings,
because analyze_transcript.gd loads DemoDefects under bare `godot -s` without autoload singletons.
Preloading DemoState transitively loaded UnitFormation and Unit.gd,
triggering `Identifier not found: Settings` compile errors on every analyzer run.
The contract was missed because the brief directed attention to lines 75-120,
and the file's header comments were not read before adding the import.
The fix defines the coordinate precision constant directly in DemoDefects
and asserts parity against DemoState in the GUT test suite where autoloads exist.

- **Do:** read a file's header contract
  before adding an import to it.

- **Don't:** reach for a cross-file constant
  when the file documents an import boundary;
  duplicate with a parity test instead.

## 2026-09-04 agy: a semicolon on an 80-char added README line

A newly added bullet line in demos/README.md reached 82 visible characters
and carried a mid-line semicolon,
failing the diff-scoped check-new-line-breaks CI check.
The edit also introduced a contradiction
with an existing sentence in the factions bullet,
which claimed team 1 never spawns in a drill,
overlooking that a scenario enemy still deploys in drill mode.
In round 3, extending the `drill` bullet with continuation lines
tripped CI's blocking list-item splice check against `- `doctrine``,
because the check is diff-scoped and the pre-existing tight join failed;
the rule was already ledger rule 18 and was in the brief.

- **Do:** break an added prose line after a semicolon or colon,
  or start a new sentence with a full stop,
  before the line reaches 80 visible characters.

- **Don't:** leave a mid-line semicolon or colon
  on an added prose line of 80 or more visible characters.

- **Do:** after adding a mechanism claim to a doc,
  grep the same file for the mechanism's keyword
  and reconcile every sentence that states the opposite.

- **Don't:** assume surrounding bullets agree
  with a newly added mechanism claim
  without grepping the file to verify consistency.

- **Do:** verify a claim about what a value "defaults to"
  by reading the lookup function
  and the default declaration before writing it.

- **Don't:** write "keeps the default X"
  without naming what the default is
  and where it is read.

- **Do:** after extending a list item with wrapped continuation lines,
  insert a blank line before the next `- ` item
  because the splice check is diff-scoped
  and your added lines make the pre-existing tight join fail
  (the rule was already ledger rule 18 and was in the brief).

- **Don't:** treat the surrounding tight list
  as licence to leave the join tight.

- **Do:** when reconciling a contradicted sentence,
  re-read the WHOLE bullet or comment block and every clause in it,
  since the contradiction usually appears in more than one clause.

- **Don't:** amend only the clause a finding quoted.

## 2026-09-04 agy: report timing and unit-relative slot displacement

A headless run timed out at thirty minutes with no report file written
because the full test suite was started inside a run with a fixed timeout
and the deliverable report was deferred until the end.
In addition, slot displacement assertions across a march compared world coordinates,
which drifted by the entire march distance instead of checking unit-relative offsets.

- **Do:** write the deliverable report file within the first minutes
  and overwrite it after each task.

- **Don't:** defer writing the report file until the end of a session.

- **Do:** run only the test files targeted by the brief
  rather than starting the full suite inside a run with a fixed timeout.

- **Don't:** start the full test suite unless the brief explicitly asks.

- **Do:** compare unit-relative offsets (`slot - u.position`)
  when asserting slot displacement across a march.

- **Don't:** compare world coordinates across a march,
  which shifts slot positions by the march distance.

- **Do:** run the awk control above over every added prose line
  before reporting a doc edit done.

- **Don't:** rely on having written the rule
  as evidence of having followed it.

- **Do:** scan added .gd and demo lines for non-ASCII bytes and issue numbers yourself
  before reporting.

- **Don't:** type a degree sign or an issue number into a comment.

- **Do:** note that tools/check.sh chars/units/comments diff-scope COMMITTED changes,
  so on an uncommitted worktree their PASS says nothing.

- **Don't:** paste a "No new code lines" PASS as evidence for uncommitted edits.

## 2026-09-04 agy: a shared completion handler serves more than one order

- **Do:** before changing an argument at a call site,
  grep for every order/path that reaches that site (here begin_pivot callers)
  and decide per path.

- **Don't:** assume the site serves only the order named in the issue.

- **Do:** grep the test tree for the old expectation text (e.g. "_in_rear_row")
  after flipping a behaviour.

- **Don't:** update only the test file the brief named.
