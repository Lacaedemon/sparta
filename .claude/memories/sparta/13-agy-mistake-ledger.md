# agy mistake ledger

The standing rules for every `agy` (Antigravity CLI, Gemini) dispatch in this repo.
Each rule is a mistake agy made on a real PR, or a repo gate one of its fix rounds tripped, stated as the action that avoids it.
The orchestrator prepends the block between the two marker lines (`STANDING RULES` and `END OF STANDING RULES`, each alone on its line) verbatim to every agy brief,
so a learning from one PR reaches the next dispatch on any other branch.
Each agy fix round appends its own new rule here on the PR branch, and the orchestrator merges the additions on `main`.
The cross-repo rule behind this file is `shared/workflow/improve-your-subagents.md` in ai-config.

STANDING RULES

Each rule below is a past mistake, or a repo gate that a past fix round tripped.
Violating one costs a fix round.

1. Re-read the target file at every line you cite;
   never trust a remembered line number.

2. Markdown: a blank line before and after every list;
   one clause per line.

3. Code comments: every bracket opened in a trailing comment closes on the same line,
   because the coverage tool skips comment-only lines
   and a stuck open bracket suppresses instrumentation for the rest of the file.

4. No digits that look like issue numbers in code comments or comment examples;
   use 42 or 99.

5. Any regex or classifier: enumerate the real input forms first (annotated declarations,
   signatures, indented statements),
   print a one-line self-test (an `awk 'BEGIN{...}'` block, `python -c`) in your summary,
   and never use \b in awk (POSIX lacks it;
   GNU awk reads it as a backspace).

6. A test must fail without the production change;
   check by reasoning about what the pre-patch code already did;
   a boundary parameter value can zero out the very effect the test guards,
   so pick a value well inside the effect
   and run the test against the pre-change file
   (`git show origin/<default-branch>:<path>`) as the negative control.

7. Test every call path you changed, not only the first one.

8. Any edited executable line, even a comment-only rewording,
   needs a test that exercises it,
   because codecov/patch counts every modified line.

9. When a default, path, or payload key changes,
   grep for every sibling docstring, README sentence,
   and comment that names the old one,
   including the error path of the new default.

10. Keep a doc comment's wording typed: an integer field is not a flag;
   a payload-key comment names every producer.

11. Mirror the sibling functions' guards (empty input,
   playback mode) when extending an enqueue_* method.

12. Keep a NEW scripts/*.gd file under 100 lines (the file_length gate applies only to
   files the diff adds); there is no line-length gate for .gd files,
   so wrap only where the surrounding code does.

13. Before returning, run the checks you can (tools/check.sh chars;
   bash -n;
   the self-tests above) and paste their output.

14. Re-read this ledger before writing a new rule;
   do not add a rule that is already here.

15. Resolve a relative path argument against the caller's cwd (prefix it with `$PWD`)
   before handing it to `git -C <project root>`;
   a raw caller-relative path resolves against the project root there.

16. Match keyword pairs in a classifier with a [ \t]+ separator rather than a literal single space,
   tolerating tabs and multiple whitespace between words.

17. Describe a value constraint in a comment using the constant's exact identifier (e.g. ZETA,
   not zeta), keeping casing identical to the declaration.

18. Markdown: a list whose items wrap onto continuation lines must be loose
   (a blank line between items),
   because the blocking lint step is the list-item splice check,
   which fails when an item follows a wrapped item with no blank line;
   a tight list is fine only when every item is a single line.

19. When a report or finding is keyed to a commit,
   run `git log <commit>..HEAD -- <paths>` for the paths involved
   before recommending work,
   and label each item already-landed, unverified, or open.

20. In a headless --print run nobody answers,
   so never end by asking for approval of a plan;
   execute and write the deliverable.

21. When extending an existing exemption, comment, or docstring,
   keep the earlier author's specific text and append;
   never replace a cited mechanism with a generic summary.

22. A new parameter takes the narrowest type that serves the one call site
   (a bool flag, not a Variant that is inferred three ways).

23. When a formula is changed, grep for its NAME and its DOC PHRASE ("mirrors",
   "same as", "keep in sync") across scripts/ and tools/, not only for call sites;
   grep for the formula's EXPRESSION text (e.g. `attack_range + RADIUS`) as well,
   and prefer replacing copies with one helper.

24. Never leave a mid-line semicolon or colon on an added line
   of 80 or more visible characters;
   break after the punctuation or end with a full stop.

25. After adding a mechanism claim to a doc,
   grep the file for the mechanism keyword
   and reconcile every existing sentence that states the opposite.

END OF STANDING RULES

## Provenance

Rules 1 to 11 and 14 to 17 come from the agy fix rounds on the perf-graph path, replay tray-row, and coverage-instrumentation PRs of 2026-09-02, whose per-PR learning sections were folded here.
Rule 12 restates the file_length gate that one of those rounds tripped,
and rule 13 is the check-before-returning step those rounds skipped.
Rule 6 was corrected on 2026-09-03 to name origin/<default-branch> over HEAD.
