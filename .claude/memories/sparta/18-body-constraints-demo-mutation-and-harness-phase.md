## A per-body hard terrain constraint: only the narrowest rule survived the demo diff

PR #1703 (issue #1670) added a hard per-body terrain constraint.
Three plausible rules were tried, and the website demo diff rejected the first three.

- (a) Eject every body inside block terrain (grown by the body radius) to the nearest edge.
  Clips whose scenarios spawn blocks overlapping the hill (cannae_scale, trapped_routing, fog_terrain_occlusion, funnel_lanes) broke.
  Bodies that differed only along the ejection axis were stacked onto one point (overlap verdict worst=0).
  Units were shifted off pinned positions.
- (b) "No new entry": exempt any body inside the GROWN rect at tick start.
  A rear rank spawned within a body radius of the hill counted as already inside, so a charge shoved it in.
  The PR's own demo had 4 men inside the hill at tick 600.
- (c) "Never deeper": an inside body may not end a tick deeper than it began.
  It held units a scenario spawned inside the hill, which changed two published clips' stories (fog_terrain_occlusion's scout reveal, trapped_routing's rout).

The final rule exempts only bodies inside the DRAWN rect at tick start.
Everything else, including the radius margin, is held at the margin edge.
Two clips that rely on pass-through are tracked for re-staging in #1706.
Spawn placement inside terrain is tracked in #1705.

- **Do:** scan every website clip whose units touch the default hill (`dump-state.sh` plus `analyze_transcript.gd --script`) before pushing a body-pass change, and read the website demo diff's whole defect-delta table.

- **Don't:** pick a per-body terrain rule from unit tests alone, because the failures only showed on scenario spawns.

## A demo must be mutation-run too

In PR #1701 (issue #1675) the first demo for a quarter-fold order fix produced an identical clip with the fix reverted.
A scenario unit defaults to `reform_before_move=true`, and the reform-hold path was already correct on main.
Setting `"reform_before_move": false` in the scenario spec (`Battle.gd` reads it) exercised the fixed path.
On main the order then kept its x 1300 target, and 4 then 6 men ended on the hill at ticks 1000 and 1200.
So the demo's expect pins bite.

- **Do:** run the demo with the fix reverted (swap in origin/main's script files) and confirm an expect pin fails.

- **Don't:** trust a demo that "shows the fix" without that run.

## A same-seed determinism test must spawn each run at the same frame phase

In PR #1703, `test_tier_transition_battle` spawned its first battle from the test's idle start.
It spawned its second right after a `physics_frame` await.
So only the first battle got a close-tier soldier tick before the first tier pass.
That was harmless until a pass changed bodies on that tick.
Then run 0 differed while runs 1 and 2 matched exactly.
The fix was `await get_tree().physics_frame` before each spawn.

- **Do:** when a determinism test fails, run it three times in one process and compare run 0 with runs 1 and 2 before suspecting sim nondeterminism.

- **Don't:** read a run-0-only divergence as an RNG or ordering bug.

## Respond to a fresh order before writing move_target

In PR #1701, `start_order_response()` re-squares a quarter-folded block.
Every writer that responds to a fresh order must call it BEFORE writing `move_target`.
Those writers are Battle's plain march and nudge, `Unit.disengage`, and `disengage_with_sacrifice`.
Otherwise the footprint is validated in the folded grid, and the block marches squared into terrain.

- **Do:** respond before the `move_target` write in any new fresh-order writer.

- **Don't:** add a writer that writes `move_target` and responds afterwards.
