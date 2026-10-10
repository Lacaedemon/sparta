## A cache-invalidation sweep must also cover the paths that grow the block

Part 21 says that moving state into a cache inherits every invalidation of that cache.
PR #1778 (#1768) adds the other direction.
Its first version made every resized row-major block hold a dealt `_sim_soldier_row_slot` pairing,
but re-dealt only when the pairing was longer than the block (a casualty).
An `absorb()` at an unchanged file count left the pairing shorter than the block,
so `formation_slots` dropped the block to the identity layout.

- **Do:** list the size-changing paths in both directions (casualty, `reap`, `absorb` or merge, reinforcement), trigger on any size mismatch, and test the growing case.

- **Don't:** assume a path behaves as on main once the fix has changed what state that path finds.

(`Lacaedemon/sparta` PR #1778, 2026-10-10.)

## A crossing threshold can hide a man who really crosses

A crossing test in PR #1778's first version counted a man as crossing only when he and his new slot each stood more than half a file pitch off the centreline.
Two rear-rank men walked 36 wu across the block, and the half-pitch threshold excluded them,
so the test read zero crossings.
The fix dropped the margin and added a bound on each man's lateral travel.

- **Do:** bound each man's travel as well as counting threshold crossings, and name the men any threshold excludes.

- **Don't:** accept a threshold just because the branch reads zero under it.

(`Lacaedemon/sparta` PR #1778, 2026-10-10.)

## A skip keyed on a phase predicate covers every block in that phase

PR #1776's (#1774) first version skipped `SoldierBodies.couple()` whenever `is_order_turning()` was true.
The skip also froze blocks with full ranks, which have no phantom drift to suppress,
so a shove during their turn was no longer followed.
The skip also covered the order-response delay, because `turn_target` is armed when the order is issued.
The merged fix measures drift against the slots as they stood when the turn began, instead of skipping.

- **Do:** gate a sim change on the defect's own precondition, and probe both a block without that precondition and the window before the visible phase starts.

- **Don't:** key a fix on a phase predicate just because the defect only shows in that phase.

(`Lacaedemon/sparta` PR #1776, 2026-10-10.)

## A getter that gains a side effect is a hidden ordering dependency

PR #1778 made `soldier_world_slots()` re-deal a row-major pairing on the first query after a reshape.
PR #1776's `reform_ranks` read the slots before arming the about-face mirror,
so once #1778 merged, that read dealt the pairing in the wrong frame.
A review of the merge commit's meaning, not its text, found it.
The same review found the square branch already dealt before the mirror on main.
The fix skips the early read whenever `Unit._slot_deal_pending` (a side-effect-free predicate) is true.

- **Do:** when a getter gains a side effect, grep every caller in open sibling branches, and review the merge commit for meaning, not only for conflicts.

- **Do:** guard a capture that must not mutate state with a side-effect-free predicate such as `_slot_deal_pending`.

- **Don't:** treat a conflict-free merge as evidence that two sim changes compose.

(`Lacaedemon/sparta` PRs #1776 and #1778, 2026-10-10.)

## A facing hold can cost combat that no defect verdict reports

PR #1790 (#1757) holds a fighting block's facing while a router is inside it,
so the slot grid does not swing after the router.
In the `charge` clip a router lingers inside an archer block,
whose front then stays off it.
The router keeps 8 men at ticks 1460 and 1500, against 6 on main.
Three ways of bounding the hold each broke another clip's formation, so the hold was kept and the cost recorded on #1793.

- **Do:** when a change holds a facing or a grid, measure what it costs in combat (for example, the casualties the enemy takes), and record any cost you accept on a tracking issue.

- **Don't:** take a clean defect delta as evidence that combat outcomes did not change.

(`Lacaedemon/sparta` PR #1790 and issue #1793, 2026-10-10.)

## Do not move a demo's staging to where the fix looks clean

After a review found that PR #1784's (#1748) demo still shed its front rank against the hill,
the next round moved the hill further from the block.
The merged PR keeps the re-staged demo but adds a unit test that pins the close-start case's improvement over main,
says in the caption how far the block starts from the hill, and tracks the rest in #1787.
Part 20's rule against choosing sample ticks by their verdict applies to staging too.

- **Do:** keep the case a review found as a test or an expect, and caption the clip with the staging it actually uses.

- **Don't:** answer a review finding by changing the staging until the verdict passes.

(`Lacaedemon/sparta` PR #1784 and issue #1787, 2026-10-10.)

## Measure a relayed "main does this too" before filing it as pre-existing

Twice in wave 8 an implementer's note said main had the same defect, and it was filed as pre-existing.
Both times a later review showed the headline figures came from the PR's own change,
and a smaller residual remained on main.
#1783 was narrowed to a 10-15 wu drift on main after the 53 wu creep turned out to be PR #1778's own regression.
#1791's first figures came from PR #1790's superseded first version.
Its later comment gives main's own figures.

- **Do:** file a relayed out-of-scope defect only after the reviewer, or a dump of the base tree, has measured it on main, and mark the figures as relayed until then.

- **Don't:** file an implementer's "also on main" as measured fact,
  because it is the claim most likely to hide the implementer's own regression.

(`Lacaedemon/sparta` issues #1783 and #1791, 2026-10-10.)

## Run the cheap `tools/check.sh` targets on every handback

Two review rounds on PR #1776 read a docs rewording without running `tools/check.sh markdown`,
and the lines missing semantic breaks surfaced only on a later doc-only fix.
The markdown checks examine only committed lines, so a run before `git commit` passes vacuously,
and the semantic-line-break check skips `.qmd` files (#1773).
On PR #1778, cancelled `demo`, `benchmark` and `demo-diff` runs sat beside successful reruns on the same head,
and were at first misread as leftovers from an earlier push.

- **Do:** have both the implementer and the reviewer run `tools/check.sh chars comments markdown units file_length` on the committed head at every handback,
  as a supplement to the full target list in part 20, and check `.qmd` line breaks by hand while #1773 is open.

- **Do:** read `commits/<sha>/check-runs` for the head before explaining a cancelled or failing row, and gate any clean claim on `check-pr-fully-clean.py` (see part 08).

- **Don't:** leave prose-format checks to the full suite, where a failure costs a full re-run.

(`Lacaedemon/sparta` PRs #1776 and #1778, 2026-10-10.)
