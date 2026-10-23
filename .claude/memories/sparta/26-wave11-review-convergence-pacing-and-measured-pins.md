## An A/B/C triage rule with a follow-up issue preceded the round-8 CLEAN on #1827

This was observed on one PR (#1838, for #1827) over 8 rounds.
Rounds 1 to 4 were about other things: contact sites, caches, perf and replay.
In round 6 the findings were mostly corner cases of anchored blocks;
the 2026-10-15 notebook says they were "converging on anchored-block corner cases".
Round 7's agy findings were mostly other sites: the fog filter in support, one-sided reach, the rally coast and the cycle-charge target.
Finding counts for rounds 5, 6 and 7 were Claude 4, 5, 5 and agy 4, 4, 7.
The round-8 review prompt defined three classes:

- (A) "a regression this PR introduces vs main a3714751, or a defect in code this PR adds
  -- these block;"

- (B) "behaviour identical on main, or a request to extend the new gap/extension to more call sites
  -- list these separately as NON-BLOCKING;
  they belong in follow-up issue #1843 ...
  and must not be re-raised if #1843 already covers them;"

- (C) "docs/tests/naming in this PR's own code -- these block."

Because B findings stopped blocking, the round-8 agy CLEAN is partly true by definition, not only by convergence.
It was agy's first CLEAN in eight rounds.
Claude's round 8 still had A:0 and C:2, and needed a confirmation pass, which was CLEAN on f54859ef.
PR #1838 then merged as 2c2955cc.
The cause (the rule versus other changes between rounds 7 and 8) was not separated by this one PR.

- **Do:** when review findings drift to ever-narrower sites on a large diff, write the A/B/C rule into the review prompt and file the B list as one issue, so each B finding has a place to go.

- **Don't:** keep running rounds with an open-ended "any finding blocks" prompt, defer B findings without the tracking issue, or read the resulting CLEAN as proof the diff has no B-class problems.

(`Lacaedemon/sparta` #1827, PR #1838, #1843, 2026-10-15.)

## A fix that changes which measurement is used must update every consumer of the old one

The round-4 fix on #1827 changed which gap is measured at contact.
The 2026-10-15 notebook records that it "missed five" consumers, found by later review rather than by the author.
Round 5 (044b1ff8) fixed them: the router anchor now mirrors `within_contact`, and `contact_point()`/`toward()` are used at the facing, press and flank sites.
Round 6 then found that the shield wall's frontal test (`_is_frontal_attack`) still read the old position-based measure, so an attacker whose anchored men stood before the wall stripped its frontal cover.
The cycle-charge recharge and the support guard needed the same extension.

- **Do:** when a fix changes which quantity is measured, grep for every reader of the old quantity and decide each one, then list them in the handback, instead of fixing only the sites a review named.

- **Don't:** treat the reviewer's list of sites as the complete set of consumers.

(`Lacaedemon/sparta` PR #1838, 2026-10-15.)

## A fix that changes pacing needs a hash and delta check before it is reported done

Round-7 fix e365f549 opened a charge's sprint window past the pair's contact extension.
Measuring it showed: first contact moved up to 165 ticks earlier than main in `cycle_charge`, 7 new melee-delta rows were flagged (charge, cycle_charge, roll_the_line, ai_honors_fog), and new defect candidates appeared in `charge` (uid9 overlap, uid0 shape_residual) and `knockback_focus` (uid7 flutter).
The notebook counts 13 clips moved.
It was reverted in a8ec459f ("keep the sprint window centre to centre;
  document the shorter runway"),
and the sprint window became item 6 of #1843.
The doc and the `SPRINT_START_DISTANCE` comment now say a charge into a deep block sprints over a shorter runway.

- **Do:** after a change to when a unit sprints, when contact lands, or any other pacing, compare per-clip hash streams and the melee delta against the previous head before calling it done.

- **Don't:** report a pacing fix as an A-class correction on the strength of its unit tests.

(`Lacaedemon/sparta` #1827, PR #1838, #1843, e365f549, a8ec459f, 2026-10-15.)

## A float-precision change can move clips the change should not touch

In a7d8be1a (the round-6 fixes), the cycle charge's pull-back replaced `sqrt(dist_sq)` with `Vector2.length()`, which moved two cavalry clips.
`length()` is single precision where the `sqrt` call is double.
The fix, 2e8e41cf, reads the distance as `sqrt(length_squared())`.
Its message names the clips `cycle_charge` (from tick 1075) and `cycle_charge_flee` (from tick 472), whose pairs take no extension, and says both hash-match the parent round's streams afterwards.

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

On 2026-10-16 02:32 PDT agy returned a 429
(the message said "Individual quota reached" and gave "Resets in 108h30m")
for both `gemini-4-argon-high` and `gemini-3.8-flash-high`.
The #1834 review (PR #1836) went ahead with the Claude reviewer only.
That message implied a reset at about 2026-10-20 15:00 PDT.
It did not hold: agy still returned 429 on 2026-10-21, with a new estimate in the notebook of about 2026-10-24 01:30 PDT, so review stayed Claude-only.
As of 2026-10-21, no second-vendor review of #1834 has been possible.

- **Do:** probe the second vendor at the start of a wave and record the result in the notebook.
  Re-probe the quota before planning a round on it rather than trusting the reset message.

- **Don't:** count a single-vendor CLEAN as the same evidence as the two-vendor CLEAN #1838 had, or leave a single-vendor round unstated in the PR.

(`Lacaedemon/sparta` PR #1836, #1834, 2026-10-16 to 2026-10-21.)

## Reviewers quote code that does not exist

In the round-6 reviews of #1827, the notebook notes that agy "quoted constants/functions not in the tree again".
Part 25 recorded the same thing in round 1, where two named functions did not exist.
Findings also needed measuring: in round 6 the two reviewers disagreed on the shield-wall case from lesson 2 (`_is_frontal_attack`).
Agy said a shield wall loses its frontal defence against an anchored attacker.
Claude said the sign test was barely affected.
The round-6 finisher report measured `melee_defense_factor` in one constructed test: a shield wall facing up, and an attacker turned 30 degrees with a 150 wu anchor whose men stand 60 wu ahead of the wall.
The factor was 1.0 with the old position-based test (frontal cover lost) and 0.65 with the fix, so agy was right.
That is one constructed case, not a sweep.
The fix is a7d8be1a.

- **Do:** grep the tree for each constant, function and line a finding quotes before acting, and measure a finding when the reviewers disagree.

- **Don't:** accept or dismiss a finding because its quote looks specific or because it came from the more trusted reviewer.

(`Lacaedemon/sparta` PR #1838, 2026-10-15.)
