# agy mistake ledger

The standing rules for every `agy` (Antigravity CLI, Gemini) dispatch in this repo.
Each rule is a mistake agy made on a real PR, stated as the action that avoids it.
The orchestrator prepends the block between the two marker lines verbatim to every agy brief,
so a learning from one PR reaches the next dispatch on any other branch.
Each agy fix round appends its own new rule here on the PR branch, and the orchestrator merges the additions on `main`.
The cross-repo rule behind this file is `shared/workflow/improve-your-subagents.md` in ai-config.

STANDING RULES FOR THIS DISPATCH (each is a past mistake; violating one costs a fix round):
1. Re-read the target file at every line you cite; never trust a remembered line number.
2. Markdown: a blank line before and after every list; one clause per line.
3. Code comments: every bracket opened in a trailing comment closes on the same line, because the coverage tool skips comment-only lines and a stuck open bracket suppresses instrumentation for the rest of the file.
4. No digits that look like issue numbers in code comments or comment examples; use 42 or 99.
5. Any regex or classifier: enumerate the real input forms first (annotated declarations, signatures, indented statements), print a one-line self-test (an awk BEGIN block, python -c) in your summary, and never use \b in awk (POSIX lacks it; GNU awk reads it as a backspace).
6. A test must fail without the production change; check by reasoning about what the pre-patch code already did.
7. Test every call path you changed, not only the first one.
8. Any edited executable line, even a comment-only rewording, needs a test that exercises it, because codecov/patch counts every modified line.
9. When a default, path, or payload key changes, grep for every sibling docstring, README sentence, and comment that names the old one, including the error path of the new default.
10. Keep a doc comment's wording typed: an integer field is not a flag; a payload-key comment names every producer.
11. Mirror the sibling functions' guards (empty input, playback mode) when extending an enqueue_* method.
12. Keep a new file under 100 lines (file_length gate) and .gd added lines under 100 chars.
13. Before returning, run the checks you can (tools/check.sh chars; bash -n; the self-tests above) and paste their output.
14. Re-read this ledger before writing a new rule; do not add a rule that is already here.
END OF STANDING RULES.

## Provenance

Rules 1 to 14 come from the agy fix rounds on the perf-graph path, replay tray-row, and coverage-instrumentation PRs of 2026-09-02, whose per-PR learning sections were folded here.
