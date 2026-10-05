## A per-body hard terrain constraint: only the narrowest rule survived the demo diff

PR #1703 (issue #1670) added a hard per-body terrain constraint.
Four rules were tried in turn.
The website demo diff rejected the first, and local scans of the clips it flagged rejected the next two.

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

## Dense defect scans use CI's own 2-tick spacing

`tools/ci/website-demo-defect-delta.sh` re-dumps each changed clip every `DEMO_DEFECT_DENSE_STEP` ticks (default 2) from the tick where it diverges.
On the re-staged `trapped_routing` clip a 4-tick local scan read `facing_whipsaw` 0.
CI's 2-tick re-dump read 11 against a threshold of 4, and a local 2-tick re-dump read 10.
The pursuer's facing snapped between about 12 and 112 degrees, some snaps only 2 ticks apart (t178-282), so 4-tick sampling stepped over every one.

- **Do:** dense-scan at 2-tick spacing before choosing a staging or calling a clip whipsaw-free.

- **Don't:** treat a clean 4-tick scan as evidence about facing metrics.

(`Lacaedemon/sparta` PR #1724, 2026-10-05.)

## Check soldier extents, not centre distance, before staging a clash

Two cavalry blocks that overlap at spawn leave the pursuer reading `engaged: true` with `in_enemy_contact: false` while its centre is 100+ wu away.
Its facing then flickers as it backs off and re-charges.
Default Cavalry block geometry, as slot-centre spans reported in that PR (not re-measured here): 60 mounts is 8 files at a 40 wu file pitch by 8 ranks at 120 wu, so 280 x 840 wu.
80 mounts is 320 x 960.
A block facing east lays its 840 wu depth along x, so a pursuer that "moved away" eastward-facing can still overlap.

- **Do:** check every unit's full soldier extent (min/max of `soldiers_full.pos` at tick 1-4) for overlap before staging a clash.

- **Don't:** judge separation from centre distance.

(`Lacaedemon/sparta` PR #1724, 2026-10-05.)

## The default hill's east corridor is 200 wu wide

The hill is `Rect2(1150, 380, 250, 200)` (kind `block`) and `FIELD` is 1600 wide, so the corridor from the hill's east face (x 1400) to the field edge (x 1600) is 200 wu.
A 60-mount cavalry block (280 wu wide) cannot stand there without men in the hill, so that staging used a 16-mount, `frontage: 4` scout (120 wu wide).

- **Do:** size a unit for the corridor it must stand in, using a small block with an explicit `frontage`.

- **Don't:** stage a default-geometry block beside block terrain and assume it fits.

(`Lacaedemon/sparta` PR #1724, 2026-10-05.)

## Pin `soldiers_in_block_terrain = 0` in stagings near block terrain

`soldiers_in_block_terrain` is both a dump field (`tools/demo/DemoState.gd`) and an `expect` field (`demos/README.md`).
Prove the pin bites by restoring the old spawn: the PR's pins failed with 6 and 19 men in the hill.

- **Do:** add the pin to any staging that sits near block terrain, then run it against the old spawn to see it fail.

- **Don't:** ship a pin that has never been seen to fail.

(`Lacaedemon/sparta` PRs #1724 and #1726, 2026-10-05.)

## A gate test must reach the gate, not a stage that sets the same flag first

The terrain backstop's render-flag gate was first tested by driving a body hard into the hill through `SoldierBodies.step`.
That test passed with the gate reverted, because the integration earlier in `step` raises `_render_dirty` itself for any body above `REST_SPEED`, so the backstop's own flag was never what the assertion read.
The fix was to call `SoldierBodies._keep_out_of_terrain` directly with a body at rest, once with a visible push and once with a 0.001 wu creep.

- **Do:** when two stages can set the same flag, call the stage under test directly, and revert the gate to watch the test fail.

- **Don't:** trust an end-to-end test of a gate whose observable an earlier stage also writes.

(`Lacaedemon/sparta` PR #1726, 2026-10-05.)

## A quarter fold's index-order re-square reads as clean shape, and its fix reads worse

Dropping a +/-PI/2 fold to 0 with soldier i kept on cell i is, to `kabsch_fit`, a rigid quarter-turn of the whole block, so `shape_residual` reads it low while men walk across the block.
In a unit test 22 of 60 slots lay across the centreline, and on the #1701 demo 23 of 60 men crossed it.
Re-pairing each man to his nearest new cell is a genuine reshape, so the same metric reads higher at first (49.5 against 45.6 at 2-tick spacing) while settling faster (mean distance to slot at tick 300: 21 wu against 49).
On main the clip's sparse own ticks failed the metric (43.8), so it carried an exemption.
With the re-pairing and ticks across the reform window it passes on the converging rule, with no exemption.

- **Do:** judge a re-slot by per-index crossings and travel (de-rotate both ticks into the settled frame and count lateral sign flips), and sample the reform window in the clip's own `state` ticks so the scan judges it rather than skips it.

- **Don't:** read a lower `shape_residual` across a fold change as a better route, or keep an exemption that only a sparse tick list makes look stale.

(`Lacaedemon/sparta` PR #1727, 2026-10-05.)
