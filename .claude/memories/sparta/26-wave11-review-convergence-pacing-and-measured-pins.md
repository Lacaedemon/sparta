## An explicit A/B/C triage rule, paired with a follow-up issue, made two reviewers converge

Each review round on #1827 (PR #1838) kept finding new sites, mostly corner cases of anchored blocks.
The 2026-10-15 notebook notes that round 6 was "converging on anchored-block corner cases", and round 7 still had agy finding new sites: fog filter in support, one-sided reach, rally coast, cycle-charge target commit, demo comments.
On 2026-10-15 the review prompt gained a triage rule:

- **A**: a regression against main, or a defect in the PR's own code. Blocks.
- **B**: already so on main, or a scope extension. Goes to one follow-up issue, #1843. Does not block.
- **C**: the PR's own docs and tests. Blocks.

Only A and C counted toward CLEAN.
Round 8 then returned agy CLEAN, the first clean verdict from agy in eight rounds, and Claude reported A:0 with C:2.
Claude's confirmation review on f54859ef was CLEAN, and PR #1838 merged as 2c2955cc.

- **Do:** when review findings drift to ever-narrower sites on a large diff, write the A/B/C rule into the review prompt and file the B list as one issue, so each B finding has a place to go.

- **Don't:** keep running rounds with an open-ended "any finding blocks" prompt, or defer B findings without the tracking issue.

(`Lacaedemon/sparta` #1827, PR #1838, #1843, 2026-10-15.)

## A fix that changes which measurement is used must update every consumer of the old one

The round-4 fix on #1827 changed which gap is measured at contact.
The 2026-10-15 notebook records that it "missed five" consumers, found by later review rather than by the author.
Round 5 (044b1ff8) fixed them: the router anchor now mirrors `within_contact`, and `contact_point()`/`toward()` are used at the facing, press and flank sites.
Round 6 then found the shield wall still read the old measure (measured 1.0 to 0.65), and the cycle-charge recharge and the support guard needed the same extension.

- **Do:** when a fix changes which quantity is measured, grep for every reader of the old quantity and decide each one, then list them in the handback, instead of fixing only the sites a review named.

- **Don't:** treat the reviewer's list of sites as the complete set of consumers.

(`Lacaedemon/sparta` PR #1838, 2026-10-15.)

## A fix that changes pacing needs a hash and delta check before it is reported done

Round-7 fix e365f549 opened a charge's sprint window past the pair's contact extension.
It looked like a plain A-class correction.
Measuring it showed otherwise: first contact moved up to 165 ticks earlier than main in `cycle_charge`, 7 new melee-delta rows were flagged (charge, cycle_charge, roll_the_line, ai_honors_fog), and new defect candidates appeared in `charge` (uid9 overlap, uid0 shape_residual) and `knockback_focus` (uid7 flutter).
The notebook counts 13 clips moved.
It was reverted in a8ec459f ("keep the sprint window centre to centre; document the shorter runway"), and the sprint window became item 6 of #1843.
The doc and the `SPRINT_START_DISTANCE` comment now say a charge into a deep block sprints over a shorter runway.

- **Do:** after a change to when a unit sprints, when contact lands, or any other pacing, compare per-clip hash streams and the melee delta against the previous head before calling it done.

- **Don't:** report a pacing fix as an A-class correction on the strength of its unit tests.

(`Lacaedemon/sparta` #1827, PR #1838, #1843, e365f549, a8ec459f, 2026-10-15.)

## A float-precision change can move clips the change should not touch

In the round-6 fixes (2e8e41cf), replacing `sqrt(dist_sq)` with `Vector2.length()` moved two cavalry clips.
`length()` is single precision where the `sqrt` call is double.
The notebook records the "precision slip" and its fix; hash streams were then equal to round 5.

- **Do:** when a change should be neutral for some clips (here cavalry), check the hash streams on those clips too, and keep `sqrt(dist_sq)` where precision matters to the stream.

- **Don't:** treat `length()` as a drop-in for `sqrt(dist_sq)`, or look at the hash streams only for the clips the change targets.

(`Lacaedemon/sparta` PR #1838, 2026-10-15.)

## Read the `--match-head-commit` SHA from the PR at the point of use

The first merge attempt for PR #1838 on 2026-10-15 passed a `--match-head-commit` value that had been padded from a short SHA to 40 characters.
The merge was rejected with "Head branch was modified", which looks the same as a concurrent push.
The notebook records the padded value as fabricated, and the fix: read `headRefOid` from the PR when issuing the merge.

- **Do:** read the full head SHA with `gh pr view N --json headRefOid` in the same step as the merge command.

- **Don't:** extend a short SHA to full length by hand, or read a "Head branch was modified" rejection as proof that someone pushed.

(`Lacaedemon/sparta` PR #1838, 2026-10-15.)

## A cross-vendor reviewer's quota can run out mid-wave

On 2026-10-16 agy returned a 429 ("Individual quota reached ... Resets in 108h30m") for both `gemini-4-argon-high` and `gemini-3.8-flash-high`.
The #1834 review (PR #1836) went ahead with the Claude reviewer only.
On 2026-10-21 agy was still 429, with a reset the notebook estimates at about 2026-10-24 01:30 PDT, so review stayed Claude-only.
These dates describe that moment.
As of 2026-10-21, no second-vendor review of #1834 has been possible.

- **Do:** plan a long wave for the case where the second vendor goes away, say plainly in the PR when a round had one reviewer, and date the statement.

- **Don't:** count a single-vendor CLEAN as the same evidence as the two-vendor CLEAN #1838 had.

(`Lacaedemon/sparta` PR #1836, #1834, 2026-10-16 to 2026-10-21.)

## Reviewers quote code that does not exist

In the round-6 and round-7 reviews of #1827, the notebook notes that agy "quoted constants/functions not in the tree again".
Part 25 recorded the same thing in round 1, where two named functions did not exist.
Findings also needed measuring: in round 6 the two reviewers disagreed on `_is_frontal_attack`, and measurement showed agy right (shield wall 1.0 to 0.65).

- **Do:** grep the tree for each constant, function and line a finding quotes before acting, and measure a finding when the reviewers disagree.

- **Don't:** accept or dismiss a finding because its quote looks specific or because it came from the more trusted reviewer.

(`Lacaedemon/sparta` PR #1838, 2026-10-15.)
