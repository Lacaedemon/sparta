## A cache-invalidation sweep must cover the paths that grow the block, not only those that shrink it

PR #1778 (#1768) made every resized row-major block hold a dealt `_sim_soldier_row_slot` pairing.
Its first version re-dealt only when the pairing outgrew the block, so an `absorb()` at an unchanged file count left the pairing shorter than the block.
`formation_slots` then fell back to the identity grid and never re-dealt, which walked men across the centreline again.
The implementer had listed merge and reinforcement as "same as main", which stopped being true once a resize left a pairing behind.

- **Do:** list the size-changing paths in both directions (casualty, `reap`, `absorb`/merge, reinforcement), trigger on any size mismatch, and test the growing case.

- **Don't:** carry "same as main" forward for a path whose precondition the fix itself changed.

(`Lacaedemon/sparta` PR #1778, 2026-10-10.)

## A test margin justified as float noise can hide a real mover

A crossing test on PR #1778 used half a file pitch plus 0.01 wu as its threshold and called the margin float noise.
The margin excluded a rear-rank man who really walked across the centre, so the test read zero crossings on a deal that still crossed.

- **Do:** bound each man's travel as well as counting threshold crossings, and justify any margin by naming the man it excludes.

- **Don't:** widen a threshold until the branch reads zero.

(`Lacaedemon/sparta` PR #1778, 2026-10-10.)

## A skip keyed on a phase predicate covers every block in that phase

PR #1776's (#1774) first version skipped `SoldierBodies.couple()` whenever `is_order_turning()` was true.
That also froze blocks with full ranks, which have no phantom drift to suppress, so a shove during their turn was no longer followed.
It also covered the order-response delay, because `turn_target` is armed when the order is issued, before the visible turn starts.
The merged fix measures drift against the slots as they stood when the turn began, instead of skipping.

- **Do:** gate a sim change on the defect's own precondition, and probe both a block without that precondition and the window before the visible phase starts.

- **Don't:** key a fix on a phase predicate just because the defect only shows in that phase.

(`Lacaedemon/sparta` PR #1776, 2026-10-10.)

## A getter that can mutate is a hidden ordering dependency

PR #1778 made `soldier_world_slots()` lazily re-deal a row-major pairing on the first query after a reshape.
PR #1776's `reform_ranks` read the slots before arming the about-face mirror, so once both had merged that read dealt the pairing in the wrong frame.
The auto-merge was textually clean, and each PR's own tests were green on its own branch.
The semantic review of the merge commit found it, and the same review found the square branch had always had the read-before-mirror bug.
The fix (`Unit._slot_deal_pending`) skips the early read whenever any layout has a deal pending.

- **Do:** when a getter gains a side effect, grep every caller in open sibling branches, and review the merge commit for meaning, not only for conflicts.

- **Do:** take a capture from a read that cannot mutate state.

- **Don't:** treat a conflict-free auto-merge plus green per-PR tests as evidence that two sim changes compose.

(`Lacaedemon/sparta` PRs #1776 and #1778, 2026-10-10.)

## A facing or grid hold has a cost no defect verdict measures

PR #1790 (#1757) holds a fighting block's facing while a router is inside it, so the slot grid does not swing after the router.
The defect delta reads the result as clean, because no verdict measures where a block faces against its target.
But a router that lingers among the ranks keeps the block's front off it, and the block lands fewer blows; the measurements are on #1793.

- **Do:** when a change holds a facing or a grid, measure what it costs in combat (strikers in reach, casualties dealt), and record any cost you accept on a tracking issue.

- **Don't:** read "no new defects" as "no behaviour change" for a change that alters facing.

(`Lacaedemon/sparta` PR #1790 and issue #1793, 2026-10-10.)

## Do not move a demo's staging to where the fix looks clean

After a review found PR #1784's (#1748) demo still shed its front rank against the hill, the next round moved the hill further from the block.
The re-staged clip passed, but the close start the review had measured was still unsolved.
The merged PR keeps the re-staged demo, adds a unit test that pins the close-start case's improvement over main, says in the caption how far the block starts from the hill, and tracks the rest in #1787.

- **Do:** keep the case the review found as a test or an expect, and caption the clip with the staging it actually uses.

- **Don't:** answer a review finding by changing the staging until the verdict passes; that is the sample-tick anti-pattern in another form.

(`Lacaedemon/sparta` PR #1784 and issue #1787, 2026-10-10.)

## Measure a relayed "main does this too" before filing it as pre-existing

Twice in wave 8 an implementer's out-of-scope note said main had the same defect, and the coordinator filed it as pre-existing.
Both times a later review showed the defect came mostly from the PR's own change: #1783 (an idle squadron's drift after a widen) and #1791 (a showcase block's re-square, which PR #1790's first version caused).
Both issues were corrected in comments.

- **Do:** file a relayed out-of-scope defect only after the reviewer, or a dump of the base tree, has measured it on main, and mark it as relayed until then.

- **Don't:** file an implementer's "also on main" as fact; it is the claim most likely to hide the implementer's own regression.

(`Lacaedemon/sparta` issues #1783 and #1791, 2026-10-10.)

## Wave hygiene: scratch directories, cheap checks, and cancelled runs

Three process misses from wave 8:

- Two concurrent agents shared the session scratchpad, and one agent's catalog run deleted the other's merge-base transcripts because they used the same file names.

- Two review rounds on PR #1776 read a docs rewording without running `tools/check.sh markdown`; the lines missing semantic breaks surfaced only on a later doc-only fix.

- On PR #1778, cancelled `demo`, `benchmark` and `demo-diff` runs were described as leftovers from an earlier push, but they were duplicates on the same head, started by marking the PR ready right after the push.

- **Do:** name a separate scratch subdirectory for each concurrent agent in its brief, and forbid deletes outside it.

- **Do:** have both the implementer and the reviewer run `tools/check.sh chars comments markdown units file_length` (seconds) at every handback, and check `.qmd` line breaks by hand while #1773 is open.

- **Do:** read `commits/<sha>/check-runs` for the head before explaining a cancelled or failing row, and gate any clean claim on `check-pr-fully-clean.py`.

- **Don't:** leave prose-format checks to the full suite, where a failure costs a full re-run (about 45 minutes on the wave machine).

(`Lacaedemon/sparta` PRs #1776, #1778 and #1790, 2026-10-10.)
