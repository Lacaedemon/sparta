## State that tracks part of another variable must be reconciled by every writer of that variable

#1859 (PR #1863) added `_absorbed_fold`, a count of the part of `_formation_angle` that small re-faces on riders folded in, so that only that part would be squared once the block was clear.
The head that round 1 reviewed (f288de05) zeroed the count only in `reform_ranks`, the rout, the rally and the file double.
Round 1 traced an engage settle after an absorb: the settle folded a further turn into `_formation_angle` and left the count standing, so the squaring would wheel the grid away from square with no order (the test b4bbbdb6 added for it: a fold at +40 would turn to +80).
b4bbbdb6 made every other write to the fold zero the count except a drill settling (engage settle, snap-absorb, `_fold_grid_lag`, the order's partial engage fold, each rally step), and added tests for the engage settle, the snap-absorb and the folded lag.
This is the writer-side counterpart of part 26's rule that a change of measurement must update every reader.

- **Do:** when new state records part of another variable, list every writer of that variable (grep the assignments), decide for each whether it resets or reconciles the new state, and test each one.

- **Don't:** reset the new state only in the writers the design was thinking about.

(`Lacaedemon/sparta` #1859, PR #1863, f288de05, b4bbbdb6, 2026-10-25.)

## Key a reset to the condition the state describes, not to a proxy

#1868 (PR #1869) added `_absorbed_drill_turn` to remember a quarter-turn drill that an absorb had cleared from the drill record.
f90f7696 restarted it at the next absorb whenever the absorbed count was 0, taking "count is 0" to mean "the fold no longer stands on that drill".
That holds when another writer ended the count, but not when the squaring itself returned the fold onto the drill: round 2 traced a second bout of riders that then found no drill to square back to, leaving the grid 20 degrees off the quarter.
9afde896 put the drill back into the record when the fold returned onto it, and added a two-bout test.

- **Do:** reset a field on the event that makes what it describes untrue, and test a sequence of two or more bouts as well as one.

- **Don't:** use another field reaching zero as a stand-in for that event.

(`Lacaedemon/sparta` #1868, PR #1869, f90f7696, 9afde896, 2026-10-26.)

## Measure the cause an exemption reason names before building a fix for it

#1858 was filed from the `interior_strike_1834` exemption reason, which blamed a grid swing for the clip's shape residual and said to remove it "once #1792 lands".
A local trial on top of PR #1863 (9c6cd751), extending #1792's fold to foot enemies, left the clip failing on every seed (best 30.7 against a 13.5 limit);
draft PR #1867 held only the claim.
On seed 0 the residual was the same on both trees through tick 142, although one grid turned 17 degrees and the other none: the six attackers push the block's men apart, and the residual is the men walking back.
The trial also flagged 6 of 186 rows in the melee-outcome delta, and PR #1867 was closed without a change, with the findings on #1858.
Part 25's lesson on issue text copied from an agent's numbers is the same failure with a different source.

- **Do:** before fixing the cause an exemption reason names, check it on a dense dump: does the defect move with that cause?

- **Don't:** treat an exemption reason's stated cause as measured.

(`Lacaedemon/sparta` #1858, PR #1867, 2026-10-25.)

## Check each option in a design call against the measured case before posting it

On #1868 the first recommendation posted to Ezra was to stop squaring once the ranks crossed square.
The measured case in #1868's body moved from 38 to 67 degrees off its heading without crossing, so that rule would not have caught it.
The message was corrected before work started, and the work gave back an absorbed turn only while it brought the fold closer to its nearest square line.

- **Do:** test each option you offer against the case the issue measured before you post it.

- **Don't:** recommend an option from its description alone.

(`Lacaedemon/sparta` #1868, 2026-10-26.)
